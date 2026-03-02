#import <Foundation/Foundation.h>

@interface DownloadTask : NSObject
@property (nonatomic, strong) NSURLSessionDownloadTask *task;
@property (nonatomic, copy) NSString *filename;
@property (nonatomic, assign) float progress;
@property (nonatomic, assign) int64_t totalBytes;
@property (nonatomic, assign) int64_t receivedBytes;
@property (nonatomic, assign) BOOL isDownloading;
@property (nonatomic, copy) NSString *destinationPath;
@property (nonatomic, strong) NSData *resumeData;
@end

@interface DownloadManager : NSObject <NSURLSessionDownloadDelegate>
@property (nonatomic, copy) void (^completionHandler)(void);
+ (instancetype)sharedManager;
@property (nonatomic, strong, readonly) NSMutableArray<DownloadTask *> *tasks;
- (void)downloadFileAtURL:(NSURL *)url toPath:(NSString *)path;
- (void)resumeTask:(DownloadTask *)task;
- (void)cancelTask:(DownloadTask *)task;
- (void)clearCompletedTasks;
@end
