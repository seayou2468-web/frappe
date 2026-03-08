#import "L.h"

@implementation L

+ (NSString *)s:(NSString *)jp en:(NSString *)en {
    NSString *lang = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppLanguage"];
    if ([lang isEqualToString:@"en"]) {
        return en;
    }
    return jp;
}

@end
