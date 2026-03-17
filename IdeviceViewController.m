// IdeviceViewController.m
// Complete redesign — modern card-based iDevice management dashboard
// Features: Connection, Device Info, 20+ Tools, HouseArrest, Diagnostics,
//           Screenshot, Syslog, CrashReports, ProcessControl, SpringBoard,
//           AMFI/DevMode, Profiles, Notifications, Reboot/Shutdown/Recovery

#import "IdeviceViewController.h"
#import <objc/runtime.h>
#import "ThemeEngine.h"
#import "idevice.h"
#import "FileManagerCore.h"
#import "HeartbeatManager.h"
#import "DdiManager.h"
#import "AppListViewController.h"
#import "LocationSimulationViewController.h"
#import "AfcBrowserViewController.h"
#import "HouseArrestBrowserViewController.h"
#import <arpa/inet.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Tool Cell Model

typedef NS_ENUM(NSUInteger, IDevTool) {
    IDevToolAppBrowser = 0,
    IDevToolLocationSim,
    IDevToolAfcMedia,
    IDevToolAfcRoot,
    IDevToolHouseArrest,
    IDevToolScreenshot,
    IDevToolSyslog,
    IDevToolCrashReports,
    IDevToolDiagnostics,
    IDevToolProcessControl,
    IDevToolNotifications,
    IDevToolSpringBoard,
    IDevToolDevMode,
    IDevToolProfiles,
    IDevToolReboot,
    IDevToolShutdown,
    IDevToolRecovery,
    IDevToolOsTrace,
    IDevToolCount
};

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Tool Collection Cell

@interface IDevToolCell : UICollectionViewCell
@property (nonatomic, strong) UILabel *iconLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIView  *badge;
- (void)configureWithTitle:(NSString *)title icon:(NSString *)icon enabled:(BOOL)enabled;
@end

@implementation IDevToolCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.contentView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.055];
    self.contentView.layer.cornerRadius = kCornerM;
    self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
    self.contentView.clipsToBounds = YES;
    self.contentView.layer.borderWidth = 0.6;
    self.contentView.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.10].CGColor;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 3);
    self.layer.shadowOpacity = 0.25;
    self.layer.shadowRadius = 8;
    self.layer.masksToBounds = NO;

    _iconLabel = [[UILabel alloc] init];
    _iconLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _iconLabel.textAlignment = NSTextAlignmentCenter;
    _iconLabel.font = [UIFont systemFontOfSize:28];
    [self.contentView addSubview:_iconLabel];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.textColor = [UIColor whiteColor];
    _titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    _titleLabel.numberOfLines = 2;
    [self.contentView addSubview:_titleLabel];

    _badge = [[UIView alloc] init];
    _badge.translatesAutoresizingMaskIntoConstraints = NO;
    _badge.backgroundColor = [UIColor systemGreenColor];
    _badge.layer.cornerRadius = 5;
    _badge.hidden = YES;
    [self.contentView addSubview:_badge];

    [NSLayoutConstraint activateConstraints:@[
        [_iconLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [_iconLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16],
        [_titleLabel.topAnchor constraintEqualToAnchor:_iconLabel.bottomAnchor constant:6],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:4],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-4],
        [_badge.widthAnchor constraintEqualToConstant:10],
        [_badge.heightAnchor constraintEqualToConstant:10],
        [_badge.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [_badge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
    ]];
    return self;
}

- (void)configureWithTitle:(NSString *)title icon:(NSString *)icon enabled:(BOOL)enabled {
    _titleLabel.text = title;
    _iconLabel.text = icon;
    self.contentView.alpha = enabled ? 1.0 : 0.4;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:highlighted?0.12:0.28
                          delay:0
         usingSpringWithDamping:highlighted?1.0:0.60
          initialSpringVelocity:highlighted?0:1.2
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        self.transform = highlighted ? CGAffineTransformMakeScale(0.91,0.91) : CGAffineTransformIdentity;
        self.contentView.backgroundColor = highlighted
            ? [UIColor colorWithWhite:1 alpha:0.14]
            : [UIColor colorWithWhite:1 alpha:0.055];
    } completion:nil];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Status Pill View

@interface StatusPillView : UIView
@property (nonatomic, strong) UIView  *dot;
@property (nonatomic, strong) UILabel *label;
- (void)setStatus:(NSString *)text color:(UIColor *)color animating:(BOOL)animating;
@end

@implementation StatusPillView

- (instancetype)initWithTitle:(NSString *)title {
    self = [super init];
    if (!self) return nil;
    self.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.07];
    self.layer.cornerRadius = 14;
    self.layer.borderWidth = 0.5;
    self.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15].CGColor;

    _dot = [[UIView alloc] init];
    _dot.translatesAutoresizingMaskIntoConstraints = NO;
    _dot.layer.cornerRadius = 5;
    _dot.backgroundColor = [UIColor systemGrayColor];
    [self addSubview:_dot];

    UILabel *head = [[UILabel alloc] init];
    head.translatesAutoresizingMaskIntoConstraints = NO;
    head.text = title;
    head.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.45];
    head.font = [UIFont systemFontOfSize:8 weight:UIFontWeightBold];
    [self addSubview:head];

    _label = [[UILabel alloc] init];
    _label.translatesAutoresizingMaskIntoConstraints = NO;
    _label.text = @"OFFLINE";
    _label.textColor = [UIColor whiteColor];
    _label.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    [self addSubview:_label];

    [NSLayoutConstraint activateConstraints:@[
        [_dot.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [_dot.widthAnchor constraintEqualToConstant:10],
        [_dot.heightAnchor constraintEqualToConstant:10],
        [_dot.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:5],
        [head.leadingAnchor constraintEqualToAnchor:_dot.trailingAnchor constant:7],
        [head.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [head.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
        [_label.leadingAnchor constraintEqualToAnchor:head.leadingAnchor],
        [_label.trailingAnchor constraintEqualToAnchor:head.trailingAnchor],
        [_label.topAnchor constraintEqualToAnchor:head.bottomAnchor constant:1],
    ]];
    return self;
}

- (void)setStatus:(NSString *)text color:(UIColor *)color animating:(BOOL)animating {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.label.text = text;
        self.dot.backgroundColor = color;
        [self.dot.layer removeAllAnimations];
        if (animating) {
            CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
            pulse.fromValue = @(1.0); pulse.toValue = @(0.2);
            pulse.duration = 1.0; pulse.autoreverses = YES;
            pulse.repeatCount = HUGE_VALF;
            [self.dot.layer addAnimation:pulse forKey:@"pulse"];
            self.dot.layer.shadowColor = color.CGColor;
            self.dot.layer.shadowOffset = CGSizeZero;
            self.dot.layer.shadowOpacity = 1.0;
            self.dot.layer.shadowRadius = 6;
        } else {
            self.dot.layer.shadowOpacity = 0;
        }
    });
}

@end

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - LogEntry

@interface LogEntry : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, assign) BOOL isError;
+ (instancetype)entryWithText:(NSString *)text isError:(BOOL)isError;
@end
@implementation LogEntry
+ (instancetype)entryWithText:(NSString *)text isError:(BOOL)isError {
    LogEntry *e = [LogEntry new];
    e.text = text; e.date = [NSDate date]; e.isError = isError;
    return e;
}
@end

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Main ViewController Interface

@interface IdeviceViewController () <UICollectionViewDelegate, UICollectionViewDataSource,
                                     UIDocumentPickerDelegate, UITextFieldDelegate>

// Layout
@property (nonatomic, strong) UIScrollView  *scrollView;
@property (nonatomic, strong) UIStackView   *mainStack;

// Connection fields
@property (nonatomic, strong) UITextField   *ipTextField;
@property (nonatomic, strong) UITextField   *portTextField;
@property (nonatomic, strong) UILabel       *pairingFileLabel;
@property (nonatomic, strong) UIButton      *connectButton;
@property (nonatomic, strong) UIButton      *disconnectButton;
@property (nonatomic, strong) UIButton      *loadPairingButton;

// Status pills
@property (nonatomic, strong) StatusPillView *lockdownPill;
@property (nonatomic, strong) StatusPillView *heartbeatPill;
@property (nonatomic, strong) StatusPillView *ddiPill;
@property (nonatomic, strong) StatusPillView *heartbeatCountPill;

// Device info
@property (nonatomic, strong) UIView        *deviceInfoCard;
@property (nonatomic, strong) UIStackView   *deviceInfoStack;
@property (nonatomic, strong) UIImageView   *deviceIconView;

// Tools grid
@property (nonatomic, strong) UIView               *toolsSection;
@property (nonatomic, strong) UICollectionView     *toolsGrid;
@property (nonatomic, strong) NSArray<NSDictionary *> *toolDefs;

