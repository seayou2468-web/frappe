#import "ZipManager.h"

@implementation ZipManager

+ (BOOL)isEncrypted:(NSString *)path {
    // Basic check: try to unzip -l and see if it asks for pass
    // Or just assume it might be and let the unzip command fail
    return YES; // Better to always ask if uncertain or check headers
}

+ (BOOL)unzipFileAtPath:(NSString *)zipPath toDestination:(NSString *)destPath password:(NSString *)password error:(NSError **)error {
    NSString *cmd;
    if (password && password.length > 0) {
        cmd = [NSString stringWithFormat:@"/usr/bin/unzip -P '%@' '%@' -d '%@'", password, zipPath, destPath];
    } else {
        cmd = [NSString stringWithFormat:@"/usr/bin/unzip '%@' -d '%@'", zipPath, destPath];
    }

    int result = system([cmd UTF8String]);
    if (result != 0) {
        if (error) *error = [NSError errorWithDomain:@"ZipManager" code:result userInfo:@{NSLocalizedDescriptionKey: @"Unzip failed"}];
        return NO;
    }
    return YES;
}

+ (BOOL)zipFiles:(NSArray<NSString *> *)filePaths toPath:(NSString *)zipPath password:(NSString *)password error:(NSError **)error {
    NSString *files = [filePaths componentsJoinedByString:@"' '"];
    NSString *cmd;
    if (password && password.length > 0) {
        cmd = [NSString stringWithFormat:@"/usr/bin/zip -P '%@' '%@' '%@'", password, zipPath, files];
    } else {
        cmd = [NSString stringWithFormat:@"/usr/bin/zip '%@' '%@'", zipPath, files];
    }

    int result = system([cmd UTF8String]);
    if (result != 0) {
        if (error) *error = [NSError errorWithDomain:@"ZipManager" code:result userInfo:@{NSLocalizedDescriptionKey: @"Zip failed"}];
        return NO;
    }
    return YES;
}

@end
