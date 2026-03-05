import os

file_path = 'FileManagerCore.m'
with open(file_path, 'r') as f:
    content = f.read()

# Fix relativeToHomePath:
old_relative = """+ (NSString *)relativeToHomePath:(NSString *)absolutePath {
    if (!absolutePath) return nil;
    NSString *stdPath = [absolutePath stringByStandardizingPath];

    // In virtualization like LiveContainer, paths often look like /.../HostApp/Documents/VirtualApp/...
    // We want the path relative to the VirtualApp root (which contains its own Documents)

    NSRange range = [stdPath rangeOfString:@"/Documents" options:NSBackwardsSearch];
    if (range.location != NSNotFound) {
        NSString *rel = [stdPath substringFromIndex:range.location + 1];
        return rel;
    }

    NSString *home = [NSHomeDirectory() stringByStandardizingPath];
    if ([stdPath hasPrefix:home]) {
        NSString *rel = [stdPath substringFromIndex:home.length];
        while ([rel hasPrefix:@"/"]) rel = [rel substringFromIndex:1];
        return rel;
    }"""

new_relative = """+ (NSString *)relativeToHomePath:(NSString *)absolutePath {
    if (!absolutePath) return nil;
    NSString *stdPath = [absolutePath stringByStandardizingPath];
    NSString *home = [NSHomeDirectory() stringByStandardizingPath];

    if ([stdPath hasPrefix:home]) {
        NSString *rel = [stdPath substringFromIndex:home.length];
        while ([rel hasPrefix:@"/"]) rel = [rel substringFromIndex:1];
        return rel;
    }

    // In virtualization like LiveContainer, paths often look like /.../HostApp/Documents/VirtualApp/...
    // We want the path relative to the VirtualApp root (which contains its own Documents)
    NSRange range = [stdPath rangeOfString:@"/Documents" options:NSBackwardsSearch];
    if (range.location != NSNotFound) {
        NSString *rel = [stdPath substringFromIndex:range.location + 1];
        return rel;
    }"""

content = content.replace(old_relative, new_relative)

# Fix absoluteFromHomeRelativePath:
old_absolute = """+ (NSString *)absoluteFromHomeRelativePath:(NSString *)relativePath {
    if (!relativePath) return nil;
    if ([relativePath isAbsolutePath]) return relativePath;
    NSString *clean = relativePath;
    while ([clean hasPrefix:@"/"]) clean = [clean substringFromIndex:1];

    // Virtualization environments like LiveContainer map their "Home" to a subdirectory
    // of the host app's Documents folder.

    if ([clean hasPrefix:@"Documents"]) {
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *rel = [clean substringFromIndex:9]; // "Documents".length
        while ([rel hasPrefix:@"/"]) rel = [rel substringFromIndex:1];
        return [docs stringByAppendingPathComponent:rel];
    }

    // Check if we are in a virtual environment by looking at the home directory's path components
    NSString *home = NSHomeDirectory();
    if ([home containsString:@"/Documents/"]) {
        // We are likely inside a virtual container.
        // NSHomeDirectory() is already the correct root for the virtual app.
        return [home stringByAppendingPathComponent:clean];
    }

    return [home stringByAppendingPathComponent:clean];
}"""

new_absolute = """+ (NSString *)absoluteFromHomeRelativePath:(NSString *)relativePath {
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

content = content.replace(old_absolute, new_absolute)

with open(file_path, 'w') as f:
    f.write(content)
