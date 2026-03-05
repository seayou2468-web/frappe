#import <Foundation/Foundation.h>

@interface WebBookmarksManager : NSObject
+ (instancetype)sharedManager;
@property (nonatomic, strong, readonly) NSArray<NSDictionary *> *bookmarks;
- (void)addBookmarkWithTitle:(NSString *)title url:(NSString *)url;
- (void)removeBookmarkAtIndex:(NSInteger)index;
@end
