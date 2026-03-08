#import "SettingsViewController.h"
#import "ThemeEngine.h"
#import "BookmarksManager.h"
#import "CustomMenuView.h"
#import "WebBrowserViewController.h"
#import "PersistenceManager.h"
#import "L.h"
#import <LocalAuthentication/LocalAuthentication.h>

@interface SettingsViewController ()
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [L s:@"設定" en:@"Settings"];
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.tableView];
}

#pragma mark - TableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 9;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 2; // General
        case 1: return 3; // Display
        case 2: return 1; // Sort
        case 3: return 2; // Appearance
        case 4: return 4; // Web
        case 5: return [PersistenceManager sharedManager].persistentDomains.count;
        case 6: return 3; // iDevice Settings
        case 7: return 1; // Advanced
        case 8: return [BookmarksManager sharedManager].bookmarks.count;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return [L s:@"全般" en:@"General"];
        case 1: return [L s:@"表示設定" en:@"Display"];
        case 2: return [L s:@"並び替え" en:@"Sort"];
        case 3: return [L s:@"テーマ" en:@"Appearance"];
        case 4: return [L s:@"ウェブ" en:@"Web"];
        case 5: return [L s:@"永続ドメイン" en:@"Persistent Domains"];
        case 6: return [L s:@"iDevice設定" en:@"iDevice Settings"];
        case 7: return [L s:@"高度な設定" en:@"Advanced"];
        case 8: return [L s:@"お気に入り" en:@"Favorites"];
        default: return nil;
    }
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
    cell.textLabel.textColor = [UIColor whiteColor];

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = [L s:@"起動時のパス" en:@"Start Path"];
            cell.detailTextLabel.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"DefaultStartPath"] ?: NSHomeDirectory();
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = [L s:@"削除時に確認する" en:@"Confirm Deletion"];
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [[NSUserDefaults standardUserDefaults] objectForKey:@"ConfirmDeletion"] ? [[NSUserDefaults standardUserDefaults] boolForKey:@"ConfirmDeletion"] : YES;
            [sw addTarget:self action:@selector(confirmDeleteToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = [L s:@"隠しファイルを表示" en:@"Show Hidden Files"];
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:@"ShowHiddenFiles"];
            [sw addTarget:self action:@selector(hiddenSwitchToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = [L s:@"フォルダを先頭に表示" en:@"Folders First"];
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [[NSUserDefaults standardUserDefaults] objectForKey:@"FoldersFirst"] ? [[NSUserDefaults standardUserDefaults] boolForKey:@"FoldersFirst"] : YES;
            [sw addTarget:self action:@selector(foldersFirstToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else {
            cell.textLabel.text = [L s:@"検索バーを常に表示" en:@"Always Show Search"];
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:@"AlwaysShowSearch"];
            [sw addTarget:self action:@selector(alwaysShowSearchToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
    } else if (indexPath.section == 2) {
        cell.textLabel.text = [L s:@"並び替え順" en:@"Sort Method"];
        NSInteger sort = [[NSUserDefaults standardUserDefaults] integerForKey:@"SortMethod"];
        NSArray *modes = @[[L s:@"名前" en:@"Name"], [L s:@"日付" en:@"Date"], [L s:@"サイズ" en:@"Size"]];
        cell.detailTextLabel.text = modes[sort % 3];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 3) {
        if (indexPath.row == 0) {
            cell.textLabel.text = [L s:@"グラス効果の透明度" en:@"Glass Alpha"];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1f", [[NSUserDefaults standardUserDefaults] floatForKey:@"GlassAlpha"] ?: 0.5];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = [L s:@"アクセントカラー" en:@"Accent Color"];
            cell.detailTextLabel.text = [L s:@"選択中" en:@"Selected"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (indexPath.section == 4) {
        if (indexPath.row == 0) {
            cell.textLabel.text = [L s:@"検索エンジン" en:@"Search Engine"];
            NSString *engine = [[NSUserDefaults standardUserDefaults] stringForKey:@"SearchEngine"] ?: @"Google";
            cell.detailTextLabel.text = engine;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = [L s:@"ホームページ" en:@"Homepage"];
            cell.detailTextLabel.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"WebHomepage"] ?: @"https://www.google.com";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = [L s:@"ブラウザデータを消去" en:@"Clear Browser Data"];
            cell.textLabel.textColor = [UIColor systemRedColor];
        } else {
            cell.textLabel.text = [L s:@"永続保存サイトを追加" en:@"Add Persistent Domain"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (indexPath.section == 5) {
        cell.textLabel.text = [PersistenceManager sharedManager].persistentDomains[indexPath.row];
    } else if (indexPath.section == 6) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"IP Address";
            cell.detailTextLabel.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"IdeviceIP"] ?: @"10.7.0.1";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Port";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)([[NSUserDefaults standardUserDefaults] integerForKey:@"IdevicePort"] ?: 62078)];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = [L s:@"言語設定" en:@"Language"];
            NSString *lang = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppLanguage"] ?: @"jp";
            cell.detailTextLabel.text = [lang isEqualToString:@"en"] ? @"English" : @"日本語";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (indexPath.section == 7) {
        cell.textLabel.text = [L s:@"全ての設定をリセット" en:@"Reset All Settings"];
        cell.textLabel.textColor = [UIColor systemRedColor];
    } else if (indexPath.section == 8) {
        NSString *path = [BookmarksManager sharedManager].bookmarks[indexPath.row];
        cell.textLabel.text = [path lastPathComponent];
        cell.detailTextLabel.text = path;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && indexPath.row == 0) [self editDefaultPath];
    else if (indexPath.section == 2) [self selectSortMethod];
    else if (indexPath.section == 3) {
        if (indexPath.row == 0) [self selectGlassAlpha];
        else [self selectAccentColor];
    } else if (indexPath.section == 4) {
        if (indexPath.row == 0) [self selectSearchEngine];
        else if (indexPath.row == 1) [self editHomepage];
        else if (indexPath.row == 2) [self clearBrowserData];
        else [self addNewPersistentDomain];
    } else if (indexPath.section == 6) {
        if (indexPath.row == 0) [self editIdeviceIP];
        else if (indexPath.row == 1) [self editIdevicePort];
        else [self selectLanguage];
    } else if (indexPath.section == 7) [self confirmResetSettings];
}

#pragma mark - iDevice Settings

- (void)editIdeviceIP {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"IP Address" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"IdeviceIP"] ?: @"10.7.0.1"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[NSUserDefaults standardUserDefaults] setObject:alert.textFields[0].text forKey:@"IdeviceIP"];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:[L s:@"キャンセル" en:@"Cancel"] style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)editIdevicePort {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Port" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = [NSString stringWithFormat:@"%ld", (long)([[NSUserDefaults standardUserDefaults] integerForKey:@"IdevicePort"] ?: 62078)];
        tf.keyboardType = UIKeyboardTypeNumberPad;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[NSUserDefaults standardUserDefaults] setInteger:[alert.textFields[0].text integerValue] forKey:@"IdevicePort"];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:[L s:@"キャンセル" en:@"Cancel"] style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)selectLanguage {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:[L s:@"言語設定" en:@"Language"]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"日本語" systemImage:nil style:CustomMenuActionStyleDefault handler:^{
        [[NSUserDefaults standardUserDefaults] setObject:@"jp" forKey:@"AppLanguage"];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SettingsChanged" object:nil];
        [self.tableView reloadData];
    }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"English" systemImage:nil style:CustomMenuActionStyleDefault handler:^{
        [[NSUserDefaults standardUserDefaults] setObject:@"en" forKey:@"AppLanguage"];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SettingsChanged" object:nil];
        [self.tableView reloadData];
    }]];
    [menu showInView:self.view];
}

#pragma mark - Existing Logic (Simplified)

- (void)selectSearchEngine {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:[L s:@"検索エンジン" en:@"Search Engine"]];
    NSArray *engines = @[@"Google", @"Bing", @"DuckDuckGo", @"Yahoo"];
    for (NSString *engine in engines) {
        [menu addAction:[CustomMenuAction actionWithTitle:engine systemImage:nil style:CustomMenuActionStyleDefault handler:^{
            [[NSUserDefaults standardUserDefaults] setObject:engine forKey:@"SearchEngine"];
            [self.tableView reloadData];
        }]];
    }
    [menu showInView:self.view];
}

- (void)editHomepage {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[L s:@"ホームページ" en:@"Homepage"] message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"WebHomepage"] ?: @"https://www.google.com"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[NSUserDefaults standardUserDefaults] setObject:alert.textFields[0].text forKey:@"WebHomepage"];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:[L s:@"キャンセル" en:@"Cancel"] style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)editDefaultPath {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[L s:@"起動パス" en:@"Start Path"] message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"DefaultStartPath"] ?: NSHomeDirectory(); }];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[NSUserDefaults standardUserDefaults] setObject:alert.textFields[0].text forKey:@"DefaultStartPath"];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:[L s:@"キャンセル" en:@"Cancel"] style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)selectSortMethod {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:[L s:@"並び替え" en:@"Sort"]];
    NSArray *modes = @[[L s:@"名前" en:@"Name"], [L s:@"日付" en:@"Date"], [L s:@"サイズ" en:@"Size"]];
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
    CustomMenuView *menu = [CustomMenuView menuWithTitle:[L s:@"透明度を選択" en:@"Select Transparency"]];
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
    CustomMenuView *menu = [CustomMenuView menuWithTitle:[L s:@"カラーを選択" en:@"Select Color"]];
    NSDictionary *colors = @{[L s:@"ブルー" en:@"Blue"]: @"blue", [L s:@"レッド" en:@"Red"]: @"red", [L s:@"グリーン" en:@"Green"]: @"green", [L s:@"パープル" en:@"Purple"]: @"purple"};
    for (NSString *name in colors) {
        [menu addAction:[CustomMenuAction actionWithTitle:name systemImage:@"circle.fill" style:CustomMenuActionStyleDefault handler:^{
            [[NSUserDefaults standardUserDefaults] setObject:colors[name] forKey:@"AccentColor"];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"SettingsChanged" object:nil];
            [self.tableView reloadData];
        }]];
    }
    [menu showInView:self.view];
}

