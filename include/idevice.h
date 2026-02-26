#ifndef IDEVICE_H
#define IDEVICE_H

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
typedef int idevice_socklen_t;
typedef struct sockaddr idevice_sockaddr;
#else
#include <sys/types.h>
#include <sys/socket.h>
typedef socklen_t idevice_socklen_t;
typedef struct sockaddr idevice_sockaddr;
#endif

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#define LOCKDOWN_PORT 62078

typedef enum AfcFopenMode {
  AfcRdOnly = 1,
  AfcRw = 2,
  AfcWrOnly = 3,
  AfcWr = 4,
  AfcAppend = 5,
  AfcRdAppend = 6,
} AfcFopenMode;

typedef enum AfcLinkType {
  Hard = 1,
  Symbolic = 2,
} AfcLinkType;

typedef enum IdeviceLoggerError {
  Success = 0,
  FileError = -1,
  AlreadyInitialized = -2,
  InvalidPathString = -3,
} IdeviceLoggerError;

typedef enum IdeviceLogLevel {
  Disabled = 0,
  ErrorLevel = 1,
  Warn = 2,
  Info = 3,
  Debug = 4,
  Trace = 5,
} IdeviceLogLevel;

typedef enum {
    PLIST_BOOLEAN,
    PLIST_UINT,
    PLIST_REAL,
    PLIST_STRING,
    PLIST_ARRAY,
    PLIST_DICT,
    PLIST_DATE,
    PLIST_DATA,
    PLIST_KEY,
    PLIST_UID,
    PLIST_NONE
} plist_type;

typedef struct AdapterHandle AdapterHandle;
typedef struct AdapterStreamHandle AdapterStreamHandle;
typedef struct AfcClientHandle AfcClientHandle;
typedef struct AfcFileHandle AfcFileHandle;
typedef struct AmfiClientHandle AmfiClientHandle;
typedef struct AppServiceHandle AppServiceHandle;
typedef struct CoreDeviceProxyHandle CoreDeviceProxyHandle;
typedef struct CrashReportCopyMobileHandle CrashReportCopyMobileHandle;
typedef struct DebugProxyHandle DebugProxyHandle;
typedef struct DiagnosticsRelayClientHandle DiagnosticsRelayClientHandle;
typedef struct DiagnosticsServiceHandle DiagnosticsServiceHandle;
typedef struct HeartbeatClientHandle HeartbeatClientHandle;
typedef struct HouseArrestClientHandle HouseArrestClientHandle;
typedef struct IdeviceHandle IdeviceHandle;
typedef struct IdevicePairingFile IdevicePairingFile;
typedef struct IdeviceProviderHandle IdeviceProviderHandle;
typedef struct IdeviceSocketHandle IdeviceSocketHandle;
typedef struct ImageMounterHandle ImageMounterHandle;
typedef struct InstallationProxyClientHandle InstallationProxyClientHandle;
typedef struct LocationSimulationHandle LocationSimulationHandle;
typedef struct LockdowndClientHandle LockdowndClientHandle;
typedef struct MisagentClientHandle MisagentClientHandle;
typedef struct NotificationProxyClientHandle NotificationProxyClientHandle;
typedef struct OsTraceRelayClientHandle OsTraceRelayClientHandle;
typedef struct OsTraceRelayReceiverHandle OsTraceRelayReceiverHandle;
typedef struct ProcessControlHandle ProcessControlHandle;
typedef struct ReadWriteOpaque ReadWriteOpaque;
typedef struct RemoteServerHandle RemoteServerHandle;
typedef struct RsdHandshakeHandle RsdHandshakeHandle;
typedef struct ScreenshotClientHandle ScreenshotClientHandle;
typedef struct ScreenshotrClientHandle ScreenshotrClientHandle;
typedef struct SpringBoardServicesClientHandle SpringBoardServicesClientHandle;
typedef struct SysdiagnoseStreamHandle SysdiagnoseStreamHandle;
typedef struct SyslogRelayClientHandle SyslogRelayClientHandle;
typedef struct TcpEatObject TcpEatObject;
typedef struct TcpFeedObject TcpFeedObject;
typedef struct UsbmuxdAddrHandle UsbmuxdAddrHandle;
typedef struct UsbmuxdConnectionHandle UsbmuxdConnectionHandle;
typedef struct UsbmuxdDeviceHandle UsbmuxdDeviceHandle;
typedef struct UsbmuxdListenerHandle UsbmuxdListenerHandle;
typedef struct Vec_u64 Vec_u64;
typedef struct DebugserverCommandHandle DebugserverCommandHandle;
typedef struct SignalResponseC SignalResponseC;

