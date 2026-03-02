#import "WebBrowserViewController.h"
#import "ThemeEngine.h"
#import "MainContainerViewController.h"
#import "BottomMenuView.h"

@interface WebBrowserViewController ()
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UITextField *urlField;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) BottomMenuView *bottomMenu;
@end

@implementation WebBrowserViewController

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
    config.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
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
    if (![urlStr hasPrefix:@"http"]) urlStr = [@"https://" stringByAppendingString:urlStr];
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
        case BottomMenuActionTabs: {
            MainContainerViewController *container = (MainContainerViewController *)self.view.window.rootViewController;
            if ([container isKindOfClass:[MainContainerViewController class]]) [container showTabSwitcher];
            break;
        }
        default: break;
    }
}

@end
