#import "LocationSimulationViewController.h"
#import "ThemeEngine.h"
#import "DdiManager.h"
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>

// ---------------------------------------------------------------------------
// タイマー設定
// ---------------------------------------------------------------------------
static const NSTimeInterval kTickInterval   = 0.1;   // 0.1秒ごとに更新 (滑らか)
static const NSInteger       kMaxPathPoints = 50000;  // 最大パスポイント数 (メモリ爆発防止)

typedef NS_ENUM(NSInteger, MoveMode) {
    MoveModeDirect       = 0,
    MoveModeStraightAuto = 1,
    MoveModeRoadAuto     = 2,
    MoveModeMultiPoint   = 3
};

// ---------------------------------------------------------------------------
// Private extension
// ---------------------------------------------------------------------------
@interface LocationSimulationViewController ()
    <MKMapViewDelegate, UITextFieldDelegate,
     UITableViewDelegate, UITableViewDataSource,
     CLLocationManagerDelegate>

// --- idevice handles (assign = C pointer, 手動管理) ---
@property (nonatomic, assign) struct IdeviceProviderHandle    *provider;
@property (nonatomic, assign) struct LockdowndClientHandle    *lockdown;
@property (nonatomic, assign) struct LocationSimulationHandle *simHandle17;
@property (nonatomic, assign) struct LocationSimulationServiceHandle *simHandleLegacy;
@property (nonatomic, assign) struct RemoteServerHandle       *remoteServer;
@property (nonatomic, assign) struct AdapterHandle            *adapter;
@property (nonatomic, assign) struct RsdHandshakeHandle       *handshake;

// --- UI ---
@property (nonatomic, strong) MKMapView              *mapView;
@property (nonatomic, strong) UIVisualEffectView     *searchBarGlass;
@property (nonatomic, strong) UITextField            *searchField;
@property (nonatomic, strong) UIView                 *controlPanel;
@property (nonatomic, strong) UISegmentedControl     *modeControl;
@property (nonatomic, strong) UISegmentedControl     *transportControl;
@property (nonatomic, strong) UITextField            *speedTextField;
@property (nonatomic, strong) UIButton               *actionButton;
@property (nonatomic, strong) UIButton               *clearButton;
@property (nonatomic, strong) UIButton               *favButton;
@property (nonatomic, strong) UIButton               *reverseButton;
@property (nonatomic, strong) UIButton               *centerButton;
@property (nonatomic, strong) UIButton               *homeButton;
@property (nonatomic, strong) UILabel                *statusLabel;

@property (nonatomic, strong) UIView   *joyBox;
@property (nonatomic, strong) UIButton *joyUp;
@property (nonatomic, strong) UIButton *joyDown;
@property (nonatomic, strong) UIButton *joyLeft;
@property (nonatomic, strong) UIButton *joyRight;
@property (nonatomic, strong) UISwitch *loopSwitch;
@property (nonatomic, strong) UILabel  *loopLabel;

// --- 検索 ---
@property (nonatomic, strong) UIVisualEffectView    *searchContainer;
@property (nonatomic, strong) UITableView           *searchResultsTable;
@property (nonatomic, strong) NSArray<MKMapItem *>  *searchResults;
@property (nonatomic, strong) MKLocalSearch         *activeSearch;     // BUG FIX: 旧検索キャンセル用

// --- ローディング ---
@property (nonatomic, strong) UIVisualEffectView        *loadingOverlay;
@property (nonatomic, strong) UIActivityIndicatorView   *loadingSpinner;
@property (nonatomic, strong) UILabel                   *loadingText;

// --- シミュレーション状態 ---
@property (nonatomic, strong) NSMutableArray<MKPointAnnotation *> *destinations;
@property (nonatomic, strong) MKPointAnnotation          *currentPosMarker;
@property (nonatomic, strong) NSMutableArray<MKPolyline *> *routePolylines;
@property (nonatomic, strong) NSTimer                    *moveTimer;
@property (nonatomic, assign) CLLocationCoordinate2D      currentSimulatedPos;
@property (nonatomic, strong) NSMutableArray<CLLocation *> *currentPathPoints;
@property (nonatomic, assign) NSInteger                   currentPathIndex;
@property (nonatomic, assign) double                      currentSpeedKmH;

// --- GPS / ホーム ---
@property (nonatomic, strong) CLLocationManager          *locManager;
@property (nonatomic, assign) CLLocationCoordinate2D      trueHomePos;
@property (nonatomic, assign) BOOL                        hasSetHome;

// --- お気に入り ---
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *favorites;

@end

// ---------------------------------------------------------------------------
@implementation LocationSimulationViewController

#pragma mark - Init

- (instancetype)initWithProvider:(struct IdeviceProviderHandle *)provider
                        lockdown:(struct LockdowndClientHandle *)lockdown
{
    self = [super init];
    if (!self) return nil;

    _provider          = provider;
    _lockdown          = lockdown;
    _destinations      = [NSMutableArray array];
    _currentPathPoints = [NSMutableArray array];
    _routePolylines    = [NSMutableArray array];
    _searchResults     = @[];
    _currentSpeedKmH   = 5.0;
    _favorites         = [NSMutableArray array];

    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:@"SimFavorites"];
    if (saved) [_favorites addObjectsFromArray:saved];

    _locManager                 = [[CLLocationManager alloc] init];
    _locManager.delegate        = self;
    _locManager.desiredAccuracy = kCLLocationAccuracyBest;
    _hasSetHome = NO;

    return self;
}

#pragma mark - View Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title                 = @"Location Simulation";
    self.view.backgroundColor  = [ThemeEngine bg];
    [self setupUI];
    [self connectSimulationService];
    [self.locManager requestWhenInUseAuthorization];
    [self.locManager startUpdatingLocation];
    [self showLoadingOverlay:YES withText:@"SYNCING ORIGINAL GPS..."];
}

