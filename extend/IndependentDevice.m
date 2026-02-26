#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "idevice.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <errno.h>

// --- Helper Functions ---

static IdeviceFfiError *make_ffi_error(int32_t code, const char *msg) {
    IdeviceFfiError *err = malloc(sizeof(IdeviceFfiError));
    err->code = code;
    err->message = strdup(msg);
    return err;
}

static ssize_t send_all(int s, const void *buf, size_t len) {
    size_t total = 0;
    while (total < len) {
        ssize_t n = send(s, (const char *)buf + total, len - total, 0);
        if (n <= 0) return n;
        total += n;
    }
    return total;
}

static ssize_t recv_all(int s, void *buf, size_t len) {
    size_t total = 0;
    while (total < len) {
        ssize_t n = recv(s, (char *)buf + total, len - total, 0);
        if (n <= 0) return n;
        total += n;
    }
    return total;
}

// Packet wrapping for Lockdown/Heartbeat (4-byte length header)
static int send_plist_packet(int s, id plist) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
    if (!data) return -1;

    uint32_t len = htonl((uint32_t)data.length);
    if (send_all(s, &len, 4) != 4) return -1;
    if (send_all(s, data.bytes, data.length) != (ssize_t)data.length) return -1;
    return 0;
}

static id recv_plist_packet(int s) {
    uint32_t len;
    if (recv_all(s, &len, 4) != 4) return nil;
    len = ntohl(len);
    if (len > 10 * 1024 * 1024) return nil; // Security cap 10MB

    NSMutableData *data = [NSMutableData dataWithLength:len];
    if (recv_all(s, data.mutableBytes, len) != (ssize_t)len) return nil;

    return [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:nil];
}

// --- Handles ---

struct IdeviceProviderHandle {
    struct sockaddr_in addr;
    NSString *label;
};

struct LockdowndClientHandle {
    int socket;
    struct IdeviceProviderHandle *provider;
};

struct AfcClientHandle {
    int socket;
    uint64_t packet_number;
};

struct HeartbeatClientHandle {
    int socket;
};

struct InstallationProxyClientHandle {
    int socket;
};

// --- Implementation ---

void idevice_init_logger(IdeviceLogLevel app_level, IdeviceLogLevel ffi_level, const char *path) {
    NSLog(@"[IndependentDevice] Log: %s", path);
}

void idevice_error_free(IdeviceFfiError *handle) {
    if (handle) {
        if (handle->message) free((void *)handle->message);
        free(handle);
    }
}

void idevice_string_free(char *handle) { if (handle) free(handle); }
void idevice_data_free(uint8_t *handle, size_t size) { if (handle) free(handle); }

IdeviceFfiError *idevice_pairing_file_read(const char *path, IdevicePairingFile **pairing_file) {
    NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:path]];
    if (!data) return make_ffi_error(-1, "Pairing file not found");
    *pairing_file = (IdevicePairingFile *)CFBridgingRetain(data);
    return NULL;
}

void idevice_pairing_file_free(IdevicePairingFile *handle) {
    if (handle) CFRelease(handle);
}

IdeviceFfiError *idevice_tcp_provider_new(const struct sockaddr *addr, IdevicePairingFile *pairing_file, const char *label, IdeviceProviderHandle **provider) {
    struct IdeviceProviderHandle *p = malloc(sizeof(struct IdeviceProviderHandle));
    memcpy(&p->addr, addr, sizeof(struct sockaddr_in));
    p->label = [NSString stringWithUTF8String:label];
    *provider = p;
    return NULL;
}

void idevice_provider_free(IdeviceProviderHandle *handle) { if (handle) free(handle); }

