#import <UIKit/UIKit.h>
#import "idevice.h"

@interface AfcBrowserViewController : UIViewController

- (instancetype)initWithProvider:(struct IdeviceProviderHandle *)provider isAfc2:(BOOL)isAfc2;

@end
