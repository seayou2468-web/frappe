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

@interface LocationSimulationViewController () <MKMapViewDelegate, UISearchBarDelegate, UITableViewDelegate, UITableViewDataSource>
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
@property (nonatomic, strong) UILabel *statusLabel;

@property (nonatomic, strong) NSMutableArray<MKPointAnnotation *> *destinations;
@property (nonatomic, strong) MKPolyline *currentRoutePolyline;
@property (nonatomic, strong) NSTimer *moveTimer;
@property (nonatomic, assign) CLLocationCoordinate2D currentSimulatedPos;
@property (nonatomic, strong) NSMutableArray<CLLocation *> *currentPathPoints;
@property (nonatomic, assign) NSInteger currentPathIndex;
@property (nonatomic, assign) double currentSpeedKmH;

@property (nonatomic, strong) UITableView *searchResultsTable;
@property (nonatomic, strong) NSArray<MKMapItem *> *searchResults;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *favorites;
@end

@implementation LocationSimulationViewController

- (instancetype)initWithProvider:(struct IdeviceProviderHandle *)provider lockdown:(struct LockdowndClientHandle *)lockdown {
    self = [super init];
    if (self) {
        _provider = provider;
        _lockdown = lockdown;
        _destinations = [[NSMutableArray alloc] init];
        _currentPathPoints = [[NSMutableArray alloc] init];
        _searchResults = [[NSArray alloc] init];
        _currentSpeedKmH = 5.0;
        _favorites = [[NSMutableArray alloc] init];
        NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:@"SimFavorites"];
        if (saved) [_favorites addObjectsFromArray:saved];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Location Simulation";
    self.view.backgroundColor = [UIColor blackColor];
    [self setupUI];
    [self connectSimulationService];

    self.currentSimulatedPos = CLLocationCoordinate2DMake(35.6895, 139.6917);
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(self.currentSimulatedPos, 1000, 1000);
    [self.mapView setRegion:region animated:NO];
}

