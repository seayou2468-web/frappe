#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ArchiveFormat) {
    ArchiveFormatZip,
    ArchiveFormatTar,
    ArchiveFormatGzip,
    ArchiveFormat7z,
    ArchiveFormatRar,
    ArchiveFormatUnknown
};

@interface ZipManager : NSObject
+ (BOOL)extractArchiveAtPath:(NSString *)archivePath toDestination:(NSString *)destPath password:(NSString * _Nullable)password error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)compressFiles:(NSArray<NSString *> *)filePaths toPath:(NSString *)archivePath format:(ArchiveFormat)format password:(NSString * _Nullable)password error:(NSError * _Nullable * _Nullable)error;
+ (ArchiveFormat)formatForPath:(NSString *)path;
@end

NS_ASSUME_NONNULL_END
