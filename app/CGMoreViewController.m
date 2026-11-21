#import "CGMoreViewController.h"
#import "CGAppUtil.h"
#import "CGTheme.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <sys/stat.h>
#include <spawn.h>

extern char **environ;

@interface CGMoreViewController () <PHPickerViewControllerDelegate, UIDocumentPickerDelegate>
@end

@implementation CGMoreViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [CGTheme applyToTableView:self.tableView];
    [CGTheme applyAccentToWindow:self.view.window];
    [self.tableView reloadData];
}

static NSArray *CGKnownKeys(void) {
    return @[K_ENABLED, K_LIMIT, K_HYST, K_TEMP_ON, K_TEMP_MAX, K_TEMP_EMERG, K_FULL_ONCE,
             K_SCHED_ON, K_SCHED_HOUR, K_SCHED_MIN_BEFORE, K_NOTIFY, K_LOWBAT_ON, K_LOWBAT_LEVEL, K_LOG,
             K_AUTO_ON, K_PULSE_ON, K_PULSE_TEMP, K_PULSE_ON_MIN, K_PULSE_OFF_MIN, K_PULSE_NIGHT_ON,
             K_PULSE_NIGHT_START, K_PULSE_NIGHT_END, K_STORAGE_ON, K_STORAGE_LEVEL, K_STORAGE_HOURS,
             K_BOOST_UNTIL, K_BOOST_MINUTES, K_CAL_ON, K_CAL_BEFORE, K_CABLE_ON, K_CABLE_COUNT,
             K_OUTAGE_ON, K_OUTAGE_MIN, K_ALARM_ON, K_NATIVE_OK, K_HOME_WIFI, K_HOME_LIMIT, K_AWAY_FULL,
             K_SAVE_ON, K_SAVE_DELAY, K_SAVE_CHARGING, K_PROFILE, K_S_CPU, K_S_CPU_LEVEL, K_S_FREEZE,
             K_S_BT, K_S_LOC, K_S_AIRDROP, K_S_LPM, K_EXCEPT, @"exceptText",
             K_ICON_ON, K_ICON_SCALE];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)sec {
    if (sec == 0) return (NSInteger)[CGTheme modeNames].count + 2;
    if (sec == 1) return 4;
    return 3;
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)sec {
    return @[@"Nền app", @"Dữ liệu", @"Hệ thống"][sec];
}
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)sec {
    if (sec == 2) return @"ChargeGuard 0.2.0 — giới hạn sạc, sạc xung, lưu kho pin, tiết kiệm khi tắt màn hình. Mọi cài đặt ở đây đồng bộ với trang ChargeGuard trong Cài đặt.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    NSInteger names = (NSInteger)[CGTheme modeNames].count;
    if (ip.section == 0) {
        if (ip.row < names) {
            cell.textLabel.text = [CGTheme modeNames][ip.row];
            cell.accessoryType = ([CGTheme mode] == ip.row) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        } else if (ip.row == names) {
            cell.textLabel.text = @"Chọn ảnh từ thư viện…";
            cell.textLabel.textColor = [UIColor systemBlueColor];
        } else {
            cell.textLabel.text = @"Xoá ảnh nền";
            cell.textLabel.textColor = [UIColor systemRedColor];
        }
    } else if (ip.section == 1) {
        cell.textLabel.text = @[@"Xuất file cài đặt", @"Nhập file cài đặt", @"Xuất báo cáo pin tháng này", @"Chia sẻ log"][ip.row];
        cell.textLabel.textColor = [UIColor systemBlueColor];
    } else {
        cell.textLabel.text = @[@"Respring", @"Khôi phục mọi thứ", @"Đặt lại mọi cài đặt về mặc định"][ip.row];
        if (ip.row == 2) cell.textLabel.textColor = [UIColor systemRedColor];
        if (ip.row == 1) cell.textLabel.textColor = [UIColor systemOrangeColor];
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSInteger names = (NSInteger)[CGTheme modeNames].count;
    if (ip.section == 0) {
        if (ip.row < names) {
            [CGTheme setMode:ip.row];
            [CGTheme applyToTableView:self.tableView];
            [CGTheme applyAccentToWindow:self.view.window];
            [self.tableView reloadData];
        } else if (ip.row == names) {
            PHPickerConfiguration *cfg = [[PHPickerConfiguration alloc] initWithPhotoLibrary:[PHPhotoLibrary sharedPhotoLibrary]];
            cfg.filter = [PHPickerFilter imagesFilter];
            cfg.selectionLimit = 1;
            PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:cfg];
            picker.delegate = self;
            [self presentViewController:picker animated:YES completion:nil];
        } else {
            [CGTheme removeBackgroundImage];
            if ([CGTheme mode] == 7) [CGTheme setMode:0];
            [CGTheme applyToTableView:self.tableView];
            [self.tableView reloadData];
        }
        return;
    }
    if (ip.section == 1) {
        if (ip.row == 0) [self exportSettings];
        else if (ip.row == 1) [self importSettings];
        else if (ip.row == 2) [self exportReport];
        else [self shareLog];
        return;
    }
    // Hệ thống
    if (ip.row == 0) [self respring];
    else if (ip.row == 1) {
        [@"1" writeToFile:CG_RESTORE_FLAG atomically:YES encoding:NSUTF8StringEncoding error:nil];
        chmod([CG_RESTORE_FLAG fileSystemRepresentation], 0666);
        notify_post("com.chargeguard/restore");
        CGShowAlert(self, @"Khôi phục", @"Đã gửi lệnh khôi phục.");
    } else [self resetDefaults];
}

