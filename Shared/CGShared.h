// CGShared.h - hằng số dùng chung cho daemon, tweak, bảng Cài đặt và app (0.2.3)
#ifndef CGSHARED_H
#define CGSHARED_H

#import <Foundation/Foundation.h>

// Domain tùy chọn (file nằm ở /var/mobile/Library/Preferences/<domain>.plist)
#define CG_DOMAIN        @"com.chargeguard.prefs"
#define CG_PREFS_PATH    @"/var/mobile/Library/Preferences/com.chargeguard.prefs.plist"
#define CG_PREFS_NOTIFY  "com.chargeguard/prefsChanged"

// File trạng thái do daemon ghi, các phần khác đọc (ở /var/tmp, ghi mỗi 15 giây)
#define CG_STATUS_PATH   @"/var/tmp/chargeguard.status.plist"
#define CG_RESTORE_FLAG  @"/var/tmp/chargeguard.restore"

// 0.2.0: log chuyển về Documents cho bền (gỡ tweak / khởi động lại vẫn còn),
// trạng thái riêng của daemon (phương thức ngắt sạc đã thắng...) nằm ở file riêng
// do daemon sở hữu, lịch sử sạc và sổ mất điện cũng ở Documents.
#define CG_LOG_PATH      @"/var/mobile/Documents/ChargeGuard.log"
#define CG_LOG_PATH_OLD  @"/var/tmp/chargeguard.log"
#define CG_DAEMON_STATE  @"/var/mobile/Library/ChargeGuardState.plist"
#define CG_HISTORY_PATH  @"/var/mobile/Documents/ChargeGuard-history.plist"
#define CG_OUTAGE_PATH   @"/var/mobile/Documents/ChargeGuard-outages.plist"

// ---- Khóa cài đặt: giới hạn sạc ----
#define K_ENABLED        @"enabled"          // BOOL, công tắc tổng
#define K_LIMIT          @"limit"            // int 10-100 (0.2.0: thanh trượt tự do)
#define K_HYST           @"hysteresis"       // int, sạc lại khi thấp hơn giới hạn bấy nhiêu %
#define K_TEMP_ON        @"tempOn"           // BOOL
#define K_TEMP_MAX       @"tempMax"          // int, độ C
#define K_TEMP_EMERG     @"tempEmerg"        // int, độ C: vệ sĩ nhiệt khẩn cấp (0.2.3)
#define K_FULL_ONCE      @"fullOnceStamp"    // double, mốc thời gian lúc bấm "Sạc đầy một lần"
#define K_SCHED_ON       @"schedOn"          // BOOL
#define K_SCHED_HOUR     @"schedHour"        // int 0-23, giờ cho sạc đầy
#define K_SCHED_MIN_BEFORE @"schedBefore"    // int, bắt đầu sạc đầy trước giờ này bấy nhiêu phút
#define K_NOTIFY         @"notifyLimit"      // BOOL, thông báo khi chạm giới hạn
#define K_LOWBAT_ON      @"lowBatOn"         // BOOL
#define K_LOWBAT_LEVEL   @"lowBatLevel"      // int %
#define K_LOG            @"logOn"            // BOOL

