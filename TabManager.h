#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TabType) {
    TabTypeFileBrowser
};

@interface TabInfo : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *currentPath;
@property (nonatomic, assign) TabType type;
@property (nonatomic, strong, _Nullable) UIImage *screenshot;
@end

@interface TabManager : NSObject
+ (instancetype)sharedManager;
@property (nonatomic, strong, readonly) NSMutableArray<TabInfo *> *tabs;
@property (nonatomic, assign) NSInteger activeTabIndex;

- (void)addNewTabWithType:(TabType)type path:(NSString * _Nullable)path;
- (void)removeTabAtIndex:(NSInteger)index;
- (TabInfo * _Nullable)activeTab;
@end

NS_ASSUME_NONNULL_END
