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
#include "archive.h"
#include "archive_entry.h"
#import "zstd.h"
#include "patchfinder/patchfind.h"

#define BUFFER_SIZE 8192
NSString *const bootstrapErrorDomain = @"BootstrapErrorDomain";
typedef NS_ENUM(NSInteger, JBErrorCode) {
    BootstrapErrorCodeFailedToGetURL            = -1,
    BootstrapErrorCodeFailedToDownload          = -2,
    BootstrapErrorCodeFailedDecompressing       = -3,
    BootstrapErrorCodeFailedExtracting          = -4,
    BootstrapErrorCodeFailedRemount             = -5,
    BootstrapErrorCodeFailedFinalising          = -6,
    BootstrapErrorCodeFailedReplacing           = -7,
};

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

static int
copy_data(struct archive *ar, struct archive *aw)
{
    int r;
    const void *buff;
    size_t size;
    la_int64_t offset;

    for (;;) {
        r = archive_read_data_block(ar, &buff, &size, &offset);
        if (r == ARCHIVE_EOF)
            return (ARCHIVE_OK);
        if (r < ARCHIVE_OK)
            return (r);
        r = archive_write_data_block(aw, buff, size, offset);
        if (r < ARCHIVE_OK) {
            fprintf(stderr, "%s\n", archive_error_string(aw));
            return (r);
        }
    }
}


int libarchive_unarchive(const char *fileToExtract, const char *extractionPath);

NSError* decompressZstd(NSString *zstdPath, NSString *tarPath)
{
    // Open the input file for reading
    FILE *input_file = fopen(zstdPath.fileSystemRepresentation, "rb");
    if (input_file == NULL) {
        return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedDecompressing userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Failed to open input file %@: %s", zstdPath, strerror(errno)]}];
    }

    // Open the output file for writing
    FILE *output_file = fopen(tarPath.fileSystemRepresentation, "wb");
    if (output_file == NULL) {
        fclose(input_file);
        return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedDecompressing userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Failed to open output file %@: %s", tarPath, strerror(errno)]}];
    }

    // Create a ZSTD decompression context
    ZSTD_DCtx *dctx = ZSTD_createDCtx();
    if (dctx == NULL) {
        fclose(input_file);
        fclose(output_file);
        return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedDecompressing userInfo:@{NSLocalizedDescriptionKey : @"Failed to create ZSTD decompression context"}];
    }

    // Create a buffer for reading input data
    uint8_t *input_buffer = (uint8_t *) malloc(BUFFER_SIZE);
    if (input_buffer == NULL) {
        ZSTD_freeDCtx(dctx);
        fclose(input_file);
        fclose(output_file);
        return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedDecompressing userInfo:@{NSLocalizedDescriptionKey : @"Failed to allocate input buffer"}];
    }

    // Create a buffer for writing output data
    uint8_t *output_buffer = (uint8_t *) malloc(BUFFER_SIZE);
    if (output_buffer == NULL) {
        free(input_buffer);
        ZSTD_freeDCtx(dctx);
        fclose(input_file);
        fclose(output_file);
        return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedDecompressing userInfo:@{NSLocalizedDescriptionKey : @"Failed to allocate output buffer"}];
    }

    // Create a ZSTD decompression stream
    ZSTD_inBuffer in = {0};
    ZSTD_outBuffer out = {0};
    ZSTD_DStream *dstream = ZSTD_createDStream();
    if (dstream == NULL) {
        free(output_buffer);
        free(input_buffer);
        ZSTD_freeDCtx(dctx);
        fclose(input_file);
        fclose(output_file);
        return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedDecompressing userInfo:@{NSLocalizedDescriptionKey : @"Failed to create ZSTD decompression stream"}];
    }

    // Initialize the ZSTD decompression stream
    size_t ret = ZSTD_initDStream(dstream);
    if (ZSTD_isError(ret)) {
        ZSTD_freeDStream(dstream);
        free(output_buffer);
        free(input_buffer);
        ZSTD_freeDCtx(dctx);
        fclose(input_file);
        fclose(output_file);
        return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedDecompressing userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Failed to initialize ZSTD decompression stream: %s", ZSTD_getErrorName(ret)]}];
    }
    
    // Read and decompress the input file
    size_t total_bytes_read = 0;
    size_t total_bytes_written = 0;
    size_t bytes_read;
    size_t bytes_written;
    while (1) {
        // Read input data into the input buffer
        bytes_read = fread(input_buffer, 1, BUFFER_SIZE, input_file);
        if (bytes_read == 0) {
            if (feof(input_file)) {
                // End of input file reached, break out of loop
                break;
            } else {
                ZSTD_freeDStream(dstream);
                free(output_buffer);
                free(input_buffer);
                ZSTD_freeDCtx(dctx);
                fclose(input_file);
                fclose(output_file);
                return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedDecompressing userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Failed to read input file: %s", strerror(errno)]}];
            }
        }

        in.src = input_buffer;
        in.size = bytes_read;
        in.pos = 0;

        while (in.pos < in.size) {
            // Initialize the output buffer
            out.dst = output_buffer;
            out.size = BUFFER_SIZE;
            out.pos = 0;

            // Decompress the input data
            ret = ZSTD_decompressStream(dstream, &out, &in);
            if (ZSTD_isError(ret)) {
                ZSTD_freeDStream(dstream);
                free(output_buffer);
                free(input_buffer);
                ZSTD_freeDCtx(dctx);
                fclose(input_file);
                fclose(output_file);
                return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedDecompressing userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Failed to decompress input data: %s", ZSTD_getErrorName(ret)]}];
            }

            // Write the decompressed data to the output file
            bytes_written = fwrite(output_buffer, 1, out.pos, output_file);
            if (bytes_written != out.pos) {
                ZSTD_freeDStream(dstream);
                free(output_buffer);
                free(input_buffer);
                ZSTD_freeDCtx(dctx);
                fclose(input_file);
                fclose(output_file);
                return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedDecompressing userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Failed to write output file: %s", strerror(errno)]}];
            }

            total_bytes_written += bytes_written;
        }

        total_bytes_read += bytes_read;
    }

    // Clean up resources
    ZSTD_freeDStream(dstream);
    free(output_buffer);
    free(input_buffer);
    ZSTD_freeDCtx(dctx);
    fclose(input_file);
    fclose(output_file);

    return nil;
}

