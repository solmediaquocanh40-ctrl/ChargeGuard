// ChargeGuard 0.2.1 - tweak trong SpringBoard: tiết kiệm pin khi tắt màn hình,
// thông báo của daemon, hồ sơ sạc theo Wi-Fi, sạc đầy theo Lịch, ghi nhận mất điện,
// báo động rút sạc, và các biện pháp làm mát phía hệ thống khi sạc nóng.
// (Chỉnh kích thước icon đã gỡ khỏi ChargeGuard từ 0.2.1 để làm tweak riêng.)
// Wi-Fi và push notification KHÔNG bị đụng tới. Chữ trong app KHÔNG bị đụng tới:
// phần tiết kiệm chỉ giảm CPU/đóng băng tiến trình nền, không chạm vào hiển thị.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <EventKit/EventKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <notify.h>
#include <signal.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <unistd.h>

// SDK iOS của Theos KHÔNG có sẵn <libproc.h> (build 0.2.0 đầu chết đúng lỗi này)
// nên tự khai báo đúng phần libproc cần dùng. Struct đặt tên riêng CGProcTaskInfo
// để tránh mọi nguy cơ trùng khai báo; nhân hệ thống chỉ quan tâm kích thước và
// vị trí các trường đầu (virtual/resident/total_user/total_system), khớp bản gốc.
#ifndef PROC_ALL_PIDS
#define PROC_ALL_PIDS 1
#endif
#ifndef PROC_PIDTASKINFO
#define PROC_PIDTASKINFO 4
#endif
struct CGProcTaskInfo {
    uint64_t pti_virtual_size;
    uint64_t pti_resident_size;
    uint64_t pti_total_user;
    uint64_t pti_total_system;
    uint64_t pti_total_idle;
    uint64_t pti_faults;
    uint32_t pti_pageins;
    uint32_t pti_cow_faults;
    uint32_t pti_messages_sent;
    uint32_t pti_messages_received;
    uint32_t pti_syscalls_mach;
    uint32_t pti_syscalls_unix;
    uint32_t pti_csw;
    uint32_t pti_threadnum;
    uint32_t pti_numrunning;
    int32_t  pti_priority;
};
int proc_listpids(uint32_t type, uint32_t typeinfo, void *buffer, int buffersize);
int proc_pidinfo(int pid, int flavor, uint64_t arg, void *buffer, int buffersize);
#import "../Shared/CGShared.h"

#ifndef PRIO_DARWIN_PROCESS
#define PRIO_DARWIN_PROCESS 4
#endif
#ifndef PRIO_DARWIN_BG
#define PRIO_DARWIN_BG 0x1000
#endif

#define FROZEN_LIST @"/var/tmp/chargeguard.frozen"

// ---------- Khai báo class riêng của hệ thống ----------
@interface BluetoothManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)powered;
- (void)setPowered:(BOOL)powered;
- (BOOL)enabled;
- (void)setEnabled:(BOOL)enabled;
@end
@interface SBApplication : NSObject
- (NSString *)bundleIdentifier;
- (int)pid;
@end
@interface SBApplicationController : NSObject
+ (instancetype)sharedInstance;
- (NSArray *)runningApplications;
@end
// ---------- Trạng thái ----------
static BOOL gScreenOff = NO;
static BOOL gActive = NO;                 // đang ở chế độ tiết kiệm
static dispatch_source_t gDelayTimer = nil;
static NSMutableArray<NSNumber *> *gFrozen;     // pid đã SIGSTOP
static NSMutableArray<NSNumber *> *gThrottled;  // pid đã hạ ưu tiên
static BOOL gDidBT = NO, gBTWas = NO;
static BOOL gDidLoc = NO, gLocWas = NO;
static BOOL gDidLPM = NO;
static BOOL gDidAirDrop = NO; static id gAirDropWas = nil;
static double gLastHeldNotified = 0;
static BOOL gLowBatNotified = NO;
static BOOL gFailNotified = NO;
static BOOL gEmergNotified = NO;
static int gLastCableNotice = 0;
static NSString *gLastAnomalyNotice = @"";
static NSString *gLastCtxSSID = nil;
static BOOL gOutagePending = NO;
static double gOutageStart = 0;
static BOOL gAlarmArmed = NO;
// 0.2.1: trạng thái làm mát phía SpringBoard
static BOOL gCoolWasActive = NO;
static BOOL gCoolDidLPM = NO;
static BOOL gCoolDidAirplane = NO;
static float gCoolPrevBright = -1;
static NSMutableArray<NSNumber *> *gCoolThrottled = nil;

