//
//  util.h
//  usprebooter
//
//  Created by LL on 29/11/23.
//

#ifndef util_h
#define util_h
#import <Foundation/Foundation.h>
void respring(void);
void crashSpringBoard(void);
int spawnRoot(NSString* path, NSArray* args, NSString** stdOut, NSString** stdErr, int* exitCode);
void killall2(NSString* processName, BOOL softly, BOOL crash);
char* return_boot_manifest_hash_main(void);

#endif /* util_h */
