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
#import <Network/Network.h>

static WKWebsiteDataStore *_nonPersistentStore = nil;
static NSString * const kDesktopUserAgent = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15";

@interface LocalHTTPFileServer : NSObject
@property (nonatomic, assign) nw_listener_t listener;
@property (nonatomic, copy) NSString *rootDirectory;
@property (nonatomic, assign) uint16_t port;
- (BOOL)startWithDirectory:(NSString *)directory port:(uint16_t)port;
- (void)stop;
@end

@implementation LocalHTTPFileServer

- (NSData *)dataFromDispatchData:(dispatch_data_t)data {
    if (!data) return [NSData data];
    __block NSMutableData *buffer = [NSMutableData data];
    dispatch_data_apply(data, ^bool(dispatch_data_t region, size_t offset, const void *bytes, size_t size) {
        [buffer appendBytes:bytes length:size];
        return true;
    });
    return buffer;
}

- (NSString *)mimeTypeForPath:(NSString *)path {
    NSString *ext = path.pathExtension.lowercaseString;
    NSDictionary<NSString *, NSString *> *map = @{@"html":@"text/html; charset=utf-8", @"htm":@"text/html; charset=utf-8", @"js":@"application/javascript", @"css":@"text/css", @"json":@"application/json", @"wasm":@"application/wasm", @"png":@"image/png", @"jpg":@"image/jpeg", @"jpeg":@"image/jpeg", @"gif":@"image/gif", @"svg":@"image/svg+xml", @"txt":@"text/plain; charset=utf-8"};
    return map[ext] ?: @"application/octet-stream";
}

- (NSData *)responseForRequestData:(NSData *)requestData {
    NSString *request = [[NSString alloc] initWithData:requestData encoding:NSUTF8StringEncoding] ?: @"";
    NSArray<NSString *> *lines = [request componentsSeparatedByString:@"\r\n"];
    NSString *requestLine = lines.firstObject ?: @"";
    NSArray<NSString *> *parts = [requestLine componentsSeparatedByString:@" "];
    NSString *method = parts.count > 0 ? parts[0] : @"";
    NSString *pathPart = parts.count > 1 ? parts[1] : @"/";
    NSRange queryRange = [pathPart rangeOfString:@"?"];
    if (queryRange.location != NSNotFound) pathPart = [pathPart substringToIndex:queryRange.location];
    if (![method isEqualToString:@"GET"]) {
        return [@"HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    }

    NSString *decodedPath = [pathPart stringByRemovingPercentEncoding] ?: @"/";
    if ([decodedPath hasPrefix:@"/"]) decodedPath = [decodedPath substringFromIndex:1];
    if (decodedPath.length == 0) decodedPath = @"index.html";
    while ([decodedPath hasPrefix:@"/"]) decodedPath = [decodedPath substringFromIndex:1];
    if ([decodedPath containsString:@".."] || [decodedPath containsString:@"\\"]) {
        return [@"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    }

    NSString *fullPath = [self.rootDirectory stringByAppendingPathComponent:decodedPath];
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory:&isDir] && isDir) {
        fullPath = [fullPath stringByAppendingPathComponent:@"index.html"];
    }
    NSData *body = [NSData dataWithContentsOfFile:fullPath];
    if (!body) {
        body = [@"404 Not Found" dataUsingEncoding:NSUTF8StringEncoding];
        NSString *header = [NSString stringWithFormat:@"HTTP/1.1 404 Not Found\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n", (unsigned long)body.length];
        NSMutableData *res = [NSMutableData dataWithData:[header dataUsingEncoding:NSUTF8StringEncoding]];
        [res appendData:body];
        return res;
    }

    NSString *mime = [self mimeTypeForPath:fullPath];
    NSString *header = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: %@\r\nContent-Length: %lu\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n", mime, (unsigned long)body.length];
    NSMutableData *res = [NSMutableData dataWithData:[header dataUsingEncoding:NSUTF8StringEncoding]];
    [res appendData:body];
    return res;
}

- (void)handleConnection:(nw_connection_t)connection {
    nw_connection_set_queue(connection, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    nw_connection_start(connection);
    __weak typeof(self) weakSelf = self;
    nw_connection_receive(connection, 1, 65536, ^(dispatch_data_t content, nw_content_context_t context, bool isComplete, nw_error_t error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || error || !content) {
            nw_connection_cancel(connection);
            return;
        }
        NSData *requestData = [self dataFromDispatchData:content];
        NSData *responseData = [self responseForRequestData:requestData];
        dispatch_data_t out = dispatch_data_create(responseData.bytes, responseData.length, dispatch_get_main_queue(), DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        nw_connection_send(connection, out, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t sendError) {
            (void)sendError;
            nw_connection_cancel(connection);
        });
    });
}

- (BOOL)startWithDirectory:(NSString *)directory port:(uint16_t)port {
    [self stop];
    self.rootDirectory = directory;
    self.port = port;
    NSString *portString = [NSString stringWithFormat:@"%hu", port];
    nw_parameters_t parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
    nw_listener_t listener = nw_listener_create_with_port(portString.UTF8String, parameters);
    if (!listener) return NO;
    self.listener = listener;
    nw_listener_set_queue(listener, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    __weak typeof(self) weakSelf = self;
    nw_listener_set_new_connection_handler(listener, ^(nw_connection_t connection) {
        [weakSelf handleConnection:connection];
    });
    nw_listener_start(listener);
    return YES;
}

- (void)stop {
    if (self.listener) {
        nw_listener_cancel(self.listener);
        self.listener = NULL;
    }
}

@end

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
@property (nonatomic, assign) BOOL isDesktopMode;
@property (nonatomic, assign) BOOL javaScriptEnabled;
@property (nonatomic, strong) LocalHTTPFileServer *localFileServer;

- (void)promptAndRunWebAssembly;
- (void)runWebAssemblyWithURLString:(NSString *)wasmURL exportName:(NSString *)exportName;
- (void)promptAndToggleLocalFileServer;
- (NSString *)sanitizedRelativeDirectory:(NSString *)raw;
- (NSString *)defaultHTMLRelativePathInDirectory:(NSString *)directory;
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
        _localFileServer = [[LocalHTTPFileServer alloc] init];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ThemeEngine bg];
    [self setupUI];
    [self applySettingsAndRefreshWebViewIfNeeded:NO];
    if (self.initialURL) {
        NSURL *url = [NSURL URLWithString:self.initialURL];
        if (url) [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
    }
    [self.webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshUI) name:@"SettingsChanged" object:nil];
}

- (void)dealloc {
    [self.localFileServer stop];
    [self.webView removeObserver:self forKeyPath:@"estimatedProgress"];
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"logger"];
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"network"];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (WKUserContentController *)configuredUserContentController {
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
    return userContent;
}

