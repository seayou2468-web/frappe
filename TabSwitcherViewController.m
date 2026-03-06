#import "TabSwitcherViewController.h"
#import "TabManager.h"
#import "ThemeEngine.h"
#import "CustomMenuView.h"
#import "MainContainerViewController.h"
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
        self.container.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.07];
        self.container.layer.cornerRadius = 24;
        self.container.layer.borderWidth = 1.0;
        self.container.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.18].CGColor;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 4);
        self.layer.shadowOpacity = 0.3;
        self.layer.shadowRadius = 8;
        self.layer.masksToBounds = NO;
        self.container.clipsToBounds = YES;
        [self.contentView addSubview:self.container];
        UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, 38)];
        header.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.05];
        [self.container addSubview:header];
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, frame.size.width-46, 38)];
        _titleLabel.textColor = [UIColor whiteColor];
        _titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
        [header addSubview:_titleLabel];
        _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_closeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
        _closeButton.tintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.45];
        _closeButton.frame = CGRectMake(frame.size.width-38, 0, 38, 38);
        [_closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [header addSubview:_closeButton];
        _previewImage = [[UIImageView alloc] initWithFrame:CGRectMake(0, 38, frame.size.width, frame.size.height-38)];
        _previewImage.contentMode = UIViewContentModeScaleAspectFill;
        _previewImage.clipsToBounds = YES;
        _previewImage.backgroundColor = [UIColor colorWithWhite:0.03 alpha:1.0];
        [self.container addSubview:_previewImage];
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLP:)];
        [self addGestureRecognizer:lp];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}
- (void)closeTapped { if (self.onClose) self.onClose(); }
- (void)handleLP:(UILongPressGestureRecognizer *)lp { if (lp.state == UIGestureRecognizerStateBegan && self.onLongPress) self.onLongPress(); }
- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self];
    if (pan.state == UIGestureRecognizerStateChanged) { if (translation.x < 0) self.container.transform = CGAffineTransformMakeTranslation(translation.x, 0); }
    else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        if (translation.x < -80) { [UIView animateWithDuration:0.2 animations:^{ self.container.transform = CGAffineTransformMakeTranslation(-self.bounds.size.width, 0); self.container.alpha = 0; } completion:^(BOOL finished) { if (self.onClose) self.onClose(); }]; }
        else { [UIView animateWithDuration:0.2 animations:^{ self.container.transform = CGAffineTransformIdentity; }]; }
    }
}
- (void)prepareForReuse { [super prepareForReuse]; self.container.transform = CGAffineTransformIdentity; self.container.alpha = 1.0; }
@end

@implementation TabSwitcherViewController {
    UICollectionView *_collectionView;
    NSMutableArray<TabInfo *> *_displayItems;
    TabGroup *_currentGroupScope;
    UIButton *_groupButton;
}

- (void)authenticateWithTab:(TabInfo *)tab completion:(void (^)(BOOL success))completion {
    if (tab.useFaceID) { LAContext *context = [[LAContext alloc] init]; [context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics localizedReason:@"認証が必要です" reply:^(BOOL success, NSError *error) { dispatch_async(dispatch_get_main_queue(), ^{ completion(success); }); }]; }
    else if (tab.password) { [self showPasswordPromptForItem:tab completion:completion]; }
    else { completion(YES); }
}

- (void)authenticateWithGroup:(TabGroup *)group completion:(void (^)(BOOL success))completion {
    if (group.useFaceID) { LAContext *context = [[LAContext alloc] init]; [context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics localizedReason:@"認証が必要です" reply:^(BOOL success, NSError *error) { dispatch_async(dispatch_get_main_queue(), ^{ completion(success); }); }]; }
    else if (group.password) { [self showPasswordPromptForItem:group completion:completion]; }
    else { completion(YES); }
}

