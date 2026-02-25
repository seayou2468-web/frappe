#import "TabManager.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TabInfo
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
        _activeTabIndex = -1;
    }
    return self;
}

- (void)addNewTabWithType:(TabType)type path:(NSString *)path {
    TabInfo *tab = [[TabInfo alloc] init];
    tab.type = type;
    tab.currentPath = path ?: @"/";

    switch (type) {
        case TabTypeFileBrowser: tab.title = [path lastPathComponent] ?: @"Files"; break;
    }

    [_tabs addObject:tab];
    self.activeTabIndex = _tabs.count - 1;
}

- (void)removeTabAtIndex:(NSInteger)index {
    if (index < _tabs.count) {
        [_tabs removeObjectAtIndex:index];
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

NS_ASSUME_NONNULL_END
