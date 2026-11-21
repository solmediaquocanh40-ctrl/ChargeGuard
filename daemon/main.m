// chargeguardd 0.2.3 - daemon chạy bằng quyền root, đọc pin và ngắt/mở sạc theo giới hạn.
// Mặc định luôn là SẠC BÌNH THƯỜNG. Chỉ ngắt sạc khi đã kiểm chứng được một cách ngắt hoạt động.
// 0.2.0: nhớ phương thức ngắt đã thắng, sạc xung, chế độ lưu kho, vệ sĩ nhiệt khẩn cấp,
// cảnh báo cáp chập chờn, phát hiện pin bất thường, lịch sử sạc, log bền ở Documents.
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdarg.h>
#import "../Shared/CGShared.h"

// ---------------- Log (0.2.0: ghi ở Documents, không mất khi gỡ tweak) ----------------
static BOOL gLogOn = YES;
static void CGLog(NSString *fmt, ...) {
    if (!gLogOn) return;
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSDateFormatter *df = [NSDateFormatter new];
    df.dateFormat = @"MM-dd HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [df stringFromDate:[NSDate date]], s];
    NSString *path = CG_LOG_PATH;
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        chmod([path fileSystemRepresentation], 0666);
        fh = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    if (!fh) { // Documents không ghi được thì quay về đường cũ
        path = CG_LOG_PATH_OLD;
        fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) {
            [@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
            chmod([path fileSystemRepresentation], 0666);
            fh = [NSFileHandle fileHandleForWritingAtPath:path];
        }
    }
    if (fh) {
        unsigned long long sz = [fh seekToEndOfFile];
        if (sz > 400000) { [fh truncateFileAtOffset:0]; }
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}

// ---------------- Đọc pin ----------------
typedef struct {
    int percent; BOOL charging; BOOL external; double tempC; int amps; int cycles; int health;
    BOOL ok;
} BatInfo;

static int64_t CGInt(NSDictionary *d, NSString *k, int64_t def) {
    id v = d[k];
    return [v isKindOfClass:[NSNumber class]] ? [v longLongValue] : def;
}

static BatInfo ReadBattery(void) {
    BatInfo b; memset(&b, 0, sizeof(b)); b.percent = -1;
    io_service_t svc = IOServiceGetMatchingService(0, IOServiceMatching("AppleSmartBattery"));
    if (!svc) return b;
    CFMutableDictionaryRef props = NULL;
    if (IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS && props) {
        NSDictionary *d = (__bridge_transfer NSDictionary *)props;
        b.percent  = (int)CGInt(d, @"CurrentCapacity", -1);
        if (b.percent < 0) b.percent = (int)CGInt(d, @"StateOfCharge", -1); // vài bản iOS dùng khóa này
        b.charging = CGInt(d, @"IsCharging", 0) != 0;
        b.external = CGInt(d, @"ExternalConnected", 0) != 0;
        b.tempC    = CGInt(d, @"Temperature", 0) / 100.0;
        b.amps     = (int)(int16_t)(CGInt(d, @"InstantAmperage", 0) & 0xFFFF);
        b.cycles   = (int)CGInt(d, @"CycleCount", 0);
        int64_t design = CGInt(d, @"DesignCapacity", 0);
        int64_t nominal = CGInt(d, @"NominalChargeCapacity", 0);
        if (nominal <= 0) nominal = CGInt(d, @"AppleRawMaxCapacity", 0);
        b.health = (design > 0 && nominal > 0) ? (int)(nominal * 100 / design) : 0;
        if (b.health <= 0) { // dự phòng: vài bản iOS báo thẳng % sức khỏe
            int64_t mc = CGInt(d, @"MaxCapacity", 0);
            if (mc > 0 && mc <= 100) b.health = (int)mc;
        }
        b.ok = (b.percent >= 0 && b.percent <= 100);
    }
    IOObjectRelease(svc);
    return b;
}

// ---------------- Ngắt sạc: nhiều cách, tự kiểm chứng ----------------
typedef struct { uint32_t key; struct { char major, minor, build, reserved[1]; uint16_t release; } vers;
    struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } pLimit;
    struct { uint32_t dataSize, dataType; char dataAttributes; } keyInfo;
    char result, status, data8; uint32_t data32; unsigned char bytes[32]; } SMCKeyData;

