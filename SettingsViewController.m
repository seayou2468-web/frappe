// SettingsViewController.m — Redesigned: clean grouped UI with icons + live feedback
#import "SettingsViewController.h"
#import "ThemeEngine.h"
#import "BookmarksManager.h"
#import "WebBrowserViewController.h"
#import "WebHistoryManager.h"
#import "PersistenceManager.h"
#import <LocalAuthentication/LocalAuthentication.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>

#define UD [NSUserDefaults standardUserDefaults]
#define NOTIFY [[NSNotificationCenter defaultCenter] postNotificationName:@"SettingsChanged" object:nil]

static inline BOOL udBool(NSString *k, BOOL def) {
    id v = [UD objectForKey:k]; return v ? [UD boolForKey:k] : def;
}
static inline NSInteger udInt(NSString *k, NSInteger def) {
    id v = [UD objectForKey:k]; return v ? [UD integerForKey:k] : def;
}
static inline NSString *udStr(NSString *k, NSString *def) {
    return [UD stringForKey:k] ?: def;
}

// ─── Row Model ────────────────────────────────────────────────────────────────
typedef NS_ENUM(NSUInteger, RowType) {
    RowTypeToggle,      // UISwitch
    RowTypeDisclosure,  // → detail
    RowTypeInfo,        // static text right
    RowTypeAction,      // tap = action, optional tint
    RowTypeSlider,      // inline slider
};

@interface SettingRow : NSObject
@property (nonatomic, copy)   NSString  *title;
@property (nonatomic, copy)   NSString  *icon;     // SF Symbol name
@property (nonatomic, strong) UIColor   *iconTint;
@property (nonatomic, assign) RowType    type;
@property (nonatomic, copy)   NSString  *udKey;    // NSUserDefaults key (toggle)
@property (nonatomic, assign) BOOL       udDefault;
@property (nonatomic, copy)   NSString  *detail;   // disclosure subtitle
@property (nonatomic, copy)   void      (^action)(UITableViewCell *cell, UIViewController *vc);
+ (instancetype)toggle:(NSString *)title icon:(NSString *)sym tint:(UIColor *)tint
                   key:(NSString *)key def:(BOOL)def;
+ (instancetype)disclosure:(NSString *)title icon:(NSString *)sym tint:(UIColor *)tint
                    detail:(NSString *)detail action:(void(^)(UITableViewCell *, UIViewController *))act;
+ (instancetype)action:(NSString *)title icon:(NSString *)sym tint:(UIColor *)tint
                action:(void(^)(UITableViewCell *, UIViewController *))act;
+ (instancetype)info:(NSString *)title icon:(NSString *)sym tint:(UIColor *)tint
              detail:(NSString *)detail;
@end
@implementation SettingRow
+ (instancetype)toggle:(NSString *)t icon:(NSString *)sym tint:(UIColor *)tint key:(NSString *)k def:(BOOL)d {
    SettingRow *r = [SettingRow new]; r.title=t; r.icon=sym; r.iconTint=tint;
    r.type=RowTypeToggle; r.udKey=k; r.udDefault=d; return r;
}
+ (instancetype)disclosure:(NSString *)t icon:(NSString *)sym tint:(UIColor *)tint
                    detail:(NSString *)d action:(void(^)(UITableViewCell *, UIViewController *))a {
    SettingRow *r = [SettingRow new]; r.title=t; r.icon=sym; r.iconTint=tint;
    r.type=RowTypeDisclosure; r.detail=d; r.action=a; return r;
}
+ (instancetype)action:(NSString *)t icon:(NSString *)sym tint:(UIColor *)tint
                action:(void(^)(UITableViewCell *, UIViewController *))a {
    SettingRow *r = [SettingRow new]; r.title=t; r.icon=sym; r.iconTint=tint;
    r.type=RowTypeAction; r.action=a; return r;
}
+ (instancetype)info:(NSString *)t icon:(NSString *)sym tint:(UIColor *)tint detail:(NSString *)d {
    SettingRow *r = [SettingRow new]; r.title=t; r.icon=sym; r.iconTint=tint;
    r.type=RowTypeInfo; r.detail=d; return r;
}
@end

