// CGSliderNumbers — hiện số bên cạnh thanh trượt ở trang Cài đặt.
// 0.2.1: class con biên dịch sẵn của PSSliderCell -> cả gói Cài đặt không nạp được.
// 0.2.2: móc runtime vào PSSliderCell -> gói nạp được nhưng số vẫn không hiện
//        (không có bằng chứng móc chạy trúng class/thời điểm, lại im lặng hoàn toàn).
// 0.2.3: bỏ móc class hệ thống. Controller tự gắn nhãn số cho từng ô của CHÍNH
//        trang mình qua cellForRow + willDisplayCell — hai hàm chắc chắn được gọi
//        cho mọi ô của trang, không phụ thuộc class hệ thống nào.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Ô này có thanh trượt bên trong không?
BOOL CGCellHasSlider(UITableViewCell *cell);
// Tạo nhãn số + gắn sự kiện kéo cho ô (gọi một lần mỗi ô, trong cellForRow).
void CGAttachSliderNumber(UITableViewCell *cell);
// Đặt vị trí nhãn, thu ngắn thanh trượt, cập nhật con số (gọi trong willDisplayCell
// và mỗi khi người dùng kéo). unit = nil thì ẩn nhãn.
void CGLayoutSliderNumber(UITableViewCell *cell, NSString *unit);