static io_connect_t gSMC = 0;
static uint32_t FourCC(const char *s) { return ((uint32_t)s[0] << 24) | ((uint32_t)s[1] << 16) | ((uint32_t)s[2] << 8) | (uint32_t)s[3]; }

static BOOL SMCOpen(void) {
    if (gSMC) return YES;
    io_service_t s = IOServiceGetMatchingService(0, IOServiceMatching("AppleSMC"));
    if (!s) { CGLog(@"smc: không có service AppleSMC"); return NO; }
    kern_return_t kr = IOServiceOpen(s, mach_task_self(), 0, &gSMC);
    IOObjectRelease(s);
    if (kr != KERN_SUCCESS) { CGLog(@"smc: IOServiceOpen lỗi 0x%x", kr); gSMC = 0; return NO; }
    return YES;
}

static BOOL SMCWriteU8(const char *key, uint8_t val) {
    if (!SMCOpen()) return NO;
    SMCKeyData in, out; size_t outSz = sizeof(out);
    memset(&in, 0, sizeof(in)); memset(&out, 0, sizeof(out));
    in.key = FourCC(key); in.data8 = 9; // lấy thông tin khóa
    if (IOConnectCallStructMethod(gSMC, 2, &in, sizeof(in), &out, &outSz) != KERN_SUCCESS || out.result != 0) return NO;
    uint32_t size = out.keyInfo.dataSize;
    if (size == 0 || size > 32) return NO;
    memset(&in, 0, sizeof(in));
    in.key = FourCC(key); in.data8 = 6; in.keyInfo.dataSize = size; in.bytes[0] = val;
    memset(&out, 0, sizeof(out)); outSz = sizeof(out);
    kern_return_t kr = IOConnectCallStructMethod(gSMC, 2, &in, sizeof(in), &out, &outSz);
    return kr == KERN_SUCCESS && out.result == 0;
}

// Các phương pháp. Mỗi cái nhận inhibit YES/NO, trả về YES nếu lệnh được chấp nhận.
static const char *kSMCKeys[] = { "CH0I", "CH0C", "CH0B", "CHTE" };
#define NMETHODS 6   // 4 khóa SMC + 2 thuộc tính IORegistry

static NSString *MethodName(int m) {
    if (m < 4) return [NSString stringWithFormat:@"SMC:%s", kSMCKeys[m]];
    return m == 4 ? @"IOReg:AppleSmartBattery.ChargeInhibit" : @"IOReg:AppleARMPMUCharger.ChargeInhibit";
}

static BOOL ApplyMethod(int m, BOOL inhibit) {
    if (m < 4) return SMCWriteU8(kSMCKeys[m], inhibit ? 1 : 0);
    const char *cls = (m == 4) ? "AppleSmartBattery" : "AppleARMPMUCharger";
    io_service_t svc = IOServiceGetMatchingService(0, IOServiceMatching(cls));
    if (!svc) return NO;
    kern_return_t kr = IORegistryEntrySetCFProperty(svc, CFSTR("ChargeInhibit"), inhibit ? kCFBooleanTrue : kCFBooleanFalse);
    IOObjectRelease(svc);
    return kr == KERN_SUCCESS;
}

static void ReleaseAllMethods(void) { for (int m = 0; m < NMETHODS; m++) ApplyMethod(m, NO); }

// ---------------- Trạng thái daemon bền (0.2.0) ----------------
// File riêng của daemon: phương thức đã thắng, các mốc đã tiêu, sổ cáp chập chờn,
// thời điểm bắt đầu cắm sạc. Không đụng vào file prefs của người dùng.
static NSMutableDictionary *gState = nil;

static void LoadState(void) {
    gState = [NSMutableDictionary dictionaryWithContentsOfFile:CG_DAEMON_STATE];
    if (!gState) gState = [NSMutableDictionary dictionary];
}
static void SaveState(void) {
    [gState writeToFile:CG_DAEMON_STATE atomically:YES];
    chmod([CG_DAEMON_STATE fileSystemRepresentation], 0644);
}