static void CGLog(NSString *fmt, ...) {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:CG_PREFS_PATH];
    if (p[K_LOG] && ![p[K_LOG] boolValue]) return;
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSDateFormatter *df = [NSDateFormatter new]; df.dateFormat = @"MM-dd HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"%@ [tweak] %@\n", [df stringFromDate:[NSDate date]], s];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:CG_LOG_PATH];
    if (!fh) {
        [@"" writeToFile:CG_LOG_PATH atomically:YES encoding:NSUTF8StringEncoding error:nil];
        chmod([CG_LOG_PATH fileSystemRepresentation], 0666);
        fh = [NSFileHandle fileHandleForWritingAtPath:CG_LOG_PATH];
    }
    if (fh) { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
}

static NSDictionary *Prefs(void) { return [NSDictionary dictionaryWithContentsOfFile:CG_PREFS_PATH] ?: @{}; }
static BOOL PB(NSDictionary *p, NSString *k, BOOL def) { return p[k] ? [p[k] boolValue] : def; }
static NSDictionary *Status(void) { return [NSDictionary dictionaryWithContentsOfFile:CG_STATUS_PATH] ?: @{}; }

static void SetPref(NSString *key, id val) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)val, (__bridge CFStringRef)CG_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)CG_DOMAIN);
}

// ---------- Thông báo đơn giản (hiện được cả khi khóa máy) ----------
static void ShowNotice(NSString *title, NSString *msg) {
    dispatch_async(dispatch_get_main_queue(), ^{
        CFOptionFlags f = 0;
        CFUserNotificationDisplayNotice(8.0, kCFUserNotificationNoteAlertLevel, NULL, NULL, NULL,
                                        (__bridge CFStringRef)title, (__bridge CFStringRef)msg, CFSTR("OK"));
        (void)f;
    });
}

// ---------- Danh sách app ----------
static NSArray *RunningApps(void) {
    Class c = objc_getClass("SBApplicationController");
    if (!c) return @[];
    id ctl = ((id (*)(id, SEL))objc_msgSend)(c, @selector(sharedInstance));
    if (![ctl respondsToSelector:@selector(runningApplications)]) return @[];
    return [ctl runningApplications] ?: @[];
}

static void SaveFrozenList(void) {
    NSArray *a = gFrozen.count ? [gFrozen copy] : @[];
    [a writeToFile:FROZEN_LIST atomically:YES];
}

static BOOL AppIsCandidate(SBApplication *app, NSArray *except, NSString **bidOut, int *pidOut) {
    NSString *bid = [app respondsToSelector:@selector(bundleIdentifier)] ? [app bundleIdentifier] : nil;
    if (!bid || [except containsObject:bid]) return NO;
    if ([bid hasPrefix:@"com.apple."]) return NO;          // không đụng app của Apple
    int pid = [app respondsToSelector:@selector(pid)] ? [app pid] : 0;
    if (pid <= 1) return NO;
    if (bidOut) *bidOut = bid;
    if (pidOut) *pidOut = pid;
    return YES;
}

// Đo %CPU nền của từng app bằng proc_pidinfo, hai mẫu cách nhau ~1.5 giây.
// Trả về nil nếu đo không được (mọi mẫu đều 0) để nơi gọi quay về cách cũ.
static NSDictionary *SampleAppCPU(NSArray *apps, NSArray *except) {
    NSMutableDictionary<NSNumber *, NSNumber *> *t0 = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSNumber *, NSString *> *names = [NSMutableDictionary dictionary];
    for (SBApplication *app in apps) {
        NSString *bid; int pid;
        if (!AppIsCandidate(app, except, &bid, &pid)) continue;
        struct CGProcTaskInfo ti;
        if (proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, sizeof(ti)) == (int)sizeof(ti)) {
            t0[@(pid)] = @(ti.pti_total_user + ti.pti_total_system);
            names[@(pid)] = bid;
        }
    }
    if (!t0.count) return nil;
    NSDate *start = [NSDate date];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        double wall = -[start timeIntervalSinceNow];
        long cores = sysconf(_SC_NPROCESSORS_ONLN);
        if (cores < 1) cores = 1;
        for (NSNumber *pidN in t0) {
            struct CGProcTaskInfo ti;
            if (proc_pidinfo(pidN.intValue, PROC_PIDTASKINFO, 0, &ti, sizeof(ti)) != (int)sizeof(ti)) continue;
            uint64_t delta = (ti.pti_total_user + ti.pti_total_system) - [t0[pidN] unsignedLongLongValue];
            double pct = wall > 0 ? ((double)delta / (wall * 1e9) * 100.0 / cores) : 0;
            result[pidN] = @(pct);
        }
        dispatch_semaphore_signal(sem);
    });
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)));
    BOOL anyNonZero = NO;
    for (NSNumber *v in result.allValues) if ([v doubleValue] > 0.01) { anyNonZero = YES; break; }
    if (!anyNonZero) { CGLog(@"đo CPU nền: mọi mẫu đều 0, quay về cách đóng băng cũ"); return nil; }
    result[@"__names"] = names;
    return result;
}

