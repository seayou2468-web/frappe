#import <UIKit/UIKit.h>

#import "idevice.h"
@interface IdeviceViewController : UIViewController <UIDocumentPickerDelegate>
@property (nonatomic, readonly) struct IdeviceProviderHandle *currentProvider;

@end
