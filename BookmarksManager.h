#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BookmarksManager : NSObject
+ (instancetype)sharedManager;
@property (nonatomic, strong, readonly) NSMutableArray<NSString *> *bookmarks;
- (void)addBookmark:(NSString *)path;
- (void)removeBookmark:(NSString *)path;
@end

NS_ASSUME_NONNULL_END
