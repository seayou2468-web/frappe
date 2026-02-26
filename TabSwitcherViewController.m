#import "TabSwitcherViewController.h"
#import "TabManager.h"
#import "ThemeEngine.h"

@interface TabCell : UICollectionViewCell
@property (nonatomic, strong) UIView *container;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *previewImage;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, copy) void (^onClose)(void);
@end

@implementation TabCell
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _container = [[UIView alloc] initWithFrame:self.bounds];
        _container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [ThemeEngine applyLiquidGlassStyleToView:_container cornerRadius:24];
        [self.contentView addSubview:_container];

        _previewImage = [[UIImageView alloc] initWithFrame:CGRectMake(10, 45, frame.size.width-20, frame.size.height-60)];
        _previewImage.contentMode = UIViewContentModeScaleAspectFill;
        _previewImage.clipsToBounds = YES;
        _previewImage.layer.cornerRadius = 16;
        _previewImage.backgroundColor = [UIColor blackColor];
        [_container addSubview:_previewImage];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 12, frame.size.width-60, 25)];
        _titleLabel.textColor = [UIColor whiteColor];
        _titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [_container addSubview:_titleLabel];

        _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_closeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
        _closeButton.tintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
        _closeButton.frame = CGRectMake(frame.size.width-40, 10, 30, 30);
        [_closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [_container addSubview:_closeButton];
    }
    return self;
}
- (void)closeTapped { if (self.onClose) self.onClose(); }
@end

@implementation TabSwitcherViewController {
    UICollectionView *_collectionView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.itemSize = CGSizeMake(self.view.bounds.size.width/2 - 25, 260);
    layout.sectionInset = UIEdgeInsetsMake(60, 20, 100, 20);
    layout.minimumInteritemSpacing = 10;
    layout.minimumLineSpacing = 20;

    _collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    _collectionView.backgroundColor = [UIColor clearColor];
    _collectionView.delegate = self;
    _collectionView.dataSource = self;
    [_collectionView registerClass:[TabCell class] forCellWithReuseIdentifier:@"TabCell"];
    [self.view addSubview:_collectionView];

    UIButton *plusBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [plusBtn setImage:[UIImage systemImageNamed:@"plus"] forState:UIControlStateNormal];
    plusBtn.tintColor = [UIColor whiteColor];
    plusBtn.layer.cornerRadius = 30;
    [ThemeEngine applyLiquidGlassStyleToView:plusBtn cornerRadius:30];
    plusBtn.frame = CGRectMake(self.view.bounds.size.width/2 - 30, self.view.bounds.size.height - 120, 60, 60);
    [plusBtn addTarget:self action:@selector(newTabTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:plusBtn];

    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, 200, 40)];
    header.text = @"Tabs";
    header.textColor = [UIColor whiteColor];
    header.font = [UIFont systemFontOfSize:32 weight:UIFontWeightBold];
    [self.view addSubview:header];
}

- (void)newTabTapped { if (self.onNewTabRequested) self.onNewTabRequested(); }

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return [TabManager sharedManager].tabs.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    TabCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"TabCell" forIndexPath:indexPath];
    TabInfo *info = [TabManager sharedManager].tabs[indexPath.item];
    cell.titleLabel.text = info.title;
    cell.previewImage.image = info.screenshot;
    cell.onClose = ^{
        [[TabManager sharedManager] removeTabAtIndex:indexPath.item];
        [collectionView reloadData];
    };
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (self.onTabSelected) self.onTabSelected(indexPath.item);
}

@end
