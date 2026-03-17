#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PPTXCompatibilityReader : NSObject
+ (NSArray<NSArray<NSString *> *> *)readSlideTextsFromPPTXPath:(NSString *)filePath;
+ (NSDictionary *)readPresentationFromOOXMLPath:(NSString *)filePath;
@end

NS_ASSUME_NONNULL_END
