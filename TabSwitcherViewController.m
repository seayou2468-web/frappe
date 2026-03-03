#import "TabSwitcherViewController.h"
#import "TabManager.h"
#import "ThemeEngine.h"
#import "CustomMenuView.h"
#import <LocalAuthentication/LocalAuthentication.h>

@interface TabCell : UICollectionViewCell
@property (nonatomic, strong) UIView *container;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *previewImage;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, copy) void (^onClose)(void);
@property (nonatomic, copy) void (^onLongPress)(void);
@end

@implementation TabCell
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.container = [[UIView alloc] initWithFrame:self.bounds];
        self.container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.container.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
        self.container.layer.cornerRadius = 16;
        self.container.clipsToBounds = YES;
        [self.contentView addSubview:self.container];

        UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, 34)];
        header.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.05];
        [self.container addSubview:header];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, frame.size.width-44, 34)];
        _titleLabel.textColor = [UIColor whiteColor];
        _titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        [header addSubview:_titleLabel];

        _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_closeButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
        _closeButton.tintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
        _closeButton.frame = CGRectMake(frame.size.width-34, 0, 34, 34);
        [_closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [header addSubview:_closeButton];

        _previewImage = [[UIImageView alloc] initWithFrame:CGRectMake(0, 34, frame.size.width, frame.size.height-34)];
        _previewImage.contentMode = UIViewContentModeScaleAspectFill;
        _previewImage.clipsToBounds = YES;
        _previewImage.backgroundColor = [UIColor blackColor];
        [self.container addSubview:_previewImage];

        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLP:)];
        [self addGestureRecognizer:lp];

        UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
        swipe.direction = UISwipeGestureRecognizerDirectionLeft;
        [self addGestureRecognizer:swipe];
    }
    return self;
}
- (void)closeTapped { if (self.onClose) self.onClose(); }
- (void)handleLP:(UILongPressGestureRecognizer *)lp {
    if (lp.state == UIGestureRecognizerStateBegan && self.onLongPress) self.onLongPress();
}
- (void)handleSwipe:(UISwipeGestureRecognizer *)swipe {
    if (swipe.state == UIGestureRecognizerStateRecognized && self.onClose) self.onClose();
}
@end

@implementation TabSwitcherViewController {
    UICollectionView *_collectionView;
    NSMutableArray *_displayItems;
}

- (void)authenticateWithTab:(TabInfo *)tab completion:(void (^)(BOOL success))completion {
    if (!tab.password && !tab.useFaceID) { completion(YES); return; }
    if (tab.useFaceID) {
        LAContext *context = [[LAContext alloc] init];
        [context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics localizedReason:@"認証が必要です" reply:^(BOOL success, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(success); });
        }];
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"パスワード入力" message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) { textField.secureTextEntry = YES; }];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            completion([alert.textFields.firstObject.text isEqualToString:tab.password]);
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { completion(NO); }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)authenticateWithGroup:(TabGroup *)group completion:(void (^)(BOOL success))completion {
    if (!group.password && !group.useFaceID) { completion(YES); return; }
    if (group.useFaceID) {
        LAContext *context = [[LAContext alloc] init];
        [context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics localizedReason:@"認証が必要です" reply:^(BOOL success, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(success); });
        }];
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"グループパスワード入力" message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) { textField.secureTextEntry = YES; }];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            completion([alert.textFields.firstObject.text isEqualToString:group.password]);
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { completion(NO); }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
    [self updateDisplayItems];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    CGFloat w = (self.view.bounds.size.width - 45) / 2;
    layout.itemSize = CGSizeMake(w, w * 1.3);
    layout.sectionInset = UIEdgeInsetsMake(20, 15, 100, 15);
    layout.minimumInteritemSpacing = 15;
    layout.minimumLineSpacing = 20;

    _collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    _collectionView.backgroundColor = [UIColor clearColor];
    _collectionView.delegate = self;
    _collectionView.dataSource = self;
    _collectionView.alwaysBounceVertical = YES;
    [_collectionView registerClass:[TabCell class] forCellWithReuseIdentifier:@"TabCell"];
    [self.view addSubview:_collectionView];

    UIView *bottomBar = [[UIView alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height-80, self.view.bounds.size.width, 80)];
    [ThemeEngine applyGlassStyleToView:bottomBar cornerRadius:0];
    [self.view addSubview:bottomBar];

    UIButton *plusBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [plusBtn setImage:[UIImage systemImageNamed:@"plus"] forState:UIControlStateNormal];
    plusBtn.tintColor = [UIColor whiteColor];
    plusBtn.frame = CGRectMake(self.view.bounds.size.width/2 - 25, 10, 50, 50);
    [plusBtn addTarget:self action:@selector(newTabTapped) forControlEvents:UIControlEventTouchUpInside];
    [bottomBar addSubview:plusBtn];

    UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [doneBtn setTitle:@"完了" forState:UIControlStateNormal];
    doneBtn.tintColor = [UIColor whiteColor];
    doneBtn.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    doneBtn.frame = CGRectMake(self.view.bounds.size.width - 80, 10, 70, 50);
    [doneBtn addTarget:self action:@selector(doneTapped) forControlEvents:UIControlEventTouchUpInside];
    [bottomBar addSubview:doneBtn];
}

