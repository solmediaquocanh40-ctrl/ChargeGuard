// CGTheme.h - nền cho app: màu có sẵn hoặc ảnh tuỳ chọn (kiểu đã làm cho TweakPacker).
#import <UIKit/UIKit.h>

@interface CGTheme : NSObject
+ (NSInteger)mode;                    // 0 hệ thống, 1 đen, 2 ngọc lục bảo, 3 xanh dương, 4 tím, 5 cam, 6 hồng, 7 ảnh
+ (void)setMode:(NSInteger)mode;
+ (NSArray<NSString *> *)modeNames;
+ (NSString *)imagePath;              // ảnh nền đã lưu (Documents)
+ (BOOL)saveBackgroundImage:(UIImage *)img;
+ (void)removeBackgroundImage;
+ (void)applyToTableView:(UITableView *)tv;
+ (void)applyAccentToWindow:(UIWindow *)window;
@end
