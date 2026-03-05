import os

def update_file(path, old, new):
    with open(path, 'r') as f:
        content = f.read()
    if old in content:
        content = content.replace(old, new)
        with open(path, 'w') as f:
            f.write(content)

# Update DownloadManager
update_file('DownloadManager.m', '#import "FileManagerCore.h"', '#import "FileManagerCore.h"\n#import "Logger.h"')
update_file('DownloadManager.m', 'NSLog(@"Download Move Error: %@ to %@", moveError.localizedDescription, destPath);', '[[Logger sharedLogger] log:[NSString stringWithFormat:@"Final Move Error: %@ to %@", moveError.localizedDescription, destPath]];')
update_file('DownloadManager.m', 'NSLog(@"Intermediate Save Error: %@", tmpError.localizedDescription);', '[[Logger sharedLogger] log:[NSString stringWithFormat:@"Intermediate Save Error: %@", tmpError.localizedDescription]];')

# Update FileManagerCore
update_file('FileManagerCore.m', '#import <Foundation/Foundation.h>', '#import <Foundation/Foundation.h>\n#import "Logger.h"')
# (Add some debug logs)
update_file('FileManagerCore.m', 'return NSHomeDirectory();', 'NSString *home = NSHomeDirectory();\n    [[Logger sharedLogger] log:[NSString stringWithFormat:@"Effective Home: %@", home]];\n    return home;')
