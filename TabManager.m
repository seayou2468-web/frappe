#import "TabManager.h"
#import "WebBrowserViewController.h"



@implementation TabInfo
@end
@implementation TabGroup
- (instancetype)init { self = [super init]; if (self) { _tabs = [NSMutableArray array]; } return self; }
@end

@implementation TabManager

+ (instancetype)sharedManager {
    static TabManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[TabManager alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _tabs = [[NSMutableArray alloc] init];
        _groups = [[NSMutableArray alloc] init];
        _activeTabIndex = -1;
    }
    return self;
}

- (void)createGroupWithTitle:(NSString *)title { TabGroup *group = [[TabGroup alloc] init]; group.title = title; [_groups addObject:group]; }
- (void)addTab:(TabInfo *)tab toGroup:(TabGroup *)group { if (tab.group) { [tab.group.tabs removeObject:tab]; } tab.group = group; [group.tabs addObject:tab]; }
- (void)addNewTabWithType:(TabType)type path:(NSString *)path {
    TabInfo *tab = [[TabInfo alloc] init];
    tab.type = type;
    tab.currentPath = path ?: @"/";

    switch (type) {
        case TabTypeFileBrowser: tab.title = [path lastPathComponent] ?: @"Files"; break;
        case TabTypeWebBrowser: tab.title = @"Browser"; break;
    }

    [_tabs addObject:tab];
    self.activeTabIndex = _tabs.count - 1;
}

- (void)removeTabAtIndex:(NSInteger)index {
    if (index < _tabs.count) {
        TabInfo *removed = _tabs[index];
        removed.viewController = nil;
        [_tabs removeObjectAtIndex:index];

        // Check if any browser tabs remain
        BOOL hasBrowserTabs = NO;
        for (TabInfo *tab in _tabs) {
            if (tab.type == TabTypeWebBrowser) {
                hasBrowserTabs = YES;
                break;
            }
        }
        if (!hasBrowserTabs) {
            [WebBrowserViewController resetSharedDataStore];
        }

        if (self.activeTabIndex >= _tabs.count) {
            self.activeTabIndex = _tabs.count - 1;
        }
    }
}

- (TabInfo *)activeTab {
    if (_activeTabIndex >= 0 && _activeTabIndex < _tabs.count) {
        return _tabs[_activeTabIndex];
    }
    return nil;
}

@end

