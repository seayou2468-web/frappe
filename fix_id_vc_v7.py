import sys

with open('IdeviceViewController.m', 'r') as f:
    content = f.read()

# Fix the duplicate lockdownd_start_service call logic error I made in fix_idevice_vc_config_v3.py
content = content.replace('''        if (err || !stream) {
            if (err) idevice_error_free(err);
            // Fallback to legacy lockdown
            if (self.currentLockdown) {
                err = lockdownd_start_service(self.currentLockdown, "com.apple.mobile.MCInstall", &port, NULL);
                if (!err) {
                    err = adapter_connect(self.currentProvider, port, &stream);
                }
                if (err) idevice_error_free(err);
            }
        }''', '''        if (err || !stream) {
            if (err) idevice_error_free(err);
            // Fallback or retry
            if (self.currentLockdown && !stream) {
                uint16_t port2 = 0;
                err = lockdownd_start_service(self.currentLockdown, "com.apple.mobile.MCInstall", &port2, NULL);
                if (!err) {
                    err = adapter_connect(self.currentProvider, port2, &stream);
                }
                if (err) idevice_error_free(err);
            }
        }''')

with open('IdeviceViewController.m', 'w') as f:
    f.write(content)
