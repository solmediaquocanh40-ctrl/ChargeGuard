#import "CGTheme.h"

static NSString * const kModeKey = @"CGThemeMode";

@implementation CGTheme

+ (NSInteger)mode { return [[NSUserDefaults standardUserDefaults] integerForKey:kModeKey]; }
+ (void)setMode:(NSInteger)mode {
    [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:kModeKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
+ (NSArray<NSString *> *)modeNames {
    return @[@"Theo hệ thống", @"Đen tuyền", @"Ngọc lục bảo", @"Xanh dương", @"Tím", @"Cam", @"Hồng", @"Ảnh tuỳ chọn"];
}
+ (NSString *)imagePath { return @"/var/mobile/Documents/ChargeGuard-theme.jpg"; }

+ (BOOL)saveBackgroundImage:(UIImage *)img {
    NSData *data = UIImageJPEGRepresentation(img, 0.85);
    return [data writeToFile:[self imagePath] atomically:YES];
}
+ (void)removeBackgroundImage {
    [[NSFileManager defaultManager] removeItemAtPath:[self imagePath] error:nil];
}

+ (UIColor *)backgroundColorForMode:(NSInteger)mode {
    switch (mode) {
        case 1: return [UIColor blackColor];
        case 2: return [UIColor colorWithRed:0.02 green:0.16 blue:0.12 alpha:1];
        case 3: return [UIColor colorWithRed:0.03 green:0.10 blue:0.24 alpha:1];
        case 4: return [UIColor colorWithRed:0.13 green:0.05 blue:0.22 alpha:1];
        case 5: return [UIColor colorWithRed:0.25 green:0.11 blue:0.02 alpha:1];
        case 6: return [UIColor colorWithRed:0.24 green:0.05 blue:0.13 alpha:1];
        default: return nil;
    }
}
+ (UIColor *)accentForMode:(NSInteger)mode {
    switch (mode) {
        case 2: return [UIColor colorWithRed:0.10 green:0.85 blue:0.60 alpha:1];
        case 3: return [UIColor colorWithRed:0.35 green:0.65 blue:1.0 alpha:1];
        case 4: return [UIColor colorWithRed:0.75 green:0.55 blue:1.0 alpha:1];
        case 5: return [UIColor colorWithRed:1.0 green:0.62 blue:0.25 alpha:1];
        case 6: return [UIColor colorWithRed:1.0 green:0.45 blue:0.65 alpha:1];
        default: return [UIColor systemGreenColor];
    }
}

+ (void)applyToTableView:(UITableView *)tv {
    NSInteger mode = [self mode];
    if (mode == 7) {
        UIImage *img = [UIImage imageWithContentsOfFile:[self imagePath]];
        if (img) {
            UIImageView *bg = [[UIImageView alloc] initWithImage:img];
            bg.contentMode = UIViewContentModeScaleAspectFill;
            bg.clipsToBounds = YES;
            UIView *dim = [[UIView alloc] initWithFrame:bg.bounds];
            dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.22];
            dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [bg addSubview:dim];
            tv.backgroundView = bg;
            tv.backgroundColor = [UIColor clearColor];
            return;
        }
    }
    UIColor *c = [self backgroundColorForMode:mode];
    tv.backgroundView = nil;
    tv.backgroundColor = c ?: [UIColor systemGroupedBackgroundColor];
}

+ (void)applyAccentToWindow:(UIWindow *)window {
    window.tintColor = [self accentForMode:[self mode]];
}

@end
