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

        uint32_t num_files = mz_zip_reader_get_num_files(&zip_archive);
        for (uint32_t i = 0; i < num_files; i++) {
            char filename[1024];
            mz_zip_reader_get_filename(&zip_archive, i, filename, sizeof(filename));

            NSString *fullDest = [destPath stringByAppendingPathComponent:[NSString stringWithUTF8String:filename]];
            if (mz_zip_reader_is_file_a_directory(&zip_archive, i)) {
                [[NSFileManager defaultManager] createDirectoryAtPath:fullDest withIntermediateDirectories:YES attributes:nil error:nil];
            } else {
                [[NSFileManager defaultManager] createDirectoryAtPath:[fullDest stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
                mz_zip_reader_extract_to_file(&zip_archive, i, [fullDest fileSystemRepresentation], 0);
            }
        }

        mz_zip_reader_end(&zip_archive);
        return YES;
    } else if (format == ArchiveFormatTar || format == ArchiveFormatGzip) {
        // Fallback to AppleArchive for TAR/GZ as it's built-in
        AAByteStream input = AAFileByteStreamOpen([archivePath fileSystemRepresentation], O_RDONLY, 0);
        if (!input) return NO;

        AAByteStream decompressor = (format == ArchiveFormatGzip) ? AADecompressionRandomAccessByteStreamOpen(input, 1) : input;
        if (!decompressor) { AAByteStreamClose(input); return NO; }

        AAArchiveStream extract = AAExtractArchiveStreamOpen(decompressor);
        if (extract) {
            // Processing loop...
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
            mz_zip_writer_add_file(&zip_archive, [path lastPathComponent].UTF8String, path.fileSystemRepresentation, NULL, 0, 9);
        }

        mz_zip_writer_finalize_archive(&zip_archive);
        mz_zip_writer_end(&zip_archive);
        return YES;
    }
    return NO;
}

@end
