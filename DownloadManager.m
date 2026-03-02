#import "DownloadManager.h"

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
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:@"com.app.download"];
        config.HTTPMaximumConnectionsPerHost = 12;
        self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    }
    return self;
}

- (void)downloadFileAtURL:(NSURL *)url toPath:(NSString *)path {
    if (!url) return;

    DownloadTask *dTask = [[DownloadTask alloc] init];
    NSString *name = [url lastPathComponent];
    if (name.length == 0 || [name isEqualToString:@"/"]) name = @"downloaded_file";
    dTask.filename = name;
    dTask.destinationPath = path;
    dTask.isDownloading = YES;
    dTask.progress = 0;

    NSURLSessionDownloadTask *task = [self.session downloadTaskWithURL:url];
    dTask.task = task;

    [_tasks addObject:dTask];
    self.taskMap[@(task.taskIdentifier)] = dTask;

    [task resume];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadStarted" object:nil];
}

- (void)cancelTask:(DownloadTask *)task {
    [task.task cancel];
    [self.tasks removeObject:task];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadUpdated" object:nil];
}

- (void)clearCompletedTasks {
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"isDownloading == YES"];
    [_tasks filterUsingPredicate:pred];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadUpdated" object:nil];
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    DownloadTask *dTask = self.taskMap[@(downloadTask.taskIdentifier)];
    if (dTask) {
        dTask.receivedBytes = totalBytesWritten;
        dTask.totalBytes = totalBytesExpectedToWrite;
        dTask.progress = (float)totalBytesWritten / (float)totalBytesExpectedToWrite;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadUpdated" object:nil];
    }
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    DownloadTask *dTask = self.taskMap[@(downloadTask.taskIdentifier)];
    if (dTask) {
        NSString *suggested = downloadTask.response.suggestedFilename;
        if (suggested) dTask.filename = suggested;

        [[NSFileManager defaultManager] createDirectoryAtPath:dTask.destinationPath withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *dest = [dTask.destinationPath stringByAppendingPathComponent:dTask.filename];
        if ([[NSFileManager defaultManager] fileExistsAtPath:dest]) {
             [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
        }
        [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:dest] error:nil];

        dTask.isDownloading = NO;
        dTask.progress = 1.0;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadFinished" object:nil];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    DownloadTask *dTask = self.taskMap[@(task.taskIdentifier)];
    if (dTask) {
        dTask.isDownloading = NO;
        if (error) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadError" object:error];
        }
    }
}

@end
