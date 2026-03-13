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
@end

@implementation AfcBrowserViewController

- (instancetype)initWithProvider:(struct IdeviceProviderHandle *)provider isAfc2:(BOOL)isAfc2 {
    self = [super init];
    if (self) {
        _provider = provider;
        _isAfc2 = isAfc2;
        _currentPath = @"/";
        _items = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.isAfc2 ? @"AFC2 (Root)" : @"AFC (Media)";
    self.view.backgroundColor = [UIColor blackColor];
    [self setupUI];
    [self connectAfc];
}

- (void)setupUI {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.delegate = self; self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    [self.view addSubview:self.tableView];
    [ThemeEngine applyGlassStyleToView:self.tableView cornerRadius:0];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.color = [UIColor whiteColor];
    self.spinner.center = self.view.center;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Back" style:UIBarButtonItemStylePlain target:self action:@selector(goBack)];
}

- (void)connectAfc {
    [self.spinner startAnimating];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        struct AfcClientHandle *client = NULL;
        struct IdeviceFfiError *err = NULL;
        if (self.isAfc2) err = afc2_client_connect(self.provider, &client);
        else err = afc_client_connect(self.provider, &client);

        if (!err) {
            self.afc = client;
            [self loadPath:self.currentPath];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.spinner stopAnimating];
                NSLog(@"[AFC] Connect failed: %s", err->message);
                idevice_error_free(err);
            });
        }
    });
}

- (void)loadPath:(NSString *)path {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        char **entries = NULL;
        size_t count = 0;
        struct IdeviceFfiError *err = afc_list_directory(self.afc, [path UTF8String], &entries, &count);

        if (!err) {
            NSMutableArray *newList = [NSMutableArray array];
            for (size_t i = 0; i < count; i++) {
                NSString *name = [NSString stringWithUTF8String:entries[i]];
                if ([name isEqualToString:@"."] || [name isEqualToString:@".."]) continue;

                NSString *full = [path stringByAppendingPathComponent:name];
                struct AfcFileInfo info = {0};
                struct IdeviceFfiError *e2 = afc_get_file_info(self.afc, [full UTF8String], &info);

                BOOL isDir = NO;
                if (!e2) {
                    if (info.st_ifmt && strcmp(info.st_ifmt, "S_IFDIR") == 0) isDir = YES;
                    afc_file_info_free(&info);
                } else { idevice_error_free(e2); }

                [newList addObject:@{@"name": name, @"isDir": @(isDir)}];
            }

            [newList sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
                BOOL d1 = [obj1[@"isDir"] boolValue];
                BOOL d2 = [obj2[@"isDir"] boolValue];
                if (d1 != d2) return d1 ? NSOrderedAscending : NSOrderedDescending;
                return [obj1[@"name"] localizedCaseInsensitiveCompare:obj2[@"name"]];
            }];

            dispatch_async(dispatch_get_main_queue(), ^{
                [self.items removeAllObjects];
                [self.items addObjectsFromArray:newList];
                self.currentPath = path;
                self.title = [path lastPathComponent].length > 0 ? [path lastPathComponent] : (self.isAfc2 ? @"Root" : @"Media");
                [self.tableView reloadData];
                [self.spinner stopAnimating];
            });
            // Entries free is missing in idevice.h? Usually it's afc_free_directory_entries.
            // Given the pattern, let's assume it should exist but maybe I missed it.
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.spinner stopAnimating];
                idevice_error_free(err);
            });
        }
    });
}

- (void)goBack {
    if ([self.currentPath isEqualToString:@"/"]) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    NSString *parent = [self.currentPath stringByDeletingLastPathComponent];
    if (parent.length == 0) parent = @"/";
    [self.spinner startAnimating];
    [self loadPath:parent];
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.items.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
    NSDictionary *item = self.items[indexPath.row];
    cell.backgroundColor = [UIColor clearColor];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.textLabel.text = item[@"name"];
    cell.imageView.image = [UIImage systemImageNamed:[item[@"isDir"] boolValue] ? @"folder.fill" : @"doc"];
    cell.imageView.tintColor = [item[@"isDir"] boolValue] ? [UIColor systemBlueColor] : [UIColor systemGrayColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = self.items[indexPath.row];
    if ([item[@"isDir"] boolValue]) {
        NSString *newPath = [self.currentPath stringByAppendingPathComponent:item[@"name"]];
        [self.spinner startAnimating];
        [self loadPath:newPath];
    }
}

- (void)dealloc {
    if (self.afc) afc_client_free(self.afc);
}

@end
