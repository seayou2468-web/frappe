#import "ZipManager.h"
#import <Foundation/Foundation.h>
#include "miniz.h"

@implementation ZipManager

+ (ArchiveFormat)formatForPath:(NSString *)path {
    NSString *ext = [path pathExtension].lowercaseString;
    if ([ext isEqualToString:@"zip"]) return ArchiveFormatZip;
    return ArchiveFormatUnknown;
}

+ (BOOL)extractArchiveAtPath:(NSString *)archivePath toDestination:(NSString *)destPath password:(NSString *)password error:(NSError **)error {
    mz_zip_archive zip_archive;
    memset(&zip_archive, 0, sizeof(zip_archive));

    if (!mz_zip_reader_init_file(&zip_archive, [archivePath fileSystemRepresentation], 0)) {
        if (error) *error = [NSError errorWithDomain:@"ZipManager" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to open ZIP"}];
        return NO;
    }

    mz_uint num_files = mz_zip_reader_get_num_files(&zip_archive);
    for (mz_uint i = 0; i < num_files; i++) {
        mz_zip_archive_file_stat file_stat;
        if (!mz_zip_reader_file_stat(&zip_archive, i, &file_stat)) continue;

        NSString *fileName = [NSString stringWithUTF8String:file_stat.m_filename];
        NSString *fullDest = [destPath stringByAppendingPathComponent:fileName];

        if (mz_zip_reader_is_file_a_directory(&zip_archive, i)) {
            [[NSFileManager defaultManager] createDirectoryAtPath:fullDest withIntermediateDirectories:YES attributes:nil error:nil];
        } else {
            [[NSFileManager defaultManager] createDirectoryAtPath:[fullDest stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
            if (!mz_zip_reader_extract_to_file(&zip_archive, i, [fullDest fileSystemRepresentation], 0)) {
                // Extraction failed
            }
        }
    }

    mz_zip_reader_end(&zip_archive);
    return YES;
}

+ (BOOL)compressFiles:(NSArray<NSString *> *)filePaths toPath:(NSString *)archivePath format:(ArchiveFormat)format password:(NSString *)password error:(NSError **)error {
    if (format != ArchiveFormatZip) return NO;

    mz_zip_archive zip_archive;
    memset(&zip_archive, 0, sizeof(zip_archive));

    if (!mz_zip_writer_init_file(&zip_archive, [archivePath fileSystemRepresentation], 0)) {
        if (error) *error = [NSError errorWithDomain:@"ZipManager" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create ZIP"}];
        return NO;
    }

    for (NSString *path in filePaths) {
        [self addPath:path toZip:&zip_archive baseDir:[path stringByDeletingLastPathComponent]];
    }

    if (!mz_zip_writer_finalize_archive(&zip_archive)) {
        if (error) *error = [NSError errorWithDomain:@"ZipManager" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to finalize ZIP"}];
        mz_zip_writer_end(&zip_archive);
        return NO;
    }

    mz_zip_writer_end(&zip_archive);
    return YES;
}

+ (void)addPath:(NSString *)path toZip:(mz_zip_archive *)pZip baseDir:(NSString *)baseDir {
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir]) return;

    NSString *relativeName = [path substringFromIndex:baseDir.length];
    if ([relativeName hasPrefix:@"/"]) relativeName = [relativeName substringFromIndex:1];

    if (isDir) {
        if (![relativeName hasSuffix:@"/"]) relativeName = [relativeName stringByAppendingString:@"/"];
        mz_zip_writer_add_mem(pZip, [relativeName UTF8String], NULL, 0, MZ_DEFAULT_COMPRESSION);

        NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil];
        for (NSString *sub in contents) {
            [self addPath:[path stringByAppendingPathComponent:sub] toZip:pZip baseDir:baseDir];
        }
    } else {
        mz_zip_writer_add_file(pZip, [relativeName UTF8String], [path fileSystemRepresentation], NULL, 0, MZ_DEFAULT_COMPRESSION);
    }
}

@end
