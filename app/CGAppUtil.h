// CGAppUtil.h - hàm dùng chung trong app ChargeGuard (đọc/ghi cùng kho cài đặt
// và file trạng thái với daemon, tweak và trang Cài đặt).
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <notify.h>
#import "../Shared/CGShared.h"

static inline NSDictionary *CGPrefs(void) {
    return [NSDictionary dictionaryWithContentsOfFile:CG_PREFS_PATH] ?: @{};
}
static inline NSDictionary *CGStatus(void) {
    return [NSDictionary dictionaryWithContentsOfFile:CG_STATUS_PATH] ?: @{};
}
static inline void CGSetPref(NSString *key, id val) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)val, (__bridge CFStringRef)CG_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)CG_DOMAIN);
    notify_post(CG_PREFS_NOTIFY);
}
static inline BOOL CGB(NSDictionary *p, NSString *k, BOOL def) { return p[k] ? [p[k] boolValue] : def; }
static inline int CGI(NSDictionary *p, NSString *k, int def) { return p[k] ? [p[k] intValue] : def; }

static inline NSString *CGStateText(NSDictionary *s) {
    if (!s.count) return @"Chưa có dữ liệu từ daemon";
    if ([s[S_EMERG] boolValue]) return @"Vệ sĩ nhiệt đang ngắt sạc";
    if ([s[S_HOLDING] boolValue]) {
        if ([s[S_STORAGE] boolValue]) return @"Đang giữ ở chế độ lưu kho";
        if ([s[S_PULSE] boolValue]) return @"Sạc xung — đang nghỉ";
        return @"Đang giữ ở mức giới hạn";
    }
    if ([s[S_BOOST] boolValue]) return @"Đang sạc cấp tốc";
    if ([s[S_CHARGING] boolValue]) return @"Đang sạc";
    if ([s[S_EXTERNAL] boolValue]) return @"Đã cắm sạc, không sạc";
    return @"Không cắm sạc";
}

static inline void CGShowAlert(UIViewController *vc, NSString *title, NSString *msg) {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [vc presentViewController:a animated:YES completion:nil];
}
static inline void CGShare(UIViewController *vc, NSArray *items) {
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    share.popoverPresentationController.sourceView = vc.view;
    share.popoverPresentationController.sourceRect = CGRectMake(vc.view.bounds.size.width / 2, vc.view.bounds.size.height / 2, 1, 1);
    [vc presentViewController:share animated:YES completion:nil];
}
