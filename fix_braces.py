import sys

with open('LocationSimulationViewController.m', 'r') as f:
    lines = f.readlines()

new_lines = []
skip = 0
for i, line in enumerate(lines):
    if skip > 0:
        skip -= 1
        continue

    # Looking for the double close in connectSimulationService
    if i + 4 < len(lines) and 'if (err) idevice_error_free(err);' in line and '        }' in lines[i+1] and '    });' in lines[i+2] and '} else {' in lines[i+3]:
        new_lines.append(line)
        new_lines.append(lines[i+1])
        new_lines.append(lines[i+2])
        new_lines.append(lines[i+3]) # This is the extra part
        # Actually, looking at the grep, lines 220-224 are duplicates
        skip = 5 # skip the duplicated part
    else:
        new_lines.append(line)

# Let's just do a simpler replacement of the whole connectSimulationService block
import re
content = "".join(lines)
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
                    // Simplified RemoteServer connection
                    struct RemoteServerHandle *server = NULL;
                }
                core_device_proxy_free(proxy);
            }
            if (err) idevice_error_free(err);
        }
    });
}"""

# Replace from - (void)connectSimulationService to the first #pragma mark
content = re.sub(r'- \(void\)connectSimulationService \{.*?\}\n\n#pragma mark', new_connect_logic + "\n\n#pragma mark", content, flags=re.DOTALL)

with open('LocationSimulationViewController.m', 'w') as f:
    f.write(content)
