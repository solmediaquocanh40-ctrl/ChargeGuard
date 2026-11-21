#import "CGChartViewController.h"
#import "CGAppUtil.h"
#import "CGTheme.h"

// Biểu đồ vẽ từ file lịch sử daemon ghi: mỗi mẫu [giờ, % pin, nhiệt x10, cờ].
@interface CGChartView : UIView
@property (nonatomic, strong) NSArray *samples;
@end

@implementation CGChartView
- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat W = rect.size.width, H = rect.size.height;
    CGFloat padL = 30, padR = 8, padT = 10, padB = 18;
    CGRect plot = CGRectMake(padL, padT, W - padL - padR, H - padT - padB);

    // lưới % pin
    [[UIColor systemGray4Color] setStroke];
    CGContextSetLineWidth(ctx, 0.5);
    for (int i = 0; i <= 4; i++) {
        CGFloat y = plot.origin.y + plot.size.height * i / 4.0;
        CGContextMoveToPoint(ctx, plot.origin.x, y);
        CGContextAddLineToPoint(ctx, CGRectGetMaxX(plot), y);
        CGContextStrokePath(ctx);
        NSString *t = [NSString stringWithFormat:@"%d", 100 - i * 25];
        [t drawAtPoint:CGPointMake(4, y - 7) withAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:9], NSForegroundColorAttributeName: [UIColor secondaryLabelColor]}];
    }
    if (self.samples.count < 2) {
        [@"Chưa đủ dữ liệu — daemon ghi một mẫu mỗi ~5 phút." drawInRect:plot withAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12], NSForegroundColorAttributeName: [UIColor secondaryLabelColor]}];
        return;
    }
    double t0 = [self.samples.firstObject[0] doubleValue];
    double t1 = [self.samples.lastObject[0] doubleValue];
    if (t1 <= t0) t1 = t0 + 1;
    // đường % pin (xanh lá)
    [[UIColor systemGreenColor] setStroke];
    CGContextSetLineWidth(ctx, 1.6);
    CGContextBeginPath(ctx);
    BOOL started = NO;
    for (NSArray *row in self.samples) {
        CGFloat x = plot.origin.x + ([row[0] doubleValue] - t0) / (t1 - t0) * plot.size.width;
        CGFloat y = plot.origin.y + (1 - [row[1] doubleValue] / 100.0) * plot.size.height;
        if (!started) { CGContextMoveToPoint(ctx, x, y); started = YES; } else CGContextAddLineToPoint(ctx, x, y);
    }
    CGContextStrokePath(ctx);
    // đường nhiệt độ (cam), thang 20-50°C
    [[UIColor systemOrangeColor] setStroke];
    CGContextSetLineWidth(ctx, 1.2);
    CGContextBeginPath(ctx);
    started = NO;
    for (NSArray *row in self.samples) {
        double temp = [row[2] doubleValue] / 10.0;
        CGFloat frac = (temp - 20) / 30.0;
        if (frac < 0) frac = 0; if (frac > 1) frac = 1;
        CGFloat x = plot.origin.x + ([row[0] doubleValue] - t0) / (t1 - t0) * plot.size.width;
        CGFloat y = plot.origin.y + (1 - frac) * plot.size.height;
        if (!started) { CGContextMoveToPoint(ctx, x, y); started = YES; } else CGContextAddLineToPoint(ctx, x, y);
    }
    CGContextStrokePath(ctx);
    // chú thích
    [@"— % pin" drawAtPoint:CGPointMake(padL, H - 15) withAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:9], NSForegroundColorAttributeName: [UIColor systemGreenColor]}];
    [@"— nhiệt độ" drawAtPoint:CGPointMake(padL + 52, H - 15) withAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:9], NSForegroundColorAttributeName: [UIColor systemOrangeColor]}];
}
@end

@interface CGChartViewController ()
@property (nonatomic, strong) CGChartView *chartView;
@property (nonatomic, strong) NSTimer *testTimer;
@property (nonatomic, assign) int testTicks;
@property (nonatomic, assign) long testAmpsSum;
@property (nonatomic, assign) int testSamples;
@property (nonatomic, assign) BOOL testing;
@end

@implementation CGChartViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [CGTheme applyToTableView:self.tableView];
    [self reloadChart];
    [self.tableView reloadData];
}

- (void)reloadChart {
    NSArray *h = [NSArray arrayWithContentsOfFile:CG_HISTORY_PATH];
    if (![h isKindOfClass:[NSArray class]]) h = @[];
    double cutoff = [[NSDate date] timeIntervalSince1970] - 24 * 3600;
    NSMutableArray *recent = [NSMutableArray array];
    for (NSArray *row in h) if ([row isKindOfClass:[NSArray class]] && row.count >= 4 && [row[0] doubleValue] >= cutoff) [recent addObject:row];
    self.chartView.samples = recent.count >= 2 ? recent : h;
    [self.chartView setNeedsDisplay];
}

