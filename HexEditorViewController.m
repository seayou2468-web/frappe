#import "HexEditorViewController.h"
#import "ThemeEngine.h"

@interface HexEditorViewController () <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate>
@property (strong, nonatomic) NSString *path;
@property (strong, nonatomic) NSData *data;
@property (strong, nonatomic) NSMutableData *mutableData;
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) UISearchBar *searchBar;
@property (assign, nonatomic) BOOL showASCIIOnly;
@end

@implementation HexEditorViewController

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _path = path;
        _data = [NSData dataWithContentsOfFile:path];
        _mutableData = [_data mutableCopy];
        _showASCIIOnly = NO;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
    self.title = [self.path lastPathComponent];

    // Ensure navigation bar is correctly configured
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationController.navigationBar.translucent = YES;

    [self setupUI];
}

- (void)setupUI {
    // UI Layout with Auto Layout to prevent overlapping
    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.barStyle = UIBarStyleBlack;
    self.searchBar.placeholder = @"Search Hex or String";
    self.searchBar.delegate = self;
    self.searchBar.backgroundImage = [[UIImage alloc] init]; // Remove shadow/background
    self.searchBar.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.searchBar];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.view addSubview:self.tableView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;

    [NSLayoutConstraint activateConstraints:@[
        [self.searchBar.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.searchBar.heightAnchor constraintEqualToConstant:50],

        [self.tableView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    UIBarButtonItem *saveBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(saveChanges)];
    UIBarButtonItem *toggleBtn = [[UIBarButtonItem alloc] initWithTitle:@"A/H" style:UIBarButtonItemStylePlain target:self action:@selector(toggleMode)];
    self.navigationItem.rightBarButtonItems = @[saveBtn, toggleBtn];
}

- (void)toggleMode {
    self.showASCIIOnly = !self.showASCIIOnly;
    [self.tableView reloadData];
}

- (void)saveChanges {
    if ([_mutableData writeToFile:self.path atomically:YES]) {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSUInteger bytesPerRow = self.showASCIIOnly ? 32 : 16;
    return (_mutableData.length + (bytesPerRow - 1)) / bytesPerRow;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"HexCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.font = [UIFont fontWithName:@"Menlo" size:11];
        cell.textLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.9];
        cell.textLabel.numberOfLines = 0;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    NSUInteger bytesPerRow = self.showASCIIOnly ? 32 : 16;
    NSUInteger offset = indexPath.row * bytesPerRow;
    NSUInteger length = MIN(bytesPerRow, _mutableData.length - offset);
    const unsigned char *bytes = (const unsigned char *)[_mutableData bytes] + offset;

    if (self.showASCIIOnly) {
        NSMutableString *asciiPart = [NSMutableString string];
        [asciiPart appendFormat:@"%08lX: ", (unsigned long)offset];
        for (NSUInteger i = 0; i < length; i++) {
            unsigned char b = bytes[i];
            if (b >= 32 && b <= 126) [asciiPart appendFormat:@"%c", b];
            else [asciiPart appendString:@"."];
        }
        cell.textLabel.text = asciiPart;
    } else {
        NSMutableString *hexPart = [NSMutableString string];
        NSMutableString *asciiPart = [NSMutableString string];

        for (NSUInteger i = 0; i < 16; i++) {
            if (i < length) {
                unsigned char b = bytes[i];
                [hexPart appendFormat:@"%02X ", b];
                if (b >= 32 && b <= 126) [asciiPart appendFormat:@"%c", b];
                else [asciiPart appendString:@"."];
            } else {
                [hexPart appendString:@"   "];
            }
        }
        cell.textLabel.text = [NSString stringWithFormat:@"%08lX: %@| %@", (unsigned long)offset, hexPart, asciiPart];
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self editByteAtRow:indexPath.row];
}

- (void)editByteAtRow:(NSInteger)row {
    NSUInteger bytesPerRow = self.showASCIIOnly ? 32 : 16;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Edit Bytes" message:@"Enter hex string (e.g. 41 42 43)" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        NSUInteger offset = row * bytesPerRow;
        NSUInteger length = MIN(bytesPerRow, self.mutableData.length - offset);
        const unsigned char *bytes = (const unsigned char *)[self.mutableData bytes] + offset;
        NSMutableString *hex = [NSMutableString string];
        for (NSUInteger i = 0; i < length; i++) [hex appendFormat:@"%02X ", bytes[i]];
        tf.text = hex;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Apply" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *hexText = alert.textFields[0].text;
        NSArray *parts = [hexText componentsSeparatedByString:@" "];
        unsigned char *bytes = (unsigned char *)[self.mutableData mutableBytes] + (row * bytesPerRow);
        NSUInteger offset = 0;
        for (NSString *p in parts) {
            if (p.length == 0) continue;
            unsigned int b;
            NSScanner *scanner = [NSScanner scannerWithString:p];
            [scanner scanHexInt:&b];
            if (row * bytesPerRow + offset < self.mutableData.length) {
                bytes[offset] = (unsigned char)b;
                offset++;
            }
        }
        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Search

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    NSString *query = searchBar.text;
    if (query.length == 0) return;

    NSData *searchData = nil;
    if ([query hasPrefix:@"0x"]) {
        NSMutableData *md = [NSMutableData data];
        NSString *hex = [query substringFromIndex:2];
        for (int i = 0; i < (int)hex.length; i+=2) {
            unsigned int b;
            if (i+2 <= hex.length) {
                [[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i, 2)]] scanHexInt:&b];
                unsigned char bc = (unsigned char)b;
                [md appendBytes:&bc length:1];
            }
        }
        searchData = md;
    } else {
        searchData = [query dataUsingEncoding:NSUTF8StringEncoding];
    }

    if (searchData) {
        NSRange range = [_mutableData rangeOfData:searchData options:0 range:NSMakeRange(0, _mutableData.length)];
        if (range.location != NSNotFound) {
            NSUInteger bytesPerRow = self.showASCIIOnly ? 32 : 16;
            NSInteger row = range.location / bytesPerRow;
            [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
        }
    }
}

@end
