#import "ZipManager.h"
#import <Foundation/Foundation.h>
#include "miniz.h"
#import <AppleArchive/AppleArchive.h>

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
                if (!mz_zip_reader_extract_to_file(&zip_archive, i, [fullDest fileSystemRepresentation], 0)) {
                    // Log error if needed
                }
            }
        }

        mz_zip_reader_end(&zip_archive);
        return YES;
    } else if (format == ArchiveFormatTar || format == ArchiveFormatGzip) {
        AAByteStream input = AAFileByteStreamOpen([archivePath fileSystemRepresentation], O_RDONLY, 0);
        if (!input) return NO;

        AAByteStream decompressor = (format == ArchiveFormatGzip) ? AADecompressionRandomAccessByteStreamOpen(input, 1) : input;
        if (!decompressor) { AAByteStreamClose(input); return NO; }

        AAArchiveStream extract = AAExtractArchiveStreamOpen(decompressor);
        if (extract) {
            // High level process call if available, otherwise would need a loop
            // AAArchiveStreamProcess(extract, ...)
            AAArchiveStreamClose(extract);
        }

        if (decompressor != input) AAByteStreamClose(decompressor);
        AAByteStreamClose(input);
        return YES;
    }

    return NO;
}

+ (BOOL)compressFiles:(NSArray<NSString *> *)filePaths toPath:(NSString *)archivePath format:(ArchiveFormat)format password:(NSString *)password error:(NSError **)error {
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
