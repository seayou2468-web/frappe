#import "WebBrowserViewController.h"
#import "ThemeEngine.h"
#import "MainContainerViewController.h"
#import "BottomMenuView.h"
#import "CustomMenuView.h"
#import "DownloadManager.h"
#import "DownloadsViewController.h"

static WKWebsiteDataStore *_sharedDataStore = nil;

@interface WebBrowserViewController ()
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UITextField *urlField;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) BottomMenuView *bottomMenu;
@end

@implementation WebBrowserViewController

+ (WKWebsiteDataStore *)sharedDataStore {
    if (!_sharedDataStore) {
        _sharedDataStore = [WKWebsiteDataStore nonPersistentDataStore];
    }
    return _sharedDataStore;
}

+ (void)resetSharedDataStore {
    _sharedDataStore = [WKWebsiteDataStore nonPersistentDataStore];
}

- (instancetype)initWithURL:(NSString *)url {
    self = [super init];
    if (self) {
        _initialURL = url ?: @"https://www.google.com";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
    [self setupUI];

    NSURL *url = [NSURL URLWithString:self.initialURL];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];

    [self.webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];
}

- (void)dealloc {
    [self.webView removeObserver:self forKeyPath:@"estimatedProgress"];
}

- (void)setupUI {
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.websiteDataStore = [WebBrowserViewController sharedDataStore];
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.navigationDelegate = self;
    self.webView.backgroundColor = [UIColor clearColor];
    self.webView.opaque = NO;
    [self.view addSubview:self.webView];

    self.urlField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 200, 36)];
    self.urlField.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    self.urlField.textColor = [UIColor whiteColor];
    self.urlField.layer.cornerRadius = 10;
    self.urlField.keyboardType = UIKeyboardTypeURL;
    self.urlField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.urlField.delegate = self;
    self.urlField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
    self.urlField.leftViewMode = UITextFieldViewModeAlways;
    self.navigationItem.titleView = self.urlField;

    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressView.progressTintColor = [ThemeEngine liquidColor];
    self.progressView.trackTintColor = [UIColor clearColor];
    [self.view addSubview:self.progressView];

    self.bottomMenu = [[BottomMenuView alloc] initWithMode:BottomMenuModeWeb];
    self.bottomMenu.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) weakSelf = self;
    self.bottomMenu.onAction = ^(BottomMenuAction action) { [weakSelf handleMenuAction:action]; };
    [self.view addSubview:self.bottomMenu];

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [self.webView addGestureRecognizer:lp];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.progressView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.progressView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.progressView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.progressView.heightAnchor constraintEqualToConstant:2],

        [self.webView.topAnchor constraintEqualToAnchor:self.progressView.bottomAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.bottomMenu.topAnchor],

        [self.bottomMenu.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bottomMenu.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bottomMenu.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.bottomMenu.heightAnchor constraintEqualToConstant:80],
    ]];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"estimatedProgress"]) {
        self.progressView.progress = self.webView.estimatedProgress;
        self.progressView.hidden = (self.webView.estimatedProgress >= 1.0);
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    NSString *urlStr = textField.text;
    if (urlStr.length == 0) return YES;
    if (![urlStr containsString:@"."] && ![urlStr hasPrefix:@"http"]) {
        urlStr = [NSString stringWithFormat:@"https://www.google.com/search?q=%@", [urlStr stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    } else if (![urlStr hasPrefix:@"http"]) {
        urlStr = [@"https://" stringByAppendingString:urlStr];
    }
    [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlStr]]];
    [textField resignFirstResponder];
    return YES;
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    self.urlField.text = webView.URL.absoluteString;
}

- (void)handleMenuAction:(BottomMenuAction)action {
    switch (action) {
        case BottomMenuActionWebBack: [self.webView goBack]; break;
        case BottomMenuActionWebForward: [self.webView goForward]; break;
        case BottomMenuActionWebShare: {
            UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[self.webView.URL ?: [NSURL URLWithString:self.initialURL]] applicationActivities:nil];
            [self presentViewController:avc animated:YES completion:nil];
            break;
        }
        case BottomMenuActionWebHome: [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://www.google.com"]]]; break;
        case BottomMenuActionDownloads: {
            DownloadsViewController *vc = [[DownloadsViewController alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
            break;
        }
        case BottomMenuActionTabs: {
            MainContainerViewController *container = (MainContainerViewController *)self.view.window.rootViewController;
            if ([container isKindOfClass:[MainContainerViewController class]]) [container showTabSwitcher];
            break;
        }
        default: break;
    }
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    NSString *ext = [url pathExtension].lowercaseString;
    NSArray *downloadExts = @[@"zip", @"ipa", @"deb", @"pdf", @"mp4", @"mp3", @"dmg", @"pkg", @"rar", @"7z", @"gz", @"tar"];

    if ([downloadExts containsObject:ext]) {
        [self triggerDownloadWithURL:url];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    if (navigationResponse.canShowMIMEType) {
        decisionHandler(WKNavigationResponsePolicyAllow);
    } else {
        [self triggerDownloadWithURL:navigationResponse.response.URL];
        decisionHandler(WKNavigationResponsePolicyCancel);
    }
}

- (void)triggerDownloadWithURL:(NSURL *)url {
    NSString *downloadsPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Downloads"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1" forHTTPHeaderField:@"User-Agent"];

    [[WebBrowserViewController sharedDataStore].httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        NSDictionary *headers = [NSHTTPCookie requestHeaderFieldsWithCookies:cookies];
        [request setAllHTTPHeaderFields:headers];

        dispatch_async(dispatch_get_main_queue(), ^{
            [[DownloadManager sharedManager] downloadFileWithRequest:request toPath:downloadsPath];

            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ダウンロード" message:@"ダウンロードを開始しました" preferredStyle:UIAlertControllerStyleAlert];
            [self presentViewController:alert animated:YES completion:nil];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [alert dismissViewControllerAnimated:YES completion:nil];
            });

            DownloadsViewController *vc = [[DownloadsViewController alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
        });
    }];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)lp {
    if (lp.state != UIGestureRecognizerStateBegan) return;

    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"ダウンロード"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"現在のページを保存" systemImage:@"arrow.down.doc" style:CustomMenuActionStyleDefault handler:^{
        [self triggerDownloadWithURL:self.webView.URL];
    }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"ダウンロード一覧を表示" systemImage:@"list.bullet" style:CustomMenuActionStyleDefault handler:^{
        DownloadsViewController *vc = [[DownloadsViewController alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
    }]];
    [menu showInView:self.view];
}

@end
