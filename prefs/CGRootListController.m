// CGRootListController 0.2.1 — trang Cài đặt của ChargeGuard.
// Giữ nguyên khung của bản cũ (trạng thái, hồ sơ, ngoại lệ, các nút công cụ)
// và thêm: sạc cấp tốc, respring, đặt lại mặc định, xuất/nhập file cài đặt,
// chẩn đoán đầy đủ (model máy, bản iOS, phương thức ngắt sạc) trong phần chép log.
#import "CGRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <notify.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <spawn.h>
#import "../Shared/CGShared.h"

extern char **environ;

@interface CGRootListController () <UIDocumentPickerDelegate>
@end

@implementation CGRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        // 0.2.1: mọi thanh trượt dùng ô CGSliderCell để hiện số khi kéo
        // (đặt cả trong Root.plist lẫn ở đây cho chắc chắn).
        for (PSSpecifier *spec in _specifiers) {
            if ([[spec propertyForKey:@"cell"] isEqualToString:@"PSSliderCell"]) {
                [spec setProperty:@"CGSliderCell" forKey:@"cellClass"];
            }
        }
    }
    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateStatusFooter];
}

// ---------- Tiện ích ghi cài đặt ----------
static void SetPref(NSString *key, id val) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)val, (__bridge CFStringRef)CG_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)CG_DOMAIN);
    notify_post(CG_PREFS_NOTIFY);
}

// ---------- Trạng thái ----------
- (void)updateStatusFooter {
    NSDictionary *s = [NSDictionary dictionaryWithContentsOfFile:CG_STATUS_PATH];
    NSString *text;
    if (!s) {
        text = @"Chưa có dữ liệu. Daemon chargeguardd chưa chạy hoặc chưa kịp ghi. Hãy đợi 15 giây rồi bấm Làm mới. Nếu vẫn trống, hãy khởi động lại máy hoặc gửi log.";
    } else {
        int sup = [s[S_SUPPORTED] intValue];
        NSString *supText = sup == 1 ? [NSString stringWithFormat:@"Ngắt sạc: hoạt động (%@)", s[S_METHOD]]
                          : sup == 0 ? @"Ngắt sạc: KHÔNG hỗ trợ trên máy này"
                                     : @"Ngắt sạc: chưa kiểm tra (sẽ thử khi pin chạm giới hạn)";
        NSMutableString *mode = [NSMutableString string];
        if ([s[S_STORAGE] boolValue]) [mode appendString:@" • lưu kho"];
        if ([s[S_PULSE] boolValue]) [mode appendString:@" • xung (đang nghỉ)"];
        if ([s[S_BOOST] boolValue]) [mode appendString:@" • cấp tốc"];
        if ([s[S_EMERG] boolValue]) [mode appendString:@" • VỆ SĨ NHIỆT"];
        if ([s[S_NATIVE] boolValue]) [mode appendString:@"\nMáy có vẻ đã bật giới hạn sạc gốc của Apple."];
        NSString *anomaly = s[S_ANOMALY];
        if ([anomaly isKindOfClass:[NSString class]] && anomaly.length)
            [mode appendFormat:@"\n⚠️ %@", anomaly];
        int cable = [s[S_CABLEWARN] intValue];
        if (cable >= 4) [mode appendFormat:@"\nCáp chập chờn: %d lần ngắt-nối/10 phút.", cable / 2];
        double age = [[NSDate date] timeIntervalSince1970] - [s[S_TIME] doubleValue];
        text = [NSString stringWithFormat:
                @"Pin: %@%%  •  %@%@\nNhiệt độ: %.1f°C  •  Dòng: %@ mA\nChu kỳ sạc: %@  •  Sức khoẻ pin: %@%%\n%@\n%@\n(cập nhật %.0f giây trước)",
                s[S_PERCENT],
                [s[S_HOLDING] boolValue] ? @"đang giữ (không sạc)" : ([s[S_CHARGING] boolValue] ? @"đang sạc" : ([s[S_EXTERNAL] boolValue] ? @"đã cắm, không sạc" : @"không cắm sạc")),
                mode,
                [s[S_TEMP] doubleValue], s[S_AMPS], s[S_CYCLES], [s[S_HEALTH] intValue] > 0 ? s[S_HEALTH] : @"?",
                supText, s[S_MESSAGE] ?: @"", age];
    }
    PSSpecifier *g = [self specifierForID:@"statusGroup"];
    if (g) {
        [g setProperty:text forKey:@"footerText"];
        [self reloadSpecifier:g animated:NO];
    }
}

- (void)refreshStatus { [self updateStatusFooter]; }

