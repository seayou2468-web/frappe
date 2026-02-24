#import <Foundation/Foundation.h>

@interface BookmarksManager : NSObject
+ (instancetype)sharedManager;
@property (nonatomic, strong, readonly) NSMutableArray<NSString *> *bookmarks;
- (void)addBookmark:(NSString *)path;
- (void)removeBookmark:(NSString *)path;
@end