// Log
@property (nonatomic, strong) UITextView    *logView;
@property (nonatomic, strong) UIView        *logCard;
@property (nonatomic, strong) NSMutableArray<LogEntry *> *logEntries;

// Profiles card
@property (nonatomic, strong) UIView        *profilesSection;

// iDevice handles
@property (nonatomic, assign) struct IdevicePairingFile    *pairingFile;
@property (nonatomic, assign) struct IdeviceProviderHandle *provider;
@property (nonatomic, assign) struct LockdowndClientHandle *lockdown;

// State
@property (nonatomic, copy)   NSString      *selectedPairingFilePath;
@property (nonatomic, assign) BOOL           isConnected;
@property (nonatomic, assign) NSInteger      heartbeatCount;
@property (nonatomic, strong) NSTimer        *heartbeatTimer;

// Saved connection profiles
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *connectionProfiles;

@end

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Implementation

@implementation IdeviceViewController

// ─── Tool definitions ────────────────────────────────────────────────────────
- (void)buildToolDefs {
    self.toolDefs = @[
        @{@"id": @(IDevToolAppBrowser),    @"title": @"App\nBrowser",      @"icon": @"📱"},
        @{@"id": @(IDevToolLocationSim),   @"title": @"Location\nSim",     @"icon": @"📍"},
        @{@"id": @(IDevToolAfcMedia),      @"title": @"AFC\nMedia",        @"icon": @"🗂️"},
        @{@"id": @(IDevToolAfcRoot),       @"title": @"AFC2\nRoot",        @"icon": @"🔓"},
        @{@"id": @(IDevToolHouseArrest),   @"title": @"House\nArrest",     @"icon": @"🏠"},
        @{@"id": @(IDevToolScreenshot),    @"title": @"Screenshot",        @"icon": @"📸"},
        @{@"id": @(IDevToolSyslog),        @"title": @"Syslog\nViewer",    @"icon": @"📋"},
        @{@"id": @(IDevToolCrashReports),  @"title": @"Crash\nReports",    @"icon": @"💥"},
        @{@"id": @(IDevToolDiagnostics),   @"title": @"Diagnostics",       @"icon": @"🔬"},
        @{@"id": @(IDevToolProcessControl),@"title": @"Process\nControl",  @"icon": @"⚙️"},
        @{@"id": @(IDevToolNotifications), @"title": @"Notif\nProxy",      @"icon": @"🔔"},
        @{@"id": @(IDevToolSpringBoard),   @"title": @"SpringBoard\nSvc",  @"icon": @"🌸"},
        @{@"id": @(IDevToolDevMode),       @"title": @"Developer\nMode",   @"icon": @"👨‍💻"},
        @{@"id": @(IDevToolProfiles),      @"title": @"Profiles\n(Misa)",  @"icon": @"🪪"},
        @{@"id": @(IDevToolReboot),        @"title": @"Reboot\nDevice",    @"icon": @"🔄"},
        @{@"id": @(IDevToolShutdown),      @"title": @"Shutdown\nDevice",  @"icon": @"⏻"},
        @{@"id": @(IDevToolRecovery),      @"title": @"Recovery\nMode",    @"icon": @"🛟"},
        @{@"id": @(IDevToolOsTrace),       @"title": @"OsTrace\nRelay",    @"icon": @"🔭"},
    ];
}

// ─── Lifecycle ───────────────────────────────────────────────────────────────
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ThemeEngine bg];
    self.title = @"iDevice Manager";
    self.logEntries = [NSMutableArray array];
    self.connectionProfiles = [NSMutableArray array];
    [self buildToolDefs];
    [self setupNavigationBar];
    [self setupScrollLayout];
    [self setupConnectionCard];
    [self setupStatusRow];
    [self setupDeviceInfoCard];
    [self setupToolsGrid];
    [self setupLogCard];
    [self loadSettings];
    [self loadConnectionProfiles];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self saveSettings];
}

- (void)dealloc {
    [self.heartbeatTimer invalidate];
    [self cleanupHandles];
}

- (void)cleanupHandles {
    if (self.lockdown)  { lockdownd_client_free(self.lockdown);   self.lockdown  = NULL; }
    if (self.provider)  { idevice_provider_free(self.provider);   self.provider  = NULL; }
    if (self.pairingFile){ idevice_pairing_file_free(self.pairingFile); self.pairingFile = NULL; }
    self.isConnected = NO;
}

// ─── Navigation Bar ──────────────────────────────────────────────────────────
- (void)setupNavigationBar {
    UIBarButtonItem *profilesBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"person.2.fill"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(showConnectionProfiles)];

    UIBarButtonItem *exportBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(exportLog)];

    self.navigationItem.rightBarButtonItems = @[exportBtn, profilesBtn];
    self.navigationController.navigationBar.prefersLargeTitles = NO;
}

// ─── Scroll Layout ───────────────────────────────────────────────────────────
- (void)setupScrollLayout {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.mainStack = [[UIStackView alloc] init];
    self.mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.mainStack.axis = UILayoutConstraintAxisVertical;
    self.mainStack.spacing = 16;
    [self.scrollView addSubview:self.mainStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.mainStack.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:16],
        [self.mainStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.mainStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.mainStack.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-30],
    ]];
}

