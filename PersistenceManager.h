#import <Foundation/Foundation.h>

@interface PersistenceManager : NSObject
+ (instancetype)sharedManager;
@property (nonatomic, strong, readonly) NSArray<NSString *> *persistentDomains;
- (void)addDomain:(NSString *)domain;
- (void)removeDomain:(NSString *)domain;
- (BOOL)isDomainPersistent:(NSString *)domain;
@end
