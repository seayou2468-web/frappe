#import "CookieEditorViewController.h"
#import "ThemeEngine.h"

@interface CookieEditorViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<NSHTTPCookie *> *cookies;
@end

@implementation CookieEditorViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Cookies";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];

    UIBarButtonItem *addBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addCookie)];
    UIBarButtonItem *exportBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"] style:UIBarButtonItemStylePlain target:self action:@selector(exportCookies)];
    UIBarButtonItem *importBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.down"] style:UIBarButtonItemStylePlain target:self action:@selector(importCookies)];
    self.navigationItem.rightBarButtonItems = @[addBtn, exportBtn, importBtn];

    [self loadCookies];
}

- (void)loadCookies {
    [self.cookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.cookies = [cookies mutableCopy];
            [self.tableView reloadData];
        });
    }];
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.cookies.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
        cell.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.05];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
    }
    NSHTTPCookie *cookie = self.cookies[indexPath.row];
    cell.textLabel.text = cookie.name;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ = %@", cookie.domain, cookie.value];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSHTTPCookie *cookie = self.cookies[indexPath.row];
    [self editCookie:cookie];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSHTTPCookie *cookie = self.cookies[indexPath.row];
        [self.cookieStore deleteCookie:cookie completionHandler:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.cookies removeObjectAtIndex:indexPath.row];
                [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
            });
        }];
    }
}

#pragma mark - Cookie Actions

- (void)addCookie {
    [self showCookieForm:nil];
}

- (void)editCookie:(NSHTTPCookie *)cookie {
    [self showCookieForm:cookie];
}

- (void)showCookieForm:(NSHTTPCookie *)cookie {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:cookie ? @"Edit Cookie" : @"Add Cookie" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"Name"; tf.text = cookie.name; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"Value"; tf.text = cookie.value; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"Domain"; tf.text = cookie.domain; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"Path"; tf.text = cookie.path ?: @"/"; }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSMutableDictionary *props = [NSMutableDictionary dictionary];
        props[NSHTTPCookieName] = alert.textFields[0].text;
        props[NSHTTPCookieValue] = alert.textFields[1].text;
        props[NSHTTPCookieDomain] = alert.textFields[2].text;
        props[NSHTTPCookiePath] = alert.textFields[3].text;

        NSHTTPCookie *newCookie = [NSHTTPCookie cookieWithProperties:props];
        if (newCookie) {
            [self.cookieStore setCookie:newCookie completionHandler:^{ [self loadCookies]; }];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)exportCookies {
    NSMutableArray *exportArr = [NSMutableArray array];
    for (NSHTTPCookie *cookie in self.cookies) {
        [exportArr addObject:cookie.properties];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:exportArr options:NSJSONWritingPrettyPrinted error:nil];
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[json] applicationActivities:nil];
    [self presentViewController:avc animated:YES completion:nil];
}

- (void)importCookies {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import Cookies" message:@"Paste JSON cookie properties array" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:nil];
    [alert addAction:[UIAlertAction actionWithTitle:@"Import" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *json = alert.textFields[0].text;
        NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
        NSArray *arr = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([arr isKindOfClass:[NSArray class]]) {
            for (NSDictionary *props in arr) {
                NSHTTPCookie *c = [NSHTTPCookie cookieWithProperties:props];
                if (c) [self.cookieStore setCookie:c completionHandler:nil];
            }
            [self loadCookies];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
