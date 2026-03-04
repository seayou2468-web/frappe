#import "DownloadManager.h"
#import "FileManagerCore.h"

@implementation DownloadTask
@end

@interface DownloadManager ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, DownloadTask *> *taskMap;
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
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    DownloadTask *dTask = [[DownloadTask alloc] init];
    NSString *name = [request.URL lastPathComponent];
    if (name.length == 0 || [name isEqualToString:@"/"]) name = @"downloaded_file";
    dTask.filename = name;
    dTask.destinationPath = path;
    dTask.isDownloading = YES;
    dTask.progress = 0;
    NSURLSessionDownloadTask *task = [self.session downloadTaskWithRequest:request];
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
    if (dTask) {
        NSString *suggested = downloadTask.response.suggestedFilename;
        if (suggested) dTask.filename = suggested;
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:dTask.destinationPath withIntermediateDirectories:YES attributes:nil error:nil];

        NSError *moveError = nil;
        NSString *finalName = [[FileManagerCore sharedManager] copyItemAtPath:location.path toDirectory:dTask.destinationPath uniqueName:dTask.filename error:&moveError];
        if (finalName) {
            dTask.filename = finalName;
            dTask.isDownloading = NO;
            dTask.progress = 1.0;
            [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadFinished" object:nil];
        } else {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadError" object:moveError];
        }
    }
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
