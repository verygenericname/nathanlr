//
//  usprebooter-BridgingHeader.h
//  nathanlr
//
//  Created by Nathan Senter on 8/14/24.
//

#include "troller.h"
#include "util.h"
#import "TDRootViewController.h"
#import "UI/AppDelegate.h"

NSString *executablePathForPID(pid_t pid);
int reboot3(uint64_t flags);
void runPacBrute(void (^ _Nullable completion)(void));
int ensure_755(const char *path);
NSError *showNonDefaultSystemApps(void);