- (void)showPasswordPromptForItem:(id)item completion:(void (^)(BOOL success))completion {
    NSString *storedPw = [item isKindOfClass:[TabInfo class]] ? ((TabInfo *)item).password : ((TabGroup *)item).password;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"パスワード入力" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) { textField.secureTextEntry = YES; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { completion([alert.textFields.firstObject.text isEqualToString:storedPw]); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { completion(NO); }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshUI) name:@"SettingsChanged" object:nil];
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
    [self updateDisplayItems];
    UIView *topBar = [[UIView alloc] init];
    topBar.translatesAutoresizingMaskIntoConstraints = NO;
    [ThemeEngine applyGlassStyleToView:topBar cornerRadius:0];
    [self.view addSubview:topBar];
    UIButton *plusBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    plusBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [plusBtn setImage:[UIImage systemImageNamed:@"plus"] forState:UIControlStateNormal];
    plusBtn.tintColor = [UIColor whiteColor];
    [plusBtn addTarget:self action:@selector(newTabTapped) forControlEvents:UIControlEventTouchUpInside];
    [topBar addSubview:plusBtn];
    _groupButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _groupButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_groupButton setTitle:@"メインタブ" forState:UIControlStateNormal];
    _groupButton.tintColor = [UIColor whiteColor];
    _groupButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [_groupButton addTarget:self action:@selector(groupSwitcherTapped) forControlEvents:UIControlEventTouchUpInside];
    [topBar addSubview:_groupButton];
    UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    doneBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [doneBtn setTitle:@"完了" forState:UIControlStateNormal];
    doneBtn.tintColor = [UIColor whiteColor];
    doneBtn.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [doneBtn addTarget:self action:@selector(doneTapped) forControlEvents:UIControlEventTouchUpInside];
    [topBar addSubview:doneBtn];
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    CGFloat screenWidth = 0;
    if (@available(iOS 13.0, *)) { for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) { if ([scene isKindOfClass:[UIWindowScene class]]) { screenWidth = ((UIWindowScene *)scene).screen.bounds.size.width; break; } } }
    if (screenWidth == 0) { #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        screenWidth = [UIScreen mainScreen].bounds.size.width;
        #pragma clang diagnostic pop
    }
    CGFloat w = (screenWidth - 48) / 2;
    layout.itemSize = CGSizeMake(w, w * 1.35);
    layout.sectionInset = UIEdgeInsetsMake(20, 16, 20, 16);
    layout.minimumInteritemSpacing = 16;
    layout.minimumLineSpacing = 22;
    _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    _collectionView.backgroundColor = [UIColor clearColor];
    _collectionView.delegate = self;
    _collectionView.dataSource = self;
    _collectionView.alwaysBounceVertical = YES;
    [_collectionView registerClass:[TabCell class] forCellWithReuseIdentifier:@"TabCell"];
    [self.view addSubview:_collectionView];
    [NSLayoutConstraint activateConstraints:@[
        [topBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [topBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [topBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [topBar.heightAnchor constraintEqualToConstant:60],
        [plusBtn.leadingAnchor constraintEqualToAnchor:topBar.leadingAnchor constant:15],
        [plusBtn.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor],
        [plusBtn.widthAnchor constraintEqualToConstant:50],
        [plusBtn.heightAnchor constraintEqualToConstant:50],
        [_groupButton.centerXAnchor constraintEqualToAnchor:topBar.centerXAnchor],
        [_groupButton.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor],
        [_groupButton.widthAnchor constraintEqualToConstant:160],
        [_groupButton.heightAnchor constraintEqualToConstant:50],
        [doneBtn.trailingAnchor constraintEqualToAnchor:topBar.trailingAnchor constant:-15],
        [doneBtn.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor],
        [doneBtn.widthAnchor constraintEqualToConstant:70],
        [doneBtn.heightAnchor constraintEqualToConstant:50],
        [_collectionView.topAnchor constraintEqualToAnchor:topBar.bottomAnchor],
        [_collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)doneTapped { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)groupSwitcherTapped {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"タブグループ"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"メインタブ" systemImage:@"tray.full" style:CustomMenuActionStyleDefault handler:^{ [self animateToGroupScope:nil]; }]];
    for (TabGroup *g in [TabManager sharedManager].groups) { [menu addAction:[CustomMenuAction actionWithTitle:g.title systemImage:@"folder" style:CustomMenuActionStyleDefault handler:^{ [self authenticateWithGroup:g completion:^(BOOL success) { if (success) [self animateToGroupScope:g]; }]; }]]; }
    if (_currentGroupScope) {
        [menu addAction:[CustomMenuAction actionWithTitle:@"名前変更" systemImage:@"pencil" style:CustomMenuActionStyleDefault handler:^{ [self showRenameGroupMenu:self->_currentGroupScope]; }]];
        [menu addAction:[CustomMenuAction actionWithTitle:@"セキュリティ" systemImage:@"lock" style:CustomMenuActionStyleDefault handler:^{ [self showSetSecurityMenu:self->_currentGroupScope]; }]];
        [menu addAction:[CustomMenuAction actionWithTitle:@"削除" systemImage:@"trash" style:CustomMenuActionStyleDestructive handler:^{ [[TabManager sharedManager] removeGroup:self->_currentGroupScope]; [self animateToGroupScope:nil]; }]];
    }
    [menu addAction:[CustomMenuAction actionWithTitle:@"新しいグループの作成" systemImage:@"plus.rectangle.on.folder" style:CustomMenuActionStyleDefault handler:^{ [self showCreateGroupMenu:nil]; }]];
    [menu showInView:self.view];
}

- (void)animateToGroupScope:(TabGroup *)group {
    if (group == _currentGroupScope) return;
    CATransition *transition = [CATransition animation];
    transition.duration = 0.3; transition.type = kCATransitionPush; transition.subtype = kCATransitionFromRight; transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [_collectionView.layer addAnimation:transition forKey:kCATransition];
    _currentGroupScope = group; [_groupButton setTitle:group ? group.title : @"メインタブ" forState:UIControlStateNormal]; [self updateDisplayItems]; [_collectionView reloadData];
}

- (void)updateDisplayItems {
    _displayItems = [NSMutableArray array];
    if (_currentGroupScope) { [_displayItems addObjectsFromArray:_currentGroupScope.tabs]; }
    else { for (TabInfo *tab in [TabManager sharedManager].tabs) { if (!tab.group) [_displayItems addObject:tab]; } }
}

- (void)newTabTapped {
    [[TabManager sharedManager] addNewTabWithType:TabTypeFileBrowser path:nil];
    TabInfo *newTab = [[TabManager sharedManager].tabs lastObject]; if (_currentGroupScope) { [[TabManager sharedManager] addTab:newTab toGroup:_currentGroupScope]; }
    [self updateDisplayItems]; [_collectionView reloadData];
    if (_displayItems.count > 0) { [_collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:_displayItems.count-1 inSection:0] atScrollPosition:UICollectionViewScrollPositionBottom animated:YES]; }
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section { return _displayItems.count; }

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    TabCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"TabCell" forIndexPath:indexPath];
    TabInfo *info = _displayItems[indexPath.item]; cell.titleLabel.text = info.title; cell.previewImage.image = info.screenshot;
    __weak typeof(self) weakSelf = self;
    cell.onClose = ^{ __strong typeof(weakSelf) strongSelf = weakSelf; if (!strongSelf) return; TabGroup *groupBefore = info.group; [[TabManager sharedManager] removeTabAtIndex:[[TabManager sharedManager].tabs indexOfObject:info]]; if (groupBefore && groupBefore.tabs.count == 0) { if (strongSelf->_currentGroupScope == groupBefore) [strongSelf animateToGroupScope:nil]; else { [strongSelf updateDisplayItems]; [strongSelf->_collectionView reloadData]; } } else { [strongSelf updateDisplayItems]; [strongSelf->_collectionView reloadData]; } };
    cell.onLongPress = ^{ [weakSelf showTabMenu:info]; }; return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    TabInfo *info = _displayItems[indexPath.item]; [self authenticateWithTab:info completion:^(BOOL success) { if (success) { if (self.onTabSelected) self.onTabSelected([[TabManager sharedManager].tabs indexOfObject:info]); } }];
}

- (void)showTabMenu:(TabInfo *)tab {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:tab.title];
    [menu addAction:[CustomMenuAction actionWithTitle:@"グループに移動" systemImage:@"folder.badge.plus" style:CustomMenuActionStyleDefault handler:^{ [self showAddToGroupMenu:tab]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"セキュリティ" systemImage:@"lock" style:CustomMenuActionStyleDefault handler:^{ [self showSetSecurityMenu:tab]; }]];
    if (tab.group) { [menu addAction:[CustomMenuAction actionWithTitle:@"グループ解除" systemImage:@"folder.badge.minus" style:CustomMenuActionStyleDefault handler:^{ [[TabManager sharedManager] addTab:tab toGroup:nil]; [self updateDisplayItems]; [self->_collectionView reloadData]; }]]; }
    [menu addAction:[CustomMenuAction actionWithTitle:@"削除" systemImage:@"trash" style:CustomMenuActionStyleDestructive handler:^{ [[TabManager sharedManager] removeTabAtIndex:[[TabManager sharedManager].tabs indexOfObject:tab]]; [self updateDisplayItems]; [self->_collectionView reloadData]; }]];
    [menu showInView:self.view];
}

- (void)showAddToGroupMenu:(TabInfo *)tab {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"グループ選択"];
    for (TabGroup *g in [TabManager sharedManager].groups) { if (g == tab.group) continue; [menu addAction:[CustomMenuAction actionWithTitle:g.title systemImage:@"folder" style:CustomMenuActionStyleDefault handler:^{ [[TabManager sharedManager] addTab:tab toGroup:g]; [self updateDisplayItems]; [self->_collectionView reloadData]; }]]; }
    [menu addAction:[CustomMenuAction actionWithTitle:@"新規グループ作成" systemImage:@"plus.rectangle.on.folder" style:CustomMenuActionStyleDefault handler:^{ [self showCreateGroupMenu:tab]; }]];
    [menu showInView:self.view];
}

