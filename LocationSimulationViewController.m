#import "LocationSimulationViewController.h"
#import "ThemeEngine.h"
#import "DdiManager.h"
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>

typedef NS_ENUM(NSInteger, MoveMode) {
    MoveModeDirect,
    MoveModeStraightAuto,
    MoveModeRoadAuto,
    MoveModeMultiPoint
};

@interface LocationSimulationViewController () <MKMapViewDelegate, UISearchBarDelegate, UITableViewDelegate, UITableViewDataSource, CLLocationManagerDelegate>
@property (nonatomic, assign) struct IdeviceProviderHandle *provider;
@property (nonatomic, assign) struct LockdowndClientHandle *lockdown;
@property (nonatomic, assign) struct LocationSimulationHandle *simHandle17;
@property (nonatomic, assign) struct LocationSimulationServiceHandle *simHandleLegacy;
@property (nonatomic, assign) struct RemoteServerHandle *remoteServer;
@property (nonatomic, assign) struct AdapterHandle *adapter;
@property (nonatomic, assign) struct RsdHandshakeHandle *handshake;

@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIView *controlPanel;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UISegmentedControl *transportControl;
@property (nonatomic, strong) UITextField *speedTextField;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) UIButton *clearButton;
@property (nonatomic, strong) UIButton *favButton;
@property (nonatomic, strong) UIButton *reverseButton;
@property (nonatomic, strong) UIButton *centerButton;
@property (nonatomic, strong) UIButton *realLocButton;
@property (nonatomic, strong) UILabel *statusLabel;

@property (nonatomic, strong) UIView *joyBox;
@property (nonatomic, strong) UIButton *joyUp;
@property (nonatomic, strong) UIButton *joyDown;
@property (nonatomic, strong) UIButton *joyLeft;
@property (nonatomic, strong) UIButton *joyRight;
@property (nonatomic, strong) UISwitch *loopSwitch;
@property (nonatomic, strong) UILabel *loopLabel;

@property (nonatomic, strong) NSMutableArray<MKPointAnnotation *> *destinations;
@property (nonatomic, strong) MKPointAnnotation *currentPosMarker;
@property (nonatomic, strong) NSMutableArray<MKPolyline *> *routePolylines;
@property (nonatomic, strong) NSTimer *moveTimer;
@property (nonatomic, assign) CLLocationCoordinate2D currentSimulatedPos;
@property (nonatomic, strong) NSMutableArray<CLLocation *> *currentPathPoints;
@property (nonatomic, assign) NSInteger currentPathIndex;
@property (nonatomic, assign) double currentSpeedKmH;

@property (nonatomic, strong) CLLocationManager *locManager;
@property (nonatomic, assign) CLLocationCoordinate2D lastRealPos;
@property (nonatomic, assign) BOOL followRealPos;

@property (nonatomic, strong) UIVisualEffectView *searchContainer;
@property (nonatomic, strong) UITableView *searchResultsTable;
@property (nonatomic, strong) NSArray<MKMapItem *> *searchResults;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *favorites;
@end

@implementation LocationSimulationViewController

- (instancetype)initWithProvider:(struct IdeviceProviderHandle *)provider lockdown:(struct LockdowndClientHandle *)lockdown {
    self = [super init];
    if (self) {
        _provider = provider; _lockdown = lockdown;
        _destinations = [NSMutableArray array]; _currentPathPoints = [NSMutableArray array];
        _routePolylines = [NSMutableArray array]; _searchResults = [NSArray array];
        _currentSpeedKmH = 5.0; _favorites = [NSMutableArray array];
        NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:@"SimFavorites"];
        if (saved) [_favorites addObjectsFromArray:saved];
        _locManager = [[CLLocationManager alloc] init]; _locManager.delegate = self;
        _followRealPos = NO;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Location Simulation"; self.view.backgroundColor = [UIColor blackColor];
    [self setupUI]; [self connectSimulationService];
    [self.locManager requestWhenInUseAuthorization]; [self.locManager startUpdatingLocation];
    self.currentSimulatedPos = CLLocationCoordinate2DMake(35.6895, 139.6917);
    [self updatePosMarker];
    [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(self.currentSimulatedPos, 1000, 1000) animated:NO];
}