typedef struct ProcessTokenC {
    uint32_t pid;
    const char *executable_url;
} ProcessTokenC;

typedef struct IdeviceFfiError {
  int32_t code;
  const char *message;
} IdeviceFfiError;

typedef void *plist_t;

typedef struct AfcFileInfo {
  size_t size;
  size_t blocks;
  int64_t creation;
  int64_t modified;
  char *st_nlink;
  char *st_ifmt;
  char *st_link_target;
} AfcFileInfo;

// Basic
void idevice_init_logger(IdeviceLogLevel app_level, IdeviceLogLevel ffi_level, const char *path);
void idevice_error_free(IdeviceFfiError *handle);
void idevice_string_free(char *handle);
void idevice_data_free(uint8_t *handle, size_t size);

// Pairing
IdeviceFfiError *idevice_pairing_file_read(const char *path, IdevicePairingFile **pairing_file);
void idevice_pairing_file_free(IdevicePairingFile *handle);

// Provider
IdeviceFfiError *idevice_tcp_provider_new(const struct sockaddr *addr, IdevicePairingFile *pairing_file, const char *label, IdeviceProviderHandle **provider);
void idevice_provider_free(IdeviceProviderHandle *handle);

// CoreDevice
IdeviceFfiError *core_device_proxy_connect(IdeviceProviderHandle *provider, CoreDeviceProxyHandle **core_device);
IdeviceFfiError *core_device_proxy_get_server_rsd_port(CoreDeviceProxyHandle *core_device, uint16_t *rsd_port);
IdeviceFfiError *core_device_proxy_create_tcp_adapter(CoreDeviceProxyHandle *core_device, AdapterHandle **adapter);
void core_device_proxy_free(CoreDeviceProxyHandle *handle);

// Adapter
IdeviceFfiError *adapter_connect(AdapterHandle *adapter, uint16_t port, ReadWriteOpaque **stream);
void adapter_free(AdapterHandle *handle);
void adapter_stream_close(AdapterStreamHandle *handle);

// RSD Handshake
IdeviceFfiError *rsd_handshake_new(ReadWriteOpaque *stream, RsdHandshakeHandle **handshake);
void rsd_handshake_free(RsdHandshakeHandle *handle);

// Remote Server
IdeviceFfiError *remote_server_connect_rsd(AdapterHandle *adapter, RsdHandshakeHandle *handshake, RemoteServerHandle **remote_server);
void remote_server_free(RemoteServerHandle *handle);

// Debug Proxy
IdeviceFfiError *debug_proxy_connect_rsd(AdapterHandle *adapter, RsdHandshakeHandle *handshake, DebugProxyHandle **debug_proxy);
void debug_proxy_free(DebugProxyHandle *handle);
void debug_proxy_send_ack(DebugProxyHandle *debug_proxy);
IdeviceFfiError *debug_proxy_send_command(DebugProxyHandle *debug_proxy, DebugserverCommandHandle *command, char **response);
void debug_proxy_set_ack_mode(DebugProxyHandle *debug_proxy, bool ack_mode);
IdeviceFfiError *debug_proxy_send_raw(DebugProxyHandle *debug_proxy, const char *data, size_t len);

