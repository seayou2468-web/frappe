#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, ArchiveFormat) {
    ArchiveFormatZip,
    ArchiveFormatUnknown
};

@interface ZipManager : NSObject
+ (BOOL)extractArchiveAtPath:(NSString *)archivePath toDestination:(NSString *)destPath password:(NSString *)password error:(NSError **)error;
+ (BOOL)compressFiles:(NSArray *)filePaths toPath:(NSString *)archivePath format:(ArchiveFormat)format password:(NSString *)password error:(NSError **)error;
+ (ArchiveFormat)formatForPath:(NSString *)path;
@end