// ---------------- Trạng thái chạy ----------------
static int gWorking = -1;          // phương pháp đã kiểm chứng; -1 chưa biết
static BOOL gAllFailed = NO;       // đã thử hết mà không cái nào ngắt được
static BOOL gHolding = NO;
static NSString *gMsg = @"Đang chạy.";
static double gHeldAt = 0;
static BOOL gPulseRest = NO;       // đang ở nhịp nghỉ của sạc xung
static BOOL gCoolActive = NO;      // 0.2.1: đang làm mát khi sạc (pin nóng >= ngưỡng)
static BOOL gCoolHold = NO;        // 0.2.1: nhịp giữ hiện tại là do làm mát
static BOOL gStorageMode = NO;
static BOOL gBoost = NO;
static BOOL gEmerg = NO;
static BOOL gNative = NO;
static int gCableWarn = 0;
static NSString *gAnomaly = @"";
static double gAnomalyAt = 0;

static void WriteStatus(BatInfo b) {
    NSMutableDictionary *s = [NSMutableDictionary dictionary];
    s[S_PERCENT] = @(b.percent); s[S_CHARGING] = @(b.charging); s[S_EXTERNAL] = @(b.external);
    s[S_TEMP] = @(b.tempC); s[S_AMPS] = @(b.amps); s[S_CYCLES] = @(b.cycles); s[S_HEALTH] = @(b.health);
    s[S_HOLDING] = @(gHolding);
    s[S_SUPPORTED] = @(gWorking >= 0 ? 1 : (gAllFailed ? 0 : -1));
    s[S_METHOD] = gWorking >= 0 ? MethodName(gWorking) : @"";
    s[S_MESSAGE] = gMsg;
    s[S_TIME] = @([[NSDate date] timeIntervalSince1970]);
    s[@"heldAt"] = @(gHeldAt);
    s[S_PULSE] = @(gPulseRest);
    s[S_COOL] = @(gCoolActive);
    s[S_STORAGE] = @(gStorageMode);
    s[S_BOOST] = @(gBoost);
    s[S_EMERG] = @(gEmerg);
    s[S_NATIVE] = @(gNative);
    s[S_CABLEWARN] = @(gCableWarn);
    s[S_ANOMALY] = gAnomaly ?: @"";
    [s writeToFile:CG_STATUS_PATH atomically:YES];
    chmod([CG_STATUS_PATH fileSystemRepresentation], 0644);
}

// Thử ngắt sạc, kiểm chứng bằng việc IsCharging/dòng sạc giảm. Chạy khi cần giữ.
static BOOL TryInhibit(void) {
    if (gWorking >= 0) { ApplyMethod(gWorking, YES); return YES; }
    if (gAllFailed) return NO;
    for (int m = 0; m < NMETHODS; m++) {
        if (!ApplyMethod(m, YES)) { CGLog(@"thử %@: lệnh bị từ chối", MethodName(m)); continue; }
        sleep(6);
        BatInfo b = ReadBattery();
        BOOL stopped = b.ok && b.external && (!b.charging || b.amps <= 50);
        CGLog(@"thử %@: sau 6s charging=%d amps=%d => %@", MethodName(m), b.charging, b.amps, stopped ? @"CHẠY" : @"không có tác dụng");
        if (stopped) {
            gWorking = m;
            gState[@"working"] = @(m);
            SaveState();
            return YES;
        }
        ApplyMethod(m, NO);
    }
    gAllFailed = YES;
    gState[@"allFailed"] = @YES;
    SaveState();
    gMsg = @"Máy này không cho phần mềm ngắt sạc (đã thử mọi cách). Giới hạn sạc không hoạt động; máy vẫn sạc bình thường.";
    CGLog(@"%@", gMsg);
    return NO;
}

static void Release(void) {
    if (gWorking >= 0) ApplyMethod(gWorking, NO); else ReleaseAllMethods();
}

// ---------------- Lịch và sạc đầy một lần ----------------
static BOOL InScheduleWindow(NSDictionary *p) {
    if (![p[K_SCHED_ON] boolValue]) return NO;
    int hour = p[K_SCHED_HOUR] ? [p[K_SCHED_HOUR] intValue] : 6;
    int before = p[K_SCHED_MIN_BEFORE] ? [p[K_SCHED_MIN_BEFORE] intValue] : 90;
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [cal components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:[NSDate date]];
    int nowMin = (int)(c.hour * 60 + c.minute);
    int target = hour * 60;
    int start = target - before;
    if (start >= 0) return nowMin >= start && nowMin < target + 30;
    // cửa sổ vượt nửa đêm
    return nowMin >= start + 1440 || nowMin < target + 30;
}

