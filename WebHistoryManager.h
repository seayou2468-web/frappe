#import <Foundation/Foundation.h>

@interface WebHistoryManager : NSObject
+ (instancetype)sharedManager;
@property (nonatomic, strong, readonly) NSArray<NSDictionary *> *history;
- (void)addHistoryEntryWithTitle:(NSString *)title url:(NSString *)url;
- (void)clearHistory;
@end
