#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "idevice.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <errno.h>

// Internal structures to match Opaque types in idevice.h
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
    NSString *rootPath;
};

struct HeartbeatClientHandle {
    int socket;
};

struct InstallationProxyClientHandle {
    int socket;
};

// Helper to create error
static IdeviceFfiError *make_ffi_error(int32_t code, const char *msg) {
    IdeviceFfiError *err = malloc(sizeof(IdeviceFfiError));
    err->code = code;
    err->message = strdup(msg);
    return err;
}

// Basic
void idevice_init_logger(IdeviceLogLevel app_level, IdeviceLogLevel ffi_level, const char *path) {
    NSLog(@"[IndependentDevice] Logger initialized with path: %s", path);
}

void idevice_error_free(IdeviceFfiError *handle) {
    if (handle) {
        if (handle->message) free((void *)handle->message);
        free(handle);
    }
}

void idevice_string_free(char *handle) {
    if (handle) free(handle);
}

void idevice_data_free(uint8_t *handle, size_t size) {
    if (handle) free(handle);
}

// Pairing
IdeviceFfiError *idevice_pairing_file_read(const char *path, IdevicePairingFile **pairing_file) {
    NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:path]];
    if (!data) return make_ffi_error(-1, "Could not read pairing file");
    *pairing_file = (IdevicePairingFile *)data; // Use NSData as the opaque pointer
    return NULL;
}

void idevice_pairing_file_free(IdevicePairingFile *handle) {
    // NSData handled by ARC or manually if needed, but here we assume it's just a ref
}

// Provider
IdeviceFfiError *idevice_tcp_provider_new(const struct sockaddr *addr, IdevicePairingFile *pairing_file, const char *label, IdeviceProviderHandle **provider) {
    struct IdeviceProviderHandle *p = malloc(sizeof(struct IdeviceProviderHandle));
    memcpy(&p->addr, addr, sizeof(struct sockaddr_in));
    p->label = [NSString stringWithUTF8String:label];
    *provider = p;
    return NULL;
}

void idevice_provider_free(IdeviceProviderHandle *handle) {
    if (handle) free(handle);
}

// Lockdownd
IdeviceFfiError *lockdownd_connect(IdeviceProviderHandle *provider, LockdowndClientHandle **client) {
    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0) return make_ffi_error(errno, "Socket creation failed");

    if (connect(s, (struct sockaddr *)&provider->addr, sizeof(struct sockaddr_in)) < 0) {
        close(s);
        return make_ffi_error(errno, "Connect failed");
    }

    struct LockdowndClientHandle *c = malloc(sizeof(struct LockdowndClientHandle));
    c->socket = s;
    c->provider = provider;
    *client = c;
    return NULL;
}

IdeviceFfiError *lockdownd_start_session(LockdowndClientHandle *client, IdevicePairingFile *pairing_file) {
    // Simple implementation: assume session started
    return NULL;
}

IdeviceFfiError *lockdownd_get_value(LockdowndClientHandle *client, const char *domain, const char *key, plist_t *value) {
    // Mocking some values for device info
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"DeviceName"] = [[UIDevice currentDevice] name];
    dict[@"ProductType"] = [[UIDevice currentDevice] model];
    dict[@"ProductVersion"] = [[UIDevice currentDevice] systemVersion];
    dict[@"UniqueDeviceID"] = @"Independent-Simulated-ID";

    if (key) {
        *value = (__bridge_retained void *)dict[[NSString stringWithUTF8String:key]];
    } else {
        *value = (__bridge_retained void *)dict;
    }
    return NULL;
}

void lockdownd_client_free(LockdowndClientHandle *handle) {
    if (handle) {
        close(handle->socket);
        free(handle);
    }
}

// Plist
void plist_free(plist_t plist) {
    if (plist) CFRelease((CFTypeRef)plist);
}

void plist_get_uint_val(plist_t node, uint64_t *val) {
    if (node) *val = [(__bridge NSNumber *)node unsignedLongLongValue];
}

void plist_get_bool_val(plist_t node, uint8_t *val) {
    if (node) *val = [(__bridge NSNumber *)node boolValue] ? 1 : 0;
}

void plist_get_string_val(plist_t node, char **val) {
    if (node) *val = strdup([(__bridge NSString *)node UTF8String]);
}

