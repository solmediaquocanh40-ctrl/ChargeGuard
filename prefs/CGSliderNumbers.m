#import "CGSliderNumbers.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static char kCGValueLabelKey;
static IMP gOrigLayoutSubviews = NULL;

// Tìm thanh trượt trong cây view của ô (hàm đệ quy thường, không dùng block tự gọi).
static UISlider *CGFindSlider(UIView *v) {
    if ([v isKindOfClass:[UISlider class]]) return (UISlider *)v;
    for (UIView *sub in v.subviews) {
        UISlider *s = CGFindSlider(sub);
        if (s) return s;
    }
    return nil;
}

// Đọc một property của specifier bằng runtime, không cần header của Preferences.
static id CGSpecProperty(id spec, NSString *key) {
    if (spec && [spec respondsToSelector:@selector(propertyForKey:)]) {
        return ((id (*)(id, SEL, id))objc_msgSend)(spec, @selector(propertyForKey:), key);
    }
    return nil;
}

static void CGRefreshLabel(UITableViewCell *cell, UISlider *slider) {
    UILabel *label = objc_getAssociatedObject(cell, &kCGValueLabelKey);
    if (!label || !slider) return;
    id spec = nil;
    if ([cell respondsToSelector:@selector(specifier)])
        spec = ((id (*)(id, SEL))objc_msgSend)(cell, @selector(specifier));
    id unit = CGSpecProperty(spec, @"CGUnit");
    if (![unit isKindOfClass:[NSString class]]) unit = @"";
    label.text = [NSString stringWithFormat:@"%d%@", (int)lroundf(slider.value), unit];
}

@interface CGSliderNumHandler : NSObject
+ (instancetype)shared;
- (void)cgMoved:(UISlider *)slider;
@end

@implementation CGSliderNumHandler
+ (instancetype)shared {
    static CGSliderNumHandler *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[CGSliderNumHandler alloc] init]; });
    return s;
}
- (void)cgMoved:(UISlider *)slider {
    UIView *v = slider;
    while (v && ![v isKindOfClass:[UITableViewCell class]]) v = v.superview;
    if (v) CGRefreshLabel((UITableViewCell *)v, slider);
}
@end

static void CGSliderLayoutSubviews(id self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigLayoutSubviews)(self, _cmd);
    UITableViewCell *cell = (UITableViewCell *)self;
    id spec = nil;
    if ([cell respondsToSelector:@selector(specifier)])
        spec = ((id (*)(id, SEL))objc_msgSend)(cell, @selector(specifier));
    // Chỉ đụng vào thanh trượt của ChargeGuard: specifier của mình có khoá CGUnit,
    // thanh trượt hệ thống ở nơi khác trong Cài đặt không có khoá này nên để yên.
    if (!CGSpecProperty(spec, @"CGUnit")) return;
    UISlider *slider = CGFindSlider(cell.contentView);
    if (!slider || !slider.superview) return;

    UILabel *label = objc_getAssociatedObject(cell, &kCGValueLabelKey);
    if (!label) {
        label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        label.textColor = [UIColor secondaryLabelColor];
        label.textAlignment = NSTextAlignmentRight;
        [slider.superview addSubview:label];
        objc_setAssociatedObject(cell, &kCGValueLabelKey, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [slider addTarget:[CGSliderNumHandler shared] action:@selector(cgMoved:) forControlEvents:UIControlEventValueChanged];
    }
    CGFloat labelW = 58;
    CGRect hb = slider.superview.bounds;
    label.frame = CGRectMake(CGRectGetMaxX(hb) - labelW - 10, 0, labelW, CGRectGetHeight(hb));
    CGRect f = slider.frame;
    CGFloat maxW = CGRectGetMinX(label.frame) - CGRectGetMinX(f) - 8;
    if (maxW > 60 && f.size.width > maxW) {
        f.size.width = maxW;
        slider.frame = f;
    }
    CGRefreshLabel(cell, slider);
}

void CGInstallSliderNumbers(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class c = objc_getClass("PSSliderCell");
        if (!c) return; // không thấy class: giữ thanh trượt gốc, không làm gì cả
        Method m = class_getInstanceMethod(c, @selector(layoutSubviews));
        if (!m) return;
        gOrigLayoutSubviews = method_getImplementation(m);
        // Nếu PSSliderCell chỉ thừa kế layoutSubviews từ class cha thì THÊM bản
        // ghi đè riêng cho nó (không đụng class cha); có sẵn của riêng nó mới thay.
        if (!class_addMethod(c, @selector(layoutSubviews), (IMP)CGSliderLayoutSubviews, "v@:")) {
            method_setImplementation(m, (IMP)CGSliderLayoutSubviews);
        }
    });
}
