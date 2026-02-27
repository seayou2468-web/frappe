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
    [self setupUI];
}

- (void)setupUI {
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    self.searchBar.barStyle = UIBarStyleBlack;
    self.searchBar.placeholder = @"Search Hex or String";
    self.searchBar.delegate = self;
    [self.view addSubview:self.searchBar];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 44, self.view.bounds.size.width, self.view.bounds.size.height - 44) style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.view addSubview:self.tableView];

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
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.numberOfLines = 0;
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
        NSMutableString *line = [NSMutableString string];
        [line appendFormat:@"%08lX: ", (unsigned long)offset];

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
        cell.textLabel.text = [NSString stringWithFormat:@"%@ | %@", hexPart, asciiPart];

        // Use a fixed width for hex part to ensure alignment
        // (Simplified for this context, in a real app would use attributed string or separate labels)
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
