#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, TabType) {
    TabTypeFileBrowser
};

@interface TabInfo : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *currentPath;
@property (nonatomic, assign) TabType type;
@property (nonatomic, strong) UIImage *screenshot;
@end

@interface TabManager : NSObject
+ (instancetype)sharedManager;
@property (nonatomic, strong, readonly) NSMutableArray<TabInfo *> *tabs;
@property (nonatomic, assign) NSInteger activeTabIndex;

- (void)addNewTabWithType:(TabType)type path:(NSString *)path;
- (void)removeTabAtIndex:(NSInteger)index;
- (TabInfo *)activeTab;
@end