// ---------- Hành động ----------
static void ThrottleAndFreeze(NSDictionary *p) {
    BOOL doCPU = PB(p, K_S_CPU, NO), doFreeze = PB(p, K_S_FREEZE, NO);
    if (!doCPU && !doFreeze) return;
    NSArray *except = p[K_EXCEPT] ?: @[];
    NSArray *apps = RunningApps();

    // 0.2.0: bật cả giảm CPU lẫn đóng băng thì chỉ đóng băng app ngốn CPU thật,
    // các app còn lại chỉ bị giảm ưu tiên. Đo không được thì quay về cách cũ.
    NSDictionary *cpu = nil;
    if (doCPU && doFreeze) cpu = SampleAppCPU(apps, except);
    int level = p[K_S_CPU_LEVEL] ? [p[K_S_CPU_LEVEL] intValue] : 15;
    NSDictionary *names = cpu[@"__names"];

    for (SBApplication *app in apps) {
        NSString *bid; int pid;
        if (!AppIsCandidate(app, except, &bid, &pid)) continue;
        BOOL hog = YES; // không có số đo thì coi như trước (đóng băng hết ứng viên)
        if (cpu) {
            double pct = [cpu[@(pid)] doubleValue];
            hog = pct >= level;
            if (hog) CGLog(@"app ngốn CPU nền: %@ %.1f%% (ngưỡng %d%%)", bid, pct, level);
        }
        if (doFreeze && hog) {
            if (kill(pid, SIGSTOP) == 0) {
                [gFrozen addObject:@(pid)];
                CGLog(@"đóng băng %@ (%d)", bid, pid);
            }
        } else if (doCPU) {
            if (setpriority(PRIO_DARWIN_PROCESS, pid, PRIO_DARWIN_BG) == 0) {
                [gThrottled addObject:@(pid)];
            }
        }
    }
    (void)names;
    SaveFrozenList();
}

static void SetLowPower(BOOL on) {
    Class c = objc_getClass("_CDBatterySaver");
    if (!c) { CGLog(@"không có _CDBatterySaver"); return; }
    id inst = nil;
    if ([c respondsToSelector:@selector(batterySaver)]) inst = ((id (*)(id, SEL))objc_msgSend)(c, @selector(batterySaver));
    SEL sel = NSSelectorFromString(@"setPowerMode:error:");
    if (inst && [inst respondsToSelector:sel]) {
        ((BOOL (*)(id, SEL, long long, id *))objc_msgSend)(inst, sel, on ? 1 : 0, NULL);
        CGLog(@"low power mode -> %d", on);
    } else CGLog(@"không có setPowerMode:error:");
}

static void SetBluetooth(BOOL on) {
    dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_LAZY);
    Class c = objc_getClass("BluetoothManager");
    if (!c) return;
    BluetoothManager *m = [c sharedInstance];
    if ([m respondsToSelector:@selector(setPowered:)]) [m setPowered:on];
    if ([m respondsToSelector:@selector(setEnabled:)]) [m setEnabled:on];
}

static BOOL BluetoothIsOn(void) {
    dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_LAZY);
    Class c = objc_getClass("BluetoothManager");
    if (!c) return NO;
    BluetoothManager *m = [c sharedInstance];
    return [m respondsToSelector:@selector(powered)] ? [m powered] : NO;
}