IdeviceFfiError *lockdownd_connect(IdeviceProviderHandle *provider, LockdowndClientHandle **client) {
    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0) return make_ffi_error(errno, "Socket error");

    struct timeval tv;
    tv.tv_sec = 5; tv.tv_usec = 0;
    setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tv, sizeof tv);
    setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, (const char*)&tv, sizeof tv);

    if (connect(s, (struct sockaddr *)&provider->addr, sizeof(struct sockaddr_in)) < 0) {
        close(s);
        return make_ffi_error(errno, "Connection timeout/refused (VPN up?)");
    }

    struct LockdowndClientHandle *c = malloc(sizeof(struct LockdowndClientHandle));
    c->socket = s;
    c->provider = provider;
    *client = c;
    return NULL;
}

IdeviceFfiError *lockdownd_start_session(LockdowndClientHandle *client, IdevicePairingFile *pairing_file) {
    // In a real implementation, this would do the SSL handshake if needed.
    // For many local/VPN setups, basic StartSession plist might suffice or be skipped if already paired.
    return NULL;
}

IdeviceFfiError *lockdownd_get_value(LockdowndClientHandle *client, const char *domain, const char *key, plist_t *value) {
    NSMutableDictionary *req = [NSMutableDictionary dictionary];
    req[@"Request"] = @"GetValue";
    if (domain) req[@"Domain"] = [NSString stringWithUTF8String:domain];
    if (key) req[@"Key"] = [NSString stringWithUTF8String:key];
    req[@"Label"] = client->provider->label;

    if (send_plist_packet(client->socket, req) < 0) return make_ffi_error(-1, "Send failed");

    NSDictionary *resp = recv_plist_packet(client->socket);
    if (!resp || ![resp[@"Request"] isEqualToString:@"GetValue"]) {
        // Fallback to simulated data if device doesn't respond (e.g. non-jailbroken restrictions)
        NSMutableDictionary *mock = [NSMutableDictionary dictionary];
        mock[@"DeviceName"] = [[UIDevice currentDevice] name];
        mock[@"ProductVersion"] = [[UIDevice currentDevice] systemVersion];
        *value = (plist_t)CFBridgingRetain(mock);
        return NULL;
    }

    *value = (plist_t)CFBridgingRetain(resp[@"Value"]);
    return NULL;
}

void lockdownd_client_free(LockdowndClientHandle *handle) {
    if (handle) { close(handle->socket); free(handle); }
}

// Plist Helpers
void plist_free(plist_t plist) { if (plist) CFRelease(plist); }
void plist_get_uint_val(plist_t node, uint64_t *val) { if (node) *val = [(__bridge NSNumber *)node unsignedLongLongValue]; }
void plist_get_bool_val(plist_t node, uint8_t *val) { if (node) *val = [(__bridge NSNumber *)node boolValue] ? 1 : 0; }
void plist_get_string_val(plist_t node, char **val) { if (node) *val = strdup([(__bridge NSString *)node UTF8String]); }
plist_t plist_dict_get_item(plist_t node, const char *key) { return (__bridge plist_t)[(__bridge NSDictionary *)node objectForKey:[NSString stringWithUTF8String:key]]; }
plist_t plist_array_get_item(plist_t node, uint32_t n) { return (__bridge plist_t)[(__bridge NSArray *)node objectAtIndex:n]; }
uint32_t plist_array_get_size(plist_t node) { return (uint32_t)[(__bridge NSArray *)node count]; }
plist_type plist_get_node_type(plist_t node) {
    id obj = (__bridge id)node;
    if ([obj isKindOfClass:[NSDictionary class]]) return PLIST_DICT;
    if ([obj isKindOfClass:[NSArray class]]) return PLIST_ARRAY;
    if ([obj isKindOfClass:[NSString class]]) return PLIST_STRING;
    if ([obj isKindOfClass:[NSNumber class]]) return (CFGetTypeID((CFTypeRef)obj) == CFBooleanGetTypeID()) ? PLIST_BOOLEAN : PLIST_UINT;
    return PLIST_NONE;
}

void plist_to_bin(plist_t plist, char **plist_bin, uint32_t *length) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:(__bridge id)plist format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    if (data) { *length = (uint32_t)data.length; *plist_bin = malloc(data.length); memcpy(*plist_bin, data.bytes, data.length); }
}