// Debugserver Command
DebugserverCommandHandle *debugserver_command_new(const char *command, const char **args, size_t args_count);
void debugserver_command_free(DebugserverCommandHandle *handle);

// Process Control
IdeviceFfiError *process_control_new(RemoteServerHandle *remote_server, ProcessControlHandle **process_control);
IdeviceFfiError *process_control_launch_app(ProcessControlHandle *process_control, const char *bundle_id, const char **args, size_t args_count, const char **env, size_t env_count, bool stop_at_entry, bool springboard, uint64_t *pid);
void process_control_free(ProcessControlHandle *handle);

// Misagent
IdeviceFfiError *misagent_connect(IdeviceProviderHandle *provider, MisagentClientHandle **client);
IdeviceFfiError *misagent_copy_all(MisagentClientHandle *client, uint8_t ***profiles, size_t **lengths, size_t *count);
IdeviceFfiError *misagent_remove(MisagentClientHandle *client, const char *uuid);
IdeviceFfiError *misagent_install(MisagentClientHandle *client, const uint8_t *profile, size_t length);
void misagent_free_profiles(uint8_t **profiles, size_t *lengths, size_t count);
void misagent_client_free(MisagentClientHandle *handle);

// Image Mounter
IdeviceFfiError *image_mounter_connect(IdeviceProviderHandle *provider, ImageMounterHandle **client);
IdeviceFfiError *image_mounter_copy_devices(ImageMounterHandle *client, plist_t **devices, size_t *count);
IdeviceFfiError *image_mounter_mount_personalized(ImageMounterHandle *client, IdeviceProviderHandle *provider, const uint8_t *image, size_t image_len, const uint8_t *trustcache, size_t trustcache_len, const uint8_t *manifest, size_t manifest_len, const char *signature, uint64_t chip_id);
void image_mounter_free(ImageMounterHandle *handle);

// Lockdownd
IdeviceFfiError *lockdownd_connect(IdeviceProviderHandle *provider, LockdowndClientHandle **client);
IdeviceFfiError *lockdownd_start_session(LockdowndClientHandle *client, IdevicePairingFile *pairing_file);
IdeviceFfiError *lockdownd_get_value(LockdowndClientHandle *client, const char *domain, const char *key, plist_t *value);
void lockdownd_client_free(LockdowndClientHandle *handle);

// Plist
void plist_free(plist_t plist);
void plist_get_uint_val(plist_t node, uint64_t *val);
void plist_get_bool_val(plist_t node, uint8_t *val);
void plist_get_string_val(plist_t node, char **val);
plist_t plist_dict_get_item(plist_t node, const char *key);
plist_t plist_array_get_item(plist_t node, uint32_t n);
uint32_t plist_array_get_size(plist_t node);
plist_type plist_get_node_type(plist_t node);
void plist_to_bin(plist_t plist, char **plist_bin, uint32_t *length);
void plist_mem_free(void *ptr);

// Syslog Relay
IdeviceFfiError *syslog_relay_connect_tcp(IdeviceProviderHandle *provider, SyslogRelayClientHandle **client);
IdeviceFfiError *syslog_relay_next(SyslogRelayClientHandle *client, char **message);
void syslog_relay_client_free(SyslogRelayClientHandle *handle);

// App Service
IdeviceFfiError *app_service_connect_rsd(AdapterHandle *adapter, RsdHandshakeHandle *handshake, AppServiceHandle **client);
IdeviceFfiError *app_service_list_processes(AppServiceHandle *client, ProcessTokenC **processes, uintptr_t *count);
void app_service_free_process_list(ProcessTokenC *processes, uintptr_t count);
IdeviceFfiError *app_service_send_signal(AppServiceHandle *client, uint32_t pid, int sig, SignalResponseC **response);
void app_service_free_signal_response(SignalResponseC *response);
void app_service_free(AppServiceHandle *handle);

