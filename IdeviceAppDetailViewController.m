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
        _data = data;
        self.title = title;
        if ([data isKindOfClass:[NSDictionary class]]) {
            _isDictionary = YES;
            _displayKeys = [[((NSDictionary *)data) allKeys] sortedArrayUsingSelector:@selector(compare:)];
        } else if ([data isKindOfClass:[NSArray class]]) {
            _isDictionary = NO;
            _displayData = (NSArray *)data;
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
    [self setupUI];
}

- (void)setupUI {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    if (self.isDictionary && self.data[@"CFBundleIdentifier"]) {
        UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 280)];

        UILabel *argsLabel = [[UILabel alloc] initWithFrame:CGRectMake(25, 10, 200, 20)];
        argsLabel.text = @"起動引数 (スペース区切り)";
        argsLabel.textColor = [UIColor lightGrayColor];
        argsLabel.font = [UIFont systemFontOfSize:12];
        [footer addSubview:argsLabel];

        self.argsField = [[UITextField alloc] initWithFrame:CGRectMake(20, 35, footer.frame.size.width - 40, 40)];
        self.argsField.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1];
        self.argsField.layer.cornerRadius = 8;
        self.argsField.textColor = [UIColor whiteColor];
        self.argsField.font = [UIFont systemFontOfSize:14];
        self.argsField.placeholder = @" e.g. --debug --verbose";
        self.argsField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:self.argsField.placeholder attributes:@{NSForegroundColorAttributeName: [UIColor grayColor]}];
        self.argsField.delegate = self;
        [footer addSubview:self.argsField];

        UILabel *envLabel = [[UILabel alloc] initWithFrame:CGRectMake(25, 85, 200, 20)];
        envLabel.text = @"環境変数 (KEY=VALUE, 改行区切り)";
        envLabel.textColor = [UIColor lightGrayColor];
        envLabel.font = [UIFont systemFontOfSize:12];
        [footer addSubview:envLabel];

        self.envField = [[UITextField alloc] initWithFrame:CGRectMake(20, 110, footer.frame.size.width - 40, 40)];
        self.envField.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1];
        self.envField.layer.cornerRadius = 8;
        self.envField.textColor = [UIColor whiteColor];
        self.envField.font = [UIFont systemFontOfSize:14];
        self.envField.placeholder = @" e.g. OS_ACTIVITY_MODE=disable";
        self.envField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:self.envField.placeholder attributes:@{NSForegroundColorAttributeName: [UIColor grayColor]}];
        self.envField.delegate = self;
        [footer addSubview:self.envField];

        UILabel *jitLabel = [[UILabel alloc] initWithFrame:CGRectMake(25, 165, 100, 31)];
        jitLabel.text = @"JIT起動有効化";
        jitLabel.textColor = [UIColor whiteColor];
        jitLabel.font = [UIFont systemFontOfSize:14];
        [footer addSubview:jitLabel];

        self.jitSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(footer.frame.size.width - 71, 165, 51, 31)];
        self.jitSwitch.onTintColor = [ThemeEngine liquidColor];
        [footer addSubview:self.jitSwitch];

        UIButton *launchBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        launchBtn.frame = CGRectMake(20, 210, footer.frame.size.width - 40, 50);
        [ThemeEngine applyGlassStyleToView:launchBtn cornerRadius:12];
        [launchBtn setTitle:@"アプリを起動" forState:UIControlStateNormal];
        [launchBtn setTitleColor:[ThemeEngine liquidColor] forState:UIControlStateNormal];
        [launchBtn addTarget:self action:@selector(launchApp) forControlEvents:UIControlEventTouchUpInside];
        [footer addSubview:launchBtn];

        self.tableView.tableFooterView = footer;
    }
}

- (void)launchApp {
    NSString *bid = self.isDictionary ? self.data[@"CFBundleIdentifier"] : nil;
    if (!bid) return;

    NSArray *args = nil;
    if (self.argsField.text.length > 0) {
        args = [self.argsField.text componentsSeparatedByString:@" "];
        NSMutableArray *cleanedArgs = [NSMutableArray array];
        for (NSString *a in args) {
            NSString *trimmed = [a stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (trimmed.length > 0) [cleanedArgs addObject:trimmed];
        }
        args = cleanedArgs;
    }

    NSMutableDictionary *env = nil;
    if (self.envField.text.length > 0) {
        env = [NSMutableDictionary dictionary];
        NSArray *lines = [self.envField.text componentsSeparatedByString:@"\n"];
        for (NSString *line in lines) {
            NSArray *parts = [line componentsSeparatedByString:@"="];
            if (parts.count >= 2) {
                env[parts[0]] = parts[1];
            }
        }
    }

    BOOL useJIT = self.jitSwitch.on;

    [[IdeviceManager sharedManager] launchAppWithBundleId:bid arguments:args environment:env useJIT:useJIT completion:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"起動エラー" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            } else {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"成功" message:@"起動要求を送信しました" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.isDictionary) return self.displayKeys.count;
    return self.displayData.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DetailCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"DetailCell"];
        cell.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.05];
        cell.textLabel.textColor = [ThemeEngine liquidColor];
        cell.detailTextLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.numberOfLines = 0;
    }

    id value = nil;
    NSString *keyLabel = nil;

    if (self.isDictionary) {
        NSString *key = self.displayKeys[indexPath.row];
        keyLabel = [self localizedKey:key];
        value = self.data[key];
    } else {
        keyLabel = [NSString stringWithFormat:@"項目 %ld", (long)indexPath.row];
        value = self.displayData[indexPath.row];
    }

    cell.textLabel.text = keyLabel;
    if ([value isKindOfClass:[NSDictionary class]]) {
        cell.detailTextLabel.text = @"[辞書データ...]";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([value isKindOfClass:[NSArray class]]) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"[配列データ: %ld件]", (long)((NSArray *)value).count];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.detailTextLabel.text = (value && value != [NSNull null]) ? [NSString stringWithFormat:@"%@", value] : @"(空)";
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    return cell;
}

- (NSString *)localizedKey:(NSString *)key {
    static NSDictionary *map = nil;
    if (!map) {
        map = @{
            @"CFBundleDisplayName": @"表示名",
            @"CFBundleName": @"アプリ名",
            @"CFBundleIdentifier": @"識別子 (Bundle ID)",
            @"CFBundleShortVersionString": @"バージョン",
            @"CFBundleVersion": @"ビルド番号",
            @"Path": @"インストールパス",
            @"Container": @"コンテナパス",
            @"DataContainer": @"データパス",
            @"ApplicationType": @"アプリの種類",
            @"Entitlements": @"エンタイトルメント",
            @"EnvironmentVariables": @"環境変数",
            @"MinimumOSVersion": @"最小OSバージョン",
            @"UIDeviceFamily": @"対応デバイス",
            @"UIRequiredDeviceCapabilities": @"必要機能"
        };
    }
    return map[key] ?: key;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    id value = self.isDictionary ? self.data[self.displayKeys[indexPath.row]] : self.displayData[indexPath.row];
    NSString *nextTitle = self.isDictionary ? self.displayKeys[indexPath.row] : [NSString stringWithFormat:@"項目 %ld", (long)indexPath.row];

    if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
        IdeviceAppDetailViewController *vc = [[IdeviceAppDetailViewController alloc] initWithData:value title:nextTitle];
        [self.navigationController pushViewController:vc animated:YES];
    }
}

@end
