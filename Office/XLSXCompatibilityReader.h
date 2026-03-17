#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface XLSXCompatibilityReader : NSObject
+ (NSArray<NSDictionary *> *)readSheetsFromXLSXPath:(NSString *)filePath;
+ (NSDictionary *)readWorkbookFromOOXMLPath:(NSString *)filePath;
@end

NS_ASSUME_NONNULL_END
