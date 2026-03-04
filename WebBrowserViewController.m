#import "WebBrowserViewController.h"
#import "TabManager.h"
#import "ThemeEngine.h"
#import "MainContainerViewController.h"
#import "BottomMenuView.h"
#import "CustomMenuView.h"
#import "DownloadManager.h"
#import "DownloadsViewController.h"
#import "PersistenceManager.h"
#import "WebInspectorViewController.h"

static WKWebsiteDataStore *_nonPersistentStore = nil;

@interface WebBrowserViewController () <WKUIDelegate, WKScriptMessageHandler>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UITextField *urlField;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) BottomMenuView *bottomMenu;
@property (nonatomic, strong) NSMutableArray<NSString *> *consoleLogs;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *networkLogs;
@end

@implementation WebBrowserViewController

+ (WKWebsiteDataStore *)sharedDataStore {
    if (!_nonPersistentStore) { _nonPersistentStore = [WKWebsiteDataStore nonPersistentDataStore]; }
    return _nonPersistentStore;
}

+ (void)resetSharedDataStore { _nonPersistentStore = [WKWebsiteDataStore nonPersistentDataStore]; }

- (instancetype)initWithURL:(NSString *)url {
    self = [super init];
    if (self) {
        NSString *home = [[NSUserDefaults standardUserDefaults] stringForKey:@"WebHomepage"] ?: @"https://www.google.com";
        _initialURL = url ?: home;
        _consoleLogs = [NSMutableArray array];
        _networkLogs = [NSMutableArray array];
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
    WKUserContentController *userContent = [[WKUserContentController alloc] init];
    [userContent addScriptMessageHandler:self name:@"logger"];
    [userContent addScriptMessageHandler:self name:@"network"];

    NSString *js =
        @"var originalLog = console.log; console.log = function(m) { window.webkit.messageHandlers.logger.postMessage(JSON.stringify(m)); originalLog.apply(console, arguments); };"
        "var originalError = console.error; console.error = function(m) { window.webkit.messageHandlers.logger.postMessage('ERROR: ' + JSON.stringify(m)); originalError.apply(console, arguments); };"
        "var originalOpen = XMLHttpRequest.prototype.open; XMLHttpRequest.prototype.open = function(method, url) {"
        "  this._url = url; this._method = method; originalOpen.apply(this, arguments);"
        "};"
        "var originalSend = XMLHttpRequest.prototype.send; XMLHttpRequest.prototype.send = function() {"
        "  this.addEventListener('load', function() {"
        "    window.webkit.messageHandlers.network.postMessage({url: this._url, method: this._method, status: this.status});"
        "  });"
        "  originalSend.apply(this, arguments);"
        "};"
        "var originalFetch = window.fetch; window.fetch = function() {"
        "  var args = arguments; return originalFetch.apply(this, arguments).then(function(response) {"
        "    window.webkit.messageHandlers.network.postMessage({url: response.url, method: 'FETCH', status: response.status});"
        "    return response;"
        "  });"
        "};";

    WKUserScript *script = [[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];
    [userContent addUserScript:script];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.userContentController = userContent;
    if ([[PersistenceManager sharedManager] isDomainPersistent:self.initialURL]) { config.websiteDataStore = [WKWebsiteDataStore defaultDataStore]; }
    else { config.websiteDataStore = [WebBrowserViewController sharedDataStore]; }

    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    self.webView.allowsBackForwardNavigationGestures = YES;
    self.webView.backgroundColor = [UIColor clearColor];
    self.webView.opaque = NO;
    [self.view addSubview:self.webView];

    self.urlField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 160, 36)];
    self.urlField.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    self.urlField.textColor = [UIColor whiteColor];
    self.urlField.layer.cornerRadius = 10;
    self.urlField.keyboardType = UIKeyboardTypeURL;
    self.urlField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.urlField.delegate = self;
    self.navigationItem.titleView = self.urlField;

    UIBarButtonItem *inspectorBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"terminal"] style:UIBarButtonItemStylePlain target:self action:@selector(prepareAndShowInspector)];
    self.navigationItem.rightBarButtonItem = inspectorBtn;

    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.progressView];

    self.bottomMenu = [[BottomMenuView alloc] initWithMode:BottomMenuModeWeb];
    self.bottomMenu.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) weakSelf = self;
    self.bottomMenu.onAction = ^(BottomMenuAction action) { [weakSelf handleMenuAction:action]; };
    [self.view addSubview:self.bottomMenu];

    [NSLayoutConstraint activateConstraints:@[
        [self.progressView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor], [self.progressView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.progressView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [self.progressView.heightAnchor constraintEqualToConstant:2],
        [self.webView.topAnchor constraintEqualToAnchor:self.progressView.bottomAnchor], [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [self.webView.bottomAnchor constraintEqualToAnchor:self.bottomMenu.topAnchor],
        [self.bottomMenu.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.bottomMenu.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [self.bottomMenu.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor], [self.bottomMenu.heightAnchor constraintEqualToConstant:80],
    ]];
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.name isEqualToString:@"logger"]) {
        [self.consoleLogs addObject:[NSString stringWithFormat:@"%@", message.body]];
    } else if ([message.name isEqualToString:@"network"]) {
        NSMutableDictionary *dict = [message.body mutableCopy];
        dict[@"time"] = [[NSDate date] description];
        [self.networkLogs addObject:dict];
    }
}

