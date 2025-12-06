#import "AppDelegate.h"
#import "CoreServices.h"
#import "nathanlr-Swift.h"

BOOL launchTest(NSString *arg1);

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.tintColor = [UIColor systemGreenColor];
    MainTabBarController *tabBarController = [[MainTabBarController alloc] init];
    self.window.rootViewController = tabBarController;
    [self.window makeKeyAndVisible];
    
//    if (getuid() == 501) {
//        [[LSApplicationWorkspace defaultWorkspace] openApplicationWithBundleID:@"com.apple.springboard"];
//        launchTest(nil);
//        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//                [[LSApplicationWorkspace defaultWorkspace] openApplicationWithBundleID:NSBundle.mainBundle.bundleIdentifier];
//        });
//    }
    
    return YES;
}

@end