- (void)setupUI {
    self.mapView = [[MKMapView alloc] initWithFrame:self.view.bounds]; self.mapView.delegate = self; [self.view addSubview:self.mapView];
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)]; [self.mapView addGestureRecognizer:lp];

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero]; self.searchBar.delegate = self; self.searchBar.placeholder = @"Search or Lat,Lon..."; self.searchBar.barStyle = UIBarStyleBlack; self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.searchTextField.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    self.searchBar.backgroundImage = [[UIImage alloc] init];
    [self.view addSubview:self.searchBar];

    self.centerButton = [self createCircleBtn:@"⌖" act:@selector(centerOnPos)]; [self.view addSubview:self.centerButton];
    self.realLocButton = [self createCircleBtn:@"📍" act:@selector(useRealLocation)]; [self.view addSubview:self.realLocButton];

    self.searchContainer = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    self.searchContainer.layer.cornerRadius = 20; self.searchContainer.clipsToBounds = YES;
    self.searchContainer.hidden = YES; self.searchContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchContainer];

    self.searchResultsTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain]; self.searchResultsTable.delegate = self; self.searchResultsTable.dataSource = self;
    self.searchResultsTable.backgroundColor = [UIColor clearColor]; self.searchResultsTable.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.searchResultsTable.separatorColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    self.searchResultsTable.translatesAutoresizingMaskIntoConstraints = NO;
    [self.searchContainer.contentView addSubview:self.searchResultsTable];

    self.controlPanel = [[UIView alloc] initWithFrame:CGRectZero]; self.controlPanel.translatesAutoresizingMaskIntoConstraints = NO; [ThemeEngine applyGlassStyleToView:self.controlPanel cornerRadius:20]; [self.view addSubview:self.controlPanel];

    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"Direct", @"Straight", @"Road", @"Multi"]]; self.modeControl.translatesAutoresizingMaskIntoConstraints = NO; self.modeControl.selectedSegmentIndex = 0; [self.modeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateNormal]; [self.controlPanel addSubview:self.modeControl];

    self.transportControl = [[UISegmentedControl alloc] initWithItems:@[@"Walk", @"Cycle", @"Run", @"Car"]]; self.transportControl.translatesAutoresizingMaskIntoConstraints = NO; self.transportControl.selectedSegmentIndex = 0; [self.transportControl addTarget:self action:@selector(transportChanged:) forControlEvents:UIControlEventValueChanged]; [self.transportControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateNormal]; [self.controlPanel addSubview:self.transportControl];

    self.speedTextField = [[UITextField alloc] initWithFrame:CGRectZero]; self.speedTextField.translatesAutoresizingMaskIntoConstraints = NO; self.speedTextField.text = @"5"; self.speedTextField.textColor = [UIColor whiteColor]; self.speedTextField.borderStyle = UITextBorderStyleRoundedRect; self.speedTextField.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1]; self.speedTextField.keyboardType = UIKeyboardTypeDecimalPad; [self.controlPanel addSubview:self.speedTextField];

    self.actionButton = [UIButton buttonWithType:UIButtonTypeSystem]; self.actionButton.translatesAutoresizingMaskIntoConstraints = NO; [self.actionButton setTitle:@"START" forState:UIControlStateNormal]; self.actionButton.backgroundColor = [UIColor systemBlueColor]; self.actionButton.tintColor = [UIColor whiteColor]; self.actionButton.layer.cornerRadius = 10; [self.actionButton addTarget:self action:@selector(actionTapped) forControlEvents:UIControlEventTouchUpInside]; [self.controlPanel addSubview:self.actionButton];

    self.clearButton = [UIButton buttonWithType:UIButtonTypeSystem]; self.clearButton.translatesAutoresizingMaskIntoConstraints = NO; [self.clearButton setTitle:@"CLEAR" forState:UIControlStateNormal]; self.clearButton.tintColor = [UIColor systemRedColor]; [self.clearButton addTarget:self action:@selector(clearDestinations) forControlEvents:UIControlEventTouchUpInside]; [self.controlPanel addSubview:self.clearButton];

    self.reverseButton = [UIButton buttonWithType:UIButtonTypeSystem]; self.reverseButton.translatesAutoresizingMaskIntoConstraints = NO; [self.reverseButton setTitle:@"REV" forState:UIControlStateNormal]; self.reverseButton.tintColor = [UIColor systemOrangeColor]; [self.reverseButton addTarget:self action:@selector(reverseDestinations) forControlEvents:UIControlEventTouchUpInside]; [self.controlPanel addSubview:self.reverseButton];

    self.favButton = [UIButton buttonWithType:UIButtonTypeSystem]; self.favButton.translatesAutoresizingMaskIntoConstraints = NO; [self.favButton setTitle:@"FAV" forState:UIControlStateNormal]; [self.favButton addTarget:self action:@selector(showFavorites) forControlEvents:UIControlEventTouchUpInside]; [self.controlPanel addSubview:self.favButton];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero]; self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO; self.statusLabel.textColor = [UIColor systemGreenColor]; self.statusLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold]; self.statusLabel.text = @"READY"; self.statusLabel.textAlignment = NSTextAlignmentCenter; [self.controlPanel addSubview:self.statusLabel];

    self.loopSwitch = [[UISwitch alloc] init]; self.loopSwitch.translatesAutoresizingMaskIntoConstraints = NO; [self.controlPanel addSubview:self.loopSwitch];
    self.loopLabel = [[UILabel alloc] init]; self.loopLabel.text = @"LOOP"; self.loopLabel.textColor = [UIColor whiteColor]; self.loopLabel.font = [UIFont systemFontOfSize:10]; self.loopLabel.translatesAutoresizingMaskIntoConstraints = NO; [self.controlPanel addSubview:self.loopLabel];

    self.joyBox = [[UIView alloc] init]; self.joyBox.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:self.joyBox]; [ThemeEngine applyGlassStyleToView:self.joyBox cornerRadius:40];
    self.joyUp = [self createJoyBtn:@"▲" act:@selector(joyMove:)]; self.joyDown = [self createJoyBtn:@"▼" act:@selector(joyMove:)]; self.joyLeft = [self createJoyBtn:@"◀" act:@selector(joyMove:)]; self.joyRight = [self createJoyBtn:@"▶" act:@selector(joyMove:)];
    [self.joyBox addSubview:self.joyUp]; [self.joyBox addSubview:self.joyDown]; [self.joyBox addSubview:self.joyLeft]; [self.joyBox addSubview:self.joyRight];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    if (safe) {
        [NSLayoutConstraint activateConstraints:@[
            [self.searchBar.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10], [self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10], [self.searchBar.trailingAnchor constraintEqualToAnchor:self.centerButton.leadingAnchor constant:-10],
            [self.centerButton.centerYAnchor constraintEqualToAnchor:self.searchBar.centerYAnchor], [self.centerButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10], [self.centerButton.widthAnchor constraintEqualToConstant:40], [self.centerButton.heightAnchor constraintEqualToConstant:40],
            [self.realLocButton.topAnchor constraintEqualToAnchor:self.centerButton.bottomAnchor constant:10], [self.realLocButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10], [self.realLocButton.widthAnchor constraintEqualToConstant:40], [self.realLocButton.heightAnchor constraintEqualToConstant:40],
            [self.searchContainer.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:5], [self.searchContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:15], [self.searchContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15], [self.searchContainer.heightAnchor constraintEqualToConstant:300],
            [self.searchResultsTable.topAnchor constraintEqualToAnchor:self.searchContainer.topAnchor], [self.searchResultsTable.leadingAnchor constraintEqualToAnchor:self.searchContainer.leadingAnchor], [self.searchResultsTable.trailingAnchor constraintEqualToAnchor:self.searchContainer.trailingAnchor], [self.searchResultsTable.bottomAnchor constraintEqualToAnchor:self.searchContainer.bottomAnchor],
            [self.controlPanel.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-10], [self.controlPanel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10], [self.controlPanel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10], [self.controlPanel.heightAnchor constraintEqualToConstant:240],
            [self.modeControl.topAnchor constraintEqualToAnchor:self.controlPanel.topAnchor constant:12], [self.modeControl.leadingAnchor constraintEqualToAnchor:self.controlPanel.leadingAnchor constant:12], [self.modeControl.trailingAnchor constraintEqualToAnchor:self.controlPanel.trailingAnchor constant:-12],
            [self.transportControl.topAnchor constraintEqualToAnchor:self.modeControl.bottomAnchor constant:10], [self.transportControl.leadingAnchor constraintEqualToAnchor:self.controlPanel.leadingAnchor constant:12], [self.transportControl.trailingAnchor constraintEqualToAnchor:self.controlPanel.trailingAnchor constant:-12],
            [self.speedTextField.topAnchor constraintEqualToAnchor:self.transportControl.bottomAnchor constant:12], [self.speedTextField.leadingAnchor constraintEqualToAnchor:self.controlPanel.leadingAnchor constant:12], [self.speedTextField.widthAnchor constraintEqualToConstant:55],
            [self.actionButton.topAnchor constraintEqualToAnchor:self.speedTextField.topAnchor], [self.actionButton.leadingAnchor constraintEqualToAnchor:self.speedTextField.trailingAnchor constant:10], [self.actionButton.trailingAnchor constraintEqualToAnchor:self.favButton.leadingAnchor constant:-10], [self.actionButton.heightAnchor constraintEqualToConstant:40],
            [self.favButton.centerYAnchor constraintEqualToAnchor:self.actionButton.centerYAnchor], [self.favButton.trailingAnchor constraintEqualToAnchor:self.controlPanel.trailingAnchor constant:-12], [self.favButton.widthAnchor constraintEqualToConstant:45],
            [self.clearButton.topAnchor constraintEqualToAnchor:self.actionButton.bottomAnchor constant:8], [self.clearButton.leadingAnchor constraintEqualToAnchor:self.controlPanel.leadingAnchor constant:12],
            [self.reverseButton.centerYAnchor constraintEqualToAnchor:self.clearButton.centerYAnchor], [self.reverseButton.centerXAnchor constraintEqualToAnchor:self.controlPanel.centerXAnchor],
            [self.loopSwitch.centerYAnchor constraintEqualToAnchor:self.clearButton.centerYAnchor], [self.loopSwitch.trailingAnchor constraintEqualToAnchor:self.controlPanel.trailingAnchor constant:-12],
            [self.loopLabel.centerYAnchor constraintEqualToAnchor:self.loopSwitch.centerYAnchor], [self.loopLabel.trailingAnchor constraintEqualToAnchor:self.loopSwitch.leadingAnchor constant:-5],
            [self.statusLabel.bottomAnchor constraintEqualToAnchor:self.controlPanel.bottomAnchor constant:-5], [self.statusLabel.centerXAnchor constraintEqualToAnchor:self.controlPanel.centerXAnchor],
            [self.joyBox.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20], [self.joyBox.bottomAnchor constraintEqualToAnchor:self.controlPanel.topAnchor constant:-20], [self.joyBox.widthAnchor constraintEqualToConstant:80], [self.joyBox.heightAnchor constraintEqualToConstant:80],
            [self.joyUp.topAnchor constraintEqualToAnchor:self.joyBox.topAnchor], [self.joyUp.centerXAnchor constraintEqualToAnchor:self.joyBox.centerXAnchor], [self.joyDown.bottomAnchor constraintEqualToAnchor:self.joyBox.bottomAnchor], [self.joyDown.centerXAnchor constraintEqualToAnchor:self.joyBox.centerXAnchor],
            [self.joyLeft.leadingAnchor constraintEqualToAnchor:self.joyBox.leadingAnchor], [self.joyLeft.centerYAnchor constraintEqualToAnchor:self.joyBox.centerYAnchor], [self.joyRight.trailingAnchor constraintEqualToAnchor:self.joyBox.trailingAnchor], [self.joyRight.centerYAnchor constraintEqualToAnchor:self.joyBox.centerYAnchor]
        ]];
    }
}

