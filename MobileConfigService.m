#import "MobileConfigService.h"
#import "HeartbeatManager.h"
#import <Security/Security.h>

@interface MobileConfigService ()

@property (nonatomic, assign) struct IdeviceProviderHandle *provider;
@property (nonatomic, assign) struct LockdowndClientHandle *lockdown;

@property (nonatomic, assign) struct CoreDeviceProxyHandle *proxy;
@property (nonatomic, assign) struct AdapterHandle *tunnelAdapter;
@property (nonatomic, assign) struct ReadWriteOpaque *stream;

@property (nonatomic, strong) dispatch_queue_t serviceQueue;
@property (nonatomic, assign) BOOL connected;

@end

@implementation MobileConfigService

- (instancetype)initWithProvider:(struct IdeviceProviderHandle *)provider lockdown:(struct LockdowndClientHandle *)lockdown {
    self = [super init];
    if (self) {
        _provider = provider;
        _lockdown = lockdown;
        _serviceQueue = dispatch_queue_create("com.frappe.mobileconfig", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    // CRITICAL: Block until the serial queue is drained.
    // This ensures no background task is using the provider/lockdown handles
    // while the parent view controller is freeing them.
    if (_serviceQueue) {
        dispatch_sync(_serviceQueue, ^{
            if (self->_stream) {
                idevice_stream_free(self->_stream);
                self->_stream = NULL;
            }
            if (self->_tunnelAdapter) {
                adapter_free(self->_tunnelAdapter);
                self->_tunnelAdapter = NULL;
            }
            if (self->_proxy) {
                core_device_proxy_free(self->_proxy);
                self->_proxy = NULL;
            }
        });
    }
}

- (void)log:(NSString *)msg {
    if (!msg) return;
    if (self.logger) {
        // Ensure logger is called on main thread as it usually updates UI
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.logger) self.logger(msg);
        });
    }
    NSLog(@"[MobileConfig] %@", msg);
}

#pragma mark - Connection

- (void)connectWithCompletion:(MobileConfigCompletion)completion {
    dispatch_async(self.serviceQueue, ^{
        if (self.connected) {
            if (completion) completion(YES, nil, nil);
            return;
        }

        [[HeartbeatManager sharedManager] pauseHeartbeat];
        [NSThread sleepForTimeInterval:0.5];

        [self log:@"Initiating connection..."];
        struct IdeviceFfiError *err = NULL;

        // Warmup link
        if (self.provider) {

        }

        // 1. RSD via CoreDeviceProxy (iOS 17+)
        if (self.provider) {
            for (int i = 0; i < 8; i++) {
                if (err) { idevice_error_free(err); err = NULL; [NSThread sleepForTimeInterval:2.0]; }
                [self log:[NSString stringWithFormat:@"Connecting to CoreDeviceProxy (attempt %d)...", i+1]];
                err = core_device_proxy_connect(self.provider, &self->_proxy);
                if (!err) break;
            }

            if (!err && self->_proxy) {
                [self log:@"CoreDeviceProxy connected. Retrieving RSD port..."];
                uint16_t rsdPort = 0;
                err = core_device_proxy_get_server_rsd_port(self->_proxy, &rsdPort);
                if (!err && rsdPort != 0) {
                    err = core_device_proxy_create_tcp_adapter(self->_proxy, &self->_tunnelAdapter);
                    if (!err && self->_tunnelAdapter) {
                        self->_proxy = NULL; // Consumed
                        struct ReadWriteOpaque *rsdStream = NULL;
                        err = adapter_connect(self->_tunnelAdapter, rsdPort, &rsdStream);
                        if (!err && rsdStream) {
                            struct RsdHandshakeHandle *handshake = NULL;
                            err = rsd_handshake_new(rsdStream, &handshake);
                            if (!err && handshake) {
                                struct CRsdService *svc_info = NULL;
                                err = rsd_get_service_info(handshake, "com.apple.mobile.MCInstall.shim.remote", &svc_info);
                                if (!err && svc_info) {
                                    [self log:[NSString stringWithFormat:@"Found shim service on port %u", svc_info->port]];
                                    err = adapter_connect(self->_tunnelAdapter, svc_info->port, &self->_stream);
                                    rsd_free_service(svc_info);
                                }
                                rsd_handshake_free(handshake);
                            }
                        }
                    }
                }
            }
        }

        // 2. Legacy Lockdown
        if (!self->_stream && self.lockdown && self.provider) {
            if (err) { idevice_error_free(err); err = NULL; }
            if (self->_proxy) { core_device_proxy_free(self->_proxy); self->_proxy = NULL; }
            if (self->_tunnelAdapter) { adapter_free(self->_tunnelAdapter); self->_tunnelAdapter = NULL; }

            [self log:@"RSD unavailable. Trying legacy MCInstall service..."];
            uint16_t port = 0;
            err = lockdownd_start_service(self.lockdown, "com.apple.mobile.MCInstall", &port, NULL);
            if (!err) {
                // For TCP providers, standard service connect is preferred.
                    // We'll attempt a direct connection if the provider supports it.
                    [self log:@"Legacy path requires an AdapterHandle. WiFi targets should use RSD."];
                    err = NULL;
            }
            if (err) { idevice_error_free(err); err = NULL; }
        }

        if (self->_stream) {
            [self log:@"Stream established. Initializing session..."];
            [self _performSendRequest:@{@"RequestType": @"HelloHostIdentifier"} completion:^(BOOL success, id result, NSString *errorMsg) {
                self.connected = success;
                [[HeartbeatManager sharedManager] resumeHeartbeat];
                if (success) [self log:@"Session initialized."];
                else [self log:[NSString stringWithFormat:@"Handshake failed: %@", errorMsg]];
                if (completion) completion(success, result, errorMsg);
            }];
        } else {
            [[HeartbeatManager sharedManager] resumeHeartbeat];
            [self log:@"Failed to connect to MobileConfig service."];
            if (completion) completion(NO, nil, @"Connection failed");
        }
    });
}

