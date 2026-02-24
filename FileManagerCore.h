#import <Foundation/Foundation.h>

@interface FileItem : NSObject
@property (strong, nonatomic) NSString *name;
@property (strong, nonatomic) NSString *fullPath;
@property (assign, nonatomic) BOOL isDirectory;
@property (assign, nonatomic) BOOL isSymbolicLink;
@property (strong, nonatomic) NSString *linkTarget;
@property (strong, nonatomic) NSDictionary *attributes;
@end

@interface FileManagerCore : NSObject

+ (instancetype)sharedManager;

- (NSArray<FileItem *> *)contentsOfDirectoryAtPath:(NSString *)path;
- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)moveItemAtPath:(NSString *)src toPath:(NSString *)dst error:(NSError **)error;
- (BOOL)copyItemAtPath:(NSString *)src toPath:(NSString *)dst error:(NSError **)error;
- (BOOL)createDirectoryAtPath:(NSString *)path error:(NSError **)error;
- (NSArray<FileItem *> *)searchFilesWithKeyword:(NSString *)keyword inPath:(NSString *)path;

@end
