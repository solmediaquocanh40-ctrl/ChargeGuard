// CGSliderCell — ô thanh trượt có hiện số ở trang Cài đặt ChargeGuard (0.2.1).
// Ô trượt mặc định của iOS không hiện giá trị nên người dùng kéo mà không biết
// đang chọn số mấy; ô này thêm một nhãn số ở mép phải, cập nhật theo thời gian thực.
// Đơn vị lấy từ khoá CGUnit trong specifier của Root.plist (%, °C...).
#import <UIKit/UIKit.h>

@interface PSSpecifier : NSObject
- (id)propertyForKey:(NSString *)key;
@end

// Khai báo tối thiểu phần cần dùng của Preferences (bundle không link framework
// Preferences, các class được nối ở runtime — đúng mẫu ChargeGuardPrefs từ đầu).
@interface PSSliderCell : UITableViewCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier;
- (UISlider *)control;
- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier;
@property (nonatomic, strong) PSSpecifier *specifier;
@end

@interface CGSliderCell : PSSliderCell
@end