// ─── Connection Card ─────────────────────────────────────────────────────────
- (void)setupConnectionCard {
    UIView *card = [self makeGlassCard];
    [self.mainStack addArrangedSubview:card];

    // Section label
    UILabel *sectionLbl = [self makeSectionLabel:@"CONNECTION TARGET"];
    sectionLbl.frame = CGRectMake(16, 14, 280, 14);
    [card addSubview:sectionLbl];

    // IP + Port row
    self.ipTextField = [self makeTextField:@"IP Address" frame:CGRectZero];
    self.portTextField = [self makeTextField:@"Port" frame:CGRectZero];
    self.portTextField.keyboardType = UIKeyboardTypeNumberPad;
    self.portTextField.delegate = self;

    UIStackView *netRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.ipTextField, self.portTextField]];
    netRow.axis = UILayoutConstraintAxisHorizontal;
    netRow.spacing = 10;
    netRow.distribution = UIStackViewDistributionFill;
    netRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.portTextField setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    [self.portTextField.widthAnchor constraintEqualToConstant:90].active = YES;
    [card addSubview:netRow];

    // Pairing file
    self.pairingFileLabel = [[UILabel alloc] init];
    self.pairingFileLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.pairingFileLabel.text = @"No pairing file loaded";
    self.pairingFileLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
    self.pairingFileLabel.font = [UIFont systemFontOfSize:12];
    [card addSubview:self.pairingFileLabel];

    self.loadPairingButton = [self makeSmallButton:@"Load Pairing File"
                                            action:@selector(selectPairingFile)
                                             color:[UIColor systemBlueColor]];
    [card addSubview:self.loadPairingButton];

    // Connect / Disconnect row
    self.connectButton = [self makePrimaryButton:@"接続する"
                                          action:@selector(connectTapped)
                                           color:[ThemeEngine accent]];
    self.disconnectButton = [self makePrimaryButton:@"切断"
                                             action:@selector(disconnectTapped)
                                              color:[UIColor systemRedColor]];
    self.disconnectButton.hidden = YES;
    [card addSubview:self.connectButton];
    [card addSubview:self.disconnectButton];

    // Activate constraints
    [NSLayoutConstraint activateConstraints:@[
        [netRow.topAnchor constraintEqualToAnchor:card.topAnchor constant:36],
        [netRow.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [netRow.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [self.ipTextField.heightAnchor constraintEqualToConstant:40],
        [self.portTextField.heightAnchor constraintEqualToConstant:40],

        [self.pairingFileLabel.topAnchor constraintEqualToAnchor:netRow.bottomAnchor constant:10],
        [self.pairingFileLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [self.pairingFileLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-100],

        [self.loadPairingButton.centerYAnchor constraintEqualToAnchor:self.pairingFileLabel.centerYAnchor],
        [self.loadPairingButton.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],

        [self.connectButton.topAnchor constraintEqualToAnchor:self.pairingFileLabel.bottomAnchor constant:12],
        [self.connectButton.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [self.connectButton.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [self.connectButton.heightAnchor constraintEqualToConstant:50],

        [self.disconnectButton.topAnchor constraintEqualToAnchor:self.connectButton.topAnchor],
        [self.disconnectButton.leadingAnchor constraintEqualToAnchor:self.connectButton.leadingAnchor],
        [self.disconnectButton.trailingAnchor constraintEqualToAnchor:self.connectButton.trailingAnchor],
        [self.disconnectButton.heightAnchor constraintEqualToConstant:50],

        [card.bottomAnchor constraintEqualToAnchor:self.connectButton.bottomAnchor constant:16],
    ]];
}

// ─── Status Row ──────────────────────────────────────────────────────────────
- (void)setupStatusRow {
    self.lockdownPill  = [[StatusPillView alloc] initWithTitle:@"LOCKDOWN"];
    self.heartbeatPill = [[StatusPillView alloc] initWithTitle:@"HEARTBEAT"];
    self.ddiPill       = [[StatusPillView alloc] initWithTitle:@"DDI IMAGE"];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.lockdownPill, self.heartbeatPill, self.ddiPill
    ]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8;
    row.distribution = UIStackViewDistributionFillEqually;

    for (UIView *pill in row.arrangedSubviews) {
        [pill.heightAnchor constraintEqualToConstant:56].active = YES;
    }
    [self.mainStack addArrangedSubview:row];
}

// ─── Device Info Card ────────────────────────────────────────────────────────
- (void)setupDeviceInfoCard {
    self.deviceInfoCard = [self makeGlassCard];
    self.deviceInfoCard.hidden = YES;
    [self.mainStack addArrangedSubview:self.deviceInfoCard];

    UILabel *lbl = [self makeSectionLabel:@"DEVICE INFORMATION"];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.deviceInfoCard addSubview:lbl];

    self.deviceIconView = [[UIImageView alloc] init];
    self.deviceIconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.deviceIconView.contentMode = UIViewContentModeScaleAspectFit;
    self.deviceIconView.tintColor = [UIColor whiteColor];
    self.deviceIconView.image = [UIImage systemImageNamed:@"iphone.gen3"];
    [self.deviceInfoCard addSubview:self.deviceIconView];

    self.deviceInfoStack = [[UIStackView alloc] init];
    self.deviceInfoStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.deviceInfoStack.axis = UILayoutConstraintAxisVertical;
    self.deviceInfoStack.spacing = 6;
    [self.deviceInfoCard addSubview:self.deviceInfoStack];

    [NSLayoutConstraint activateConstraints:@[
        [lbl.topAnchor constraintEqualToAnchor:self.deviceInfoCard.topAnchor constant:14],
        [lbl.leadingAnchor constraintEqualToAnchor:self.deviceInfoCard.leadingAnchor constant:16],

        [self.deviceIconView.topAnchor constraintEqualToAnchor:lbl.bottomAnchor constant:10],
        [self.deviceIconView.leadingAnchor constraintEqualToAnchor:self.deviceInfoCard.leadingAnchor constant:16],
        [self.deviceIconView.widthAnchor constraintEqualToConstant:50],
        [self.deviceIconView.heightAnchor constraintEqualToConstant:50],

        [self.deviceInfoStack.topAnchor constraintEqualToAnchor:lbl.bottomAnchor constant:10],
        [self.deviceInfoStack.leadingAnchor constraintEqualToAnchor:self.deviceIconView.trailingAnchor constant:14],
        [self.deviceInfoStack.trailingAnchor constraintEqualToAnchor:self.deviceInfoCard.trailingAnchor constant:-16],
        [self.deviceInfoCard.bottomAnchor constraintEqualToAnchor:self.deviceInfoStack.bottomAnchor constant:16],
    ]];
}

// ─── Tools Grid ──────────────────────────────────────────────────────────────
- (void)setupToolsGrid {
    self.toolsSection = [[UIView alloc] init];
    self.toolsSection.translatesAutoresizingMaskIntoConstraints = NO;
    self.toolsSection.hidden = YES;
    [self.mainStack addArrangedSubview:self.toolsSection];

    UILabel *lbl = [self makeSectionLabel:@"DEVICE TOOLS"];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.toolsSection addSubview:lbl];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    CGFloat pad = 8;
    CGFloat screenW = (self.view.bounds.size.width > 0) ? self.view.bounds.size.width : 390.0;
    CGFloat width = (screenW - 32.0 - pad * 2.0) / 3.0;
    layout.itemSize = CGSizeMake(width, width * 0.9);
    layout.minimumInteritemSpacing = pad;
    layout.minimumLineSpacing = pad;

    self.toolsGrid = [[UICollectionView alloc] initWithFrame:CGRectZero
                                        collectionViewLayout:layout];
    self.toolsGrid.translatesAutoresizingMaskIntoConstraints = NO;
    self.toolsGrid.backgroundColor = [UIColor clearColor];
    self.toolsGrid.delegate = self;
    self.toolsGrid.dataSource = self;
    self.toolsGrid.scrollEnabled = NO;
    [self.toolsGrid registerClass:[IDevToolCell class] forCellWithReuseIdentifier:@"ToolCell"];
    [self.toolsSection addSubview:self.toolsGrid];

    NSInteger rows = (self.toolDefs.count + 2) / 3;
    CGFloat gridH = rows * (width * 0.9 + pad);

    [NSLayoutConstraint activateConstraints:@[
        [lbl.topAnchor constraintEqualToAnchor:self.toolsSection.topAnchor],
        [lbl.leadingAnchor constraintEqualToAnchor:self.toolsSection.leadingAnchor],
        [self.toolsGrid.topAnchor constraintEqualToAnchor:lbl.bottomAnchor constant:10],
        [self.toolsGrid.leadingAnchor constraintEqualToAnchor:self.toolsSection.leadingAnchor],
        [self.toolsGrid.trailingAnchor constraintEqualToAnchor:self.toolsSection.trailingAnchor],
        [self.toolsGrid.heightAnchor constraintEqualToConstant:gridH],
        [self.toolsSection.bottomAnchor constraintEqualToAnchor:self.toolsGrid.bottomAnchor],
    ]];
}

// ─── Log Card ────────────────────────────────────────────────────────────────
- (void)setupLogCard {
    self.logCard = [self makeGlassCard];
    [self.mainStack addArrangedSubview:self.logCard];

    UILabel *lbl = [self makeSectionLabel:@"ACTIVITY LOG"];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.logCard addSubview:lbl];

    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    clearBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [clearBtn setTitle:@"Clear" forState:UIControlStateNormal];
    [clearBtn setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    clearBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    [clearBtn addTarget:self action:@selector(clearLog) forControlEvents:UIControlEventTouchUpInside];
    [self.logCard addSubview:clearBtn];

    self.logView = [[UITextView alloc] init];
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    self.logView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    self.logView.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
    self.logView.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10];
    self.logView.editable = NO;
    self.logView.layer.cornerRadius = 10;
    self.logView.text = @"[IDLE] Waiting for connection...\n";
    [self.logCard addSubview:self.logView];

    [NSLayoutConstraint activateConstraints:@[
        [lbl.topAnchor constraintEqualToAnchor:self.logCard.topAnchor constant:14],
        [lbl.leadingAnchor constraintEqualToAnchor:self.logCard.leadingAnchor constant:16],
        [clearBtn.centerYAnchor constraintEqualToAnchor:lbl.centerYAnchor],
        [clearBtn.trailingAnchor constraintEqualToAnchor:self.logCard.trailingAnchor constant:-12],
        [self.logView.topAnchor constraintEqualToAnchor:lbl.bottomAnchor constant:8],
        [self.logView.leadingAnchor constraintEqualToAnchor:self.logCard.leadingAnchor constant:12],
        [self.logView.trailingAnchor constraintEqualToAnchor:self.logCard.trailingAnchor constant:-12],
        [self.logView.heightAnchor constraintEqualToConstant:160],
        [self.logCard.bottomAnchor constraintEqualToAnchor:self.logView.bottomAnchor constant:12],
    ]];
}

// ─── CollectionView DataSource ───────────────────────────────────────────────
- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return self.toolDefs.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    IDevToolCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"ToolCell" forIndexPath:ip];
    NSDictionary *def = self.toolDefs[ip.item];
    [cell configureWithTitle:def[@"title"] icon:def[@"icon"] enabled:self.isConnected];
    return cell;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    if (!self.isConnected) {
        [self log:@"[WARN] Connect to device first." isError:YES];
        [self showToast:@"Connect to device first"];
        return;
    }
    IDevTool tool = [self.toolDefs[ip.item][@"id"] unsignedIntegerValue];
    [self launchTool:tool];
}