// ---------- Hồ sơ và ngoại lệ ----------
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)spec {
    [super setPreferenceValue:value specifier:spec];
    NSString *key = [spec propertyForKey:@"key"];
    notify_post(CG_PREFS_NOTIFY);
    if ([key isEqualToString:@"exceptText"]) {
        NSMutableArray *arr = [NSMutableArray array];
        for (NSString *part in [(NSString *)value componentsSeparatedByString:@","]) {
            NSString *t = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (t.length) [arr addObject:t];
        }
        SetPref(K_EXCEPT, arr);
    } else if ([key isEqualToString:@"profile"]) {
        int pr = [value intValue];
        if (pr >= 1 && pr <= 3) {
            //            CPU  Freeze BT   Loc   AirD  LPM
            BOOL t[4][6] = {{0},
                            {0, 0, 0, 0, 0, 1},   // Nhẹ: chỉ nguồn điện thấp
                            {1, 0, 1, 0, 0, 1},   // Cân bằng
                            {1, 1, 1, 1, 1, 1}};  // Mạnh
            NSArray *keys = @[K_S_CPU, K_S_FREEZE, K_S_BT, K_S_LOC, K_S_AIRDROP, K_S_LPM];
            for (int i = 0; i < 6; i++) SetPref(keys[i], @(t[pr][i]));
            [self reloadSpecifiers];
        }
    }
}

// ---------- Nút ----------
- (void)fullOnce {
    SetPref(K_FULL_ONCE, @([[NSDate date] timeIntervalSince1970]));
    [self alert:@"Sạc đầy một lần" message:@"Đã bật. Máy sẽ sạc tới 100% một lần rồi quay lại mức giới hạn."];
}

- (void)boostOnce {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:CG_PREFS_PATH] ?: @{};
    int mins = p[K_BOOST_MINUTES] ? [p[K_BOOST_MINUTES] intValue] : 15;
    SetPref(K_BOOST_UNTIL, @([[NSDate date] timeIntervalSince1970] + mins * 60));
    [self alert:@"Sạc cấp tốc" message:[NSString stringWithFormat:@"Đã bật sạc cấp tốc trong %d phút: bỏ qua mọi giới hạn, hết giờ tự quay về bình thường.", mins]];
}

- (void)restoreAll {
    [@"1" writeToFile:CG_RESTORE_FLAG atomically:YES encoding:NSUTF8StringEncoding error:nil];
    chmod([CG_RESTORE_FLAG fileSystemRepresentation], 0666);
    notify_post("com.chargeguard/restore");
    [self alert:@"Khôi phục" message:@"Đã gửi lệnh khôi phục. Mọi app bị đóng băng sẽ được thả và các thiết lập đã tắt sẽ bật lại."];
}

- (void)respring {
    pid_t pid;
    const char *args1[] = {"/usr/bin/sbreload", NULL};
    if (posix_spawn(&pid, args1[0], NULL, NULL, (char *const *)args1, environ) != 0) {
        const char *args2[] = {"/usr/bin/killall", "-9", "SpringBoard", NULL};
        if (posix_spawn(&pid, args2[0], NULL, NULL, (char *const *)args2, environ) != 0) {
            [self alert:@"Respring" message:@"Không tìm thấy sbreload trên máy. Hãy respring bằng cách bạn thường dùng."];
        }
    }
}

// ---------- Đặt lại mặc định / xuất / nhập cài đặt ----------
static NSArray *KnownKeys(void) {
    return @[K_ENABLED, K_LIMIT, K_HYST, K_TEMP_ON, K_TEMP_MAX, K_TEMP_EMERG, K_FULL_ONCE,
             K_SCHED_ON, K_SCHED_HOUR, K_SCHED_MIN_BEFORE, K_NOTIFY, K_LOWBAT_ON, K_LOWBAT_LEVEL, K_LOG,
             K_AUTO_ON, K_PULSE_ON, K_PULSE_TEMP, K_PULSE_ON_MIN, K_PULSE_OFF_MIN, K_PULSE_NIGHT_ON,
             K_PULSE_NIGHT_START, K_PULSE_NIGHT_END, K_STORAGE_ON, K_STORAGE_LEVEL, K_STORAGE_HOURS,
             K_BOOST_UNTIL, K_BOOST_MINUTES, K_CAL_ON, K_CAL_BEFORE, K_CABLE_ON, K_CABLE_COUNT,
             K_OUTAGE_ON, K_OUTAGE_MIN, K_ALARM_ON, K_NATIVE_OK, K_HOME_WIFI, K_HOME_LIMIT, K_AWAY_FULL,
             K_SAVE_ON, K_SAVE_DELAY, K_SAVE_CHARGING, K_PROFILE, K_S_CPU, K_S_CPU_LEVEL, K_S_FREEZE,
             K_S_BT, K_S_LOC, K_S_AIRDROP, K_S_LPM, K_EXCEPT, @"exceptText",
             K_FLOOR, K_NOTIFY_FAIL,
             K_COOL_ON, K_COOL_TEMP, K_COOL_SLOW, K_COOL_APPS, K_COOL_LPM,
             K_COOL_DIM, K_COOL_DIMLV, K_COOL_AIR, K_COOL_NOTIFY];
}

