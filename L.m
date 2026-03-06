
#import "L.h"

@implementation L
+ (NSString *)s:(NSString *)jp en:(NSString *)en {
    NSString *lang = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppLanguage"];
    if ([lang isEqualToString:@"English"]) return en;
    return jp;
}
@end