#pragma mark - UI Setup

- (void)setupUI {
    // --- Map ---
    self.mapView = [[MKMapView alloc] initWithFrame:self.view.bounds];
    self.mapView.autoresizingMask    = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.mapView.delegate            = self;
    self.mapView.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.mapView.showsUserLocation   = YES;
    [self.view addSubview:self.mapView];

    UILongPressGestureRecognizer *lp =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [self.mapView addGestureRecognizer:lp];

    // --- Search bar glass ---
    self.searchBarGlass = [[UIVisualEffectView alloc] initWithEffect:
                           [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    self.searchBarGlass.layer.cornerRadius = 25;
    self.searchBarGlass.clipsToBounds      = YES;
    self.searchBarGlass.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBarGlass.layer.borderWidth  = 0.5;
    self.searchBarGlass.layer.borderColor  = [[UIColor whiteColor] colorWithAlphaComponent:0.2].CGColor;
    [self.view addSubview:self.searchBarGlass];

    // --- Search icon ---
    UIImageView *si = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]];
    si.tintColor    = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
    si.translatesAutoresizingMaskIntoConstraints = NO;
    [self.searchBarGlass.contentView addSubview:si];

    // --- Search field ---
    self.searchField = [[UITextField alloc] initWithFrame:CGRectZero];
    self.searchField.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchField.placeholder        = @"Search location or 00.0, 00.0";
    self.searchField.textColor          = [UIColor whiteColor];
    self.searchField.font               = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    self.searchField.delegate           = self;
    self.searchField.returnKeyType      = UIReturnKeySearch;
    self.searchField.keyboardAppearance = UIKeyboardAppearanceDark;
    [self.searchField addTarget:self action:@selector(searchTextChanged:)
               forControlEvents:UIControlEventEditingChanged];
    [self.searchBarGlass.contentView addSubview:self.searchField];

    // --- Floating buttons ---
    self.centerButton = [self createCircleBtn:@"⌖" act:@selector(centerOnPos)];
    [self.view addSubview:self.centerButton];

    self.homeButton = [self createCircleBtn:@"🏠" act:@selector(useHomeLocation)];
    [self.view addSubview:self.homeButton];

    // --- Search results container ---
    self.searchContainer = [[UIVisualEffectView alloc] initWithEffect:
                            [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    self.searchContainer.layer.cornerRadius = 20;
    self.searchContainer.clipsToBounds      = YES;
    self.searchContainer.hidden             = YES;
    self.searchContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchContainer];

    self.searchResultsTable = [[UITableView alloc] initWithFrame:CGRectZero
                                                           style:UITableViewStylePlain];
    self.searchResultsTable.delegate        = self;
    self.searchResultsTable.dataSource      = self;
    self.searchResultsTable.backgroundColor = [UIColor clearColor];
    self.searchResultsTable.separatorStyle  = UITableViewCellSeparatorStyleSingleLine;
    self.searchResultsTable.separatorColor  = [[UIColor whiteColor] colorWithAlphaComponent:0.05];
    self.searchResultsTable.translatesAutoresizingMaskIntoConstraints = NO;
    [self.searchContainer.contentView addSubview:self.searchResultsTable];

    // --- Control panel ---
    self.controlPanel = [[UIView alloc] initWithFrame:CGRectZero];
    self.controlPanel.translatesAutoresizingMaskIntoConstraints = NO;
    [ThemeEngine applyGlassStyleToView:self.controlPanel cornerRadius:20];
    [self.view addSubview:self.controlPanel];

    // Mode
    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"Direct", @"Straight", @"Road", @"Multi"]];
    self.modeControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.modeControl.selectedSegmentIndex = 0;
    [self.modeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]}
                                    forState:UIControlStateNormal];
    [self.controlPanel addSubview:self.modeControl];

    // Transport
    self.transportControl = [[UISegmentedControl alloc] initWithItems:@[@"Walk", @"Cycle", @"Run", @"Car"]];
    self.transportControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.transportControl.selectedSegmentIndex = 0;
    [self.transportControl addTarget:self action:@selector(transportChanged:)
                    forControlEvents:UIControlEventValueChanged];
    [self.transportControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]}
                                         forState:UIControlStateNormal];
    [self.controlPanel addSubview:self.transportControl];

    // Speed field
    self.speedTextField = [[UITextField alloc] initWithFrame:CGRectZero];
    self.speedTextField.translatesAutoresizingMaskIntoConstraints = NO;
    self.speedTextField.text               = @"5";
    self.speedTextField.textColor          = [UIColor whiteColor];
    self.speedTextField.borderStyle        = UITextBorderStyleRoundedRect;
    self.speedTextField.backgroundColor    = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    self.speedTextField.keyboardType       = UIKeyboardTypeDecimalPad;
    self.speedTextField.keyboardAppearance = UIKeyboardAppearanceDark;
    [self.controlPanel addSubview:self.speedTextField];

    // Action button
    self.actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.actionButton setTitle:@"START SIMULATION" forState:UIControlStateNormal];
    self.actionButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBlack];
    self.actionButton.backgroundColor = [UIColor systemBlueColor];
    self.actionButton.tintColor       = [UIColor whiteColor];
    self.actionButton.layer.cornerRadius = 10;
    [self.actionButton addTarget:self action:@selector(actionTapped)
                forControlEvents:UIControlEventTouchUpInside];
    [self.controlPanel addSubview:self.actionButton];

    // Clear / Reverse / Fav buttons
    self.clearButton = [self createTextBtn:@"RESET"
                                     color:[UIColor systemRedColor]
                                       act:@selector(clearDestinations)];
    [self.controlPanel addSubview:self.clearButton];

    self.reverseButton = [self createTextBtn:@"REV"
                                       color:[UIColor systemOrangeColor]
                                         act:@selector(reverseDestinations)];
    [self.controlPanel addSubview:self.reverseButton];

    self.favButton = [self createTextBtn:@"FAV"
                                   color:[UIColor systemYellowColor]
                                     act:@selector(showFavorites)];
    [self.controlPanel addSubview:self.favButton];

    // Status label
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.textColor     = [UIColor systemGreenColor];
    self.statusLabel.font          = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    self.statusLabel.text          = @"READY";
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.controlPanel addSubview:self.statusLabel];

    // Loop switch
    self.loopSwitch = [[UISwitch alloc] init];
    self.loopSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    self.loopSwitch.onTintColor = [UIColor systemBlueColor];
    [self.controlPanel addSubview:self.loopSwitch];

    self.loopLabel = [[UILabel alloc] init];
    self.loopLabel.text      = @"LOOP";
    self.loopLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
    self.loopLabel.font      = [UIFont systemFontOfSize:10 weight:UIFontWeightBlack];
    self.loopLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.controlPanel addSubview:self.loopLabel];

    // Joystick
    self.joyBox = [[UIView alloc] init];
    self.joyBox.translatesAutoresizingMaskIntoConstraints = NO;
    [ThemeEngine applyGlassStyleToView:self.joyBox cornerRadius:40];
    [self.view addSubview:self.joyBox];

    self.joyUp    = [self createJoyBtn:@"▲" act:@selector(joyMove:)];
    self.joyDown  = [self createJoyBtn:@"▼" act:@selector(joyMove:)];
    self.joyLeft  = [self createJoyBtn:@"◀" act:@selector(joyMove:)];
    self.joyRight = [self createJoyBtn:@"▶" act:@selector(joyMove:)];
    [self.joyBox addSubview:self.joyUp];
    [self.joyBox addSubview:self.joyDown];
    [self.joyBox addSubview:self.joyLeft];
    [self.joyBox addSubview:self.joyRight];

    // Loading overlay
    self.loadingOverlay = [[UIVisualEffectView alloc] initWithEffect:
                           [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    self.loadingOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingOverlay.hidden = YES;
    [self.view addSubview:self.loadingOverlay];

    self.loadingSpinner = [[UIActivityIndicatorView alloc]
                           initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.loadingSpinner.color = [UIColor whiteColor];
    self.loadingSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.loadingOverlay.contentView addSubview:self.loadingSpinner];

    self.loadingText = [[UILabel alloc] init];
    self.loadingText.textColor = [UIColor whiteColor];
    self.loadingText.font      = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.loadingText.translatesAutoresizingMaskIntoConstraints = NO;
    [self.loadingOverlay.contentView addSubview:self.loadingText];

    // --- Auto Layout ---
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        // Search bar
        [self.searchBarGlass.topAnchor constraintEqualToAnchor:safe.topAnchor constant:15],
        [self.searchBarGlass.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.searchBarGlass.trailingAnchor constraintEqualToAnchor:self.centerButton.leadingAnchor constant:-12],
        [self.searchBarGlass.heightAnchor constraintEqualToConstant:50],

        [si.leadingAnchor constraintEqualToAnchor:self.searchBarGlass.leadingAnchor constant:15],
        [si.centerYAnchor constraintEqualToAnchor:self.searchBarGlass.centerYAnchor],
        [si.widthAnchor constraintEqualToConstant:22],
        [si.heightAnchor constraintEqualToConstant:22],

        [self.searchField.leadingAnchor constraintEqualToAnchor:si.trailingAnchor constant:12],
        [self.searchField.trailingAnchor constraintEqualToAnchor:self.searchBarGlass.trailingAnchor constant:-15],
        [self.searchField.topAnchor constraintEqualToAnchor:self.searchBarGlass.topAnchor],
        [self.searchField.bottomAnchor constraintEqualToAnchor:self.searchBarGlass.bottomAnchor],

        // Floating buttons
        [self.centerButton.centerYAnchor constraintEqualToAnchor:self.searchBarGlass.centerYAnchor],
        [self.centerButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],
        [self.centerButton.widthAnchor constraintEqualToConstant:40],
        [self.centerButton.heightAnchor constraintEqualToConstant:40],

        [self.homeButton.topAnchor constraintEqualToAnchor:self.centerButton.bottomAnchor constant:12],
        [self.homeButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],
        [self.homeButton.widthAnchor constraintEqualToConstant:40],
        [self.homeButton.heightAnchor constraintEqualToConstant:40],

        // Search results
        [self.searchContainer.topAnchor constraintEqualToAnchor:self.searchBarGlass.bottomAnchor constant:8],
        [self.searchContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.searchContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.searchContainer.heightAnchor constraintEqualToConstant:320],

        [self.searchResultsTable.topAnchor constraintEqualToAnchor:self.searchContainer.topAnchor],
        [self.searchResultsTable.leadingAnchor constraintEqualToAnchor:self.searchContainer.leadingAnchor],
        [self.searchResultsTable.trailingAnchor constraintEqualToAnchor:self.searchContainer.trailingAnchor],
        [self.searchResultsTable.bottomAnchor constraintEqualToAnchor:self.searchContainer.bottomAnchor],

        // Control panel
        [self.controlPanel.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-10],
        [self.controlPanel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.controlPanel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [self.controlPanel.heightAnchor constraintEqualToConstant:250],

        // Segments
        [self.modeControl.topAnchor constraintEqualToAnchor:self.controlPanel.topAnchor constant:15],
        [self.modeControl.leadingAnchor constraintEqualToAnchor:self.controlPanel.leadingAnchor constant:15],
        [self.modeControl.trailingAnchor constraintEqualToAnchor:self.controlPanel.trailingAnchor constant:-15],

        [self.transportControl.topAnchor constraintEqualToAnchor:self.modeControl.bottomAnchor constant:12],
        [self.transportControl.leadingAnchor constraintEqualToAnchor:self.controlPanel.leadingAnchor constant:15],
        [self.transportControl.trailingAnchor constraintEqualToAnchor:self.controlPanel.trailingAnchor constant:-15],

        // Speed + Action row
        [self.speedTextField.topAnchor constraintEqualToAnchor:self.transportControl.bottomAnchor constant:15],
        [self.speedTextField.leadingAnchor constraintEqualToAnchor:self.controlPanel.leadingAnchor constant:15],
        [self.speedTextField.widthAnchor constraintEqualToConstant:65],

        [self.actionButton.topAnchor constraintEqualToAnchor:self.speedTextField.topAnchor],
        [self.actionButton.leadingAnchor constraintEqualToAnchor:self.speedTextField.trailingAnchor constant:12],
        [self.actionButton.trailingAnchor constraintEqualToAnchor:self.favButton.leadingAnchor constant:-12],
        [self.actionButton.heightAnchor constraintEqualToConstant:40],

        [self.favButton.centerYAnchor constraintEqualToAnchor:self.actionButton.centerYAnchor],
        [self.favButton.trailingAnchor constraintEqualToAnchor:self.controlPanel.trailingAnchor constant:-15],
        [self.favButton.widthAnchor constraintEqualToConstant:50],

        // Clear / Reverse / Loop row
        [self.clearButton.topAnchor constraintEqualToAnchor:self.actionButton.bottomAnchor constant:10],
        [self.clearButton.leadingAnchor constraintEqualToAnchor:self.controlPanel.leadingAnchor constant:15],

        [self.reverseButton.centerYAnchor constraintEqualToAnchor:self.clearButton.centerYAnchor],
        [self.reverseButton.centerXAnchor constraintEqualToAnchor:self.controlPanel.centerXAnchor],

        [self.loopSwitch.centerYAnchor constraintEqualToAnchor:self.clearButton.centerYAnchor],
        [self.loopSwitch.trailingAnchor constraintEqualToAnchor:self.controlPanel.trailingAnchor constant:-15],

        [self.loopLabel.centerYAnchor constraintEqualToAnchor:self.loopSwitch.centerYAnchor],
        [self.loopLabel.trailingAnchor constraintEqualToAnchor:self.loopSwitch.leadingAnchor constant:-8],

        // Status
        [self.statusLabel.bottomAnchor constraintEqualToAnchor:self.controlPanel.bottomAnchor constant:-5],
        [self.statusLabel.centerXAnchor constraintEqualToAnchor:self.controlPanel.centerXAnchor],

        // Joystick
        [self.joyBox.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-25],
        [self.joyBox.bottomAnchor constraintEqualToAnchor:self.controlPanel.topAnchor constant:-25],
        [self.joyBox.widthAnchor constraintEqualToConstant:90],
        [self.joyBox.heightAnchor constraintEqualToConstant:90],

        [self.joyUp.topAnchor constraintEqualToAnchor:self.joyBox.topAnchor],
        [self.joyUp.centerXAnchor constraintEqualToAnchor:self.joyBox.centerXAnchor],
        [self.joyDown.bottomAnchor constraintEqualToAnchor:self.joyBox.bottomAnchor],
        [self.joyDown.centerXAnchor constraintEqualToAnchor:self.joyBox.centerXAnchor],
        [self.joyLeft.leadingAnchor constraintEqualToAnchor:self.joyBox.leadingAnchor],
        [self.joyLeft.centerYAnchor constraintEqualToAnchor:self.joyBox.centerYAnchor],
        [self.joyRight.trailingAnchor constraintEqualToAnchor:self.joyBox.trailingAnchor],
        [self.joyRight.centerYAnchor constraintEqualToAnchor:self.joyBox.centerYAnchor],

        // Loading overlay (full screen)
        [self.loadingOverlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.loadingOverlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.loadingOverlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.loadingOverlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [self.loadingSpinner.centerXAnchor constraintEqualToAnchor:self.loadingOverlay.centerXAnchor],
        [self.loadingSpinner.centerYAnchor constraintEqualToAnchor:self.loadingOverlay.centerYAnchor],
        [self.loadingText.topAnchor constraintEqualToAnchor:self.loadingSpinner.bottomAnchor constant:15],
        [self.loadingText.centerXAnchor constraintEqualToAnchor:self.loadingOverlay.centerXAnchor],
    ]];
}

#pragma mark - Helper: Button Factories

- (UIButton *)createCircleBtn:(NSString *)title act:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.backgroundColor    = [[UIColor blackColor] colorWithAlphaComponent:0.6];
    b.tintColor          = [UIColor whiteColor];
    b.layer.cornerRadius = 20;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UIButton *)createTextBtn:(NSString *)title color:(UIColor *)color act:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    b.tintColor       = color;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UIButton *)createJoyBtn:(NSString *)title act:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:25];
    b.tintColor       = [UIColor whiteColor];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