#pragma mark - Ảnh nền

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *r = results.firstObject;
    if (!r) return;
    [r.itemProvider loadObjectOfClass:[UIImage class] completionHandler:^(id<NSItemProviderReading> obj, NSError *err) {
        if (![obj isKindOfClass:[UIImage class]]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([CGTheme saveBackgroundImage:(UIImage *)obj]) {
                [CGTheme setMode:7];
                [CGTheme applyToTableView:self.tableView];
                [self.tableView reloadData];
            } else {
                CGShowAlert(self, @"Ảnh nền", @"Không lưu được ảnh.");
            }
        });
    }];
}

#pragma mark - Xuất / nhập / báo cáo / log

- (void)exportSettings {
    NSDictionary *cur = CGPrefs();
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *k in CGKnownKeys()) if (cur[k]) out[k] = cur[k];
    out[@"_chargeguard"] = @"settings";
    out[@"_version"] = @"0.2.0";
    NSData *data = [NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingPrettyPrinted error:nil];
    NSString *path = @"/var/mobile/Documents/ChargeGuard-settings.json";
    if (![data writeToFile:path atomically:YES]) { CGShowAlert(self, @"Xuất cài đặt", @"Không ghi được file."); return; }
    chmod([path fileSystemRepresentation], 0666);
    CGShare(self, @[[NSURL fileURLWithPath:path]]);
}

- (void)importSettings {
    UTType *json = [UTType typeWithIdentifier:@"public.json"];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[json ?: UTType.data] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSData *data = [NSData dataWithContentsOfURL:urls.firstObject];
    id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![obj isKindOfClass:[NSDictionary class]]) { CGShowAlert(self, @"Nhập cài đặt", @"File không đúng định dạng."); return; }
    int n = 0;
    for (NSString *k in CGKnownKeys()) {
        id v = obj[k];
        if (v && v != [NSNull null]) { CGSetPref(k, v); n++; }
    }
    CGShowAlert(self, @"Nhập cài đặt", [NSString stringWithFormat:@"Đã nhập %d mục cài đặt.", n]);
}