// ─── Main VC ─────────────────────────────────────────────────────────────────
@interface SettingsViewController () <UITableViewDelegate, UITableViewDataSource>
@property (strong) UITableView *tableView;
@property (strong) NSArray<NSDictionary *> *sections; // [{title, rows:[SettingRow]}]
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"設定";
    self.view.backgroundColor = [ThemeEngine bg];
    [self buildSections];
    [self setupTable];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self buildSections];
    [self.tableView reloadData];
}

// ─── Table Setup ─────────────────────────────────────────────────────────────
- (void)setupTable {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                  style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorColor = [ThemeEngine border];
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 56, 0, 0);
    [self.view addSubview:self.tableView];
}

// ─── Build Sections ───────────────────────────────────────────────────────────
- (void)buildSections {
    __weak typeof(self) ws = self;

    UIColor *blue   = [UIColor systemBlueColor];
    UIColor *green  = [UIColor systemGreenColor];
    UIColor *orange = [UIColor systemOrangeColor];
    UIColor *purple = [UIColor systemPurpleColor];
    UIColor *red    = [UIColor systemRedColor];
    UIColor *teal   = [UIColor systemTealColor];
    UIColor *pink   = [UIColor systemPinkColor];
    UIColor *indigo = [UIColor systemIndigoColor];

    // Helper: show picker alert
    void (^picker)(NSString *, NSArray *, NSString *, void(^)(NSString *)) =
    ^(NSString *title, NSArray *opts, NSString *key, void(^done)(NSString *)) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:title
            message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSString *opt in opts) {
            BOOL isCur = [udStr(key, opts.firstObject) isEqualToString:opt];
            UIAlertAction *act = [UIAlertAction actionWithTitle:
                [NSString stringWithFormat:@"%@ %@", isCur?@"✓":@"", opt]
                style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
                    [UD setObject:opt forKey:key]; NOTIFY;
                    if (done) done(opt);
                    [ws buildSections]; [ws.tableView reloadData];
                }];
            [a addAction:act];
        }
        [a addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
        a.popoverPresentationController.sourceView = ws.view;
        a.popoverPresentationController.sourceRect = CGRectMake(ws.view.bounds.size.width/2,
                                                                 ws.view.bounds.size.height/2, 1,1);
        [ws presentViewController:a animated:YES completion:nil];
    };

    // Helper: number input
    void (^numInput)(NSString *, NSString *, NSInteger, NSInteger, NSInteger) =
    ^(NSString *title, NSString *key, NSInteger def, NSInteger min, NSInteger max) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:title
            message:[NSString stringWithFormat:@"(%ld〜%ld)", (long)min, (long)max]
            preferredStyle:UIAlertControllerStyleAlert];
        [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
            tf.keyboardType = UIKeyboardTypeNumberPad;
            tf.text = [NSString stringWithFormat:@"%ld", (long)udInt(key, def)];
        }];
        [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *_) {
                NSInteger v = MAX(min, MIN(max, [a.textFields.firstObject.text integerValue]));
                [UD setInteger:v forKey:key]; NOTIFY;
                [ws buildSections]; [ws.tableView reloadData];
            }]];
        [a addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
        [ws presentViewController:a animated:YES completion:nil];
    };

    // Helper: text input
    void (^textInput)(NSString *, NSString *, NSString *) =
    ^(NSString *title, NSString *key, NSString *def) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:title
            message:nil preferredStyle:UIAlertControllerStyleAlert];
        [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
            tf.text = udStr(key, def);
            tf.autocorrectionType = UITextAutocorrectionTypeNo;
            tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        }];
        [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *_) {
                NSString *v = a.textFields.firstObject.text;
                if (v.length) { [UD setObject:v forKey:key]; NOTIFY; }
                [ws buildSections]; [ws.tableView reloadData];
            }]];
        [a addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
        [ws presentViewController:a animated:YES completion:nil];
    };

    self.sections = @[

        // ── ファイル管理 ─────────────────────────────────────────────────────
        @{@"title": @"ファイル管理",
          @"rows": @[
            [SettingRow toggle:@"隠しファイルを表示" icon:@"eye.fill" tint:blue key:@"ShowHiddenFiles" def:NO],
            [SettingRow toggle:@"フォルダを先頭に" icon:@"folder.fill" tint:orange key:@"FoldersFirst" def:YES],
            [SettingRow toggle:@"削除前に確認" icon:@"trash.fill" tint:red key:@"ConfirmDeletion" def:YES],
            [SettingRow toggle:@"上書き前に確認" icon:@"doc.fill.badge.plus" tint:orange key:@"ConfirmOverwrite" def:YES],
            [SettingRow disclosure:@"並び順"
                           icon:@"arrow.up.arrow.down" tint:indigo
                         detail:@[@"名前",@"変更日",@"サイズ",@"種類",@"拡張子"][MIN(udInt(@"SortMethod",0),4)]
                         action:^(UITableViewCell *c, UIViewController *v){
                             picker(@"並び替え順", @[@"名前",@"変更日",@"サイズ",@"種類",@"拡張子"], @"SortMethod", nil);
                         }],
            [SettingRow toggle:@"降順" icon:@"chevron.down" tint:indigo key:@"SortDescending" def:NO],
        ]},

        // ── 外観 ─────────────────────────────────────────────────────────────
        @{@"title": @"外観・テーマ",
          @"rows": @[
            [SettingRow disclosure:@"アクセントカラー"
                           icon:@"paintpalette.fill" tint:[ThemeEngine accent]
                         detail:udStr(@"AccentColor",@"blue")
                         action:^(UITableViewCell *c, UIViewController *v){
                             picker(@"アクセントカラー",
                                    @[@"blue",@"green",@"red",@"purple",@"orange",@"cyan",@"pink"],
                                    @"AccentColor", nil);
                         }],
            [SettingRow disclosure:@"カラースキーム"
                           icon:@"moon.stars.fill" tint:purple
                         detail:udStr(@"ColorScheme",@"Dark")
                         action:^(UITableViewCell *c, UIViewController *v){
                             picker(@"カラースキーム",
                                    @[@"Dark",@"AMOLED Black",@"Nord",@"Solarized",@"Dracula"],
                                    @"ColorScheme", nil);
                         }],
            [SettingRow toggle:@"アニメーション有効" icon:@"sparkles" tint:orange key:@"EnableAnimations" def:YES],
            [SettingRow toggle:@"ハプティックフィードバック" icon:@"hand.tap.fill" tint:teal key:@"HapticFeedback" def:YES],
        ]},

        // ── Web ──────────────────────────────────────────────────────────────
        @{@"title": @"Web ブラウザ",
          @"rows": @[
            [SettingRow disclosure:@"ホームページ"
                           icon:@"house.fill" tint:blue
                         detail:udStr(@"WebHomepage",@"about:blank")
                         action:^(UITableViewCell *c, UIViewController *v){
                             textInput(@"ホームページURL", @"WebHomepage", @"about:blank");
                         }],
            [SettingRow disclosure:@"検索エンジン"
                           icon:@"magnifyingglass" tint:green
                         detail:udStr(@"SearchEngine",@"Google")
                         action:^(UITableViewCell *c, UIViewController *v){
                             picker(@"検索エンジン",
                                    @[@"Google",@"DuckDuckGo",@"Bing",@"Yahoo",@"Ecosia"],
                                    @"SearchEngine", nil);
                         }],
            [SettingRow toggle:@"JavaScript" icon:@"curlybraces" tint:orange key:@"WebJavaScript" def:YES],
            [SettingRow toggle:@"広告ブロック" icon:@"shield.fill" tint:green key:@"AdBlocker" def:NO],
            [SettingRow toggle:@"デスクトップモード" icon:@"desktopcomputer" tint:indigo key:@"DesktopMode" def:NO],
            [SettingRow action:@"閲覧履歴を消去"
                        icon:@"clock.arrow.circlepath" tint:red
                       action:^(UITableViewCell *c, UIViewController *v){
                           UIAlertController *a = [UIAlertController
                               alertControllerWithTitle:@"閲覧履歴を消去"
                               message:@"すべての履歴を削除しますか？"
                               preferredStyle:UIAlertControllerStyleAlert];
                           [a addAction:[UIAlertAction actionWithTitle:@"消去"
                               style:UIAlertActionStyleDestructive
                               handler:^(UIAlertAction *_){ [[WebHistoryManager sharedManager] clearHistory]; }]];
                           [a addAction:[UIAlertAction actionWithTitle:@"キャンセル"
                               style:UIAlertActionStyleCancel handler:nil]];
                           [v presentViewController:a animated:YES completion:nil];
                       }],
        ]},

        // ── エディタ ─────────────────────────────────────────────────────────
        @{@"title": @"テキストエディタ",
          @"rows": @[
            [SettingRow disclosure:@"フォントサイズ"
                           icon:@"textformat.size" tint:blue
                         detail:[NSString stringWithFormat:@"%ldpt", (long)udInt(@"EditorFontSize",14)]
                         action:^(UITableViewCell *c, UIViewController *v){
                             numInput(@"フォントサイズ", @"EditorFontSize", 14, 8, 32);
                         }],
            [SettingRow disclosure:@"エディタテーマ"
                           icon:@"paintbrush.fill" tint:purple
                         detail:udStr(@"EditorTheme",@"Monokai")
                         action:^(UITableViewCell *c, UIViewController *v){
                             picker(@"エディタテーマ",
                                    @[@"Monokai",@"GitHub Dark",@"Solarized Dark",@"Nord",@"Dracula",@"One Dark"],
                                    @"EditorTheme", nil);
                         }],
            [SettingRow toggle:@"シンタックスハイライト" icon:@"highlighter" tint:orange key:@"SyntaxHighlight" def:YES],
            [SettingRow toggle:@"行番号表示" icon:@"list.number" tint:teal key:@"ShowLineNumbers" def:YES],
            [SettingRow toggle:@"自動インデント" icon:@"arrow.right.to.line" tint:indigo key:@"AutoIndent" def:YES],
            [SettingRow disclosure:@"タブ幅"
                           icon:@"arrow.left.and.right" tint:blue
                         detail:[NSString stringWithFormat:@"%ld文字", (long)udInt(@"TabWidth",4)]
                         action:^(UITableViewCell *c, UIViewController *v){
                             numInput(@"タブ幅", @"TabWidth", 4, 2, 8);
                         }],
        ]},

        // ── iDevice ──────────────────────────────────────────────────────────
        @{@"title": @"iDevice 接続",
          @"rows": @[
            [SettingRow disclosure:@"デフォルトIPアドレス"
                           icon:@"network" tint:blue
                         detail:udStr(@"IdeviceIP",@"10.7.0.1")
                         action:^(UITableViewCell *c, UIViewController *v){
                             textInput(@"デフォルトIP", @"IdeviceIP", @"10.7.0.1");
                         }],
            [SettingRow disclosure:@"デフォルトポート"
                           icon:@"cable.connector" tint:teal
                         detail:udStr(@"IdevicePort",@"62078")
                         action:^(UITableViewCell *c, UIViewController *v){
                             textInput(@"ポート番号", @"IdevicePort", @"62078");
                         }],
            [SettingRow disclosure:@"タイムアウト（秒）"
                           icon:@"timer" tint:orange
                         detail:[NSString stringWithFormat:@"%ld秒", (long)udInt(@"IdeviceTimeout",30)]
                         action:^(UITableViewCell *c, UIViewController *v){
                             numInput(@"タイムアウト", @"IdeviceTimeout", 30, 5, 120);
                         }],
            [SettingRow toggle:@"自動再接続" icon:@"arrow.clockwise.circle.fill" tint:green key:@"IdeviceAutoReconnect" def:NO],
        ]},

        // ── 位置情報シミュレーション ──────────────────────────────────────────
        @{@"title": @"位置情報シミュレーション",
          @"rows": @[
            [SettingRow disclosure:@"デフォルト移動速度"
                           icon:@"speedometer" tint:orange
                         detail:[NSString stringWithFormat:@"%.0f km/h",
                                  [[UD objectForKey:@"SimDefaultSpeed"] ? : @60.0 floatValue]]
                         action:^(UITableViewCell *c, UIViewController *v){
                             UIAlertController *a = [UIAlertController alertControllerWithTitle:@"移動速度 (km/h)"
                                 message:@"1〜500" preferredStyle:UIAlertControllerStyleAlert];
                             [a addTextFieldWithConfigurationHandler:^(UITextField *tf){
                                 tf.keyboardType = UIKeyboardTypeDecimalPad;
                                 tf.text = [NSString stringWithFormat:@"%.0f",
                                             [[UD objectForKey:@"SimDefaultSpeed"]?:@60.0 floatValue]];
                             }];
                             [a addAction:[UIAlertAction actionWithTitle:@"保存"
                                 style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
                                     float f = MAX(1, MIN(500, [a.textFields.firstObject.text floatValue]));
                                     [UD setFloat:f forKey:@"SimDefaultSpeed"]; NOTIFY;
                                     [ws buildSections]; [ws.tableView reloadData];
                                 }]];
                             [a addAction:[UIAlertAction actionWithTitle:@"キャンセル"
                                 style:UIAlertActionStyleCancel handler:nil]];
                             [v presentViewController:a animated:YES completion:nil];
                         }],
            [SettingRow toggle:@"自動再生" icon:@"play.fill" tint:green key:@"SimAutoPlay" def:YES],
            [SettingRow toggle:@"ルートをループ" icon:@"repeat" tint:blue key:@"SimLoopRoute" def:NO],
        ]},

        // ── スプレッドシート ─────────────────────────────────────────────────
        @{@"title": @"スプレッドシート",
          @"rows": @[
            [SettingRow disclosure:@"フォントサイズ"
                           icon:@"textformat" tint:blue
                         detail:[NSString stringWithFormat:@"%ldpt", (long)udInt(@"SpreadFontSize",13)]
                         action:^(UITableViewCell *c, UIViewController *v){
                             numInput(@"フォントサイズ", @"SpreadFontSize", 13, 8, 24);
                         }],
            [SettingRow disclosure:@"デフォルト行高"
                           icon:@"arrow.up.and.down.square" tint:teal
                         detail:[NSString stringWithFormat:@"%ldpt", (long)udInt(@"SpreadRowHeight",28)]
                         action:^(UITableViewCell *c, UIViewController *v){
                             numInput(@"行の高さ", @"SpreadRowHeight", 28, 20, 80);
                         }],
            [SettingRow toggle:@"自動保存" icon:@"internaldrive.fill" tint:green key:@"SpreadAutoSave" def:YES],
            [SettingRow toggle:@"自動計算" icon:@"function" tint:orange key:@"SpreadAutoCalc" def:YES],
        ]},

        // ── プライバシー ─────────────────────────────────────────────────────
        @{@"title": @"プライバシー",
          @"rows": @[
            [SettingRow toggle:@"デフォルトでプライベートモード" icon:@"eye.slash.fill" tint:red key:@"DefaultPrivate" def:NO],
            [SettingRow action:@"すべての設定をリセット"
                        icon:@"arrow.counterclockwise" tint:red
                       action:^(UITableViewCell *c, UIViewController *v){
                           UIAlertController *a = [UIAlertController
                               alertControllerWithTitle:@"設定をリセット"
                               message:@"すべてデフォルトに戻します。"
                               preferredStyle:UIAlertControllerStyleAlert];
                           [a addAction:[UIAlertAction actionWithTitle:@"リセット"
                               style:UIAlertActionStyleDestructive
                               handler:^(UIAlertAction *_){
                                   for (NSString *k in [[UD dictionaryRepresentation] allKeys])
                                       [UD removeObjectForKey:k];
                                   NOTIFY; [ws buildSections]; [ws.tableView reloadData];
                               }]];
                           [a addAction:[UIAlertAction actionWithTitle:@"キャンセル"
                               style:UIAlertActionStyleCancel handler:nil]];
                           [v presentViewController:a animated:YES completion:nil];
                       }],
        ]},

        // ── このアプリについて ────────────────────────────────────────────────
        @{@"title": @"このアプリについて",
          @"rows": @[
            [SettingRow info:@"バージョン"
                       icon:@"info.circle.fill" tint:blue
                     detail:[[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"]?:@"1.0"],
            [SettingRow info:@"ビルド"
                       icon:@"hammer.fill" tint:teal
                     detail:[[NSBundle mainBundle] infoDictionary][@"CFBundleVersion"]?:@"1"],
            [SettingRow disclosure:@"ライセンス"
                           icon:@"doc.plaintext.fill" tint:indigo
                         detail:nil
                         action:^(UITableViewCell *c, UIViewController *v){ [ws showLicenses]; }],
        ]},

    ];
}

// ─── TableView DataSource/Delegate ────────────────────────────────────────────
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return (NSInteger)self.sections.count; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return self.sections[s][@"title"];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return [(NSArray *)self.sections[s][@"rows"] count];
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip { return 52; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"SCell";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cid];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [ThemeEngine textPrimary];
        cell.textLabel.font = [ThemeEngine fontBody];
        cell.detailTextLabel.textColor = [ThemeEngine textSecondary];
        cell.detailTextLabel.font = [ThemeEngine fontCaption];
        UIView *sel = [[UIView alloc] init];
        sel.backgroundColor = [[ThemeEngine accent] colorWithAlphaComponent:0.12];
        cell.selectedBackgroundView = sel;
    }
    cell.accessoryType  = UITableViewCellAccessoryNone;
    cell.accessoryView  = nil;
    cell.textLabel.textColor = [ThemeEngine textPrimary];

    SettingRow *row = self.sections[ip.section][@"rows"][ip.row];

    // Icon box
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
        configurationWithPointSize:14 weight:UIImageSymbolWeightMedium];
    UIImage *img = [UIImage systemImageNamed:row.icon withConfiguration:cfg];
    UIImageView *iconView = [[UIImageView alloc] initWithImage:img];
    iconView.tintColor = row.iconTint ?: [ThemeEngine accent];
    iconView.contentMode = UIViewContentModeCenter;
    UIView *iconBox = [[UIView alloc] initWithFrame:CGRectMake(0,0,32,32)];
    iconBox.backgroundColor = [row.iconTint colorWithAlphaComponent:0.15] ?: [[ThemeEngine accent] colorWithAlphaComponent:0.15];
    iconBox.layer.cornerRadius = 8;
    iconBox.layer.cornerCurve = kCACornerCurveContinuous;
    iconView.frame = CGRectMake(0,0,32,32);
    [iconBox addSubview:iconView];
    cell.imageView.image = nil;
    // Use a UIView wrapper as imageView (leftView workaround via indent)
    cell.indentationLevel = 0;

    // Build left accessory manually
    for (UIView *v in cell.contentView.subviews) {
        if ([v isKindOfClass:[UIView class]] && v != cell.textLabel && v != cell.detailTextLabel
            && v != cell.imageView) {
            if (v.tag == 9901) [v removeFromSuperview];
        }
    }
    iconBox.tag = 9901;
    iconBox.frame = CGRectMake(12, 10, 32, 32);
    [cell.contentView addSubview:iconBox];
    cell.textLabel.frame = CGRectMake(56, 0, cell.contentView.bounds.size.width - 56 - 80, 52);
    cell.imageView.image = nil;

    cell.textLabel.text = row.title;

    switch (row.type) {
        case RowTypeToggle: {
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = udBool(row.udKey, row.udDefault);
            sw.onTintColor = [ThemeEngine accent];
            sw.accessibilityIdentifier = row.udKey;
            [sw addTarget:self action:@selector(switchToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        case RowTypeDisclosure:
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.detailTextLabel.text = row.detail;
            break;
        case RowTypeInfo:
            cell.detailTextLabel.text = row.detail;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        case RowTypeAction:
            cell.textLabel.textColor = (row.iconTint == [UIColor systemRedColor])
                ? [UIColor systemRedColor] : [ThemeEngine textPrimary];
            break;
        default: break;
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    SettingRow *row = self.sections[ip.section][@"rows"][ip.row];
    if (row.action) {
        row.action([tv cellForRowAtIndexPath:ip], self);
    }
}

- (void)switchToggled:(UISwitch *)sw {
    [UD setBool:sw.isOn forKey:sw.accessibilityIdentifier];
    NOTIFY;
}

// ─── Licenses ─────────────────────────────────────────────────────────────────
- (void)showLicenses {
    UIViewController *vc = [[UIViewController alloc] init];
    vc.title = @"ライセンス";
    vc.view.backgroundColor = [ThemeEngine bg];
    UITextView *tv = [[UITextView alloc] init];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.text = @"MIT License\n\nCopyright (c) 2024 Frappe Project\n\n"
              @"idevice library — Apache 2.0 (jkcoxson)\n"
              @"miniz — MIT License\n"
              @"libplist — LGPL-2.1\n";
    tv.backgroundColor = [UIColor clearColor];
    tv.textColor = [ThemeEngine textSecondary];
    tv.font = [ThemeEngine fontMono];
    tv.editable = NO;
    [vc.view addSubview:tv];
    [NSLayoutConstraint activateConstraints:@[
        [tv.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor constant:16],
        [tv.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor constant:16],
        [tv.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor constant:-16],
        [tv.bottomAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.bottomAnchor constant:-16],
    ]];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
