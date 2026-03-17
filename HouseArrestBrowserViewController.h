#import <UIKit/UIKit.h>
#import "idevice.h"

NS_ASSUME_NONNULL_BEGIN

@interface HouseArrestBrowserViewController : UIViewController

- (instancetype)initWithProvider:(struct IdeviceProviderHandle *)provider;

@end

NS_ASSUME_NONNULL_END
