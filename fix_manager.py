import sys

filepath = 'IdeviceManager.m'
with open(filepath, 'r') as f:
    content = f.read()

# Fix idevice_tcp_provider_new call and reorder logic to load pairing file first
old_block = """    struct IdeviceFfiError *err = NULL;
    struct IdeviceProviderHandle *provider = NULL;

    err = idevice_tcp_provider_new((const idevice_sockaddr *)&sa, sizeof(sa), &provider);
    if (err) {
        [self _handleFfiError:err];
        return;
    }
    self.provider = provider;

    struct LockdowndClientHandle *lockdown = NULL;
    err = lockdownd_connect(provider, &lockdown);
    if (err) {
        [self _handleFfiError:err];
        return;
    }
    self.lockdownClient = lockdown;

    if (self.pairingFilePath) {
        struct IdevicePairingFile *pairingFile = NULL;
        err = idevice_pairing_file_read([self.pairingFilePath UTF8String], &pairingFile);
        if (err) {
            [self _handleFfiError:err];
            return;
        }

        err = lockdownd_start_session(lockdown, pairingFile);
        idevice_pairing_file_free(pairingFile);"""

new_block = """    struct IdeviceFfiError *err = NULL;
    struct IdeviceProviderHandle *provider = NULL;
    struct IdevicePairingFile *pairingFile = NULL;

    if (self.pairingFilePath) {
        err = idevice_pairing_file_read([self.pairingFilePath UTF8String], &pairingFile);
        if (err) {
            [self _handleFfiError:err];
            return;
        }
    } else {
        [self _handleError:@"Pairing file not selected"];
        return;
    }

    err = idevice_tcp_provider_new((const idevice_sockaddr *)&sa, pairingFile, "frappe-idevice", &provider);
    if (err) {
        if (pairingFile) idevice_pairing_file_free(pairingFile);
        [self _handleFfiError:err];
        return;
    }
    self.provider = provider;

    struct LockdowndClientHandle *lockdown = NULL;
    err = lockdownd_connect(provider, &lockdown);
    if (err) {
        if (pairingFile) idevice_pairing_file_free(pairingFile);
        [self _handleFfiError:err];
        return;
    }
    self.lockdownClient = lockdown;

    err = lockdownd_start_session(lockdown, pairingFile);
    idevice_pairing_file_free(pairingFile);"""

content = content.replace(old_block, new_block)

with open(filepath, 'w') as f:
    f.write(content)
