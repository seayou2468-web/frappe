#import <Foundation/Foundation.h>

@interface Logger : NSObject
+ (instancetype)sharedLogger;
- (void)log:(NSString *)message;
@property (nonatomic, strong, readonly) NSArray<NSString *> *logs;
@end
