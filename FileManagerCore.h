#import <Foundation/Foundation.h>

@interface FileItem : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *fullPath;
@property (nonatomic, assign) BOOL isDirectory;
@property (nonatomic, assign) BOOL isSymbolicLink;
@property (nonatomic, copy) NSString *linkTarget;
@property (nonatomic, assign) BOOL isLocked;
@property (nonatomic, strong) NSDictionary *attributes;
@end

@interface FileManagerCore : NSObject
+ (instancetype)sharedManager;
- (NSArray<FileItem *> *)contentsOfDirectoryAtPath:(NSString *)path;
- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)copyItemAtPath:(NSString *)src toPath:(NSString *)dest error:(NSError **)error;
- (NSArray<FileItem *> *)searchFilesWithQuery:(NSString *)query inPath:(NSString *)path recursive:(BOOL)recursive;
@end
