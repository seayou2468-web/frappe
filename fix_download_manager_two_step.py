import os

file_path = 'DownloadManager.m'
with open(file_path, 'r') as f:
    content = f.read()

# Replace didFinishDownloadingToURL with the two-step logic
old_handler = """- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    DownloadTask *dTask = self.taskMap[@(downloadTask.taskIdentifier)];

    NSString *rawPath = dTask ? dTask.relativeDestinationPath : nil;
    if (!rawPath) rawPath = dTask ? dTask.destinationPath : downloadTask.taskDescription;

    NSString *destPath = nil;
    if (rawPath) {
        NSString *rel = [FileManagerCore relativeToHomePath:rawPath];
        destPath = [FileManagerCore absoluteFromHomeRelativePath:rel];
    }

    if (!destPath) {
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        destPath = [docs stringByAppendingPathComponent:@"Downloads"];
    }

    NSString *filename = dTask ? dTask.filename : downloadTask.response.suggestedFilename;
    if (!filename) filename = @"downloaded_file";

    NSError *moveError = nil;
    NSString *finalName = [[FileManagerCore sharedManager] moveItemAtURL:location toDirectory:destPath uniqueName:filename error:&moveError];

    if (finalName) {
        if (dTask) {
            dTask.filename = finalName;
            dTask.isDownloading = NO;
            dTask.progress = 1.0;
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadFinished" object:nil];
    } else {
        NSLog(@"Download Move Error: %@ to %@", moveError.localizedDescription, destPath);
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadError" object:moveError];
    }
}"""

new_handler = """- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    DownloadTask *dTask = self.taskMap[@(downloadTask.taskIdentifier)];
    NSFileManager *fm = [NSFileManager defaultManager];

    // Step 1: Immediately move to an internal temporary location within the app sandbox
    // (This helps bypass issues where system background daemon cannot reach guest app sub-directories)
    NSString *home = [FileManagerCore effectiveHomeDirectory];
    NSString *internalTmpDir = [home stringByAppendingPathComponent:@"Documents/.download_tmp"];
    [fm createDirectoryAtPath:internalTmpDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *tmpFilename = [NSString stringWithFormat:@"tmp_%ld_%@", (long)[[NSDate date] timeIntervalSince1970], downloadTask.response.suggestedFilename ?: @"file"];
    NSString *tmpPath = [internalTmpDir stringByAppendingPathComponent:tmpFilename];
    NSURL *tmpURL = [NSURL fileURLWithPath:tmpPath];

    NSError *tmpError = nil;
    if ([fm fileExistsAtPath:tmpPath]) [fm removeItemAtPath:tmpPath error:nil];

    BOOL tmpSuccess = [fm moveItemAtURL:location toURL:tmpURL error:&tmpError];
    if (!tmpSuccess) {
        // Fallback to copy if move fails
        tmpSuccess = [fm copyItemAtURL:location toURL:tmpURL error:&tmpError];
    }

    if (!tmpSuccess) {
        NSLog(@"Intermediate Save Error: %@", tmpError.localizedDescription);
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadError" object:tmpError];
        return;
    }

    // Step 2: Final move to the target destination
    NSString *rawPath = dTask ? dTask.relativeDestinationPath : nil;
    if (!rawPath) rawPath = dTask ? dTask.destinationPath : downloadTask.taskDescription;

    NSString *destPath = nil;
    if (rawPath) {
        NSString *rel = [FileManagerCore relativeToHomePath:rawPath];
        destPath = [FileManagerCore absoluteFromHomeRelativePath:rel];
    }

    if (!destPath) {
        destPath = [home stringByAppendingPathComponent:@"Documents/Downloads"];
    }

    NSString *filename = dTask ? dTask.filename : downloadTask.response.suggestedFilename;
    if (!filename) filename = @"downloaded_file";

    NSError *moveError = nil;
    NSString *finalName = [[FileManagerCore sharedManager] moveItemAtURL:tmpURL toDirectory:destPath uniqueName:filename error:&moveError];

    if (finalName) {
        if (dTask) {
            dTask.filename = finalName;
            dTask.isDownloading = NO;
            dTask.progress = 1.0;
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadFinished" object:nil];
    } else {
        NSLog(@"Final Move Error: %@ to %@", moveError.localizedDescription, destPath);
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadError" object:moveError];
    }

    // Cleanup temporary file
    [fm removeItemAtURL:tmpURL error:nil];
}"""

content = content.replace(old_handler, new_handler)

with open(file_path, 'w') as f:
    f.write(content)
