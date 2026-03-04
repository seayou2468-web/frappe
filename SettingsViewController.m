#import "SettingsViewController.h"
#import "ThemeEngine.h"
#import "BookmarksManager.h"
#import "CustomMenuView.h"
#import "WebBrowserViewController.h"
#import "PersistenceManager.h"
#import <LocalAuthentication/LocalAuthentication.h>

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
    return 8;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 2; // General
        case 1: return 3; // Display
        case 2: return 1; // Sort
        case 3: return 2; // Appearance
        case 4: return 4; // Web: Engine, Homepage, Clear Data, Add Whitelist
        case 5: return [PersistenceManager sharedManager].persistentDomains.count; // Whitelist items
        case 6: return 1; // Advanced
        case 7: return [BookmarksManager sharedManager].bookmarks.count; // Favorites
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"全般";
        case 1: return @"表示設定";
        case 2: return @"並び替え";
        case 3: return @"外観カスタマイズ";
        case 4: return @"ウェブブラウザ";
        case 5: return @"データを常に保持するサイト";
        case 6: return @"詳細";
        case 7: return @"お気に入り";
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
            cell.textLabel.text = @"起動時のパス";
            cell.detailTextLabel.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"DefaultStartPath"] ?: NSHomeDirectory();
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = @"削除時に確認する";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [[NSUserDefaults standardUserDefaults] objectForKey:@"ConfirmDeletion"] ? [[NSUserDefaults standardUserDefaults] boolForKey:@"ConfirmDeletion"] : YES;
            [sw addTarget:self action:@selector(confirmDeleteToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
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
        if (indexPath.row == 0) {
            cell.textLabel.text = @"検索エンジン";
            NSString *engine = [[NSUserDefaults standardUserDefaults] stringForKey:@"SearchEngine"] ?: @"Google";
            if ([engine isEqualToString:@"Custom"]) {
                NSString *customUrl = [[NSUserDefaults standardUserDefaults] stringForKey:@"CustomSearchURL"];
                cell.detailTextLabel.text = customUrl ? [NSString stringWithFormat:@"カスタム (%@)", customUrl] : @"カスタム (未設定)";
            } else {
                cell.detailTextLabel.text = engine;
            }
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"ホームページ";
            cell.detailTextLabel.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"WebHomepage"] ?: @"https://www.google.com";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"ブラウザデータを消去";
            cell.textLabel.textColor = [UIColor systemRedColor];
        } else {
            cell.textLabel.text = @"永続保存サイトを追加";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (indexPath.section == 5) {
        cell.textLabel.text = [PersistenceManager sharedManager].persistentDomains[indexPath.row];
    } else if (indexPath.section == 6) {
        cell.textLabel.text = @"全ての設定をリセット";
        cell.textLabel.textColor = [UIColor systemRedColor];
    } else if (indexPath.section == 7) {
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
    } else if (indexPath.section == 6) [self confirmResetSettings];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return (indexPath.section == 5 || indexPath.section == 7);
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        if (indexPath.section == 5) {
            NSString *domain = [PersistenceManager sharedManager].persistentDomains[indexPath.row];
            [[PersistenceManager sharedManager] removeDomain:domain];
        } else if (indexPath.section == 7) {
            NSString *path = [BookmarksManager sharedManager].bookmarks[indexPath.row];
            [[BookmarksManager sharedManager] removeBookmark:path];
        }
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
}

#pragma mark - Browser Customization

- (void)selectSearchEngine {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"検索エンジン"];
    NSArray *engines = @[@"Google", @"Bing", @"DuckDuckGo", @"Yahoo", @"Custom"];
    for (NSString *engine in engines) {
        NSString *display = [engine isEqualToString:@"Custom"] ? @"カスタム設定..." : engine;
        [menu addAction:[CustomMenuAction actionWithTitle:display systemImage:nil style:CustomMenuActionStyleDefault handler:^{
            if ([engine isEqualToString:@"Custom"]) {
                [self editCustomSearchURL];
            } else {
                [[NSUserDefaults standardUserDefaults] setObject:engine forKey:@"SearchEngine"];
                [self.tableView reloadData];
            }
        }]];
    }
    [menu showInView:self.view];
}

- (void)editCustomSearchURL {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"カスタム検索" message:@"検索URLを入力してください (例: https://example.com/search?q=)" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"CustomSearchURL"] ?: @"";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *url = alert.textFields[0].text;
        if (url.length > 0) {
            [[NSUserDefaults standardUserDefaults] setObject:@"Custom" forKey:@"SearchEngine"];
            [[NSUserDefaults standardUserDefaults] setObject:url forKey:@"CustomSearchURL"];
            [self.tableView reloadData];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)editHomepage {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ホームページ" message:@"URLを入力してください" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"WebHomepage"] ?: @"https://www.google.com";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[NSUserDefaults standardUserDefaults] setObject:alert.textFields[0].text forKey:@"WebHomepage"];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Existing Logic

- (void)editDefaultPath {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"起動パス" message:@"アプリ起動時に開くパスを入力してください" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"DefaultStartPath"] ?: NSHomeDirectory(); }];
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

- (void)addNewPersistentDomain {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"永続ドメイン" message:@"ドメイン名を入力してください" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:nil];
    [alert addAction:[UIAlertAction actionWithTitle:@"追加" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *domain = alert.textFields[0].text;
        if (domain.length > 0) { [[PersistenceManager sharedManager] addDomain:domain]; [self.tableView reloadData]; }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)clearBrowserData {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"データ消去" message:@"履歴、クッキー、キャッシュを全て消去しますか？" preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"消去" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [WebBrowserViewController resetSharedDataStore]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmResetSettings {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"設定リセット" message:@"全ての設定を初期状態に戻しますか？" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"リセット" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSString *appDomain = [[NSBundle mainBundle] bundleIdentifier];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:appDomain];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SettingsChanged" object:nil];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmDeleteToggled:(UISwitch *)sender { [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"ConfirmDeletion"]; }
- (void)hiddenSwitchToggled:(UISwitch *)sender { [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"ShowHiddenFiles"]; [[NSNotificationCenter defaultCenter] postNotificationName:@"SettingsChanged" object:nil]; }
- (void)foldersFirstToggled:(UISwitch *)sender { [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"FoldersFirst"]; [[NSNotificationCenter defaultCenter] postNotificationName:@"SettingsChanged" object:nil]; }
- (void)alwaysShowSearchToggled:(UISwitch *)sender { [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"AlwaysShowSearch"]; [[NSNotificationCenter defaultCenter] postNotificationName:@"SettingsChanged" object:nil]; }

@end
