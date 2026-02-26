#import "SettingsViewController.h"
#import "ThemeEngine.h"

@interface SettingsViewController () <UITableViewDelegate, UITableViewDataSource>
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) NSArray *sections;

@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    self.sections = @[
        @{@"title": @"Connection", @"items": @[@"Custom Target IP"]},
        @{@"title": @"Browser", @"items": @[@"Default Start Path", @"Show Hidden Files"]},
        @{@"title": @"About", @"items": @[@"Version 1.0 (Liquidglass)"]}
    ];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self.sections[section][@"items"] count]; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return self.sections[section][@"title"]; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"SettingsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellID];
        cell.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.05];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
    }
    NSString *item = self.sections[indexPath.section][@"items"][indexPath.row];
    cell.textLabel.text = item;

    if ([item isEqualToString:@"Custom Target IP"]) {
        cell.detailTextLabel.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"customTargetIP"] ?: @"10.7.0.1";
    } else if ([item isEqualToString:@"Default Start Path"]) {
        cell.detailTextLabel.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"defaultStartPath"] ?: @"/";
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *item = self.sections[indexPath.section][@"items"][indexPath.row];

    if ([item isEqualToString:@"Custom Target IP"]) {
        [self promptForSetting:@"Custom Target IP" key:@"customTargetIP"];
    } else if ([item isEqualToString:@"Default Start Path"]) {
        [self promptForSetting:@"Default Start Path" key:@"defaultStartPath"];
    }
}

- (void)promptForSetting:(NSString *)title key:(NSString *)key {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = [[NSUserDefaults standardUserDefaults] stringForKey:key];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[NSUserDefaults standardUserDefaults] setObject:alert.textFields[0].text forKey:key];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end