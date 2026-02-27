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
    ArchiveFormat format = [self formatForPath:archivePath];

    if (format == ArchiveFormatZip) {
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
                mz_zip_reader_extract_to_file(&zip_archive, i, [fullDest fileSystemRepresentation], 0);
            }
        }

        mz_zip_reader_end(&zip_archive);
        return YES;
    }

    return NO;
}

+ (BOOL)compressFiles:(NSArray *)filePaths toPath:(NSString *)archivePath format:(ArchiveFormat)format password:(NSString *)password error:(NSError **)error {
    if (format == ArchiveFormatZip) {
        mz_zip_archive zip_archive;
        memset(&zip_archive, 0, sizeof(zip_archive));

        if (!mz_zip_writer_init_file(&zip_archive, [archivePath fileSystemRepresentation], 0)) {
            return NO;
        }

        for (NSString *path in filePaths) {
            mz_zip_writer_add_file(&zip_archive, [path lastPathComponent].UTF8String, [path fileSystemRepresentation], NULL, 0, MZ_DEFAULT_COMPRESSION);
        }

        mz_zip_writer_finalize_archive(&zip_archive);
        mz_zip_writer_end(&zip_archive);
        return YES;
    }
    return NO;
}

@end
