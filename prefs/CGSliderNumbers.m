#import "CGSliderNumbers.h"
#import <objc/runtime.h>
#import <objc/message.h>

static char kCGValueLabelKey;

// Tìm thanh trượt trong cây view của ô (hàm đệ quy thường, không dùng block tự gọi).
static UISlider *CGFindSlider(UIView *v) {
    if ([v isKindOfClass:[UISlider class]]) return (UISlider *)v;
    for (UIView *sub in v.subviews) {
        UISlider *s = CGFindSlider(sub);
        if (s) return s;
    }
    return nil;
}

static UILabel *CGLabelForCell(UITableViewCell *cell) {
    return objc_getAssociatedObject(cell, &kCGValueLabelKey);
}

// Đọc CGUnit của specifier gắn với ô, hoàn toàn bằng runtime (không cần header Preferences).
static NSString *CGUnitForCell(UITableViewCell *cell) {
    id spec = nil;
    if ([cell respondsToSelector:@selector(specifier)])
        spec = ((id (*)(id, SEL))objc_msgSend)(cell, @selector(specifier));
    id unit = nil;
    if (spec && [spec respondsToSelector:@selector(propertyForKey:)])
        unit = ((id (*)(id, SEL, id))objc_msgSend)(spec, @selector(propertyForKey:), @"CGUnit");
    return [unit isKindOfClass:[NSString class]] ? unit : nil;
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
    if (v) {
        UITableViewCell *cell = (UITableViewCell *)v;
        CGLayoutSliderNumber(cell, CGUnitForCell(cell));
    }
}
@end

BOOL CGCellHasSlider(UITableViewCell *cell) {
    return CGFindSlider(cell.contentView) != nil;
}

void CGAttachSliderNumber(UITableViewCell *cell) {
    if (CGLabelForCell(cell)) return;
    UISlider *slider = CGFindSlider(cell.contentView);
    if (!slider || !slider.superview) return;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    label.textColor = [UIColor secondaryLabelColor];
    label.textAlignment = NSTextAlignmentRight;
    [slider.superview addSubview:label];
    objc_setAssociatedObject(cell, &kCGValueLabelKey, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [slider addTarget:[CGSliderNumHandler shared] action:@selector(cgMoved:) forControlEvents:UIControlEventValueChanged];
}

void CGLayoutSliderNumber(UITableViewCell *cell, NSString *unit) {
    UILabel *label = CGLabelForCell(cell);
    if (!label) return;
    if (!unit) { label.hidden = YES; return; }
    UISlider *slider = CGFindSlider(cell.contentView);
    if (!slider || !slider.superview) { label.hidden = YES; return; }
    label.hidden = NO;
    UIView *host = slider.superview;
    CGFloat labelW = 58;
    label.frame = CGRectMake(CGRectGetMaxX(host.bounds) - labelW - 10, 0, labelW, CGRectGetHeight(host.bounds));
    CGRect f = slider.frame;
    CGFloat maxW = CGRectGetMinX(label.frame) - CGRectGetMinX(f) - 8;
    if (maxW > 60 && f.size.width > maxW) {
        f.size.width = maxW;
        slider.frame = f;
    }
    label.text = [NSString stringWithFormat:@"%d%@", (int)lroundf(slider.value), unit];
}