- (void)doneTapped { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)updateDisplayItems {
    _displayItems = [NSMutableArray array];
    [_displayItems addObjectsFromArray:[TabManager sharedManager].groups];
    for (TabInfo *tab in [TabManager sharedManager].tabs) {
        if (!tab.group) [_displayItems addObject:tab];
    }
}

- (void)showInputMenuWithTitle:(NSString *)title completion:(void (^)(NSString *text))completion {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:nil];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (completion) completion(alert.textFields.firstObject.text);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)newTabTapped { if (self.onNewTabRequested) self.onNewTabRequested(); }

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return _displayItems.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    TabCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"TabCell" forIndexPath:indexPath];
    id item = _displayItems[indexPath.item];

    if ([item isKindOfClass:[TabGroup class]]) {
        TabGroup *group = (TabGroup *)item;
        cell.titleLabel.text = [NSString stringWithFormat:@"%@ (%lu)", group.title, (unsigned long)group.tabs.count];
        cell.previewImage.image = (group.tabs.count > 0) ? group.tabs.firstObject.screenshot : nil;
        cell.onClose = ^{
            [[TabManager sharedManager].groups removeObject:group];
            [self updateDisplayItems];
            [collectionView reloadData];
        };
        cell.onLongPress = ^{ [self showGroupMenu:group]; };
    } else {
        TabInfo *info = (TabInfo *)item;
        cell.titleLabel.text = info.title;
        cell.previewImage.image = info.screenshot;
        cell.onClose = ^{
            [[TabManager sharedManager] removeTabAtIndex:[[TabManager sharedManager].tabs indexOfObject:info]];
            [self updateDisplayItems];
            [collectionView reloadData];
        };
        cell.onLongPress = ^{ [self showTabMenu:info]; };
    }
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    id item = _displayItems[indexPath.item];
    NSInteger idx = -1;
    if ([item isKindOfClass:[TabGroup class]]) {
        TabGroup *group = (TabGroup *)item;
        if (group.tabs.count > 0) idx = [[TabManager sharedManager].tabs indexOfObject:group.tabs.firstObject];
    } else {
        idx = [[TabManager sharedManager].tabs indexOfObject:item];
    }

    if (idx != -1) {
        TabInfo *info = ([item isKindOfClass:[TabGroup class]] && ((TabGroup *)item).tabs.count > 0) ? ((TabGroup *)item).tabs.firstObject : (TabInfo *)item;
        [self authenticateWithTab:info completion:^(BOOL success) {
            if (success) {
                if (info.group) {
                    [self authenticateWithGroup:info.group completion:^(BOOL gSuccess) {
                        if (gSuccess && self.onTabSelected) self.onTabSelected(idx);
                    }];
                } else if (self.onTabSelected) {
                    self.onTabSelected(idx);
                }
            }
        }];
    }
}

- (void)showTabMenu:(TabInfo *)tab {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:tab.title];
    [menu addAction:[CustomMenuAction actionWithTitle:@"グループに追加" systemImage:@"folder.badge.plus" style:CustomMenuActionStyleDefault handler:^{
        [self showAddToGroupMenu:tab];
    }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"パスワード設定" systemImage:@"lock" style:CustomMenuActionStyleDefault handler:^{
        [self showSetPasswordMenu:tab];
    }]];
    if (tab.group) {
        [menu addAction:[CustomMenuAction actionWithTitle:@"グループから削除" systemImage:@"folder.badge.minus" style:CustomMenuActionStyleDefault handler:^{
            [tab.group.tabs removeObject:tab];
            tab.group = nil;
            [self updateDisplayItems];
            [_collectionView reloadData];
        }]];
    }
    [menu addAction:[CustomMenuAction actionWithTitle:@"削除" systemImage:@"trash" style:CustomMenuActionStyleDestructive handler:^{
        [[TabManager sharedManager] removeTabAtIndex:[[TabManager sharedManager].tabs indexOfObject:tab]];
        [self updateDisplayItems];
        [_collectionView reloadData];
    }]];
    [menu showInView:self.view];
}