#pragma mark - Loading Overlay

- (void)showLoadingOverlay:(BOOL)show withText:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.loadingText.text     = text;
        self.loadingOverlay.hidden = !show;
        if (show) [self.loadingSpinner startAnimating];
        else       [self.loadingSpinner stopAnimating];
    });
}

#pragma mark - Logging

- (void)log:(NSString *)msg {
    NSLog(@"[SimVC] %@", msg);
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = [msg uppercaseString];
    });
}

#pragma mark - Transport Control

- (void)transportChanged:(UISegmentedControl *)sender {
    NSArray<NSString *> *defaults = @[@"5", @"20", @"40", @"80"];
    NSUInteger idx = (NSUInteger)sender.selectedSegmentIndex;
    if (idx < defaults.count) {
        self.speedTextField.text = defaults[idx];
    }
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager
     didUpdateLocations:(NSArray<CLLocation *> *)locations
{
    CLLocation *loc = locations.lastObject;
    if (loc.horizontalAccuracy < 0 || loc.horizontalAccuracy > 100) return;

    if (!self.hasSetHome) {
        self.hasSetHome          = YES;
        self.trueHomePos         = loc.coordinate;
        self.currentSimulatedPos = loc.coordinate;

        // BUG FIX: GPS確定後は位置更新停止 → バッテリー節約
        [manager stopUpdatingLocation];

        [self updatePosMarker];
        [self centerOnPos];
        [self showLoadingOverlay:NO withText:@""];
        [self log:@"ORIGINAL GPS LOCKED"];
    }
}

- (void)useHomeLocation {
    if (!self.hasSetHome) { [self log:@"WAITING FOR GPS..."]; return; }
    self.currentSimulatedPos = self.trueHomePos;
    [self updateDeviceLocation:self.currentSimulatedPos];
    [self centerOnPos];
    [self log:@"SYNC TO ORIGINAL"];
}

#pragma mark - Connection

- (void)connectSimulationService {
    [self log:@"TUNNELING..."];
    __weak typeof(self) weakSelf = self;

    [[DdiManager sharedManager] checkAndMountDdiWithProvider:self.provider
                                                    lockdown:self.lockdown
                                                  completion:^(BOOL success, NSString *message) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (!success) {
            [strongSelf log:[NSString stringWithFormat:@"DDI FAIL: %@", message]];
            return;
        }

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            __strong typeof(weakSelf) s = weakSelf;
            if (!s) return;

            struct IdeviceFfiError *err  = NULL;
            struct CoreDeviceProxyHandle *proxy = NULL;
            err = core_device_proxy_connect(s.provider, &proxy);

            if (!err && proxy) {
                // iOS 17+ (CoreDevice) パス
                uint16_t rsdPort = 0;
                struct IdeviceFfiError *portErr = core_device_proxy_get_server_rsd_port(proxy, &rsdPort);
                if (portErr) { idevice_error_free(portErr); }

                struct AdapterHandle *adapter = NULL;
                struct IdeviceFfiError *adaptErr = core_device_proxy_create_tcp_adapter(proxy, &adapter);
                if (adaptErr) { idevice_error_free(adaptErr); }

                // proxy の所有権は adapter に移転したので、adapter 取得後は解放不要
                // (adapter が null の場合のみ proxy を解放)
                if (adapter) {
                    s.adapter = adapter;

                    struct ReadWriteOpaque *rsdStream = NULL;
                    struct IdeviceFfiError *connErr = adapter_connect(adapter, rsdPort, &rsdStream);
                    if (connErr) { idevice_error_free(connErr); }

                    if (rsdStream) {
                        // BUG FIX: rsdStream は rsd_handshake_new に消費される
                        struct RsdHandshakeHandle *handshake = NULL;
                        struct IdeviceFfiError *hsErr = rsd_handshake_new(rsdStream, &handshake);
                        // rsdStream は consumed なので解放不可
                        if (hsErr) { idevice_error_free(hsErr); }

                        if (handshake) {
                            s.handshake = handshake;

                            struct RemoteServerHandle *server = NULL;
                            struct IdeviceFfiError *srvErr =
                                remote_server_connect_rsd(adapter, handshake, &server);
                            if (srvErr) { idevice_error_free(srvErr); }

                            if (server) {
                                s.remoteServer = server;

                                struct LocationSimulationHandle *sim17 = NULL;
                                struct IdeviceFfiError *simErr =
                                    location_simulation_new(server, &sim17);
                                if (simErr) { idevice_error_free(simErr); }

                                if (sim17) {
                                    s.simHandle17 = sim17;
                                    [s log:@"CD READY"];
                                    return;  // 成功: iOS 17+ パス完了
                                }
                            }
                        }
                    }
                } else {
                    // adapter 取得失敗時のみ proxy を解放
                    core_device_proxy_free(proxy);
                }
            } else if (err) {
                idevice_error_free(err);
                err = NULL;
            }

            // フォールバック: レガシー lockdown パス (iOS 16 以前)
            struct LocationSimulationServiceHandle *legacy = NULL;
            err = lockdown_location_simulation_connect(s.provider, &legacy);
            if (!err && legacy) {
                s.simHandleLegacy = legacy;
                [s log:@"LD READY"];
            } else {
                [s log:@"FAIL: NO SIM SERVICE"];
                if (err) { idevice_error_free(err); }
            }
        });
    }];
}

