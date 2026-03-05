#import "WebHistoryManager.h"

@interface WebHistoryManager ()
@property (nonatomic, strong) NSMutableArray *mutableHistory;
@end

@implementation WebHistoryManager

+ (instancetype)sharedManager {
    static WebHistoryManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[WebHistoryManager alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:@"WebHistory"];
        _mutableHistory = saved ? [saved mutableCopy] : [NSMutableArray array];
    }
    return self;
}

- (NSArray *)history {
    return [self.mutableHistory copy];
}

- (void)addHistoryEntryWithTitle:(NSString *)title url:(NSString *)url {
    if (!url || [url isEqualToString:@"about:blank"]) return;

    // Remove if already exists to move to top
    for (NSDictionary *entry in [self.mutableHistory copy]) {
        if ([entry[@"url"] isEqualToString:url]) {
            [self.mutableHistory removeObject:entry];
            break;
        }
    }

    [self.mutableHistory insertObject:@{@"title": title ?: url, @"url": url, @"date": [NSDate date]} atIndex:0];

    if (self.mutableHistory.count > 500) [self.mutableHistory removeLastObject];
    [self save];
}

- (void)clearHistory {
    [self.mutableHistory removeAllObjects];
    [self save];
}

- (void)save {
    [[NSUserDefaults standardUserDefaults] setObject:self.mutableHistory forKey:@"WebHistory"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