// ---- Khóa cài đặt 0.2.0: sạc thông minh ----
#define K_AUTO_ON        @"autoOn"           // BOOL, chế độ tự động toàn phần (tự chọn thông số theo sức khoẻ pin)
#define K_PULSE_ON       @"pulseOn"          // BOOL, sạc xung (ngắt/nhả theo nhịp cho mát pin)
#define K_PULSE_TEMP     @"pulseTemp"        // int °C, nóng tới đây thì bắt đầu xung khi đang sạc lên
#define K_PULSE_ON_MIN   @"pulseOnMin"       // int phút sạc trong một nhịp
#define K_PULSE_OFF_MIN  @"pulseOffMin"      // int phút nghỉ trong một nhịp
#define K_PULSE_NIGHT_ON @"pulseNightOn"     // BOOL, ban đêm luôn xung dù chưa nóng
#define K_PULSE_NIGHT_START @"pulseNightStart" // int giờ 0-23
#define K_PULSE_NIGHT_END   @"pulseNightEnd"   // int giờ 0-23
#define K_STORAGE_ON     @"storageOn"        // BOOL, chế độ pin lưu kho khi cắm sạc lâu
#define K_STORAGE_LEVEL  @"storageLevel"     // int 40-70 %
#define K_STORAGE_HOURS  @"storageHours"     // int giờ cắm liên tục thì về lưu kho
#define K_BOOST_UNTIL    @"boostUntil"       // double, sạc cấp tốc tới mốc thời gian này
#define K_BOOST_MINUTES  @"boostMinutes"     // int phút cho nút sạc cấp tốc
#define K_CAL_ON         @"calOn"            // BOOL, sạc đầy theo sự kiện Lịch (tweak ghi cờ dưới đây)
#define K_CAL_BEFORE     @"calBefore"        // int phút trước sự kiện thì sạc đầy
#define K_CAL_FULL_STAMP @"calFullStamp"     // double, tweak đặt khi sắp có sự kiện
#define K_CABLE_ON       @"cableOn"          // BOOL, cảnh báo cáp/củ sạc chập chờn
#define K_CABLE_COUNT    @"cableCount"       // int số lần ngắt-nối trong 10 phút thì kết luận cáp dỏm
#define K_OUTAGE_ON      @"outageOn"         // BOOL, ghi nhận mất điện (phần tweak lo)
#define K_OUTAGE_MIN     @"outageMin"        // int phút mất tối thiểu mới ghi
#define K_ALARM_ON       @"alarmOn"          // BOOL, báo động khi bị rút sạc (phần tweak lo)
#define K_NATIVE_OK      @"nativeOverride"   // BOOL, vẫn dùng ChargeGuard dù máy có giới hạn sạc gốc

// ---- Khóa cài đặt 0.2.0: hồ sơ theo nơi chốn (phần tweak ghi mức hiệu lực) ----
#define K_HOME_WIFI      @"homeWifi"         // NSString tên Wi-Fi nhà
#define K_HOME_LIMIT     @"homeLimit"        // int % khi ở nhà
#define K_AWAY_FULL      @"awayFull"         // BOOL, ra khỏi nhà thì sạc đầy
#define K_CTX_LIMIT      @"ctxLimit"         // int %, 0 = không áp dụng (tweak ghi)
#define K_CTX_STAMP      @"ctxStamp"         // double, mốc lúc tweak ghi (quá 10 phút thì bỏ qua)

// ---- Khóa cài đặt: tiết kiệm khi tắt màn hình ----
#define K_SAVE_ON        @"saveOn"           // BOOL, công tắc tổng phần tiết kiệm
#define K_SAVE_DELAY     @"saveDelay"        // int phút sau khi khóa mới bắt đầu
#define K_SAVE_CHARGING  @"saveWhileCharging"// BOOL, vẫn tiết kiệm khi đang sạc
#define K_PROFILE        @"profile"          // 0 tùy chỉnh, 1 nhẹ, 2 cân bằng, 3 mạnh
#define K_S_CPU          @"sCPU"             // giảm CPU nền
#define K_S_CPU_LEVEL    @"sCPULevel"        // int % CPU nền: app ngốn hơn mức này mới bị đóng băng (0.2.3)
#define K_S_FREEZE       @"sFreeze"          // đóng băng app nền (0.2.0: chỉ app ngốn CPU nếu bật sCPU)
#define K_S_BT           @"sBluetooth"
#define K_S_LOC          @"sLocation"
#define K_S_AIRDROP      @"sAirDrop"
#define K_S_LPM          @"sLowPower"        // bật Chế độ nguồn điện thấp khi khóa
#define K_EXCEPT         @"exceptApps"       // NSArray bundle id ngoại lệ
// Hai khoá sBGRefresh / sRaiseToWake của 0.1.0 bị loại hẳn: không có cơ chế
// hệ thống đáng tin để tweak đọc/ghi chúng, để lại chỉ tổ gây hiểu lầm.

