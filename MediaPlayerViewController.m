#import "MediaPlayerViewController.h"
#import "ThemeEngine.h"
#import <AVKit/AVKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MediaPlayerViewController ()
@property (strong, nonatomic) AVPlayerViewController *playerVC;
@property (strong, nonatomic) NSString *path;
@end

@implementation MediaPlayerViewController

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _path = path;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
    self.title = [self.path lastPathComponent];

    AVPlayer *player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:self.path]];
    self.playerVC = [[AVPlayerViewController alloc] init];
    self.playerVC.player = player;

    [self addChildViewController:self.playerVC];
    self.playerVC.view.frame = self.view.bounds;
    self.playerVC.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.playerVC.view];
    [self.playerVC didMoveToParentViewController:self];

    [player play];
}

@end

NS_ASSUME_NONNULL_END
