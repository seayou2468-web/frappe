#import "SceneDelegate.h"
#import "MainContainerViewController.h"

NS_ASSUME_NONNULL_BEGIN

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.rootViewController = [[MainContainerViewController alloc] init];
    [self.window makeKeyAndVisible];
}

@end

NS_ASSUME_NONNULL_END