// ---- Khóa cài đặt 0.2.1 ----
// Chỉnh kích thước icon ĐÃ GỠ khỏi ChargeGuard theo yêu cầu của anh Quoc
// (sẽ làm thành tweak riêng); hai khoá iconOn/iconScale cũ không còn ai đọc.
#define K_FLOOR          @"floorLevel"       // int 5-30 %: mức an toàn tối thiểu, dưới mức này không bao giờ giữ sạc (0.2.0 là hằng số 20 trong daemon, 0.2.1 cho chọn)
#define K_NOTIFY_FAIL    @"notifyFail"       // BOOL, báo khi máy không cho ngắt sạc

// ---- Khóa cài đặt 0.2.1: làm mát khi sạc ----
#define K_COOL_ON        @"coolEnabled"      // BOOL, công tắc tổng làm mát khi sạc
#define K_COOL_TEMP      @"coolTemp"         // int °C, nóng từ mức này thì làm mát
#define K_COOL_SLOW      @"coolSlowCharge"   // BOOL, sạc chậm theo nhịp 3-1 khi nóng (daemon)
#define K_COOL_APPS      @"coolApps"         // BOOL, giảm CPU app nền ngốn khi nóng (tweak)
#define K_COOL_LPM       @"coolLPM"          // BOOL, bật Chế độ nguồn điện thấp khi nóng (tweak)
#define K_COOL_DIM       @"coolDimScreen"    // BOOL, giảm độ sáng màn hình khi nóng (tweak)
#define K_COOL_DIMLV     @"coolDimLevel"     // int %, mức sáng tối đa khi làm mát
#define K_COOL_AIR       @"coolAirplane"     // BOOL, nóng hơn ngưỡng +3°C thì bật chế độ máy bay (tweak, thử nghiệm)
#define K_COOL_NOTIFY    @"coolNotify"       // BOOL, thông báo khi làm mát bắt đầu/kết thúc

// ---- Khóa thống kê (app ghi) ----
#define K_STAT_CYCLES0   @"statCyclesBase"   // int chu kỳ tại lần mở app đầu tiên của tháng
#define K_STAT_MONTH     @"statMonth"        // int tháng của mốc trên

// ---- Khóa trạng thái (daemon ghi) ----
#define S_PERCENT        @"percent"
#define S_CHARGING       @"charging"
#define S_EXTERNAL       @"external"
#define S_TEMP           @"tempC"
#define S_AMPS           @"amps"
#define S_CYCLES         @"cycles"
#define S_HEALTH         @"healthPct"
#define S_HOLDING        @"holding"          // đang giữ (đã ngắt sạc)
#define S_SUPPORTED      @"supported"        // 1 hỗ trợ ngắt sạc, 0 không, -1 chưa biết
#define S_METHOD         @"method"
#define S_MESSAGE        @"message"
#define S_TIME           @"time"
#define S_PULSE          @"pulse"            // 0.2.0: đang trong nhịp nghỉ của sạc xung
#define S_STORAGE        @"storageMode"      // 0.2.0: đang ở chế độ lưu kho
#define S_BOOST          @"boost"            // 0.2.0: đang sạc cấp tốc
#define S_EMERG          @"emergency"        // 0.2.0: vệ sĩ nhiệt đã kích hoạt
#define S_NATIVE         @"nativeLimit"      // 0.2.0: máy có vẻ đã bật giới hạn sạc gốc của Apple
#define S_CABLEWARN      @"cableWarn"        // 0.2.0: số lần chập chờn trong 10 phút gần nhất
#define S_ANOMALY        @"anomaly"          // 0.2.0: dấu hiệu pin bất thường (chuỗi, rỗng = không có)
#define S_COOL           @"cooling"          // 0.2.1: đang ở trạng thái làm mát khi sạc (pin nóng >= ngưỡng)

#endif
