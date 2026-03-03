#import "AppDelegate.h"
#import "DownloadManager.h"



@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // iOS 13以上では SceneDelegate に任せる
    return YES;
}


- (void)application:(UIApplication *)application handleEventsForBackgroundURLSession:(NSString *)identifier completionHandler:(void (^)(void))completionHandler {
    if ([identifier isEqualToString:@"com.app.godspeed.download"]) {
        [DownloadManager sharedManager].completionHandler = completionHandler;
    }
}

@end