#pragma mark - Map & Marker

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    CLLocationCoordinate2D coord =
        [self.mapView convertPoint:[gesture locationInView:self.mapView]
              toCoordinateFromView:self.mapView];
    [self addDestination:coord];
}

- (void)addDestination:(CLLocationCoordinate2D)coord {
    MKPointAnnotation *ann = [[MKPointAnnotation alloc] init];
    ann.coordinate = coord;
    ann.title      = [NSString stringWithFormat:@"P%lu", (unsigned long)self.destinations.count + 1];
    [self.mapView addAnnotation:ann];
    [self.destinations addObject:ann];
    [self log:[NSString stringWithFormat:@"P%lu SET", (unsigned long)self.destinations.count]];

    if (self.modeControl.selectedSegmentIndex == MoveModeRoadAuto) {
        [self calculateRoute];
    }
}

- (void)updatePosMarker {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.currentPosMarker) {
            self.currentPosMarker       = [[MKPointAnnotation alloc] init];
            self.currentPosMarker.title = @"TARGET";
            [self.mapView addAnnotation:self.currentPosMarker];
        }
        // BUG FIX: MKPointAnnotation.coordinate は UIView.animate 不可→直接代入
        self.currentPosMarker.coordinate = self.currentSimulatedPos;
    });
}

