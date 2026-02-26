#import "AfcBrowserViewController.h"
#import "extend/JITEnableContext.h"
#import "FileManagerCore.h"
#import "ThemeEngine.h"

@interface AfcBrowserViewController ()
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) NSArray<FileItem *> *items;
@property (strong, nonatomic) UIActivityIndicatorView *spinner;

@implementation AfcBrowserViewController

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) { _currentPath = path ?: @"/"; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [@"AFC: " stringByAppendingString:self.currentPath];
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.center = self.view.center;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    [self reloadData];
}

- (void)reloadData {
    [self.spinner startAnimating];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NSArray *fetched = [[JITEnableContext shared] afcContentsOfDirectoryAtPath:self.currentPath error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            if (error) {
                [self showError:error];
            } else {
                self.items = fetched;
                [self.tableView reloadData];
            }
        });
    });
}

- (void)showError:(NSError *)error {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"AFC Error" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AfcCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"AfcCell"];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor lightGrayColor];
    }

    FileItem *item = self.items[indexPath.row];
    cell.textLabel.text = item.name;
    cell.imageView.image = [UIImage systemImageNamed:item.isDirectory ? @"folder.fill" : @"doc.fill"];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    FileItem *item = self.items[indexPath.row];
    if (item.isDirectory) {
        AfcBrowserViewController *next = [[AfcBrowserViewController alloc] initWithPath:item.fullPath];
        [self.navigationController pushViewController:next animated:YES];
    } else {
        // Maybe add push/pull functionality here
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:item.name message:@"AFC File" preferredStyle:UIAlertControllerStyleActionSheet];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

@end