- (WKWebsiteDataStore *)effectiveDataStoreForURLString:(NSString *)urlString {
    if (self.isPrivateMode) return [WKWebsiteDataStore nonPersistentDataStore];
    if ([[PersistenceManager sharedManager] isDomainPersistent:urlString]) return [WKWebsiteDataStore defaultDataStore];
    return [WebBrowserViewController sharedDataStore];
}

- (WKWebView *)buildWebViewWithDataStore:(WKWebsiteDataStore *)dataStore {
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.userContentController = [self configuredUserContentController];
    WKWebpagePreferences *pagePreferences = [[WKWebpagePreferences alloc] init];
    pagePreferences.allowsContentJavaScript = self.javaScriptEnabled;
    config.defaultWebpagePreferences = pagePreferences;
    config.websiteDataStore = dataStore;

    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    webView.translatesAutoresizingMaskIntoConstraints = NO;
    webView.navigationDelegate = self;
    webView.UIDelegate = self;
    webView.allowsBackForwardNavigationGestures = YES;
    webView.customUserAgent = self.isDesktopMode ? kDesktopUserAgent : nil;
    webView.backgroundColor = [UIColor clearColor];
    webView.opaque = NO;

    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(handleRefresh:) forControlEvents:UIControlEventValueChanged];
    webView.scrollView.refreshControl = refreshControl;
    return webView;
}

