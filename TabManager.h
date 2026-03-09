#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>



typedef NS_ENUM(NSInteger, TabType) {
    TabTypeFileBrowser,
    TabTypeWebBrowser
};

@class TabGroup;
@interface TabInfo : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *currentPath;
@property (nonatomic, assign) TabType type;
@property (nonatomic, strong) UIImage *screenshot;
@property (nonatomic, strong) UIViewController *viewController;
@property (nonatomic, copy) NSString *password;
@property (nonatomic, assign) BOOL useFaceID;
@property (nonatomic, assign) TabGroup *group;
@end

@interface TabGroup : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSMutableArray<TabInfo *> *tabs;
@property (nonatomic, copy) NSString *password;
@property (nonatomic, assign) BOOL useFaceID;
@end
@interface TabManager : NSObject
+ (instancetype)sharedManager;
@property (nonatomic, strong, readonly) NSMutableArray<TabInfo *> *tabs;
@property (nonatomic, strong, readonly) NSMutableArray<TabGroup *> *groups;
@property (nonatomic, assign) NSInteger activeTabIndex;

- (TabGroup *)createGroupWithTitle:(NSString *)title;
- (void)addTab:(TabInfo *)tab toGroup:(TabGroup *)group;
- (void)addNewTabWithType:(TabType)type path:(NSString * )path;
- (void)removeTabAtIndex:(NSInteger)index;
- (void)removeGroup:(TabGroup *)group;
- (TabInfo * )activeTab;
@end