- (void)centerOnPos {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.mapView setCenterCoordinate:self.currentSimulatedPos animated:YES];
    });
}

- (void)reverseDestinations {
    if (self.destinations.count < 2) return;
    NSArray *rev = [[self.destinations reverseObjectEnumerator] allObjects];
    [self.destinations removeAllObjects];
    [self.destinations addObjectsFromArray:rev];
    for (NSUInteger i = 0; i < self.destinations.count; i++) {
        self.destinations[i].title = [NSString stringWithFormat:@"P%lu", (unsigned long)i + 1];
    }
    [self log:@"PATH REVERSED"];
    if (self.modeControl.selectedSegmentIndex == MoveModeRoadAuto) {
        [self calculateRoute];
    }
}

- (void)clearDestinations {
    [self.moveTimer invalidate];
    self.moveTimer = nil;

    [self.mapView removeAnnotations:self.destinations];
    [self.destinations removeAllObjects];
    for (MKPolyline *p in self.routePolylines) [self.mapView removeOverlay:p];
    [self.routePolylines removeAllObjects];
    [self.currentPathPoints removeAllObjects];
    self.currentPathIndex = 0;

    [self.actionButton setTitle:@"START SIMULATION" forState:UIControlStateNormal];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (self.simHandleLegacy) {
            struct IdeviceFfiError *e = lockdown_location_simulation_clear(self.simHandleLegacy);
            if (e) { idevice_error_free(e); }
        }
        if (self.simHandle17) {
            struct IdeviceFfiError *e = location_simulation_clear(self.simHandle17);
            if (e) { idevice_error_free(e); }
        }
    });

    if (self.hasSetHome) {
        self.currentSimulatedPos = self.trueHomePos;
        [self centerOnPos];
        [self updatePosMarker];
    }
    [self log:@"RESET TO SYSTEM GPS"];
}