- (void)setupUI {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.javaScriptEnabled = [defaults objectForKey:@"WebJavaScript"] ? [defaults boolForKey:@"WebJavaScript"] : YES;
    self.isAdBlockEnabled = [defaults boolForKey:@"AdBlocker"];
    self.isDesktopMode = [defaults boolForKey:@"DesktopMode"];

    self.webView = [self buildWebViewWithDataStore:[self effectiveDataStoreForURLString:self.initialURL]];
    [self.view addSubview:self.webView];

    // ── URL pill field (iOS 26 design) ──────────────────────────────────────
    UIView *urlPillContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 280, 38)];
    [ThemeEngine applyGlassToView:urlPillContainer radius:19];
    urlPillContainer.layer.shadowColor = [UIColor blackColor].CGColor;
    urlPillContainer.layer.shadowOffset = CGSizeMake(0,3);
    urlPillContainer.layer.shadowOpacity = 0.35;
    urlPillContainer.layer.shadowRadius = 8;

    self.urlField = [[UITextField alloc] initWithFrame:CGRectMake(8, 0, 248, 38)];
    self.urlField.backgroundColor = [UIColor clearColor];
    self.urlField.textColor = [ThemeEngine textPrimary];
    self.urlField.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.urlField.keyboardType = UIKeyboardTypeURL;
    self.urlField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.urlField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.urlField.returnKeyType = UIReturnKeyGo;
    self.urlField.delegate = self;
    self.urlField.textAlignment = NSTextAlignmentCenter;
    self.urlField.attributedPlaceholder = [[NSAttributedString alloc]
        initWithString:@"検索またはURLを入力"
        attributes:@{NSForegroundColorAttributeName: [ThemeEngine textTertiary]}];

    // Lock icon left view
    UIImageSymbolConfiguration *lockCfg = [UIImageSymbolConfiguration
        configurationWithPointSize:12 weight:UIImageSymbolWeightMedium];
    UIImageView *lockIcon = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"magnifyingglass" withConfiguration:lockCfg]];
    lockIcon.tintColor = [ThemeEngine textTertiary];
    lockIcon.contentMode = UIViewContentModeScaleAspectFit;
    UIView *leftPad = [[UIView alloc] initWithFrame:CGRectMake(0,0,30,20)];
    lockIcon.frame = CGRectMake(10,0,14,20);
    [leftPad addSubview:lockIcon];
    self.urlField.leftView = leftPad;
    self.urlField.leftViewMode = UITextFieldViewModeAlways;

    [urlPillContainer addSubview:self.urlField];
    self.navigationItem.titleView = urlPillContainer;

    UIBarButtonItem *menuBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"ellipsis.circle.fill"]
                style:UIBarButtonItemStylePlain target:self action:@selector(showBrowserOthersMenu)];
    menuBtn.tintColor = [ThemeEngine accent];
    self.navigationItem.leftBarButtonItem = menuBtn;

    UIBarButtonItem *inspectorBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"terminal"]
                style:UIBarButtonItemStylePlain target:self action:@selector(prepareAndShowInspector)];
    inspectorBtn.tintColor = [ThemeEngine textSecondary];
    self.navigationItem.rightBarButtonItem = inspectorBtn;

    // ── Progress bar ─────────────────────────────────────────────────────
    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressView.progressTintColor = [ThemeEngine accent];
    self.progressView.trackTintColor = [UIColor clearColor];
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

    if (self.isAdBlockEnabled) {
        [self applyAdBlockRules];
    }
}

