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

    if (error) return @[];

    NSMutableArray *items = [NSMutableArray arrayWithCapacity:contents.count];
    for (NSString *name in contents) {
        NSString *fullPath = [path stringByAppendingPathComponent:name];
        FileItem *item = [[FileItem alloc] init];
        item.name = name;
        item.fullPath = fullPath;

        NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
        item.attributes = attrs;
        NSString *fileType = [attrs fileType];
        item.isDirectory = [fileType isEqualToString:NSFileTypeDirectory];
        item.isSymbolicLink = [fileType isEqualToString:NSFileTypeSymbolicLink];

        if (item.isSymbolicLink) {
            item.linkTarget = [fm destinationOfSymbolicLinkAtPath:fullPath error:nil];
        }

        if (item.isDirectory) {
            item.isLocked = ![fm isReadableFileAtPath:fullPath];
        }
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
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
    return [[NSFileManager defaultManager] createSymbolicLinkAtPath:path withDestinationPath:dest error:error];
}

- (NSArray<FileItem *> *)searchFilesWithQuery:(NSString *)query inPath:(NSString *)path recursive:(BOOL)recursive {
    if (!query || query.length == 0) return @[];

    NSMutableArray *results = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *lowerQuery = [query lowercaseString];

    if (recursive) {
        // Use faster URL-based enumerator with pre-fetching
        NSArray *keys = @[NSURLNameKey, NSURLIsDirectoryKey, NSURLIsSymbolicLinkKey];
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtURL:[NSURL fileURLWithPath:path]
                                     includingPropertiesForKeys:keys
                                                        options:NSDirectoryEnumerationSkipsHiddenFiles
                                                   errorHandler:^BOOL(NSURL *url, NSError *error) { return YES; }];

        for (NSURL *url in enumerator) {
            NSString *filename;
            [url getResourceValue:&filename forKey:NSURLNameKey error:nil];

            if ([filename.lowercaseString containsString:lowerQuery]) {
                FileItem *item = [[FileItem alloc] init];
                item.name = filename;
                item.fullPath = url.path;

                NSNumber *isDir;
                [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
                item.isDirectory = [isDir boolValue];

                NSNumber *isSym;
                [url getResourceValue:&isSym forKey:NSURLIsSymbolicLinkKey error:nil];
                item.isSymbolicLink = [isSym boolValue];

                if (item.isSymbolicLink) {
                    item.linkTarget = [fm destinationOfSymbolicLinkAtPath:url.path error:nil];
                }
                [results addObject:item];
            }
        }
    } else {
        NSArray *items = [self contentsOfDirectoryAtPath:path];
        for (FileItem *item in items) {
            if ([item.name.lowercaseString containsString:lowerQuery]) {
                [results addObject:item];
            }
        }
    }
    return results;
}

@end
