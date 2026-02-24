// BottomMenuView.m
#import "BottomMenuView.h"

@implementation BottomMenuView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [[UIColor systemGray5Color] colorWithAlphaComponent:0.9];

        UIButton *favBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        favBtn.frame = CGRectMake(20, 5, 40, 40);
        [favBtn setTitle:@"★" forState:UIControlStateNormal];
        [favBtn addTarget:self action:@selector(favTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:favBtn];
    }
    return self;
}

- (void)favTapped {
    if (self.onFavoriteTapped) {
        self.onFavoriteTapped();
    }
}

@end