- (UIButton *)createCircleBtn:(NSString *)t act:(SEL)a {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem]; [b setTitle:t forState:UIControlStateNormal]; b.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6]; b.tintColor = [UIColor whiteColor]; b.layer.cornerRadius = 20; b.translatesAutoresizingMaskIntoConstraints = NO; [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside]; return b;
}

- (UIButton *)createJoyBtn:(NSString *)t act:(SEL)a {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem]; [b setTitle:t forState:UIControlStateNormal]; b.titleLabel.font = [UIFont systemFontOfSize:22]; b.tintColor = [UIColor whiteColor]; [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside]; b.translatesAutoresizingMaskIntoConstraints = NO; return b;
}

- (void)log:(NSString *)msg { NSLog(@"[SimVC] %@", msg); dispatch_async(dispatch_get_main_queue(), ^{ self.statusLabel.text = [msg uppercaseString]; }); }

- (void)transportChanged:(UISegmentedControl *)sender {
    NSArray *v = @[@"5", @"20", @"40", @"80"]; if (sender.selectedSegmentIndex < v.count) self.speedTextField.text = v[sender.selectedSegmentIndex];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    self.lastRealPos = locations.lastObject.coordinate;
}

- (void)useRealLocation {
    if (self.lastRealPos.latitude == 0) { [self log:@"REAL LOC UNKNOWN"]; return; }
    self.currentSimulatedPos = self.lastRealPos; [self updateDeviceLocation:self.currentSimulatedPos]; [self centerOnPos]; [self log:@"SYNC TO REAL"];
}

