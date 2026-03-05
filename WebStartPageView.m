#import "WebStartPageView.h"
#import "WebBookmarksManager.h"
#import "ThemeEngine.h"

@interface WebStartPageView () <UICollectionViewDelegate, UICollectionViewDataSource, UISearchBarDelegate>
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UICollectionView *collectionView;
@end

@implementation WebStartPageView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [ThemeEngine mainBackgroundColor];
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
    self.searchBar.placeholder = @"検索またはURLを入力";
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.delegate = self;
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.searchBar];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.itemSize = CGSizeMake(80, 100);
    layout.minimumInteritemSpacing = 20;
    layout.minimumLineSpacing = 20;
    layout.sectionInset = UIEdgeInsetsMake(20, 20, 20, 20);

    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.backgroundColor = [UIColor clearColor];
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    [self.collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"Cell"];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.collectionView];

    [NSLayoutConstraint activateConstraints:@[
        [self.searchBar.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:40],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],

        [self.collectionView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:20],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];
}

- (void)reloadBookmarks {
    [self.collectionView reloadData];
}

#pragma mark - UISearchBarDelegate

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    if (self.onSearch) self.onSearch(searchBar.text);
    [searchBar resignFirstResponder];
}

#pragma mark - UICollectionView

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return [WebBookmarksManager sharedManager].bookmarks.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"Cell" forIndexPath:indexPath];
    for (UIView *sub in cell.contentView.subviews) [sub removeFromSuperview];

    NSDictionary *bookmark = [WebBookmarksManager sharedManager].bookmarks[indexPath.item];

    UIView *iconView = [[UIView alloc] initWithFrame:CGRectMake(10, 0, 60, 60)];
    iconView.backgroundColor = [[ThemeEngine accentColor] colorWithAlphaComponent:0.8];
    iconView.layer.cornerRadius = 14;
    [cell.contentView addSubview:iconView];

    UILabel *iconLabel = [[UILabel alloc] initWithFrame:iconView.bounds];
    NSString *t = bookmark[@"title"] ?: @"W";
    iconLabel.text = t.length > 0 ? [[t substringToIndex:1] uppercaseString] : @"W";
    iconLabel.textColor = [UIColor whiteColor];
    iconLabel.textAlignment = NSTextAlignmentCenter;
    iconLabel.font = [UIFont boldSystemFontOfSize:24];
    [iconView addSubview:iconLabel];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 65, 80, 30)];
    titleLabel.text = bookmark[@"title"] ?: @"Untitled";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont systemFontOfSize:11];
    titleLabel.numberOfLines = 2;
    [cell.contentView addSubview:titleLabel];

    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (self.onBookmarkSelect) {
        self.onBookmarkSelect([WebBookmarksManager sharedManager].bookmarks[indexPath.item][@"url"]);
    }
}

@end