static void ApplySavings(void) {
    NSDictionary *p = Prefs();
    gFrozen = [NSMutableArray array]; gThrottled = [NSMutableArray array];
    CGLog(@"BẬT tiết kiệm khi tắt màn hình");

    if (PB(p, K_S_BT, NO)) {
        gBTWas = BluetoothIsOn();
        if (gBTWas) { SetBluetooth(NO); gDidBT = YES; CGLog(@"tắt Bluetooth"); }
    }
    if (PB(p, K_S_LOC, NO)) {
        if ([CLLocationManager respondsToSelector:@selector(locationServicesEnabled)]) {
            gLocWas = [CLLocationManager locationServicesEnabled];
            if (gLocWas && [CLLocationManager respondsToSelector:NSSelectorFromString(@"setLocationServicesEnabled:")]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)([CLLocationManager class], NSSelectorFromString(@"setLocationServicesEnabled:"), NO);
                gDidLoc = YES; CGLog(@"tắt Dịch vụ định vị");
            }
        }
    }
    if (PB(p, K_S_AIRDROP, NO)) {
        id old = (__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("DiscoverableMode"), CFSTR("com.apple.sharingd"));
        gAirDropWas = old;
        if (![old isEqual:@"Off"]) {
            CFPreferencesSetAppValue(CFSTR("DiscoverableMode"), CFSTR("Off"), CFSTR("com.apple.sharingd"));
            CFPreferencesAppSynchronize(CFSTR("com.apple.sharingd"));
            gDidAirDrop = YES; CGLog(@"tắt AirDrop (thử nghiệm)");
        }
    }
    if (PB(p, K_S_LPM, NO)) {
        if (![[NSProcessInfo processInfo] isLowPowerModeEnabled]) { SetLowPower(YES); gDidLPM = YES; }
    }
    ThrottleAndFreeze(p);
    gActive = YES;
}

static void RestoreAll(NSString *why) {
    if (!gActive && !gFrozen.count && !gThrottled.count && !gDidBT && !gDidLoc && !gDidLPM && !gDidAirDrop) return;
    CGLog(@"KHÔI PHỤC (%@)", why);
    for (NSNumber *n in gFrozen) kill(n.intValue, SIGCONT);
    for (NSNumber *n in gThrottled) setpriority(PRIO_DARWIN_PROCESS, n.intValue, 0);
    gFrozen = nil; gThrottled = nil;
    [[NSFileManager defaultManager] removeItemAtPath:FROZEN_LIST error:nil];
    if (gDidBT && gBTWas) SetBluetooth(YES);
    gDidBT = NO;
    if (gDidLoc && gLocWas) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)([CLLocationManager class], NSSelectorFromString(@"setLocationServicesEnabled:"), YES);
    }
    gDidLoc = NO;
    if (gDidAirDrop) {
        CFPreferencesSetAppValue(CFSTR("DiscoverableMode"), (__bridge CFPropertyListRef)(gAirDropWas ?: @"Contacts Only"), CFSTR("com.apple.sharingd"));
        CFPreferencesAppSynchronize(CFSTR("com.apple.sharingd"));
    }
    gDidAirDrop = NO; gAirDropWas = nil;
    if (gDidLPM) SetLowPower(NO);
    gDidLPM = NO;
    gActive = NO;
}

// SpringBoard khởi động lại khi app còn bị đóng băng thì thả hết
static void RecoverFromCrash(void) {
    NSArray *left = [NSArray arrayWithContentsOfFile:FROZEN_LIST];
    for (NSNumber *n in left) { kill(n.intValue, SIGCONT); setpriority(PRIO_DARWIN_PROCESS, n.intValue, 0); }
    if (left.count) CGLog(@"khôi phục %lu app bị đóng băng từ lần trước", (unsigned long)left.count);
    [[NSFileManager defaultManager] removeItemAtPath:FROZEN_LIST error:nil];
}

// ---------- Điều kiện được phép tiết kiệm ----------
typedef void (^DoneBlock)(BOOL allowed);

static void CheckAllowed(NSDictionary *p, DoneBlock done) {
    NSDictionary *st = Status(); // pin và đang cắm sạc
    if (!PB(p, K_SAVE_CHARGING, NO) && [st[S_EXTERNAL] boolValue]) { CGLog(@"bỏ qua: đang cắm sạc"); done(NO); return; }
    // 0.2.0: chốt nhiệt cho phần tiết kiệm — pin đang nóng thì không đóng băng app
    if (PB(p, K_TEMP_ON, YES) && [st[S_TEMP] doubleValue] >= (p[K_TEMP_MAX] ? [p[K_TEMP_MAX] intValue] : 40)) {
        CGLog(@"bỏ qua: pin đang nóng (%.1f°C)", [st[S_TEMP] doubleValue]); done(NO); return;
    }
    Class tc = objc_getClass("TUCallCenter");
    if (tc && [tc respondsToSelector:@selector(sharedInstance)]) {
        id cc = ((id (*)(id, SEL))objc_msgSend)(tc, @selector(sharedInstance));
        SEL s = NSSelectorFromString(@"currentCallCount");
        if ([cc respondsToSelector:s] && ((long (*)(id, SEL))objc_msgSend)(cc, s) > 0) { CGLog(@"bỏ qua: đang gọi"); done(NO); return; }
    }
    void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    typedef void (*GetPlaying)(dispatch_queue_t, void (^)(Boolean));
    GetPlaying fn = h ? (GetPlaying)dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") : NULL;
    if (!fn) { done(YES); return; }
    fn(dispatch_get_main_queue(), ^(Boolean playing) {
        if (playing) CGLog(@"bỏ qua: đang phát nhạc/video");
        done(!playing);
    });
}

