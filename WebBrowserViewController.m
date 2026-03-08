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
#import "WebStartPageView.h"
#import "WebBookmarksManager.h"
#import "CookieEditorViewController.h"
#import "WebHistoryManager.h"
#import "WebHistoryViewController.h"
#import "Logger.h"
#import "FileManagerCore.h"

static WKWebsiteDataStore *_nonPersistentStore = nil;

@interface WeakScriptMessageProxy : NSObject <WKScriptMessageHandler>
@property (nonatomic, weak) id<WKScriptMessageHandler> delegate;
@end
@implementation WeakScriptMessageProxy
- (void)userContentController:(WKUserContentController *)ucc didReceiveScriptMessage:(WKScriptMessage *)m {
    [self.delegate userContentController:ucc didReceiveScriptMessage:m];
}
@end

@interface WebBrowserViewController () <WKUIDelegate, WKScriptMessageHandler>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) WebStartPageView *startPage;
@property (nonatomic, strong) UITextField *urlField;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) BottomMenuView *bottomMenu;
@property (nonatomic, strong) NSMutableArray<NSString *> *consoleLogs;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *networkLogs;
@property (nonatomic, assign) BOOL isPrivateMode;
@property (nonatomic, assign) BOOL isAdBlockEnabled;
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
        _initialURL = ([url hasPrefix:@"http"] || [url containsString:@"."]) ? url : nil;
        _consoleLogs = [NSMutableArray array];
        _networkLogs = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
    [self setupUI];
    if (self.initialURL) {
        NSURL *url = [NSURL URLWithString:self.initialURL];
        if (url) [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
    }
    [self.webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshUI) name:@"SettingsChanged" object:nil];
}

- (void)dealloc {
    [self.webView removeObserver:self forKeyPath:@"estimatedProgress"];
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"logger"];
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"network"];
}

