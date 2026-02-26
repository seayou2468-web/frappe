#import "FileManagerCore.h"

@implementation FileItem

@end

@implementation FileManagerCore

+ (instancetype)sharedManager {
    static FileManagerCore *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[FileManagerCore alloc] init];
    });
    return shared;
}

- (NSArray<FileItem *> *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *contents = [fm contentsOfDirectoryAtPath:path error:error];
    if (*error) return @[];

    NSMutableArray *items = [NSMutableArray array];
    for (NSString *name in contents) {
        NSString *fullPath = [path stringByAppendingPathComponent:name];
        FileItem *item = [[FileItem alloc] init];
        item.name = name;
        item.fullPath = fullPath;
        NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
        item.attributes = attrs;
        item.isDirectory = [[attrs fileType] isEqualToString:NSFileTypeDirectory];
        item.isSymbolicLink = [[attrs fileType] isEqualToString:NSFileTypeSymbolicLink];
        if (item.isSymbolicLink) item.linkTarget = [fm destinationOfSymbolicLinkAtPath:fullPath error:nil];
        if (item.isDirectory) item.isLocked = ![fm isReadableFileAtPath:fullPath];
        [items addObject:item];
    }
    return [items sortedArrayUsingComparator:^NSComparisonResult(FileItem *obj1, FileItem *obj2) {
        if (obj1.isDirectory != obj2.isDirectory) return obj1.isDirectory ? NSOrderedAscending : NSOrderedDescending;
        return [obj1.name compare:obj2.name options:NSCaseInsensitiveSearch];
    }];
}

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error {
    return [[NSFileManager defaultManager] removeItemAtPath:path error:error];
}

- (BOOL)copyItemAtPath:(NSString *)src toPath:(NSString *)dest error:(NSError **)error {
    return [[NSFileManager defaultManager] copyItemAtPath:src toPath:dest error:error];
}

- (BOOL)createSymbolicLinkAtPath:(NSString *)path withDestinationPath:(NSString *)dest error:(NSError **)error {
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    return [[NSFileManager defaultManager] createSymbolicLinkAtPath:path withDestinationPath:dest error:error];
}

- (NSArray<FileItem *> *)searchFilesWithQuery:(NSString *)query inPath:(NSString *)path recursive:(BOOL)recursive {
    NSMutableArray *results = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (recursive) {
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtURL:[NSURL fileURLWithPath:path] includingPropertiesForKeys:nil options:0 errorHandler:^BOOL(NSURL *url, NSError *error) { return YES; }];
        for (NSURL *url in enumerator) {
            if ([url.lastPathComponent.lowercaseString containsString:query.lowercaseString]) {
                FileItem *item = [[FileItem alloc] init];
                item.name = url.lastPathComponent;
                item.fullPath = url.path;
                NSDictionary *attrs = [fm attributesOfItemAtPath:url.path error:nil];
                item.isDirectory = [[attrs fileType] isEqualToString:NSFileTypeDirectory];
                item.isSymbolicLink = [[attrs fileType] isEqualToString:NSFileTypeSymbolicLink];
                if (item.isSymbolicLink) item.linkTarget = [fm destinationOfSymbolicLinkAtPath:url.path error:nil];
                [results addObject:item];
            }
        }
    } else {
        NSError *err = nil;
        for (FileItem *item in [self contentsOfDirectoryAtPath:path error:&err]) {
            if ([item.name.lowercaseString containsString:query.lowercaseString]) [results addObject:item];
        }
    }
    return results;
}

@end