// ---------- Màn hình tắt / bật ----------
static void CancelDelay(void) {
    if (gDelayTimer) { dispatch_source_cancel(gDelayTimer); gDelayTimer = nil; }
}

static void ScreenChanged(BOOL off) {
    if (off == gScreenOff) return;
    gScreenOff = off;
    NSDictionary *p = Prefs();
    CancelDelay();
    if (!off) {
        RestoreAll(@"mở màn hình");
        gOutagePending = NO; // có người đụng vào máy thì không tính là mất điện nữa
        return;
    }
    if (!PB(p, K_SAVE_ON, NO)) return;
    int mins = p[K_SAVE_DELAY] ? [p[K_SAVE_DELAY] intValue] : 2;
    CGLog(@"màn hình tắt, chờ %d phút", mins);
    gDelayTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(gDelayTimer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)mins * 60 * NSEC_PER_SEC), DISPATCH_TIME_FOREVER, NSEC_PER_SEC);
    dispatch_source_set_event_handler(gDelayTimer, ^{
        CancelDelay();
        if (!gScreenOff || gActive) return;
        NSDictionary *pp = Prefs();
        CheckAllowed(pp, ^(BOOL ok) { if (ok && gScreenOff && !gActive) ApplySavings(); });
    });
    dispatch_resume(gDelayTimer);
}

// ---------- 0.2.0: sạc đầy theo Lịch ----------
static EKEventStore *gCalStore = nil;
static BOOL gCalAsked = NO;
static void CheckCalendar(NSDictionary *p) {
    if (!PB(p, K_CAL_ON, NO)) return;
    @try {
        if (!gCalStore) gCalStore = [EKEventStore new];
        if (!gCalAsked) {
            gCalAsked = YES;
            [gCalStore requestAccessToEntityType:EKEntityTypeEvent completion:^(BOOL granted, NSError *err) {
                CGLog(@"quyền đọc Lịch: %@%@", granted ? @"được cấp" : @"BỊ TỪ CHỐI", err ? err.localizedDescription : @"");
            }];
            return;
        }
        if ([EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent] != EKAuthorizationStatusAuthorized) return;
        int before = p[K_CAL_BEFORE] ? [p[K_CAL_BEFORE] intValue] : 120;
        NSDate *now = [NSDate date];
        NSDate *to = [now dateByAddingTimeInterval:before * 60];
        NSPredicate *pred = [gCalStore predicateForEventsWithStartDate:now endDate:to calendars:nil];
        NSArray *events = [gCalStore eventsMatchingPredicate:pred];
        for (EKEvent *ev in events) {
            if (ev.allDay) continue;
            // sự kiện bắt đầu trong cửa sổ => đặt cờ sạc đầy cho daemon
            SetPref(K_CAL_FULL_STAMP, @([now timeIntervalSince1970]));
            CGLog(@"Lịch: sự kiện '%@' lúc %@ — đặt cờ sạc đầy", ev.title ?: @"", ev.startDate);
            break;
        }
    } @catch (NSException *e) {
        CGLog(@"Lịch: lỗi %@", e.reason);
    }
}

// ---------- 0.2.0: hồ sơ sạc theo Wi-Fi ----------
static NSString *CurrentSSID(void) {
    static void *lib = NULL;
    static CFArrayRef (*copyIfs)(void) = NULL;
    static CFDictionaryRef (*copyInfo)(CFStringRef) = NULL;
    if (!lib) {
        lib = dlopen("/System/Library/Frameworks/CaptiveNetwork.framework/CaptiveNetwork", RTLD_LAZY);
        if (lib) {
            copyIfs = (CFArrayRef (*)(void))dlsym(lib, "CNCopySupportedInterfaces");
            copyInfo = (CFDictionaryRef (*)(CFStringRef))dlsym(lib, "CNCopyCurrentNetworkInfo");
        }
    }
    if (!copyIfs || !copyInfo) return nil;
    NSArray *ifs = (__bridge_transfer NSArray *)copyIfs();
    for (NSString *ifn in ifs) {
        NSDictionary *info = (__bridge_transfer NSDictionary *)copyInfo((__bridge CFStringRef)ifn);
        NSString *ssid = info[@"SSID"];
        if (ssid.length) return ssid;
    }
    return nil;
}

