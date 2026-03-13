#import "AfcBrowserViewController.h"
#import "ThemeEngine.h"

@interface AfcBrowserViewController () <UITableViewDelegate, UITableViewDataSource, UIGestureRecognizerDelegate>
@property (nonatomic, assign) struct IdeviceProviderHandle *provider;
@property (nonatomic, assign) struct AfcClientHandle *afc;
@property (nonatomic, assign) BOOL isAfc2;
@property (nonatomic, strong) NSString *currentPath;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *items;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIScreenEdgePanGestureRecognizer *customSwipeGesture;
@property (nonatomic, strong) UILabel *pathLabel;
@property (nonatomic, strong) UIView *headerView;
@end

@implementation AfcBrowserViewController

- (instancetype)initWithProvider:(struct IdeviceProviderHandle *)provider isAfc2:(BOOL)isAfc2 {
    self = [super init];
    if (self) {
        _provider = provider; _isAfc2 = isAfc2;
        _currentPath = @"/"; _items = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.isAfc2 ? @"System Root" : @"Media Staging";
    self.view.backgroundColor = [UIColor blackColor];
    [self setupUI];
    [self connectAfc];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self updatePopGestureState];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // Always restore system pop gesture when leaving
    if (self.navigationController.interactivePopGestureRecognizer) {
        self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    }
}

- (void)updatePopGestureState {
    BOOL isAtRoot = [self.currentPath isEqualToString:@"/"];
    if (self.navigationController.interactivePopGestureRecognizer) {
        // Disable system back-pop gesture when deep in folders so our custom one can work
        self.navigationController.interactivePopGestureRecognizer.enabled = isAtRoot;
    }
}

- (void)setupUI {
    self.headerView = [[UIView alloc] init];
    self.headerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.headerView];
    [ThemeEngine applyGlassStyleToView:self.headerView cornerRadius:0];

    self.pathLabel = [[UILabel alloc] init];
    self.pathLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.pathLabel.textColor = [UIColor systemBlueColor];
    self.pathLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBlack];
    self.pathLabel.text = @"/";
    self.pathLabel.lineBreakMode = NSLineBreakByTruncatingHead;
    [self.headerView addSubview:self.pathLabel];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self; self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    [self.view addSubview:self.tableView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.color = [UIColor whiteColor];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Parent" style:UIBarButtonItemStylePlain target:self action:@selector(goBack)];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.headerView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.headerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.headerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.headerView.heightAnchor constraintEqualToConstant:44],

        [self.pathLabel.leadingAnchor constraintEqualToAnchor:self.headerView.leadingAnchor constant:15],
        [self.pathLabel.trailingAnchor constraintEqualToAnchor:self.headerView.trailingAnchor constant:-15],
        [self.pathLabel.centerYAnchor constraintEqualToAnchor:self.headerView.centerYAnchor],

        [self.tableView.topAnchor constraintEqualToAnchor:self.headerView.bottomAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];

    self.customSwipeGesture = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeBack:)];
    self.customSwipeGesture.edges = UIRectEdgeLeft; self.customSwipeGesture.delegate = self;
    [self.view addGestureRecognizer:self.customSwipeGesture];
}

- (void)connectAfc {
    dispatch_async(dispatch_get_main_queue(), ^{ [self.spinner startAnimating]; });
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        struct AfcClientHandle *client = NULL;
        struct IdeviceFfiError *err = self.isAfc2 ? afc2_client_connect(self.provider, &client) : afc_client_connect(self.provider, &client);
        if (!err) {
            self.afc = client;
            [self loadPath:@"/"];
        } else {
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ [self.spinner stopAnimating]; });
        }
    });
}

- (void)loadPath:(NSString *)path {
    dispatch_async(dispatch_get_main_queue(), ^{ [self.spinner startAnimating]; });
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        char **entries = NULL; size_t count = 0;
        struct IdeviceFfiError *err = afc_list_directory(self.afc, [path UTF8String], &entries, &count);
        if (!err) {
            NSMutableArray *newList = [NSMutableArray array];
            for (size_t i = 0; i < count; i++) {
                NSString *name = [NSString stringWithUTF8String:entries[i]];
                if ([name isEqualToString:@"."] || [name isEqualToString:@".."]) continue;

                NSString *full = [path isEqualToString:@"/"] ? [@"/" stringByAppendingString:name] : [path stringByAppendingPathComponent:name];
                struct AfcFileInfo info = {0};
                struct IdeviceFfiError *e2 = afc_get_file_info(self.afc, [full UTF8String], &info);

                BOOL isDir = NO;
                if (!e2) {
                    if (info.st_ifmt && (strstr(info.st_ifmt, "DIR") || strstr(info.st_ifmt, "directory"))) isDir = YES;
                    afc_file_info_free(&info);
                } else { idevice_error_free(e2); if (![name containsString:@"."]) isDir = YES; }
                [newList addObject:@{@"name": name, @"isDir": @(isDir)}];
            }
            [newList sortUsingComparator:^NSComparisonResult(id o1, id o2) {
                if ([o1[@"isDir"] boolValue] != [o2[@"isDir"] boolValue]) return [o1[@"isDir"] boolValue] ? NSOrderedAscending : NSOrderedDescending;
                return [o1[@"name"] localizedCaseInsensitiveCompare:o2[@"name"]];
            }];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.items removeAllObjects]; [self.items addObjectsFromArray:newList];
                self.currentPath = path; self.pathLabel.text = path;
                [self.tableView reloadData]; [self.spinner stopAnimating];
                [self updatePopGestureState];
            });
        } else {
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ [self.spinner stopAnimating]; });
        }
    });
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.customSwipeGesture) {
        return ![self.currentPath isEqualToString:@"/"];
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ([gestureRecognizer isKindOfClass:[UIScreenEdgePanGestureRecognizer class]] &&
        [otherGestureRecognizer isKindOfClass:[UIScreenEdgePanGestureRecognizer class]]) {
        return YES;
    }
    return NO;
}

- (void)handleSwipeBack:(UIScreenEdgePanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [gen impactOccurred];
        [self goBack];
    }
}

- (void)goBack {
    if ([self.currentPath isEqualToString:@"/"]) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    NSString *parent = [self.currentPath stringByDeletingLastPathComponent];
    if (parent.length == 0 || [parent isEqualToString:@"."]) parent = @"/";

    // Add a simple transition effect for "folder back" if desired,
    // but just loading the path is standard for this app.
    [self loadPath:parent];
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.items.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
    NSDictionary *item = self.items[indexPath.row];
    cell.backgroundColor = [UIColor clearColor]; cell.textLabel.textColor = [UIColor whiteColor];
    cell.textLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    cell.textLabel.text = item[@"name"];
    BOOL isDir = [item[@"isDir"] boolValue];
    cell.imageView.image = [UIImage systemImageNamed:isDir ? @"folder.fill" : @"doc"];
    cell.imageView.tintColor = isDir ? [UIColor systemBlueColor] : [UIColor systemGrayColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = self.items[indexPath.row];
    if ([item[@"isDir"] boolValue]) {
        NSString *name = item[@"name"];
        NSString *newPath = [self.currentPath isEqualToString:@"/"] ? [@"/" stringByAppendingString:name] : [self.currentPath stringByAppendingPathComponent:name];
        [self loadPath:newPath];
    }
}

- (void)dealloc { if (self.afc) afc_client_free(self.afc); }

@end
