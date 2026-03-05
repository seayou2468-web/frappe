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
        if (saved) {
            _mutableBookmarks = [saved mutableCopy];
        } else {
            _mutableBookmarks = [NSMutableArray arrayWithArray:@[
                @{@"title": @"Google", @"url": @"https://www.google.com"},
                @{@"title": @"GitHub", @"url": @"https://github.com"},
                @{@"title": @"YouTube", @"url": @"https://www.youtube.com"}
            ]];
            [self save];
        }
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

- (void)updateBookmarkAtIndex:(NSInteger)index title:(NSString *)title url:(NSString *)url {
    if (index < self.mutableBookmarks.count && url) {
        self.mutableBookmarks[index] = @{@"title": title ?: url, @"url": url};
        [self save];
    }
}

- (void)save {
    [[NSUserDefaults standardUserDefaults] setObject:self.mutableBookmarks forKey:@"WebBookmarks"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
