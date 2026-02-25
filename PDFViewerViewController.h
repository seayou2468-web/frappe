#import <UIKit/UIKit.h>
#import <PDFKit/PDFKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface PDFViewerViewController : UIViewController
- (instancetype)initWithPath:(NSString *)path;
@end

NS_ASSUME_NONNULL_END
