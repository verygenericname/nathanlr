#import "TDUtils.h"
#import "DumpDecrypted.h"
#import "LSApplicationProxy+AltList.h"
#import "util.h"
#import "TSPresentationDelegate.h"

UIWindow *alertWindow = NULL;
UIWindow *kw = NULL;
UIViewController *root = NULL;
UIAlertController *alertController = NULL;
UIAlertController *doneController = NULL;
UIAlertController *errorController = NULL;

NSMutableArray *appList(void) {
    NSMutableArray *apps = [NSMutableArray array];

    NSArray <LSApplicationProxy *> *installedApplications = [[LSApplicationWorkspace defaultWorkspace] atl_allInstalledApplications];
    [installedApplications enumerateObjectsUsingBlock:^(LSApplicationProxy *proxy, NSUInteger idx, BOOL *stop) {

        NSString *bundleID = [proxy atl_bundleIdentifier];
        NSString *name = [proxy atl_nameToDisplay];
        NSString *version = [proxy atl_shortVersionString];
        NSString *executable = proxy.canonicalExecutablePath;
        NSString *injected = @"";
        
        NSString *appBundlePath = appPath(bundleID);
        NSString *appBundleAppPath = findAppPathInBundlePath(appBundlePath);
        
        if ([appBundlePath containsString:@"/var/containers/Bundle/Application/"]) {
            if ([name isEqualToString:@"TrollStore"]) return;
            if ([name isEqualToString:@"NathanLR"]) return;
            if (fileExists([appBundleAppPath stringByAppendingString:@"/.TrollStorePersistenceHelper"])) return;
        } else {
            if (![proxy atl_isUserApplication]) return;
        }

        if (!bundleID || !name || !version || !executable) return;
        
        if(fileExists([appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"])) {
            BOOL isExec = [[NSFileManager defaultManager] isExecutableFileAtPath:[appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"]];
            
            if (!isExec) {
                injected = @" • Injected✅";
            }
        }

        NSMutableDictionary *item = [NSMutableDictionary dictionaryWithDictionary:@{
            @"bundleID":bundleID,
            @"name":name,
            @"version":version,
            @"executable":executable,
            @"injected":injected
        }];

        [apps addObject:item];
    }];

    NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
    [apps sortUsingDescriptors:@[descriptor]];

    return [apps copy];
}

NSUInteger iconFormat(void) {
    return (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) ? 8 : 10;
}

NSArray *sysctl_ps(void);

pid_t findProcessID(NSString *appName) {
    pid_t pid = -1;
    NSArray *processes = sysctl_ps();
    for (NSDictionary *process in processes) {
        NSString *proc_name = process[@"proc_name"];
        if ([proc_name isEqualToString:appName]) {
            pid = [process[@"pid"] intValue];
            break;
        }
    }
    return pid;
}

//void launchAndCheckProcess(NSString *appName, NSString *bundleID) {
//    pid_t pid = -1;
//    killall2(appName, YES, NO);
//    while (pid == -1) {
//        pid = findProcessID(appName);
//        if (pid == -1) {
//
//            [[UIApplication sharedApplication] launchApplicationWithIdentifier:bundleID suspended:YES];
//
//            [NSThread sleepForTimeInterval:1.0];
//        }
//    }
//    NSLog(@"Process %@ with PID %d found!", appName, pid);
//}

NSString* findAppPathInBundlePath(NSString* bundlePath);

void decryptApp(NSDictionary *app) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [TSPresentationDelegate startActivity:@"Injecting..."];
//        alertWindow = [[UIWindow alloc] initWithFrame: [UIScreen mainScreen].bounds];
//        alertWindow.rootViewController = [UIViewController new];
//        alertWindow.windowLevel = UIWindowLevelAlert + 1;
//        [alertWindow makeKeyAndVisible];
        
        // Show a "Decrypting!" alert on the device and block the UI
    });

//    NSLog(@"[trolldecrypt] spawning thread to do decryption in background...");

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//        NSLog(@"[trolldecrypt] inside decryption thread.");
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSFileManager *fileManager2 = [NSFileManager defaultManager];
        NSString *bundleID = app[@"bundleID"];
        NSString *name = app[@"name"];
        NSString *version = app[@"version"];
        NSString *executable = app[@"executable"];
        NSString *binaryName = [executable lastPathComponent];
        
        NSString *appBundlePath = appPath(bundleID);
        NSString *appBundleAppPath = findAppPathInBundlePath(appBundlePath);

//        NSLog(@"[trolldecrypt] bundleID: %@", bundleID);
//        NSLog(@"[trolldecrypt] name: %@", name);
//        NSLog(@"[trolldecrypt] version: %@", version);
//        NSLog(@"[trolldecrypt] executable: %@", executable);
//        NSLog(@"[trolldecrypt] binaryName: %@", binaryName);
        
        [[UIApplication sharedApplication] launchApplicationWithIdentifier:bundleID suspended:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSMutableArray* args = [NSMutableArray new];
            [args addObject:@"--appinject"];
            [args addObject:bundleID];
            NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
            NSString *binaryPath = [bundlePath stringByAppendingPathComponent:@"NathanLR"];
            spawnRoot(binaryPath, args, nil, nil);

            dispatch_async(dispatch_get_main_queue(), ^{
                [TSPresentationDelegate stopActivityWithCompletion:^{
                        doneController = [UIAlertController alertControllerWithTitle:@"Done toggling Tweaks" message:@"If your tweaks are not there, try toggling on again until it works.\n(The injector is prone to crashes don't know why)\nIf you have injected into this app, it will not work in normal mode. Please uninject if you would like to use it in normal mode. (If it's a trollstore app it will just not have tweaks in normal mode.)" preferredStyle:UIAlertControllerStyleAlert];
                        UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil];
                        [doneController addAction:cancel];
                        [TSPresentationDelegate presentViewController:doneController animated:YES completion:nil];
                }];
            });
    });
    });
}
