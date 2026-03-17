#import "ThemeEngine.h"

// ─── Palette ──────────────────────────────────────────────────────────────────
static UIColor *hexRGB(uint32_t v) {
    return [UIColor colorWithRed:((v>>16)&0xFF)/255.0
                           green:((v>>8)&0xFF)/255.0
                            blue:(v&0xFF)/255.0
                           alpha:1.0];
}

@implementation ThemeEngine

+ (UIColor *)bg           { return hexRGB(0x09090F); }
+ (UIColor *)surface      { return [UIColor colorWithWhite:1 alpha:0.055]; }
+ (UIColor *)surfaceHigh  { return [UIColor colorWithWhite:1 alpha:0.10]; }
+ (UIColor *)border       { return [UIColor colorWithWhite:1 alpha:0.10]; }
+ (UIColor *)textPrimary  { return [UIColor colorWithWhite:1 alpha:0.96]; }
+ (UIColor *)textSecondary{ return [UIColor colorWithWhite:1 alpha:0.50]; }
+ (UIColor *)textTertiary { return [UIColor colorWithWhite:1 alpha:0.28]; }

+ (UIColor *)accent {
    NSString *c = [[NSUserDefaults standardUserDefaults] stringForKey:@"AccentColor"];
    if ([c isEqualToString:@"red"])    return [UIColor systemRedColor];
    if ([c isEqualToString:@"green"])  return [UIColor systemGreenColor];
    if ([c isEqualToString:@"purple"]) return [UIColor systemPurpleColor];
    if ([c isEqualToString:@"orange"]) return [UIColor systemOrangeColor];
    if ([c isEqualToString:@"cyan"])   return [UIColor systemCyanColor];
    if ([c isEqualToString:@"pink"])   return [UIColor systemPinkColor];
    return [UIColor systemBlueColor];
}

// ─── File type tints ──────────────────────────────────────────────────────────
+ (UIColor *)tintForFolder { return hexRGB(0x4A9EFF); }

+ (UIColor *)tintForExtension:(NSString *)ext {
    ext = ext.lowercaseString;
    if ([@[@"png",@"jpg",@"jpeg",@"gif",@"heic",@"bmp",@"webp"] containsObject:ext]) return hexRGB(0xFF9F0A);
    if ([@[@"mp4",@"mov",@"avi",@"mkv",@"m4v"] containsObject:ext])                  return hexRGB(0xBF5AF2);
    if ([@[@"mp3",@"wav",@"m4a",@"flac",@"aac"] containsObject:ext])                 return hexRGB(0xFF375F);
    if ([@[@"zip",@"rar",@"7z",@"tar",@"gz",@"bz2"] containsObject:ext])             return hexRGB(0xFFD60A);
    if ([ext isEqualToString:@"pdf"])                                                  return hexRGB(0xFF453A);
    if ([@[@"db",@"sqlite",@"sql"] containsObject:ext])                               return hexRGB(0x30D158);
    if ([@[@"plist",@"xml"] containsObject:ext])                                      return hexRGB(0xFF9F0A);
    if ([@[@"json",@"yaml",@"yml"] containsObject:ext])                               return hexRGB(0x64D2FF);
    if ([@[@"html",@"htm",@"css",@"js"] containsObject:ext])                         return hexRGB(0xFF6961);
    if ([@[@"c",@"cpp",@"h",@"m",@"mm",@"py",@"sh",@"swift"] containsObject:ext])    return hexRGB(0x34C759);
    if ([@[@"csv",@"tsv",@"xlsx",@"xls"] containsObject:ext])                        return hexRGB(0x30D158);
    return [UIColor colorWithWhite:1 alpha:0.55];
}

