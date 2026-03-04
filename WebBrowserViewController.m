#import "WebBrowserViewController.h"
#import "TabManager.h"
#import "ThemeEngine.h"
#import "MainContainerViewController.h"
#import "BottomMenuView.h"
#import "CustomMenuView.h"
#import "DownloadManager.h"
#import "DownloadsViewController.h"
#import "PersistenceManager.h"

static WKWebsiteDataStore *_nonPersistentStore = nil;

@interface WebBrowserViewController () <WKUIDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UITextField *urlField;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) BottomMenuView *bottomMenu;
@end

@implementation WebBrowserViewController

+ (WKWebsiteDataStore *)sharedDataStore {
    if (!_nonPersistentStore) {
        _nonPersistentStore = [WKWebsiteDataStore nonPersistentDataStore];
    }
    return _nonPersistentStore;
}

+ (void)resetSharedDataStore {
    _nonPersistentStore = [WKWebsiteDataStore nonPersistentDataStore];
}

- (instancetype)initWithURL:(NSString *)url {
    self = [super init];
    if (self) {
        NSString *home = [[NSUserDefaults standardUserDefaults] stringForKey:@"WebHomepage"] ?: @"https://www.google.com";
        _initialURL = url ?: home;
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

- (void)dealloc { [self.webView removeObserver:self forKeyPath:@"estimatedProgress"]; }

- (void)setupUI {
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    if ([[PersistenceManager sharedManager] isDomainPersistent:self.initialURL]) {
        config.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    } else {
        config.websiteDataStore = [WebBrowserViewController sharedDataStore];
    }
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    self.webView.allowsBackForwardNavigationGestures = YES;
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
        [self.progressView.topAnchor constraintEqualToAnchor:safe.topAnchor], [self.progressView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.progressView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [self.progressView.heightAnchor constraintEqualToConstant:2],
        [self.webView.topAnchor constraintEqualToAnchor:self.progressView.bottomAnchor], [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [self.webView.bottomAnchor constraintEqualToAnchor:self.bottomMenu.topAnchor],
        [self.bottomMenu.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.bottomMenu.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [self.bottomMenu.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor], [self.bottomMenu.heightAnchor constraintEqualToConstant:80],
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
        NSString *engine = [[NSUserDefaults standardUserDefaults] stringForKey:@"SearchEngine"] ?: @"Google";
        NSString *baseUrl = @"https://www.google.com/search?q=";
        if ([engine isEqualToString:@"Bing"]) baseUrl = @"https://www.bing.com/search?q=";
        else if ([engine isEqualToString:@"DuckDuckGo"]) baseUrl = @"https://duckduckgo.com/?q=";
        else if ([engine isEqualToString:@"Yahoo"]) baseUrl = @"https://search.yahoo.com/search?p=";
        else if ([engine isEqualToString:@"Custom"]) {
            baseUrl = [[NSUserDefaults standardUserDefaults] stringForKey:@"CustomSearchURL"] ?: baseUrl;
        }
        urlStr = [NSString stringWithFormat:@"%@%@", baseUrl, [urlStr stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    } else if (![urlStr hasPrefix:@"http"]) {
        urlStr = [@"https://" stringByAppendingString:urlStr];
    }
    [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlStr]]];
    [textField resignFirstResponder];
    return YES;
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    TabInfo *active = [[TabManager sharedManager] activeTab];
    if (active && active.type == TabTypeWebBrowser) {
        active.currentPath = webView.URL.absoluteString;
        active.title = webView.title.length > 0 ? webView.title : @"Browser";
    }
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
        case BottomMenuActionWebHome: {
            NSString *home = [[NSUserDefaults standardUserDefaults] stringForKey:@"WebHomepage"] ?: @"https://www.google.com";
            [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:home]]];
            break;
        }
        case BottomMenuActionDownloads: { DownloadsViewController *vc = [[DownloadsViewController alloc] init]; [self.navigationController pushViewController:vc animated:YES]; break; }
        case BottomMenuActionTabs: { MainContainerViewController *container = (MainContainerViewController *)self.view.window.rootViewController; if ([container isKindOfClass:[MainContainerViewController class]]) [container showTabSwitcher]; break; }
        default: break;
    }
}

#pragma mark - Developer Tools

- (void)handleLongPress:(UILongPressGestureRecognizer *)lp {
    if (lp.state != UIGestureRecognizerStateBegan) return;
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"ツール"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"クッキーを表示" systemImage:@"info.circle" style:CustomMenuActionStyleDefault handler:^{ [self showCookies]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"Webインスペクタ" systemImage:@"terminal" style:CustomMenuActionStyleDefault handler:^{ [self showWebInspector]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"ページを保存" systemImage:@"arrow.down.doc" style:CustomMenuActionStyleDefault handler:^{ [self triggerDownloadWithURL:self.webView.URL]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"永続サイトに追加" systemImage:@"lock.shield" style:CustomMenuActionStyleDefault handler:^{ [[PersistenceManager sharedManager] addDomain:self.webView.URL.host]; }]];
    [menu showInView:self.view];
}

- (void)showCookies {
    [self.webView.configuration.websiteDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableString *str = [NSMutableString stringWithFormat:@"Current Cookies: %lu\n\n", (unsigned long)cookies.count];
            for (NSHTTPCookie *cookie in cookies) { [str appendFormat:@"Name: %@\nValue: %@\nDomain: %@\n\n", cookie.name, cookie.value, cookie.domain]; }
            UITextView *tv = [[UITextView alloc] initWithFrame:self.view.bounds]; tv.text = str; tv.editable = NO; tv.backgroundColor = [UIColor blackColor]; tv.textColor = [UIColor greenColor]; tv.font = [UIFont fontWithName:@"Menlo" size:12];
            UIViewController *vc = [[UIViewController alloc] init]; vc.view = tv; vc.title = @"Cookies"; [self.navigationController pushViewController:vc animated:YES];
        });
    }];
}

- (void)showWebInspector {
    [self.webView evaluateJavaScript:@"document.documentElement.outerHTML" completionHandler:^(id result, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UITextView *tv = [[UITextView alloc] initWithFrame:self.view.bounds]; tv.text = (NSString *)result; tv.editable = NO; tv.backgroundColor = [UIColor blackColor]; tv.textColor = [UIColor whiteColor]; tv.font = [UIFont fontWithName:@"Menlo" size:11];
            UIViewController *vc = [[UIViewController alloc] init]; vc.view = tv; vc.title = @"Source Inspector"; [self.navigationController pushViewController:vc animated:YES];
        });
    }];
}

- (void)triggerDownloadWithURL:(NSURL *)url {
    NSString *downloadsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    downloadsPath = [downloadsPath stringByAppendingPathComponent:@"Downloads"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1" forHTTPHeaderField:@"User-Agent"];
    [self.webView.configuration.websiteDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        [request setAllHTTPHeaderFields:[NSHTTPCookie requestHeaderFieldsWithCookies:cookies]];
        dispatch_async(dispatch_get_main_queue(), ^{ [[DownloadManager sharedManager] downloadFileWithRequest:request toPath:downloadsPath]; DownloadsViewController *vc = [[DownloadsViewController alloc] init]; [self.navigationController pushViewController:vc animated:YES]; });
    }];
}

@end
