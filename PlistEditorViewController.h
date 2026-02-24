#import <UIKit/UIKit.h>

@interface PlistEditorViewController : UIViewController

- (instancetype)initWithPath:(NSString *)path;
- (instancetype)initWithValue:(id)value key:(NSString *)key root:(id)root;

@end
