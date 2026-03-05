import os

def update_file(path, old, new):
    with open(path, 'r') as f:
        content = f.read()
    if old in content:
        content = content.replace(old, new)
        with open(path, 'w') as f:
            f.write(content)

# Correct the DownloadManager replacement
update_file('DownloadManager.m', 'NSLog(@"Final Move Error: %@ to %@", moveError.localizedDescription, destPath);', '[[Logger sharedLogger] log:[NSString stringWithFormat:@"Final Move Error: %@ to %@", moveError.localizedDescription, destPath]];')
update_file('DownloadManager.m', 'NSLog(@"Intermediate Save Error: %@", tmpError.localizedDescription);', '[[Logger sharedLogger] log:[NSString stringWithFormat:@"Intermediate Save Error: %@", tmpError.localizedDescription]];')

# Add success logs
update_file('DownloadManager.m', '[[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadFinished" object:nil];', '[[Logger sharedLogger] log:[NSString stringWithFormat:@"Download Finished: %@", finalName]]; [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadFinished" object:nil];')
update_file('DownloadManager.m', 'dTask.relativeDestinationPath = [FileManagerCore relativeToHomePath:path];', 'dTask.relativeDestinationPath = [FileManagerCore relativeToHomePath:path]; [[Logger sharedLogger] log:[NSString stringWithFormat:@"Download target path: %@", path]];')
