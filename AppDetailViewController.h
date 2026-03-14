#import <UIKit/UIKit.h>
#import "AppManager.h"

@interface AppDetailViewController : UIViewController
- (instancetype)initWithAppInfo:(AppInfo *)appInfo provider:(struct IdeviceProviderHandle *)provider;
@end
