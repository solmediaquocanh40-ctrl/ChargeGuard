#import "CGHomeViewController.h"
#import "CGAppUtil.h"
#import "CGTheme.h"
#include <sys/stat.h>

@interface CGHomeViewController ()
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UISlider *limitSlider;
@property (nonatomic, strong) UILabel *limitValueLabel;
@end

@implementation CGHomeViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)];
    [self updateMonthlyBase];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [CGTheme applyToTableView:self.tableView];
    [self refresh];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.timer invalidate];
    self.timer = nil;
}

- (void)refresh { [self.tableView reloadData]; }

// Mốc chu kỳ đầu tháng để tính tốc độ chai pin và báo cáo
- (void)updateMonthlyBase {
    NSDictionary *s = CGStatus();
    int cycles = [s[S_CYCLES] intValue];
    if (cycles <= 0) return;
    NSDictionary *p = CGPrefs();
    NSInteger month = [[NSCalendar currentCalendar] component:NSCalendarUnitMonth fromDate:[NSDate date]];
    if (CGI(p, K_STAT_MONTH, 0) != (int)month) {
        CGSetPref(K_STAT_MONTH, @(month));
        CGSetPref(K_STAT_CYCLES0, @(cycles));
    }
}

- (NSArray *)outages {
    NSArray *a = [NSArray arrayWithContentsOfFile:CG_OUTAGE_PATH];
    return [a isKindOfClass:[NSArray class]] ? a : @[];
}

- (double)heldHours {
    NSArray *h = [NSArray arrayWithContentsOfFile:CG_HISTORY_PATH];
    if (![h isKindOfClass:[NSArray class]]) return 0;
    long n = 0;
    for (NSArray *row in h) if ([row isKindOfClass:[NSArray class]] && row.count >= 4 && ([row[3] intValue] & 4)) n++;
    return n * 5.0 / 60.0; // mỗi mẫu cách nhau ~5 phút
}