plist_t plist_dict_get_item(plist_t node, const char *key) {
    return (__bridge plist_t)[(__bridge NSDictionary *)node objectForKey:[NSString stringWithUTF8String:key]];
}

plist_t plist_array_get_item(plist_t node, uint32_t n) {
    return (__bridge plist_t)[(__bridge NSArray *)node objectAtIndex:n];
}

uint32_t plist_array_get_size(plist_t node) {
    return (uint32_t)[(__bridge NSArray *)node count];
}

plist_type plist_get_node_type(plist_t node) {
    id obj = (__bridge id)node;
    if ([obj isKindOfClass:[NSDictionary class]]) return PLIST_DICT;
    if ([obj isKindOfClass:[NSArray class]]) return PLIST_ARRAY;
    if ([obj isKindOfClass:[NSString class]]) return PLIST_STRING;
    if ([obj isKindOfClass:[NSNumber class]]) {
        if (CFGetTypeID((CFTypeRef)obj) == CFBooleanGetTypeID()) return PLIST_BOOLEAN;
        return PLIST_UINT;
    }
    if ([obj isKindOfClass:[NSData class]]) return PLIST_DATA;
    if ([obj isKindOfClass:[NSDate class]]) return PLIST_DATE;
    return PLIST_NONE;
}

void plist_to_bin(plist_t plist, char **plist_bin, uint32_t *length) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:(__bridge id)plist format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    if (data) {
        *length = (uint32_t)data.length;
        *plist_bin = malloc(data.length);
        memcpy(*plist_bin, data.bytes, data.length);
    }
}

int plist_to_xml(plist_t plist, char **xml_out, uint32_t *length) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:(__bridge id)plist format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
    if (data) {
        *length = (uint32_t)data.length;
        *xml_out = malloc(data.length + 1);
        memcpy(*xml_out, data.bytes, data.length);
        (*xml_out)[data.length] = '\0';
        return 0;
    }
    return -1;
}

void plist_mem_free(void *ptr) {
    if (ptr) free(ptr);
}

// AFC
IdeviceFfiError *afc_client_connect(IdeviceProviderHandle *provider, AfcClientHandle **client) {
    struct AfcClientHandle *c = malloc(sizeof(struct AfcClientHandle));
    c->socket = -1; // Simulated
    c->rootPath = @"/";
    *client = c;
    return NULL;
}

void afc_client_free(AfcClientHandle *handle) {
    if (handle) free(handle);
}

IdeviceFfiError *afc_list_directory(AfcClientHandle *client, const char *path, char ***entries, size_t *count) {
    NSError *err = nil;
    NSArray *list = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[NSString stringWithUTF8String:path] error:&err];
    if (err) return make_ffi_error((int)err.code, [err.localizedDescription UTF8String]);

    *count = list.count;
    *entries = malloc(sizeof(char *) * list.count);
    for (NSUInteger i = 0; i < list.count; i++) {
        (*entries)[i] = strdup([list[i] UTF8String]);
    }
    return NULL;
}

IdeviceFfiError *afc_get_file_info(AfcClientHandle *client, const char *path, AfcFileInfo *info) {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:[NSString stringWithUTF8String:path] error:nil];
    if (!attrs) return make_ffi_error(-1, "File not found");

    info->size = [attrs fileSize];
    info->creation = [[attrs fileCreationDate] timeIntervalSince1970];
    info->modified = [[attrs fileModificationDate] timeIntervalSince1970];
    info->st_ifmt = strdup([[attrs fileType] UTF8String]);
    return NULL;
}

void afc_file_info_free(AfcFileInfo *info) {
    if (info->st_ifmt) free(info->st_ifmt);
}

// Installation Proxy
IdeviceFfiError *installation_proxy_connect(IdeviceProviderHandle *provider, InstallationProxyClientHandle **client) {
    struct InstallationProxyClientHandle *c = malloc(sizeof(struct InstallationProxyClientHandle));
    c->socket = -1;
    *client = c;
    return NULL;
}

IdeviceFfiError *installation_proxy_get_apps(InstallationProxyClientHandle *client, const char **bundle_ids, size_t bundle_ids_count, uint32_t flags, plist_t **apps, size_t *count) {
    // Since we are non-jailbroken, we can only see what the system allows.
    // We will return a simulated list for now or empty.
    *count = 0;
    *apps = NULL;
    return NULL;
}

