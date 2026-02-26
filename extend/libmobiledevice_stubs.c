#include "idevice.h"
#include <stdlib.h>

void lockdownd_client_free(LockdowndClientHandle *handle) {
    // Stub
}

void idevice_error_free(IdeviceFfiError *handle) {
    // Stub
}

void idevice_pairing_file_free(IdevicePairingFile *handle) {
    // Stub
}

void idevice_provider_free(IdeviceProviderHandle *handle) {
    // Stub
}

void image_mounter_free(ImageMounterHandle *handle) {
    // Stub
}

void plist_free(plist_t plist) {
    // Stub
}

void idevice_data_free(uint8_t *handle, size_t size) {
    // Stub
}

void plist_mem_free(void *ptr) {
    if (ptr) free(ptr);
}

void installation_proxy_client_free(InstallationProxyClientHandle *handle) {
    // Stub
}

void springboard_services_free(SpringBoardServicesClientHandle *handle) {
    // Stub
}

void afc_client_free(AfcClientHandle *handle) {
    // Stub
}

void afc_file_info_free(AfcFileInfo *info) {
    // Stub
}

void afc_file_close(AfcFileHandle *handle) {
    // Stub
}

void app_service_free_process_list(ProcessTokenC *processes, uintptr_t count) {
    // Stub
}

void app_service_free_signal_response(SignalResponseC *response) {
    // Stub
}

void app_service_free(AppServiceHandle *handle) {
    // Stub
}

void remote_server_free(RemoteServerHandle *handle) {
    // Stub
}

void rsd_handshake_free(RsdHandshakeHandle *handle) {
    // Stub
}

void adapter_free(AdapterHandle *handle) {
    // Stub
}

void core_device_proxy_free(CoreDeviceProxyHandle *handle) {
    // Stub
}

void debug_proxy_free(DebugProxyHandle *handle) {
    // Stub
}

void debugserver_command_free(DebugserverCommandHandle *handle) {
    // Stub
}

void process_control_free(ProcessControlHandle *handle) {
    // Stub
}

void heartbeat_client_free(HeartbeatClientHandle *handle) {
    // Stub
}

void syslog_relay_client_free(SyslogRelayClientHandle *handle) {
    // Stub
}

void location_simulation_free(LocationSimulationHandle *handle) {
    // Stub
}

void misagent_client_free(MisagentClientHandle *handle) {
    // Stub
}

void diagnostics_service_free(DiagnosticsServiceHandle *handle) {
    // Stub
}