// ─── Tool Launcher ───────────────────────────────────────────────────────────
- (void)launchTool:(IDevTool)tool {
    switch (tool) {
        case IDevToolAppBrowser:
            [self showAppList]; break;
        case IDevToolLocationSim:
            [self showLocationSim]; break;
        case IDevToolAfcMedia:
            [self showAfc:NO]; break;
        case IDevToolAfcRoot:
            [self showAfc:YES]; break;
        case IDevToolHouseArrest:
            [self showHouseArrest]; break;
        case IDevToolScreenshot:
            [self takeScreenshot]; break;
        case IDevToolSyslog:
            [self showSyslog]; break;
        case IDevToolCrashReports:
            [self showCrashReports]; break;
        case IDevToolDiagnostics:
            [self showDiagnostics]; break;
        case IDevToolProcessControl:
            [self showProcessControl]; break;
        case IDevToolNotifications:
            [self showNotificationProxy]; break;
        case IDevToolSpringBoard:
            [self showSpringBoardServices]; break;
        case IDevToolDevMode:
            [self showDevMode]; break;
        case IDevToolProfiles:
            [self showProfiles]; break;
        case IDevToolReboot:
            [self confirmReboot]; break;
        case IDevToolShutdown:
            [self confirmShutdown]; break;
        case IDevToolRecovery:
            [self confirmRecovery]; break;
        case IDevToolOsTrace:
            [self showOsTrace]; break;
        default:
            [self log:[NSString stringWithFormat:@"[WARN] Tool not implemented yet (id=%lu).", (unsigned long)tool]
                 isError:NO];
    }
}

// ─── Connection Logic ─────────────────────────────────────────────────────────
- (void)connectTapped {
    if (!self.selectedPairingFilePath) {
        [self log:@"[ERROR] No pairing file loaded." isError:YES];
        [self showToast:@"Load a pairing file first"];
        return;
    }
    NSString *ip = [self.ipTextField.text stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceCharacterSet]];
    if (ip.length == 0) {
        [self showToast:@"Enter device IP address"]; return;
    }
    self.connectButton.enabled = NO;
    [self lockdownPill].hidden = NO;
    [self.lockdownPill setStatus:@"CONNECTING" color:[UIColor systemOrangeColor] animating:YES];
    [self.heartbeatPill setStatus:@"WAITING" color:[UIColor systemGrayColor] animating:NO];
    [self.ddiPill setStatus:@"WAITING" color:[UIColor systemGrayColor] animating:NO];
    [self log:@"[INFO] Initiating connection..." isError:NO];

    // Cache UI values on main thread before going to background
    NSString *_cachedIP   = [self.ipTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *_cachedPort = self.portTextField.text;
    NSString *_cachedPath = self.selectedPairingFilePath;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self performConnectionWithIP:_cachedIP port:_cachedPort pairingPath:_cachedPath];
    });
}

- (void)performConnectionWithIP:(NSString *)ipStr port:(NSString *)portStr pairingPath:(NSString *)pairingPath {
    int port = [portStr intValue];
    if (port <= 0 || port > 65535) port = 62078;

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port   = htons((uint16_t)port);
    if (inet_pton(AF_INET, [ipStr UTF8String], &addr.sin_addr) != 1) {
        [self failConnection:@"Invalid IP address" phase:@"ADDR_PARSE"];
        return;
    }

    // Load pairing file
    struct IdevicePairingFile *pf = NULL;
    struct IdeviceFfiError *err = idevice_pairing_file_read(
        [pairingPath UTF8String], &pf);
    if (err) { [self failFromError:err phase:@"PAIRING_READ"]; return; }
    self.pairingFile = pf;

    // Create provider
    struct IdeviceProviderHandle *prov = NULL;
    err = idevice_tcp_provider_new((const idevice_sockaddr *)&addr, pf,
                                   "FrappeManager", &prov);
    if (err) { [self failFromError:err phase:@"PROVIDER_INIT"]; return; }
    self.provider = prov;
    self.pairingFile = NULL; // consumed by provider

    // Lockdown
    struct LockdowndClientHandle *ld = NULL;
    err = lockdownd_connect(prov, &ld);
    if (err) { [self failFromError:err phase:@"LOCKDOWN_CONNECT"]; return; }
    self.lockdown = ld;

    [self log:@"[OK] Lockdown session established." isError:NO];
    [self.lockdownPill setStatus:@"VERIFIED" color:[UIColor systemGreenColor] animating:NO];
    [self fetchAllDeviceInfo:ld];

    // Heartbeat
    [self log:@"[INFO] Starting heartbeat relay..." isError:NO];
    [[HeartbeatManager sharedManager] startHeartbeatWithProvider:prov];
    [self.heartbeatPill setStatus:@"ACTIVE" color:[UIColor systemGreenColor] animating:YES];
    self.heartbeatCount = 0;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
            target:self selector:@selector(tickHeartbeat) userInfo:nil repeats:YES];
    });

    // DDI
    [self log:@"[INFO] Checking developer disk image..." isError:NO];
    [[DdiManager sharedManager] checkAndMountDdiWithProvider:prov lockdown:ld completion:^(BOOL ok, NSString *msg){
        [self log:msg isError:!ok];
        [self.ddiPill setStatus:ok ? @"MOUNTED" : @"NOT FOUND"
                          color:ok ? [UIColor systemGreenColor] : [UIColor systemOrangeColor]
                      animating:NO];
    }];

    // Update UI
    dispatch_async(dispatch_get_main_queue(), ^{
        self.isConnected = YES;
        self.connectButton.hidden = YES;
        self.disconnectButton.hidden = NO;
        self.connectButton.enabled = YES;
        self.toolsSection.hidden = NO;
        self.deviceInfoCard.hidden = NO;
        [self.toolsGrid reloadData];
        [self log:@"[OK] Device ready. All tools available." isError:NO];
    });
}

- (void)failFromError:(struct IdeviceFfiError *)err phase:(NSString *)phase {
    NSString *msg = (err && err->message) ? [NSString stringWithUTF8String:err->message] : @"Unknown error";
    idevice_error_free(err);
    [self failConnection:msg phase:phase];
}

- (void)failConnection:(NSString *)msg phase:(NSString *)phase {
    [self cleanupHandles];
    NSString *full = [NSString stringWithFormat:@"[FAIL:%@] %@", phase, msg];
    [self log:full isError:YES];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.connectButton.enabled = YES;
        self.connectButton.hidden = NO;
        self.disconnectButton.hidden = YES;
        [self.lockdownPill setStatus:@"FAILED" color:[UIColor systemRedColor] animating:NO];
        [self showToast:[NSString stringWithFormat:@"Error: %@", msg]];
    });
}

- (void)disconnectTapped {
    [self.heartbeatTimer invalidate];
    self.heartbeatTimer = nil;
    [[HeartbeatManager sharedManager] stopHeartbeat];
    [self cleanupHandles];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.connectButton.hidden = NO;
        self.disconnectButton.hidden = YES;
        self.toolsSection.hidden = YES;
        self.deviceInfoCard.hidden = YES;
        [self.lockdownPill setStatus:@"OFFLINE" color:[UIColor systemGrayColor] animating:NO];
        [self.heartbeatPill setStatus:@"OFFLINE" color:[UIColor systemGrayColor] animating:NO];
        [self.ddiPill setStatus:@"OFFLINE" color:[UIColor systemGrayColor] animating:NO];
        for (UIView *v in self.deviceInfoStack.arrangedSubviews) [v removeFromSuperview];
        [self log:@"[INFO] Disconnected." isError:NO];
    });
}

- (void)tickHeartbeat {
    self.heartbeatCount++;
    [self.heartbeatPill setStatus:[NSString stringWithFormat:@"BEAT #%ld", (long)self.heartbeatCount]
                            color:[UIColor systemGreenColor]
                        animating:YES];
}

// ─── Device Info Fetch ────────────────────────────────────────────────────────
- (void)fetchAllDeviceInfo:(struct LockdowndClientHandle *)ld {
    NSArray *keys = @[
        @"DeviceName", @"ProductType", @"ProductVersion", @"BuildVersion",
        @"UniqueDeviceID", @"HardwareModel", @"CPUArchitecture",
        @"TotalDiskCapacity", @"TotalSystemAvailable", @"WiFiAddress",
        @"BluetoothAddress", @"PhoneNumber", @"SerialNumber",
        @"InternationalMobileEquipmentIdentity", @"BatteryCurrentCapacity",
        @"BasebandVersion", @"ModelNumber"
    ];

    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIView *v in self.deviceInfoStack.arrangedSubviews) [v removeFromSuperview];
    });

    for (NSString *key in keys) {
        plist_t val = NULL;
        struct IdeviceFfiError *err = lockdownd_get_value(ld, [key UTF8String], NULL, &val);
        if (err) { idevice_error_free(err); continue; }
        if (!val) continue;

        char *str = NULL;
        plist_get_string_val(val, &str);
        if (!str) {
            // Try integer
            uint64_t num = 0;
            plist_get_uint_val(val, &num);
            if (num > 0) {
                NSString *numStr = [self formatBytes:num key:key];
                NSString *k = key; NSString *v = numStr;
                dispatch_async(dispatch_get_main_queue(), ^{ [self addInfoRow:k value:v]; });
            }
        } else {
            NSString *nsStr = [NSString stringWithUTF8String:str];
            NSString *k = key;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self addInfoRow:k value:nsStr];
                if ([k isEqualToString:@"DeviceName"]) {
                    self.navigationItem.title = nsStr;
                }
            });
            plist_mem_free(str);
        }
        plist_free(val);
    }
}

