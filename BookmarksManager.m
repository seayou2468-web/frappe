#import "BookmarksManager.h"

NS_ASSUME_NONNULL_BEGIN

@implementation BookmarksManager

+ (instancetype)sharedManager {
    static BookmarksManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[BookmarksManager alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _bookmarks = [[[NSUserDefaults standardUserDefaults] stringArrayForKey:@"Bookmarks"] mutableCopy] ?: [NSMutableArray array];
    }
    return self;
}

- (void)addBookmark:(NSString *)path {
    if (![_bookmarks containsObject:path]) {
        [_bookmarks addObject:path];
        [self save];
    }
}

- (void)removeBookmark:(NSString *)path {
    [_bookmarks removeObject:path];
    [self save];
}

- (void)save {
    [[NSUserDefaults standardUserDefaults] setObject:_bookmarks forKey:@"Bookmarks"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end

NS_ASSUME_NONNULL_END
