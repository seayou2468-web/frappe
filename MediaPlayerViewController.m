#import "MediaPlayerViewController.h"

@implementation MediaPlayerViewController

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        self.player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:path]];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.player play];
}

@end