#pragma mark - Plist Service Protocol (Internal)

- (void)_performSendRequest:(NSDictionary *)request completion:(MobileConfigCompletion)completion {
    if (!self->_stream) {
        if (completion) completion(NO, nil, @"Not connected");
        return;
    }

    NSError *error = nil;
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:request
                                                                   format:NSPropertyListXMLFormat_v1_0
                                                                  options:0
                                                                    error:&error];
    if (!plistData) {
        if (completion) completion(NO, nil, @"Serialization error");
        return;
    }

    struct AdapterStreamHandle *ash = (struct AdapterStreamHandle *)self->_stream;
    uint32_t len = CFSwapInt32HostToBig((uint32_t)plistData.length);

    struct IdeviceFfiError *err = NULL;
    NSDictionary *response = nil;

    // 3-attempt retry loop for transient WiFi errors
    for (int attempt = 0; attempt < 3; attempt++) {
        if (attempt > 0) [NSThread sleepForTimeInterval:0.5];

        err = adapter_send(ash, (const uint8_t *)&len, sizeof(len));
        if (err) { idevice_error_free(err); err = NULL; continue; }

        err = adapter_send(ash, (const uint8_t *)plistData.bytes, plistData.length);
        if (err) { idevice_error_free(err); err = NULL; continue; }

        uint32_t respLenBig = 0;
        uintptr_t readLen = 0;
        err = adapter_recv(ash, (uint8_t *)&respLenBig, &readLen, sizeof(respLenBig));
        if (err || readLen != sizeof(respLenBig)) { if (err) { idevice_error_free(err); err = NULL; } continue; }

        uint32_t respLen = CFSwapInt32BigToHost(respLenBig);
        if (respLen == 0 || respLen > 10 * 1024 * 1024) break;

        NSMutableData *respData = [NSMutableData dataWithLength:respLen];
        uintptr_t totalRead = 0;
        BOOL readFailed = NO;
        while (totalRead < respLen) {
            uintptr_t currentRead = 0;
            err = adapter_recv(ash, (uint8_t *)respData.mutableBytes + totalRead, &currentRead, respLen - totalRead);
            if (err || currentRead == 0) {
                if (err) { idevice_error_free(err); err = NULL; }
                readFailed = YES; break;
            }
            totalRead += currentRead;
        }
        if (readFailed) continue;

        response = [NSPropertyListSerialization propertyListWithData:respData options:NSPropertyListImmutable format:NULL error:NULL];
        if (response) break;
    }

    if (response) {
        if (completion) completion(YES, response, nil);
    } else {
        if (completion) completion(NO, nil, @"Link unstable");
    }
}

