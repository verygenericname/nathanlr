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
#import <IOKit/IOKitLib.h>
//#include <sys/proc_info.h>
// #include <libproc.h>
#include "archive.h"
#include "archive_entry.h"
#import "zstd.h"
#include "Exploits/TaskPortHaxxApp/TaskPortHaxxApp/Header.h"
#include "Exploits/TaskPortHaxxApp/TaskPortHaxxApp/unarchive.h"
#include "choma/CSBlob.h"
#include "choma/FileStream.h"
#include "choma/CodeDirectory.h"

#define kCFPreferencesNoContainer CFSTR("kCFPreferencesNoContainer")
void _CFPreferencesSetValueWithContainer(CFStringRef key, CFPropertyListRef value, CFStringRef applicationID, CFStringRef userName, CFStringRef hostName, CFStringRef containerPath);
Boolean _CFPreferencesSynchronizeWithContainer(CFStringRef applicationID, CFStringRef userName, CFStringRef hostName, CFStringRef containerPath);
CFArrayRef _CFPreferencesCopyKeyListWithContainer(CFStringRef applicationID, CFStringRef userName, CFStringRef hostName, CFStringRef containerPath);
CFDictionaryRef _CFPreferencesCopyMultipleWithContainer(CFArrayRef keysToFetch, CFStringRef applicationID, CFStringRef userName, CFStringRef hostName, CFStringRef containerPath);

bool macho_is_encrypted(MachO *macho);
MachO *macho_init_for_reading(const char *filePath);
void initLoad(void);

NSError *showNonDefaultSystemApps(void)
{
    _CFPreferencesSetValueWithContainer(CFSTR("SBShowNonDefaultSystemApps"), kCFBooleanTrue, CFSTR("com.apple.springboard"), CFSTR("mobile"), kCFPreferencesAnyHost, kCFPreferencesNoContainer);
    _CFPreferencesSynchronizeWithContainer(CFSTR("com.apple.springboard"), CFSTR("mobile"), kCFPreferencesAnyHost, kCFPreferencesNoContainer);
    return nil;
}

int ensure_755(const char *path) {
    struct stat s;

    if (stat(path, &s) != 0) {
        perror("stat");
        return -1;
    }

    mode_t perms = s.st_mode & 0777;

    if (perms != 0755) {
        if (chmod(path, 0755) != 0) {
            perror("chmod");
            return -1;
        }
    }

    return 0;
}

char *get_team_id(char *path) {
    int count = 0;
    uint32_t offset = 0;
    char *teamid = NULL;

    MachO *macho = macho_init_for_reading(path);

    CS_SuperBlob *superblob = macho_read_code_signature(macho);
    CS_DecodedSuperBlob *decodedSuperBlob = csd_superblob_decode(superblob);
    CS_DecodedBlob *currentBlob = decodedSuperBlob->firstBlob;
    
    while (currentBlob) {
        uint32_t blobType = currentBlob->type;
        
        if (blobType == CSSLOT_CODEDIRECTORY || blobType == CSSLOT_ALTERNATE_CODEDIRECTORIES) {
            CS_CodeDirectory codeDir;
            csd_blob_read(currentBlob, 0, sizeof(codeDir), &codeDir);
            CODE_DIRECTORY_APPLY_BYTE_ORDER(&codeDir, BIG_TO_HOST_APPLIER);
            teamid = csd_code_directory_copy_team_id(currentBlob, NULL);
        }

        currentBlob = currentBlob->next;
    }
    
    

    free(superblob);
    return teamid;
}

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

