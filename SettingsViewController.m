#import "SettingsViewController.h"
#import "ThemeEngine.h"
#import "BookmarksManager.h"
#import "CustomMenuView.h"

@interface SettingsViewController ()
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"設定";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.tableView];
}

#pragma mark - TableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1; // Default Path
    if (section == 1) return 3; // Show Hidden, Folders First, Reveal Search
    if (section == 2) return 1; // Sort Method
    if (section == 3) return 2; // Glass Intensity, Accent Color
    if (section == 4) return [BookmarksManager sharedManager].bookmarks.count; // Favorites
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"全般";
    if (section == 1) return @"表示設定";
    if (section == 2) return @"並び替え";
    if (section == 3) return @"外観カスタマイズ";
    if (section == 4) return @"お気に入り";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SettingsCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"SettingsCell"];
        cell.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.05];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
    }

    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (indexPath.section == 0) {
        cell.textLabel.text = @"起動時のパス";
        cell.detailTextLabel.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"DefaultStartPath"] ?: @"/";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"隠しファイルを表示";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:@"ShowHiddenFiles"];
            [sw addTarget:self action:@selector(hiddenSwitchToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"フォルダを先頭に表示";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [[NSUserDefaults standardUserDefaults] objectForKey:@"FoldersFirst"] ? [[NSUserDefaults standardUserDefaults] boolForKey:@"FoldersFirst"] : YES;
            [sw addTarget:self action:@selector(foldersFirstToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else {
            cell.textLabel.text = @"検索バーを常に表示";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:@"AlwaysShowSearch"];
            [sw addTarget:self action:@selector(alwaysShowSearchToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
    } else if (indexPath.section == 2) {
        cell.textLabel.text = @"並び替え順";
        NSInteger sort = [[NSUserDefaults standardUserDefaults] integerForKey:@"SortMethod"];
        NSArray *modes = @[@"名前", @"日付", @"サイズ"];
        cell.detailTextLabel.text = modes[sort % 3];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 3) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"グラス効果の透明度";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1f", [[NSUserDefaults standardUserDefaults] floatForKey:@"GlassAlpha"] ?: 0.5];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = @"アクセントカラー";
            cell.detailTextLabel.text = @"選択中";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (indexPath.section == 4) {
        NSString *path = [BookmarksManager sharedManager].bookmarks[indexPath.row];
        cell.textLabel.text = [path lastPathComponent];
        cell.detailTextLabel.text = path;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        [self editDefaultPath];
    } else if (indexPath.section == 2) {
        [self selectSortMethod];
    } else if (indexPath.section == 3) {
        if (indexPath.row == 0) [self selectGlassAlpha];
        else [self selectAccentColor];
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 4;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete && indexPath.section == 4) {
        NSString *path = [BookmarksManager sharedManager].bookmarks[indexPath.row];
        [[BookmarksManager sharedManager] removeBookmark:path];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
}

- (void)editDefaultPath {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"起動パス" message:@"アプリ起動時に開くパスを入力してください" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"DefaultStartPath"] ?: @"/";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[NSUserDefaults standardUserDefaults] setObject:alert.textFields[0].text forKey:@"DefaultStartPath"];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SettingsChanged" object:nil];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)selectSortMethod {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"並び替え"];
    NSArray *modes = @[@"名前", @"日付", @"サイズ"];
    for (NSInteger i = 0; i < modes.count; i++) {
        [menu addAction:[CustomMenuAction actionWithTitle:modes[i] systemImage:nil style:CustomMenuActionStyleDefault handler:^{
            [[NSUserDefaults standardUserDefaults] setInteger:i forKey:@"SortMethod"];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"SettingsChanged" object:nil];
            [self.tableView reloadData];
        }]];
    }
    [menu showInView:self.view];
}

- (void)selectGlassAlpha {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"透明度を選択"];
    NSArray *alphas = @[@"0.2", @"0.4", @"0.6", @"0.8"];
    for (NSString *a in alphas) {
        [menu addAction:[CustomMenuAction actionWithTitle:a systemImage:nil style:CustomMenuActionStyleDefault handler:^{
            [[NSUserDefaults standardUserDefaults] setFloat:[a floatValue] forKey:@"GlassAlpha"];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"SettingsChanged" object:nil];
            [self.tableView reloadData];
        }]];
    }
    [menu showInView:self.view];
}

- (void)selectAccentColor {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"カラーを選択"];
    NSDictionary *colors = @{@"ブルー": @"blue", @"レッド": @"red", @"グリーン": @"green", @"パープル": @"purple"};
    for (NSString *name in colors) {
        [menu addAction:[CustomMenuAction actionWithTitle:name systemImage:@"circle.fill" style:CustomMenuActionStyleDefault handler:^{
            [[NSUserDefaults standardUserDefaults] setObject:colors[name] forKey:@"AccentColor"];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"SettingsChanged" object:nil];
            [self.tableView reloadData];
        }]];
    }
    [menu showInView:self.view];
}

- (void)hiddenSwitchToggled:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"ShowHiddenFiles"];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SettingsChanged" object:nil];
}

- (void)foldersFirstToggled:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"FoldersFirst"];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SettingsChanged" object:nil];
}

- (void)alwaysShowSearchToggled:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"AlwaysShowSearch"];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SettingsChanged" object:nil];
}

@end
