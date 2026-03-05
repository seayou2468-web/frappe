#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface DownloadTask : NSObject
@property (strong, nonatomic) NSURLSessionTask *task;
@property (copy, nonatomic) NSString *filename;
@property (assign, nonatomic) float progress;
@property (assign, nonatomic) int64_t totalBytes;
@property (assign, nonatomic) int64_t receivedBytes;
@property (assign, nonatomic) BOOL isDownloading;
@property (copy, nonatomic) NSString *destinationPath;
@property (copy, nonatomic) NSString *relativeDestinationPath;
@property (strong, nonatomic) NSData *resumeData;
@property (assign, nonatomic) UIBackgroundTaskIdentifier backgroundTaskID;
@property (strong, nonatomic) NSFileHandle *fileHandle;
@property (copy, nonatomic) NSString *tempPath;
@end

@interface DownloadManager : NSObject <NSURLSessionDataDelegate>
@property (copy, nonatomic) void (^completionHandler)(void);
+ (instancetype)sharedManager;
@property (strong, nonatomic, readonly) NSMutableArray<DownloadTask *> *tasks;
- (void)downloadFileAtURL:(NSURL *)url toPath:(NSString *)path;
- (void)downloadFileWithRequest:(NSURLRequest *)request toPath:(NSString *)path;
- (void)resumeTask:(DownloadTask *)task;
- (void)cancelTask:(DownloadTask *)task;
- (void)clearCompletedTasks;
@end