#pragma mark - Public Methods

- (void)sendRequest:(NSDictionary *)request completion:(MobileConfigCompletion)completion {
    dispatch_async(self.serviceQueue, ^{
        [[HeartbeatManager sharedManager] pauseHeartbeat];
        [self _performSendRequest:request completion:^(BOOL s, id r, NSString *e) {
            [[HeartbeatManager sharedManager] resumeHeartbeat];
            if (completion) completion(s, r, e);
        }];
    });
}

- (void)helloWithCompletion:(MobileConfigCompletion)completion {
    [self sendRequest:@{@"RequestType": @"HelloHostIdentifier"} completion:completion];
}

- (void)getProfileListWithCompletion:(MobileConfigCompletion)completion {
    [self sendRequest:@{@"RequestType": @"GetProfileList"} completion:completion];
}

- (void)installProfileWithData:(NSData *)profileData completion:(MobileConfigCompletion)completion {
    if (!profileData) { if (completion) completion(NO, nil, @"No data"); return; }
    [self sendRequest:@{@"RequestType": @"InstallProfile", @"Payload": profileData} completion:completion];
}

- (void)removeProfileWithIdentifier:(NSString *)identifier completion:(MobileConfigCompletion)completion {
    if (!identifier) { if (completion) completion(NO, nil, @"No ID"); return; }
    [self sendRequest:@{@"RequestType": @"RemoveProfile", @"Identifier": identifier} completion:completion];
}

- (void)getCloudConfigurationWithCompletion:(MobileConfigCompletion)completion {
    [self sendRequest:@{@"RequestType": @"GetCloudConfiguration"} completion:completion];
}

- (void)setWiFiPowerState:(BOOL)state completion:(MobileConfigCompletion)completion {
    [self sendRequest:@{@"RequestType": @"SetWiFiPowerState", @"PowerState": @(state)} completion:completion];
}

- (void)eraseDeviceWithPreserveDataPlan:(BOOL)preserve disallowProximity:(BOOL)disallow completion:(MobileConfigCompletion)completion {
    [self sendRequest:@{
        @"RequestType": @"EraseDevice",
        @"PreserveDataPlan": @(preserve),
        @"DisallowProximitySetup": @(disallow)
    } completion:completion];
}

- (void)escalateWithCertificate:(SecCertificateRef)cert privateKey:(SecKeyRef)key completion:(MobileConfigCompletion)completion {
    if (!cert || !key) { if (completion) completion(NO, nil, @"No cert/key"); return; }
    CFDataRef certData = SecCertificateCopyData(cert);
    if (!certData) { if (completion) completion(NO, nil, @"Cert error"); return; }
    NSData *certNSData = (__bridge_transfer NSData *)certData;

    dispatch_async(self.serviceQueue, ^{
        [[HeartbeatManager sharedManager] pauseHeartbeat];
        [self _performSendRequest:@{@"RequestType": @"Escalate", @"SupervisorCertificate": certNSData} completion:^(BOOL success, id result, NSString *error) {
            if (!success || ![result isKindOfClass:[NSDictionary class]]) {
                [[HeartbeatManager sharedManager] resumeHeartbeat];
                if (completion) completion(NO, nil, error ?: @"Invalid response");
                return;
            }

            NSData *challenge = result[@"Challenge"];
            if (![challenge isKindOfClass:[NSData class]]) {
                [[HeartbeatManager sharedManager] resumeHeartbeat];
                if (completion) completion(NO, nil, @"No challenge");
                return;
            }

            NSData *signedChallenge = [self signData:challenge certificate:cert privateKey:key];
            if (!signedChallenge) {
                [[HeartbeatManager sharedManager] resumeHeartbeat];
                if (completion) completion(NO, nil, @"Signing failed");
                return;
            }

            [self _performSendRequest:@{@"RequestType": @"EscalateResponse", @"SignedRequest": signedChallenge} completion:^(BOOL s2, id r2, NSString *e2) {
                if (!s2) {
                    [[HeartbeatManager sharedManager] resumeHeartbeat];
                    if (completion) completion(NO, nil, e2);
                    return;
                }
                [self _performSendRequest:@{@"RequestType": @"ProceedWithKeybagMigration"} completion:^(BOOL s3, id r3, NSString *e3) {
                    [[HeartbeatManager sharedManager] resumeHeartbeat];
                    if (completion) completion(s3, r3, e3);
                }];
            }];
        }];
    });
}

