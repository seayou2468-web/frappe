import sys

with open('IdeviceViewController.m', 'r') as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    if '#import "LocationSimulationViewController.h"' in line:
        new_lines.append(line)
        new_lines.append('#import "MobileConfigService.h"\n')
        new_lines.append('#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>\n')
    elif '@property (nonatomic, assign) struct LockdowndClientHandle *currentLockdown;' in line:
        new_lines.append(line)
        new_lines.append('@property (nonatomic, strong) MobileConfigService *mobileConfig;\n')
    elif '[self.mainStack addArrangedSubview:self.retryButton];' in line:
        new_lines.append(line)
        new_lines.append('    [self setupMobileConfigUI];\n')
    else:
        new_lines.append(line)

# Add implementation methods at the end before @end
final_lines = []
for line in new_lines:
    if line.strip() == '@end' and 'implementation IdeviceViewController' in "".join(final_lines[-500:]):
        final_lines.append('\n'
            '- (void)setupMobileConfigUI {\n'
            '    UIView *mcCard = [[UIView alloc] init];\n'
            '    [ThemeEngine applyGlassStyleToView:mcCard cornerRadius:25];\n'
            '    [self.mainStack addArrangedSubview:mcCard];\n'
            '\n'
            '    UILabel *mcHeader = [[UILabel alloc] initWithFrame:CGRectMake(20, 15, 200, 20)];\n'
            '    mcHeader.text = @"MOBILE_CONFIG"; mcHeader.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5]; mcHeader.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];\n'
            '    [mcCard addSubview:mcHeader];\n'
            '\n'
            '    UIButton *listBtn = [UIButton buttonWithType:UIButtonTypeSystem];\n'
            '    [listBtn setTitle:@"LIST PROFILES" forState:UIControlStateNormal];\n'
            '    listBtn.frame = CGRectMake(20, 45, 120, 35);\n'
            '    [listBtn addTarget:self action:@selector(listProfiles) forControlEvents:UIControlEventTouchUpInside];\n'
            '    [mcCard addSubview:listBtn];\n'
            '\n'
            '    UIButton *restrBtn = [UIButton buttonWithType:UIButtonTypeSystem];\n'
            '    [restrBtn setTitle:@"RESTRICTIONS" forState:UIControlStateNormal];\n'
            '    restrBtn.frame = CGRectMake(150, 45, 120, 35);\n'
            '    [restrBtn addTarget:self action:@selector(installRestrictions) forControlEvents:UIControlEventTouchUpInside];\n'
            '    [mcCard addSubview:restrBtn];\n'
            '\n'
            '    [mcCard.heightAnchor constraintEqualToConstant:100].active = YES;\n'
            '}\n'
            '\n'
            '- (void)listProfiles {\n'
            '    [self ensureMobileConfig:^(BOOL success) {\n'
            '        if (!success) return;\n'
            '        [self.mobileConfig getProfileListWithCompletion:^(BOOL s, id res, NSString *err) {\n'
            '            dispatch_async(dispatch_get_main_queue(), ^{\n'
            '                if (s) {\n'
            '                    [self log:[NSString stringWithFormat:@"Profiles: %@", res]];\n'
            '                } else {\n'
            '                    [self log:[NSString stringWithFormat:@"List failed: %@", err]];\n'
            '                }\n'
            '            });\n'
            '        }];\n'
            '    }];\n'
            '}\n'
            '\n'
            '- (void)installRestrictions {\n'
            '    [self ensureMobileConfig:^(BOOL success) {\n'
            '        if (!success) return;\n'
            '        [self.mobileConfig installRestrictionsProfileWithCompletion:^(BOOL s, id res, NSString *err) {\n'
            '            dispatch_async(dispatch_get_main_queue(), ^{\n'
            '                if (s) {\n'
            '                    [self log:@"Restrictions profile installed"];\n'
            '                } else {\n'
            '                    [self log:[NSString stringWithFormat:@"Failed: %@", err]];\n'
            '                }\n'
            '            });\n'
            '        }];\n'
            '    }];\n'
            '}\n'
            '\n'
            '- (void)ensureMobileConfig:(void(^)(BOOL))completion {\n'
            '    if (self.mobileConfig) { completion(YES); return; }\n'
            '    if (!self.currentProvider) { [self log:@"No device connected"]; completion(NO); return; }\n'
            '\n'
            '    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{\n'
            '        struct RsdHandshakeHandle *handshake = NULL;\n'
            '        uint16_t port = 0;\n'
            '        struct ReadWriteOpaque *stream = NULL;\n'
            '\n'
            '        // Try RSD first (iOS 17+)\n'
            '        struct IdeviceFfiError *err = idevice_rsd_checkin_provider(self.currentProvider, &handshake);\n'
            '        if (!err) {\n'
            '            struct CRsdService *svc = NULL;\n'
            '            err = rsd_get_service_info(handshake, "com.apple.mobile.MCInstall.shim.remote", &svc);\n'
            '            if (!err && svc) {\n'
            '                port = svc->port;\n'
            '                rsd_free_service(svc);\n'
            '                err = adapter_connect(self.currentProvider, port, &stream);\n'
            '            }\n'
            '            rsd_handshake_free(handshake);\n'
            '        }\n'
            '\n'
            '        if (err || !stream) {\n'
            '            if (err) idevice_error_free(err);\n'
            '            // Fallback to legacy lockdown\n'
            '            if (self.currentLockdown) {\n'
            '                err = lockdownd_start_service(self.currentLockdown, "com.apple.mobile.MCInstall", &port, NULL);\n'
            '                if (!err) {\n'
            '                    err = adapter_connect(self.currentProvider, port, &stream);\n'
            '                }\n'
            '                if (err) idevice_error_free(err);\n'
            '            }\n'
            '        }\n'
            '\n'
            '        dispatch_async(dispatch_get_main_queue(), ^{\n'
            '            if (stream) {\n'
            '                self.mobileConfig = [[MobileConfigService alloc] initWithStream:stream];\n'
            '                completion(YES);\n'
            '            } else {\n'
            '                [self log:@"Failed to connect to MobileConfig service"];\n'
            '                completion(NO);\n'
            '            }\n'
            '        });\n'
            '    });\n'
            '}\n'
        )
        final_lines.append(line)
    else:
        final_lines.append(line)

with open('IdeviceViewController.m', 'w') as f:
    f.writelines(final_lines)