- (void)exportReport {
    NSDictionary *s = CGStatus();
    NSDictionary *p = CGPrefs();
    NSDateFormatter *mf = [NSDateFormatter new];
    mf.dateFormat = @"MM/yyyy";
    NSMutableString *r = [NSMutableString stringWithFormat:@"BÁO CÁO PIN — %@\nChargeGuard 0.2.0\n\n", [mf stringFromDate:[NSDate date]]];
    [r appendFormat:@"Sức khoẻ pin: %@%% • Chu kỳ hiện tại: %@\n", [s[S_HEALTH] intValue] > 0 ? s[S_HEALTH] : @"?", s[S_CYCLES] ?: @"?"];
    int base = CGI(p, K_STAT_CYCLES0, 0);
    if (base > 0) [r appendFormat:@"Chu kỳ đã thêm trong tháng: %d\n", [s[S_CYCLES] intValue] - base];
    NSArray *h = [NSArray arrayWithContentsOfFile:CG_HISTORY_PATH];
    long held = 0; double maxTemp = 0; long samples = 0;
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSInteger month = [cal component:NSCalendarUnitMonth fromDate:[NSDate date]];
    if ([h isKindOfClass:[NSArray class]]) {
        for (NSArray *row in h) {
            if (![row isKindOfClass:[NSArray class]] || row.count < 4) continue;
            NSDate *d = [NSDate dateWithTimeIntervalSince1970:[row[0] doubleValue]];
            if ([cal component:NSCalendarUnitMonth fromDate:d] != month) continue;
            samples++;
            if ([row[3] intValue] & 4) held++;
            double t = [row[2] doubleValue] / 10.0;
            if (t > maxTemp) maxTemp = t;
        }
    }
    [r appendFormat:@"Thời gian giữ ở giới hạn: %.1f giờ • Nhiệt độ pin cao nhất: %.1f°C\n", held * 5.0 / 60.0, maxTemp];
    NSArray *o = [NSArray arrayWithContentsOfFile:CG_OUTAGE_PATH];
    [r appendFormat:@"Số lần mất điện đã ghi: %lu\n", (unsigned long)([o isKindOfClass:[NSArray class]] ? o.count : 0)];
    [r appendFormat:@"Mức giới hạn đang đặt: %d%% • Ngắt sạc: %@\n", CGI(p, K_LIMIT, 90),
        [s[S_SUPPORTED] intValue] == 1 ? [NSString stringWithFormat:@"hoạt động (%@)", s[S_METHOD]] : @"chưa rõ"];
    NSString *path = @"/var/mobile/Documents/ChargeGuard-report.txt";
    [r writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    chmod([path fileSystemRepresentation], 0666);
    CGShare(self, @[[NSURL fileURLWithPath:path]]);
}

- (void)shareLog {
    NSString *path = CG_LOG_PATH;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) path = CG_LOG_PATH_OLD;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) CGShare(self, @[[NSURL fileURLWithPath:path]]);
    else CGShowAlert(self, @"Log", @"Chưa có file log.");
}

#pragma mark - Hệ thống

- (void)respring {
    pid_t pid;
    const char *args1[] = {"/usr/bin/sbreload", NULL};
    if (posix_spawn(&pid, args1[0], NULL, NULL, (char *const *)args1, environ) != 0) {
        const char *args2[] = {"/usr/bin/killall", "-9", "SpringBoard", NULL};
        if (posix_spawn(&pid, args2[0], NULL, NULL, (char *const *)args2, environ) != 0) {
            CGShowAlert(self, @"Respring", @"Không tìm thấy sbreload trên máy.");
        }
    }
}

- (void)resetDefaults {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Đặt lại về mặc định"
        message:@"Mọi cài đặt của ChargeGuard sẽ bị xoá và quay về mặc định. Tiếp tục?"
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Đặt lại" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *act) {
        NSDictionary *cur = CGPrefs();
        for (NSString *k in cur.allKeys) {
            CFPreferencesSetAppValue((__bridge CFStringRef)k, NULL, (__bridge CFStringRef)CG_DOMAIN);
        }
        CFPreferencesAppSynchronize((__bridge CFStringRef)CG_DOMAIN);
        notify_post(CG_PREFS_NOTIFY);
        CGShowAlert(self, @"Đã đặt lại", @"Mọi cài đặt đã về mặc định.");
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