+ (NSString *)symbolForExtension:(NSString *)ext {
    ext = ext.lowercaseString;
    if ([@[@"png",@"jpg",@"jpeg",@"gif",@"heic",@"bmp",@"webp"] containsObject:ext]) return @"photo.fill";
    if ([@[@"mp4",@"mov",@"avi",@"mkv",@"m4v"] containsObject:ext])                  return @"play.rectangle.fill";
    if ([@[@"mp3",@"wav",@"m4a",@"flac",@"aac"] containsObject:ext])                 return @"music.note";
    if ([@[@"zip",@"rar",@"7z",@"tar",@"gz",@"bz2"] containsObject:ext])             return @"archivebox.fill";
    if ([ext isEqualToString:@"pdf"])                                                  return @"doc.richtext.fill";
    if ([@[@"db",@"sqlite",@"sql"] containsObject:ext])                               return @"cylinder.fill";
    if ([@[@"plist",@"xml",@"json",@"yaml",@"yml"] containsObject:ext])               return @"curlybraces";
    if ([@[@"html",@"htm",@"css",@"js"] containsObject:ext])                          return @"globe";
    if ([@[@"c",@"cpp",@"h",@"m",@"mm",@"py",@"sh",@"swift"] containsObject:ext])    return @"chevron.left.forwardslash.chevron.right";
    if ([@[@"csv",@"tsv",@"xlsx",@"xls"] containsObject:ext])                        return @"tablecells.fill";
    return @"doc.fill";
}

// ─── Glass surface ────────────────────────────────────────────────────────────
+ (void)applyGlassToView:(UIView *)view radius:(CGFloat)r {
    // Remove old blur if any
    for (UIView *sv in view.subviews) {
        if ([sv isKindOfClass:[UIVisualEffectView class]]) { [sv removeFromSuperview]; break; }
    }
    UIVisualEffectView *blur = [self makeBlurView:UIBlurEffectStyleSystemUltraThinMaterialDark radius:r];
    blur.frame = view.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [view insertSubview:blur atIndex:0];

    view.backgroundColor = [UIColor colorWithWhite:1 alpha:0.04];
    view.layer.cornerRadius = r;
    view.layer.borderWidth = 0.6;
    view.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
}

+ (UIVisualEffectView *)makeBlurView:(UIBlurEffectStyle)style radius:(CGFloat)r {
    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:style]];
    v.layer.cornerRadius = r;
    v.clipsToBounds = YES;
    return v;
}

// ─── Typography ───────────────────────────────────────────────────────────────
+ (UIFont *)fontTitle    { return [UIFont systemFontOfSize:28 weight:UIFontWeightBold]; }
+ (UIFont *)fontHeadline { return [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]; }
+ (UIFont *)fontBody     { return [UIFont systemFontOfSize:15 weight:UIFontWeightRegular]; }
+ (UIFont *)fontSubhead  { return [UIFont systemFontOfSize:13 weight:UIFontWeightMedium]; }
+ (UIFont *)fontCaption  { return [UIFont systemFontOfSize:11 weight:UIFontWeightRegular]; }
+ (UIFont *)fontMono     { return [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular]; }

// ─── Legacy compat shims ──────────────────────────────────────────────────────
+ (UIColor *)mainBackgroundColor { return [self bg]; }
+ (UIColor *)liquidColor         { return [self accent]; }
+ (void)applyLiquidStyleToView:(UIView *)view cornerRadius:(CGFloat)r {
    view.backgroundColor = [self accent];
    view.layer.cornerRadius = r;
    view.layer.shadowColor = [UIColor blackColor].CGColor;
    view.layer.shadowOffset = CGSizeMake(0, 4);
    view.layer.shadowOpacity = 0.4;
    view.layer.shadowRadius = 10;
}
+ (void)applyGlassStyleToView:(UIView *)view cornerRadius:(CGFloat)r {
    [self applyGlassToView:view radius:r];
}
@end

// ─── LiquidGlassView (legacy compat) ─────────────────────────────────────────
@implementation LiquidGlassView {
    CAShapeLayer *_hl;
}
- (instancetype)initWithFrame:(CGRect)f cornerRadius:(CGFloat)r {
    self = [super initWithFrame:f];
    if (self) { _cornerRadius = r; [self setup]; }
    return self;
}
- (void)setup {
    self.backgroundColor = [ThemeEngine accent];
    self.layer.cornerRadius = _cornerRadius;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(0,5);
    self.layer.shadowOpacity = 0.4;
    self.layer.shadowRadius = 12;
    _hl = [CAShapeLayer layer];
    _hl.fillColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
    [self.layer addSublayer:_hl];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect t = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height * 0.45);
    _hl.path = [UIBezierPath bezierPathWithRoundedRect:t
        byRoundingCorners:UIRectCornerTopLeft|UIRectCornerTopRight
        cornerRadii:CGSizeMake(_cornerRadius,_cornerRadius)].CGPath;
}
@end