static BOOL InNightWindow(NSDictionary *p) {
    int startH = p[K_PULSE_NIGHT_START] ? [p[K_PULSE_NIGHT_START] intValue] : 22;
    int endH = p[K_PULSE_NIGHT_END] ? [p[K_PULSE_NIGHT_END] intValue] : 6;
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSInteger h = [cal component:NSCalendarUnitHour fromDate:[NSDate date]];
    if (startH == endH) return NO;
    if (startH < endH) return h >= startH && h < endH;
    return h >= startH || h < endH;
}

// Dò giới hạn sạc gốc của Apple (iOS 17+ trên máy đời mới): chỉ dò có bằng chứng
// là file cài đặt của hệ thống sạc thông minh tồn tại và có khóa bật. Kết quả ghi
// vào trạng thái để người dùng và log cùng thấy; có công tắc cho phép dùng tiếp.
static BOOL ProbeNativeLimit(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.apple.smartcharging.plist"];
    if (![d isKindOfClass:[NSDictionary class]]) return NO;
    for (NSString *k in @[@"EnableSmartCharging", @"SmartChargingEnabled", @"enabled", @"Enabled"]) {
        id v = d[k];
        if ([v isKindOfClass:[NSNumber class]] && [v boolValue]) {
            CGLog(@"dò thấy giới hạn sạc gốc của Apple đang bật (khóa %@)", k);
            return YES;
        }
    }
    return NO;
}

// ---------------- Lịch sử sạc (cho biểu đồ trong app) ----------------
static int gTickCount = 0;
static void AppendHistory(BatInfo b) {
    // mỗi 20 tick (~5 phút) ghi một mẫu: [mốc giờ, % pin, nhiệt x10, cờ trạng thái]
    NSMutableArray *h = [NSMutableArray arrayWithContentsOfFile:CG_HISTORY_PATH];
    if (!h) h = [NSMutableArray array];
    int flags = (b.external ? 1 : 0) | (b.charging ? 2 : 0) | (gHolding ? 4 : 0) | (gPulseRest ? 8 : 0) | (gStorageMode ? 16 : 0);
    [h addObject:@[@([[NSDate date] timeIntervalSince1970]), @(b.percent), @((int)(b.tempC * 10)), @(flags)]];
    while (h.count > 2200) [h removeObjectAtIndex:0];
    [h writeToFile:CG_HISTORY_PATH atomically:YES];
    chmod([CG_HISTORY_PATH fileSystemRepresentation], 0666);
}

