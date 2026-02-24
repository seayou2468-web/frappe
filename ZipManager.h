#import <Foundation/Foundation.h>

@interface ZipManager : NSObject
+ (BOOL)unzipFileAtPath:(NSString *)zipPath toDestination:(NSString *)destPath password:(NSString *)password error:(NSError **)error;
+ (BOOL)zipFiles:(NSArray<NSString *> *)filePaths toPath:(NSString *)zipPath password:(NSString *)password error:(NSError **)error;
+ (BOOL)isEncrypted:(NSString *)path;
@end