static void CheckWiFiContext(NSDictionary *p) {
    NSString *home = p[K_HOME_WIFI];
    if (![home isKindOfClass:[NSString class]] || !home.length) return;
    NSString *ssid = CurrentSSID();
    if (!ssid) return;
    int ctx = 0;
    if ([ssid isEqualToString:home]) ctx = p[K_HOME_LIMIT] ? [p[K_HOME_LIMIT] intValue] : 80;
    else if (PB(p, K_AWAY_FULL, NO)) ctx = 100;
    int old = [p[K_CTX_LIMIT] intValue];
    if (ctx != old) {
        SetPref(K_CTX_LIMIT, @(ctx));
        SetPref(K_CTX_STAMP, @([[NSDate date] timeIntervalSince1970]));
        CGLog(@"Wi-Fi '%@' (nhà: '%@') => mức hiệu lực %@", ssid, home, ctx ? @(ctx) : @"thường");
    } else {
        SetPref(K_CTX_STAMP, @([[NSDate date] timeIntervalSince1970])); // gia hạn mốc
    }
    gLastCtxSSID = ssid;
}

// ---------- 0.2.1: Làm mát khi sạc — phần SpringBoard ----------
// Daemon lo phần sạc chậm theo nhịp; phần này lo các yếu tố phía hệ thống:
// giảm CPU app nền ngốn, Chế độ nguồn điện thấp, giảm độ sáng, chế độ máy bay.
// Mọi thay đổi đều được khôi phục nguyên trạng khi pin nguội hoặc rút sạc.
static BOOL SetAirplaneMode(BOOL on) {
    Class c = objc_getClass("SBTelephonyManager");
    if (!c) { CGLog(@"làm mát: không thấy SBTelephonyManager"); return NO; }
    id mgr = nil;
    if ([c respondsToSelector:@selector(sharedTelephonyManager)])
        mgr = ((id (*)(id, SEL))objc_msgSend)(c, @selector(sharedTelephonyManager));
    SEL sel = NSSelectorFromString(@"setIsInAirplaneMode:");
    if (mgr && [mgr respondsToSelector:sel]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(mgr, sel, on);
        CGLog(@"làm mát: chế độ máy bay -> %d", on);
        return YES;
    }
    CGLog(@"làm mát: SBTelephonyManager không có setIsInAirplaneMode:");
    return NO;
}

static float CurrentBrightness(void) {
    typedef float (*GetFn)(void);
    static GetFn getFn = NULL;
    if (!getFn) getFn = (GetFn)dlsym(RTLD_DEFAULT, "BKSDisplayBrightnessGet");
    return getFn ? getFn() : -1;
}

static BOOL SetBrightness(float level) {
    typedef void (*SetFn)(float, int);
    static SetFn setFn = NULL;
    if (!setFn) setFn = (SetFn)dlsym(RTLD_DEFAULT, "BKSDisplayBrightnessSet");
    if (!setFn) return NO;
    setFn(level, 0);
    return YES;
}

// Chỉ giảm ưu tiên CPU (không đóng băng) cho app nền ngốn CPU — an toàn khi máy đang mở.
static void CoolThrottleApps(NSDictionary *p) {
    NSArray *except = p[K_EXCEPT] ?: @[];
    NSArray *apps = RunningApps();
    NSDictionary *cpu = SampleAppCPU(apps, except);
    if (!cpu) return; // đo không được hoặc không app nào ngốn thật: không đụng gì
    int level = p[K_S_CPU_LEVEL] ? [p[K_S_CPU_LEVEL] intValue] : 15;
    if (!gCoolThrottled) gCoolThrottled = [NSMutableArray array];
    for (SBApplication *app in apps) {
        NSString *bid; int pid;
        if (!AppIsCandidate(app, except, &bid, &pid)) continue;
        if ([cpu[@(pid)] doubleValue] < level) continue;
        if (setpriority(PRIO_DARWIN_PROCESS, pid, PRIO_DARWIN_BG) == 0) {
            [gCoolThrottled addObject:@(pid)];
            CGLog(@"làm mát: giảm CPU %@ (%.1f%% nền)", bid, [cpu[@(pid)] doubleValue]);
        }
    }
}

