import re

with open('IdeviceManager.m', 'r') as f:
    content = f.read()

# Refine _performConnect for better error cleanup
old_connect = r"""    err = idevice_tcp_provider_new((const idevice_sockaddr *)&sa, pairingForProvider, "frappe-idevice", &localProvider);
    if (err || !localProvider) { [self _handleFfiError:err fallback:@"プロバイダーの作成に失敗しました"]; idevice_pairing_file_free(pairingForSession); return; }
    err = lockdownd_connect(localProvider, &localLockdown);
    if (err || !localLockdown) { [self _handleFfiError:err fallback:@"Lockdownサービスへの接続に失敗しました"]; idevice_provider_free(localProvider); idevice_pairing_file_free(pairingForSession); return; }
    err = lockdownd_start_session(localLockdown, pairingForSession);
    if (err) { [self _handleFfiError:err fallback:@"セッションの開始に失敗しました"]; idevice_pairing_file_free(pairingForSession); lockdownd_client_free(localLockdown); idevice_provider_free(localProvider); return; }"""

new_connect = r"""    err = idevice_tcp_provider_new((const idevice_sockaddr *)&sa, pairingForProvider, "frappe-idevice", &localProvider);
    if (err || !localProvider) {
        [self _handleFfiError:err fallback:@"プロバイダーの作成に失敗しました"];
        idevice_pairing_file_free(pairingForProvider);
        idevice_pairing_file_free(pairingForSession);
        return;
    }
    // Note: localProvider now owns pairingForProvider logic internally usually,
    // but if idevice_tcp_provider_new fails, we must free it.

    err = lockdownd_connect(localProvider, &localLockdown);
    if (err || !localLockdown) {
        [self _handleFfiError:err fallback:@"Lockdownサービスへの接続に失敗しました"];
        idevice_provider_free(localProvider);
        idevice_pairing_file_free(pairingForSession);
        return;
    }

    err = lockdownd_start_session(localLockdown, pairingForSession);
    if (err) {
        [self _handleFfiError:err fallback:@"セッションの開始に失敗しました"];
        idevice_pairing_file_free(pairingForSession);
        lockdownd_client_free(localLockdown);
        idevice_provider_free(localProvider);
        return;
    }"""

content = content.replace(old_connect, new_connect)

with open('IdeviceManager.m', 'w') as f:
    f.write(content)