- (void)connectSimulationService {
    [self log:@"TUNNELING..."];
    [[DdiManager sharedManager] checkAndMountDdiWithProvider:self.provider lockdown:self.lockdown completion:^(BOOL success, NSString *message) {
        if (!success) { [self log:[NSString stringWithFormat:@"DDI FAIL: %@", message]]; return; }
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            struct IdeviceFfiError *err = NULL; struct CoreDeviceProxyHandle *proxy = NULL; err = core_device_proxy_connect(self.provider, &proxy);
            if (!err) {
                uint16_t rsdPort = 0; core_device_proxy_get_server_rsd_port(proxy, &rsdPort);
                struct AdapterHandle *adapter = NULL; core_device_proxy_create_tcp_adapter(proxy, &adapter);
                if (adapter) {
                    self.adapter = adapter; struct ReadWriteOpaque *rsdStream = NULL; adapter_connect(adapter, rsdPort, &rsdStream);
                    struct RsdHandshakeHandle *handshake = NULL; rsd_handshake_new(rsdStream, &handshake);
                    if (handshake) {
                        self.handshake = handshake; struct RemoteServerHandle *server = NULL; remote_server_connect_rsd(adapter, handshake, &server);
                        if (server) {
                            self.remoteServer = server; struct LocationSimulationHandle *sim17 = NULL; location_simulation_new(server, &sim17);
                            if (sim17) { self.simHandle17 = sim17; [self log:@"CD READY"]; return; }
                        }
                    }
                }
                if (proxy) core_device_proxy_free(proxy);
            }
            if (err) { idevice_error_free(err); }
            struct LocationSimulationServiceHandle *legacy = NULL; err = lockdown_location_simulation_connect(self.provider, &legacy);
            if (!err) { self.simHandleLegacy = legacy; [self log:@"LD READY"]; }
            else { [self log:@"FAIL"]; idevice_error_free(err); }
        });
    }];
}

