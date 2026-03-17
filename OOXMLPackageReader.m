#import "OOXMLPackageReader.h"
#include "miniz.h"

@implementation OOXMLPackageReader

+ (NSArray<NSString *> *)entryNamesInZipAtPath:(NSString *)zipPath {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    mz_zip_archive zip;
    memset(&zip, 0, sizeof(zip));

    if (!mz_zip_reader_init_file(&zip, [zipPath fileSystemRepresentation], 0)) {
        return names;
    }

    mz_uint count = mz_zip_reader_get_num_files(&zip);
    for (mz_uint i = 0; i < count; i++) {
        mz_zip_archive_file_stat stat;
        if (!mz_zip_reader_file_stat(&zip, i, &stat)) continue;
        if (!stat.m_filename) continue;
        NSString *name = [NSString stringWithUTF8String:stat.m_filename];
        if (name.length > 0) [names addObject:name];
    }

    mz_zip_reader_end(&zip);
    return names;
}

+ (NSData *)dataForEntry:(NSString *)entryPath inZipAtPath:(NSString *)zipPath {
    if (entryPath.length == 0 || zipPath.length == 0) return nil;
    size_t size = 0;
    void *data = mz_zip_extract_archive_file_to_heap([zipPath fileSystemRepresentation], [entryPath UTF8String], &size, 0);
    if (!data || size == 0) {
        if (data) mz_free(data);
        return nil;
    }

    NSData *result = [NSData dataWithBytes:data length:size];
    mz_free(data);
    return result;
}


+ (BOOL)hasVBAMacroProjectInZipAtPath:(NSString *)zipPath {
    NSArray<NSString *> *entries = [self entryNamesInZipAtPath:zipPath];
    for (NSString *entry in entries) {
        NSString *lower = entry.lowercaseString;
        if ([lower hasSuffix:@"vbaproject.bin"] || [lower containsString:@"/vba/"]) return YES;
    }
    return NO;
}

+ (NSArray<NSString *> *)vbaRelatedEntryNamesInZipAtPath:(NSString *)zipPath {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSArray<NSString *> *entries = [self entryNamesInZipAtPath:zipPath];
    for (NSString *entry in entries) {
        NSString *lower = entry.lowercaseString;
        if ([lower hasSuffix:@"vbaproject.bin"] ||
            [lower hasSuffix:@"vbaprojectsignature.bin"] ||
            [lower containsString:@"/vba/"] ||
            [lower hasSuffix:@"macrosheets/sheet1.xml"] ||
            [lower containsString:@"macrosheet"] ||
            [lower containsString:@"dialogsheet"]) {
            [parts addObject:entry];
        }
    }
    return parts;
}

@end