- (void)promptAndRunWebAssembly {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"WebAssembly実行"
                                                                   message:@"Wasm URL と実行したい export 関数名（任意）を指定"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"https://example.com/module.wasm";
        textField.keyboardType = UIKeyboardTypeURL;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"main (任意)";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"実行" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *wasmURL = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *exportName = [alert.textFields.lastObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (wasmURL.length == 0) return;
        [self runWebAssemblyWithURLString:wasmURL exportName:exportName];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)runWebAssemblyWithURLString:(NSString *)wasmURL exportName:(NSString *)exportName {
    NSString *escapedURL = [[wasmURL stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    NSString *escapedExport = [[exportName stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];

    NSString *js = [NSString stringWithFormat:
                    @"(async function(){"
                    "const u=\"%@\";const fn=\"%@\";"
                    "const timeout=new Promise((_,rej)=>setTimeout(()=>rej(new Error('WASM timeout')),8000));"
                    "const run=(async()=>{"
                    "const r=await fetch(u,{cache:'no-store'});"
                    "if(!r.ok) throw new Error('fetch failed: '+r.status);"
                    "const bytes=await r.arrayBuffer();"
                    "const mod=await WebAssembly.instantiate(bytes,{});"
                    "if(fn&&mod.instance.exports[fn]){return mod.instance.exports[fn]();}"
                    "return Object.keys(mod.instance.exports);"
                    "})();"
                    "return await Promise.race([run,timeout]);"
                    "})();", escapedURL, escapedExport];

    __weak typeof(self) weakSelf = self;
    [self.webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *log = error ? [NSString stringWithFormat:@"WASM ERR: %@", error.localizedDescription] : [NSString stringWithFormat:@"WASM OK: %@", result ?: @"(null)"];
            [weakSelf.consoleLogs addObject:log];
            [[Logger sharedLogger] log:[NSString stringWithFormat:@"[BROWSER] %@", log]];
        });
    }];
}

- (NSString *)sanitizedRelativeDirectory:(NSString *)raw {
    NSString *trim = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trim.length == 0) return nil;
    NSString *normalized = [trim stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    while ([normalized hasPrefix:@"/"]) normalized = [normalized substringFromIndex:1];
    if ([normalized containsString:@".."] || [normalized hasPrefix:@"~"]) return nil;
    return normalized;
}

- (NSString *)defaultHTMLRelativePathInDirectory:(NSString *)directory {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *preferred = @[@"index.html", @"index.htm", @"main.html", @"default.html"];
    for (NSString *name in preferred) {
        NSString *path = [directory stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:path isDirectory:&isDir] && !isDir) return name;
    }

    NSDirectoryEnumerator *enumerator = [fm enumeratorAtURL:[NSURL fileURLWithPath:directory]
                                  includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                     options:NSDirectoryEnumerationSkipsHiddenFiles
                                                errorHandler:nil];
    for (NSURL *url in enumerator) {
        NSNumber *isDir = nil;
        [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        if (isDir.boolValue) continue;
        NSString *ext = url.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"html"] || [ext isEqualToString:@"htm"]) {
            NSString *full = url.path;
            if ([full hasPrefix:directory]) {
                NSString *rel = [full substringFromIndex:directory.length];
                while ([rel hasPrefix:@"/"]) rel = [rel substringFromIndex:1];
                if (rel.length) return rel;
            }
        }
    }
    return @"index.html";
}

- (void)promptAndToggleLocalFileServer {
    if (self.localFileServer.listener) {
        [self.localFileServer stop];
        [[Logger sharedLogger] log:@"[BROWSER] Local file server stopped"];
        return;
    }

    NSString *home = [FileManagerCore effectiveHomeDirectory];
    NSString *docs = [home stringByAppendingPathComponent:@"Documents"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ローカルWebサーバー起動"
                                                                   message:@"Documents配下のディレクトリ（相対）とポートを指定"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"例: WebRoot";
        textField.text = @"WebRoot";
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"8080";
        textField.keyboardType = UIKeyboardTypeNumberPad;
        textField.text = @"8080";
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"起動" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSString *relativeDir = [self sanitizedRelativeDirectory:alert.textFields.firstObject.text ?: @""];
        NSString *portText = [alert.textFields.lastObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (relativeDir.length == 0) {
            [[Logger sharedLogger] log:@"[BROWSER] Local server start failed: invalid directory path"];
            return;
        }

        NSString *target = [docs stringByAppendingPathComponent:relativeDir];
        BOOL isDir = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:target isDirectory:&isDir] || !isDir) {
            [[Logger sharedLogger] log:[NSString stringWithFormat:@"[BROWSER] Local server start failed: directory not found %@", target]];
            return;
        }

        NSInteger portValue = portText.integerValue;
        if (portValue <= 0 || portValue > 65535) portValue = 8080;
        BOOL started = [self.localFileServer startWithDirectory:target port:(uint16_t)portValue];
        if (!started) {
            [[Logger sharedLogger] log:@"[BROWSER] Local server start failed"];
            return;
        }

        NSString *htmlPath = [self defaultHTMLRelativePathInDirectory:target];
        NSString *escapedHTML = [htmlPath stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]] ?: @"index.html";
        NSString *urlString = [NSString stringWithFormat:@"http://127.0.0.1:%ld/%@", (long)portValue, escapedHTML];
        [[Logger sharedLogger] log:[NSString stringWithFormat:@"[BROWSER] Local server started: %@ -> %@", urlString, target]];
        [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlString]]];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
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