NSError* extractTar(NSString * tarPath, NSString *destinationPath)
{
    int r = libarchive_unarchive(tarPath.fileSystemRepresentation, destinationPath.fileSystemRepresentation);
    if (r != 0) {
        return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedExtracting userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"libarchive returned %d", r]}];
    }
    return nil;
}

void extractBootstrap(NSString *path)
{
    NSString *bootstrapTar = [@"/var/tmp" stringByAppendingPathComponent:@"bootstrap.tar"];
    NSError *decompressionError = decompressZstd(path, bootstrapTar);
    if (decompressionError) {
        return;
    }
    
    decompressionError = extractTar(bootstrapTar, [NSString stringWithFormat:@"%s/", return_boot_manifest_hash_main()]);
    if (decompressionError) {
        return;
    }
    removeFileAtPath(@"/var/tmp/bootstrap.tar");
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
            extractBootstrap([bundlePath stringByAppendingString:@"/bootstrap-nathanlr-iphoneos-arm64.tar.zst"]);
            createSymlink([NSString stringWithFormat:@"%s/%@", return_boot_manifest_hash_main(), @"/jb"], @"/var/jb");
            
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
            
            NSString *nathanlrSource = @"Types: deb\n"
                        @"URIs: https://nathan4s.lol/nathanlr/\n"
                        @"Suites: ./\n"
                        @"Components:\n";
            [nathanlrSource writeToFile:@"/var/jb/etc/apt/sources.list.d/nathanlr.sources" atomically:NO encoding:NSUTF8StringEncoding error:nil];
            
            spawnRoot(@"/var/jb/usr/bin/dpkg", @[@"-i", [bundlePath stringByAppendingString:@"/sysfiles.deb"]], nil, nil, nil);
            removeFileAtPath(@"/var/jb/Library/dpkg/info/shshd.prerm");
            spawnRoot(@"/var/jb/usr/bin/dpkg", @[@"-r", @"shshd"], NULL, NULL, nil);
            spawnRoot(@"/var/jb/usr/bin/dpkg", @[@"-r", @"libkrw0", @"libdimentio0"], NULL, NULL, nil);
            spawnRoot(@"/var/jb/usr/bin/dpkg", @[@"-i", [bundlePath stringByAppendingString:@"/ellekit.deb"]], nil, nil, nil);
            spawnRoot(@"/var/jb/usr/bin/dpkg", @[@"-i", [bundlePath stringByAppendingString:@"/org.coolstar.sileo_2.5_iphoneos-arm64.deb"]], nil, nil, nil);
            spawnRoot(@"/var/jb/bin/sh", @[@"/var/jb/prep_bootstrap.sh"], nil, nil, nil);
            
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
            if (argv[3]) {
                NSLog(@"Reinjecting");
                NSString *chomaOutput2;
                NSString *binaryPath52 = [bundlePath stringByAppendingPathComponent:@"choma"];
                NSMutableArray* args52 = [NSMutableArray new];
                [args52 addObject:@"-i"];
                [args52 addObject:[appBundleAppPath stringByAppendingPathComponent:appName]];
                [args52 addObject:@"-c"];
                spawnRoot(binaryPath52, args52, &chomaOutput2, nil, nil);
                NSString *cleanedOutput2 = [[chomaOutput2 componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
                removeFileAtPath([appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"]);
                copyFile(@"/var/jb/basebins/appstorehelper.dylib", [appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"]);
                apply_coretrust_bypass_wrapper([appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"].UTF8String, [appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"].UTF8String, (char *)cleanedOutput2.UTF8String, NULL);
                removeExecutePermission([appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"]);
                setUserAndGroup([appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"]);
                killall2(appName, YES, NO);
                exit(0);
            } else if (isExec) {
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

