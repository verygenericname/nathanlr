//
//  main.m
//  FileTroller
//
//  Created by Nathan Senter on 3/7/23.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import <stdio.h>
#include <spawn.h>
//#import "fun/kpf/patchfinder.h"
#include "util.h"
#import "CoreServices.h"
#import "DumpDecrypted.h"
#include <stdlib.h>
#include <unistd.h>
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <mach-o/loader.h>
#include <mach-o/dyld_images.h>
#include <fcntl.h>
#include <mach/task_info.h>
#import <sys/sysctl.h>
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <sys/proc_info.h>
#include <libproc.h>
#include "patchfinder/patchfind.h"

@interface UIApplication (tweakName)
+ (id)sharedApplication;
- (BOOL)launchApplicationWithIdentifier:(id)arg1 suspended:(BOOL)arg2;
@end

int apply_coretrust_bypass_wrapper(const char *inputPath, const char *outputPath, char *teamID, char *appStoreBinary);
int ptrace(int, int, int, int);
NSString *executablePathForPID(pid_t pid) {
    char pathBuffer[PROC_PIDPATHINFO_MAXSIZE];
    int result = proc_pidpath(pid, pathBuffer, sizeof(pathBuffer));

    if (result > 0) {
        NSString *executablePath = [NSString stringWithUTF8String:pathBuffer];
        return executablePath;
    }

    return nil;
}

void setOwnershipForFolder(NSString *folderPath) {
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSError *error;
    NSDictionary *attributes = @{
        NSFileOwnerAccountID: @(501),
        NSFileGroupOwnerAccountID: @(501)
    };

    if ([fileManager setAttributes:attributes ofItemAtPath:folderPath error:&error]) {
        NSLog(@"Ownership changed successfully for %@", folderPath);

        NSArray *contents = [fileManager contentsOfDirectoryAtPath:folderPath error:nil];
        for (NSString *item in contents) {
            NSString *itemPath = [folderPath stringByAppendingPathComponent:item];
            setOwnershipForFolder(itemPath);
        }
    } else {
        NSLog(@"Error changing ownership for %@: %@", folderPath, [error localizedDescription]);
    }
}

void createSymlink(NSString *originalPath, NSString *symlinkPath) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    BOOL success = [fileManager createSymbolicLinkAtPath:symlinkPath withDestinationPath:originalPath error:&error];
    
    if (success) {
        NSLog(@"Symlink created successfully at %@", symlinkPath);
    } else {
        NSLog(@"Failed to create symlink: %@", [error localizedDescription]);
    }
}

BOOL removeFileAtPath(NSString *filePath) {
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSError *error;
        if ([fileManager removeItemAtPath:filePath error:&error]) {
            NSLog(@"File removed successfully: %@", filePath);
            return YES;
        } else {
            NSLog(@"Error removing file at %@: %@", filePath, [error localizedDescription]);
        }

    return NO;
}

BOOL copyFile(NSString *sourcePath, NSString *destinationPath) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    
    BOOL success = [fileManager copyItemAtPath:sourcePath toPath:destinationPath error:&error];
    
    if (success) {
        NSLog(@"File copied successfully");
    } else {
        NSLog(@"Error copying file: %@", [error localizedDescription]);
    }
    
    return success;
}

NSString* appPath(NSString* identifier)
{
    NSError* mcmError;
    MCMAppContainer* appContainer = [MCMAppContainer containerWithIdentifier:identifier createIfNecessary:NO existed:NULL error:&mcmError];
    if(!appContainer) return nil;
    return appContainer.url.path;
}

BOOL moveFile(NSString *sourcePath, NSString *destinationPath) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    
    BOOL success = [fileManager moveItemAtPath:sourcePath toPath:destinationPath error:&error];
    
    if (success) {
        NSLog(@"File moved successfully");
    } else {
        NSLog(@"Error moving file: %@", [error localizedDescription]);
    }
    
    return success;
}

