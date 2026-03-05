#import "DownloadManager.h"
#import "FileManagerCore.h"
#import "Logger.h"

@implementation DownloadTask
@end

@interface DownloadManager ()
@property (strong, nonatomic) NSURLSession *session;
@property (strong, nonatomic) NSMutableDictionary<NSNumber *, DownloadTask *> *taskMap;
@end

@implementation DownloadManager

+ (instancetype)sharedManager {
    static DownloadManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[DownloadManager alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _tasks = [NSMutableArray array];
        _taskMap = [NSMutableDictionary dictionary];
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:@"com.app.godspeed.download"];
        config.HTTPMaximumConnectionsPerHost = 16;
        config.waitsForConnectivity = YES;
        config.allowsCellularAccess = YES;
        config.timeoutIntervalForResource = 24 * 60 * 60;
        self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    }
    return self;
}

- (void)downloadFileWithRequest:(NSURLRequest *)request toPath:(NSString *)path {
    if (!request) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    DownloadTask *dTask = [[DownloadTask alloc] init];
    NSString *name = [request.URL lastPathComponent];
    if (name.length == 0 || [name isEqualToString:@"/"]) name = @"downloaded_file";
    dTask.filename = name;
    dTask.destinationPath = path;
    dTask.relativeDestinationPath = [FileManagerCore relativeToHomePath:path];
    [[Logger sharedLogger] log:[NSString stringWithFormat:@"[DOWNLOAD] Starting: %@ to %@", request.URL.absoluteString, path]];
    [[Logger sharedLogger] log:[NSString stringWithFormat:@"[DOWNLOAD] Relative Target: %@", dTask.relativeDestinationPath]];
    dTask.isDownloading = YES;
    dTask.progress = 0;

    NSURLSessionDownloadTask *task = [self.session downloadTaskWithRequest:request];
    task.taskDescription = path;
    dTask.task = task;

    [self.tasks addObject:dTask];
    self.taskMap[@(task.taskIdentifier)] = dTask;
    [task resume];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadStarted" object:nil];
}

- (void)downloadFileAtURL:(NSURL *)url toPath:(NSString *)path {
    if (!url) return;
    [self downloadFileWithRequest:[NSURLRequest requestWithURL:url] toPath:path];
}

- (void)resumeTask:(DownloadTask *)task {
    if (task.resumeData) {
        NSURLSessionDownloadTask *newDownloadTask = [self.session downloadTaskWithResumeData:task.resumeData];
        task.task = newDownloadTask;
        task.isDownloading = YES;
        task.resumeData = nil;
        self.taskMap[@(newDownloadTask.taskIdentifier)] = task;
        [newDownloadTask resume];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadStarted" object:nil];
    }
}

- (void)cancelTask:(DownloadTask *)task {
    [task.task cancel];
    [self.tasks removeObject:task];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadUpdated" object:nil];
}

- (void)clearCompletedTasks {
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"isDownloading == YES"];
    [self.tasks filterUsingPredicate:pred];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadUpdated" object:nil];
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    DownloadTask *dTask = self.taskMap[@(downloadTask.taskIdentifier)];
    if (dTask) {
        dTask.receivedBytes = totalBytesWritten;
        dTask.totalBytes = totalBytesExpectedToWrite;
        if (totalBytesExpectedToWrite > 0) dTask.progress = (float)totalBytesWritten / (float)totalBytesExpectedToWrite;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadUpdated" object:nil];
    }
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    DownloadTask *dTask = self.taskMap[@(downloadTask.taskIdentifier)];
    NSFileManager *fm = [NSFileManager defaultManager];
    [[Logger sharedLogger] log:[NSString stringWithFormat:@"[DOWNLOAD] Finished data: %@", location.path]];

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

    [[Logger sharedLogger] log:[NSString stringWithFormat:@"[DOWNLOAD] Step 1: Internal tmp move to %@", tmpPath]];
    BOOL tmpSuccess = [fm moveItemAtURL:location toURL:tmpURL error:&tmpError];
    if (!tmpSuccess) {
        [[Logger sharedLogger] log:@"[DOWNLOAD] Move failed, trying copy fallback..."];
        tmpSuccess = [fm copyItemAtURL:location toURL:tmpURL error:&tmpError];
    }

    if (!tmpSuccess) {
        [[Logger sharedLogger] log:[NSString stringWithFormat:@"Intermediate Save Error: %@", tmpError.localizedDescription]];
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
        [[Logger sharedLogger] log:[NSString stringWithFormat:@"[DOWNLOAD] SUCCESS: Saved as %@", finalName]];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadFinished" object:nil];
    } else {
        [[Logger sharedLogger] log:[NSString stringWithFormat:@"Final Move Error: %@ to %@", moveError.localizedDescription, destPath]];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadError" object:moveError];
    }

    // Cleanup temporary file
    [fm removeItemAtURL:tmpURL error:nil];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    DownloadTask *dTask = self.taskMap[@(task.taskIdentifier)];
    if (dTask) {
        dTask.isDownloading = NO;
        if (error) {
            NSData *resumeData = error.userInfo[NSURLSessionDownloadTaskResumeData];
            if (resumeData) dTask.resumeData = resumeData;
            [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadError" object:error];
        } else {
            [self.taskMap removeObjectForKey:@(task.taskIdentifier)];
        }
    }
}

- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session {
    if (self.completionHandler) {
        void (^handler)(void) = self.completionHandler;
        self.completionHandler = nil;
        handler();
    }
}

@end