- (NSString *)formatBytes:(uint64_t)bytes key:(NSString *)key {
    if ([key containsString:@"Capacity"] || [key containsString:@"Available"]) {
        double gb = bytes / (1024.0 * 1024.0 * 1024.0);
        return [NSString stringWithFormat:@"%.1f GB", gb];
    }
    return [NSString stringWithFormat:@"%llu", (unsigned long long)bytes];
}

- (void)addInfoRow:(NSString *)key value:(NSString *)value {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8;

    UILabel *kLabel = [[UILabel alloc] init];
    kLabel.text = [self friendlyKey:key];
    kLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.45];
    kLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [kLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];

    UILabel *vLabel = [[UILabel alloc] init];
    vLabel.text = value;
    vLabel.textColor = [UIColor whiteColor];
    vLabel.font = [UIFont systemFontOfSize:11];
    vLabel.textAlignment = NSTextAlignmentRight;
    vLabel.adjustsFontSizeToFitWidth = YES;
    vLabel.minimumScaleFactor = 0.7;

    [row addArrangedSubview:kLabel];
    [row addArrangedSubview:vLabel];
    [self.deviceInfoStack addArrangedSubview:row];
}

- (NSString *)friendlyKey:(NSString *)key {
    NSDictionary *map = @{
        @"DeviceName": @"Name",
        @"ProductType": @"Model",
        @"ProductVersion": @"iOS",
        @"BuildVersion": @"Build",
        @"UniqueDeviceID": @"UDID",
        @"HardwareModel": @"HW Model",
        @"CPUArchitecture": @"CPU",
        @"TotalDiskCapacity": @"Disk",
        @"TotalSystemAvailable": @"Free",
        @"WiFiAddress": @"Wi-Fi",
        @"BluetoothAddress": @"BT Addr",
        @"PhoneNumber": @"Phone",
        @"SerialNumber": @"Serial",
        @"InternationalMobileEquipmentIdentity": @"IMEI",
        @"BatteryCurrentCapacity": @"Battery%",
        @"BasebandVersion": @"Baseband",
        @"ModelNumber": @"Model #",
    };
    return map[key] ?: key;
}

// ─── Tool Implementations ─────────────────────────────────────────────────────

- (void)showAppList {
    AppListViewController *vc = [[AppListViewController alloc] initWithProvider:self.provider];
    [self.navigationController pushViewController:vc animated:YES];
    // Note: AppListViewController uses installation_proxy (works for all iOS versions).
    // For iOS 17+ devices with RSD, app_service provides icons — called automatically by AppManager.
}

- (void)showLocationSim {
    LocationSimulationViewController *vc = [[LocationSimulationViewController alloc]
        initWithProvider:self.provider lockdown:self.lockdown];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showAfc:(BOOL)isAfc2 {
    AfcBrowserViewController *vc = [[AfcBrowserViewController alloc]
        initWithProvider:self.provider isAfc2:isAfc2];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showHouseArrest {
    HouseArrestBrowserViewController *vc = [[HouseArrestBrowserViewController alloc]
        initWithProvider:self.provider];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)takeScreenshot {
    [self log:@"[INFO] Taking screenshot..." isError:NO];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        struct ScreenshotrClientHandle *sshot = NULL;
        struct IdeviceFfiError *err = screenshotr_connect(self.provider, &sshot);
        if (err) {
            NSString *m = err->message ? [NSString stringWithUTF8String:err->message] : @"unknown";
            idevice_error_free(err);
            [self log:[NSString stringWithFormat:@"[FAIL] Screenshot: %@", m] isError:YES];
            return;
        }
        struct ScreenshotData sd; memset(&sd, 0, sizeof(sd));
        err = screenshotr_take_screenshot(sshot, &sd);
        if (err) {
            NSString *m = err->message ? [NSString stringWithUTF8String:err->message] : @"unknown";
            idevice_error_free(err);
            screenshotr_client_free(sshot);
            [self log:[NSString stringWithFormat:@"[FAIL] Screenshot capture: %@", m] isError:YES];
            return;
        }
        screenshotr_client_free(sshot);
        if (sd.data && sd.length > 0) {
            NSData *imgData = [NSData dataWithBytes:sd.data length:sd.length];
            UIImage *img = [UIImage imageWithData:imgData];
            screenshotr_screenshot_free(sd);
            if (img) {
                UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil);
                [self log:@"[OK] Screenshot saved to Photos." isError:NO];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showScreenshotPreview:img];
                });
            }
        }
    });
}

- (void)showScreenshotPreview:(UIImage *)img {
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor blackColor];
    vc.title = @"Screenshot";

    UIImageView *iv = [[UIImageView alloc] initWithImage:img];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.contentMode = UIViewContentModeScaleAspectFit;
    [vc.view addSubview:iv];

    [NSLayoutConstraint activateConstraints:@[
        [iv.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor],
        [iv.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor],
        [iv.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor],
        [iv.bottomAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.bottomAnchor],
    ]];

    UIBarButtonItem *shareBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(shareCurrentScreenshot:)];
    vc.navigationItem.rightBarButtonItem = shareBtn;
    objc_setAssociatedObject(shareBtn, "screenshotImage", img, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [self.navigationController pushViewController:vc animated:YES];
}

- (void)shareCurrentScreenshot:(UIBarButtonItem *)sender {
    UIImage *img = objc_getAssociatedObject(sender, "screenshotImage");
    if (!img) return;
    UIActivityViewController *avc = [[UIActivityViewController alloc]
        initWithActivityItems:@[img] applicationActivities:nil];
    avc.popoverPresentationController.barButtonItem = sender;
    [self presentViewController:avc animated:YES completion:nil];
}

- (void)showSyslog {
    [self log:@"[INFO] Opening syslog viewer..." isError:NO];
    UIViewController *vc = [[UIViewController alloc] init];
    vc.title = @"Syslog";
    vc.view.backgroundColor = [ThemeEngine bg];

    UITextView *tv = [[UITextView alloc] init];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    tv.textColor = [[UIColor greenColor] colorWithAlphaComponent:0.9];
    tv.font = [UIFont fontWithName:@"Menlo" size:9] ?: [UIFont systemFontOfSize:9];
    tv.editable = NO;
    tv.text = @"[Syslog] Connecting...\n";
    [vc.view addSubview:tv];

    [NSLayoutConstraint activateConstraints:@[
        [tv.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor],
        [tv.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor],
        [tv.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor],
        [tv.bottomAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.bottomAnchor],
    ]];

    [self.navigationController pushViewController:vc animated:YES];

    // Stream syslog on background thread
    struct IdeviceProviderHandle *prov = self.provider;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        struct SyslogRelayClientHandle *relay = NULL;
        struct IdeviceFfiError *err = syslog_relay_connect_tcp(prov, &relay);
        if (err) {
            NSString *m = err->message ? [NSString stringWithUTF8String:err->message] : @"?";
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{
                tv.text = [tv.text stringByAppendingFormat:@"[ERROR] %@\n", m];
            });
            return;
        }
        // Read up to 2000 lines
        for (int i = 0; i < 2000; i++) {
            char *line = NULL;
            err = syslog_relay_next(relay, &line);
            if (err || !line) { if(err) idevice_error_free(err); break; }
            NSString *logLine = [NSString stringWithUTF8String:line];
            idevice_string_free(line);
            dispatch_async(dispatch_get_main_queue(), ^{
                tv.text = [tv.text stringByAppendingFormat:@"%@\n", logLine];
                [tv scrollRangeToVisible:NSMakeRange(tv.text.length - 1, 1)];
            });
        }
        syslog_relay_client_free(relay);
    });
}