BOOL removeExecutePermission(NSString *filePath) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if (![fileManager fileExistsAtPath:filePath]) {
        NSLog(@"Error: File does not exist at %@", filePath);
        return NO;
    }

    NSError *error;
    NSMutableDictionary *attributes = [[fileManager attributesOfItemAtPath:filePath error:&error] mutableCopy];
    
    if (attributes) {
        NSNumber *currentPermissions = attributes[NSFilePosixPermissions];
        
        if (currentPermissions != nil) {
            NSUInteger newPermissions = [currentPermissions unsignedIntegerValue] & ~(S_IXUSR | S_IXGRP | S_IXOTH);
    
            [attributes setObject:@(newPermissions) forKey:NSFilePosixPermissions];
            
            if ([fileManager setAttributes:attributes ofItemAtPath:filePath error:&error]) {
                NSLog(@"Execute bit removed successfully from %@", filePath);
                return YES;
            } else {
                NSLog(@"Error updating file attributes: %@", [error localizedDescription]);
            }
        } else {
            NSLog(@"Error: Unable to retrieve file permissions for %@", filePath);
        }
    } else {
        NSLog(@"Error retrieving file attributes: %@", [error localizedDescription]);
    }
    
    return NO;
}

BOOL setUserAndGroup(NSString *filePath) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if (![fileManager fileExistsAtPath:filePath]) {
        NSLog(@"Error: File does not exist at %@", filePath);
        return NO;
    }

    NSError *error;
    
    NSMutableDictionary *attributes = [[fileManager attributesOfItemAtPath:filePath error:&error] mutableCopy];
    
    if (attributes) {
        [attributes setObject:@(33) forKey:NSFileOwnerAccountID];
        [attributes setObject:@(33) forKey:NSFileGroupOwnerAccountID];

        if ([fileManager setAttributes:attributes ofItemAtPath:filePath error:&error]) {
            NSLog(@"User and group set successfully for %@", filePath);
            return YES;
        } else {
            NSLog(@"Error updating file attributes: %@", [error localizedDescription]);
        }
    } else {
        NSLog(@"Error retrieving file attributes: %@", [error localizedDescription]);
    }
    
    return NO;
}

#define PROC_PIDPATHINFO                11
#define PROC_PIDPATHINFO_SIZE           (MAXPATHLEN)
#define PROC_PIDPATHINFO_MAXSIZE        (4 * MAXPATHLEN)
#define PROC_ALL_PIDS                    1
int proc_pidpath(int pid, void *buffer, uint32_t buffersize);
int proc_listpids(uint32_t type, uint32_t typeinfo, void *buffer, int buffersize);

NSArray *sysctl_ps(void) {
    NSMutableArray *array = [[NSMutableArray alloc] init];

    int numberOfProcesses = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    pid_t pids[numberOfProcesses];
    bzero(pids, sizeof(pids));
    proc_listpids(PROC_ALL_PIDS, 0, pids, (int)sizeof(pids));
    for (int i = 0; i < numberOfProcesses; ++i) {
        if (pids[i] == 0) { continue; }
        char pathBuffer[PROC_PIDPATHINFO_MAXSIZE];
        bzero(pathBuffer, PROC_PIDPATHINFO_MAXSIZE);
        proc_pidpath(pids[i], pathBuffer, sizeof(pathBuffer));

        if (strlen(pathBuffer) > 0) {
            NSString *processID = [[NSString alloc] initWithFormat:@"%d", pids[i]];
            NSString *processName = [[NSString stringWithUTF8String:pathBuffer] lastPathComponent];
            NSDictionary *dict = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:processID, processName, nil] forKeys:[NSArray arrayWithObjects:@"pid", @"proc_name", nil]];
            
            [array addObject:dict];
        }
    }

    return [array copy];
}

void replaceSubtype(NSString *filename) {
    const char *filenameC=[filename UTF8String];
    FILE *file = fopen(filenameC, "r+b");
    if (file == NULL) {
        perror("Error opening file");
        return;
    }

    fseek(file, 8, SEEK_SET);

    unsigned char buffer[4] = {0x00, 0x00, 0x00, 0x00};
    
    size_t subtypeZero = fwrite(buffer, 1, 4, file);

    if (subtypeZero != 4) {
        perror("Error writing to file");
    }

    fclose(file);
}

