#import <Foundation/Foundation.h>
#import "FileManagerCore.h"

typedef NS_ENUM(NSInteger, ArchiveFormat) {
    ArchiveFormatZip,
    ArchiveFormatUnknown
};

@interface ZipManager : NSObject
+ (BOOL)extractArchiveAtPath:(NSString *)archivePath toDestination:(NSString *)destPath password:(NSString *)password error:(NSError **)error;
+ (BOOL)compressFiles:(NSArray<NSString *> *)filePaths toPath:(NSString *)archivePath format:(ArchiveFormat)format password:(NSString *)password error:(NSError **)error;
+ (ArchiveFormat)formatForPath:(NSString *)path;
+ (NSArray<FileItem *> *)listContentsOfZipAtPath:(NSString *)zipPath internalPath:(NSString *)internalPath;
@end