- (void)applySettingsAndRefreshWebViewIfNeeded:(BOOL)allowReload {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL newDesktopMode = [defaults boolForKey:@"DesktopMode"];
    BOOL newAdBlock = [defaults boolForKey:@"AdBlocker"];
    BOOL newJavaScriptEnabled = [defaults objectForKey:@"WebJavaScript"] ? [defaults boolForKey:@"WebJavaScript"] : YES;

    BOOL javaScriptChanged = (newJavaScriptEnabled != self.javaScriptEnabled);
    self.isDesktopMode = newDesktopMode;
    self.webView.customUserAgent = self.isDesktopMode ? kDesktopUserAgent : nil;

    if (newAdBlock != self.isAdBlockEnabled) {
        self.isAdBlockEnabled = newAdBlock;
        if (self.isAdBlockEnabled) [self applyAdBlockRules];
        else [self removeAdBlockRules];
    }

    if (allowReload && javaScriptChanged) {
        self.javaScriptEnabled = newJavaScriptEnabled;
        NSURL *currentURL = self.webView.URL;
        [self.webView removeObserver:self forKeyPath:@"estimatedProgress"];
        [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"logger"];
        [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"network"];
        [self.webView removeFromSuperview];

        self.webView = [self buildWebViewWithDataStore:[self effectiveDataStoreForURLString:currentURL.absoluteString ?: self.initialURL]];
        [self.view insertSubview:self.webView belowSubview:self.progressView];

        [NSLayoutConstraint activateConstraints:@[
            [self.webView.topAnchor constraintEqualToAnchor:self.progressView.bottomAnchor],
            [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [self.webView.bottomAnchor constraintEqualToAnchor:self.bottomMenu.topAnchor],
        ]];

        [self.webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];

        NSURL *target = currentURL ?: [NSURL URLWithString:@"about:blank"];
        [self.webView loadRequest:[NSURLRequest requestWithURL:target]];
    } else {
        self.javaScriptEnabled = newJavaScriptEnabled;
    }
}



- (void)refreshUI {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.view.backgroundColor = [ThemeEngine bg];
        self.startPage.backgroundColor = [ThemeEngine bg];
        [self applySettingsAndRefreshWebViewIfNeeded:YES];
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
    NSString *ua = desktop ? kDesktopUserAgent : nil;
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

    NSURL *previousURL = self.webView.URL;
    [self.webView removeObserver:self forKeyPath:@"estimatedProgress"];
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"logger"];
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"network"];
    [self.webView removeFromSuperview];

    self.webView = [self buildWebViewWithDataStore:[self effectiveDataStoreForURLString:previousURL.absoluteString ?: self.initialURL]];
    [self.view insertSubview:self.webView belowSubview:self.progressView];

    [NSLayoutConstraint activateConstraints:@[
        [self.webView.topAnchor constraintEqualToAnchor:self.progressView.bottomAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.bottomMenu.topAnchor],
    ]];

    [self.webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];

    if (previousURL) [self.webView loadRequest:[NSURLRequest requestWithURL:previousURL]];
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
    [menu addAction:[CustomMenuAction actionWithTitle:@"WebAssembly実行" systemImage:@"cpu" style:CustomMenuActionStyleDefault handler:^{ [self promptAndRunWebAssembly]; }]];
    NSString *serverTitle = self.localFileServer.listener ? @"ローカルWebサーバー停止" : @"ローカルWebサーバー起動";
    [menu addAction:[CustomMenuAction actionWithTitle:serverTitle systemImage:@"network" style:CustomMenuActionStyleDefault handler:^{ [self promptAndToggleLocalFileServer]; }]];

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
        case BottomMenuActionWebHome: {
            NSString *home = [[NSUserDefaults standardUserDefaults] stringForKey:@"WebHomepage"] ?: @"about:blank";
            NSURL *homeURL = [NSURL URLWithString:home];
            if (!homeURL || (!homeURL.scheme && [home containsString:@"."])) {
                homeURL = [NSURL URLWithString:[@"https://" stringByAppendingString:home]];
            }
            if (!homeURL) homeURL = [NSURL URLWithString:@"about:blank"];
            [self.webView loadRequest:[NSURLRequest requestWithURL:homeURL]];
            break;
        }
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
    NSString *ua = self.webView.customUserAgent;
    if (ua.length > 0) {
        [request setValue:ua forHTTPHeaderField:@"User-Agent"];
    }
    [self.webView.configuration.websiteDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        NSDictionary *cookieHeaders = [NSHTTPCookie requestHeaderFieldsWithCookies:cookies];
        for (NSString *key in cookieHeaders) {
            [request setValue:cookieHeaders[key] forHTTPHeaderField:key];
        }
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
