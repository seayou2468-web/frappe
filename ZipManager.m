#import "ZipManager.h"
// In a real scenario, we would link libarchive or minizip.
// Since we are restricted to system frameworks and no external dependencies,
// we will use the 'Compression' framework for basic compression,
// but for ZIP with password, we might need to use private APIs or system() calls if possible.
// For the sake of this task, I will implement a wrapper that suggests libarchive usage.

@implementation ZipManager

+ (BOOL)unzipFileAtPath:(NSString *)zipPath toDestination:(NSString *)destPath password:(NSString *)password error:(NSError **)error {
    // Implementation would use libarchive or similar system C library.
    // For now, let's use a simple system() call as a placeholder,
    // which is common in non-AppStore tools.

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