- (void)showCreateGroupMenu:(TabInfo *)tab {
    [self showInputMenuWithTitle:@"新規グループ名" completion:^(NSString *name) { if (name.length == 0) name = @"無題"; TabGroup *g = [[TabManager sharedManager] createGroupWithTitle:name]; if (tab) { [[TabManager sharedManager] addTab:tab toGroup:g]; [self updateDisplayItems]; [self->_collectionView reloadData]; } else { [[TabManager sharedManager] addNewTabWithType:TabTypeFileBrowser path:nil]; [[TabManager sharedManager] addTab:[TabManager sharedManager].tabs.lastObject toGroup:g]; [self animateToGroupScope:g]; } }];
}

- (void)showRenameGroupMenu:(TabGroup *)group { [self showInputMenuWithTitle:@"新しい名前" completion:^(NSString *name) { if (name.length > 0) { group.title = name; [self->_groupButton setTitle:name forState:UIControlStateNormal]; } }]; }

- (void)showSetSecurityMenu:(id)item {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"セキュリティ設定"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"パスワードを設定" systemImage:@"key" style:CustomMenuActionStyleDefault handler:^{ [self showInputMenuWithTitle:@"パスワード" completion:^(NSString *pw) { if ([item isKindOfClass:[TabInfo class]]) { ((TabInfo *)item).password = (pw.length > 0) ? pw : nil; ((TabInfo *)item).useFaceID = NO; } else { ((TabGroup *)item).password = (pw.length > 0) ? pw : nil; ((TabGroup *)item).useFaceID = NO; } }]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"FaceIDを使用" systemImage:@"faceid" style:CustomMenuActionStyleDefault handler:^{ if ([item isKindOfClass:[TabInfo class]]) { ((TabInfo *)item).useFaceID = YES; ((TabInfo *)item).password = nil; } else { ((TabGroup *)item).useFaceID = YES; ((TabGroup *)item).password = nil; } }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"ロック解除" systemImage:@"lock.open" style:CustomMenuActionStyleDefault handler:^{ if ([item isKindOfClass:[TabInfo class]]) { ((TabInfo *)item).password = nil; ((TabInfo *)item).useFaceID = NO; } else { ((TabGroup *)item).password = nil; ((TabGroup *)item).useFaceID = NO; } }]];
    [menu showInView:self.view];
}

- (void)showInputMenuWithTitle:(NSString *)title completion:(void (^)(NSString *text))completion {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert]; [alert addTextFieldWithConfigurationHandler:nil];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { if (completion) completion(alert.textFields.firstObject.text); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { if (completion) completion(nil); }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)refreshUI { dispatch_async(dispatch_get_main_queue(), ^{ self.view.backgroundColor = [ThemeEngine mainBackgroundColor]; }); }

@end