- (NSArray *)tests {
    NSArray *a = CGPrefs()[@"chargerTests"];
    return [a isKindOfClass:[NSArray class]] ? a : @[];
}

#pragma mark - Đo củ/cáp sạc

- (void)startTest {
    NSDictionary *s = CGStatus();
    if (![s[S_EXTERNAL] boolValue]) {
        CGShowAlert(self, @"Đo củ/cáp sạc", @"Hãy cắm sạc trước khi đo.");
        return;
    }
    self.testing = YES;
    self.testTicks = 0; self.testAmpsSum = 0; self.testSamples = 0;
    [self.tableView reloadData];
    self.testTimer = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(testTick) userInfo:nil repeats:YES];
}
- (void)testTick {
    NSDictionary *s = CGStatus();
    self.testTicks++;
    if (![s[S_EXTERNAL] boolValue]) { [self finishTestWithAbort:@"Sạc bị rút giữa chừng — phép đo huỷ."]; return; }
    if ([s[S_CHARGING] boolValue]) {
        self.testAmpsSum += labs([s[S_AMPS] intValue]);
        self.testSamples++;
    }
    [self.tableView reloadData];
    if (self.testTicks >= 30) [self finishTestWithAbort:nil]; // 30 mẫu x 2 giây = 60 giây
}
- (void)finishTestWithAbort:(NSString *)abortMsg {
    [self.testTimer invalidate]; self.testTimer = nil;
    self.testing = NO;
    if (abortMsg) { CGShowAlert(self, @"Đo củ/cáp sạc", abortMsg); [self.tableView reloadData]; return; }
    if (self.testSamples < 5) {
        CGShowAlert(self, @"Đo củ/cáp sạc", @"Máy không ở trạng thái đang sạc trong lúc đo (có thể đang bị giữ ở giới hạn). Hãy đo khi pin dưới mức giới hạn.");
        [self.tableView reloadData];
        return;
    }
    long avg = self.testAmpsSum / self.testSamples;
    double watts = avg / 1000.0 * 3.85;
    NSString *grade = avg >= 1800 ? @"Sạc nhanh tốt" : avg >= 1000 ? @"Tốc độ trung bình" : @"Chậm — nên kiểm tra cáp/củ";
    NSMutableArray *tests = [NSMutableArray arrayWithArray:[self tests]];
    [tests insertObject:@{@"date": @([[NSDate date] timeIntervalSince1970]), @"amps": @(avg), @"grade": grade} atIndex:0];
    while (tests.count > 20) [tests removeLastObject];
    CGSetPref(@"chargerTests", tests);
    [self.tableView reloadData];
    CGShowAlert(self, @"Kết quả đo", [NSString stringWithFormat:@"Dòng vào pin trung bình: %ld mA (≈ %.1fW ở phía pin).\nĐánh giá: %@.", avg, watts, grade]);
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)sec {
    if (sec == 0) return 1;
    return 1 + (NSInteger)[self tests].count;
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)sec {
    return sec == 0 ? @"Lịch sử sạc 24 giờ gần nhất" : @"Kiểm tra củ/cáp sạc";
}
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)sec {
    if (sec == 1) return @"Đo dòng sạc thật vào pin trong 60 giây và chấm điểm. Số watt là ước tính phía pin, không phải công suất ghi trên củ sạc.";
    return nil;
}
- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    return ip.section == 0 ? 220 : 44;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 0) {
        UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"chart"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"chart"];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            self.chartView = [[CGChartView alloc] initWithFrame:CGRectMake(8, 4, tv.bounds.size.width - 48, 212)];
            self.chartView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            self.chartView.backgroundColor = [UIColor clearColor];
            [cell.contentView addSubview:self.chartView];
            [self reloadChart];
        }
        return cell;
    }
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"c"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (ip.row == 0) {
        cell.textLabel.text = self.testing ? [NSString stringWithFormat:@"Đang đo… %d/60 giây", self.testTicks * 2] : @"Đo củ/cáp sạc (60 giây)";
        cell.textLabel.textColor = self.testing ? [UIColor secondaryLabelColor] : [UIColor systemBlueColor];
        cell.detailTextLabel.text = nil;
        cell.selectionStyle = self.testing ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
    } else {
        NSDictionary *t = [self tests][ip.row - 1];
        NSDateFormatter *df = [NSDateFormatter new];
        df.dateFormat = @"dd/MM HH:mm";
        cell.textLabel.text = [df stringFromDate:[NSDate dateWithTimeIntervalSince1970:[t[@"date"] doubleValue]]];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ mA • %@", t[@"amps"], t[@"grade"]];
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 1 && ip.row == 0 && !self.testing) [self startTest];
}

@end