- (void)joyMove:(UIButton *)sender {
    // 速度に比例したステップ (5km/h → 0.0001度 ≒ 11m)
    double step = 0.0001 * ([self.speedTextField.text doubleValue] / 5.0);
    CLLocationCoordinate2D c = self.currentSimulatedPos;

    if      (sender == self.joyUp)    c.latitude  += step;
    else if (sender == self.joyDown)  c.latitude  -= step;
    else if (sender == self.joyLeft)  c.longitude -= step;
    else if (sender == self.joyRight) c.longitude += step;

    [self updateDeviceLocation:c];
    [self centerOnPos];
}

#pragma mark - Search

- (void)searchTextChanged:(UITextField *)sender {
    NSString *text = sender.text;
    if (text.length < 2) {
        self.searchContainer.hidden = YES;
        // BUG FIX: 進行中の検索をキャンセル
        [self.activeSearch cancel];
        self.activeSearch = nil;
        return;
    }

    // BUG FIX: 前の検索をキャンセルしてデバウンス
    [self.activeSearch cancel];
    self.activeSearch = nil;

    NSString *capturedText = [text copy];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        // フィールドが変わっていたら中断
        if (![self.searchField.text isEqualToString:capturedText]) return;

        MKLocalSearchRequest *req = [[MKLocalSearchRequest alloc] init];
        req.naturalLanguageQuery  = capturedText;

        MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:req];
        self.activeSearch = search;

        [search startWithCompletionHandler:^(MKLocalSearchResponse *resp, NSError *err) {
            if (search != self.activeSearch) return;  // 古い検索結果は捨てる
            self.activeSearch = nil;
            if (resp.mapItems.count > 0) {
                self.searchResults = resp.mapItems;
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.searchContainer.hidden = NO;
                    [self.searchResultsTable reloadData];
                });
            }
        }];
    });
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    NSString *t = textField.text;
    if ([t containsString:@","]) {
        NSArray<NSString *> *parts = [t componentsSeparatedByString:@","];
        if (parts.count == 2) {
            double lat = [parts[0] doubleValue];
            double lon = [parts[1] doubleValue];
            if (CLLocationCoordinate2DIsValid(CLLocationCoordinate2DMake(lat, lon))) {
                [self addDestination:CLLocationCoordinate2DMake(lat, lon)];
            }
        }
    }
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.searchResults.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell =
        [tableView dequeueReusableCellWithIdentifier:@"SimCell"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                  reuseIdentifier:@"SimCell"];

    cell.textLabel.textColor       = [UIColor whiteColor];
    cell.textLabel.font            = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    cell.detailTextLabel.textColor = [ThemeEngine textTertiary];
    cell.detailTextLabel.font      = [UIFont systemFontOfSize:11];
    cell.backgroundColor           = [UIColor clearColor];

    UIView *bg = [[UIView alloc] init];
    bg.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    cell.selectedBackgroundView = bg;

    NSUInteger row = (NSUInteger)indexPath.row;
    if (row < self.searchResults.count) {
        MKMapItem *item         = self.searchResults[row];
        cell.textLabel.text     = item.name;
        cell.detailTextLabel.text = item.name;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSUInteger row = (NSUInteger)indexPath.row;
    if (row < self.searchResults.count) {
        MKMapItem *item = self.searchResults[row];
        [self.mapView setCenterCoordinate:item.location.coordinate animated:YES];
        [self addDestination:item.location.coordinate];
        self.searchContainer.hidden = YES;
        self.searchField.text       = @"";
        [self.searchField resignFirstResponder];
    }
}