// ---------------- Vòng lặp chính ----------------
static void Tick(void) {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:CG_PREFS_PATH] ?: @{};
    gLogOn = p[K_LOG] ? [p[K_LOG] boolValue] : YES;

    BatInfo b = ReadBattery();
    if (!b.ok) { gMsg = @"Không đọc được pin."; WriteStatus(b); return; }
    double now = [[NSDate date] timeIntervalSince1970];

    // --- Đọc cài đặt (mặc định an toàn như bản cũ) ---
    BOOL enabled = p[K_ENABLED] ? [p[K_ENABLED] boolValue] : NO;
    int limit = p[K_LIMIT] ? [p[K_LIMIT] intValue] : 90;
    if (limit < 10) limit = 10;
    if (limit > 100) limit = 100;
    int hyst  = p[K_HYST] ? [p[K_HYST] intValue] : 3;
    BOOL tempOn = p[K_TEMP_ON] ? [p[K_TEMP_ON] boolValue] : YES;
    int tempMax = p[K_TEMP_MAX] ? [p[K_TEMP_MAX] intValue] : 40;
    int tempEmerg = p[K_TEMP_EMERG] ? [p[K_TEMP_EMERG] intValue] : 45;

    // Chế độ tự động toàn phần: tự chọn mức theo sức khoẻ pin
    if ([p[K_AUTO_ON] boolValue] && enabled) {
        if (b.health >= 90) limit = 80;
        else if (b.health >= 80) limit = 75;
        else if (b.health > 0) limit = 70;
    }

    // --- Giới hạn gốc của Apple: nhường nếu có, trừ khi người dùng cho phép dùng tiếp ---
    gNative = ProbeNativeLimit();
    BOOL nativeYield = gNative && ![p[K_NATIVE_OK] boolValue];

    // --- Sạc đầy một lần + sạc đầy theo Lịch (hai cờ độc lập, tiêu thụ riêng) ---
    double stamp = [p[K_FULL_ONCE] doubleValue];
    double consumed = [gState[@"consumedFull"] doubleValue];
    BOOL fullOnce = stamp > consumed;
    if (fullOnce && b.percent >= 100) {
        gState[@"consumedFull"] = @(stamp); SaveState(); fullOnce = NO;
        CGLog(@"sạc đầy một lần: xong");
    }
    double calStamp = [p[K_CAL_FULL_STAMP] doubleValue];
    double calConsumed = [gState[@"consumedCal"] doubleValue];
    BOOL calFull = calStamp > calConsumed;
    if (calFull && b.percent >= 100) {
        gState[@"consumedCal"] = @(calStamp); SaveState(); calFull = NO;
        CGLog(@"sạc đầy theo Lịch: xong");
    }

    // --- Sạc cấp tốc ---
    gBoost = [p[K_BOOST_UNTIL] doubleValue] > now;

    BOOL fullIntent = fullOnce || calFull || InScheduleWindow(p) || gBoost;

    // --- Theo dõi cắm sạc liên tục (cho chế độ lưu kho) + cáp chập chờn ---
    static BOOL lastExternal = NO;
    if (b.external && !lastExternal) {
        gState[@"pluggedSince"] = @(now);
        NSMutableArray *ev = [NSMutableArray arrayWithArray:(gState[@"cableEvents"] ?: @[])];
        [ev addObject:@(now)];
        while (ev.count && [ev.firstObject doubleValue] < now - 600) [ev removeObjectAtIndex:0];
        gState[@"cableEvents"] = ev;
        SaveState();
    }
    if (!b.external && lastExternal) {
        NSMutableArray *ev = [NSMutableArray arrayWithArray:(gState[@"cableEvents"] ?: @[])];
        [ev addObject:@(now)];
        while (ev.count && [ev.firstObject doubleValue] < now - 600) [ev removeObjectAtIndex:0];
        gState[@"cableEvents"] = ev;
        SaveState();
    }
    lastExternal = b.external;
    NSArray *cableEvents = gState[@"cableEvents"] ?: @[];
    NSMutableArray *recent = [NSMutableArray array];
    for (NSNumber *t in cableEvents) if ([t doubleValue] >= now - 600) [recent addObject:t];
    gCableWarn = (int)recent.count;
    BOOL cableBad = [p[K_CABLE_ON] boolValue] && gCableWarn >= (p[K_CABLE_COUNT] ? [p[K_CABLE_COUNT] intValue] : 5) * 2;
    // (mỗi lần chập chờn = 1 lần ngắt + 1 lần nối = 2 sự kiện)

    // --- Phát hiện pin bất thường ---
    static int lastPct = -1; static double lastTemp = -1;
    if (lastPct >= 0) {
        if (!b.external && lastPct - b.percent >= 4) {
            gAnomaly = [NSString stringWithFormat:@"Pin tụt %d%% trong 15 giây khi không dùng sạc — dấu hiệu pin bất thường.", lastPct - b.percent];
            gAnomalyAt = now; CGLog(@"BẤT THƯỜNG: %@", gAnomaly);
        } else if (lastTemp > 0 && b.tempC - lastTemp >= 4.0 && !b.charging) {
            gAnomaly = [NSString stringWithFormat:@"Nhiệt độ pin nhảy %.1f°C trong 15 giây — dấu hiệu pin bất thường.", b.tempC - lastTemp];
            gAnomalyAt = now; CGLog(@"BẤT THƯỜNG: %@", gAnomaly);
        } else if (gAnomaly.length && now - gAnomalyAt > 1800) {
            gAnomaly = @"";
        }
    }
    lastPct = b.percent; lastTemp = b.tempC;

    // --- Mức hiệu lực: lưu kho > hồ sơ nơi chốn > mức thường ---
    double pluggedSince = [gState[@"pluggedSince"] doubleValue];
    gStorageMode = NO;
    int effLimit = limit;
    if ([p[K_STORAGE_ON] boolValue] && b.external && pluggedSince > 0 && (now - pluggedSince) >= (p[K_STORAGE_HOURS] ? [p[K_STORAGE_HOURS] intValue] : 12) * 3600.0 && !fullIntent) {
        gStorageMode = YES;
        effLimit = p[K_STORAGE_LEVEL] ? [p[K_STORAGE_LEVEL] intValue] : 55;
    } else if (!fullIntent) {
        double ctxStamp = [p[K_CTX_STAMP] doubleValue];
        int ctxLimit = [p[K_CTX_LIMIT] intValue];
        if (ctxLimit >= 10 && ctxLimit <= 100 && ctxStamp > 0 && now - ctxStamp < 600) effLimit = ctxLimit;
    }

    // --- Quyết định giữ sạc ---
    // 0.2.1: mức an toàn tối thiểu cho người dùng chọn (0.2.0 là hằng số 20)
    int floorLvl = p[K_FLOOR] ? [p[K_FLOOR] intValue] : 20;
    if (floorLvl < 5) floorLvl = 5;
    if (floorLvl > 30) floorLvl = 30;
    gEmerg = tempOn && b.tempC >= tempEmerg && b.percent > floorLvl;
    BOOL allow = !enabled || effLimit >= 100 || fullIntent || b.percent <= floorLvl || !b.external || nativeYield;
    BOOL tempHot = tempOn && b.tempC >= tempMax && b.percent > floorLvl && enabled && !fullIntent;

    BOOL wantHold;
    if (gEmerg) wantHold = enabled && b.external;
    else if (tempHot) wantHold = YES;
    else if (allow) wantHold = NO;
    else if (gHolding) wantHold = b.percent > (effLimit - hyst);
    else wantHold = b.percent >= effLimit;

    // --- Sạc xung: khi đang sạc lên mà nóng, hoặc trong khung giờ đêm ---
    BOOL pulseActive = NO;
    if ([p[K_PULSE_ON] boolValue] && enabled && b.external && !fullIntent && !gStorageMode && !nativeYield && !gEmerg && b.percent < effLimit && b.percent > floorLvl) {
        if ((tempOn && b.tempC >= (p[K_PULSE_TEMP] ? [p[K_PULSE_TEMP] intValue] : 38)) ||
            ([p[K_PULSE_NIGHT_ON] boolValue] && InNightWindow(p))) {
            pulseActive = YES;
        }
    }
    static double pulsePhaseStart = 0; static BOOL pulsePhaseRest = NO;
    if (pulseActive) {
        int onMin = p[K_PULSE_ON_MIN] ? [p[K_PULSE_ON_MIN] intValue] : 5;
        int offMin = p[K_PULSE_OFF_MIN] ? [p[K_PULSE_OFF_MIN] intValue] : 5;
        if (pulsePhaseStart == 0) { pulsePhaseStart = now; pulsePhaseRest = NO; }
        double elapsed = (now - pulsePhaseStart) / 60.0;
        if (!pulsePhaseRest && elapsed >= onMin) { pulsePhaseRest = YES; pulsePhaseStart = now; CGLog(@"xung: vào nhịp nghỉ"); }
        else if (pulsePhaseRest && elapsed >= offMin) { pulsePhaseRest = NO; pulsePhaseStart = now; CGLog(@"xung: sạc tiếp"); }
        wantHold = pulsePhaseRest;
        gPulseRest = pulsePhaseRest;
    } else {
        pulsePhaseStart = 0; pulsePhaseRest = NO; gPulseRest = NO;
    }

    // --- 0.2.1: Làm mát khi sạc (phần daemon: sạc chậm theo nhịp) ---
    // Pin nóng tới ngưỡng thì chuyển sang nhịp giữ 3 nhịp / nhả 1 nhịp: dòng sạc
    // trung bình giảm mạnh nên máy nguội dần mà vẫn lên pin. Phần giảm tải app,
    // nguồn điện thấp, độ sáng... do phía SpringBoard lo theo cờ S_COOL.
    int coolTemp = p[K_COOL_TEMP] ? [p[K_COOL_TEMP] intValue] : 40;
    BOOL coolNow = [p[K_COOL_ON] boolValue] && enabled && b.external && b.tempC >= coolTemp && b.percent > floorLvl;
    if (coolNow && !gCoolActive) CGLog(@"LÀM MÁT: bắt đầu (pin %.1f°C, ngưỡng %d°C)", b.tempC, coolTemp);
    if (!coolNow && gCoolActive) CGLog(@"LÀM MÁT: kết thúc (pin %.1f°C)", b.tempC);
    gCoolActive = coolNow;
    gCoolHold = NO;
    static int coolPhase = 0;
    if (gCoolActive && [p[K_COOL_SLOW] boolValue] && !fullIntent && !gEmerg && b.percent < 100) {
        coolPhase = (coolPhase + 1) % 4;
        wantHold = (coolPhase != 3);
        gCoolHold = wantHold;
        gPulseRest = NO; // làm mát ưu tiên hơn sạc xung
    } else {
        coolPhase = 0;
    }

    if (wantHold && !gHolding) {
        if (TryInhibit()) {
            gHolding = YES; gHeldAt = now;
            gMsg = gEmerg ? [NSString stringWithFormat:@"VỆ SĨ NHIỆT: đã ngắt sạc ở %.1f°C.", b.tempC]
                 : gCoolHold ? @"Đang làm mát: sạc chậm theo nhịp cho pin nguội."
                 : gPulseRest ? @"Sạc xung: đang nghỉ cho mát pin."
                 : tempHot ? [NSString stringWithFormat:@"Tạm ngừng sạc vì nóng (%.1f°C).", b.tempC]
                 : gStorageMode ? [NSString stringWithFormat:@"Đang giữ ở chế độ lưu kho %d%%.", b.percent]
                 : [NSString stringWithFormat:@"Đang giữ ở %d%%.", b.percent];
            CGLog(@"GIỮ: %d%% %.1fC (%@)", b.percent, b.tempC, MethodName(gWorking));
        }
    } else if (wantHold && gHolding) {
        TryInhibit(); // lệnh nhắc lại phòng khi hệ thống đặt lại
        // kiểm chứng lại phương thức đã nhớ: nếu máy lại sạc vượt mức thì dò lại từ đầu
        if (b.charging && b.amps > 200 && b.percent > effLimit + 2 && !gPulseRest && !gCoolHold) {
            CGLog(@"phương thức %@ không còn tác dụng, dò lại", MethodName(gWorking));
            gWorking = -1; gAllFailed = NO;
            gState[@"working"] = @(-1); gState[@"allFailed"] = @NO; SaveState();
            Release(); gHolding = NO;
        }
    } else if (!wantHold && gHolding) {
        Release(); gHolding = NO; gMsg = @"Đang sạc bình thường.";
        CGLog(@"MỞ SẠC LẠI: %d%%", b.percent);
    } else if (!gHolding && !gAllFailed) {
        if (nativeYield) gMsg = @"Máy đang dùng giới hạn sạc gốc của Apple, ChargeGuard tạm nhường. Bật 'Vẫn dùng ChargeGuard' nếu muốn.";
        else if (cableBad) gMsg = [NSString stringWithFormat:@"Cáp/củ sạc chập chờn: %d lần ngắt-nối trong 10 phút. Nên thay cáp.", gCableWarn / 2];
        else if (gBoost) gMsg = @"Đang sạc cấp tốc, bỏ qua giới hạn.";
        else if (gStorageMode) gMsg = @"Đang ở chế độ lưu kho.";
        else gMsg = enabled ? @"Đang theo dõi." : @"Giới hạn sạc đang tắt, sạc bình thường.";
    }
    if (gEmerg && enabled) gMsg = [NSString stringWithFormat:@"VỆ SĨ NHIỆT: pin %.1f°C, đã ngắt sạc để bảo vệ pin.", b.tempC];

    WriteStatus(b);
    if (++gTickCount % 20 == 0) AppendHistory(b);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        umask(022);
        LoadState();
        if (gState[@"working"]) gWorking = [gState[@"working"] intValue];
        gAllFailed = [gState[@"allFailed"] boolValue];
        CGLog(@"chargeguardd 0.2.3 khởi động (phương thức đã nhớ: %@)", gWorking >= 0 ? MethodName(gWorking) : @"chưa có");
        ReleaseAllMethods();              // luôn bắt đầu ở trạng thái sạc bình thường
        // Dọn khi bị tắt
        signal(SIGTERM, SIG_IGN);
        dispatch_source_t term = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(term, ^{ ReleaseAllMethods(); CGLog(@"nhận SIGTERM, mở sạc và thoát"); exit(0); });
        dispatch_resume(term);

        dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 0), 15 * NSEC_PER_SEC, 2 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(t, ^{ @autoreleasepool { Tick(); } });
        dispatch_resume(t);
        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}
