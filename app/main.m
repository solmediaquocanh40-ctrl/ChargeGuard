#import <UIKit/UIKit.h>
#import "CGAppDelegate.h"

static void CGExceptionHandler(NSException *exception) {
    NSString *line = [NSString stringWithFormat:@"[app] CRASH %@ — %@\n%@\n",
        exception.name, exception.reason, [exception.callStackSymbols componentsJoinedByString:@"\n"]];
    NSString *path = @"/var/mobile/Documents/ChargeGuard.log";
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (fh) { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
}

int main(int argc, char *argv[]) {
    NSSetUncaughtExceptionHandler(&CGExceptionHandler);
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([CGAppDelegate class]));
    }
}
