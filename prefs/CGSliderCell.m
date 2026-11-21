#import "CGSliderCell.h"

@implementation CGSliderCell {
    UILabel *_valueLabel;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        _valueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _valueLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        _valueLabel.textColor = [UIColor secondaryLabelColor];
        _valueLabel.textAlignment = NSTextAlignmentRight;
        UISlider *slider = nil;
        if ([self respondsToSelector:@selector(control)]) slider = [self control];
        if (slider) {
            [slider addTarget:self action:@selector(cgSliderMoved:) forControlEvents:UIControlEventValueChanged];
            // nhãn nằm cùng superview với thanh trượt để toạ độ luôn khớp
            [slider.superview ?: self.contentView addSubview:_valueLabel];
        } else {
            [self.contentView addSubview:_valueLabel];
        }
        [self cgUpdateLabel];
    }
    return self;
}

- (void)cgSliderMoved:(UISlider *)slider {
    [self cgUpdateLabel];
}

- (void)cgUpdateLabel {
    UISlider *slider = nil;
    if ([self respondsToSelector:@selector(control)]) slider = [self control];
    if (!slider) { _valueLabel.text = @""; return; }
    NSString *unit = [self.specifier propertyForKey:@"CGUnit"];
    if (![unit isKindOfClass:[NSString class]]) unit = @"";
    _valueLabel.text = [NSString stringWithFormat:@"%d%@", (int)lroundf(slider.value), unit];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    UISlider *slider = nil;
    if ([self respondsToSelector:@selector(control)]) slider = [self control];
    if (!slider) return;
    [self cgUpdateLabel];
    UIView *host = _valueLabel.superview ?: self.contentView;
    CGFloat labelW = 58;
    CGRect hb = host.bounds;
    _valueLabel.frame = CGRectMake(CGRectGetMaxX(hb) - labelW - 10, 0, labelW, CGRectGetHeight(hb));
    // thu ngắn thanh trượt để chừa chỗ cho nhãn số (chỉ khi slider cùng host với nhãn)
    if (slider.superview == host) {
        CGRect f = slider.frame;
        CGFloat maxW = CGRectGetMinX(_valueLabel.frame) - CGRectGetMinX(f) - 8;
        if (maxW > 60 && f.size.width > maxW) {
            f.size.width = maxW;
            slider.frame = f;
        }
    }
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    [self cgUpdateLabel];
}

@end
