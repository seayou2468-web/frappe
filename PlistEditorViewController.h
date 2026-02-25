#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PlistEditorViewController : UIViewController

- (instancetype)initWithPath:(NSString * _Nullable)path;
- (instancetype)initWithValue:(id)value key:(NSString * _Nullable)key root:(id)root undo:(NSUndoManager *)undo;

@end

NS_ASSUME_NONNULL_END
