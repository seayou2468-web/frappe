#import <UIKit/UIKit.h>
#import "idevice.h"

@interface AppListViewController : UIViewController
- (instancetype)initWithProvider:(struct IdeviceProviderHandle *)provider;
@end