- (void)setupUI {
    self.mapView = [[MKMapView alloc] initWithFrame:self.view.bounds];
    self.mapView.delegate = self;
    [self.view addSubview:self.mapView];

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [self.mapView addGestureRecognizer:lp];

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"Search or Lat,Lon...";
    self.searchBar.barStyle = UIBarStyleBlack;
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchBar];

    self.searchResultsTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.searchResultsTable.delegate = self;
    self.searchResultsTable.dataSource = self;
    self.searchResultsTable.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.9];
    self.searchResultsTable.hidden = YES;
    self.searchResultsTable.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchResultsTable];

    self.controlPanel = [[UIView alloc] initWithFrame:CGRectZero];
    self.controlPanel.translatesAutoresizingMaskIntoConstraints = NO;
    [ThemeEngine applyGlassStyleToView:self.controlPanel cornerRadius:20];
    [self.view addSubview:self.controlPanel];

    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"Direct", @"Straight", @"Road", @"Multi"]];
    self.modeControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.modeControl.selectedSegmentIndex = 0;
    [self.modeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateNormal];
    [self.controlPanel addSubview:self.modeControl];

    self.transportControl = [[UISegmentedControl alloc] initWithItems:@[@"Walk", @"Cycle", @"Car"]];
    self.transportControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.transportControl.selectedSegmentIndex = 0;
    [self.transportControl addTarget:self action:@selector(transportChanged:) forControlEvents:UIControlEventValueChanged];
    [self.transportControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateNormal];
    [self.controlPanel addSubview:self.transportControl];

    self.speedTextField = [[UITextField alloc] initWithFrame:CGRectZero];
    self.speedTextField.translatesAutoresizingMaskIntoConstraints = NO;
    self.speedTextField.text = @"5";
    self.speedTextField.textColor = [UIColor whiteColor];
    self.speedTextField.borderStyle = UITextBorderStyleRoundedRect;
    self.speedTextField.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    self.speedTextField.keyboardType = UIKeyboardTypeDecimalPad;
    [self.controlPanel addSubview:self.speedTextField];

    self.actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.actionButton setTitle:@"START" forState:UIControlStateNormal];
    self.actionButton.backgroundColor = [UIColor systemBlueColor];
    self.actionButton.tintColor = [UIColor whiteColor];
    self.actionButton.layer.cornerRadius = 10;
    [self.actionButton addTarget:self action:@selector(actionTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.controlPanel addSubview:self.actionButton];

    self.clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.clearButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.clearButton setTitle:@"CLEAR ALL" forState:UIControlStateNormal];
    self.clearButton.tintColor = [UIColor systemRedColor];
    [self.clearButton addTarget:self action:@selector(clearDestinations) forControlEvents:UIControlEventTouchUpInside];
    [self.controlPanel addSubview:self.clearButton];

    self.favButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.favButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.favButton setTitle:@"FAV" forState:UIControlStateNormal];
    [self.favButton addTarget:self action:@selector(showFavorites) forControlEvents:UIControlEventTouchUpInside];
    [self.controlPanel addSubview:self.favButton];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.textColor = [UIColor systemGreenColor];
    self.statusLabel.font = [UIFont systemFontOfSize:10];
    self.statusLabel.text = @"READY";
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.controlPanel addSubview:self.statusLabel];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    if (safe) {
        [NSLayoutConstraint activateConstraints:@[
            [self.searchBar.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
            [self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
            [self.searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
            [self.searchResultsTable.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
            [self.searchResultsTable.leadingAnchor constraintEqualToAnchor:self.searchBar.leadingAnchor],
            [self.searchResultsTable.trailingAnchor constraintEqualToAnchor:self.searchBar.trailingAnchor],
            [self.searchResultsTable.heightAnchor constraintEqualToConstant:250],
            [self.controlPanel.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-20],
            [self.controlPanel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:15],
            [self.controlPanel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],
            [self.controlPanel.heightAnchor constraintEqualToConstant:220],
            [self.modeControl.topAnchor constraintEqualToAnchor:self.controlPanel.topAnchor constant:15],
            [self.modeControl.leadingAnchor constraintEqualToAnchor:self.controlPanel.leadingAnchor constant:15],
            [self.modeControl.trailingAnchor constraintEqualToAnchor:self.controlPanel.trailingAnchor constant:-15],
            [self.transportControl.topAnchor constraintEqualToAnchor:self.modeControl.bottomAnchor constant:10],
            [self.transportControl.leadingAnchor constraintEqualToAnchor:self.controlPanel.leadingAnchor constant:15],
            [self.transportControl.trailingAnchor constraintEqualToAnchor:self.controlPanel.trailingAnchor constant:-15],
            [self.speedTextField.topAnchor constraintEqualToAnchor:self.transportControl.bottomAnchor constant:15],
            [self.speedTextField.leadingAnchor constraintEqualToAnchor:self.controlPanel.leadingAnchor constant:15],
            [self.speedTextField.widthAnchor constraintEqualToConstant:70],
            [self.actionButton.topAnchor constraintEqualToAnchor:self.speedTextField.topAnchor],
            [self.actionButton.leadingAnchor constraintEqualToAnchor:self.speedTextField.trailingAnchor constant:10],
            [self.actionButton.trailingAnchor constraintEqualToAnchor:self.favButton.leadingAnchor constant:-10],
            [self.actionButton.heightAnchor constraintEqualToConstant:40],
            [self.favButton.centerYAnchor constraintEqualToAnchor:self.actionButton.centerYAnchor],
            [self.favButton.trailingAnchor constraintEqualToAnchor:self.controlPanel.trailingAnchor constant:-15],
            [self.favButton.widthAnchor constraintEqualToConstant:50],
            [self.clearButton.topAnchor constraintEqualToAnchor:self.actionButton.bottomAnchor constant:5],
            [self.clearButton.centerXAnchor constraintEqualToAnchor:self.controlPanel.centerXAnchor],
            [self.statusLabel.topAnchor constraintEqualToAnchor:self.clearButton.bottomAnchor constant:5],
            [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.controlPanel.leadingAnchor constant:10],
            [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.controlPanel.trailingAnchor constant:-10]
        ]];
    }
}

- (void)log:(NSString *)msg {
    NSLog(@"[SimVC] %@", msg);
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = msg;
    });
}

- (void)transportChanged:(UISegmentedControl *)sender {
    switch (sender.selectedSegmentIndex) {
        case 0: self.speedTextField.text = @"5"; break;
        case 1: self.speedTextField.text = @"20"; break;
        case 2: self.speedTextField.text = @"60"; break;
    }
}

- (void)connectSimulationService {
    [self log:@"Initializing Tunnel..."];
    [[DdiManager sharedManager] checkAndMountDdiWithProvider:self.provider lockdown:self.lockdown completion:^(BOOL success, NSString *message) {
        if (!success) {
            [self log:[NSString stringWithFormat:@"DDI FAIL: %@", message]];
            return;
        }
        [self log:@"DDI Active. Establishing Session..."];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            struct IdeviceFfiError *err = NULL;

            // 1. Try iOS 17+ (CoreDevice)
            struct CoreDeviceProxyHandle *proxy = NULL;
            err = core_device_proxy_connect(self.provider, &proxy);
            if (!err) {
                uint16_t rsdPort = 0;
                err = core_device_proxy_get_server_rsd_port(proxy, &rsdPort);
                if (!err) {
                    struct AdapterHandle *adapter = NULL;
                    err = core_device_proxy_create_tcp_adapter(proxy, &adapter);
                    if (!err) {
                        self.adapter = adapter;
                        struct ReadWriteOpaque *rsdStream = NULL;
                        err = adapter_connect(adapter, rsdPort, &rsdStream);
                        if (!err) {
                            struct RsdHandshakeHandle *handshake = NULL;
                            err = rsd_handshake_new(rsdStream, &handshake);
                            if (!err) {
                                self.handshake = handshake;
                                struct RemoteServerHandle *server = NULL;
                                err = remote_server_connect_rsd(adapter, handshake, &server);
                                if (!err) {
                                    self.remoteServer = server;
                                    struct LocationSimulationHandle *sim17 = NULL;
                                    err = location_simulation_new(server, &sim17);
                                    if (!err) {
                                        self.simHandle17 = sim17;
                                        [self log:@"CoreDevice Service Ready"];
                                        return;
                                    }
                                }
                            }
                        }
                    }
                }
                if (proxy) core_device_proxy_free(proxy);
            }
            if (err) { idevice_error_free(err); err = NULL; }

            // 2. Try Legacy (Lockdown)
            struct LocationSimulationServiceHandle *legacy = NULL;
            err = lockdown_location_simulation_connect(self.provider, &legacy);
            if (!err) {
                self.simHandleLegacy = legacy;
                [self log:@"Legacy Service Ready"];
            } else {
                [self log:[NSString stringWithFormat:@"FAIL: %s", err->message]];
                idevice_error_free(err);
            }
        });
    }];
}

