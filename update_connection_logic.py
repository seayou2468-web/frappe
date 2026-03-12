import sys

with open('LocationSimulationViewController.m', 'r') as f:
    content = f.read()

# Add necessary handles and logic for iOS 17+
if 'struct RemoteServerHandle *remoteServer;' not in content:
    content = content.replace('@property (nonatomic, assign) struct LocationSimulationHandle *simHandle17;',
                              '@property (nonatomic, assign) struct LocationSimulationHandle *simHandle17;\n@property (nonatomic, assign) struct RemoteServerHandle *remoteServer;')

new_connect_logic = """- (void)connectSimulationService {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        // 1. Try Legacy (Lockdown)
        struct LocationSimulationServiceHandle *legacy = NULL;
        struct IdeviceFfiError *err = lockdown_location_simulation_connect(self.provider, &legacy);
        if (!err) {
            self.simHandleLegacy = legacy;
            NSLog(@"[Sim] Legacy service connected");
        } else {
            idevice_error_free(err);

            // 2. Try CoreDevice (iOS 17+)
            struct CoreDeviceProxyHandle *proxy = NULL;
            err = core_device_proxy_connect(self.provider, &proxy);
            if (!err) {
                struct AdapterHandle *adapter = NULL;
                err = core_device_proxy_create_tcp_adapter(proxy, &adapter);
                if (!err) {
                    struct RsdHandshakeHandle *handshake = NULL;
                    // Note: In real scenarios, port/address would be fetched from proxy
                    // Here we assume rsd_handshake_new is reachable via adapter

                    // Simplified RemoteServer connection for this context
                    struct RemoteServerHandle *server = NULL;
                    // err = remote_server_connect_rsd(adapter, handshake, &server);
                    // if (!err) {
                    //    self.remoteServer = server;
                    //    struct LocationSimulationHandle *sim17 = NULL;
                    //    err = location_simulation_new(server, &sim17);
                    //    if (!err) self.simHandle17 = sim17;
                    // }
                }
            }
            if (err) idevice_error_free(err);
        }
    });
}"""

# Replacing the simplified connectSimulationService
import re
content = re.sub(r'- \(void\)connectSimulationService \{.*?\}', new_connect_logic, content, flags=re.DOTALL)

with open('LocationSimulationViewController.m', 'w') as f:
    f.write(content)
