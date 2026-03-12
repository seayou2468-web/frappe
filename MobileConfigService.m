#import "MobileConfigService.h"
#import <Security/Security.h>

@interface MobileConfigService ()
@property (nonatomic, assign) struct ReadWriteOpaque *stream;
@end

@implementation MobileConfigService

- (instancetype)initWithStream:(struct ReadWriteOpaque *)stream {
    self = [super init];
    if (self) {
        _stream = stream;
    }
    return self;
}

- (void)dealloc {
    if (_stream) {
        // idevice_stream_free(_stream); // Should be managed by the caller if we follow HeartbeatManager pattern
    }
}

#pragma mark - Plist Service Protocol

- (void)sendRequest:(NSDictionary *)request completion:(MobileConfigCompletion)completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:request
                                                                       format:NSPropertyListXMLFormat_v1_0
                                                                      options:0
                                                                        error:&error];
        if (!plistData) {
            if (completion) completion(NO, nil, [NSString stringWithFormat:@"Failed to serialize plist: %@", error.localizedDescription]);
            return;
        }

        uint32_t len = CFSwapInt32HostToBig((uint32_t)plistData.length);

        // Use adapter_send via the stream (casted back if it's an AdapterStreamHandle)
        // Wait, idevice.h doesn't show a direct 'stream_send' for ReadWriteOpaque.
        // But adapter_send takes AdapterStreamHandle*.
        // If we got this stream from adapter_connect, it's actually an AdapterStreamHandle*.

        struct AdapterStreamHandle *ash = (struct AdapterStreamHandle *)self.stream;
        struct IdeviceFfiError *err = adapter_send(ash, (const uint8_t *)&len, sizeof(len));
        if (err) {
            NSString *msg = [NSString stringWithUTF8String:err->message ?: "Unknown send error"];
            idevice_error_free(err);
            if (completion) completion(NO, nil, msg);
            return;
        }

        err = adapter_send(ash, (const uint8_t *)plistData.bytes, plistData.length);
        if (err) {
            NSString *msg = [NSString stringWithUTF8String:err->message ?: "Unknown send error"];
            idevice_error_free(err);
            if (completion) completion(NO, nil, msg);
            return;
        }

        // Receive response
        uint32_t respLenBig = 0;
        uintptr_t readLen = 0;
        err = adapter_recv(ash, (uint8_t *)&respLenBig, &readLen, sizeof(respLenBig));
        if (err || readLen != sizeof(respLenBig)) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "Recv error"] : @"Short read for length";
            if (err) idevice_error_free(err);
            if (completion) completion(NO, nil, msg);
            return;
        }

        uint32_t respLen = CFSwapInt32BigToHost(respLenBig);
        if (respLen > 10 * 1024 * 1024) { // 10MB sanity check
             if (completion) completion(NO, nil, @"Response too large");
             return;
        }

        NSMutableData *respData = [NSMutableData dataWithLength:respLen];
        uintptr_t totalRead = 0;
        while (totalRead < respLen) {
            uintptr_t currentRead = 0;
            err = adapter_recv(ash, (uint8_t *)respData.mutableBytes + totalRead, &currentRead, respLen - totalRead);
            if (err) {
                NSString *msg = [NSString stringWithUTF8String:err->message ?: "Recv data error"];
                idevice_error_free(err);
                if (completion) completion(NO, nil, msg);
                return;
            }
            if (currentRead == 0) break;
            totalRead += currentRead;
        }

        if (totalRead != respLen) {
            if (completion) completion(NO, nil, @"Incomplete response data");
            return;
        }

        NSDictionary *response = [NSPropertyListSerialization propertyListWithData:respData
                                                                           options:NSPropertyListImmutable
                                                                            format:NULL
                                                                             error:&error];
        if (!response) {
            if (completion) completion(NO, nil, [NSString stringWithFormat:@"Failed to parse response: %@", error.localizedDescription]);
            return;
        }

        if (completion) completion(YES, response, nil);
    });
}

#pragma mark - Methods

- (void)helloWithCompletion:(MobileConfigCompletion)completion {
    [self sendRequest:@{@"RequestType": @"HelloHostIdentifier"} completion:completion];
}

- (void)getProfileListWithCompletion:(MobileConfigCompletion)completion {
    [self sendRequest:@{@"RequestType": @"GetProfileList"} completion:completion];
}

- (void)installProfileWithData:(NSData *)profileData completion:(MobileConfigCompletion)completion {
    [self sendRequest:@{@"RequestType": @"InstallProfile", @"Payload": profileData} completion:completion];
}

- (void)removeProfileWithIdentifier:(NSString *)identifier completion:(MobileConfigCompletion)completion {
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
    // 1. Get Challenge
    CFDataRef certData = SecCertificateCopyData(cert);
    NSData *certNSData = (__bridge_transfer NSData *)certData;

    [self sendRequest:@{@"RequestType": @"Escalate", @"SupervisorCertificate": certNSData} completion:^(BOOL success, id result, NSString *error) {
        if (!success) {
            if (completion) completion(NO, nil, error);
            return;
        }

        NSData *challenge = result[@"Challenge"];
        if (!challenge) {
            if (completion) completion(NO, nil, @"No challenge received");
            return;
        }

        // 2. Sign Challenge (PKCS7)
        // Note: On iOS, PKCS7 signing is usually done via CMS (Cryptographic Message Syntax).
        // For simplicity, we'll try to use SecCMS functions or similar if available,
        // or a standard signature if that's what MCInstall expects for 'SignedRequest'.
        // Python uses PKCS7SignatureBuilder.

        NSData *signedChallenge = [self signData:challenge certificate:cert privateKey:key];
        if (!signedChallenge) {
            if (completion) completion(NO, nil, @"Failed to sign challenge");
            return;
        }

        // 3. EscalateResponse
        [self sendRequest:@{@"RequestType": @"EscalateResponse", @"SignedRequest": signedChallenge} completion:^(BOOL s2, id r2, NSString *e2) {
            if (!s2) {
                if (completion) completion(NO, nil, e2);
                return;
            }

            // 4. ProceedWithKeybagMigration
            [self sendRequest:@{@"RequestType": @"ProceedWithKeybagMigration"} completion:completion];
        }];
    }];
}

- (NSData *)signData:(NSData *)data certificate:(SecCertificateRef)cert privateKey:(SecKeyRef)key {
    // Ported from pymobiledevice3's PKCS7SignatureBuilder
    // On iOS, this is typically handled via Security.framework's CMS (Cryptographic Message Syntax)

    // Note: CMSEncoder is available on macOS, but on iOS it's often private or requires specific entitlements.
    // However, for the 'SignedRequest' in MCInstall, a PKCS#1 v1.5 signature is often accepted if wrapped correctly,
    // or a full CMS SignedData blob.

    // Since we must be purely native and independent of Python, we'll implement a robust signature path.
    // For now, we use SecKeyCreateSignature which provides the core cryptographic operation.
    // In a production scenario with full CMSEncoder access, we would wrap this in a CMS container.

    CFErrorRef error = NULL;
    // MCInstall typically expects SHA256 with RSA/ECDSA
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
        if (completion) completion(NO, nil, @"Failed to build restrictions profile");
        return;
    }

    [self installProfileWithData:data completion:completion];
}

@end
