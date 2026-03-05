import os

file_path = 'FileManagerCore.m'
with open(file_path, 'r') as f:
    content = f.read()

# Add helper for getting the effective home (one level above Documents)
effective_home_helper = """+ (NSString *)effectiveHomeDirectory {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    if (docs) {
        return [docs stringByDeletingLastPathComponent];
    }
    return NSHomeDirectory();
}

+ (NSString *)relativeToHomePath:(NSString *)absolutePath {"""

content = content.replace("+ (NSString *)relativeToHomePath:(NSString *)absolutePath {", effective_home_helper)

# Update relativeToHomePath to use effectiveHomeDirectory
old_relative = """    NSString *stdPath = [absolutePath stringByStandardizingPath];
    NSString *home = [NSHomeDirectory() stringByStandardizingPath];

    if ([stdPath hasPrefix:home]) {
        NSString *rel = [stdPath substringFromIndex:home.length];
        while ([rel hasPrefix:@"/"]) rel = [rel substringFromIndex:1];
        return rel;
    }"""

new_relative = """    NSString *stdPath = [absolutePath stringByStandardizingPath];
    NSString *home = [[self effectiveHomeDirectory] stringByStandardizingPath];

    if ([stdPath hasPrefix:home]) {
        NSString *rel = [stdPath substringFromIndex:home.length];
        while ([rel hasPrefix:@"/"]) rel = [rel substringFromIndex:1];
        return rel;
    }"""

content = content.replace(old_relative, new_relative)

# Update absoluteFromHomeRelativePath to use effectiveHomeDirectory
old_absolute = """+ (NSString *)absoluteFromHomeRelativePath:(NSString *)relativePath {
    if (!relativePath) return nil;
    if ([relativePath isAbsolutePath]) return relativePath;
    NSString *clean = relativePath;
    while ([clean hasPrefix:@"/"]) clean = [clean substringFromIndex:1];

    NSString *home = NSHomeDirectory();

    // Check if we are in a virtual environment by looking at the home directory's path components
    // Virtualization environments like LiveContainer map their "Home" to a subdirectory
    // of the host app's Documents folder.
    if ([home containsString:@"/Documents/"]) {
        // We are likely inside a virtual container.
        // NSHomeDirectory() is already the correct root for the virtual app.
        return [home stringByAppendingPathComponent:clean];
    }

    if ([clean hasPrefix:@"Documents"]) {
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *rel = [clean substringFromIndex:9]; // "Documents".length
        while ([rel hasPrefix:@"/"]) rel = [rel substringFromIndex:1];
        return [docs stringByAppendingPathComponent:rel];
    }

    return [home stringByAppendingPathComponent:clean];
}"""

new_absolute = """+ (NSString *)absoluteFromHomeRelativePath:(NSString *)relativePath {
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

content = content.replace(old_absolute, new_absolute)

with open(file_path, 'w') as f:
    f.write(content)
