#import "CGAppDelegate.h"
#import "CGTheme.h"
#import "CGHomeViewController.h"
#import "CGChartViewController.h"
#import "CGMoreViewController.h"

@implementation CGAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    CGHomeViewController *home = [CGHomeViewController new];
    home.title = @"Tổng quan";
    home.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Tổng quan" image:[UIImage systemImageNamed:@"battery.75"] tag:0];

    CGChartViewController *chart = [CGChartViewController new];
    chart.title = @"Biểu đồ";
    chart.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Biểu đồ" image:[UIImage systemImageNamed:@"chart.line.uptrend.xyaxis"] tag:1];

    CGMoreViewController *more = [CGMoreViewController new];
    more.title = @"Cài đặt";
    more.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Cài đặt" image:[UIImage systemImageNamed:@"gearshape"] tag:2];

    UITabBarController *tabs = [UITabBarController new];
    tabs.viewControllers = @[
        [[UINavigationController alloc] initWithRootViewController:home],
        [[UINavigationController alloc] initWithRootViewController:chart],
        [[UINavigationController alloc] initWithRootViewController:more],
    ];
    self.window.rootViewController = tabs;
    [CGTheme applyAccentToWindow:self.window];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
