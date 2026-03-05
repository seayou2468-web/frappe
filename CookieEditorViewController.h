#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface CookieEditorViewController : UIViewController
@property (nonatomic, strong) WKHTTPCookieStore *cookieStore;
@end
