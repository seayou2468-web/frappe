#import "WebBookmarksManager.h"

@interface WebBookmarksManager ()
@property (nonatomic, strong) NSMutableArray *mutableBookmarks;
@end

@implementation WebBookmarksManager

+ (instancetype)sharedManager {
    static WebBookmarksManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[WebBookmarksManager alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:@"WebBookmarks"];
        _mutableBookmarks = saved ? [saved mutableCopy] : [NSMutableArray array];
    }
    return self;
}

- (NSArray *)bookmarks {
    return [self.mutableBookmarks copy];
}

- (void)addBookmarkWithTitle:(NSString *)title url:(NSString *)url {
    if (!url) return;
    [self.mutableBookmarks addObject:@{@"title": title ?: url, @"url": url}];
    [self save];
}

- (void)removeBookmarkAtIndex:(NSInteger)index {
    if (index < self.mutableBookmarks.count) {
        [self.mutableBookmarks removeObjectAtIndex:index];
        [self save];
    }
}

- (void)save {
    [[NSUserDefaults standardUserDefaults] setObject:self.mutableBookmarks forKey:@"WebBookmarks"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