- (NSString *)forecastText {
    NSDictionary *s = CGStatus();
    int health = [s[S_HEALTH] intValue];
    int cycles = [s[S_CYCLES] intValue];
    if (health <= 0) return @"Chưa đọc được sức khoẻ pin";
    if (health <= 80) return @"Pin đã ở mốc 80% — nên cân nhắc thay pin";
    NSDictionary *p = CGPrefs();
    int base = CGI(p, K_STAT_CYCLES0, 0);
    int used = cycles - base;
    if (base <= 0 || used < 1) return @"Mở app thêm vài ngày để có số liệu dự báo";
    // thô: ~25 chu kỳ ≈ 1% sức khoẻ; used = chu kỳ đã thêm trong tháng này
    double months = (health - 80) * 25.0 / used;
    if (months > 120) return @"Pin còn rất khoẻ — trên 10 năm nữa mới tới mốc 80% (ước tính thô)";
    return [NSString stringWithFormat:@"Ước tính thô: còn khoảng %.0f tháng nữa pin tới mốc 80%% (tháng này +%d chu kỳ)", months, used];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)sec {
    if (sec == 0) return 8;
    if (sec == 1) return 5;
    NSArray *o = [self outages];
    return o.count ? (NSInteger)o.count : 1;
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)sec {
    return @[@"Trạng thái pin", @"Điều khiển nhanh", @"Sổ mất điện"][sec];
}
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)sec {
    if (sec == 1) return @"Mọi thay đổi ở đây áp dụng ngay cho daemon và đồng bộ với trang ChargeGuard trong Cài đặt.";
    if (sec == 2) return @"Mất điện được ghi khi sạc bị ngắt trong lúc máy đang khoá. Bật tính năng này trong Cài đặt > ChargeGuard.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"c"];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSDictionary *s = CGStatus();
    NSDictionary *p = CGPrefs();

    if (ip.section == 0) {
        switch (ip.row) {
            case 0:
                cell.textLabel.text = @"Pin hiện tại";
                cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
                cell.detailTextLabel.text = s.count ? [NSString stringWithFormat:@"%@%%", s[S_PERCENT]] : @"—";
                cell.detailTextLabel.font = [UIFont boldSystemFontOfSize:20];
                break;
            case 1:
                cell.textLabel.text = @"Trạng thái";
                cell.detailTextLabel.text = CGStateText(s);
                break;
            case 2:
                cell.textLabel.text = @"Nhiệt độ / dòng sạc";
                cell.detailTextLabel.text = s.count ? [NSString stringWithFormat:@"%.1f°C • %@ mA", [s[S_TEMP] doubleValue], s[S_AMPS]] : @"—";
                break;
            case 3:
                cell.textLabel.text = @"Chu kỳ / sức khoẻ pin";
                cell.detailTextLabel.text = s.count ? [NSString stringWithFormat:@"%@ chu kỳ • %@%%", s[S_CYCLES], [s[S_HEALTH] intValue] > 0 ? s[S_HEALTH] : @"?"] : @"—";
                break;
            case 4: {
                cell.textLabel.text = @"Ngắt sạc";
                int sup = [s[S_SUPPORTED] intValue];
                cell.detailTextLabel.text = !s.count ? @"—" : sup == 1 ? [NSString stringWithFormat:@"Hoạt động (%@)", s[S_METHOD]] : sup == 0 ? @"Không hỗ trợ trên máy này" : @"Chưa kiểm tra";
                break;
            }
            case 5:
                cell.textLabel.text = @"Dự báo tuổi thọ pin";
                cell.detailTextLabel.text = [self forecastText];
                cell.detailTextLabel.numberOfLines = 2;
                break;
            case 6:
                cell.textLabel.text = @"Tổng giờ đã giữ ở giới hạn";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1f giờ", [self heldHours]];
                break;
            case 7:
                cell.textLabel.text = @"Làm mát khi sạc";
                cell.detailTextLabel.text = !CGB(p, K_COOL_ON, NO) ? @"Đang tắt" : [s[S_COOL] boolValue] ? @"Đang làm mát" : @"Đang bật, chờ nóng";
                break;
        }
        return cell;
    }

    if (ip.section == 1) {
        switch (ip.row) {
            case 0: {
                cell.textLabel.text = @"Bật giới hạn sạc";
                if (!self.enabledSwitch) {
                    self.enabledSwitch = [UISwitch new];
                    [self.enabledSwitch addTarget:self action:@selector(enabledChanged) forControlEvents:UIControlEventValueChanged];
                }
                self.enabledSwitch.on = CGB(p, K_ENABLED, NO);
                cell.accessoryView = self.enabledSwitch;
                break;
            }
            case 1: {
                cell.textLabel.text = @"Mức ngưng sạc";
                if (!self.limitSlider) {
                    self.limitSlider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 150, 30)];
                    self.limitSlider.minimumValue = 10;
                    self.limitSlider.maximumValue = 100;
                    [self.limitSlider addTarget:self action:@selector(limitSliding) forControlEvents:UIControlEventValueChanged];
                    [self.limitSlider addTarget:self action:@selector(limitCommitted) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
                }
                self.limitSlider.value = CGI(p, K_LIMIT, 90);
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%d%%", (int)self.limitSlider.value];
                cell.accessoryView = self.limitSlider;
                break;
            }
            case 2:
                cell.textLabel.text = @"Sạc đầy 100% một lần";
                cell.textLabel.textColor = [UIColor systemBlueColor];
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                break;
            case 3:
                cell.textLabel.text = [NSString stringWithFormat:@"Sạc cấp tốc (%d phút)", CGI(p, K_BOOST_MINUTES, 15)];
                cell.textLabel.textColor = [UIColor systemBlueColor];
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                break;
            case 4:
                cell.textLabel.text = @"Khôi phục mọi thứ";
                cell.textLabel.textColor = [UIColor systemOrangeColor];
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                break;
        }
        return cell;
    }

    // Sổ mất điện
    NSArray *o = [self outages];
    if (!o.count) {
        cell.textLabel.text = @"Chưa ghi nhận lần mất điện nào";
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
    } else {
        NSDictionary *rec = o[o.count - 1 - ip.row];
        NSDate *d = [NSDate dateWithTimeIntervalSince1970:[rec[@"start"] doubleValue]];
        NSDateFormatter *df = [NSDateFormatter new];
        df.dateFormat = @"dd/MM HH:mm";
        cell.textLabel.text = [df stringFromDate:d];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"mất khoảng %@ phút", rec[@"minutes"]];
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section != 1) return;
    NSDictionary *p = CGPrefs();
    if (ip.row == 2) {
        CGSetPref(K_FULL_ONCE, @([[NSDate date] timeIntervalSince1970]));
        CGShowAlert(self, @"Sạc đầy một lần", @"Đã bật. Máy sẽ sạc tới 100% một lần rồi quay lại mức giới hạn.");
    } else if (ip.row == 3) {
        int mins = CGI(p, K_BOOST_MINUTES, 15);
        CGSetPref(K_BOOST_UNTIL, @([[NSDate date] timeIntervalSince1970] + mins * 60));
        CGShowAlert(self, @"Sạc cấp tốc", [NSString stringWithFormat:@"Đã bật sạc cấp tốc trong %d phút.", mins]);
    } else if (ip.row == 4) {
        [@"1" writeToFile:CG_RESTORE_FLAG atomically:YES encoding:NSUTF8StringEncoding error:nil];
        chmod([CG_RESTORE_FLAG fileSystemRepresentation], 0666);
        notify_post("com.chargeguard/restore");
        CGShowAlert(self, @"Khôi phục", @"Đã gửi lệnh: thả mọi app bị đóng băng và bật lại các kết nối đã tắt.");
    }
}

- (void)enabledChanged { CGSetPref(K_ENABLED, @(self.enabledSwitch.on)); }
- (void)limitSliding {
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:1]];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%d%%", (int)self.limitSlider.value];
}
- (void)limitCommitted { CGSetPref(K_LIMIT, @((int)self.limitSlider.value)); }

@end