- (NSData *)signData:(NSData *)data certificate:(SecCertificateRef)cert privateKey:(SecKeyRef)key {
    if (!data || !key) return nil;
    CFErrorRef error = NULL;
    CFDataRef signature = SecKeyCreateSignature(key, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256, (__bridge CFDataRef)data, &error);
    if (error) {
        CFRelease(error);
        return nil;
    }
    return (__bridge_transfer NSData *)signature;
}

- (void)installRestrictionsProfileWithCompletion:(MobileConfigCompletion)completion {
    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSDictionary *payloadContent = @{
        @"PayloadDescription": @"Configures restrictions",
        @"PayloadDisplayName": @"Restrictions",
        @"PayloadIdentifier": [NSString stringWithFormat:@"com.apple.applicationaccess.%@", uuid],
        @"PayloadType": @"com.apple.applicationaccess",
        @"PayloadUUID": uuid,
        @"PayloadVersion": @1,
        @"allowActivityContinuation": @YES,
        @"allowAddingGameCenterFriends": @YES,
        @"allowAirPlayIncomingRequests": @YES,
        @"allowAirPrint": @YES,
        @"allowAirPrintCredentialsStorage": @YES,
        @"allowAirPrintiBeaconDiscovery": @YES,
        @"allowAppCellularDataModification": @YES,
        @"allowAppClips": @YES,
        @"allowAppInstallation": @YES,
        @"allowAppRemoval": @YES,
        @"allowApplePersonalizedAdvertising": @YES,
        @"allowAssistant": @YES,
        @"allowAssistantWhileLocked": @YES,
        @"allowAutoCorrection": @YES,
        @"allowAutoUnlock": @YES,
        @"allowAutomaticAppDownloads": @YES,
        @"allowBluetoothModification": @YES,
        @"allowBookstore": @YES,
        @"allowBookstoreErotica": @YES,
        @"allowCamera": @YES,
        @"allowCellularPlanModification": @YES,
        @"allowChat": @YES,
        @"allowCloudBackup": @YES,
        @"allowCloudDocumentSync": @YES,
        @"allowCloudPhotoLibrary": @YES,
        @"allowContinuousPathKeyboard": @YES,
        @"allowDefinitionLookup": @YES,
        @"allowDeviceNameModification": @YES,
        @"allowDeviceSleep": @YES,
        @"allowDictation": @YES,
        @"allowESIMModification": @YES,
        @"allowEnablingRestrictions": @YES,
        @"allowEnterpriseAppTrust": @YES,
        @"allowEnterpriseBookBackup": @YES,
        @"allowEnterpriseBookMetadataSync": @YES,
        @"allowEraseContentAndSettings": @YES,
        @"allowExplicitContent": @YES,
        @"allowFilesNetworkDriveAccess": @YES,
        @"allowFilesUSBDriveAccess": @YES,
        @"allowFindMyDevice": @YES,
        @"allowFindMyFriends": @YES,
        @"allowFingerprintForUnlock": @YES,
        @"allowFingerprintModification": @YES,
        @"allowGameCenter": @YES,
        @"allowGlobalBackgroundFetchWhenRoaming": @YES,
        @"allowInAppPurchases": @YES,
        @"allowKeyboardShortcuts": @YES,
        @"allowManagedAppsCloudSync": @YES,
        @"allowMultiplayerGaming": @YES,
        @"allowMusicService": @YES,
        @"allowNews": @YES,
        @"allowNotificationsModification": @YES,
        @"allowOpenFromManagedToUnmanaged": @YES,
        @"allowOpenFromUnmanagedToManaged": @YES,
        @"allowPairedWatch": @YES,
        @"allowPassbookWhileLocked": @YES,
        @"allowPasscodeModification": @YES,
        @"allowPasswordAutoFill": @YES,
        @"allowPasswordProximityRequests": @YES,
        @"allowPasswordSharing": @YES,
        @"allowPersonalHotspotModification": @YES,
        @"allowPhotoStream": @YES,
        @"allowPredictiveKeyboard": @YES,
        @"allowProximitySetupToNewDevice": @YES,
        @"allowRadioService": @YES,
        @"allowRemoteAppPairing": @YES,
        @"allowRemoteScreenObservation": @YES,
        @"allowSafari": @YES,
        @"allowScreenShot": @YES,
        @"allowSharedStream": @YES,
        @"allowSpellCheck": @YES,
        @"allowSpotlightInternetResults": @YES,
        @"allowSystemAppRemoval": @YES,
        @"allowUIAppInstallation": @YES,
        @"allowUIConfigurationProfileInstallation": @YES,
        @"allowUSBRestrictedMode": @YES,
        @"allowUnpairedExternalBootToRecovery": @NO,
        @"allowUntrustedTLSPrompt": @YES,
        @"allowVPNCreation": @YES,
        @"allowVideoConferencing": @YES,
        @"allowVoiceDialing": @YES,
        @"allowWallpaperModification": @YES,
        @"allowiTunes": @YES,
        @"enforcedSoftwareUpdateDelay": @0,
        @"forceAirDropUnmanaged": @NO,
        @"forceAirPrintTrustedTLSRequirement": @NO,
        @"forceAssistantProfanityFilter": @NO,
        @"forceAuthenticationBeforeAutoFill": @NO,
        @"forceAutomaticDateAndTime": @NO,
        @"forceClassroomAutomaticallyJoinClasses": @NO,
        @"forceClassroomRequestPermissionToLeaveClasses": @NO,
        @"forceClassroomUnpromptedAppAndDeviceLock": @NO,
        @"forceClassroomUnpromptedScreenObservation": @NO,
        @"forceDelayedSoftwareUpdates": @YES,
        @"forceEncryptedBackup": @NO,
        @"forceITunesStorePasswordEntry": @NO,
        @"forceLimitAdTracking": @NO,
        @"forceWatchWristDetection": @NO,
        @"forceWiFiPowerOn": @NO,
        @"forceWiFiWhitelisting": @NO,
        @"ratingApps": @1000,
        @"ratingMovies": @1000,
        @"ratingRegion": @"us",
        @"ratingTVShows": @1000,
        @"safariAcceptCookies": @2.0,
        @"safariAllowAutoFill": @YES,
        @"safariAllowJavaScript": @YES,
        @"safariAllowPopups": @YES,
        @"safariForceFraudWarning": @NO,
    };

    NSDictionary *profile = @{
        @"PayloadContent": @[payloadContent],
        @"PayloadDisplayName": @"Restrictions",
        @"PayloadIdentifier": uuid,
        @"PayloadRemovalDisallowed": @NO,
        @"PayloadType": @"Configuration",
        @"PayloadUUID": uuid,
        @"PayloadVersion": @1,
    };

    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:profile format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    if (!data) {
        if (completion) completion(NO, nil, @"Failed to build profile");
        return;
    }

    [self installProfileWithData:data completion:^(BOOL s, id r, NSString *e) { if (completion) completion(s, r, e); }];
}

@end