static void HandleCooling(NSDictionary *p, NSDictionary *st) {
    BOOL active = PB(p, K_COOL_ON, NO) && [st[S_COOL] boolValue];
    double temp = [st[S_TEMP] doubleValue];
    int coolTemp = p[K_COOL_TEMP] ? [p[K_COOL_TEMP] intValue] : 40;

    if (active && !gCoolWasActive) {
        CGLog(@"làm mát phía hệ thống: BẬT (pin %.1f°C)", temp);
        if (PB(p, K_COOL_NOTIFY, YES))
            ShowNotice(@"ChargeGuard — Làm mát", [NSString stringWithFormat:@"Pin nóng %.0f°C, đang bật các biện pháp làm mát khi sạc.", temp]);
        if (PB(p, K_COOL_APPS, YES) && !gActive) CoolThrottleApps(p);
        if (PB(p, K_COOL_LPM, YES) && ![[NSProcessInfo processInfo] isLowPowerModeEnabled]) {
            SetLowPower(YES); gCoolDidLPM = YES;
        }
        if (PB(p, K_COOL_DIM, NO)) {
            float cur = CurrentBrightness();
            float lv = (p[K_COOL_DIMLV] ? [p[K_COOL_DIMLV] intValue] : 40) / 100.0f;
            if (cur > lv && SetBrightness(lv)) {
                gCoolPrevBright = cur;
                CGLog(@"làm mát: giảm độ sáng %.2f -> %.2f", cur, lv);
            }
        }
    }
    // Nóng hơn nữa (ngưỡng + 3°C) mới tính tới chế độ máy bay, và chỉ khi đã bật sẵn tuỳ chọn này
    if (active && !gCoolDidAirplane && PB(p, K_COOL_AIR, NO) && temp >= coolTemp + 3) {
        if (SetAirplaneMode(YES)) gCoolDidAirplane = YES;
    }
    if (!active && gCoolWasActive) {
        CGLog(@"làm mát phía hệ thống: TẮT, khôi phục mọi thứ");
        if (gCoolDidLPM) { SetLowPower(NO); gCoolDidLPM = NO; }
        if (gCoolPrevBright >= 0) { SetBrightness(gCoolPrevBright); gCoolPrevBright = -1; }
        if (gCoolDidAirplane) { SetAirplaneMode(NO); gCoolDidAirplane = NO; }
        for (NSNumber *pidN in gCoolThrottled) setpriority(PRIO_DARWIN_PROCESS, pidN.intValue, 0);
        [gCoolThrottled removeAllObjects];
        if (PB(p, K_COOL_NOTIFY, YES))
            ShowNotice(@"ChargeGuard — Làm mát", @"Pin đã nguội, đã tắt các biện pháp làm mát.");
    }
    gCoolWasActive = active;
}

