#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OOXMLPackageReader : NSObject
+ (NSArray<NSString *> *)entryNamesInZipAtPath:(NSString *)zipPath;
+ (nullable NSData *)dataForEntry:(NSString *)entryPath inZipAtPath:(NSString *)zipPath;
+ (BOOL)hasVBAMacroProjectInZipAtPath:(NSString *)zipPath;
+ (NSArray<NSString *> *)vbaRelatedEntryNamesInZipAtPath:(NSString *)zipPath;
@end

NS_ASSUME_NONNULL_END