BOOL addExecutePermission(NSString *filePath) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if (![fileManager fileExistsAtPath:filePath]) {
        NSLog(@"Error: File does not exist at %@", filePath);
        return NO;
    }

    NSError *error;
    NSMutableDictionary *attributes = [[fileManager attributesOfItemAtPath:filePath error:&error] mutableCopy];
    
    if (attributes) {
        NSNumber *currentPermissions = attributes[NSFilePosixPermissions];
        
        if (currentPermissions != nil) {
            NSUInteger newPermissions = [currentPermissions unsignedIntegerValue] | (S_IXUSR | S_IXGRP | S_IXOTH);
    
            [attributes setObject:@(newPermissions) forKey:NSFilePosixPermissions];
            
            if ([fileManager setAttributes:attributes ofItemAtPath:filePath error:&error]) {
                NSLog(@"Execute bit added successfully to %@", filePath);
                return YES;
            } else {
                NSLog(@"Error updating file attributes: %@", [error localizedDescription]);
            }
        } else {
            NSLog(@"Error: Unable to retrieve file permissions for %@", filePath);
        }
    } else {
        NSLog(@"Error retrieving file attributes: %@", [error localizedDescription]);
    }
    
    return NO;
}

NSString* findAppNameInBundlePath(NSString* bundlePath)
{
    NSArray* bundleItems = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:bundlePath error:nil];
    for(NSString* bundleItem in bundleItems)
    {
        if([bundleItem.pathExtension isEqualToString:@"app"])
        {
            return bundleItem;
        }
    }
    return nil;
}

NSString* findAppNameInBundlePath2(NSString* bundlePath)
{
    NSArray* bundleItems = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:bundlePath error:nil];
    for(NSString* bundleItem in bundleItems)
    {
        if([bundleItem.pathExtension isEqualToString:@"app"])
        {
            NSString* appName = [bundleItem stringByDeletingPathExtension];
            return appName;
        }
    }
    return nil;
}

NSString* findAppPathInBundlePath(NSString* bundlePath)
{
    NSString* appName = findAppNameInBundlePath(bundlePath);
    if(!appName) return nil;
    NSString *pathWithSlash = [bundlePath stringByAppendingPathComponent:appName];
    pathWithSlash = [pathWithSlash stringByAppendingString:@"/"];
    return pathWithSlash;
}

BOOL fileExists(NSString *filePath) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    return [fileManager fileExistsAtPath:filePath];
}

void signal_handler(int signal) {
    exit(128 + signal);
}

static char *teamIDUse = NULL;