// ---------- Vòng kiểm tra định kỳ ----------
static void PeriodicTick(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:CG_RESTORE_FLAG]) {
        [fm removeItemAtPath:CG_RESTORE_FLAG error:nil];
        RestoreAll(@"nút Khôi phục");
    }
    NSDictionary *p = Prefs(), *st = Status();
    double now = [[NSDate date] timeIntervalSince1970];

    // thông báo chạm giới hạn (như bản cũ)
    double held = [st[@"heldAt"] doubleValue];
    if (PB(p, K_NOTIFY, NO) && held > gLastHeldNotified && [st[S_HOLDING] boolValue]) {
        gLastHeldNotified = held;
        ShowNotice(@"ChargeGuard", [NSString stringWithFormat:@"Pin đã chạm giới hạn, đang giữ ở %@%%.", st[S_PERCENT]]);
    } else if (held > gLastHeldNotified) gLastHeldNotified = held;

    if (PB(p, K_LOWBAT_ON, NO)) {
        int lvl = p[K_LOWBAT_LEVEL] ? [p[K_LOWBAT_LEVEL] intValue] : 20;
        int pct = [st[S_PERCENT] intValue];
        BOOL ext = [st[S_EXTERNAL] boolValue];
        if (!ext && pct > 0 && pct <= lvl && !gLowBatNotified) {
            gLowBatNotified = YES;
            ShowNotice(@"ChargeGuard", [NSString stringWithFormat:@"Pin còn %d%%.", pct]);
        } else if (ext || pct > lvl + 3) gLowBatNotified = NO;
    }

    // 0.2.0: daemon báo không ngắt được sạc thì nói rõ cho người dùng, một lần mỗi lần khởi động
    // 0.2.1: có công tắc riêng (notifyFail, mặc định bật)
    if (PB(p, K_NOTIFY_FAIL, YES) && [st[S_SUPPORTED] intValue] == 0 && !gFailNotified) {
        gFailNotified = YES;
        ShowNotice(@"ChargeGuard", @"Máy này không cho phần mềm ngắt sạc, giới hạn sạc không hoạt động. Xem chi tiết trong Cài đặt > ChargeGuard.");
    }
    // 0.2.0: vệ sĩ nhiệt kích hoạt
    if ([st[S_EMERG] boolValue] && !gEmergNotified) {
        gEmergNotified = YES;
        ShowNotice(@"ChargeGuard — Vệ sĩ nhiệt", [NSString stringWithFormat:@"Pin nóng %@°C, đã ngắt sạc để bảo vệ pin.", st[S_TEMP]]);
    } else if (![st[S_EMERG] boolValue]) gEmergNotified = NO;
    // 0.2.0: cáp chập chờn
    if (PB(p, K_CABLE_ON, NO)) {
        int warn = [st[S_CABLEWARN] intValue];
        int threshold = (p[K_CABLE_COUNT] ? [p[K_CABLE_COUNT] intValue] : 5) * 2;
        if (warn >= threshold && warn != gLastCableNotice) {
            gLastCableNotice = warn;
            ShowNotice(@"ChargeGuard", [NSString stringWithFormat:@"Cáp/củ sạc chập chờn: %d lần ngắt-nối trong 10 phút. Nên thay cáp.", warn / 2]);
        }
    }
    // 0.2.0: pin bất thường
    NSString *anomaly = st[S_ANOMALY];
    if ([anomaly isKindOfClass:[NSString class]] && anomaly.length && ![anomaly isEqualToString:gLastAnomalyNotice]) {
        gLastAnomalyNotice = anomaly;
        ShowNotice(@"ChargeGuard", anomaly);
    }

    // 0.2.0: mất điện + báo động rút sạc — theo dõi nguồn sạc khi màn hình tắt
    static BOOL lastExt = NO; static BOOL extInit = NO;
    BOOL ext = [st[S_EXTERNAL] boolValue];
    if (!extInit) { lastExt = ext; extInit = YES; }
    if (ext != lastExt) {
        if (!ext && gScreenOff) {
            // bị ngắt sạc trong lúc máy đang ngủ
            if (PB(p, K_ALARM_ON, NO)) {
                gAlarmArmed = YES;
                ShowNotice(@"ChargeGuard — Báo động", @"Sạc vừa bị rút khi máy đang khoá!");
                for (int i = 0; i < 3; i++) AudioServicesPlaySystemSound(1005);
            }
            if (PB(p, K_OUTAGE_ON, NO) && !gOutagePending) {
                gOutagePending = YES; gOutageStart = now;
                CGLog(@"ngắt sạc khi máy ngủ: bắt đầu tính mất điện");
            }
        }
        if (ext && gOutagePending) {
            gOutagePending = NO;
            double mins = (now - gOutageStart) / 60.0;
            int minNeed = p[K_OUTAGE_MIN] ? [p[K_OUTAGE_MIN] intValue] : 5;
            if (mins >= minNeed) {
                NSMutableArray *recs = [NSMutableArray arrayWithContentsOfFile:CG_OUTAGE_PATH];
                if (!recs) recs = [NSMutableArray array];
                [recs addObject:@{@"start": @(gOutageStart), @"minutes": @((int)mins)}];
                while (recs.count > 100) [recs removeObjectAtIndex:0];
                [recs writeToFile:CG_OUTAGE_PATH atomically:YES];
                chmod([CG_OUTAGE_PATH fileSystemRepresentation], 0666);
                ShowNotice(@"ChargeGuard", [NSString stringWithFormat:@"Vừa mất điện khoảng %d phút (điện đã có lại).", (int)mins]);
                CGLog(@"mất điện %.0f phút, đã ghi sổ", mins);
            }
        }
        lastExt = ext;
    }

    CheckCalendar(p);
    CheckWiFiContext(p);
    HandleCooling(p, st);
}

%ctor {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        CGLog(@"tweak 0.2.2 nạp vào SpringBoard");
        RecoverFromCrash();

        int tok1, tok2;
        notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &tok1, dispatch_get_main_queue(), ^(int t) {
            uint64_t state = 0; notify_get_state(t, &state);
            ScreenChanged(state != 0);
        });
        notify_register_dispatch("com.chargeguard/restore", &tok2, dispatch_get_main_queue(), ^(int t) {
            RestoreAll(@"thông báo từ Cài đặt");
        });

        dispatch_source_t tick = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(tick, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), 30 * NSEC_PER_SEC, 5 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(tick, ^{ @autoreleasepool { PeriodicTick(); } });
        dispatch_resume(tick);
        // giữ tham chiếu cho timer sống suốt (gán vào biến static)
        static dispatch_source_t keep; keep = tick; (void)keep;
    }
}
