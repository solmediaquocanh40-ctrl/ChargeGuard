# ChargeGuard 0.2.2

Giới hạn mức sạc pin, sạc thông minh và tiết kiệm pin khi tắt màn hình cho máy jailbreak iOS 14–18 (rootless là chính, vẫn build kèm rootful và roothide). Cài xong có **cả trang trong Cài đặt lẫn app ngoài màn hình chính** — hai nơi dùng chung một kho cài đặt, chỉnh ở đâu cũng ăn.

## Có gì mới ở 0.2.2
- **Sửa lỗi trang Cài đặt không tải được** ở 0.2.1: cách gắn nhãn số cho thanh trượt bằng class con biên dịch sẵn làm cả gói Cài đặt lỗi khi nạp. 0.2.2 gắn số bằng móc runtime — không thấy class hệ thống thì tự bỏ qua, trang Cài đặt vẫn chạy với thanh trượt gốc.
- Script cài đặt ghi kết quả đăng ký app (uicache) vào log để chẩn đoán từ xa nếu app vẫn chưa hiện icon.

## Có gì mới ở 0.2.1
- **Sửa lỗi không hiện icon app** sau khi cài (bản 0.2.0 thiếu bước đăng ký app với hệ thống).
- **Mọi thanh trượt trong Cài đặt hiện số** ở mép phải, kéo tới đâu số chạy tới đó.
- **Mới: Làm mát khi sạc** — pin nóng tới ngưỡng bạn chọn thì máy tự làm mát: sạc chậm theo nhịp 3–1, giảm CPU app nền ngốn, bật Chế độ nguồn điện thấp, tuỳ chọn giảm độ sáng và (thử nghiệm) chế độ máy bay khi nóng hơn nữa. Pin nguội hoặc rút sạc là mọi thứ khôi phục nguyên trạng.
- **Mức an toàn tối thiểu** giờ cho chọn 5–30% (trước đây cố định 20%), thêm công tắc riêng cho thông báo "máy không cho ngắt sạc".
- **Gỡ chỉnh kích thước icon** khỏi ChargeGuard — tính năng này sẽ thành một tweak riêng.

## ChargeGuard làm được gì

**Giới hạn sạc (daemon chạy quyền root)**
- Ngưng sạc ở mức tự chọn **10–100%** (thanh trượt), có độ lệch để không ngắt–nối liên tục. Daemon tự thử nhiều cách ngắt sạc (khoá SMC, thuộc tính IORegistry), **tự kiểm chứng cách nào chạy thật mới dùng**, và **nhớ cách đã thắng** cho lần sau. Máy nào không cho ngắt thì báo rõ "không hỗ trợ", máy vẫn sạc bình thường.
- An toàn là trên hết: mặc định TẮT; pin dưới 20% luôn được sạc; daemon bị tắt là sạc được mở lại ngay.
- **Vệ sĩ nhiệt:** pin nóng quá ngưỡng thường thì tạm ngừng, nóng quá ngưỡng khẩn cấp (tự chọn) thì ngắt ngay kể cả đang sạc đầy một lần.
- **Sạc xung:** sạc một đoạn, nghỉ một đoạn theo nhịp phút tự chọn — tự chạy khi pin nóng hoặc trong khung giờ đêm bạn đặt.
- **Chế độ lưu kho:** cắm sạc liên tục nhiều giờ thì tự giữ ở mức lưu kho 40–70%.
- **Sạc đầy một lần**, **sạc cấp tốc** (bỏ qua giới hạn trong số phút tự chọn, hết giờ tự tắt), **lịch sạc đầy trước giờ dậy**, **sạc đầy theo sự kiện trong Lịch**.
- **Hồ sơ theo nơi chốn:** ở Wi-Fi nhà thì giữ một mức riêng, ra ngoài thì tuỳ chọn sạc đầy.
- **Chế độ tự động toàn phần:** tự chọn mức giữ theo sức khoẻ pin (pin khoẻ giữ 80, pin chai giữ thấp hơn).
- Máy có giới hạn sạc gốc của Apple (iPhone đời mới, iOS 17+) thì ChargeGuard tự nhường, trừ khi bạn cho phép dùng tiếp.
- **Cảnh báo cáp/củ chập chờn** (ngắt–nối liên tục), **phát hiện pin bất thường** (tụt % đột ngột, nhiệt nhảy vọt), **ghi nhận mất điện** khi sạc bị ngắt lúc máy đang khoá, **báo động rút sạc**.

