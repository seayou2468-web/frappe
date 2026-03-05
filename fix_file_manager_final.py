import os

file_path = 'FileManagerCore.m'
with open(file_path, 'r') as f:
    content = f.read()

# Update effectiveHomeDirectory to return NSHomeDirectory()
old_helper = """+ (NSString *)effectiveHomeDirectory {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    if (docs) {
        return [docs stringByDeletingLastPathComponent];
    }
    return NSHomeDirectory();
}"""

new_helper = """+ (NSString *)effectiveHomeDirectory {
    return NSHomeDirectory();
}"""

content = content.replace(old_helper, new_helper)

# Update absoluteFromHomeRelativePath to use NSHomeDirectory() for everything
old_absolute = """+ (NSString *)absoluteFromHomeRelativePath:(NSString *)relativePath {
    if (!relativePath) return nil;
    if ([relativePath isAbsolutePath]) return relativePath;
    NSString *clean = relativePath;
    while ([clean hasPrefix:@"/"]) clean = [clean substringFromIndex:1];

    NSString *home = [self effectiveHomeDirectory];

    if ([clean hasPrefix:@"Documents"]) {
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        if (docs) {
            NSString *rel = [clean substringFromIndex:9]; // "Documents".length
            while ([rel hasPrefix:@"/"]) rel = [rel substringFromIndex:1];
            return [docs stringByAppendingPathComponent:rel];
        }
    }

    return [home stringByAppendingPathComponent:clean];
}"""

new_absolute = """+ (NSString *)absoluteFromHomeRelativePath:(NSString *)relativePath {
    if (!relativePath) return nil;
    if ([relativePath isAbsolutePath]) return relativePath;
    NSString *clean = relativePath;
    while ([clean hasPrefix:@"/"]) clean = [clean substringFromIndex:1];

    NSString *home = [self effectiveHomeDirectory];
    return [home stringByAppendingPathComponent:clean];
}"""

content = content.replace(old_absolute, new_absolute)

with open(file_path, 'w') as f:
    f.write(content)
