// File: PlistViewer.h
// Location: プロジェクト直下

#import <UIKit/UIKit.h>

@interface PlistViewer : UIViewController <UITableViewDelegate, UITableViewDataSource>

- (instancetype)initWithPlistPath:(NSString *)path;
- (instancetype)initWithPlistObject:(id)obj title:(NSString *)title parentPath:(NSString *)path;

@end