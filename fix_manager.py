import re

with open('IdeviceManager.m', 'r') as f:
    content = f.read()

# Fix image_mounter_copy_devices call and memory management
old_ddi_block = r"""        plist_t devices = NULL; size_t count = 0;
        err = image_mounter_copy_devices(mounter, &devices, &count);
        if (!err) ddi = (count > 0); else idevice_error_free(err);
        image_mounter_free(mounter);"""

new_ddi_block = r"""        plist_t *devices = NULL; size_t count = 0;
        err = image_mounter_copy_devices(mounter, &devices, &count);
        if (!err) {
            ddi = (count > 0);
            if (devices) idevice_plist_array_free(devices, (uintptr_t)count);
        } else {
            idevice_error_free(err);
        }
        image_mounter_free(mounter);"""

content = content.replace(old_ddi_block, new_ddi_block)

# Ensure pairingFilePath check is robust
old_pairing_check = r"""    if (pairingPath) {
        err = idevice_pairing_file_read([pairingPath UTF8String], &pairingForProvider);
        if (!err) err = idevice_pairing_file_read([pairingPath UTF8String], &pairingForSession);
        if (err || !pairingForProvider || !pairingForSession) {
            [self _handleFfiError:err fallback:@"ペアリングファイルの読み込みに失敗しました"];
            if (pairingForProvider) idevice_pairing_file_free(pairingForProvider);
            if (pairingForSession) idevice_pairing_file_free(pairingForSession);
            return;
        }
    } else { [self _handleError:@"ペアリングファイルが選択されていません"]; return; }"""

new_pairing_check = r"""    if (pairingPath && pairingPath.length > 0) {
        err = idevice_pairing_file_read([pairingPath UTF8String], &pairingForProvider);
        if (!err) {
            err = idevice_pairing_file_read([pairingPath UTF8String], &pairingForSession);
        }
        if (err || !pairingForProvider || !pairingForSession) {
            [self _handleFfiError:err fallback:@"ペアリングファイルの読み込みに失敗しました"];
            if (pairingForProvider) idevice_pairing_file_free(pairingForProvider);
            if (pairingForSession) idevice_pairing_file_free(pairingForSession);
            return;
        }
    } else {
        [self _handleError:@"ペアリングファイルが選択されていません。設定から選択してください。"];
        return;
    }"""

content = content.replace(old_pairing_check, new_pairing_check)

with open('IdeviceManager.m', 'w') as f:
    f.write(content)
