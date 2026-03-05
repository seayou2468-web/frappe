#import "DownloadManager.h"
#import "FileManagerCore.h"
#import "Logger.h"
#import <AVFoundation/AVFoundation.h>

@implementation DownloadTask
@end

@interface DownloadManager () <NSURLSessionDataDelegate>
@property (strong, nonatomic) NSURLSession *session;
@property (strong, nonatomic) NSMutableDictionary<NSNumber *, DownloadTask *> *taskMap;
@property (strong, nonatomic) AVAudioPlayer *audioPlayer;
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

        // Use defaultSessionConfiguration for pseudo-backgrounding
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.URLCache = nil;
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        config.HTTPMaximumConnectionsPerHost = 8;
        config.timeoutIntervalForRequest = 60;
        config.timeoutIntervalForResource = 24 * 60 * 60;
        self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:[NSOperationQueue mainQueue]];

        [self setupAudioSession];
        [self clearInternalCache];
    }
    return self;
}

- (void)setupAudioSession {
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
                                     withOptions:AVAudioSessionCategoryOptionMixWithOthers
                                           error:nil];
}

- (void)playSilentAudio {
    if (self.audioPlayer.isPlaying) return;

    // Create a minimal silent WAV file (1 second of silence)
    NSString *path = [[FileManagerCore effectiveHomeDirectory] stringByAppendingPathComponent:@"Library/Caches/.silent.wav"];
    // Cleanup old path
    NSString *oldPath = [[FileManagerCore effectiveHomeDirectory] stringByAppendingPathComponent:@"Documents/.silent.wav"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:oldPath]) [[NSFileManager defaultManager] removeItemAtPath:oldPath error:nil];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        // WAV header for 8000Hz, 16-bit, mono, 1 second
        unsigned char header[] = {
            'R','I','F','F', 0x24,0x3e,0x00,0x00, 'W','A','V','E',
            'f','m','t',' ', 0x10,0x00,0x00,0x00, 0x01,0x00, 0x01,0x00,
            0x40,0x1f,0x00,0x00, 0x80,0x3e,0x00,0x00, 0x02,0x00, 0x10,0x00,
            'd','a','t','a', 0x00,0x3e,0x00,0x00
        };
        NSMutableData *data = [NSMutableData dataWithBytes:header length:sizeof(header)];
        [data increaseLengthBy:16000]; // 1 second of silence (zeroes)
        [data writeToFile:path atomically:YES];
    }

    NSError *error;
    self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&error];
    self.audioPlayer.numberOfLoops = -1; // Infinite loop
    self.audioPlayer.volume = 0.01; // Nearly silent
    [self.audioPlayer prepareToPlay];
    [self.audioPlayer play];

    [[Logger sharedLogger] log:@"[SYSTEM] Started pseudo-background audio"];
}

- (void)stopSilentAudio {
    BOOL anyDownloading = NO;
    for (DownloadTask *t in self.tasks) {
        if (t.isDownloading) { anyDownloading = YES; break; }
    }

    if (!anyDownloading && self.audioPlayer.isPlaying) {
        [self.audioPlayer stop];
        [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
        [[Logger sharedLogger] log:@"[SYSTEM] Stopped pseudo-background audio"];
    }
}

#pragma mark - Download Logic

- (void)downloadFileWithRequest:(NSURLRequest *)request toPath:(NSString *)path {
    if (!request) return;

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];

    DownloadTask *dTask = [[DownloadTask alloc] init];
    dTask.filename = [request.URL lastPathComponent] ?: @"downloaded_file";
    dTask.destinationPath = path;
    dTask.relativeDestinationPath = [FileManagerCore relativeToHomePath:path];

    // Start Background Task
    dTask.backgroundTaskID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [[Logger sharedLogger] log:@"[DOWNLOAD] Background task expired!"];
        [[UIApplication sharedApplication] endBackgroundTask:dTask.backgroundTaskID];
        dTask.backgroundTaskID = UIBackgroundTaskInvalid;
    }];

    // Setup Temporary File for Streaming Write
    NSString *home = [FileManagerCore effectiveHomeDirectory];
    NSString *tmpDir = [home stringByAppendingPathComponent:@"Library/Caches/.download_tmp"];
    // Cleanup old path
    NSString *oldTmpDir = [home stringByAppendingPathComponent:@"Documents/.download_tmp"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:oldTmpDir]) [[NSFileManager defaultManager] removeItemAtPath:oldTmpDir error:nil];
    [fm createDirectoryAtPath:tmpDir withIntermediateDirectories:YES attributes:nil error:nil];
    dTask.tempPath = [tmpDir stringByAppendingPathComponent:[NSString stringWithFormat:@"stream_%ld", (long)[[NSDate date] timeIntervalSince1970]]];
    [fm createFileAtPath:dTask.tempPath contents:nil attributes:nil];
    dTask.fileHandle = [NSFileHandle fileHandleForWritingAtPath:dTask.tempPath];

    dTask.isDownloading = YES;
    dTask.progress = 0;

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request];
    dTask.task = task;

    [self.tasks addObject:dTask];
    self.taskMap[@(task.taskIdentifier)] = dTask;

    [[Logger sharedLogger] log:[NSString stringWithFormat:@"[DOWNLOAD] Pseudo-BG Start: %@", request.URL.absoluteString]];

    [self playSilentAudio];
    [task resume];

    [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadStarted" object:nil];
}