#pragma mark - Map & Touch

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    CGPoint touchPoint = [gesture locationInView:self.mapView];
    CLLocationCoordinate2D coord = [self.mapView convertPoint:touchPoint toCoordinateFromView:self.mapView];
    [self addDestination:coord];
}

- (void)addDestination:(CLLocationCoordinate2D)coord {
    MKPointAnnotation *ann = [[MKPointAnnotation alloc] init];
    ann.coordinate = coord;
    ann.title = [NSString stringWithFormat:@"Target %lu", (unsigned long)self.destinations.count + 1];
    [self.mapView addAnnotation:ann];
    [self.destinations addObject:ann];
    [self log:[NSString stringWithFormat:@"Point added (%lu total)", (unsigned long)self.destinations.count]];

    if (self.modeControl.selectedSegmentIndex == MoveModeRoadAuto) {
        [self calculateRoute];
    }
}

- (void)clearDestinations {
    [self.moveTimer invalidate];
    [self.mapView removeAnnotations:self.destinations];
    [self.destinations removeAllObjects];
    if (self.currentRoutePolyline) [self.mapView removeOverlay:self.currentRoutePolyline];
    self.currentPathPoints = [[NSMutableArray alloc] init];
    [self.actionButton setTitle:@"START" forState:UIControlStateNormal];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (self.simHandleLegacy) lockdown_location_simulation_clear(self.simHandleLegacy);
        if (self.simHandle17) location_simulation_clear(self.simHandle17);
    });
    [self log:@"Simulation cleared"];
}

#pragma mark - Search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length < 2) {
        dispatch_async(dispatch_get_main_queue(), ^{ self.searchResultsTable.hidden = YES; });
        return;
    }
    MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] init];
    request.naturalLanguageQuery = searchText;
    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:request];
    [search startWithCompletionHandler:^(MKLocalSearchResponse *resp, NSError *err) {
        if (resp) {
            self.searchResults = resp.mapItems;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.searchResultsTable.hidden = NO;
                [self.searchResultsTable reloadData];
            });
        }
    }];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.searchResults.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor lightGrayColor];
        cell.backgroundColor = [UIColor clearColor];
    }
    if (indexPath.row < self.searchResults.count) {
        MKMapItem *item = self.searchResults[indexPath.row];
        cell.textLabel.text = item.name;
        cell.detailTextLabel.text = item.name;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row < self.searchResults.count) {
        MKMapItem *item = self.searchResults[indexPath.row];
        [self.mapView setCenterCoordinate:item.location.coordinate animated:YES];
        [self addDestination:item.location.coordinate];
        self.searchResultsTable.hidden = YES;
        self.searchBar.text = @"";
        [self.searchBar resignFirstResponder];
    }
}