#pragma mark - Movement

- (void)actionTapped {
    if ([self.moveTimer isValid]) {
        [self.moveTimer invalidate];
        self.moveTimer = nil;
        [self.actionButton setTitle:@"START SIMULATION" forState:UIControlStateNormal];
        [self log:@"STOPPED"];
        return;
    }
    if (self.destinations.count == 0) { [self log:@"NO TARGET"]; return; }

    self.currentSpeedKmH = [self.speedTextField.text doubleValue];
    if (self.currentSpeedKmH <= 0) self.currentSpeedKmH = 5.0;

    MoveMode mode = (MoveMode)self.modeControl.selectedSegmentIndex;
    if (mode == MoveModeDirect) {
        [self updateDeviceLocation:self.destinations.firstObject.coordinate];
        [self log:@"TELEPORTED"];
    } else {
        [self startSimulation];
    }
}

- (void)startSimulation {
    MoveMode mode = (MoveMode)self.modeControl.selectedSegmentIndex;

    if (mode != MoveModeRoadAuto) {
        [self.currentPathPoints removeAllObjects];
    }
    self.currentPathIndex = 0;

    if (mode == MoveModeStraightAuto) {
        [self buildStraightPath];
    } else if (mode == MoveModeMultiPoint) {
        [self buildMultiPointPath];
    } else if (mode == MoveModeRoadAuto) {
        if (self.currentPathPoints.count == 0) {
            [self calculateRoute];
            return;
        }
    }

    if (self.currentPathPoints.count == 0) { [self log:@"NO PATH"]; return; }

    [self.actionButton setTitle:@"STOP SIMULATION" forState:UIControlStateNormal];

    // BUG FIX: NSRunLoopCommonModes でスクロール中もタイマー継続
    self.moveTimer = [NSTimer timerWithTimeInterval:kTickInterval
                                            target:self
                                          selector:@selector(onTick)
                                          userInfo:nil
                                           repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.moveTimer forMode:NSRunLoopCommonModes];
    [self log:@"RUNNING..."];
}

- (void)buildStraightPath {
    CLLocation *from = [[CLLocation alloc] initWithLatitude:self.currentSimulatedPos.latitude
                                                  longitude:self.currentSimulatedPos.longitude];
    CLLocation *to   = [[CLLocation alloc]
                        initWithLatitude:self.destinations.firstObject.coordinate.latitude
                               longitude:self.destinations.firstObject.coordinate.longitude];
    [self interpolateFrom:from to:to into:self.currentPathPoints];
}

- (void)buildMultiPointPath {
    CLLocation *prev = [[CLLocation alloc] initWithLatitude:self.currentSimulatedPos.latitude
                                                  longitude:self.currentSimulatedPos.longitude];
    for (MKPointAnnotation *ann in self.destinations) {
        CLLocation *next = [[CLLocation alloc] initWithLatitude:ann.coordinate.latitude
                                                      longitude:ann.coordinate.longitude];
        [self interpolateFrom:prev to:next into:self.currentPathPoints];
        prev = next;
    }
}

/// BUG FIX: ステップ数に上限を設けメモリ爆発を防止。
/// タイマー間隔 kTickInterval 秒ごとに1ポイント進む前提で計算。
- (void)interpolateFrom:(CLLocation *)start
                     to:(CLLocation *)end
                   into:(NSMutableArray<CLLocation *> *)path
{
    double dist     = [end distanceFromLocation:start];
    double speedMPS = (self.currentSpeedKmH * 1000.0) / 3600.0;
    // kTickInterval 秒ごとに speedMPS * kTickInterval メートル進む
    double metersPerTick = speedMPS * kTickInterval;
    int    steps         = MAX(1, (int)(dist / metersPerTick));

    // 上限チェック: 既存分も含めてkMaxPathPoints以内に収める
    NSInteger remaining = kMaxPathPoints - (NSInteger)path.count;
    if (remaining <= 0) return;
    if (steps > (int)remaining) steps = (int)remaining;

    for (int i = 1; i <= steps; i++) {
        double r = (double)i / (double)steps;
        double lat = start.coordinate.latitude  + (end.coordinate.latitude  - start.coordinate.latitude)  * r;
        double lon = start.coordinate.longitude + (end.coordinate.longitude - start.coordinate.longitude) * r;
        [path addObject:[[CLLocation alloc] initWithLatitude:lat longitude:lon]];
    }
}

