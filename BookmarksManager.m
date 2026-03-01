#import "BookmarksManager.h"

@interface BookmarksManager ()
@property (nonatomic, strong) NSMutableArray<NSString *> *bookmarksInternal;
@end

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
        NSArray *saved = [[NSUserDefaults standardUserDefaults] stringArrayForKey:@"Bookmarks"];
        _bookmarksInternal = saved ? [saved mutableCopy] : [NSMutableArray array];
    }
    return self;
}

- (NSMutableArray<NSString *> *)bookmarks {
    return _bookmarksInternal;
}

- (void)addBookmark:(NSString *)path {
    if (!path) return;
    if (![_bookmarksInternal containsObject:path]) {
        [_bookmarksInternal addObject:path];
        [self save];
    }
}

- (void)removeBookmark:(NSString *)path {
    if (!path) return;
    [_bookmarksInternal removeObject:path];
    [self save];
}

- (void)save {
    [[NSUserDefaults standardUserDefaults] setObject:_bookmarksInternal forKey:@"Bookmarks"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