#pragma mark - Map & Marker

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    CLLocationCoordinate2D coord = [self.mapView convertPoint:[gesture locationInView:self.mapView] toCoordinateFromView:self.mapView];
    [self addDestination:coord];
}

- (void)addDestination:(CLLocationCoordinate2D)coord {
    MKPointAnnotation *ann = [[MKPointAnnotation alloc] init]; ann.coordinate = coord; ann.title = [NSString stringWithFormat:@"P%lu", (unsigned long)self.destinations.count + 1];
    [self.mapView addAnnotation:ann]; [self.destinations addObject:ann]; [self log:[NSString stringWithFormat:@"P%lu SET", (unsigned long)self.destinations.count]];
    if (self.modeControl.selectedSegmentIndex == MoveModeRoadAuto) [self calculateRoute];
}

- (void)updatePosMarker {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.currentPosMarker) { self.currentPosMarker = [[MKPointAnnotation alloc] init]; self.currentPosMarker.title = @"ME"; [self.mapView addAnnotation:self.currentPosMarker]; }
        [UIView animateWithDuration:0.5 animations:^{ self.currentPosMarker.coordinate = self.currentSimulatedPos; }];
    });
}

- (void)centerOnPos { [self.mapView setCenterCoordinate:self.currentSimulatedPos animated:YES]; }

