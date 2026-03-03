#import "PersistenceManager.h"

@implementation PersistenceManager {
    NSMutableArray *_domains;
}

+ (instancetype)sharedManager {
    static PersistenceManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PersistenceManager alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSArray *saved = [[NSUserDefaults standardUserDefaults] stringArrayForKey:@"PersistentDomains"];
        _domains = saved ? [saved mutableCopy] : [NSMutableArray array];
    }
    return self;
}

- (NSArray<NSString *> *)persistentDomains { return [_domains copy]; }

- (void)addDomain:(NSString *)domain {
    NSString *clean = [self cleanDomain:domain];
    if (clean.length > 0 && ![_domains containsObject:clean]) {
        [_domains addObject:clean];
        [self save];
    }
}

- (void)removeDomain:(NSString *)domain {
    [_domains removeObject:[self cleanDomain:domain]];
    [self save];
}

- (BOOL)isDomainPersistent:(NSString *)domain {
    NSString *clean = [self cleanDomain:domain];
    for (NSString *d in _domains) {
        if ([clean containsString:d]) return YES;
    }
    return NO;
}

- (NSString *)cleanDomain:(NSString *)url {
    NSURL *u = [NSURL URLWithString:url];
    if (u && u.host) return u.host.lowercaseString;
    return url.lowercaseString;
}

- (void)save {
    [[NSUserDefaults standardUserDefaults] setObject:_domains forKey:@"PersistentDomains"];
}

@end
