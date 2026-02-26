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

struct IdeviceFfiError *afc_client_new(struct IdeviceHandle *socket,
                                       struct AfcClientHandle **client);

void afc_client_free(struct AfcClientHandle *handle);

struct IdeviceFfiError *afc_list_directory(struct AfcClientHandle *client,
                                           const char *path,
                                           char ***entries,
                                           size_t *count);

struct IdeviceFfiError *afc_make_directory(struct AfcClientHandle *client,
                                           const char *path);

struct IdeviceFfiError *afc_get_file_info(struct AfcClientHandle *client,
                                          const char *path,
                                          struct AfcFileInfo *info);

void afc_file_info_free(struct AfcFileInfo *info);

struct IdeviceFfiError *afc_file_open(struct AfcClientHandle *client,
                                      const char *path,
                                      enum AfcFopenMode mode,
                                      struct AfcFileHandle **handle);

struct IdeviceFfiError *afc_file_close(struct AfcFileHandle *handle);

struct IdeviceFfiError *afc_file_read(struct AfcFileHandle *handle,
                                      uint8_t **data,
                                      uintptr_t len,
                                      size_t *bytes_read);

struct IdeviceFfiError *afc_file_read_entire(struct AfcFileHandle *handle,
                                             uint8_t **data,
                                             size_t *length);

struct IdeviceFfiError *afc_file_seek(struct AfcFileHandle *handle,
                                      int64_t offset,
                                      int whence,
                                      int64_t *new_pos);

struct IdeviceFfiError *afc_file_tell(struct AfcFileHandle *handle,
                                      int64_t *pos);

struct IdeviceFfiError *afc_file_write(struct AfcFileHandle *handle,
                                       const uint8_t *data,
                                       size_t length);

struct IdeviceFfiError *afc_make_link(struct AfcClientHandle *client,
                                      const char *target,
                                      const char *source,
                                      enum AfcLinkType link_type);

struct IdeviceFfiError *diagnostics_service_connect_rsd(
    struct AdapterHandle *provider,
    struct RsdHandshakeHandle *handshake,
    struct DiagnosticsServiceHandle **handle);

struct IdeviceFfiError *diagnostics_service_new(
    struct ReadWriteOpaque *socket,
    struct DiagnosticsServiceHandle **handle);

struct IdeviceFfiError *diagnostics_service_capture_sysdiagnose(
    struct DiagnosticsServiceHandle *handle,
    bool dry_run,
    char **preferred_filename,
    uintptr_t *expected_length,
    struct SysdiagnoseStreamHandle **stream_handle);

struct IdeviceFfiError *sysdiagnose_stream_next(
    struct SysdiagnoseStreamHandle *handle,
    uint8_t **data,
    uintptr_t *len);

void diagnostics_service_free(struct DiagnosticsServiceHandle *handle);

#endif