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

- (NSArray<FileItem *> *)contentsOfDirectoryAtPath:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error;
    NSArray *contents = [fm contentsOfDirectoryAtPath:path error:&error];

    if (error) {
        // Handle inaccessible directory by returning a single item or specific state if desired
        // but for now we just return empty as per user request
        return @[];
    }

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

        if (item.isSymbolicLink) {
            item.linkTarget = [fm destinationOfSymbolicLinkAtPath:fullPath error:nil];
        }

        // Check if locked (can't read contents)
        if (item.isDirectory) {
            item.isLocked = ![fm isReadableFileAtPath:fullPath];
        }

        [items addObject:item];
    }

    return [items sortedArrayUsingComparator:^NSComparisonResult(FileItem *obj1, FileItem *obj2) {
        if (obj1.isDirectory != obj2.isDirectory) {
            return obj1.isDirectory ? NSOrderedAscending : NSOrderedDescending;
        }
        return [obj1.name compare:obj2.name options:NSCaseInsensitiveSearch];
    }];
}

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error {
    return [[NSFileManager defaultManager] removeItemAtPath:path error:error];
}

- (BOOL)copyItemAtPath:(NSString *)src toPath:(NSString *)dest error:(NSError **)error {
    return [[NSFileManager defaultManager] copyItemAtPath:src toPath:dest error:error];
}

- (NSArray<FileItem *> *)searchFilesWithQuery:(NSString *)query inPath:(NSString *)path recursive:(BOOL)recursive {
    NSMutableArray *results = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSDirectoryEnumerator *enumerator;
    if (recursive) {
        enumerator = [fm enumeratorAtURL:[NSURL fileURLWithPath:path] includingPropertiesForKeys:nil options:0 errorHandler:nil];
    } else {
        // Shallow search just in current dir contents
        for (FileItem *item in [self contentsOfDirectoryAtPath:path]) {
            if ([item.name.lowercaseString containsString:query.lowercaseString]) {
                [results addObject:item];
            }
        }
        return results;
    }

    for (NSURL *url in enumerator) {
        if ([url.lastPathComponent.lowercaseString containsString:query.lowercaseString]) {
            FileItem *item = [[FileItem alloc] init];
            item.name = url.lastPathComponent;
            item.fullPath = url.path;
            NSDictionary *attrs = [fm attributesOfItemAtPath:url.path error:nil];
            item.isDirectory = [[attrs fileType] isEqualToString:NSFileTypeDirectory];
            [results addObject:item];
        }
    }
    return results;
}

@end
