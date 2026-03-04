#import <UIKit/UIKit.h>

typedef void (^ConsoleCommandHandler)(NSString *command);

@interface WebInspectorViewController : UIViewController
@property (nonatomic, copy) NSString *htmlSource;
@property (nonatomic, strong) NSMutableArray<NSString *> *consoleLogs;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *networkLogs;
@property (nonatomic, strong) NSDictionary *storageData;
@property (nonatomic, strong) NSArray<NSHTTPCookie *> *cookies;
@property (nonatomic, copy) ConsoleCommandHandler onCommand;
@end