- (void)reverseDestinations {
    if (self.destinations.count < 2) return;
    NSArray *rev = [[self.destinations reverseObjectEnumerator] allObjects]; [self.destinations removeAllObjects]; [self.destinations addObjectsFromArray:rev];
    for (NSUInteger i = 0; i < self.destinations.count; i++) self.destinations[i].title = [NSString stringWithFormat:@"P%lu", (unsigned long)i + 1];
    [self log:@"REVERSED"]; if (self.modeControl.selectedSegmentIndex == MoveModeRoadAuto) [self calculateRoute];
}

- (void)clearDestinations {
    [self.moveTimer invalidate]; [self.mapView removeAnnotations:self.destinations]; [self.destinations removeAllObjects];
    for (MKPolyline *p in self.routePolylines) [self.mapView removeOverlay:p]; [self.routePolylines removeAllObjects];
    [self.currentPathPoints removeAllObjects]; [self.actionButton setTitle:@"START" forState:UIControlStateNormal];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{ if (self.simHandleLegacy) lockdown_location_simulation_clear(self.simHandleLegacy); if (self.simHandle17) location_simulation_clear(self.simHandle17); });
    [self log:@"CLEARED"];
}

- (void)joyMove:(UIButton *)sender {
    double step = 0.0001 * ([self.speedTextField.text doubleValue] / 5.0); CLLocationCoordinate2D c = self.currentSimulatedPos;
    if (sender == self.joyUp) c.latitude += step; else if (sender == self.joyDown) c.latitude -= step; else if (sender == self.joyLeft) c.longitude -= step; else if (sender == self.joyRight) c.longitude += step;
    [self updateDeviceLocation:c]; [self centerOnPos];
}

#pragma mark - Search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length < 2) { dispatch_async(dispatch_get_main_queue(), ^{ self.searchContainer.hidden = YES; }); return; }
    MKLocalSearchRequest *req = [[MKLocalSearchRequest alloc] init]; req.naturalLanguageQuery = searchText;
    [[[MKLocalSearch alloc] initWithRequest:req] startWithCompletionHandler:^(MKLocalSearchResponse *resp, NSError *err) {
        if (resp) { self.searchResults = resp.mapItems; dispatch_async(dispatch_get_main_queue(), ^{ self.searchContainer.hidden = NO; [self.searchResultsTable reloadData]; }); }
    }];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    if ([searchBar.text containsString:@","]) {
        NSArray *p = [searchBar.text componentsSeparatedByString:@","];
        if (p.count == 2) [self addDestination:CLLocationCoordinate2DMake([p[0] doubleValue], [p[1] doubleValue])];
    } [searchBar resignFirstResponder];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.searchResults.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
    cell.textLabel.textColor = [UIColor whiteColor]; cell.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
    cell.backgroundColor = [UIColor clearColor]; cell.selectedBackgroundView = [[UIView alloc] init]; cell.selectedBackgroundView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    cell.textLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium]; cell.detailTextLabel.font = [UIFont systemFontOfSize:10];
    if (indexPath.row < self.searchResults.count) { MKMapItem *item = self.searchResults[indexPath.row]; cell.textLabel.text = item.name; cell.detailTextLabel.text = item.placemark.title; }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row < self.searchResults.count) {
        MKMapItem *item = self.searchResults[indexPath.row]; [self.mapView setCenterCoordinate:item.location.coordinate animated:YES]; [self addDestination:item.location.coordinate];
        self.searchContainer.hidden = YES; self.searchBar.text = @""; [self.searchBar resignFirstResponder];
    }
}

#pragma mark - Movement Execution