**Tiết kiệm pin khi tắt màn hình (phần SpringBoard)**
- Khoá máy sau số phút bạn chọn thì: giảm CPU app nền, đóng băng app nền, tắt Bluetooth/định vị/AirDrop, bật nguồn điện thấp — mở màn hình là khôi phục hết.
- Bản 0.2.0 **đo CPU nền thật của từng app** và chỉ đóng băng app ngốn trên ngưỡng bạn đặt; app ngoan chỉ bị giảm ưu tiên. Pin đang nóng thì không đóng băng. Đang gọi, đang phát nhạc, đang cắm sạc (nếu bạn chọn) thì không đụng vào.
- Phần này chỉ chạm vào tiến trình, **không đụng vào hiển thị — chữ trong app không bị mờ**.

**App ngoài màn hình chính**
- Tab Tổng quan: % pin, trạng thái, nhiệt độ, chu kỳ, sức khoẻ pin, phương thức ngắt sạc, **dự báo tuổi thọ pin**, tổng giờ đã giữ ở giới hạn, sổ mất điện; bật/tắt và kéo mức ngưng sạc ngay tại đây; nút sạc đầy một lần, sạc cấp tốc, khôi phục.
- Tab Biểu đồ: biểu đồ % pin và nhiệt độ 24 giờ (daemon ghi mẫu mỗi ~5 phút), **đo củ/cáp sạc trong 60 giây** và chấm điểm, lưu lịch sử các lần đo.
- Tab Cài đặt: **chọn nền app** (màu có sẵn hoặc ảnh của bạn), xuất/nhập file cài đặt, **báo cáo pin hằng tháng**, chia sẻ log, respring, đặt lại mặc định.

**Trang trong Cài đặt** — đầy đủ mọi công tắc và thông số (tất cả đều gắn số chọn được: mức %, nhiệt °C, phút/giờ, số lần), dòng trạng thái chẩn đoán, nút respring, đặt lại mặc định, xuất/nhập cài đặt, chép log kèm chẩn đoán (model máy, bản iOS, phương thức ngắt sạc).

**Làm mát khi sạc (0.2.1):** một công tắc tổng + ngưỡng °C tự chọn. Daemon lo sạc chậm theo nhịp; phía SpringBoard lo giảm CPU app nền, nguồn điện thấp, độ sáng và chế độ máy bay. Mọi thay đổi đều tự khôi phục khi pin nguội.

## Giới hạn thật (nói trước cho rõ)
- Ngắt sạc được hay không phụ thuộc vào máy: daemon tự dò và tự kiểm chứng, không chạy được thì báo rõ chứ không giả vờ.
- Đo củ/cáp: số watt là ước tính phía pin, không phải số in trên củ sạc.
- Dự báo tuổi thọ pin là ước tính thô từ tốc độ thêm chu kỳ, chỉ để tham khảo.
- Đọc tên Wi-Fi và Lịch trong SpringBoard phụ thuộc quyền hệ thống cấp cho tiến trình hệ thống; không đọc được thì tính năng tương ứng nằm yên, có ghi trong log.

## Build
Đẩy toàn bộ thư mục lên repo GitHub (giữ thư mục .github), nhớ đặt file workflow vào `.github/workflows/build.yml`. Tab Actions build 3 bản: ChargeGuard-0.2.2-rootful, -rootless, -roothide. **Mỗi lần build lại phải đẩy commit mới** — nút Re-run chỉ chạy lại workflow của commit cũ.

## Dùng
Cài .deb bằng Sileo, respring. Vào Cài đặt > ChargeGuard hoặc mở app ChargeGuard ngoài màn hình.
Log: `Documents/ChargeGuard.log` (gỡ tweak vẫn còn). Trạng thái: `/var/tmp/chargeguard.status.plist`. Lịch sử sạc: `Documents/ChargeGuard-history.plist`.
