import sys

with open('IdeviceViewController.m', 'r') as f:
    content = f.read()

# Fix the method call again to use the correct rsd port logic if we can't find a direct helper
# Actually, I'll use the rsdPort logic from AppManager.m
old_block = """        struct RsdHandshakeHandle *handshake = NULL;
        uint16_t port = 0;
        struct ReadWriteOpaque *stream = NULL;

        // Try RSD first (iOS 17+)
        struct IdeviceFfiError *err = rsd_handshake_new_from_provider(self.currentProvider, &handshake);
        if (!err) {
            struct CRsdService *svc = NULL;
            err = rsd_get_service_info(handshake, "com.apple.mobile.MCInstall.shim.remote", &svc);
            if (!err && svc) {
                port = svc->port;
                rsd_free_service(svc);
                err = adapter_connect(self.currentProvider, port, &stream);
            }
            rsd_handshake_free(handshake);
        }"""

new_block = """        uint16_t rsdPort = 0;
        struct ReadWriteOpaque *stream = NULL;
        struct IdeviceFfiError *err = NULL;

        // Try RSD port lookup if we could, but we need CoreDeviceProxy for that.
        // For now, let's stick to legacy or try to guess RSD port if it's constant,
        // OR better, use the Lockdown client to get it if possible.

        // Let's use the provided Lockdown client to start service
        if (self.currentLockdown) {
            uint16_t port = 0;
            err = lockdownd_start_service(self.currentLockdown, "com.apple.mobile.MCInstall", &port, NULL);
            if (!err) {
                err = adapter_connect(self.currentProvider, port, &stream);
            }
        }"""

content = content.replace(old_block, new_block)

with open('IdeviceViewController.m', 'w') as f:
    f.write(content)
