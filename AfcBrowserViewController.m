#import "AfcBrowserViewController.h"
#import "ThemeEngine.h"

@interface AfcBrowserViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, assign) struct IdeviceProviderHandle *provider;
@property (nonatomic, assign) struct AfcClientHandle *afc;
@property (nonatomic, assign) BOOL isAfc2;
@property (nonatomic, strong) NSString *currentPath;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *items;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *pathLabel;
@property (nonatomic, strong) UIView *headerView;
@end

@implementation AfcBrowserViewController

- (instancetype)initWithProvider:(struct IdeviceProviderHandle *)provider isAfc2:(BOOL)isAfc2 {
    self = [super init];
    if (self) {
        _provider = provider;
        _isAfc2 = isAfc2;
        _currentPath = @"/";
        _items = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.isAfc2 ? @"Root" : @"Media";
    self.view.backgroundColor = [UIColor blackColor];
    [self setupUI];
    [self connectAfc];
}

- (void)setupUI {
    self.headerView = [[UIView alloc] initWithFrame:CGRectZero];
    self.headerView.translatesAutoresizingMaskIntoConstraints = NO;
    [ThemeEngine applyGlassStyleToView:self.headerView cornerRadius:0];
    [self.view addSubview:self.headerView];

    self.pathLabel = [[UILabel alloc] init];
    self.pathLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.pathLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.7];
    self.pathLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    self.pathLabel.text = self.currentPath;
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
        [self.headerView.heightAnchor constraintEqualToConstant:30],

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
}

- (void)connectAfc {
    [self showLoading:YES];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        struct AfcClientHandle *client = NULL;
        struct IdeviceFfiError *err = self.isAfc2 ? afc2_client_connect(self.provider, &client) : afc_client_connect(self.provider, &client);

        if (!err) {
            self.afc = client;
            [self loadPath:self.currentPath];
        } else {
            [self handleError:err];
        }
    });
}

- (void)showLoading:(BOOL)loading {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (loading) [self.spinner startAnimating];
        else [self.spinner stopAnimating];
    });
}

- (void)handleError:(struct IdeviceFfiError *)err {
    NSString *msg = [NSString stringWithUTF8String:err->message];
    NSLog(@"[AFC] Error: %@", msg);
    idevice_error_free(err);
    [self showLoading:NO];
}

- (void)loadPath:(NSString *)path {
    [self showLoading:YES];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        char **entries = NULL;
        size_t count = 0;
        struct IdeviceFfiError *err = afc_list_directory(self.afc, [path UTF8String], &entries, &count);

        if (!err) {
            NSMutableArray *newList = [NSMutableArray array];
            for (size_t i = 0; i < count; i++) {
                NSString *name = [NSString stringWithUTF8String:entries[i]];
                if ([name isEqualToString:@"."] || [name isEqualToString:@".."]) continue;

                NSString *full;
                if ([path isEqualToString:@"/"]) full = [@"/" stringByAppendingString:name];
                else full = [path stringByAppendingPathComponent:name];

                struct AfcFileInfo info = {0};
                struct IdeviceFfiError *e2 = afc_get_file_info(self.afc, [full UTF8String], &info);

                BOOL isDir = NO;
                if (!e2) {
                    if (info.st_ifmt && (strcmp(info.st_ifmt, "S_IFDIR") == 0 || strcmp(info.st_ifmt, "directory") == 0)) isDir = YES;
                    afc_file_info_free(&info);
                } else {
                    idevice_error_free(e2);
                    if (![name containsString:@"."]) isDir = YES;
                }
                [newList addObject:@{@"name": name, @"isDir": @(isDir)}];
            }

            [newList sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
                BOOL d1 = [obj1[@"isDir"] boolValue];
                BOOL d2 = [obj2[@"isDir"] boolValue];
                if (d1 != d2) return d1 ? NSOrderedAscending : NSOrderedDescending;
                return [obj1[@"name"] localizedCaseInsensitiveCompare:obj2[@"name"]];
            }];

            dispatch_async(dispatch_get_main_queue(), ^{
                self.items = newList;
                self.currentPath = path;
                self.pathLabel.text = path;
                [self.tableView reloadData];
                [self.spinner stopAnimating];
            });
        } else {
            [self handleError:err];
        }
    });
}

- (void)goBack {
    if ([self.currentPath isEqualToString:@"/"]) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    NSString *parent = [self.currentPath stringByDeletingLastPathComponent];
    if (parent.length == 0 || [parent isEqualToString:@"."]) parent = @"/";
    [self loadPath:parent];
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.items.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
    NSDictionary *item = self.items[indexPath.row];
    cell.backgroundColor = [UIColor clearColor];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.textLabel.font = [UIFont systemFontOfSize:15];
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
        NSString *newPath;
        if ([self.currentPath isEqualToString:@"/"]) newPath = [@"/" stringByAppendingString:name];
        else newPath = [self.currentPath stringByAppendingPathComponent:name];
        [self loadPath:newPath];
    }
}

- (void)dealloc {
    if (self.afc) afc_client_free(self.afc);
}

@end