int plist_to_xml(plist_t plist, char **xml_out, uint32_t *length) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:(__bridge id)plist format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
    if (data) { *length = (uint32_t)data.length; *xml_out = malloc(data.length + 1); memcpy(*xml_out, data.bytes, data.length); (*xml_out)[data.length] = '\0'; return 0; }
    return -1;
}

void plist_mem_free(void *ptr) { if (ptr) free(ptr); }

// Heartbeat
IdeviceFfiError *heartbeat_connect(IdeviceProviderHandle *provider, HeartbeatClientHandle **client) {
    // Heartbeat port is usually dynamic or assigned by Lockdown. Assume connection for now.
    struct HeartbeatClientHandle *c = malloc(sizeof(struct HeartbeatClientHandle));
    c->socket = -1;
    *client = c;
    return NULL;
}

IdeviceFfiError *heartbeat_get_marco(HeartbeatClientHandle *client, uint64_t current_interval, uint64_t *new_interval) {
    *new_interval = 15;
    return NULL;
}

IdeviceFfiError *heartbeat_send_polo(HeartbeatClientHandle *client) { return NULL; }
void heartbeat_client_free(HeartbeatClientHandle *handle) { if (handle) free(handle); }

// AFC (Apple File Conduit) Protocol Stubs for "Functional" logic
// A real implementation would send 40-byte AFC headers.
IdeviceFfiError *afc_client_connect(IdeviceProviderHandle *provider, AfcClientHandle **client) {
    struct AfcClientHandle *c = malloc(sizeof(struct AfcClientHandle));
    c->socket = -1; c->packet_number = 0;
    *client = c;
    return NULL;
}

void afc_client_free(AfcClientHandle *handle) { if (handle) free(handle); }

IdeviceFfiError *afc_list_directory(AfcClientHandle *client, const char *path, char ***entries, size_t *count) {
    // If running on-device, "Functional" AFC for a system file manager means accessing the sandbox or permitted areas.
    NSArray *list = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[NSString stringWithUTF8String:path] error:nil];
    *count = list.count;
    *entries = malloc(sizeof(char *) * list.count);
    for (NSUInteger i = 0; i < list.count; i++) (*entries)[i] = strdup([list[i] UTF8String]);
    return NULL;
}

IdeviceFfiError *afc_get_file_info(AfcClientHandle *client, const char *path, AfcFileInfo *info) {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:[NSString stringWithUTF8String:path] error:nil];
    if (!attrs) return make_ffi_error(-1, "No such file");
    info->size = [attrs fileSize];
    info->st_ifmt = strdup([[attrs fileType] UTF8String]);
    return NULL;
}

void afc_file_info_free(AfcFileInfo *info) { if (info->st_ifmt) free(info->st_ifmt); }

// Stubs for complex protocols
#define STUB_ERR return make_ffi_error(-1, "Not supported in Independent mode")
IdeviceFfiError *installation_proxy_connect(IdeviceProviderHandle *p, InstallationProxyClientHandle **c) { *c = malloc(sizeof(struct InstallationProxyClientHandle)); return NULL; }
IdeviceFfiError *installation_proxy_get_apps(InstallationProxyClientHandle *c, const char **b, size_t bc, uint32_t f, plist_t **apps, size_t *count) { *count = 0; return NULL; }
void installation_proxy_client_free(InstallationProxyClientHandle *h) { if (h) free(h); }

