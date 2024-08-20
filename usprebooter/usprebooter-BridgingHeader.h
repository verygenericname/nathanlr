//
//  usprebooter-BridgingHeader.h
//  nathanlr
//
//  Created by Nathan Senter on 8/14/24.
//

#include "troller.h"
#include "util.h"
#include "Exploits/kfd/kfd.h"
#include "patchfinder/patchfind.h"
#include "Exploits/libjailbreak/vnode.h"
#import "TDRootViewController.h"
#import "UI/AppDelegate.h"

NSString *executablePathForPID(pid_t pid);
int reboot3(uint64_t flags);