- (void)calculateRoute {
    if (self.destinations.count == 0) return;
    [self log:@"ROUTING..."];

    for (MKPolyline *p in self.routePolylines) [self.mapView removeOverlay:p];
    [self.routePolylines removeAllObjects];

    CLLocationCoordinate2D startCoord =
        (self.destinations.count > 1)
        ? self.destinations.firstObject.coordinate
        : self.currentSimulatedPos;
    CLLocationCoordinate2D endCoord = self.destinations.lastObject.coordinate;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    MKPlacemark *srcMark = [[MKPlacemark alloc] initWithCoordinate:startCoord];
    MKPlacemark *dstMark = [[MKPlacemark alloc] initWithCoordinate:endCoord];
    MKDirectionsRequest *req = [[MKDirectionsRequest alloc] init];
    req.source               = [[MKMapItem alloc] initWithPlacemark:srcMark];
    req.destination          = [[MKMapItem alloc] initWithPlacemark:dstMark];
#pragma clang diagnostic pop
    req.transportType        = (self.transportControl.selectedSegmentIndex == 0)
                               ? MKDirectionsTransportTypeWalking
                               : MKDirectionsTransportTypeAutomobile;

    MKDirections *directions = [[MKDirections alloc] initWithRequest:req];
    __weak typeof(self) weakSelf = self;

    [directions calculateDirectionsWithCompletionHandler:^(MKDirectionsResponse *resp, NSError *err) {
        __strong typeof(weakSelf) s = weakSelf;
        if (!s) return;
        if (!resp || resp.routes.count == 0) { [s log:@"ROUTE FAIL"]; return; }

        MKRoute *route = resp.routes.firstObject;

        dispatch_async(dispatch_get_main_queue(), ^{
            [s.routePolylines addObject:route.polyline];
            [s.mapView addOverlay:route.polyline];
        });

        NSUInteger count = route.polyline.pointCount;
        if (count == 0) { [s log:@"ROUTE EMPTY"]; return; }

        CLLocationCoordinate2D *coords = malloc(sizeof(CLLocationCoordinate2D) * count);
        if (!coords) { [s log:@"ROUTE ALLOC FAIL"]; return; }
        [route.polyline getCoordinates:coords range:NSMakeRange(0, count)];

        [s.currentPathPoints removeAllObjects];
        CLLocation *prevL = nil;
        for (NSUInteger i = 0; i < count; i++) {
            CLLocation *currL = [[CLLocation alloc] initWithLatitude:coords[i].latitude
                                                           longitude:coords[i].longitude];
            if (prevL) {
                [s interpolateFrom:prevL to:currL into:s.currentPathPoints];
            } else {
                [s.currentPathPoints addObject:currL];
            }
            prevL = currL;
            // 上限到達なら打ち切り
            if (s.currentPathPoints.count >= (NSUInteger)kMaxPathPoints) break;
        }
        free(coords);
        [s log:@"ROUTE READY"];

        if (s.modeControl.selectedSegmentIndex == MoveModeRoadAuto && ![s.moveTimer isValid]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [s startSimulation];
            });
        }
    }];
}

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView
            rendererForOverlay:(id<MKOverlay>)overlay
{
    if ([overlay isKindOfClass:[MKPolyline class]]) {
        MKPolylineRenderer *r = [[MKPolylineRenderer alloc] initWithPolyline:(MKPolyline *)overlay];
        r.strokeColor = [UIColor systemBlueColor];
        r.lineWidth   = 4;
        return r;
    }
    return nil;
}

- (void)onTick {
    if (self.currentPathIndex >= (NSInteger)self.currentPathPoints.count) {
        if (self.loopSwitch.on) {
            self.currentPathIndex = 0;
        } else {
            [self.moveTimer invalidate];
            self.moveTimer = nil;
            [self.actionButton setTitle:@"START SIMULATION" forState:UIControlStateNormal];
            [self log:@"ARRIVED"];
        }
        return;
    }

    CLLocation *loc = self.currentPathPoints[(NSUInteger)self.currentPathIndex];
    [self updateDeviceLocation:loc.coordinate];
    self.currentPathIndex++;
}

- (void)updateDeviceLocation:(CLLocationCoordinate2D)coord {
    self.currentSimulatedPos = coord;
    [self updatePosMarker];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (self.simHandleLegacy) {
            char lat[32], lon[32];
            snprintf(lat, sizeof(lat), "%.8f", coord.latitude);
            snprintf(lon, sizeof(lon), "%.8f", coord.longitude);
            struct IdeviceFfiError *e = lockdown_location_simulation_set(self.simHandleLegacy, lat, lon);
            if (e) { idevice_error_free(e); }
        }
        if (self.simHandle17) {
            struct IdeviceFfiError *e = location_simulation_set(self.simHandle17,
                                                                coord.latitude,
                                                                coord.longitude);
            if (e) { idevice_error_free(e); }
        }
    });
}

#pragma mark - Favorites

- (void)showFavorites {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Favorites"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Save Current Location"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *a) { [self addFavorite]; }]];

    for (NSDictionary *fav in self.favorites) {
        NSString *name = fav[@"name"];
        [sheet addAction:[UIAlertAction actionWithTitle:name
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *a) {
            CLLocationCoordinate2D c =
                CLLocationCoordinate2DMake([fav[@"lat"] doubleValue], [fav[@"lon"] doubleValue]);
            [self.mapView setCenterCoordinate:c animated:YES];
            [self addDestination:c];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];

    // iPad: popoverPresentationController
    sheet.popoverPresentationController.sourceView = self.favButton;
    sheet.popoverPresentationController.sourceRect = self.favButton.bounds;

    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)addFavorite {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save Favorite"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Location name";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *a) {
        NSString *name = alert.textFields.firstObject.text;
        if (name.length == 0) name = @"Point";
        [self.favorites addObject:@{
            @"name": name,
            @"lat":  @(self.currentSimulatedPos.latitude),
            @"lon":  @(self.currentSimulatedPos.longitude)
        }];
        [[NSUserDefaults standardUserDefaults] setObject:self.favorites forKey:@"SimFavorites"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Dealloc

- (void)dealloc {
    // BUG FIX: NSTimer invalidate はメインスレッドから。
    // dealloc はどのスレッドからでも呼ばれ得るが、
    // ここでは retain cycle が無い設計なのでメインスレッド確定。
    [self.moveTimer invalidate];
    self.moveTimer = nil;

    [self.locManager stopUpdatingLocation];

    // C ハンドルの解放順序: 依存関係の逆順
    if (self.simHandleLegacy) { lockdown_location_simulation_free(self.simHandleLegacy); }
    if (self.simHandle17)     { location_simulation_free(self.simHandle17); }
    if (self.remoteServer)    { remote_server_free(self.remoteServer); }
    if (self.handshake)       { rsd_handshake_free(self.handshake); }
    if (self.adapter)         { adapter_free(self.adapter); }
}

@end
