#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface WebBrowserViewController : UIViewController <WKNavigationDelegate, UITextFieldDelegate>
@property (nonatomic, strong) NSString *initialURL;
- (instancetype)initWithURL:(NSString *)url;
@end