// Installation Proxy
IdeviceFfiError *installation_proxy_connect(IdeviceProviderHandle *provider, InstallationProxyClientHandle **client);
IdeviceFfiError *installation_proxy_get_apps(InstallationProxyClientHandle *client, const char **bundle_ids, size_t bundle_ids_count, uint32_t flags, plist_t **apps, size_t *count);
void installation_proxy_client_free(InstallationProxyClientHandle *handle);

// SpringBoard Services
IdeviceFfiError *springboard_services_connect(IdeviceProviderHandle *provider, SpringBoardServicesClientHandle **client);
IdeviceFfiError *springboard_services_get_icon(SpringBoardServicesClientHandle *client, const char *bundle_id, void **png_data, size_t *png_size);
void springboard_services_free(SpringBoardServicesClientHandle *handle);

// Location Simulation
IdeviceFfiError *location_simulation_new(RemoteServerHandle *remote_server, LocationSimulationHandle **client);
IdeviceFfiError *location_simulation_set(LocationSimulationHandle *client, double latitude, double longitude);
IdeviceFfiError *location_simulation_clear(LocationSimulationHandle *client);
void location_simulation_free(LocationSimulationHandle *handle);

// Heartbeat
IdeviceFfiError *heartbeat_connect(IdeviceProviderHandle *provider, HeartbeatClientHandle **client);
IdeviceFfiError *heartbeat_get_marco(HeartbeatClientHandle *client, uint64_t current_interval, uint64_t *new_interval);
IdeviceFfiError *heartbeat_send_polo(HeartbeatClientHandle *client);
void heartbeat_client_free(HeartbeatClientHandle *handle);

// AFC
IdeviceFfiError *afc_client_connect(IdeviceProviderHandle *provider, AfcClientHandle **client);
IdeviceFfiError *afc_client_new(IdeviceHandle *socket, AfcClientHandle **client);
void afc_client_free(AfcClientHandle *handle);
IdeviceFfiError *afc_list_directory(AfcClientHandle *client, const char *path, char ***entries, size_t *count);
IdeviceFfiError *afc_make_directory(AfcClientHandle *client, const char *path);
IdeviceFfiError *afc_get_file_info(AfcClientHandle *client, const char *path, AfcFileInfo *info);
void afc_file_info_free(AfcFileInfo *info);
IdeviceFfiError *afc_file_open(AfcClientHandle *client, const char *path, AfcFopenMode mode, AfcFileHandle **handle);
IdeviceFfiError *afc_file_close(AfcFileHandle *handle);
IdeviceFfiError *afc_file_read(AfcFileHandle *handle, uint8_t **data, uintptr_t len, size_t *bytes_read);
IdeviceFfiError *afc_file_read_entire(AfcFileHandle *handle, uint8_t **data, size_t *length);
IdeviceFfiError *afc_file_seek(AfcFileHandle *handle, int64_t offset, int whence, int64_t *new_pos);
IdeviceFfiError *afc_file_tell(AfcFileHandle *handle, int64_t *pos);
IdeviceFfiError *afc_file_write(AfcFileHandle *handle, const uint8_t *data, size_t length);
IdeviceFfiError *afc_make_link(AfcClientHandle *client, const char *target, const char *source, AfcLinkType link_type);

// Diagnostics
IdeviceFfiError *diagnostics_service_connect_rsd(AdapterHandle *provider, RsdHandshakeHandle *handshake, DiagnosticsServiceHandle **handle);
IdeviceFfiError *diagnostics_service_new(ReadWriteOpaque *socket, DiagnosticsServiceHandle **handle);
IdeviceFfiError *diagnostics_service_capture_sysdiagnose(DiagnosticsServiceHandle *handle, bool dry_run, char **preferred_filename, uintptr_t *expected_length, SysdiagnoseStreamHandle **stream_handle);
IdeviceFfiError *sysdiagnose_stream_next(SysdiagnoseStreamHandle *handle, uint8_t **data, uintptr_t *len);
void diagnostics_service_free(DiagnosticsServiceHandle *handle);

#endif
