#import <Foundation/Foundation.h>

@class NSURLSessionDownloadTask;

@interface DownloadTask : NSObject
@property (strong, nonatomic) NSURLSessionDownloadTask *task;
@property (copy, nonatomic) NSString *filename;
@property (assign, nonatomic) float progress;
@property (assign, nonatomic) int64_t totalBytes;
@property (assign, nonatomic) int64_t receivedBytes;
@property (assign, nonatomic) BOOL isDownloading;
@property (copy, nonatomic) NSString *destinationPath;
@property (copy, nonatomic) NSString *relativeDestinationPath;
@property (strong, nonatomic) NSData *resumeData;
@end

@interface DownloadManager : NSObject <NSURLSessionDownloadDelegate>
@property (copy, nonatomic) void (^completionHandler)(void);
+ (instancetype)sharedManager;
@property (strong, nonatomic, readonly) NSMutableArray<DownloadTask *> *tasks;
- (void)downloadFileAtURL:(NSURL *)url toPath:(NSString *)path;
- (void)downloadFileWithRequest:(NSURLRequest *)request toPath:(NSString *)path;
- (void)resumeTask:(DownloadTask *)task;
- (void)cancelTask:(DownloadTask *)task;
- (void)clearCompletedTasks;
@end