- (void)prepareAndShowInspector {
    [self.webView evaluateJavaScript:@"document.documentElement.outerHTML" completionHandler:^(id html, NSError *error) {
        [self.webView evaluateJavaScript:@"(function(){ return {local: JSON.stringify(localStorage), session: JSON.stringify(sessionStorage)}; })();" completionHandler:^(id storage, NSError *error2) {
            [self.webView.configuration.websiteDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    WebInspectorViewController *vc = [[WebInspectorViewController alloc] init];
                    vc.htmlSource = (NSString *)html;
                    vc.consoleLogs = self.consoleLogs;
                    vc.networkLogs = self.networkLogs;
                    vc.cookies = cookies;

                    NSDictionary *sDict = (NSDictionary *)storage;
                    NSMutableDictionary *finalStorage = [NSMutableDictionary dictionary];
                    if (sDict[@"local"]) finalStorage[@"local"] = [NSJSONSerialization JSONObjectWithData:[sDict[@"local"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
                    if (sDict[@"session"]) finalStorage[@"session"] = [NSJSONSerialization JSONObjectWithData:[sDict[@"session"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
                    vc.storageData = finalStorage;

                    vc.onCommand = ^(NSString *command) {
                        [self.webView evaluateJavaScript:command completionHandler:nil];
                    };

                    [self.navigationController pushViewController:vc animated:YES];
                });
            }];
        }];
    }];
}

#pragma mark - Existing methods ... (textFieldShouldReturn, didFinishNavigation, handleMenuAction, triggerDownloadWithURL)

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    NSString *urlStr = textField.text;
    if (urlStr.length == 0) return YES;
    if (![urlStr containsString:@"."] && ![urlStr hasPrefix:@"http"]) {
        NSString *engine = [[NSUserDefaults standardUserDefaults] stringForKey:@"SearchEngine"] ?: @"Google";
        NSString *baseUrl = @"https://www.google.com/search?q=";
        if ([engine isEqualToString:@"Bing"]) baseUrl = @"https://www.bing.com/search?q=";
        else if ([engine isEqualToString:@"DuckDuckGo"]) baseUrl = @"https://duckduckgo.com/?q=";
        else if ([engine isEqualToString:@"Yahoo"]) baseUrl = @"https://search.yahoo.com/search?p=";
        else if ([engine isEqualToString:@"Custom"]) baseUrl = [[NSUserDefaults standardUserDefaults] stringForKey:@"CustomSearchURL"] ?: baseUrl;
        urlStr = [NSString stringWithFormat:@"%@%@", baseUrl, [urlStr stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    } else if (![urlStr hasPrefix:@"http"]) { urlStr = [@"https://" stringByAppendingString:urlStr]; }
    [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlStr]]];
    [textField resignFirstResponder];
    return YES;
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    TabInfo *active = [[TabManager sharedManager] activeTab];
    if (active && active.type == TabTypeWebBrowser) { active.currentPath = webView.URL.absoluteString; active.title = webView.title.length > 0 ? webView.title : @"Browser"; }
    self.urlField.text = webView.URL.absoluteString;
}

- (void)handleMenuAction:(BottomMenuAction)action {
    switch (action) {
        case BottomMenuActionWebBack: [self.webView goBack]; break;
        case BottomMenuActionWebForward: [self.webView goForward]; break;
        case BottomMenuActionWebShare: { UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[self.webView.URL ?: [NSURL URLWithString:self.initialURL]] applicationActivities:nil]; [self presentViewController:avc animated:YES completion:nil]; break; }
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
