#import <UIKit/UIKit.h>
#import "idevice.h"

@interface ProfileManagerViewController : UIViewController
- (instancetype)initWithProvider:(struct IdeviceProviderHandle *)provider;
@end