- (void)downloadFileAtURL:(NSURL *)url toPath:(NSString *)path {
    if (!url) return;
    [self downloadFileWithRequest:[NSURLRequest requestWithURL:url] toPath:path];
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    DownloadTask *dTask = self.taskMap[@(dataTask.taskIdentifier)];
    if (dTask) {
        dTask.totalBytes = response.expectedContentLength;
    }
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    DownloadTask *dTask = self.taskMap[@(dataTask.taskIdentifier)];
    if (dTask) {
        [dTask.fileHandle writeData:data];
        dTask.receivedBytes += data.length;
        if (dTask.totalBytes > 0) dTask.progress = (float)dTask.receivedBytes / (float)dTask.totalBytes;

        [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadUpdated" object:nil];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    DownloadTask *dTask = self.taskMap[@(task.taskIdentifier)];
    if (!dTask) return;

    [dTask.fileHandle closeFile];
    dTask.fileHandle = nil;
    dTask.isDownloading = NO;

    if (error) {
        [[Logger sharedLogger] log:[NSString stringWithFormat:@"[DOWNLOAD] Error: %@", error.localizedDescription]];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadError" object:error];
    } else {
        [[Logger sharedLogger] log:@"[DOWNLOAD] Stream complete, relocating..."];

        NSString *destPath = [FileManagerCore absoluteFromHomeRelativePath:dTask.relativeDestinationPath];
        NSError *moveError = nil;
        NSString *finalName = [[FileManagerCore sharedManager] moveItemAtURL:[NSURL fileURLWithPath:dTask.tempPath] toDirectory:destPath uniqueName:dTask.filename error:&moveError];

        if (finalName) {
            dTask.filename = finalName;
            dTask.progress = 1.0;
            [[Logger sharedLogger] log:[NSString stringWithFormat:@"[DOWNLOAD] SUCCESS: %@", finalName]];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadFinished" object:nil];
        } else {
            [[Logger sharedLogger] log:[NSString stringWithFormat:@"[DOWNLOAD] Final Move Error: %@", moveError.localizedDescription]];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadError" object:moveError];
        }
    }

    // Clean up temp file
    [[NSFileManager defaultManager] removeItemAtPath:dTask.tempPath error:nil];

    // End Background Task
    if (dTask.backgroundTaskID != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:dTask.backgroundTaskID];
        dTask.backgroundTaskID = UIBackgroundTaskInvalid;
    }

    [self stopSilentAudio];
    [self.taskMap removeObjectForKey:@(task.taskIdentifier)];
}

#pragma mark - Controls

- (void)resumeTask:(DownloadTask *)task {
    // In pseudo-bg, we focus on keeping the process alive.
}

- (void)cancelTask:(DownloadTask *)task {
    [task.task cancel];
    [task.fileHandle closeFile];
    [[NSFileManager defaultManager] removeItemAtPath:task.tempPath error:nil];
    [self.tasks removeObject:task];
    if (task.backgroundTaskID != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:task.backgroundTaskID];
        task.backgroundTaskID = UIBackgroundTaskInvalid;
    }
    [self stopSilentAudio];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadUpdated" object:nil];
}

- (void)clearCompletedTasks {
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"isDownloading == YES"];
    [self.tasks filterUsingPredicate:pred];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"DownloadUpdated" object:nil];
}


- (void)clearInternalCache {
    NSString *cacheDir = [[FileManagerCore effectiveHomeDirectory] stringByAppendingPathComponent:@"Library/Caches"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:cacheDir error:nil];
    for (NSString *file in files) {
        if ([file isEqualToString:@".silent.wav"] || [file isEqualToString:@".download_tmp"]) continue;
        [fm removeItemAtPath:[cacheDir stringByAppendingPathComponent:file] error:nil];
    }
    [[Logger sharedLogger] log:@"[SYSTEM] Cleared internal Library/Caches"];
}
@end