- (void)showGroupMenu:(TabGroup *)group {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:group.title];
    [menu addAction:[CustomMenuAction actionWithTitle:@"名前を変更" systemImage:@"pencil" style:CustomMenuActionStyleDefault handler:^{
        [self showRenameGroupMenu:group];
    }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"パスワード設定" systemImage:@"lock" style:CustomMenuActionStyleDefault handler:^{
        [self showSetPasswordMenu:group];
    }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"グループ解除" systemImage:@"folder.badge.minus" style:CustomMenuActionStyleDefault handler:^{
        for (TabInfo *t in group.tabs) t.group = nil;
        [[TabManager sharedManager].groups removeObject:group];
        [self updateDisplayItems];
        [_collectionView reloadData];
    }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"削除" systemImage:@"trash" style:CustomMenuActionStyleDestructive handler:^{
        [[TabManager sharedManager].groups removeObject:group];
        [self updateDisplayItems];
        [_collectionView reloadData];
    }]];
    [menu showInView:self.view];
}

- (void)showAddToGroupMenu:(TabInfo *)tab {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"グループ選択"];
    for (TabGroup *g in [TabManager sharedManager].groups) {
        [menu addAction:[CustomMenuAction actionWithTitle:g.title systemImage:@"folder" style:CustomMenuActionStyleDefault handler:^{
            [[TabManager sharedManager] addTab:tab toGroup:g];
            [self updateDisplayItems];
            [_collectionView reloadData];
        }]];
    }
    [menu addAction:[CustomMenuAction actionWithTitle:@"新規グループ作成" systemImage:@"plus.rectangle.on.folder" style:CustomMenuActionStyleDefault handler:^{
        [self showCreateGroupMenu:tab];
    }]];
    [menu showInView:self.view];
}

- (void)showCreateGroupMenu:(TabInfo *)tab {
    [self showInputMenuWithTitle:@"新規グループ名" completion:^(NSString *name) {
        if (name.length == 0) name = @"無題";
        [[TabManager sharedManager] createGroupWithTitle:name];
        TabGroup *g = [TabManager sharedManager].groups.lastObject;
        [[TabManager sharedManager] addTab:tab toGroup:g];
        [self updateDisplayItems];
        [_collectionView reloadData];
    }];
}

- (void)showRenameGroupMenu:(TabGroup *)group {
    [self showInputMenuWithTitle:@"新しい名前" completion:^(NSString *name) {
        if (name.length > 0) group.title = name;
        [self updateDisplayItems];
        [_collectionView reloadData];
    }];
}

- (void)showSetPasswordMenu:(id)item {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"セキュリティ設定"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"パスワードを設定" systemImage:@"key" style:CustomMenuActionStyleDefault handler:^{
        [self showInputMenuWithTitle:@"パスワード" completion:^(NSString *pw) {
            if (pw.length == 0) pw = nil;
            if ([item isKindOfClass:[TabInfo class]]) ((TabInfo *)item).password = pw;
            else if ([item isKindOfClass:[TabGroup class]]) ((TabGroup *)item).password = pw;
        }];
    }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"FaceIDを使用" systemImage:@"faceid" style:CustomMenuActionStyleDefault handler:^{
        if ([item isKindOfClass:[TabInfo class]]) ((TabInfo *)item).useFaceID = YES;
        else if ([item isKindOfClass:[TabGroup class]]) ((TabGroup *)item).useFaceID = YES;
    }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"ロック解除" systemImage:@"lock.open" style:CustomMenuActionStyleDefault handler:^{
        if ([item isKindOfClass:[TabInfo class]]) { ((TabInfo *)item).password = nil; ((TabInfo *)item).useFaceID = NO; }
        else if ([item isKindOfClass:[TabGroup class]]) { ((TabGroup *)item).password = nil; ((TabGroup *)item).useFaceID = NO; }
    }]];
    [menu showInView:self.view];
}

@end