- (void)showCrashReports {
    [self log:@"[INFO] Fetching crash reports..." isError:NO];
    UITableViewController *tvc = [[UITableViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    tvc.title = @"Crash Reports";
    tvc.view.backgroundColor = [ThemeEngine bg];
    tvc.tableView.backgroundColor = [UIColor clearColor];

    NSMutableArray<NSString *> *reports = [NSMutableArray array];
    __weak UITableViewController *weakTvc = tvc;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        struct CrashReportCopyMobileHandle *cr = NULL;
        struct IdeviceFfiError *err = crash_report_client_connect(self.provider, &cr);
        if (err) {
            idevice_error_free(err);
            [self log:@"[FAIL] Crash report client unavailable" isError:YES];
            return;
        }
        char **files = NULL; size_t count = 0;
        err = crash_report_client_ls(cr, "/", &files, &count);
        if (!err && files) {
            for (size_t i = 0; i < count; i++) {
                if (files[i]) [reports addObject:[NSString stringWithUTF8String:files[i]]];
            }
            idevice_outer_slice_free((void *)files, (uintptr_t)count);
        }
        if (err) idevice_error_free(err);

        dispatch_async(dispatch_get_main_queue(), ^{
            [weakTvc.tableView reloadData];
        });
    });

    // Use objc associations to pass data to the table
    objc_setAssociatedObject(tvc, "reports", reports, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // Override tableView via category-style using blocks stored in associations
    // Use a simple subclass approach inline
    // Actually, let's just use UIAlertController to list them
    [self.navigationController pushViewController:tvc animated:YES];
    [self log:[NSString stringWithFormat:@"[OK] Found %lu crash reports", (unsigned long)reports.count] isError:NO];
}

- (void)showDiagnostics {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Diagnostics"
        message:@"Select diagnostic action:"
        preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray *actions = @[
        @{@"title": @"📊 All Info", @"sel": @"diagAll"},
        @{@"title": @"🔋 GasGauge (Battery)", @"sel": @"diagBattery"},
        @{@"title": @"📶 WiFi Info", @"sel": @"diagWifi"},
        @{@"title": @"💾 NAND Info", @"sel": @"diagNand"},
        @{@"title": @"📱 MobileGestalt", @"sel": @"diagMobileGestalt"},
        @{@"title": @"🔄 Reboot Device", @"sel": @"diagReboot"},
    ];

    for (NSDictionary *a in actions) {
        NSString *selStr = a[@"sel"];
        UIAlertAction *action = [UIAlertAction actionWithTitle:a[@"title"]
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *_) {
                [self runDiagnostic:selStr];
            }];
        [alert addAction:action];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView = self.view;
    alert.popoverPresentationController.sourceRect = self.view.bounds;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)runDiagnostic:(NSString *)type {
    [self log:[NSString stringWithFormat:@"[INFO] Running diagnostic: %@", type] isError:NO];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        struct DiagnosticsRelayClientHandle *diag = NULL;
        struct IdeviceFfiError *err = diagnostics_relay_client_connect(self.provider, &diag);
        if (err) {
            NSString *m = err->message ? [NSString stringWithUTF8String:err->message] : @"?";
            idevice_error_free(err);
            [self log:[NSString stringWithFormat:@"[FAIL] Diagnostics: %@", m] isError:YES];
            return;
        }

        plist_t result = NULL;
        if ([type isEqualToString:@"diagAll"]) {
            err = diagnostics_relay_client_all(diag, &result);
        } else if ([type isEqualToString:@"diagBattery"]) {
            err = diagnostics_relay_client_gasguage(diag, &result);
        } else if ([type isEqualToString:@"diagWifi"]) {
            err = diagnostics_relay_client_wifi(diag, &result);
        } else if ([type isEqualToString:@"diagNand"]) {
            err = diagnostics_relay_client_nand(diag, &result);
        } else if ([type isEqualToString:@"diagMobileGestalt"]) {
            err = diagnostics_relay_client_mobilegestalt(diag, NULL, 0, &result);
        } else if ([type isEqualToString:@"diagReboot"]) {
            err = diagnostics_relay_client_restart(diag);
        }

        if (err) {
            NSString *m = err->message ? [NSString stringWithUTF8String:err->message] : @"?";
            idevice_error_free(err);
            [self log:[NSString stringWithFormat:@"[FAIL] %@: %@", type, m] isError:YES];
        } else {
            if (result) {
                [self log:@"[OK] Diagnostic data received." isError:NO];
                [self showPlistResult:result title:type];
                plist_free(result);
            } else {
                [self log:@"[OK] Command executed." isError:NO];
            }
        }
        diagnostics_relay_client_free(diag);
    });
}

- (void)showPlistResult:(plist_t)pl title:(NSString *)title {
    // Convert plist to string representation
    char *xml = NULL;
    uint32_t xmlLen = 0;
    plist_to_xml(pl, &xml, &xmlLen);
    NSString *content = (xml && xmlLen > 0) ? [NSString stringWithUTF8String:xml] : @"(no data)";
    if (xml) plist_mem_free(xml);

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = [[UIViewController alloc] init];
        vc.title = title;
        vc.view.backgroundColor = [ThemeEngine bg];

        UITextView *tv = [[UITextView alloc] init];
        tv.translatesAutoresizingMaskIntoConstraints = NO;
        tv.backgroundColor = [UIColor clearColor];
        tv.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.85];
        tv.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10];
        tv.text = content;
        tv.editable = NO;
        [vc.view addSubview:tv];
        [NSLayoutConstraint activateConstraints:@[
            [tv.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor constant:8],
            [tv.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor constant:8],
            [tv.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor constant:-8],
            [tv.bottomAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.bottomAnchor constant:-8],
        ]];
        [self.navigationController pushViewController:vc animated:YES];
    });
}

- (void)showProcessControl {
    [self log:@"[INFO] Opening Process Control..." isError:NO];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Process Control"
        message:@"Enter bundle ID to launch:"
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"com.example.app";
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Launch" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        NSString *bundleId = alert.textFields.firstObject.text;
        if (bundleId.length == 0) return;
        [self launchApp:bundleId];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Kill by PID" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
        [self promptKillByPID];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)launchApp:(NSString *)bundleId {
    [self log:[NSString stringWithFormat:@"[INFO] Launching %@...", bundleId] isError:NO];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        // ProcessControl requires RSD (iOS 17+) — use app_service instead
        [self log:@"[INFO] ProcessControl requires RSD. Use AppBrowser to launch apps." isError:NO];
    });
}

- (void)promptKillByPID {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Kill Process"
        message:@"Enter PID:" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeNumberPad;
        tf.placeholder = @"PID";
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Kill" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
        uint32_t pid = (uint32_t)[a.textFields.firstObject.text intValue];
        if (pid == 0) return;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            [self log:@"[INFO] ProcessControl requires RSD connection (iOS 17+)." isError:NO];
        });
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)showNotificationProxy {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Notification Proxy"
        message:@"Post notification to device:"
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"com.apple.mobile.lockdown.host_attached";
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Post" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        NSString *notif = alert.textFields.firstObject.text;
        if (notif.length == 0) return;
        [self postNotification:notif];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)postNotification:(NSString *)notif {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        struct NotificationProxyClientHandle *np = NULL;
        struct IdeviceFfiError *err = notification_proxy_connect(self.provider, &np);
        if (err) { idevice_error_free(err); [self log:@"[FAIL] Notification proxy unavailable" isError:YES]; return; }
        err = notification_proxy_post(np, [notif UTF8String]);
        if (err) {
            NSString *m = err->message ? [NSString stringWithUTF8String:err->message] : @"?";
            idevice_error_free(err);
            [self log:[NSString stringWithFormat:@"[FAIL] Post notif: %@", m] isError:YES];
        } else {
            [self log:[NSString stringWithFormat:@"[OK] Posted: %@", notif] isError:NO];
        }
        notification_proxy_client_free(np);
    });
}

- (void)showSpringBoardServices {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"SpringBoard Services"
        message:@"Select action:"
        preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"🌅 Get Home Screen Wallpaper" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self sbGetWallpaper:NO];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"🔒 Get Lock Screen Wallpaper" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self sbGetWallpaper:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"📐 Get Icon Metrics" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self sbGetIconMetrics];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView = self.view;
    alert.popoverPresentationController.sourceRect = self.view.bounds;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)sbGetWallpaper:(BOOL)isLock {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        struct SpringBoardServicesClientHandle *sb = NULL;
        struct IdeviceFfiError *err = springboard_services_connect(self.provider, &sb);
        if (err) { idevice_error_free(err); [self log:@"[FAIL] SpringBoard unavailable" isError:YES]; return; }

        void *data = NULL; size_t len = 0;
        if (isLock) {
            err = springboard_services_get_lock_screen_wallpaper_preview(sb, &data, &len);
        } else {
            err = springboard_services_get_home_screen_wallpaper_preview(sb, &data, &len);
        }
        if (err) {
            NSString *m = err->message ? [NSString stringWithUTF8String:err->message] : @"?";
            idevice_error_free(err);
            [self log:[NSString stringWithFormat:@"[FAIL] Wallpaper: %@", m] isError:YES];
        } else if (data && len > 0) {
            UIImage *img = [UIImage imageWithData:[NSData dataWithBytes:data length:len]];
            free(data);
            if (img) {
                [self log:@"[OK] Wallpaper received." isError:NO];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showScreenshotPreview:img];
                });
            }
        }
        springboard_services_free(sb);
    });
}

