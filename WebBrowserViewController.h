#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface WebBrowserViewController : UIViewController <WKNavigationDelegate, UITextFieldDelegate>
@property (nonatomic, strong) NSString *initialURL;
@property (nonatomic, strong, readonly) WKWebView *webView;
- (instancetype)initWithURL:(NSString *)url;
+ (WKWebsiteDataStore *)sharedDataStore;
+ (void)resetSharedDataStore;
@end