- (void)actionTapped {
    if ([self.moveTimer isValid]) { [self.moveTimer invalidate]; [self.actionButton setTitle:@"START" forState:UIControlStateNormal]; [self log:@"STOPPED"]; return; }
    if (self.destinations.count == 0) { [self log:@"NO TARGET"]; return; }
    self.currentSpeedKmH = [self.speedTextField.text doubleValue] ?: 5.0;
    MoveMode mode = (MoveMode)self.modeControl.selectedSegmentIndex;
    if (mode == MoveModeDirect) { [self updateDeviceLocation:self.destinations.firstObject.coordinate]; [self log:@"JUMPED"]; }
    else { [self startSimulation]; }
}

- (void)startSimulation {
    MoveMode mode = (MoveMode)self.modeControl.selectedSegmentIndex;
    if (mode != MoveModeRoadAuto) { [self.currentPathPoints removeAllObjects]; }
    self.currentPathIndex = 0;
    if (mode == MoveModeStraightAuto) { [self buildStraightPath]; }
    else if (mode == MoveModeMultiPoint) { [self buildMultiPointPath]; }
    else if (mode == MoveModeRoadAuto) { if (self.currentPathPoints.count == 0) { [self calculateRoute]; return; } }

    if (self.currentPathPoints.count > 0) {
        [self.actionButton setTitle:@"STOP" forState:UIControlStateNormal];
        self.moveTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(onTick) userInfo:nil repeats:YES];
        [self log:@"MOVING..."];
    }
}

- (void)buildStraightPath {
    [self interpolateBetween:[[CLLocation alloc] initWithLatitude:self.currentSimulatedPos.latitude longitude:self.currentSimulatedPos.longitude] and:[[CLLocation alloc] initWithLatitude:self.destinations.firstObject.coordinate.latitude longitude:self.destinations.firstObject.coordinate.longitude] into:self.currentPathPoints];
}

- (void)buildMultiPointPath {
    CLLocation *prev = [[CLLocation alloc] initWithLatitude:self.currentSimulatedPos.latitude longitude:self.currentSimulatedPos.longitude];
    for (MKPointAnnotation *ann in self.destinations) { CLLocation *next = [[CLLocation alloc] initWithLatitude:ann.coordinate.latitude longitude:ann.coordinate.longitude]; [self interpolateBetween:prev and:next into:self.currentPathPoints]; prev = next; }
}

- (void)interpolateBetween:(CLLocation *)start and:(CLLocation *)end into:(NSMutableArray *)path {
    double dist = [end distanceFromLocation:start]; double speedMPS = (self.currentSpeedKmH * 1000.0) / 3600.0; int steps = MAX(1, (int)(dist / speedMPS));
    for (int i = 1; i <= steps; i++) {
        double r = (double)i / steps;
        [path addObject:[[CLLocation alloc] initWithLatitude:start.coordinate.latitude + (end.coordinate.latitude - start.coordinate.latitude) * r longitude:start.coordinate.longitude + (end.coordinate.longitude - start.coordinate.longitude) * r]];
    }
}