- (void)resetDefaults {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Đặt lại về mặc định"
        message:@"Mọi cài đặt của ChargeGuard sẽ bị xoá và quay về mặc định. Tiếp tục?"
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Đặt lại" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *act) {
        NSDictionary *cur = [NSDictionary dictionaryWithContentsOfFile:CG_PREFS_PATH] ?: @{};
        for (NSString *k in cur.allKeys) {
            CFPreferencesSetAppValue((__bridge CFStringRef)k, NULL, (__bridge CFStringRef)CG_DOMAIN);
        }
        CFPreferencesAppSynchronize((__bridge CFStringRef)CG_DOMAIN);
        notify_post(CG_PREFS_NOTIFY);
        [self reloadSpecifiers];
        [self alert:@"Đã đặt lại" message:@"Mọi cài đặt đã về mặc định. Daemon sẽ áp dụng trong vài giây."];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)exportSettings {
    NSDictionary *cur = [NSDictionary dictionaryWithContentsOfFile:CG_PREFS_PATH] ?: @{};
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *k in KnownKeys()) if (cur[k]) out[k] = cur[k];
    out[@"_chargeguard"] = @"settings";
    out[@"_version"] = @"0.2.1";
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingPrettyPrinted error:&err];
    if (!data) { [self alert:@"Xuất cài đặt" message:@"Không tạo được file."]; return; }
    NSString *path = @"/var/mobile/Documents/ChargeGuard-settings.json";
    if (![data writeToFile:path atomically:YES]) path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ChargeGuard-settings.json"], [data writeToFile:path atomically:YES];
    chmod([path fileSystemRepresentation], 0666);
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
    share.popoverPresentationController.sourceView = self.view;
    share.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 1, 1);
    [self presentViewController:share animated:YES completion:nil];
}

- (void)importSettings {
    // Không dùng UTType.data dạng property: header SDK của Theos không khai báo
    // (build 0.2.0 lần 2 chết đúng lỗi này) — tạo bằng identifier cho chắc.
    UTType *json = [UTType typeWithIdentifier:@"public.json"];
    UTType *anyData = [UTType typeWithIdentifier:@"public.data"];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[json ?: anyData] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    NSData *data = [NSData dataWithContentsOfURL:url];
    id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![obj isKindOfClass:[NSDictionary class]]) {
        [self alert:@"Nhập cài đặt" message:@"File không đúng định dạng ChargeGuard."];
        return;
    }
    int n = 0;
    for (NSString *k in KnownKeys()) {
        id v = obj[k];
        if (v && v != [NSNull null]) { SetPref(k, v); n++; }
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)CG_DOMAIN);
    notify_post(CG_PREFS_NOTIFY);
    [self reloadSpecifiers];
    [self alert:@"Nhập cài đặt" message:[NSString stringWithFormat:@"Đã nhập %d mục cài đặt.", n]];
}

// ---------- Log và chẩn đoán ----------
- (void)copyLog {
    NSString *log = [NSString stringWithContentsOfFile:CG_LOG_PATH encoding:NSUTF8StringEncoding error:nil];
    if (!log.length) log = [NSString stringWithContentsOfFile:CG_LOG_PATH_OLD encoding:NSUTF8StringEncoding error:nil] ?: @"(log trống)";
    if (log.length > 8000) log = [log substringFromIndex:log.length - 8000];
    struct utsname uts; uname(&uts);
    NSDictionary *s = [NSDictionary dictionaryWithContentsOfFile:CG_STATUS_PATH];
    NSString *diag = [NSString stringWithFormat:
        @"Máy: %s • iOS %@ • ChargeGuard 0.2.1\nNgắt sạc: %@\n",
        uts.machine, [UIDevice currentDevice].systemVersion,
        [s[S_SUPPORTED] intValue] == 1 ? [NSString stringWithFormat:@"hoạt động (%@)", s[S_METHOD]]
        : [s[S_SUPPORTED] intValue] == 0 ? @"KHÔNG hỗ trợ" : @"chưa kiểm tra"];
    NSString *all = [NSString stringWithFormat:@"=== chẩn đoán ===\n%@=== status ===\n%@\n=== log ===\n%@", diag, s ?: @"(không có)", log];
    [UIPasteboard generalPasteboard].string = all;
    [self alert:@"Đã sao chép log" message:@"Dán nội dung đó cho mình để chỉnh tweak."];
}

- (void)clearLog {
    [@"" writeToFile:CG_LOG_PATH atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [self alert:@"Log" message:@"Đã xoá."];
}

- (void)alert:(NSString *)title message:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
