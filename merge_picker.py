import sys

with open('IdeviceViewController.m', 'r') as f:
    content = f.read()

# We have two documentPicker:didPickDocumentsAtURLs:
# One is the original for pairing files, the other is for supervisor certificates.

original_picker = """- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject; if (!url) return;
    [self log:@"Importing device identity..."];
    BOOL access = [url startAccessingSecurityScopedResource];
    NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *pairingDir = [docsDir stringByAppendingPathComponent:@"PairingFiles"];
    [[NSFileManager defaultManager] createDirectoryAtPath:pairingDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *targetFilename = @"pairfile.plist";
    NSString *destPath = [pairingDir stringByAppendingPathComponent:targetFilename];
    if ([[NSFileManager defaultManager] fileExistsAtPath:destPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
    }
    NSError *error = nil;
    if ([[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:destPath] error:&error]) {
        self.selectedPairingFilePath = destPath;
        self.pairingFileLabel.text = @"CONFIGURED: pairfile.plist";
        self.pairingFileLabel.textColor = [UIColor systemGreenColor];
        [self log:@"Identity imported successfully."];
    } else {
        [self log:[NSString stringWithFormat:@"Import failed: %@", error.localizedDescription]];
    }
    if (access) [url stopAccessingSecurityScopedResource];
}"""

# Actually, the original one might be slightly different in the file now.
# Let's find the start of both.

import re

pickers = list(re.finditer(r'- \(void\)documentPicker:\(UIDocumentPickerViewController \*\)controller didPickDocumentsAtURLs:\(NSArray<NSURL \*> \*\)urls \{', content))

if len(pickers) >= 2:
    # Merge them. We can use the controller's tag or just check what's being picked.
    # But wait, controller doesn't have a tag easily usable here without subclasses.
    # We can check the document types or just try to handle both.

    merged_picker = """- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject; if (!url) return;

    // Check if it's a P12 or a Plist
    NSString *ext = [url pathExtension].lowercaseString;
    if ([ext isEqualToString:@"p12"] || [ext isEqualToString:@"pfx"]) {
        [self handleSupervisorCertPick:url];
    } else {
        [self handlePairingFilePick:url];
    }
}

- (void)handlePairingFilePick:(NSURL *)url {
    [self log:@"Importing device identity..."];
    BOOL access = [url startAccessingSecurityScopedResource];
    NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *pairingDir = [docsDir stringByAppendingPathComponent:@"PairingFiles"];
    [[NSFileManager defaultManager] createDirectoryAtPath:pairingDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *targetFilename = @"pairfile.plist";
    NSString *destPath = [pairingDir stringByAppendingPathComponent:targetFilename];
    if ([[NSFileManager defaultManager] fileExistsAtPath:destPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
    }
    NSError *error = nil;
    if ([[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:destPath] error:&error]) {
        self.selectedPairingFilePath = destPath;
        self.pairingFileLabel.text = @"CONFIGURED: pairfile.plist";
        self.pairingFileLabel.textColor = [UIColor systemGreenColor];
        [self log:@"Identity imported successfully."];
    } else {
        [self log:[NSString stringWithFormat:@"Import failed: %@", error.localizedDescription]];
    }
    if (access) [url stopAccessingSecurityScopedResource];
}

- (void)handleSupervisorCertPick:(NSURL *)url {
    NSData *p12Data = [NSData dataWithContentsOfURL:url];
    if (!p12Data) { [self log:@"Failed to read certificate"]; return; }

    [self ensureMobileConfig:^(BOOL success) {
        if (!success) return;

        NSDictionary *options = @{(__bridge id)kSecImportExportPassphrase: @""};
        CFArrayRef items = NULL;
        OSStatus status = SecPKCS12Import((__bridge CFDataRef)p12Data, (__bridge CFDictionaryRef)options, &items);

        if (status == errSecSuccess && CFArrayGetCount(items) > 0) {
            NSDictionary *identityDict = (__bridge NSDictionary *)CFArrayGetValueAtIndex(items, 0);
            SecIdentityRef identity = (__bridge SecIdentityRef)identityDict[(__bridge id)kSecImportItemIdentity];
            SecCertificateRef cert = NULL;
            SecKeyRef key = NULL;
            SecIdentityCopyCertificate(identity, &cert);
            SecIdentityCopyPrivateKey(identity, &key);

            [self.mobileConfig escalateWithCertificate:cert privateKey:key completion:^(BOOL s, id res, NSString *err) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (s) [self log:@"Escalation successful!"];
                    else [self log:[NSString stringWithFormat:@"Escalation failed: %@", err]];
                    if (cert) CFRelease(cert);
                    if (key) CFRelease(key);
                });
            }];
            CFRelease(items);
        } else {
            [self log:[NSString stringWithFormat:@"P12 Import failed: %d", (int)status]];
        }
    }];
}"""

    # Remove the second one entirely and replace the first one.
    first_start = pickers[0].start()
    second_start = pickers[1].start()

    # Find end of second one
    # This is tricky, let's just find the last } before @end that belongs to it.
    # Actually, I'll just rebuild the file from parts.

    # Let's find the first one's end
    first_end = content.find('}', first_start)
    # Match braces to find the real end
    stack = 1
    i = first_start + content[first_start:].find('{') + 1
    while stack > 0 and i < len(content):
        if content[i] == '{': stack += 1
        elif content[i] == '}': stack -= 1
        i += 1
    first_end = i

    # Second one
    second_end = content.find('}', second_start)
    stack = 1
    i = second_start + content[second_start:].find('{') + 1
    while stack > 0 and i < len(content):
        if content[i] == '{': stack += 1
        elif content[i] == '}': stack -= 1
        i += 1
    second_end = i

    new_content = content[:first_start] + merged_picker + content[first_end:second_start] + content[second_end:]

    with open('IdeviceViewController.m', 'w') as f:
        f.write(new_content)
    print("Successfully merged pickers")
else:
    print("Could not find two pickers")