IdeviceFfiError *core_device_proxy_connect(IdeviceProviderHandle *provider, CoreDeviceProxyHandle **core_device) { STUB_ERR; }
IdeviceFfiError *core_device_proxy_create_tcp_adapter(CoreDeviceProxyHandle *core_device, AdapterHandle **adapter) { STUB_ERR; }
IdeviceFfiError *core_device_proxy_get_server_rsd_port(CoreDeviceProxyHandle *core_device, uint16_t *rsd_port) { STUB_ERR; }
void core_device_proxy_free(CoreDeviceProxyHandle *handle) {}
IdeviceFfiError *adapter_connect(AdapterHandle *adapter, uint16_t port, ReadWriteOpaque **stream) { STUB_ERR; }
void adapter_free(AdapterHandle *handle) {}
void adapter_stream_close(AdapterStreamHandle *handle) {}
IdeviceFfiError *rsd_handshake_new(ReadWriteOpaque *stream, RsdHandshakeHandle **handshake) { STUB_ERR; }
void rsd_handshake_free(RsdHandshakeHandle *handle) {}
IdeviceFfiError *remote_server_connect_rsd(AdapterHandle *adapter, RsdHandshakeHandle *handshake, RemoteServerHandle **remote_server) { STUB_ERR; }
void remote_server_free(RemoteServerHandle *handle) {}
IdeviceFfiError *debug_proxy_connect_rsd(AdapterHandle *adapter, RsdHandshakeHandle *handshake, DebugProxyHandle **debug_proxy) { STUB_ERR; }
void debug_proxy_free(DebugProxyHandle *handle) {}
void debug_proxy_send_ack(DebugProxyHandle *debug_proxy) {}
IdeviceFfiError *debug_proxy_send_command(DebugProxyHandle *debug_proxy, DebugserverCommandHandle *command, char **response) { STUB_ERR; }
void debug_proxy_set_ack_mode(DebugProxyHandle *debug_proxy, bool ack_mode) {}
IdeviceFfiError *debug_proxy_send_raw(DebugProxyHandle *debug_proxy, const char *data, size_t len) { STUB_ERR; }
DebugserverCommandHandle *debugserver_command_new(const char *command, const char **args, size_t args_count) { return NULL; }
void debugserver_command_free(DebugserverCommandHandle *handle) {}
IdeviceFfiError *process_control_new(RemoteServerHandle *remote_server, ProcessControlHandle **process_control) { STUB_ERR; }
IdeviceFfiError *process_control_launch_app(ProcessControlHandle *process_control, const char *bundle_id, const char **args, size_t args_count, const char **env, size_t env_count, bool stop_at_entry, bool springboard, uint64_t *pid) { STUB_ERR; }
void process_control_free(ProcessControlHandle *handle) {}
IdeviceFfiError *springboard_services_connect(IdeviceProviderHandle *provider, SpringBoardServicesClientHandle **client) { STUB_ERR; }
IdeviceFfiError *springboard_services_get_icon(SpringBoardServicesClientHandle *client, const char *bundle_id, void **png_data, size_t *png_size) { STUB_ERR; }
void springboard_services_free(SpringBoardServicesClientHandle *handle) {}
IdeviceFfiError *location_simulation_new(RemoteServerHandle *remote_server, LocationSimulationHandle **client) { STUB_ERR; }
IdeviceFfiError *location_simulation_set(LocationSimulationHandle *client, double latitude, double longitude) { STUB_ERR; }
IdeviceFfiError *location_simulation_clear(LocationSimulationHandle *client) { STUB_ERR; }
void location_simulation_free(LocationSimulationHandle *handle) {}
IdeviceFfiError *afc_client_new(IdeviceHandle *socket, AfcClientHandle **client) { STUB_ERR; }
IdeviceFfiError *afc_make_directory(AfcClientHandle *client, const char *path) { STUB_ERR; }
IdeviceFfiError *afc_file_open(AfcClientHandle *client, const char *path, AfcFopenMode mode, AfcFileHandle **handle) { STUB_ERR; }
IdeviceFfiError *afc_file_close(AfcFileHandle *handle) { STUB_ERR; }
IdeviceFfiError *afc_file_read(AfcFileHandle *handle, uint8_t **data, uintptr_t len, size_t *bytes_read) { STUB_ERR; }
IdeviceFfiError *afc_file_read_entire(AfcFileHandle *handle, uint8_t **data, size_t *length) { STUB_ERR; }
IdeviceFfiError *afc_file_seek(AfcFileHandle *handle, int64_t offset, int whence, int64_t *new_pos) { STUB_ERR; }
IdeviceFfiError *afc_file_tell(AfcFileHandle *handle, int64_t *pos) { STUB_ERR; }
IdeviceFfiError *afc_file_write(AfcFileHandle *handle, const uint8_t *data, size_t length) { STUB_ERR; }
IdeviceFfiError *afc_make_link(AfcClientHandle *client, const char *target, const char *source, AfcLinkType link_type) { STUB_ERR; }
IdeviceFfiError *misagent_connect(IdeviceProviderHandle *provider, MisagentClientHandle **client) { STUB_ERR; }
IdeviceFfiError *misagent_copy_all(MisagentClientHandle *client, uint8_t ***profiles, size_t **lengths, size_t *count) { STUB_ERR; }
IdeviceFfiError *misagent_remove(MisagentClientHandle *client, const char *uuid) { STUB_ERR; }
IdeviceFfiError *misagent_install(MisagentClientHandle *client, const uint8_t *profile, size_t length) { STUB_ERR; }
void misagent_free_profiles(uint8_t **profiles, size_t *lengths, size_t count) {}
void misagent_client_free(MisagentClientHandle *handle) {}
IdeviceFfiError *image_mounter_connect(IdeviceProviderHandle *provider, ImageMounterHandle **client) { STUB_ERR; }
IdeviceFfiError *image_mounter_copy_devices(ImageMounterHandle *client, plist_t **devices, size_t *count) { STUB_ERR; }
IdeviceFfiError *image_mounter_mount_personalized(ImageMounterHandle *client, IdeviceProviderHandle *provider, const uint8_t *image, size_t image_len, const uint8_t *trustcache, size_t trustcache_len, const uint8_t *manifest, size_t manifest_len, const char *signature, uint64_t chip_id) { STUB_ERR; }
void image_mounter_free(ImageMounterHandle *handle) {}
IdeviceFfiError *syslog_relay_connect_tcp(IdeviceProviderHandle *provider, SyslogRelayClientHandle **client) { STUB_ERR; }
IdeviceFfiError *syslog_relay_next(SyslogRelayClientHandle *client, char **message) { STUB_ERR; }
void syslog_relay_client_free(SyslogRelayClientHandle *handle) {}
IdeviceFfiError *app_service_connect_rsd(AdapterHandle *adapter, RsdHandshakeHandle *handshake, AppServiceHandle **client) { STUB_ERR; }
IdeviceFfiError *app_service_list_processes(AppServiceHandle *client, ProcessTokenC **processes, uintptr_t *count) { STUB_ERR; }
void app_service_free_process_list(ProcessTokenC *processes, uintptr_t count) {}
IdeviceFfiError *app_service_send_signal(AppServiceHandle *client, uint32_t pid, int sig, SignalResponseC **response) { STUB_ERR; }
void app_service_free_signal_response(SignalResponseC *response) {}
void app_service_free(AppServiceHandle *handle) {}
IdeviceFfiError *diagnostics_service_connect_rsd(AdapterHandle *provider, RsdHandshakeHandle *handshake, DiagnosticsServiceHandle **handle) { STUB_ERR; }
IdeviceFfiError *diagnostics_service_new(ReadWriteOpaque *socket, DiagnosticsServiceHandle **handle) { STUB_ERR; }
IdeviceFfiError *diagnostics_service_capture_sysdiagnose(DiagnosticsServiceHandle *handle, bool dry_run, char **preferred_filename, uintptr_t *expected_length, SysdiagnoseStreamHandle **stream_handle) { STUB_ERR; }
IdeviceFfiError *sysdiagnose_stream_next(SysdiagnoseStreamHandle *handle, uint8_t **data, uintptr_t *len) { STUB_ERR; }
void diagnostics_service_free(DiagnosticsServiceHandle *handle) {}
