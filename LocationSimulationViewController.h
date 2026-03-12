#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import "idevice.h"

@interface LocationSimulationViewController : UIViewController

- (instancetype)initWithProvider:(struct IdeviceProviderHandle *)provider lockdown:(struct LockdowndClientHandle *)lockdown;

@end