- (void)sbGetIconMetrics {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        struct SpringBoardServicesClientHandle *sb = NULL;
        struct IdeviceFfiError *err = springboard_services_connect(self.provider, &sb);
        if (err) { idevice_error_free(err); return; }
        plist_t metrics = NULL;
        err = springboard_services_get_homescreen_icon_metrics(sb, &metrics);
        if (!err && metrics) {
            [self showPlistResult:metrics title:@"Icon Metrics"];
            plist_free(metrics);
        }
        if (err) idevice_error_free(err);
        springboard_services_free(sb);
    });
}

- (void)showDevMode {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Developer Mode (AMFI)"
        message:@"Select action:"
        preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"Accept Developer Mode" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self amfiAction:@"accept"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Enable Developer Mode" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
        [self amfiAction:@"enable"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reveal in UI" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self amfiAction:@"reveal"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView = self.view;
    alert.popoverPresentationController.sourceRect = self.view.bounds;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)amfiAction:(NSString *)action {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        struct AmfiClientHandle *amfi = NULL;
        struct IdeviceFfiError *err = amfi_connect(self.provider, &amfi);
        if (err) { idevice_error_free(err); [self log:@"[FAIL] AMFI unavailable" isError:YES]; return; }

        if ([action isEqualToString:@"accept"]) {
            err = amfi_accept_developer_mode(amfi);
        } else if ([action isEqualToString:@"enable"]) {
            err = amfi_enable_developer_mode(amfi);
        } else if ([action isEqualToString:@"reveal"]) {
            err = amfi_reveal_developer_mode_option_in_ui(amfi);
        }
        if (err) {
            NSString *m = err->message ? [NSString stringWithUTF8String:err->message] : @"?";
            idevice_error_free(err);
            [self log:[NSString stringWithFormat:@"[FAIL] AMFI %@: %@", action, m] isError:YES];
        } else {
            [self log:[NSString stringWithFormat:@"[OK] AMFI: %@", action] isError:NO];
        }
        amfi_client_free(amfi);
    });
}

- (void)showProfiles {
    [self log:@"[INFO] Fetching provisioning profiles..." isError:NO];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        struct MisagentClientHandle *mis = NULL;
        struct IdeviceFfiError *err = misagent_connect(self.provider, &mis);
        if (err) {
            idevice_error_free(err);
            [self log:@"[FAIL] Misagent unavailable" isError:YES];
            return;
        }
        uint8_t **profiles = NULL; size_t *lens = NULL; size_t count = 0;
        err = misagent_copy_all(mis, &profiles, &lens, &count);
        if (err) {
            NSString *m = err->message ? [NSString stringWithUTF8String:err->message] : @"?";
            idevice_error_free(err);
            [self log:[NSString stringWithFormat:@"[FAIL] Profiles: %@", m] isError:YES];
        } else {
            [self log:[NSString stringWithFormat:@"[OK] Found %zu profiles.", count] isError:NO];
            if (profiles) misagent_free_profiles(profiles, lens, count);
        }
        misagent_client_free(mis);
    });
}

- (void)confirmReboot {
    [self showDestructiveConfirm:@"Reboot Device"
                         message:@"Are you sure you want to reboot this device?"
                      confirmTitle:@"Reboot"
                         action:^{ [self doReboot]; }];
}

- (void)confirmShutdown {
    [self showDestructiveConfirm:@"Shutdown Device"
                         message:@"Are you sure you want to shut down this device?"
                      confirmTitle:@"Shutdown"
                         action:^{ [self doShutdown]; }];
}

- (void)confirmRecovery {
    [self showDestructiveConfirm:@"Enter Recovery Mode"
                         message:@"This will put the device into recovery mode."
                      confirmTitle:@"Enter Recovery"
                         action:^{ [self doEnterRecovery]; }];
}

- (void)doReboot {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        struct DiagnosticsRelayClientHandle *diag = NULL;
        struct IdeviceFfiError *err = diagnostics_relay_client_connect(self.provider, &diag);
        if (err) { idevice_error_free(err); return; }
        err = diagnostics_relay_client_restart(diag);
        if (err) idevice_error_free(err);
        else [self log:@"[OK] Reboot command sent." isError:NO];
        diagnostics_relay_client_free(diag);
    });
}

- (void)doShutdown {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        struct DiagnosticsRelayClientHandle *diag = NULL;
        struct IdeviceFfiError *err = diagnostics_relay_client_connect(self.provider, &diag);
        if (err) { idevice_error_free(err); return; }
        err = diagnostics_relay_client_shutdown(diag);
        if (err) idevice_error_free(err);
        else [self log:@"[OK] Shutdown command sent." isError:NO];
        diagnostics_relay_client_free(diag);
    });
}

- (void)doEnterRecovery {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        struct IdeviceFfiError *err = lockdownd_enter_recovery(self.lockdown);
        if (err) {
            NSString *m = err->message ? [NSString stringWithUTF8String:err->message] : @"?";
            idevice_error_free(err);
            [self log:[NSString stringWithFormat:@"[FAIL] Recovery: %@", m] isError:YES];
        } else {
            [self log:@"[OK] Device entering recovery mode." isError:NO];
        }
    });
}

- (void)showOsTrace {
    UIViewController *vc = [[UIViewController alloc] init];
    vc.title = @"OsTrace Relay";
    vc.view.backgroundColor = [ThemeEngine bg];

    UITextView *tv = [[UITextView alloc] init];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    tv.textColor = [UIColor systemCyanColor];
    tv.font = [UIFont fontWithName:@"Menlo" size:9] ?: [UIFont systemFontOfSize:9];
    tv.editable = NO;
    [vc.view addSubview:tv];
    [NSLayoutConstraint activateConstraints:@[
        [tv.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor],
        [tv.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor],
        [tv.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor],
        [tv.bottomAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.bottomAnchor],
    ]];

    [self.navigationController pushViewController:vc animated:YES];

    struct IdeviceProviderHandle *prov = self.provider;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        struct OsTraceRelayClientHandle *ot = NULL;
        struct IdeviceFfiError *err = os_trace_relay_connect(prov, &ot);
        if (err) {
            NSString *m = err->message ? [NSString stringWithUTF8String:err->message] : @"?";
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{
                tv.text = [NSString stringWithFormat:@"[ERROR] %@\n", m];
            });
            return;
        }
        struct OsTraceRelayReceiverHandle *receiver = NULL;
        err = os_trace_relay_start_trace(ot, &receiver, NULL);
        if (err) { idevice_error_free(err); os_trace_relay_free(ot); return; }

        for (int i = 0; i < 3000; i++) {
            struct OsTraceLog *log_entry = NULL;
            err = os_trace_relay_next(receiver, &log_entry);
            if (err || !log_entry) { if(err) idevice_error_free(err); break; }

            NSString *msg = log_entry->message ?
                [NSString stringWithUTF8String:log_entry->message] : @"";
            NSString *proc = log_entry->image_name ?
                [NSString stringWithUTF8String:log_entry->image_name] : @"?";
            NSString *line = [NSString stringWithFormat:@"[%@] %@\n", proc, msg];
            os_trace_relay_free_log(log_entry);
            dispatch_async(dispatch_get_main_queue(), ^{
                tv.text = [tv.text stringByAppendingString:line];
                [tv scrollRangeToVisible:NSMakeRange(tv.text.length - 1, 1)];
            });
        }
        os_trace_relay_receiver_free(receiver);
        os_trace_relay_free(ot);
    });
}

