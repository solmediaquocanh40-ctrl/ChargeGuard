// CGSliderNumbers — hiện số bên cạnh thanh trượt ở trang Cài đặt (0.2.2).
// Bản 0.2.1 dùng class con biên dịch sẵn của PSSliderCell và làm cả gói Cài đặt
// không tải được trên máy thật, nên 0.2.2 đổi hẳn cách làm: KHÔNG tham chiếu
// PSSliderCell lúc biên dịch — lúc chạy mới dò class bằng runtime rồi móc vào
// hàm layoutSubviews của nó. Dò không thấy class thì trang Cài đặt vẫn chạy
// bình thường với thanh trượt gốc, chỉ là không có số.
#import <Foundation/Foundation.h>

void CGInstallSliderNumbers(void);