int child_execve(char *exceptionPortName, char *path) {
    mach_port_t exception_port = MACH_PORT_NULL;
    mach_port_t fake_bootstrap_port = MACH_PORT_NULL;
    bootstrap_look_up(bootstrap_port, exceptionPortName, &exception_port);
    assert(exception_port != MACH_PORT_NULL);
    bootstrap_look_up(bootstrap_port, "com.kdt.taskporthaxx.fake_bootstrap_port", &fake_bootstrap_port);
    assert(fake_bootstrap_port != MACH_PORT_NULL);
    
    task_set_exception_ports(mach_task_self(),
        EXC_MASK_ALL | EXC_MASK_CRASH,
        exception_port,
        EXCEPTION_STATE_IDENTITY | MACH_EXCEPTION_CODES,
        ARM_THREAD_STATE64);
    mach_port_t bootstrapPort = bootstrap_port;
    task_set_bootstrap_port(mach_task_self(), fake_bootstrap_port);
    
    posix_spawnattr_t attr;
    if(posix_spawnattr_init(&attr) != 0) {
        perror("posix_spawnattr_init");
        return 1;
    }
    
    if(posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETEXEC) != 0) {
        perror("posix_spawnattr_set_flags");
        return 1;
    }
    
    posix_spawnattr_set_registered_ports_np(&attr, (mach_port_t[]){0, bootstrapPort, fake_bootstrap_port}, 3);
    posix_spawnattr_setexceptionports_np(&attr,
        EXC_MASK_ALL | EXC_MASK_CRASH,
        exception_port, EXCEPTION_STATE_IDENTITY | MACH_EXCEPTION_CODES, ARM_THREAD_STATE64);
    char *argv2[] = { path, NULL };
    posix_spawn(NULL, argv2[0], NULL, &attr, argv2, environ);
    perror("posix_spawn");
    return 1;
}

int load_trust_cache(NSString *tcPath) {
    NSData *tcData = [NSData dataWithContentsOfFile:tcPath];
    if (!tcData) {
        printf("Trust cache file not found: %s\n", tcPath.fileSystemRepresentation);
        return 1;
    }
    CFDictionaryRef match = IOServiceMatching("AppleMobileFileIntegrity");
    io_service_t svc = IOServiceGetMatchingService(0, match);
    io_connect_t conn;
    IOServiceOpen(svc, mach_task_self_, 0, &conn);
    kern_return_t kr = IOConnectCallMethod(conn, 2, NULL, 0, tcData.bytes, tcData.length, NULL, NULL, NULL, NULL);
    if (kr != KERN_SUCCESS) {
        printf("IOConnectCallMethod failed: %s\n", mach_error_string(kr));
        return 1;
    }
    printf("Loaded trust cache from %s\n", tcPath.fileSystemRepresentation);
    IOServiceClose(conn);
    IOObjectRelease(svc);
    return 0;
}