- (void)setupUI {
    WKUserContentController *userContent = [[WKUserContentController alloc] init];
    WeakScriptMessageProxy *proxy = [[WeakScriptMessageProxy alloc] init];
    proxy.delegate = self;
    [userContent addScriptMessageHandler:proxy name:@"logger"];
    [userContent addScriptMessageHandler:proxy name:@"network"];

    NSString *js =
        @"var originalLog = console.log; console.log = function(m) { try { window.webkit.messageHandlers.logger.postMessage(JSON.stringify(m)); } catch(e) {} originalLog.apply(console, arguments); };"
        "var originalError = console.error; console.error = function(m) { try { window.webkit.messageHandlers.logger.postMessage('ERROR: ' + JSON.stringify(m)); } catch(e) {} originalError.apply(console, arguments); };"
        "var originalOpen = XMLHttpRequest.prototype.open; XMLHttpRequest.prototype.open = function(method, url) {"
        "  this._url = url; this._method = method; originalOpen.apply(this, arguments);"
        "};"
        "var originalSend = XMLHttpRequest.prototype.send; XMLHttpRequest.prototype.send = function() {"
        "  this.addEventListener('load', function() {"
        "    try { window.webkit.messageHandlers.network.postMessage({url: this._url, method: this._method, status: this.status}); } catch(e) {}"
        "  });"
        "  originalSend.apply(this, arguments);"
        "};"
        "var originalFetch = window.fetch; window.fetch = function() {"
        "  var args = arguments; return originalFetch.apply(this, arguments).then(function(response) {"
        "    try { window.webkit.messageHandlers.network.postMessage({url: response.url, method: 'FETCH', status: response.status}); } catch(e) {}"
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

    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(handleRefresh:) forControlEvents:UIControlEventValueChanged];
    self.webView.scrollView.refreshControl = refreshControl;

    self.urlField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 240, 36)];
    self.urlField.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12];
    self.urlField.textColor = [UIColor whiteColor];
    self.urlField.layer.cornerRadius = 12;
    self.urlField.layer.borderWidth = 1.0;
    self.urlField.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2].CGColor;
    self.urlField.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.urlField.keyboardType = UIKeyboardTypeURL;
    self.urlField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.urlField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.urlField.delegate = self;
    self.urlField.textAlignment = NSTextAlignmentCenter;
    self.urlField.placeholder = @"検索またはURLを入力";

    UIImageView *searchIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]];
    searchIcon.tintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.4];
    searchIcon.contentMode = UIViewContentModeScaleAspectFit;
    UIView *leftPadding = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 32, 20)];
    searchIcon.frame = CGRectMake(10, 0, 16, 20);
    [leftPadding addSubview:searchIcon];
    self.urlField.leftView = leftPadding;
    self.urlField.leftViewMode = UITextFieldViewModeAlways;

    self.navigationItem.titleView = self.urlField;

    UIBarButtonItem *menuBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(showBrowserOthersMenu)];
    self.navigationItem.leftBarButtonItem = menuBtn;

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

    self.startPage = [[WebStartPageView alloc] initWithFrame:self.view.bounds];
    self.startPage.translatesAutoresizingMaskIntoConstraints = NO;
    self.startPage.onBookmarkSelect = ^(NSString *url) { [weakSelf.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:url]]]; };
    self.startPage.onSearch = ^(NSString *query) {
        UITextField *dummy = [[UITextField alloc] init];
        dummy.text = query;
        [weakSelf textFieldShouldReturn:dummy];
    };
    [self.view addSubview:self.startPage];

    [NSLayoutConstraint activateConstraints:@[
        [self.progressView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor], [self.progressView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.progressView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [self.progressView.heightAnchor constraintEqualToConstant:2],
        [self.webView.topAnchor constraintEqualToAnchor:self.progressView.bottomAnchor], [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [self.webView.bottomAnchor constraintEqualToAnchor:self.bottomMenu.topAnchor],
        [self.bottomMenu.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.bottomMenu.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [self.bottomMenu.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor], [self.bottomMenu.heightAnchor constraintEqualToConstant:80],
        [self.startPage.topAnchor constraintEqualToAnchor:self.progressView.bottomAnchor], [self.startPage.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.startPage.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [self.startPage.bottomAnchor constraintEqualToAnchor:self.bottomMenu.topAnchor],
    ]];
    self.startPage.hidden = (self.initialURL != nil);
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.name isEqualToString:@"logger"]) {
        NSString *log = [NSString stringWithFormat:@"%@", message.body];
        if (log.length > 0) [self.consoleLogs addObject:log];
    } else if ([message.name isEqualToString:@"network"]) {
        if ([message.body isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *dict = [message.body mutableCopy];
            dict[@"time"] = [[NSDate date] description];
            [self.networkLogs addObject:dict];
        }
    }
}

- (void)prepareAndShowInspector {
    [self.webView evaluateJavaScript:@"document.documentElement.outerHTML" completionHandler:^(id html, NSError *error) {
        [self.webView evaluateJavaScript:@"(function(){ return {local: JSON.stringify(localStorage), session: JSON.stringify(sessionStorage)}; })();" completionHandler:^(id storage, NSError *error2) {
            [self.webView.configuration.websiteDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    WebInspectorViewController *vc = [[WebInspectorViewController alloc] init];
                    vc.htmlSource = html ?: @"";
                    vc.consoleLogs = self.consoleLogs;
                    vc.networkLogs = self.networkLogs;
                    vc.cookies = cookies ?: @[];

                    if ([storage isKindOfClass:[NSDictionary class]]) {
                        NSDictionary *sDict = (NSDictionary *)storage;
                        NSMutableDictionary *finalStorage = [NSMutableDictionary dictionary];
                        if (sDict[@"local"]) finalStorage[@"local"] = [NSJSONSerialization JSONObjectWithData:[sDict[@"local"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
                        if (sDict[@"session"]) finalStorage[@"session"] = [NSJSONSerialization JSONObjectWithData:[sDict[@"session"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
                        vc.storageData = finalStorage;
                    }

                    __weak typeof(self) weakSelf = self;
                    vc.onCommand = ^(NSString *command) {
                        if (command.length > 0) {
                            [weakSelf.webView evaluateJavaScript:command completionHandler:^(id result, NSError *jsError) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    NSString *echo = result ? [NSString stringWithFormat:@"OUT> %@", result] : (jsError ? [NSString stringWithFormat:@"ERR> %@", jsError.localizedDescription] : @"OUT> undefined");
                                    [weakSelf.consoleLogs addObject:echo];
                                });
                            }];
                        }
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
    NSURL *target = [NSURL URLWithString:urlStr];
    if (target) [self.webView loadRequest:[NSURLRequest requestWithURL:target]];
    [textField resignFirstResponder];
    return YES;
}



- (void)refreshUI {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
        self.startPage.backgroundColor = [ThemeEngine mainBackgroundColor];
        [self.bottomMenu setupUI];
        // Other UI updates if needed
    });
}

- (void)bookmarkCurrentPage {
    NSString *url = self.webView.URL.absoluteString;
    NSString *title = self.webView.title;
    if (url) {
        [[WebBookmarksManager sharedManager] addBookmarkWithTitle:title url:url];
        [self.startPage reloadBookmarks];
        [[Logger sharedLogger] log:[NSString stringWithFormat:@"[BROWSER] Bookmarked: %@", url]];
    }
}


- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (!self.isPrivateMode) {
        NSSet *websiteDataTypes = [NSSet setWithArray:@[WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]];
        NSDate *dateFrom = [NSDate dateWithTimeIntervalSince1970:0];
        [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:websiteDataTypes modifiedSince:dateFrom completionHandler:^{}];
    }
    TabInfo *active = [[TabManager sharedManager] activeTab];
    if (active && active.type == TabTypeWebBrowser) { active.currentPath = webView.URL.absoluteString; active.title = webView.title.length > 0 ? webView.title : @"Browser"; }
    self.urlField.text = webView.URL.absoluteString;
    self.startPage.hidden = (webView.URL != nil && ![webView.URL.absoluteString isEqualToString:@"about:blank"]);
    if (webView.URL && ![webView.URL.absoluteString isEqualToString:@"about:blank"]) {
        [[WebHistoryManager sharedManager] addHistoryEntryWithTitle:webView.title url:webView.URL.absoluteString];
    }
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    NSString *ext = url.pathExtension.lowercaseString;
    if ([@[@"zip", @"rar", @"7z", @"tar", @"gz", @"ipa", @"deb", @"mp4", @"mov", @"mp3", @"pdf"] containsObject:ext]) {
        [self triggerDownloadWithURL:url];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}





- (void)promptFindOnPage {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ページ内検索" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"検索ワード"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"検索" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *query = alert.textFields[0].text;
        if (query.length > 0) {
            NSString *js = [NSString stringWithFormat:@"window.find('%@', false, false, true, false, false, true)", query];
            [self.webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
                if ([result boolValue] == NO) {
                    [[Logger sharedLogger] log:@"[BROWSER] No matches found for search"];
                }
            }];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showUserAgentMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"User-Agent設定"];
    BOOL isDesktop = (self.webView.customUserAgent != nil);

    NSString *mobileTitle = isDesktop ? @"モバイル" : @"モバイル (有効)";
    NSString *desktopTitle = isDesktop ? @"デスクトップ (有効)" : @"デスクトップ";

    [menu addAction:[CustomMenuAction actionWithTitle:mobileTitle systemImage:@"iphone" style:CustomMenuActionStyleDefault handler:^{
        [self applyUserAgent:NO];
    }]];
    [menu addAction:[CustomMenuAction actionWithTitle:desktopTitle systemImage:@"desktopcomputer" style:CustomMenuActionStyleDefault handler:^{
        [self applyUserAgent:YES];
    }]];
    [menu showInView:self.view];
}

- (void)applyUserAgent:(BOOL)desktop {
    NSString *ua = desktop ? @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15" : nil;
    self.webView.customUserAgent = ua;
    [self.webView reload];
    [[Logger sharedLogger] log:[NSString stringWithFormat:@"[BROWSER] User-Agent changed to: %@", desktop ? @"Desktop" : @"Mobile"]];
}

- (void)showHistory {
    WebHistoryViewController *vc = [[WebHistoryViewController alloc] init];
    __weak typeof(self) weakSelf = self;
    vc.onUrlSelected = ^(NSString *url) {
        [weakSelf.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:url]]];
    };
    [self.navigationController pushViewController:vc animated:YES];
}


- (void)togglePrivateMode {
    self.isPrivateMode = !self.isPrivateMode;
    [[Logger sharedLogger] log:[NSString stringWithFormat:@"[BROWSER] Private Mode: %@", self.isPrivateMode ? @"ON" : @"OFF"]];

    // Re-initialize WebView with correct data store
    [self.webView removeFromSuperview];
    [self.webView removeObserver:self forKeyPath:@"estimatedProgress"];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.websiteDataStore = self.isPrivateMode ? [WKWebsiteDataStore nonPersistentDataStore] : [WKWebsiteDataStore defaultDataStore];

    // Restore message handlers
    WKUserContentController *userContent = [[WKUserContentController alloc] init];
    WeakScriptMessageProxy *proxy = [[WeakScriptMessageProxy alloc] init];
    proxy.delegate = self;
    [userContent addScriptMessageHandler:proxy name:@"logger"];
    [userContent addScriptMessageHandler:proxy name:@"network"];
    config.userContentController = userContent;

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    [self.view insertSubview:self.webView belowSubview:self.progressView];

    [NSLayoutConstraint activateConstraints:@[
        [self.webView.topAnchor constraintEqualToAnchor:self.progressView.bottomAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.bottomMenu.topAnchor],
    ]];

    [self.webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];

    if (self.webView.URL) [self.webView reload];
    else [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]]];
}

- (void)showBrowserOthersMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"ブラウザ操作"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"再読み込み" systemImage:@"arrow.clockwise" style:CustomMenuActionStyleDefault handler:^{ [self.webView reload]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"URLをコピー" systemImage:@"doc.on.doc" style:CustomMenuActionStyleDefault handler:^{ [[UIPasteboard generalPasteboard] setString:self.webView.URL.absoluteString]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"このページをブックマーク" systemImage:@"star" style:CustomMenuActionStyleDefault handler:^{ [self bookmarkCurrentPage]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"履歴" systemImage:@"clock" style:CustomMenuActionStyleDefault handler:^{ [self showHistory]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"User-Agent切替" systemImage:@"person.crop.circle.badge.questionmark" style:CustomMenuActionStyleDefault handler:^{ [self showUserAgentMenu]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"Cookieの管理" systemImage:@"lock.shield" style:CustomMenuActionStyleDefault handler:^{ [self showCookieEditor]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"ページ内検索" systemImage:@"magnifyingglass" style:CustomMenuActionStyleDefault handler:^{ [self promptFindOnPage]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"ページを共有" systemImage:@"square.and.arrow.up" style:CustomMenuActionStyleDefault handler:^{ [self handleMenuAction:BottomMenuActionWebShare]; }]];

    NSString *privateTitle = self.isPrivateMode ? @"プライベートモード: ON" : @"プライベートモード: OFF";
    [menu addAction:[CustomMenuAction actionWithTitle:privateTitle systemImage:@"eye.slash" style:CustomMenuActionStyleDefault handler:^{ [self togglePrivateMode]; }]];

    NSString *adBlockTitle = self.isAdBlockEnabled ? @"広告ブロック: ON" : @"広告ブロック: OFF";
    [menu addAction:[CustomMenuAction actionWithTitle:adBlockTitle systemImage:@"shield.fill" style:CustomMenuActionStyleDefault handler:^{ [self toggleAdBlock]; }]];

    [menu showInView:self.view];
}

- (void)showCookieEditor {
    CookieEditorViewController *vc = [[CookieEditorViewController alloc] init];
    vc.cookieStore = self.webView.configuration.websiteDataStore.httpCookieStore;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)handleMenuAction:(BottomMenuAction)action {
    switch (action) {
        case BottomMenuActionWebBack: [self.webView goBack]; break;
        case BottomMenuActionWebForward: [self.webView goForward]; break;
        case BottomMenuActionWebShare: { if (self.webView.URL) { UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[self.webView.URL] applicationActivities:nil]; [self presentViewController:avc animated:YES completion:nil]; } break; }
        case BottomMenuActionWebHome: { [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]]]; break; }
        case BottomMenuActionOthers: [self showBrowserOthersMenu]; break;
        case BottomMenuActionDownloads: { DownloadsViewController *vc = [[DownloadsViewController alloc] init]; [self.navigationController pushViewController:vc animated:YES]; break; }
        case BottomMenuActionTabs: { MainContainerViewController *container = (MainContainerViewController *)self.view.window.rootViewController; if ([container isKindOfClass:[MainContainerViewController class]]) [container showTabSwitcher]; break; }
        case BottomMenuActionIdevice: { MainContainerViewController *container = (MainContainerViewController *)self.view.window.rootViewController; if ([container isKindOfClass:[MainContainerViewController class]]) [container handleMenuAction:action]; break; }
        default: break;
    }
}

- (void)triggerDownloadWithURL:(NSURL *)url {
    if (!url) return;
    // Derive download path from the effective home to ensure it's within the virtual sandbox
    NSString *home = [FileManagerCore effectiveHomeDirectory];
    NSString *downloadsPath = [[home stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:@"Downloads"];

    // In virtualization environments, we must ensure the path passed to DownloadManager
    // is one that can be correctly relativized.

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1" forHTTPHeaderField:@"User-Agent"];
    [self.webView.configuration.websiteDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        [request setAllHTTPHeaderFields:[NSHTTPCookie requestHeaderFieldsWithCookies:cookies]];
        dispatch_async(dispatch_get_main_queue(), ^{ [[DownloadManager sharedManager] downloadFileWithRequest:request toPath:downloadsPath];  });
    }];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"estimatedProgress"]) {
        self.progressView.progress = self.webView.estimatedProgress;
        self.progressView.hidden = (self.webView.estimatedProgress >= 1.0);
    }
}


- (void)toggleAdBlock {
    self.isAdBlockEnabled = !self.isAdBlockEnabled;
    [[Logger sharedLogger] log:[NSString stringWithFormat:@"[BROWSER] Ad-block: %@", self.isAdBlockEnabled ? @"ON" : @"OFF"]];

    if (self.isAdBlockEnabled) {
        [self applyAdBlockRules];
    } else {
        [self removeAdBlockRules];
    }
}

- (void)applyAdBlockRules {
    NSString *jsonRules = @"[ { \"trigger\": { \"url-filter\": \".*doubleclick.net.*\" }, \"action\": { \"type\": \"block\" } }, { \"trigger\": { \"url-filter\": \".*google-analytics.com.*\" }, \"action\": { \"type\": \"block\" } }, { \"trigger\": { \"url-filter\": \".*googlesyndication.com.*\" }, \"action\": { \"type\": \"block\" } } ]";

    if (@available(iOS 11.0, *)) {
        [[WKContentRuleListStore defaultStore] compileContentRuleListForIdentifier:@"AdBlockList" encodedContentRuleList:jsonRules completionHandler:^(WKContentRuleList *list, NSError *error) {
            if (list) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.webView.configuration.userContentController addContentRuleList:list];
                    [self.webView reload];
                });
            }
        }];
    }
}

- (void)removeAdBlockRules {
    if (@available(iOS 11.0, *)) {
        [self.webView.configuration.userContentController removeAllContentRuleLists];
        [self.webView reload];
    }
}


- (void)handleRefresh:(UIRefreshControl *)sender {
    [self.webView reload];
    [sender endRefreshing];
}
@end