- (void)calculateRoute {
    if (self.destinations.count == 0) return; [self log:@"ROUTING..."];
    for (MKPolyline *p in self.routePolylines) [self.mapView removeOverlay:p]; [self.routePolylines removeAllObjects];
    CLLocationCoordinate2D start = (self.destinations.count > 1) ? self.destinations.firstObject.coordinate : self.currentSimulatedPos;
    CLLocationCoordinate2D end = self.destinations.lastObject.coordinate;
    MKDirectionsRequest *req = [[MKDirectionsRequest alloc] init];
    req.source = [[MKMapItem alloc] initWithLocation:[[CLLocation alloc] initWithLatitude:start.latitude longitude:start.longitude] address:nil];
    req.destination = [[MKMapItem alloc] initWithLocation:[[CLLocation alloc] initWithLatitude:end.latitude longitude:end.longitude] address:nil];
    req.transportType = (self.transportControl.selectedSegmentIndex == 0) ? MKDirectionsTransportTypeWalking : MKDirectionsTransportTypeAutomobile;
    [[[MKDirections alloc] initWithRequest:req] calculateDirectionsWithCompletionHandler:^(MKDirectionsResponse *resp, NSError *err) {
        if (resp.routes.count > 0) {
            MKRoute *route = resp.routes.firstObject;
            dispatch_async(dispatch_get_main_queue(), ^{ [self.routePolylines addObject:route.polyline]; [self.mapView addOverlay:route.polyline]; });
            NSUInteger count = route.polyline.pointCount; CLLocationCoordinate2D *coords = malloc(sizeof(CLLocationCoordinate2D) * count); [route.polyline getCoordinates:coords range:NSMakeRange(0, count)];
            [self.currentPathPoints removeAllObjects]; CLLocation *prevL = nil;
            for (NSUInteger i = 0; i < count; i++) {
                CLLocation *currL = [[CLLocation alloc] initWithLatitude:coords[i].latitude longitude:coords[i].longitude];
                if (prevL) [self interpolateBetween:prevL and:currL into:self.currentPathPoints]; else [self.currentPathPoints addObject:currL];
                prevL = currL;
            }
            free(coords); [self log:@"ROUTE OK"];
            if (self.modeControl.selectedSegmentIndex == MoveModeRoadAuto && ![self.moveTimer isValid]) dispatch_async(dispatch_get_main_queue(), ^{ [self startSimulation]; });
        } else [self log:@"ROUTE FAIL"];
    }];
}

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay {
    if ([overlay isKindOfClass:[MKPolyline class]]) { MKPolylineRenderer *r = [[MKPolylineRenderer alloc] initWithPolyline:(MKPolyline *)overlay]; r.strokeColor = [UIColor systemBlueColor]; r.lineWidth = 4; return r; }
    return nil;
}

- (void)onTick {
    if (self.currentPathIndex >= self.currentPathPoints.count) {
        if (self.loopSwitch.on) { self.currentPathIndex = 0; }
        else { [self.moveTimer invalidate]; [self.actionButton setTitle:@"START" forState:UIControlStateNormal]; [self log:@"ARRIVED"]; return; }
    }
    CLLocation *loc = self.currentPathPoints[self.currentPathIndex]; [self updateDeviceLocation:loc.coordinate]; self.currentPathIndex++;
}

- (void)updateDeviceLocation:(CLLocationCoordinate2D)coord {
    self.currentSimulatedPos = coord; [self updatePosMarker];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        if (self.simHandleLegacy) { char lat[32], lon[32]; snprintf(lat, 32, "%.8f", coord.latitude); snprintf(lon, 32, "%.8f", coord.longitude); lockdown_location_simulation_set(self.simHandleLegacy, lat, lon); }
        if (self.simHandle17) location_simulation_set(self.simHandle17, coord.latitude, coord.longitude);
    });
}

#pragma mark - Favorites

- (void)showFavorites {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Favorites" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Add Current" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self addFavorite]; }]];
    for (NSDictionary *fav in self.favorites) { [sheet addAction:[UIAlertAction actionWithTitle:fav[@"name"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        CLLocationCoordinate2D c = CLLocationCoordinate2DMake([fav[@"lat"] doubleValue], [fav[@"lon"] doubleValue]); [self.mapView setCenterCoordinate:c animated:YES]; [self addDestination:c];
    }]]; }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:sheet animated:YES completion:nil];
}

- (void)addFavorite {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save Favorite" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:nil]; [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields.firstObject.text ?: @"Point"; [self.favorites addObject:@{@"name": name, @"lat": @(self.currentSimulatedPos.latitude), @"lon": @(self.currentSimulatedPos.longitude)}];
        [[NSUserDefaults standardUserDefaults] setObject:self.favorites forKey:@"SimFavorites"];
    }]]; [self presentViewController:alert animated:YES completion:nil];
}

- (void)dealloc {
    [self.locManager stopUpdatingLocation];
    [self.moveTimer invalidate]; if (self.simHandleLegacy) lockdown_location_simulation_free(self.simHandleLegacy);
    if (self.simHandle17) location_simulation_free(self.simHandle17); if (self.remoteServer) remote_server_free(self.remoteServer);
    if (self.handshake) rsd_handshake_free(self.handshake); if (self.adapter) adapter_free(self.adapter);
}
@end