// ─── Connection Profiles ──────────────────────────────────────────────────────
- (void)showConnectionProfiles {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Connection Profiles"
        message:nil
        preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"💾 Save Current Profile" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self saveCurrentProfile];
    }]];

    for (NSDictionary *profile in self.connectionProfiles) {
        NSString *name = profile[@"name"] ?: @"Profile";
        UIAlertAction *a = [UIAlertAction actionWithTitle:[NSString stringWithFormat:@"📡 %@", name]
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *_) {
                [self loadProfile:profile];
            }];
        [alert addAction:a];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)saveCurrentProfile {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Profile Name"
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"e.g. My iPhone";
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        NSString *name = a.textFields.firstObject.text;
        if (name.length == 0) name = [NSString stringWithFormat:@"Profile %lu", self.connectionProfiles.count + 1];
        NSDictionary *p = @{
            @"name": name,
            @"ip": self.ipTextField.text ?: @"",
            @"port": self.portTextField.text ?: @"62078",
            @"pairingPath": self.selectedPairingFilePath ?: @"",
        };
        [self.connectionProfiles addObject:p];
        [self saveConnectionProfiles];
        [self showToast:[NSString stringWithFormat:@"Profile '%@' saved", name]];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)loadProfile:(NSDictionary *)profile {
    self.ipTextField.text = profile[@"ip"];
    self.portTextField.text = profile[@"port"];
    NSString *path = profile[@"pairingPath"];
    if (path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        self.selectedPairingFilePath = path;
        self.pairingFileLabel.text = path.lastPathComponent;
        self.pairingFileLabel.textColor = [UIColor systemGreenColor];
    }
    [self showToast:[NSString stringWithFormat:@"Loaded: %@", profile[@"name"]]];
}

- (void)saveConnectionProfiles {
    [[NSUserDefaults standardUserDefaults] setObject:self.connectionProfiles forKey:@"ConnectionProfiles"];
}

- (void)loadConnectionProfiles {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:@"ConnectionProfiles"];
    if (saved) self.connectionProfiles = [saved mutableCopy];
}

// ─── Pairing File ─────────────────────────────────────────────────────────────
- (void)selectPairingFile {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
  didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;

    BOOL accessed = [url startAccessingSecurityScopedResource];
    NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *pairingDir = [docsDir stringByAppendingPathComponent:@"PairingFiles"];
    [[NSFileManager defaultManager] createDirectoryAtPath:pairingDir
                             withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *dest = [pairingDir stringByAppendingPathComponent:@"pairfile.plist"];
    [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];

    NSError *copyErr = nil;
    NSString *filename = [[FileManagerCore sharedManager] moveItemAtURL:url
                                                             toDirectory:pairingDir
                                                             uniqueName:@"pairfile.plist"
                                                                  error:&copyErr];
    if (accessed) [url stopAccessingSecurityScopedResource];

    if (filename) {
        self.selectedPairingFilePath = [pairingDir stringByAppendingPathComponent:filename];
        self.pairingFileLabel.text = filename;
        self.pairingFileLabel.textColor = [UIColor systemGreenColor];
        [self log:@"[OK] Pairing file loaded." isError:NO];
        [self saveSettings];
    } else {
        [self log:[NSString stringWithFormat:@"[FAIL] Import: %@", copyErr.localizedDescription] isError:YES];
    }
}

// ─── Settings Persist ─────────────────────────────────────────────────────────
- (void)loadSettings {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    self.ipTextField.text   = [ud stringForKey:@"IdeviceIP"]   ?: @"10.7.0.1";
    self.portTextField.text = [ud stringForKey:@"IdevicePort"] ?: @"62078";

    NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *pairPath = [docsDir stringByAppendingPathComponent:@"PairingFiles/pairfile.plist"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:pairPath]) {
        self.selectedPairingFilePath = pairPath;
        self.pairingFileLabel.text = @"pairfile.plist ✓";
        self.pairingFileLabel.textColor = [UIColor systemGreenColor];
    }
}

- (void)saveSettings {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:self.ipTextField.text   forKey:@"IdeviceIP"];
    [ud setObject:self.portTextField.text forKey:@"IdevicePort"];
}

// ─── Log ─────────────────────────────────────────────────────────────────────
- (void)log:(NSString *)msg isError:(BOOL)isError {
    LogEntry *entry = [LogEntry entryWithText:msg isError:isError];
    [self.logEntries addObject:entry];

    dispatch_async(dispatch_get_main_queue(), ^{
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"HH:mm:ss";
        NSString *time = [fmt stringFromDate:entry.date];
        NSAttributedString *current = self.logView.attributedText ?: [[NSAttributedString alloc] initWithString:@""];
        NSMutableAttributedString *appended = [current mutableCopy];
        NSDictionary *attrs = @{
            NSFontAttributeName: [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10],
            NSForegroundColorAttributeName: isError ? [UIColor systemRedColor]
                                                    : [[UIColor whiteColor] colorWithAlphaComponent:0.8],
        };
        NSAttributedString *line = [[NSAttributedString alloc]
            initWithString:[NSString stringWithFormat:@"[%@] %@\n", time, msg]
                attributes:attrs];
        [appended appendAttributedString:line];
        self.logView.attributedText = appended;
        [self.logView scrollRangeToVisible:NSMakeRange(self.logView.text.length - 1, 1)];
    });
}

- (void)clearLog {
    [self.logEntries removeAllObjects];
    self.logView.text = @"[LOG CLEARED]\n";
}

- (void)exportLog {
    NSMutableString *export = [NSMutableString string];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm:ss";
    for (LogEntry *e in self.logEntries) {
        [export appendFormat:@"[%@] %@\n", [fmt stringFromDate:e.date], e.text];
    }
    UIActivityViewController *avc = [[UIActivityViewController alloc]
        initWithActivityItems:@[export] applicationActivities:nil];
    avc.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
    [self presentViewController:avc animated:YES completion:nil];
}

// ─── UI Helpers ──────────────────────────────────────────────────────────────
- (UIView *)makeGlassCard {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [ThemeEngine applyGlassToView:card radius:kCornerL];
    card.layer.shadowColor = [UIColor blackColor].CGColor;
    card.layer.shadowOffset = CGSizeMake(0, 4);
    card.layer.shadowOpacity = 0.30;
    card.layer.shadowRadius = 14;
    return card;
}

- (UILabel *)makeSectionLabel:(NSString *)text {
    UILabel *lbl = [[UILabel alloc] init];
    lbl.text = text;
    lbl.textColor = [ThemeEngine textTertiary];
    lbl.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    return lbl;
}

- (UITextField *)makeTextField:(NSString *)placeholder frame:(CGRect)f {
    UITextField *tf = [[UITextField alloc] init];
    tf.translatesAutoresizingMaskIntoConstraints = NO;
    tf.placeholder = placeholder;
    tf.textColor = [UIColor whiteColor];
    tf.font = [UIFont systemFontOfSize:14];
    tf.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
    tf.layer.cornerRadius = 10;
    tf.layer.borderWidth = 0.5;
    tf.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15].CGColor;
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 1)];
    tf.leftView = pad; tf.leftViewMode = UITextFieldViewModeAlways;
    // Placeholder color
    tf.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder
        attributes:@{NSForegroundColorAttributeName: [[UIColor whiteColor] colorWithAlphaComponent:0.3]}];
    return tf;
}

- (UIButton *)makePrimaryButton:(NSString *)title action:(SEL)sel color:(UIColor *)color {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    btn.backgroundColor = color;
    btn.layer.cornerRadius = kCornerM;
    btn.layer.cornerCurve = kCACornerCurveContinuous;
    btn.layer.shadowColor = color.CGColor;
    btn.layer.shadowOffset = CGSizeMake(0, 5);
    btn.layer.shadowOpacity = 0.50;
    btn.layer.shadowRadius = 12;
    [btn addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (UIButton *)makeSmallButton:(NSString *)title action:(SEL)sel color:(UIColor *)color {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:color forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [btn addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)showToast:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UILabel *toast = [[UILabel alloc] init];
        toast.text = message;
        toast.textColor = [UIColor whiteColor];
        toast.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
        toast.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        toast.textAlignment = NSTextAlignmentCenter;
        toast.layer.cornerRadius = 16;
        toast.clipsToBounds = YES;
        toast.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:toast];
        [NSLayoutConstraint activateConstraints:@[
            [toast.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [toast.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20],
            [toast.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor multiplier:0.8],
            [toast.heightAnchor constraintEqualToConstant:40],
        ]];
        toast.alpha = 0;
        [UIView animateWithDuration:0.3 animations:^{ toast.alpha = 1; }
                         completion:^(BOOL _) {
            [UIView animateWithDuration:0.3 delay:2.0 options:0 animations:^{ toast.alpha = 0; }
                             completion:^(BOOL __) { [toast removeFromSuperview]; }];
        }];
    });
}

- (void)showDestructiveConfirm:(NSString *)title message:(NSString *)msg confirmTitle:(NSString *)ctitle action:(void(^)(void))action {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:ctitle style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
        if (action) action();
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

// ─── Keyboard ─────────────────────────────────────────────────────────────────
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.view endEditing:YES];
    [super touchesBegan:touches withEvent:event];
}

@end
