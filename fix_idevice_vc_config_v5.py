import sys

with open('IdeviceViewController.m', 'r') as f:
    content = f.read()

# Add escalate and certificate picker logic
escalate_logic = """\n
- (void)escalateSupervisor {\n
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"com.rsa.pkcs-12", @"public.item"] inMode:UIDocumentPickerModeImport];\n
    picker.delegate = (id<UIDocumentPickerDelegate>)self;\n
    picker.allowsMultipleSelection = NO;\n
    [self presentViewController:picker animated:YES completion:nil];\n
}\n
\n
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {\n
    NSURL *url = urls.firstObject;\n
    if (!url) return;\n
    \n
    NSData *p12Data = [NSData dataWithContentsOfURL:url];\n
    if (!p12Data) { [self log:@"Failed to read certificate"]; return; }\n
    \n
    [self ensureMobileConfig:^(BOOL success) {\n
        if (!success) return;\n
        \n
        // For simplicity in this UI, we assume a P12 with no password or prompt the user.\n
        // In a real app, we would show a password dialog.\n
        NSDictionary *options = @{(__bridge id)kSecImportExportPassphrase: @""};\n
        CFArrayRef items = NULL;\n
        OSStatus status = SecPKCS12Import((__bridge CFDataRef)p12Data, (__bridge CFDictionaryRef)options, &items);\n
        \n
        if (status == errSecSuccess && CFArrayGetCount(items) > 0) {\n
            NSDictionary *identityDict = (__bridge NSDictionary *)CFArrayGetValueAtIndex(items, 0);\n
            SecIdentityRef identity = (__bridge SecIdentityRef)identityDict[(__bridge id)kSecImportItemIdentity];\n
            SecCertificateRef cert = NULL;\n
            SecKeyRef key = NULL;\n
            SecIdentityCopyCertificate(identity, &cert);\n
            SecIdentityCopyPrivateKey(identity, &key);\n
            \n
            [self.mobileConfig escalateWithCertificate:cert privateKey:key completion:^(BOOL s, id res, NSString *err) {\n
                dispatch_async(dispatch_get_main_queue(), ^{\n
                    if (s) [self log:@"Escalation successful!"];\n
                    else [self log:[NSString stringWithFormat:@"Escalation failed: %@", err]];\n
                    if (cert) CFRelease(cert);\n
                    if (key) CFRelease(key);\n
                });\n
            }];\n
            CFRelease(items);\n
        } else {\n
            [self log:[NSString stringWithFormat:@"P12 Import failed: %d", (int)status]];\n
        }\n
    }];\n
}\n
"""

# Append before the last @end
last_end_index = content.rfind('@end')
content = content[:last_end_index] + escalate_logic + content[last_end_index:]

# Add Escalate button to UI
content = content.replace('    [mcCard.heightAnchor constraintEqualToConstant:100].active = YES;',
                          '    UIButton *escBtn = [UIButton buttonWithType:UIButtonTypeSystem];\n    [escBtn setTitle:@"ESCALATE" forState:UIControlStateNormal];\n    escBtn.frame = CGRectMake(20, 85, 120, 35);\n    [escBtn addTarget:self action:@selector(escalateSupervisor) forControlEvents:UIControlEventTouchUpInside];\n    [mcCard addSubview:escBtn];\n\n    [mcCard.heightAnchor constraintEqualToConstant:130].active = YES;')

with open('IdeviceViewController.m', 'w') as f:
    f.write(content)