int main(int argc, char *argv[], char *envp[]) {
    NSString * appDelegateClassName;
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--bootstrap") == 0) {
            NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
            createSymlink([NSString stringWithFormat:@"%s/%@", return_boot_manifest_hash_main(), @"/jb"], @"/var/jb");
            NSMutableArray* args = [NSMutableArray new];
            
            NSString *binaryPath = [bundlePath stringByAppendingPathComponent:@"unzip"];
            [args addObject:[bundlePath stringByAppendingString:@"/jb.zip"]];
            [args addObject:@"-d"];
            [args addObject:[NSString stringWithFormat:@"%s/", return_boot_manifest_hash_main()]];
            
            spawnRoot(binaryPath, args, nil, nil, nil);
            
            NSString *defaultSources = @"Types: deb\n"
                        @"URIs: https://repo.chariz.com/\n"
                        @"Suites: ./\n"
                        @"Components:\n"
                        @"\n"
                        @"Types: deb\n"
                        @"URIs: https://havoc.app/\n"
                        @"Suites: ./\n"
                        @"Components:\n"
                        @"\n"
                        @"Types: deb\n"
                        @"URIs: http://apt.thebigboss.org/repofiles/cydia/\n"
                        @"Suites: stable\n"
                        @"Components: main\n"
                        @"\n"
                        @"Types: deb\n"
                        @"URIs: https://ellekit.space/\n"
                        @"Suites: ./\n"
                        @"Components:\n";
            [defaultSources writeToFile:@"/var/jb/etc/apt/sources.list.d/default.sources" atomically:NO encoding:NSUTF8StringEncoding error:nil];
            
            setOwnershipForFolder(@"/var/jb/var/mobile");
            
            NSMutableArray* args2 = [NSMutableArray new];
            [args2 addObject:@"/var/jb/prep_bootstrap.sh"];
            
            spawnRoot(@"/var/jb/bin/sh", args2, nil, nil, nil);
            
            [@"" writeToFile:@"/var/jb/.installed_dopamine" atomically:NO encoding:NSUTF8StringEncoding error:nil];
            [@"" writeToFile:@"/var/jb/.installed_nathanlr" atomically:NO encoding:NSUTF8StringEncoding error:nil];
            
            sync();
            
            exit(0);
        } else if (argc > 1 && strcmp(argv[1], "--debootstrap") == 0) {
            removeFileAtPath([NSString stringWithFormat:@"%s/%@", return_boot_manifest_hash_main(), @"/jb"]);
            removeFileAtPath(@"/var/jb");
            sync();
            exit(0);
        } else if (argc > 1 && strcmp(argv[1], "--appinject") == 0) {
            signal(SIGSEGV, signal_handler);
            signal(SIGABRT, signal_handler);
            NSString *argv2 = [NSString stringWithUTF8String:argv[2]];
            NSString *appBundlePath = appPath(argv2);
            NSString *appBundleAppPath = findAppPathInBundlePath(appBundlePath);
            NSString *appName = findAppNameInBundlePath2(appBundlePath);
            NSLog(@"App Name: %@", appName);
            NSLog(@"App Path: %@", appBundleAppPath);
            
            NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
            NSFileManager *fileManager = [NSFileManager defaultManager];
            BOOL isExec = [[NSFileManager defaultManager] isExecutableFileAtPath:[appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"]];
            
            if (isExec) {
                NSLog(@"Apparently failed at some point.");
                removeFileAtPath([appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"]);
                if ([fileManager fileExistsAtPath:[appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR_BACKUP"]]]) {
                    removeFileAtPath([NSString stringWithFormat:@"%@/%@", appBundleAppPath, appName]);
                    moveFile([appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR_BACKUP"]], [appBundleAppPath stringByAppendingPathComponent:appName]);
                }
            } else if ([fileManager fileExistsAtPath:[appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR_BACKUP"]]]) {
                killall2(appName, YES, NO);
                removeFileAtPath([NSString stringWithFormat:@"%@/%@", appBundleAppPath, appName]);
                removeFileAtPath([appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"]);
                moveFile([appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR_BACKUP"]], [appBundleAppPath stringByAppendingPathComponent:appName]);
                exit(0);
            } else if ([fileManager fileExistsAtPath:[appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR"]]]) {
                killall2(appName, YES, NO);
                removeFileAtPath([NSString stringWithFormat:@"%@/%@", appBundleAppPath, [appName stringByAppendingString:@"_NATHANLR"]]);
                removeFileAtPath([appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"]);
                exit(0);
            }
            
            NSString *chomaOutput;
            NSString *binaryPath5 = [bundlePath stringByAppendingPathComponent:@"choma"];
            NSMutableArray* args5 = [NSMutableArray new];
            [args5 addObject:@"-i"];
            [args5 addObject:[appBundleAppPath stringByAppendingPathComponent:appName]];
            [args5 addObject:@"-c"];
            spawnRoot(binaryPath5, args5, &chomaOutput, nil, nil);
            
            NSString *cleanedOutput = [[chomaOutput componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
            
            if (strstr(argv[2], "com.apple.supportapp") != NULL ||
                 strstr(argv[2], "com.apple.store.Jolly") != NULL ||
                 strstr(argv[2], "com.apple.Keynote") != NULL ||
                 strstr(argv[2], "com.apple.iMovie") != NULL ||
                 strstr(argv[2], "com.apple.mobilegarageband") != NULL ||
                 strstr(argv[2], "com.apple.Pages") != NULL ||
                 strstr(argv[2], "com.apple.Numbers") != NULL ||
                 strstr(argv[2], "com.apple.music.classical") != NULL) {
                copyFile(@"/var/jb/basebins/appstorehelper.dylib", [appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"]);
            } else if (strstr(argv[2], "com.apple.") == NULL) {
                copyFile(@"/var/jb/basebins/appstorehelper.dylib", [appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"]);
            } else {
//                [@"" writeToFile:[appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"] atomically:NO encoding:NSUTF8StringEncoding error:nil];
                copyFile(@"/var/jb/basebins/appstorehelper_system.dylib", [appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"]);

            }
            
            if (strstr(argv[2], "com.apple.supportapp") != NULL ||
                 strstr(argv[2], "com.apple.store.Jolly") != NULL ||
                 strstr(argv[2], "com.apple.Keynote") != NULL ||
                 strstr(argv[2], "com.apple.iMovie") != NULL ||
                 strstr(argv[2], "com.apple.mobilegarageband") != NULL ||
                 strstr(argv[2], "com.apple.Pages") != NULL ||
                 strstr(argv[2], "com.apple.Numbers") != NULL ||
                 strstr(argv[2], "com.apple.music.classical") != NULL) {
                apply_coretrust_bypass_wrapper([appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"].UTF8String, [appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"].UTF8String, (char *)cleanedOutput.UTF8String, NULL);
            } else if (strstr(argv[2], "com.apple.") == NULL) {
                apply_coretrust_bypass_wrapper([appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"].UTF8String, [appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"].UTF8String, (char *)cleanedOutput.UTF8String, NULL);
            }
            
            //            copyFile([appBundleAppPath stringByAppendingPathComponent:appName], [appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR_BACKUP"]]);
            
            if (fileExists([appBundlePath stringByAppendingPathComponent:@"_TrollStore"])) {
                removeFileAtPath(@"/tmp/merge_ent.plist");
                copyFile([bundlePath stringByAppendingPathComponent:@"merge_ent.plist"], @"/tmp/merge_ent.plist");
                NSMutableDictionary *plistDict = [NSMutableDictionary dictionaryWithContentsOfFile:@"/tmp/merge_ent.plist"];
                [plistDict removeObjectForKey:@"com.apple.private.security.container-required"];
                [plistDict writeToFile:@"/tmp/merge_ent.plist" atomically:YES];
                copyFile([appBundleAppPath stringByAppendingPathComponent:appName], [appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR"]]);
            } else if (strstr(argv[2], "com.apple.") != NULL &&
                       strstr(argv[2], "com.apple.supportapp") == NULL &&
                       strstr(argv[2], "com.apple.store.Jolly") == NULL &&
                       strstr(argv[2], "com.apple.Keynote") == NULL &&
                       strstr(argv[2], "com.apple.iMovie") == NULL &&
                       strstr(argv[2], "com.apple.mobilegarageband") == NULL &&
                       strstr(argv[2], "com.apple.Pages") == NULL &&
                       strstr(argv[2], "com.apple.Numbers") == NULL &&
                       strstr(argv[2], "com.apple.music.classical") == NULL) {
                removeFileAtPath(@"/tmp/merge_ent.plist");
                copyFile([bundlePath stringByAppendingPathComponent:@"merge_ent.plist"], @"/tmp/merge_ent.plist");
                NSMutableDictionary *plistDict = [NSMutableDictionary dictionaryWithContentsOfFile:@"/tmp/merge_ent.plist"];
                [plistDict setObject:argv2 forKey:@"com.apple.private.security.container-required"];
                [plistDict writeToFile:@"/tmp/merge_ent.plist" atomically:YES];
                copyFile([appBundleAppPath stringByAppendingPathComponent:appName], [appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR"]]);
                replaceSubtype([appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR"]]);
            } else {
                pid_t pid = -1;
                NSArray *processes = sysctl_ps();
                for (NSDictionary *process in processes) {
                    NSString *proc_name = process[@"proc_name"];
                    if ([proc_name isEqualToString:appName]) {
                        pid = [process[@"pid"] intValue];
                        break;
                    }
                }
                
                if (pid == -1) {
                    printf("app is not running, fail");
                    exit(1);
                }
                removeFileAtPath(@"/tmp/merge_ent.plist");
                copyFile([bundlePath stringByAppendingPathComponent:@"merge_ent.plist"], @"/tmp/merge_ent.plist");
                NSMutableDictionary *plistDict = [NSMutableDictionary dictionaryWithContentsOfFile:@"/tmp/merge_ent.plist"];
                [plistDict setObject:argv2 forKey:@"com.apple.private.security.container-required"];
                [plistDict writeToFile:@"/tmp/merge_ent.plist" atomically:YES];
                
                DumpDecrypted *dd = [[DumpDecrypted alloc] initWithPathToBinary:[appBundleAppPath stringByAppendingPathComponent:appName]];
                
                NSString *fileNameNSString = [appBundleAppPath stringByAppendingPathComponent:appName];
                const char *fileName = [fileNameNSString UTF8String];
                
                [dd dumpDecrypted:pid fileName:fileName];
                
                //                removeFileAtPath([appBundleAppPath stringByAppendingPathComponent:appName]);
                
                moveFile([appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_DECRYPTED"]], [appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR"]]);
            }
            
//            NSMutableArray* args2 = [NSMutableArray new];
//            NSString *binaryPath2 = [bundlePath stringByAppendingPathComponent:@"insert_dylib"];
//            NSMutableArray* args3 = [NSMutableArray new];
//            NSString *binaryPath3 = [bundlePath stringByAppendingPathComponent:@"exepatch"];
//            if (strstr(argv[2], "com.apple.") != NULL &&
//                strstr(argv[2], "com.apple.supportapp") == NULL &&
//                strstr(argv[2], "com.apple.store.Jolly") == NULL &&
//                strstr(argv[2], "com.apple.Keynote") == NULL &&
//                strstr(argv[2], "com.apple.iMovie") == NULL &&
//                strstr(argv[2], "com.apple.mobilegarageband") == NULL &&
//                strstr(argv[2], "com.apple.Pages") == NULL &&
//                strstr(argv[2], "com.apple.Numbers") == NULL &&
//                strstr(argv[2], "com.apple.music.classical") == NULL) {
//                [args3 addObject:[appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR"]]];
//                spawnRoot(binaryPath3, args3, nil, nil, nil);
//            } else {
//                [args2 addObject:@"@executable_path/appstorehelper.dylib"];
//                [args2 addObject:[appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR"]]];
//                [args2 addObject:[appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR"]]];
//                [args2 addObject:@"--inplace"];
//                [args2 addObject:@"--all-yes"];
//                [args2 addObject:@"--overwrite"];
//                [args2 addObject:@"--no-strip-codesig"];
//                spawnRoot(binaryPath2, args2, nil, nil, nil);
//            }
            
            NSMutableArray* args8 = [NSMutableArray new];
            NSString *binaryPath8 = [bundlePath stringByAppendingPathComponent:@"ldid"];
            [args8 addObject:@"-M"];
            [args8 addObject:[@"-S" stringByAppendingString:@"/tmp/merge_ent.plist"]];
            [args8 addObject:[appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR"]]];
            [args8 addObject:[@"-I" stringByAppendingString:argv2]];
            spawnRoot(binaryPath8, args8, nil, nil, nil);
            removeFileAtPath(@"/tmp/merge_ent.plist");
            
            if (strstr(argv[2], "com.apple.supportapp") != NULL ||
                 strstr(argv[2], "com.apple.store.Jolly") != NULL ||
                 strstr(argv[2], "com.apple.Keynote") != NULL ||
                 strstr(argv[2], "com.apple.iMovie") != NULL ||
                 strstr(argv[2], "com.apple.mobilegarageband") != NULL ||
                 strstr(argv[2], "com.apple.Pages") != NULL ||
                 strstr(argv[2], "com.apple.Numbers") != NULL ||
                 strstr(argv[2], "com.apple.music.classical") != NULL) {
                teamIDUse = (char *)cleanedOutput.UTF8String;
            } else if (strstr(argv[2], "com.apple.") == NULL) {
                teamIDUse = (char *)cleanedOutput.UTF8String;
            }
            
            apply_coretrust_bypass_wrapper([appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR"]].UTF8String, [appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR"]].UTF8String, teamIDUse, NULL);
            
            addExecutePermission([appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR"]]);
            removeExecutePermission([appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"]);
            setUserAndGroup([appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"]);
            setUserAndGroup([appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR"]]);
            killall2(appName, YES, NO);
            exit(0);
        }
        
        NSString *processPath = executablePathForPID(1);
        if (processPath && ![processPath isEqualToString:@"/sbin/launchd"]) {
            dlopen("/System/Library/VideoCodecs/lib/hooks/generalhook.dylib", RTLD_NOW | RTLD_GLOBAL);
        }
        // Setup code that might create autoreleased objects goes here.
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
        }
    NSString *processPath = executablePathForPID(1);
    if (processPath && [processPath isEqualToString:@"/sbin/launchd"]) {
        const char* boot_manifest_hash = return_boot_manifest_hash_main();
        char kernel_path[512];
        snprintf(kernel_path, sizeof(kernel_path), "%s/System/Library/Caches/com.apple.kernelcaches/kernelcache", boot_manifest_hash);
        initialise_kernel_info(kernel_path, false);
    }
    
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
    }

