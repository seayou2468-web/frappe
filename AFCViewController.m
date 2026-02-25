#import "AFCViewController.h"
#import "JITEnableContext.h"
#import "ThemeEngine.h"
#import "PathBarView.h"

@interface AFCViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, strong) PathBarView *pathBar;
@end

@implementation AFCViewController

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _currentPath = path ?: @"/";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"AFC Browser";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    [self setupUI];
    [self reloadData];
}

- (void)setupUI {
    self.pathBar = [[PathBarView alloc] initWithFrame:CGRectZero];
    self.pathBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pathBar updatePath:self.currentPath];
    [self.view addSubview:self.pathBar];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.view addSubview:self.tableView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.pathBar.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
        [self.pathBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.pathBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [self.pathBar.heightAnchor constraintEqualToConstant:44],

        [self.tableView.topAnchor constraintEqualToAnchor:self.pathBar.bottomAnchor constant:10],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)reloadData {
    NSError *error = nil;
    self.items = [[JITEnableContext shared] afcListDir:self.currentPath error:&error];
    if (error) {
        NSLog(@"AFC error: %@", error);
    }
    [self.tableView reloadData];
    [self.pathBar updatePath:self.currentPath];
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"AFCCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
    }

    NSString *name = self.items[indexPath.row];
    cell.textLabel.text = name;

    NSString *full = [self.currentPath stringByAppendingPathComponent:name];
    if ([[JITEnableContext shared] afcIsPathDirectory:full]) {
        cell.imageView.image = [UIImage systemImageNamed:@"folder.fill"];
        cell.imageView.tintColor = [UIColor systemYellowColor];
    } else {
        cell.imageView.image = [UIImage systemImageNamed:@"doc.fill"];
        cell.imageView.tintColor = [UIColor systemBlueColor];
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *name = self.items[indexPath.row];
    NSString *full = [self.currentPath stringByAppendingPathComponent:name];

    if ([[JITEnableContext shared] afcIsPathDirectory:full]) {
        AFCViewController *vc = [[AFCViewController alloc] initWithPath:full];
        [self.navigationController pushViewController:vc animated:YES];
    } else {
        // Handle file (Download, etc.)
    }
}

@end
