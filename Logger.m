#import "Logger.h"

@interface Logger ()
@property (nonatomic, strong) NSMutableArray<NSString *> *mutableLogs;
@end

@implementation Logger

+ (instancetype)sharedLogger {
    static Logger *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[Logger alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableLogs = [NSMutableArray array];
    }
    return self;
}

- (void)log:(NSString *)message {
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle];
    NSString *fullMessage = [NSString stringWithFormat:@"[%@] %@", timestamp, message];
    NSLog(@"%@", fullMessage);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.mutableLogs addObject:fullMessage];
        if (self.mutableLogs.count > 1000) [self.mutableLogs removeObjectAtIndex:0];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"NewLogAdded" object:fullMessage];
    });
}

- (NSArray<NSString *> *)logs {
    return [self.mutableLogs copy];
}

@end