void installation_proxy_client_free(InstallationProxyClientHandle *handle) {
    if (handle) free(handle);
}

// Heartbeat
IdeviceFfiError *heartbeat_connect(IdeviceProviderHandle *provider, HeartbeatClientHandle **client) {
    struct HeartbeatClientHandle *c = malloc(sizeof(struct HeartbeatClientHandle));
    c->socket = -1;
    *client = c;
    return NULL;
}

IdeviceFfiError *heartbeat_get_marco(HeartbeatClientHandle *client, uint64_t current_interval, uint64_t *new_interval) {
    *new_interval = 15;
    sleep(5); // Simulate wait
    return NULL;
}

IdeviceFfiError *heartbeat_send_polo(HeartbeatClientHandle *client) {
    return NULL;
}

void heartbeat_client_free(HeartbeatClientHandle *handle) {
    if (handle) free(handle);
}

// Stubs for the rest to avoid link errors
#define STUB_ERR return make_ffi_error(-1, "Not implemented in Independent mode")
#define STUB_VOID

IdeviceFfiError *core_device_proxy_connect(IdeviceProviderHandle *provider, CoreDeviceProxyHandle **core_device) { STUB_ERR; }
IdeviceFfiError *core_device_proxy_get_server_rsd_port(CoreDeviceProxyHandle *core_device, uint16_t *rsd_port) { STUB_ERR; }
IdeviceFfiError *core_device_proxy_create_tcp_adapter(CoreDeviceProxyHandle *core_device, AdapterHandle **adapter) { STUB_ERR; }
void core_device_proxy_free(CoreDeviceProxyHandle *handle) { STUB_VOID; }
IdeviceFfiError *adapter_connect(AdapterHandle *adapter, uint16_t port, ReadWriteOpaque **stream) { STUB_ERR; }
void adapter_free(AdapterHandle *handle) { STUB_VOID; }
void adapter_stream_close(AdapterStreamHandle *handle) { STUB_VOID; }
IdeviceFfiError *rsd_handshake_new(ReadWriteOpaque *stream, RsdHandshakeHandle **handshake) { STUB_ERR; }
void rsd_handshake_free(RsdHandshakeHandle *handle) { STUB_VOID; }
IdeviceFfiError *remote_server_connect_rsd(AdapterHandle *adapter, RsdHandshakeHandle *handshake, RemoteServerHandle **remote_server) { STUB_ERR; }
void remote_server_free(RemoteServerHandle *handle) { STUB_VOID; }
IdeviceFfiError *debug_proxy_connect_rsd(AdapterHandle *adapter, RsdHandshakeHandle *handshake, DebugProxyHandle **debug_proxy) { STUB_ERR; }
void debug_proxy_free(DebugProxyHandle *handle) { STUB_VOID; }
void debug_proxy_send_ack(DebugProxyHandle *debug_proxy) { STUB_VOID; }
IdeviceFfiError *debug_proxy_send_command(DebugProxyHandle *debug_proxy, DebugserverCommandHandle *command, char **response) { STUB_ERR; }
void debug_proxy_set_ack_mode(DebugProxyHandle *debug_proxy, bool ack_mode) { STUB_VOID; }
IdeviceFfiError *debug_proxy_send_raw(DebugProxyHandle *debug_proxy, const char *data, size_t len) { STUB_ERR; }
DebugserverCommandHandle *debugserver_command_new(const char *command, const char **args, size_t args_count) { return NULL; }
void debugserver_command_free(DebugserverCommandHandle *handle) { STUB_VOID; }
IdeviceFfiError *process_control_new(RemoteServerHandle *remote_server, ProcessControlHandle **process_control) { STUB_ERR; }
IdeviceFfiError *process_control_launch_app(ProcessControlHandle *process_control, const char *bundle_id, const char **args, size_t args_count, const char **env, size_t env_count, bool stop_at_entry, bool springboard, uint64_t *pid) { STUB_ERR; }
void process_control_free(ProcessControlHandle *handle) { STUB_VOID; }
IdeviceFfiError *misagent_connect(IdeviceProviderHandle *provider, MisagentClientHandle **client) { STUB_ERR; }
IdeviceFfiError *misagent_copy_all(MisagentClientHandle *client, uint8_t ***profiles, size_t **lengths, size_t *count) { STUB_ERR; }
IdeviceFfiError *misagent_remove(MisagentClientHandle *client, const char *uuid) { STUB_ERR; }
IdeviceFfiError *misagent_install(MisagentClientHandle *client, const uint8_t *profile, size_t length) { STUB_ERR; }
void misagent_free_profiles(uint8_t **profiles, size_t *lengths, size_t count) { STUB_VOID; }
void misagent_client_free(MisagentClientHandle *handle) { STUB_VOID; }
IdeviceFfiError *image_mounter_connect(IdeviceProviderHandle *provider, ImageMounterHandle **client) { STUB_ERR; }
IdeviceFfiError *image_mounter_copy_devices(ImageMounterHandle *client, plist_t **devices, size_t *count) { STUB_ERR; }
IdeviceFfiError *image_mounter_mount_personalized(ImageMounterHandle *client, IdeviceProviderHandle *provider, const uint8_t *image, size_t image_len, const uint8_t *trustcache, size_t trustcache_len, const uint8_t *manifest, size_t manifest_len, const char *signature, uint64_t chip_id) { STUB_ERR; }
void image_mounter_free(ImageMounterHandle *handle) { STUB_VOID; }
IdeviceFfiError *syslog_relay_connect_tcp(IdeviceProviderHandle *provider, SyslogRelayClientHandle **client) { STUB_ERR; }
IdeviceFfiError *syslog_relay_next(SyslogRelayClientHandle *client, char **message) { STUB_ERR; }
void syslog_relay_client_free(SyslogRelayClientHandle *handle) { STUB_VOID; }
IdeviceFfiError *app_service_connect_rsd(AdapterHandle *adapter, RsdHandshakeHandle *handshake, AppServiceHandle **client) { STUB_ERR; }
IdeviceFfiError *app_service_list_processes(AppServiceHandle *client, ProcessTokenC **processes, uintptr_t *count) { STUB_ERR; }
void app_service_free_process_list(ProcessTokenC *processes, uintptr_t count) { STUB_VOID; }
IdeviceFfiError *app_service_send_signal(AppServiceHandle *client, uint32_t pid, int sig, SignalResponseC **response) { STUB_ERR; }
void app_service_free_signal_response(SignalResponseC *response) { STUB_VOID; }
void app_service_free(AppServiceHandle *handle) { STUB_VOID; }
IdeviceFfiError *springboard_services_connect(IdeviceProviderHandle *provider, SpringBoardServicesClientHandle **client) { STUB_ERR; }
IdeviceFfiError *springboard_services_get_icon(SpringBoardServicesClientHandle *client, const char *bundle_id, void **png_data, size_t *png_size) { STUB_ERR; }
void springboard_services_free(SpringBoardServicesClientHandle *handle) { STUB_VOID; }
IdeviceFfiError *location_simulation_new(RemoteServerHandle *remote_server, LocationSimulationHandle **client) { STUB_ERR; }
IdeviceFfiError *location_simulation_set(LocationSimulationHandle *client, double latitude, double longitude) { STUB_ERR; }
IdeviceFfiError *location_simulation_clear(LocationSimulationHandle *client) { STUB_ERR; }
void location_simulation_free(LocationSimulationHandle *handle) { STUB_VOID; }
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
IdeviceFfiError *diagnostics_service_connect_rsd(AdapterHandle *provider, RsdHandshakeHandle *handshake, DiagnosticsServiceHandle **handle) { STUB_ERR; }
IdeviceFfiError *diagnostics_service_new(ReadWriteOpaque *socket, DiagnosticsServiceHandle **handle) { STUB_ERR; }
IdeviceFfiError *diagnostics_service_capture_sysdiagnose(DiagnosticsServiceHandle *handle, bool dry_run, char **preferred_filename, uintptr_t *expected_length, SysdiagnoseStreamHandle **stream_handle) { STUB_ERR; }
IdeviceFfiError *sysdiagnose_stream_next(SysdiagnoseStreamHandle *handle, uint8_t **data, uintptr_t *len) { STUB_ERR; }
void diagnostics_service_free(DiagnosticsServiceHandle *handle) { STUB_VOID; }
