#import "IdeviceAppDetailViewController.h"
#import "ThemeEngine.h"
#import "IdeviceManager.h"

@interface IdeviceAppDetailViewController () <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) id data;
@property (nonatomic, strong) NSArray *displayKeys;
@property (nonatomic, strong) NSArray *displayData;
@property (nonatomic, assign) BOOL isDictionary;
@property (nonatomic, strong) UITextField *argsField;
@property (nonatomic, strong) UITextField *envField;
@property (nonatomic, strong) UISwitch *jitSwitch;
@end

@implementation IdeviceAppDetailViewController

- (instancetype)initWithData:(id)data title:(NSString *)title {
    self = [super init];
    if (self) {
        _data = data; self.title = title;
        if ([data isKindOfClass:[NSDictionary class]]) { _isDictionary = YES; _displayKeys = [[((NSDictionary *)data) allKeys] sortedArrayUsingSelector:@selector(compare:)]; }
        else if ([data isKindOfClass:[NSArray class]]) { _isDictionary = NO; _displayData = (NSArray *)data; }
    }
    return self;
}

- (void)viewDidLoad { [super viewDidLoad]; self.view.backgroundColor = [ThemeEngine mainBackgroundColor]; [self setupUI]; }

- (void)setupUI {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.backgroundColor = [UIColor clearColor]; self.tableView.delegate = self; self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    if (self.isDictionary && self.data[@"CFBundleIdentifier"]) {
        UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 280)];
        UILabel *argsL = [[UILabel alloc] initWithFrame:CGRectMake(25, 10, 200, 20)]; argsL.text = @"起動引数 (スペース区切り)"; argsL.textColor = [UIColor lightGrayColor]; argsL.font = [UIFont systemFontOfSize:12]; [footer addSubview:argsL];
        self.argsField = [[UITextField alloc] initWithFrame:CGRectMake(20, 35, footer.frame.size.width - 40, 40)]; self.argsField.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1]; self.argsField.layer.cornerRadius = 8; self.argsField.textColor = [UIColor whiteColor]; self.argsField.font = [UIFont systemFontOfSize:14]; self.argsField.placeholder = @" e.g. --debug"; self.argsField.delegate = self; [footer addSubview:self.argsField];
        UILabel *envL = [[UILabel alloc] initWithFrame:CGRectMake(25, 85, 200, 20)]; envL.text = @"環境変数 (KEY=VALUE, 改行区切り)"; envL.textColor = [UIColor lightGrayColor]; envL.font = [UIFont systemFontOfSize:12]; [footer addSubview:envL];
        self.envField = [[UITextField alloc] initWithFrame:CGRectMake(20, 110, footer.frame.size.width - 40, 40)]; self.envField.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1]; self.envField.layer.cornerRadius = 8; self.envField.textColor = [UIColor whiteColor]; self.envField.font = [UIFont systemFontOfSize:14]; self.envField.placeholder = @" e.g. OS_ACTIVITY_MODE=disable"; self.envField.delegate = self; [footer addSubview:self.envField];
        UILabel *jitL = [[UILabel alloc] initWithFrame:CGRectMake(25, 165, 100, 31)]; jitL.text = @"JIT起動有効化"; jitL.textColor = [UIColor whiteColor]; jitL.font = [UIFont systemFontOfSize:14]; [footer addSubview:jitL];
        self.jitSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(footer.frame.size.width - 71, 165, 51, 31)]; self.jitSwitch.onTintColor = [ThemeEngine liquidColor]; [footer addSubview:self.jitSwitch];
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem]; btn.frame = CGRectMake(20, 210, footer.frame.size.width - 40, 50); [ThemeEngine applyGlassStyleToView:btn cornerRadius:12]; [btn setTitle:@"アプリを起動" forState:UIControlStateNormal]; [btn setTitleColor:[ThemeEngine liquidColor] forState:UIControlStateNormal]; [btn addTarget:self action:@selector(launchApp) forControlEvents:UIControlEventTouchUpInside]; [footer addSubview:btn];
        self.tableView.tableFooterView = footer;
    }
}

- (void)launchApp {
    NSString *bid = self.isDictionary ? self.data[@"CFBundleIdentifier"] : nil; if (!bid) return;
    NSArray *args = (self.argsField.text.length > 0) ? [self.argsField.text componentsSeparatedByString:@" "] : nil;
    NSMutableDictionary *env = nil; if (self.envField.text.length > 0) { env = [NSMutableDictionary dictionary]; NSArray *ls = [self.envField.text componentsSeparatedByString:@"\n"]; for (NSString *l in ls) { NSArray *p = [l componentsSeparatedByString:@"="]; if (p.count >= 2) env[p[0]] = p[1]; } }
    [[IdeviceManager sharedManager] launchAppWithBundleId:bid arguments:args environment:env useJIT:self.jitSwitch.on completion:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *t = error ? @"起動エラー" : @"成功"; NSString *m = error ? error.localizedDescription : @"起動要求を送信しました";
            UIAlertController *a = [UIAlertController alertControllerWithTitle:t message:m preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:a animated:YES completion:nil];
        });
    }];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.isDictionary ? self.displayKeys.count : self.displayData.count; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"DetailCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"DetailCell"];
    c.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.05]; c.textLabel.textColor = [ThemeEngine liquidColor]; c.detailTextLabel.textColor = [UIColor whiteColor]; c.detailTextLabel.numberOfLines = 0;
    id v = self.isDictionary ? self.data[self.displayKeys[ip.row]] : self.displayData[ip.row];
    c.textLabel.text = self.isDictionary ? [self localizedKey:self.displayKeys[ip.row]] : [NSString stringWithFormat:@"項目 %ld", (long)ip.row];
    if ([v isKindOfClass:[NSDictionary class]]) { c.detailTextLabel.text = @"[辞書データ...]"; c.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
    else if ([v isKindOfClass:[NSArray class]]) { c.detailTextLabel.text = [NSString stringWithFormat:@"[配列データ: %ld件]", (long)((NSArray *)v).count]; c.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
    else { c.detailTextLabel.text = (v && v != [NSNull null]) ? [NSString stringWithFormat:@"%@", v] : @"(空)"; c.accessoryType = UITableViewCellAccessoryNone; }
    return c;
}

- (NSString *)localizedKey:(NSString *)k {
    static NSDictionary *m = nil; if (!m) m = @{@"CFBundleDisplayName":@"表示名",@"CFBundleName":@"アプリ名",@"CFBundleIdentifier":@"識別子 (Bundle ID)",@"CFBundleShortVersionString":@"バージョン",@"CFBundleVersion":@"ビルド番号",@"Path":@"インストールパス",@"Container":@"コンテナパス",@"DataContainer":@"データパス",@"ApplicationType":@"アプリ種類",@"Entitlements":@"エンタイトルメント",@"EnvironmentVariables":@"環境変数",@"MinimumOSVersion":@"最小OSバージョン",@"UIDeviceFamily":@"対応デバイス",@"UIRequiredDeviceCapabilities":@"必要機能"};
    return m[k] ?: k;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES]; id v = self.isDictionary ? self.data[self.displayKeys[ip.row]] : self.displayData[ip.row];
    if ([v isKindOfClass:[NSDictionary class]] || [v isKindOfClass:[NSArray class]]) { [self.navigationController pushViewController:[[IdeviceAppDetailViewController alloc] initWithData:v title:self.isDictionary ? self.displayKeys[ip.row] : [NSString stringWithFormat:@"項目 %ld", (long)ip.row]] animated:YES]; }
}
@end
