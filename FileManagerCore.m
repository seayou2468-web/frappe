#import "FileManagerCore.h"
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>

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
    NSMutableArray<FileItem *> *items = [NSMutableArray array];
    DIR *dir = opendir([path UTF8String]);

    if (!dir) {
        // Access denied or not a directory - treat as empty as per requirements
        return @[];
    }

    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }

        NSString *name = [NSString stringWithUTF8String:entry->d_name];
        NSString *fullPath = [path stringByAppendingPathComponent:name];

        FileItem *item = [[FileItem alloc] init];
        item.name = name;
        item.fullPath = fullPath;

        struct stat st;
        if (lstat([fullPath UTF8String], &st) == 0) {
            item.isDirectory = S_ISDIR(st.st_mode);
            item.isSymbolicLink = S_ISLNK(st.st_mode);

            if (item.isSymbolicLink) {
                char buf[PATH_MAX];
                ssize_t len = readlink([fullPath UTF8String], buf, sizeof(buf)-1);
                if (len != -1) {
                    buf[len] = '\0';
                    item.linkTarget = [NSString stringWithUTF8String:buf];
                }
            }

            item.attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:fullPath error:nil];
        }

        [items addObject:item];
    }
    closedir(dir);

    return [items sortedArrayUsingComparator:^NSComparisonResult(FileItem *obj1, FileItem *obj2) {
        if (obj1.isDirectory != obj2.isDirectory) {
            return obj1.isDirectory ? NSOrderedAscending : NSOrderedDescending;
        }
        return [obj1.name localizedStandardCompare:obj2.name];
    }];
}

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error {
    return [[NSFileManager defaultManager] removeItemAtPath:path error:error];
}

- (BOOL)moveItemAtPath:(NSString *)src toPath:(NSString *)dst error:(NSError **)error {
    return [[NSFileManager defaultManager] moveItemAtPath:src toPath:dst error:error];
}

- (BOOL)copyItemAtPath:(NSString *)src toPath:(NSString *)dst error:(NSError **)error {
    return [[NSFileManager defaultManager] copyItemAtPath:src toPath:dst error:error];
}

- (BOOL)createDirectoryAtPath:(NSString *)path error:(NSError **)error {
    return [[NSFileManager defaultManager] createDirectoryAtURL:[NSURL fileURLWithPath:path] withIntermediateDirectories:YES attributes:nil error:error];
}

- (NSArray<FileItem *> *)searchFilesWithKeyword:(NSString *)keyword inPath:(NSString *)path {
    NSMutableArray<FileItem *> *results = [NSMutableArray array];
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:path];
    NSString *file;
    while ((file = [enumerator nextObject])) {
        if ([file.lastPathComponent containsString:keyword]) {
            NSString *fullPath = [path stringByAppendingPathComponent:file];
            FileItem *item = [[FileItem alloc] init];
            item.name = file.lastPathComponent;
            item.fullPath = fullPath;
            NSDictionary *attrs = [enumerator fileAttributes];
            item.isDirectory = [[attrs fileType] isEqualToString:NSFileTypeDirectory];
            [results addObject:item];
        }
    }
    return results;
}

@end