#pragma mark - Movement Execution

- (void)actionTapped {
    if ([self.moveTimer isValid]) {
        [self.moveTimer invalidate];
        [self.actionButton setTitle:@"START" forState:UIControlStateNormal];
        [self log:@"Simulation stopped"];
        return;
    }
    if (self.destinations.count == 0) {
        [self log:@"Add a target point first"];
        return;
    }
    self.currentSpeedKmH = [self.speedTextField.text doubleValue] ?: 5.0;

    MoveMode mode = (MoveMode)self.modeControl.selectedSegmentIndex;
    if (mode == MoveModeDirect) {
        [self updateDeviceLocation:self.destinations.firstObject.coordinate];
        [self log:@"Direct teleport successful"];
    } else {
        [self startSimulation];
    }
}

- (void)startSimulation {
    MoveMode mode = (MoveMode)self.modeControl.selectedSegmentIndex;
    if (mode != MoveModeRoadAuto) { [self.currentPathPoints removeAllObjects]; }
    self.currentPathIndex = 0;

    if (mode == MoveModeStraightAuto) {
        [self buildStraightPath];
    } else if (mode == MoveModeMultiPoint) {
        [self buildMultiPointPath];
    } else if (mode == MoveModeRoadAuto) {
        if (!self.currentPathPoints || self.currentPathPoints.count == 0) {
            [self calculateRoute];
            return;
        }
    }

    if (self.currentPathPoints.count > 0) {
        [self.actionButton setTitle:@"STOP" forState:UIControlStateNormal];
        self.moveTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(onTick) userInfo:nil repeats:YES];
        [self log:@"Simulation active"];
    }
}

- (void)buildStraightPath {
    CLLocation *start = [[CLLocation alloc] initWithLatitude:self.currentSimulatedPos.latitude longitude:self.currentSimulatedPos.longitude];
    CLLocation *end = [[CLLocation alloc] initWithLatitude:self.destinations.firstObject.coordinate.latitude longitude:self.destinations.firstObject.coordinate.longitude];
    [self interpolateBetween:start and:end into:self.currentPathPoints];
}

- (void)buildMultiPointPath {
    CLLocation *prev = [[CLLocation alloc] initWithLatitude:self.currentSimulatedPos.latitude longitude:self.currentSimulatedPos.longitude];
    for (MKPointAnnotation *ann in self.destinations) {
        CLLocation *next = [[CLLocation alloc] initWithLatitude:ann.coordinate.latitude longitude:ann.coordinate.longitude];
        [self interpolateBetween:prev and:next into:self.currentPathPoints];
        prev = next;
    }
}

- (void)interpolateBetween:(CLLocation *)start and:(CLLocation *)end into:(NSMutableArray *)path {
    double dist = [end distanceFromLocation:start];
    double speedMPS = (self.currentSpeedKmH * 1000.0) / 3600.0;
    int steps = MAX(1, (int)(dist / speedMPS));
    for (int i = 1; i <= steps; i++) {
        double r = (double)i / steps;
        double lat = start.coordinate.latitude + (end.coordinate.latitude - start.coordinate.latitude) * r;
        double lon = start.coordinate.longitude + (end.coordinate.longitude - start.coordinate.longitude) * r;
        [path addObject:[[CLLocation alloc] initWithLatitude:lat longitude:lon]];
    }
}

