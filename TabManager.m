#import "TabManager.h"
#import "WebBrowserViewController.h"

@implementation TabInfo
@end

@implementation TabGroup
- (instancetype)init {
    self = [super init];
    if (self) {
        _tabs = [NSMutableArray array];
    }
    return self;
}
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

- (TabGroup *)createGroupWithTitle:(NSString *)title {
    TabGroup *group = [[TabGroup alloc] init];
    group.title = title;
    [_groups addObject:group];
    return group;
}

- (void)addTab:(TabInfo *)tab toGroup:(TabGroup *)group {
    TabGroup *oldGroup = tab.group;
    if (oldGroup) {
        [oldGroup.tabs removeObject:tab];
        if (oldGroup.tabs.count == 0) {
            [_groups removeObject:oldGroup];
        }
    }
    tab.group = group;
    if (group) {
        [group.tabs addObject:tab];
    }
}

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

        TabGroup *group = removed.group;
        if (group) {
            [group.tabs removeObject:removed];
            if (group.tabs.count == 0) {
                [_groups removeObject:group];
            }
        }

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

- (void)removeGroup:(TabGroup *)group {
    if (!group) return;
    NSArray *tabsToRemove = [group.tabs copy];
    for (TabInfo *tab in tabsToRemove) {
        NSInteger idx = [_tabs indexOfObject:tab];
        if (idx != NSNotFound) {
            [self removeTabAtIndex:idx];
        }
    }
    [_groups removeObject:group];
}

- (TabInfo *)activeTab {
    if (_activeTabIndex >= 0 && _activeTabIndex < _tabs.count) {
        return _tabs[_activeTabIndex];
    }
    return nil;
}

@end