int child_stage1_prepare(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *outDir = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject.path;
    NSString *zipPath = [outDir stringByAppendingPathComponent:@"UpdateBrainService.zip"];
    NSString *assetDir = [outDir stringByAppendingPathComponent:@"AssetData"];
    
    if ([fm fileExistsAtPath:zipPath] || ![fm fileExistsAtPath:assetDir]) {
        printf("Downloading UpdateBrainService\n");
        NSURL *url = [NSURL URLWithString:@"https://updates.cdn-apple.com/2022FallFCS/patches/012-73541/F0A2BDFD-317B-4557-BD18-269079BDB196/com_apple_MobileAsset_MobileSoftwareUpdate_UpdateBrain/f9886a753f7d0b2fc3378a28ab6975769f6b1c26.zip"];
        NSData *urlData = [NSData dataWithContentsOfURL:url];
        if (!urlData) {
            printf("Failed to download UpdateBrainService\n");
            return 1;
        }
        
        // Save and extract UpdateBrainService
        [urlData writeToFile:zipPath atomically:YES];
        printf("Downloaded UpdateBrainService to %s\n", zipPath.fileSystemRepresentation);
        printf("Extracting UpdateBrainService\n");
        extract(zipPath, outDir, NULL);
        [NSFileManager.defaultManager removeItemAtPath:zipPath error:nil];
    }
    
    // Copy xpc service
    NSString *execDir = @"/var/db/com.apple.xpc.roleaccountd.staging/exec";
    [fm createDirectoryAtPath:execDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *xpcName = @"com.apple.MobileSoftwareUpdate.UpdateBrainService.xpc";
    NSString *outXPCPath = [execDir stringByAppendingPathComponent:xpcName];
    if (![fm fileExistsAtPath:outXPCPath]) {
        NSError *error = nil;
        [fm copyItemAtPath:[assetDir stringByAppendingPathComponent:xpcName] toPath:outXPCPath error:&error];
        if (error) {
            NSLog(@"Failed to copy UpdateBrainService.xpc: %@", error);
            return 1;
        }
    }
    
    printf("Stage 1 setup complete\n");
    return 0;
}

kern_return_t _launch_job_routine(int selector, xpc_object_t request, id *result);
xpc_object_t _CFXPCCreateXPCObjectFromCFObject(id object);

int apply_coretrust_bypass_wrapper(const char *inputPath, const char *outputPath, char *teamID, char *identifier, char *appStoreBinary);
int proc_pidpath(int pid, void * buffer, uint32_t  buffersize);
#define PROC_PIDPATHINFO_MAXSIZE        (4*MAXPATHLEN)
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


int libarchive_unarchive(const char *fileToExtract, const char *extractionPath)
{
    struct archive *a;
    struct archive *ext;
    struct archive_entry *entry;
    int flags;
    int r;

    /* Select which attributes we want to restore. */
    flags = ARCHIVE_EXTRACT_TIME;
    flags |= ARCHIVE_EXTRACT_PERM;
    flags |= ARCHIVE_EXTRACT_ACL;
    flags |= ARCHIVE_EXTRACT_FFLAGS;
    flags |= ARCHIVE_EXTRACT_OWNER;

    a = archive_read_new();
    archive_read_support_format_all(a);
    archive_read_support_filter_all(a);
    ext = archive_write_disk_new();
    archive_write_disk_set_options(ext, flags);
    archive_write_disk_set_standard_lookup(ext);
    if ((r = archive_read_open_filename(a, fileToExtract, 10240)))
            return 1;
    for (;;) {
            r = archive_read_next_header(a, &entry);
            if (r == ARCHIVE_EOF)
                    break;
            if (r < ARCHIVE_OK)
                    fprintf(stderr, "%s\n", archive_error_string(a));
            if (r < ARCHIVE_WARN)
                    return 1;

            const char *currentFile = archive_entry_pathname(entry);
            char outputPath[PATH_MAX];
            strlcpy(outputPath, extractionPath, PATH_MAX);
            strlcat(outputPath, "/", PATH_MAX);
            strlcat(outputPath, currentFile, PATH_MAX);

            archive_entry_set_pathname(entry, outputPath);
            
            r = archive_write_header(ext, entry);
            if (r < ARCHIVE_OK)
                    fprintf(stderr, "%s\n", archive_error_string(ext));
            else if (archive_entry_size(entry) > 0) {
                    r = copy_data(a, ext);
                    if (r < ARCHIVE_OK)
                            fprintf(stderr, "%s\n", archive_error_string(ext));
                    if (r < ARCHIVE_WARN)
                            return 1;
            }
            r = archive_write_finish_entry(ext);
            if (r < ARCHIVE_OK)
                    fprintf(stderr, "%s\n", archive_error_string(ext));
            if (r < ARCHIVE_WARN)
                    return 1;
    }
    archive_read_close(a);
    archive_read_free(a);
    archive_write_close(ext);
    archive_write_free(ext);
    
    return 0;
}

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
            lchown("/var/jb", 0, 0);
            
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
            //            spawnRoot(@"/var/jb/usr/bin/dpkg", @[@"-i", [bundlePath stringByAppendingString:@"/ellekit.deb"]], nil, nil, nil);
            spawnRoot(@"/var/jb/usr/bin/dpkg", @[@"-i", [bundlePath stringByAppendingString:@"/org.coolstar.sileo_2.5.1_iphoneos-arm64.deb"]], nil, nil, nil);
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
        } else if (argc > 1 && strcmp(argv[1], "--hideJB") == 0) {
            if (fileExists(@"/var/jb/.procursus_strapped")) {
                char *boot_hash = return_boot_manifest_hash_main();
                char jbAppPath[PATH_MAX];
                snprintf(jbAppPath, sizeof(jbAppPath), "%s/jb/Applications", boot_hash);
                char uicachePath[PATH_MAX];
                snprintf(uicachePath, sizeof(uicachePath), "%s/jb/usr/bin/uicache", boot_hash);
                
                NSArray *jailbreakApps = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[NSString stringWithUTF8String:jbAppPath] error:nil];
                if (jailbreakApps.count) {
                    for (NSString *jailbreakApp in jailbreakApps) {
                        NSString *jailbreakAppPath = [[NSString stringWithUTF8String:jbAppPath] stringByAppendingPathComponent:jailbreakApp];
                        spawnRoot([NSString stringWithUTF8String:uicachePath], @[@"-u", jailbreakAppPath], nil, nil, nil);
                    }
                }
                [[NSFileManager defaultManager] removeItemAtPath:@"/var/jb" error:nil];
            } else {
                [[NSFileManager defaultManager] removeItemAtPath:@"/var/jb" error:nil];
                
                createSymlink([NSString stringWithFormat:@"%s/%@", return_boot_manifest_hash_main(), @"/jb"], @"/var/jb");
                lchown("/var/jb", 0, 0);
                
                spawnRoot(@"/var/jb/usr/bin/uicache", @[@"-a"], nil, nil, nil);
            }
            
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
                char *cleanedOutput2 = get_team_id((char *)[appBundleAppPath stringByAppendingPathComponent:appName].UTF8String);
                removeFileAtPath([appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"]);
                copyFile(@"/var/jb/basebins/appstorehelper.dylib", [appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"]);
                apply_coretrust_bypass_wrapper([appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"].UTF8String, [appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"].UTF8String, cleanedOutput2, argv[2], NULL);
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
            
            char *cleanedOutput = get_team_id((char *)[appBundleAppPath stringByAppendingPathComponent:appName].UTF8String);
            
            removeFileAtPath([appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"]);
            removeFileAtPath([appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR"]]);
            if (cleanedOutput && strlen(cleanedOutput) > 0) {
                copyFile(@"/var/jb/basebins/appstorehelper.dylib", [appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"]);
            } else {
                cleanedOutput = NULL;
                copyFile(@"/var/jb/basebins/appstorehelper_system.dylib", [appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"]);
            }
            
            apply_coretrust_bypass_wrapper([appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"].UTF8String, [appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"].UTF8String, cleanedOutput, argv[2], NULL);
            
            //            copyFile([appBundleAppPath stringByAppendingPathComponent:appName], [appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR_BACKUP"]]);
            
            copyFile([appBundleAppPath stringByAppendingPathComponent:appName], [appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR"]]);
            
            MachO *theMacho = macho_init_for_reading([appBundleAppPath stringByAppendingPathComponent:appName].UTF8String);
            bool isEncrypted = macho_is_encrypted(theMacho);
            macho_free(theMacho);
            
            NSMutableArray* args8 = [NSMutableArray new];
            NSString *binaryPath8 = @"/var/jb/basebins/ldid_dpkg_autosign";
            [args8 addObject:@"-M"];
            if (cleanedOutput == NULL) {
                removeFileAtPath(@"/tmp/merge_ent.plist");
                NSMutableDictionary *plistDict = [NSMutableDictionary dictionaryWithContentsOfFile:[bundlePath stringByAppendingPathComponent:@"merge_ent.plist"]];
                [plistDict setObject:argv2 forKey:@"com.apple.private.security.container-required"];
                [plistDict writeToFile:@"/tmp/merge_ent.plist" atomically:YES];
                [args8 addObject:[@"-S" stringByAppendingString:@"/tmp/merge_ent.plist"]];
            } else {
                [args8 addObject:[@"-S" stringByAppendingString:[bundlePath stringByAppendingPathComponent:@"merge_ent.plist"]]];
            }
            [args8 addObject:[appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR"]]];
            [args8 addObject:[@"-I" stringByAppendingString:argv2]];
            
            spawnRoot(binaryPath8, args8, nil, nil, nil);
            removeFileAtPath(@"/tmp/merge_ent.plist");
            
            if (isEncrypted) {
                apply_coretrust_bypass_wrapper([appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR"]].UTF8String, [appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR"]].UTF8String, cleanedOutput, argv[2], (char *)[appBundleAppPath stringByAppendingPathComponent:appName].UTF8String);
                FILE *isEncrypted = fopen([appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR_ISENCRYPTED"]].UTF8String, "w");
                fclose(isEncrypted);
                setUserAndGroup([appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR_ISENCRYPTED"]]);
            } else {
                apply_coretrust_bypass_wrapper([appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR"]].UTF8String, [appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR"]].UTF8String, cleanedOutput, argv[2], NULL);
            }
            
            addExecutePermission([appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR"]]);
            removeExecutePermission([appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"]);
            setUserAndGroup([appBundleAppPath stringByAppendingString:@"/appstorehelper.dylib"]);
            setUserAndGroup([appBundleAppPath stringByAppendingPathComponent:[appName stringByAppendingString:@"_NATHANLR"]]);
            killall2(appName, YES, NO);
            exit(0);
        }
        
        
#if !DTSECURITY_WAIT_FOR_DEBUGGER
        char *startSuspended = getenv("HAXX_START_SUSPENDED");
        if (startSuspended && atoi(startSuspended)) {
            usleep(100000); // FIXME: how to sleep until ptrace attach?
        }
#endif
        
        if(argc >= 2) {
            if (strcmp(argv[1], "dtsecurity") == 0) {
                char *boot_hash = return_boot_manifest_hash_main();
                if (access("/var/jb/.procursus_strapped", F_OK) != 0) {
                    char jbPath[PATH_MAX];
                    snprintf(jbPath, sizeof(jbPath), "%s/jb", boot_hash);
                    symlink(jbPath, "/var/jb");
                    lchown("/var/jb", 0, 0);
                }
                symlink("/var/jb/System/Library/SysBins/faked", "/var/jb/lunch");
                NSString *execDir = @"/var/db/com.apple.xpc.roleaccountd.staging/exec";
                [NSFileManager.defaultManager createDirectoryAtPath:execDir withIntermediateDirectories:YES attributes:nil error:nil];
                NSString *outDir = @"/var/db/com.apple.xpc.roleaccountd.staging/exec/TaskPortHaxx.xpc";
                if (![[NSFileManager defaultManager] fileExistsAtPath:outDir]) {
                    NSError *error = nil;
                    [NSFileManager.defaultManager copyItemAtPath:@"/System/Library/PrivateFrameworks/DVTInstrumentsFoundation.framework/XPCServices/com.apple.dt.instruments.dtsecurity.xpc" toPath:outDir error:&error];
                    if (error) {
                        NSLog(@"Failed to copy dtsecurity.xpc: %@", error);
                        return 1;
                    }
                }
                char *portName = getenv("HAXX_EXCEPTION_PORT_NAME");
                char *path = "/var/db/com.apple.xpc.roleaccountd.staging/exec/TaskPortHaxx.xpc/com.apple.dt.instruments.dtsecurity";
                return child_execve(portName, path);
            } else if (strcmp(argv[1], "updatebrain") == 0) {
                char *portName = getenv("HAXX_EXCEPTION_PORT_NAME");
                char *path = "/var/db/com.apple.xpc.roleaccountd.staging/exec/com.apple.MobileSoftwareUpdate.UpdateBrainService.xpc/com.apple.MobileSoftwareUpdate.UpdateBrainService";
                return child_execve(portName, path);
            } else if (strcmp(argv[1], "updatebrain-prepare") == 0) {
                return child_stage1_prepare();
            }
        }
        
        
        NSString *processPath = executablePathForPID(1);
        if (processPath && [processPath isEqualToString:@"/sbin/launchd"]) {
            //            dlopen("/System/Library/VideoCodecs/lib/hooks/generalhook.dylib", RTLD_NOW | RTLD_GLOBAL);
            initLoad();
        }
        // Setup code that might create autoreleased objects goes here.
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
    }
    //    if (__builtin_available(iOS 17.0, *)) {
    //        //
    //    } else {
    //        NSString *processPath = executablePathForPID(1);
    //        if (processPath && [processPath isEqualToString:@"/sbin/launchd"]) {
    //            const char* boot_manifest_hash = return_boot_manifest_hash_main();
    //            char kernel_path[512];
    //            snprintf(kernel_path, sizeof(kernel_path), "%s/System/Library/Caches/com.apple.kernelcaches/kernelcache", boot_manifest_hash);
    //            initialise_kernel_info(kernel_path, false);
    //        }
    //    }
    
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}

