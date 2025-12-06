//
//  ProcessContext.h
//  TaskPortHaxxApp
//
//  Created by Duy Tran on 7/11/25.
//

@import Foundation;
#import "Header.h"
#define RemoteArbCall(instance, _pc, ...) [instance arbCall:#_pc pc:(uint64_t)(_pc) args:(uint64_t[]){__VA_ARGS__} argCount:sizeof((uint64_t[]){__VA_ARGS__})/sizeof(uint64_t)]

@interface ProcessContext : NSObject
@property(nonatomic, strong) NSString *exceptionPortName;
@property(nonatomic, assign) pid_t pid;
@property(nonatomic, assign) mach_port_t taskPort;
@property(nonatomic, assign) mach_port_t exceptionPort;
@property(nonatomic, strong) dispatch_semaphore_t inputReadySemaphore;
@property(nonatomic, strong) dispatch_semaphore_t outputReadySemaphore;
@property(nonatomic, strong) dispatch_semaphore_t hitExcHandlerSemaphore;
@property(nonatomic, assign) arm_thread_state64_internal *newState;
@property(nonatomic, assign) NSUInteger numExceptionsHandled;
@property(nonatomic, assign) uintptr_t expectedLR;
@property(nonatomic, assign) uintptr_t lastPC;

- (instancetype)initWithExceptionPortName:(NSString *)portName;
- (void)spawnProcess:(NSString *)name suspended:(BOOL)suspended;
- (uint32_t)read32:(uintptr_t)address;
- (uint64_t)read64:(uintptr_t)address;
- (void)write32:(uintptr_t)address value:(uint32_t)value;
- (void)write64:(uintptr_t)address value:(uint64_t)value;
- (void)writeBytes:(uintptr_t)address data:(const void *)data length:(size_t)length;
- (uint64_t)writeString:(uintptr_t)address string:(const char *)string;
- (uint64_t)taskRead64:(mach_port_t)task addr:(uint64_t)addr map:(uint64_t)map;
- (void)taskHexDump:(uint64_t)addr size:(size_t)size task:(mach_port_t)task map:(uint64_t)map;
- (uint64_t)arbCall:(char *)name pc:(uintptr_t)pc args:(uint64_t *)args argCount:(NSUInteger)argCount;
- (void)setLr:(uint64_t)newLR;
- (void)resume;
- (void)terminate;

- (kern_return_t)catch_mach_exception_raise_state_identity:(mach_port_t)thread task:(mach_port_t)task
exception:(exception_type_t)exception code:(mach_exception_data_t)code
codeCnt:(mach_msg_type_number_t)codeCnt flavor:(int *)flavor
old_state:(const arm_thread_state64_internal *)old_state old_stateCnt:(mach_msg_type_number_t)old_stateCnt
new_state:(arm_thread_state64_internal *)new_state new_stateCnt:(mach_msg_type_number_t *)new_stateCnt;
@end
