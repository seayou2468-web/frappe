#import "ImageViewerViewController.h"
#import "ThemeEngine.h"
#import "CustomMenuView.h"
#import <CoreImage/CoreImage.h>

@interface ImageViewerViewController () <UIScrollViewDelegate>
@property (strong, nonatomic) NSString *path;
@property (strong, nonatomic) UIScrollView *scrollView;
@property (strong, nonatomic) UIImageView *imageView;
@property (strong, nonatomic) UIImage *originalImage;
@end

@implementation ImageViewerViewController

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) { _path = path; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.title = self.path.lastPathComponent;

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.delegate = self;
    self.scrollView.minimumZoomScale = 1.0;
    self.scrollView.maximumZoomScale = 5.0;
    [self.view addSubview:self.scrollView];

    self.originalImage = [UIImage imageWithContentsOfFile:self.path];
    self.imageView = [[UIImageView alloc] initWithImage:self.originalImage];
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.frame = self.scrollView.bounds;
    self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.scrollView addSubview:self.imageView];

    UIBarButtonItem *editBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit target:self action:@selector(showEditMenu)];
    self.navigationItem.rightBarButtonItem = editBtn;
}

- (void)showEditMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"画像編集・変換"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"白黒" systemImage:@"camera.filters" style:CustomMenuActionStyleDefault handler:^{ [self applyFilter:@"CIPhotoEffectMono"]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"セピア" systemImage:@"camera.filters" style:CustomMenuActionStyleDefault handler:^{ [self applyFilter:@"CISepiaTone"]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"回転" systemImage:@"rotate.right" style:CustomMenuActionStyleDefault handler:^{ [self rotateImage]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"PNGとして保存" systemImage:@"doc.arrow.down" style:CustomMenuActionStyleDefault handler:^{ [self exportAs:@"png"]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"JPEGとして保存" systemImage:@"doc.arrow.down" style:CustomMenuActionStyleDefault handler:^{ [self exportAs:@"jpg"]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"HEICとして保存" systemImage:@"doc.arrow.down" style:CustomMenuActionStyleDefault handler:^{ [self exportAs:@"heic"]; }]];
    [menu showInView:self.view];
}

- (void)applyFilter:(NSString *)filterName {
    CIImage *ciInput = [[CIImage alloc] initWithImage:self.imageView.image];
    CIFilter *filter = [CIFilter filterWithName:filterName];
    [filter setValue:ciInput forKey:kCIInputImageKey];
    if ([filterName isEqualToString:@"CISepiaTone"]) [filter setValue:@1.0 forKey:kCIInputIntensityKey];

    CIImage *ciOutput = filter.outputImage;
    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef cgImage = [context createCGImage:ciOutput fromRect:[ciOutput extent]];
    UIImage *newImg = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);

    self.imageView.image = newImg;
}

- (void)rotateImage {
    UIImage *img = self.imageView.image;
    UIImageOrientation newOrient;
    switch (img.imageOrientation) {
        case UIImageOrientationUp: newOrient = UIImageOrientationRight; break;
        case UIImageOrientationRight: newOrient = UIImageOrientationDown; break;
        case UIImageOrientationDown: newOrient = UIImageOrientationLeft; break;
        default: newOrient = UIImageOrientationUp; break;
    }
    self.imageView.image = [UIImage imageWithCGImage:img.CGImage scale:img.scale orientation:newOrient];
}

- (void)exportAs:(NSString *)format {
    NSData *data = nil;
    if ([format isEqualToString:@"png"]) data = UIImagePNGRepresentation(self.imageView.image);
    else if ([format isEqualToString:@"heic"]) {
        if (@available(iOS 11.0, *)) {
            CIContext *ctx = [CIContext context];
            data = [ctx HEIFRepresentationOfImage:[[CIImage alloc] initWithImage:self.imageView.image] format:kCIFormatRGBA8 colorSpace:CGColorSpaceCreateDeviceRGB() options:@{}];
        }
    }
    else data = UIImageJPEGRepresentation(self.imageView.image, 0.9);

    NSString *newPath = [[self.path stringByDeletingPathExtension] stringByAppendingPathExtension:format];
    if (data && [data writeToFile:newPath atomically:YES]) {
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeError];
    }
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView { return self.imageView; }

@end