- (void)addNewPersistentDomain {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[L s:@"永続ドメイン" en:@"Persistent Domain"] message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:nil];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *domain = alert.textFields[0].text;
        if (domain.length > 0) { [[PersistenceManager sharedManager] addDomain:domain]; [self.tableView reloadData]; }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:[L s:@"キャンセル" en:@"Cancel"] style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)clearBrowserData {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[L s:@"データ消去" en:@"Clear Data"] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:[L s:@"消去" en:@"Clear"] style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [WebBrowserViewController resetSharedDataStore]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:[L s:@"キャンセル" en:@"Cancel"] style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmResetSettings {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[L s:@"設定リセット" en:@"Reset Settings"] message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[L s:@"リセット" en:@"Reset"] style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSString *appDomain = [[NSBundle mainBundle] bundleIdentifier];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:appDomain];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SettingsChanged" object:nil];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:[L s:@"キャンセル" en:@"Cancel"] style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmDeleteToggled:(UISwitch *)sender { [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"ConfirmDeletion"]; }
- (void)hiddenSwitchToggled:(UISwitch *)sender { [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"ShowHiddenFiles"]; [[NSNotificationCenter defaultCenter] postNotificationName:@"SettingsChanged" object:nil]; }
- (void)foldersFirstToggled:(UISwitch *)sender { [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"FoldersFirst"]; [[NSNotificationCenter defaultCenter] postNotificationName:@"SettingsChanged" object:nil]; }
- (void)alwaysShowSearchToggled:(UISwitch *)sender { [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"AlwaysShowSearch"]; [[NSNotificationCenter defaultCenter] postNotificationName:@"SettingsChanged" object:nil]; }

@end
