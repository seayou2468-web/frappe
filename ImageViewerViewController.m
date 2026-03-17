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
    self.view.backgroundColor = [ThemeEngine bg];
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

    UIBarButtonItem *editBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"pencil"] style:UIBarButtonItemStylePlain target:self action:@selector(showEditMenu)];
    self.navigationItem.rightBarButtonItem = editBtn;
}

- (void)showEditMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"画像編集・変換"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"白黒" systemImage:@"camera.filters" style:CustomMenuActionStyleDefault handler:^{ [self applyFilter:@"CIPhotoEffectMono"]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"セピア" systemImage:@"camera.filters" style:CustomMenuActionStyleDefault handler:^{ [self applyFilter:@"CISepiaTone"]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"明るさを上げる" systemImage:@"sun.max.fill" style:CustomMenuActionStyleDefault handler:^{ [self adjustBrightness:0.2]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"右に回転" systemImage:@"rotate.right" style:CustomMenuActionStyleDefault handler:^{ [self rotateImage]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"左右反転" systemImage:@"arrow.left.and.right" style:CustomMenuActionStyleDefault handler:^{ [self flipHorizontal]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"上下反転" systemImage:@"arrow.up.and.down" style:CustomMenuActionStyleDefault handler:^{ [self flipVertical]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"写真アプリに保存" systemImage:@"photo.badge.arrow.down" style:CustomMenuActionStyleDefault handler:^{ [self saveToPhotos]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"共有" systemImage:@"square.and.arrow.up" style:CustomMenuActionStyleDefault handler:^{ [self shareImage]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"PNGとして保存" systemImage:@"doc.arrow.down" style:CustomMenuActionStyleDefault handler:^{ [self exportAs:@"png"]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"JPEGとして保存" systemImage:@"doc.arrow.down" style:CustomMenuActionStyleDefault handler:^{ [self exportAs:@"jpg"]; }]];
    [menu showInView:self.view];
}

- (void)flipHorizontal {
    UIImage *img = self.imageView.image;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:img.size];
    UIImage *flipped = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGContextTranslateCTM(c, img.size.width, 0); CGContextScaleCTM(c, -1, 1);
        [img drawAtPoint:CGPointZero];
    }];
    self.imageView.image = flipped;
}

- (void)flipVertical {
    UIImage *img = self.imageView.image;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:img.size];
    UIImage *flipped = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGContextTranslateCTM(c, 0, img.size.height); CGContextScaleCTM(c, 1, -1);
        [img drawAtPoint:CGPointZero];
    }];
    self.imageView.image = flipped;
}

- (void)adjustBrightness:(CGFloat)val {
    CIImage *ci = [[CIImage alloc] initWithImage:self.imageView.image];
    CIFilter *f = [CIFilter filterWithName:@"CIColorControls"];
    [f setValue:ci forKey:kCIInputImageKey];
    [f setValue:@(val) forKey:@"inputBrightness"];
    CIContext *ctx = [CIContext contextWithOptions:nil];
    CGImageRef cg = [ctx createCGImage:f.outputImage fromRect:f.outputImage.extent];
    self.imageView.image = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
}

- (void)saveToPhotos {
    UIImageWriteToSavedPhotosAlbum(self.imageView.image, self, @selector(image:didFinishSaving:contextInfo:), nil);
}
- (void)image:(UIImage *)image didFinishSaving:(NSError *)err contextInfo:(void *)ctx {
    [[UINotificationFeedbackGenerator new] notificationOccurred:err ? UINotificationFeedbackTypeError : UINotificationFeedbackTypeSuccess];
}

- (void)shareImage {
    UIActivityViewController *avc = [[UIActivityViewController alloc]
        initWithActivityItems:@[self.imageView.image] applicationActivities:nil];
    avc.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:avc animated:YES completion:nil];
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
