#import "ZipManager.h"

@implementation ZipManager

+ (ArchiveFormat)formatForPath:(NSString *)path {
    NSString *ext = [path pathExtension].lowercaseString;
    if ([ext isEqualToString:@"zip"]) return ArchiveFormatZip;
    if ([ext isEqualToString:@"tar"]) return ArchiveFormatTar;
    if ([ext isEqualToString:@"gz"] || [ext isEqualToString:@"tgz"]) return ArchiveFormatGzip;
    if ([ext isEqualToString:@"7z"]) return ArchiveFormat7z;
    if ([ext isEqualToString:@"rar"]) return ArchiveFormatRar;
    return ArchiveFormatUnknown;
}

+ (BOOL)extractArchiveAtPath:(NSString *)archivePath toDestination:(NSString *)destPath password:(NSString *)password error:(NSError **)error {
    ArchiveFormat format = [self formatForPath:archivePath];
    NSString *cmd = nil;

    switch (format) {
        case ArchiveFormatZip:
            if (password && password.length > 0) {
                cmd = [NSString stringWithFormat:@"/usr/bin/unzip -P '%@' '%@' -d '%@'", password, archivePath, destPath];
            } else {
                cmd = [NSString stringWithFormat:@"/usr/bin/unzip '%@' -d '%@'", archivePath, destPath];
            }
            break;
        case ArchiveFormatTar:
            cmd = [NSString stringWithFormat:@"/usr/bin/tar -xf '%@' -C '%@'", archivePath, destPath];
            break;
        case ArchiveFormatGzip:
            cmd = [NSString stringWithFormat:@"/usr/bin/tar -xzf '%@' -C '%@'", archivePath, destPath];
            break;
        case ArchiveFormat7z:
            // Assuming 7z is available or symlinked
            cmd = [NSString stringWithFormat:@"/usr/bin/7z x '%@' -o'%@' -p'%@'", archivePath, destPath, password ?: @""];
            break;
        case ArchiveFormatRar:
            cmd = [NSString stringWithFormat:@"/usr/bin/unrar x '%@' '%@'", archivePath, destPath];
            break;
        default:
            if (error) *error = [NSError errorWithDomain:@"ArchiveManager" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Unsupported format"}];
            return NO;
    }

    int result = system([cmd UTF8String]);
    if (result != 0) {
        if (error) *error = [NSError errorWithDomain:@"ArchiveManager" code:result userInfo:@{NSLocalizedDescriptionKey: @"Extraction failed"}];
        return NO;
    }
    return YES;
}

+ (BOOL)compressFiles:(NSArray<NSString *> *)filePaths toPath:(NSString *)archivePath format:(ArchiveFormat)format password:(NSString *)password error:(NSError **)error {
    NSString *files = [filePaths componentsJoinedByString:@"' '"];
    NSString *cmd = nil;

    switch (format) {
        case ArchiveFormatZip:
            if (password && password.length > 0) {
                cmd = [NSString stringWithFormat:@"/usr/bin/zip -P '%@' '%@' '%@'", password, archivePath, files];
            } else {
                cmd = [NSString stringWithFormat:@"/usr/bin/zip '%@' '%@'", archivePath, files];
            }
            break;
        case ArchiveFormatTar:
            cmd = [NSString stringWithFormat:@"/usr/bin/tar -cf '%@' '%@'", archivePath, files];
            break;
        case ArchiveFormatGzip:
            cmd = [NSString stringWithFormat:@"/usr/bin/tar -czf '%@' '%@'", archivePath, files];
            break;
        case ArchiveFormat7z:
            cmd = [NSString stringWithFormat:@"/usr/bin/7z a '%@' '%@' -p'%@'", archivePath, files, password ?: @""];
            break;
        default:
            if (error) *error = [NSError errorWithDomain:@"ArchiveManager" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Unsupported format for compression"}];
            return NO;
    }

    int result = system([cmd UTF8String]);
    if (result != 0) {
        if (error) *error = [NSError errorWithDomain:@"ArchiveManager" code:result userInfo:@{NSLocalizedDescriptionKey: @"Compression failed"}];
        return NO;
    }
    return YES;
}

@end