- (void)calculateRoute {
    if (self.destinations.count == 0) return;
    [self log:@"Calculating route..."];
    MKDirectionsRequest *req = [[MKDirectionsRequest alloc] init];
    CLLocation *sourceLoc = [[CLLocation alloc] initWithLatitude:self.currentSimulatedPos.latitude longitude:self.currentSimulatedPos.longitude];
    CLLocation *destLoc = [[CLLocation alloc] initWithLatitude:self.destinations.lastObject.coordinate.latitude longitude:self.destinations.lastObject.coordinate.longitude];
    req.source = [[MKMapItem alloc] initWithLocation:sourceLoc address:nil];
    req.destination = [[MKMapItem alloc] initWithLocation:destLoc address:nil];
    req.transportType = (self.transportControl.selectedSegmentIndex == 0) ? MKDirectionsTransportTypeWalking : MKDirectionsTransportTypeAutomobile;
    MKDirections *dir = [[MKDirections alloc] initWithRequest:req];
    [dir calculateDirectionsWithCompletionHandler:^(MKDirectionsResponse *resp, NSError *err) {
        if (resp.routes.count > 0) {
            MKRoute *route = resp.routes.firstObject;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.currentRoutePolyline) [self.mapView removeOverlay:self.currentRoutePolyline];
                self.currentRoutePolyline = route.polyline;
                [self.mapView addOverlay:self.currentRoutePolyline];
            });
            NSUInteger count = route.polyline.pointCount;
            CLLocationCoordinate2D *coords = malloc(sizeof(CLLocationCoordinate2D) * count);
            [route.polyline getCoordinates:coords range:NSMakeRange(0, count)];

            NSMutableArray *interpolated = [NSMutableArray array];
            CLLocation *prevL = nil;
            for (NSUInteger i = 0; i < count; i++) {
                CLLocation *currL = [[CLLocation alloc] initWithLatitude:coords[i].latitude longitude:coords[i].longitude];
                if (prevL) { [self interpolateBetween:prevL and:currL into:interpolated]; }
                else { [interpolated addObject:currL]; }
                prevL = currL;
            }
            [self.currentPathPoints removeAllObjects];
            [self.currentPathPoints addObjectsFromArray:interpolated];
            free(coords);
            [self log:@"Route ready"];
            if (self.modeControl.selectedSegmentIndex == MoveModeRoadAuto && ![self.moveTimer isValid]) {
                dispatch_async(dispatch_get_main_queue(), ^{ [self startSimulation]; });
            }
        } else { [self log:@"Route failed"]; }
    }];
}

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay {
    if ([overlay isKindOfClass:[MKPolyline class]]) {
        MKPolylineRenderer *r = [[MKPolylineRenderer alloc] initWithPolyline:(MKPolyline *)overlay];
        r.strokeColor = [UIColor systemBlueColor]; r.lineWidth = 4; return r;
    }
    return nil;
}

- (void)onTick {
    if (self.currentPathIndex >= self.currentPathPoints.count) {
        [self.moveTimer invalidate];
        [self.actionButton setTitle:@"START" forState:UIControlStateNormal];
        [self log:@"Destination reached"];
        return;
    }
    CLLocation *loc = self.currentPathPoints[self.currentPathIndex];
    [self updateDeviceLocation:loc.coordinate];
    self.currentPathIndex++;
}

- (void)updateDeviceLocation:(CLLocationCoordinate2D)coord {
    self.currentSimulatedPos = coord;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        if (self.simHandleLegacy) {
            char lat[32], lon[32];
            snprintf(lat, 32, "%.8f", coord.latitude);
            snprintf(lon, 32, "%.8f", coord.longitude);
            struct IdeviceFfiError *err = lockdown_location_simulation_set(self.simHandleLegacy, lat, lon);
            if (err) { NSLog(@"[SimVC] Legacy set failed: %s", err->message); idevice_error_free(err); }
        }
        if (self.simHandle17) {
            struct IdeviceFfiError *err = location_simulation_set(self.simHandle17, coord.latitude, coord.longitude);
            if (err) { NSLog(@"[SimVC] 17 set failed: %s", err->message); idevice_error_free(err); }
        }
    });
}

#pragma mark - Favorites

- (void)showFavorites {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Favorites" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Add Current to Favs" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self addFavorite]; }]];
    for (NSDictionary *fav in self.favorites) {
        [sheet addAction:[UIAlertAction actionWithTitle:fav[@"name"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            CLLocationCoordinate2D c = CLLocationCoordinate2DMake([fav[@"lat"] doubleValue], [fav[@"lon"] doubleValue]);
            [self.mapView setCenterCoordinate:c animated:YES];
            [self addDestination:c];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)addFavorite {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"New Favorite" message:@"Enter name" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:nil];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields.firstObject.text ?: @"Point";
        [self.favorites addObject:@{@"name": name, @"lat": @(self.currentSimulatedPos.latitude), @"lon": @(self.currentSimulatedPos.longitude)}];
        [[NSUserDefaults standardUserDefaults] setObject:self.favorites forKey:@"SimFavorites"];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)dealloc {
    [self.moveTimer invalidate];
    if (self.simHandleLegacy) lockdown_location_simulation_free(self.simHandleLegacy);
    if (self.simHandle17) location_simulation_free(self.simHandle17);
    if (self.remoteServer) remote_server_free(self.remoteServer);
    if (self.handshake) rsd_handshake_free(self.handshake);
    if (self.adapter) adapter_free(self.adapter);
}

@end
