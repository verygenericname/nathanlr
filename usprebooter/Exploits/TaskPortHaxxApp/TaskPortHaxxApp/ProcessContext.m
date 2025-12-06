//
//  ProcessContext.m
//  TaskPortHaxxApp
//
//  Created by Duy Tran on 7/11/25.
//

#import "ProcessContext.h"
#import "Header.h"
#include "mach_excServer.h"

void DumpRegisters(const arm_thread_state64_internal *old_state) {
    printf("Registers:\n"
           " x0: 0x%016llx  x1: 0x%016llx  x2: 0x%016llx  x3: 0x%016llx\n"
           " x4: 0x%016llx  x5: 0x%016llx  x6: 0x%016llx  x7: 0x%016llx\n"
           " x8: 0x%016llx  x9: 0x%016llx x10: 0x%016llx x11: 0x%016llx\n"
           "x12: 0x%016llx x13: 0x%016llx x14: 0x%016llx x15: 0x%016llx\n"
           "x16: 0x%016llx x17: 0x%016llx x18: 0x%016llx x19: 0x%016llx\n"
           "x20: 0x%016llx x21: 0x%016llx x22: 0x%016llx x23: 0x%016llx\n"
           "x24: 0x%016llx x25: 0x%016llx x26: 0x%016llx x27: 0x%016llx\n"
           "x28: 0x%016llx  fp: 0x%016llx  lr: 0x%016llx\n"
           " pc: 0x%016llx  sp: 0x%016llx psr: 0x%08x"
           "\n",
           old_state->__x[ 0], old_state->__x[ 1], old_state->__x[ 2], old_state->__x[ 3], old_state->__x[ 4], old_state->__x[ 5], old_state->__x[ 6], old_state->__x[ 7], old_state->__x[ 8], old_state->__x[ 9],
           old_state->__x[10], old_state->__x[11], old_state->__x[12], old_state->__x[13], old_state->__x[14], old_state->__x[15], old_state->__x[16], old_state->__x[17], old_state->__x[18], old_state->__x[19],
           old_state->__x[20], old_state->__x[21], old_state->__x[22], old_state->__x[23], old_state->__x[24], old_state->__x[25], old_state->__x[26], old_state->__x[27], old_state->__x[28],
           old_state->__fp, old_state->__lr, old_state->__pc, old_state->__sp, old_state->__cpsr);
}

#define __DARWIN_ARM_THREAD_STATE64_FLAGS_NO_PTRAUTH 1
@implementation ProcessContext

- (instancetype)initWithExceptionPortName:(NSString *)portName {
    self = [super init];
    self.exceptionPortName = portName;
    // setup exception handler
    _expectedLR = 0xFFFFFF00;
    _inputReadySemaphore = dispatch_semaphore_create(0);
    _outputReadySemaphore = dispatch_semaphore_create(0);
    kern_return_t kr = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &_exceptionPort);
    kr = mach_port_insert_right(mach_task_self(), _exceptionPort, _exceptionPort, MACH_MSG_TYPE_MAKE_SEND);
    kr = bootstrap_register(bootstrap_port, portName.UTF8String, _exceptionPort);
    assert(kr == KERN_SUCCESS);
    printf("%s registered on port 0x%x\n", portName.UTF8String, _exceptionPort);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self exceptionServer];
    });
    return self;
}

- (void)spawnProcess:(NSString *)name suspended:(BOOL)suspended {
    self.pid = launchTest(self.exceptionPortName, name, suspended);
}

- (uint32_t)read32:(uintptr_t)address {
    return (uint32_t)RemoteArbCall(self, __atomic_load_4, address, 3);
}
- (uint64_t)read64:(uintptr_t)address {
    return RemoteArbCall(self, __atomic_load_8, address, 3);
}
- (void)write32:(uintptr_t)address value:(uint32_t)value {
    RemoteArbCall(self, __atomic_store_4, address, value, 0);
}
- (void)write64:(uintptr_t)address value:(uint64_t)value {
    RemoteArbCall(self, __atomic_store_8, address, value, 0);
}
- (void)writeBytes:(uintptr_t)address data:(const void *)data length:(size_t)length {
    length = (length + 7) & ~7ULL;
    for (size_t offset = 0; offset < length; offset += 8) {
        [self write64:address + offset value:*((uint64_t *)(data + offset))];
    }
}
- (uint64_t)writeString:(uintptr_t)address string:(const char *)string {
    size_t len = (strlen(string)+1 + 7) & ~7ULL;
    [self writeBytes:address data:string length:len];
    return address;
}

- (uint64_t)taskRead64:(mach_port_t)task addr:(uint64_t)addr map:(uint64_t)map {
    kern_return_t kr = (kern_return_t)RemoteArbCall(self, vm_read_overwrite, task, addr, sizeof(uint64_t), map, map + 8);
    if (kr != KERN_SUCCESS) {
        printf("RemoteTaskRead64 failed\n");
        return kr;
    }
    return kr;
}

- (void)taskHexDump:(uint64_t)addr size:(size_t)size task:(mach_port_t)task map:(uint64_t)map {
     void *data = malloc(size);
     if (!data) return;

     size_t off = 0;
     while (off < size) {
         [self taskRead64:task addr:addr + off map:map];
         uint64_t v = [self read64:map];

         size_t to_copy = (size - off) < 8 ? (size - off) : 8;
         memcpy((unsigned char*)data + off, &v, to_copy);
         off += to_copy;
     }

     char ascii[17];
     size_t i, j;
     ascii[16] = '\0';
     for (i = 0; i < size; ++i) {
         if ((i % 16) == 0)
         {
             printf("[0x%016llx+0x%03zx] ", addr, i);
         }

         printf("%02X ", ((unsigned char*)data)[i]);
         if (((unsigned char*)data)[i] >= ' ' && ((unsigned char*)data)[i] <= '~') {
             ascii[i % 16] = ((unsigned char*)data)[i];
         } else {
             ascii[i % 16] = '.';
         }
         if ((i+1) % 8 == 0 || i+1 == size) {
             printf(" ");
             if ((i+1) % 16 == 0) {
                 printf("|  %s \n", ascii);
             } else if (i+1 == size) {
                 ascii[(i+1) % 16] = '\0';
                 if ((i+1) % 16 <= 8) {
                     printf(" ");
                 }
                 for (j = (i+1) % 16; j < 16; ++j) {
                     printf("   ");
                 }
                 printf("|  %s \n", ascii);
             }
         }
     }
     free(data);
 }

- (uint64_t)arbCall:(char *)name pc:(uintptr_t)pc args:(uint64_t *)args argCount:(NSUInteger)argCount {
    // libswiftDistributed.dylib`swift_distributed_execute_target:
    // 0x20d1f0e58 <+352>: br     x8
    if (!_newState) {
        dispatch_semaphore_wait(_outputReadySemaphore, DISPATCH_TIME_FOREVER);
    }
    
    if (argCount > 8) {
        uint64_t sp = _newState->__sp; xpaci(sp);
        for (int i = 8; i < argCount; i++) {
            [self write64:sp + sizeof(uint64_t[i-8]) value:args[i]];
        }
        argCount = 8;
    }
    
    xpaci(pc);
    _newState->__x[8] = pc;
    memcpy(&_newState->__x[0], args, argCount * sizeof(uint64_t));
    
    printf("Calling function %s\n", name);
    
    _newState->__pc = brX8Address;
    if (_newState->__flags & __DARWIN_ARM_THREAD_STATE64_FLAGS_NO_PTRAUTH) {
        xpaci(_newState->__pc);
        _newState->__lr = 0xFFFFFF00;
    } else {
        _newState->__flags &= ~__DARWIN_ARM_THREAD_STATE64_FLAGS_KERNEL_SIGNED_PC;
    }
    
    [self resume];
    
    printf("- function returned x0=0x%llx\n", _newState->__x[0]);
    return _newState->__x[0];
}

- (void)setLr:(uint64_t)newLR {
    // libdispatch.dylib`__dispatch_event_loop_cancel_waiter.cold.1:
    // 0x18e527974 <+8>:  mov    x30, x1
    // libdispatch.dylib`__dispatch_event_loop_cancel_waiter.cold.2:
    // 0x18e527978 <+0>:  ldr    x8, [x0, #0x40]
    
    // x0=0 to cause a null deref to bring control back to us
    RemoteArbCall(self, changeLRAddress, 0, newLR);
}

- (void)resume {
    dispatch_semaphore_signal(_inputReadySemaphore);
    dispatch_semaphore_wait(_outputReadySemaphore, DISPATCH_TIME_FOREVER);
}

- (void)terminate {
    if (_newState->__flags & __DARWIN_ARM_THREAD_STATE64_FLAGS_NO_PTRAUTH) {
        _newState->__pc = (uint64_t)raise;
        _newState->__x[0] = SIGKILL;
        dispatch_semaphore_signal(_inputReadySemaphore);
    }
    // deallocate exception port
    mach_port_t port = _exceptionPort;
    _exceptionPort = MACH_PORT_NULL;
    mach_port_deallocate(mach_task_self(), port);
}

- (kern_return_t)catch_mach_exception_raise_state_identity:(mach_port_t)thread task:(mach_port_t)task
exception:(exception_type_t)exception code:(mach_exception_data_t)code
codeCnt:(mach_msg_type_number_t)codeCnt flavor:(int *)flavor
old_state:(const arm_thread_state64_internal *)old_state old_stateCnt:(mach_msg_type_number_t)old_stateCnt
new_state:(arm_thread_state64_internal *)new_state new_stateCnt:(mach_msg_type_number_t *)new_stateCnt {
    if (*flavor != ARM_THREAD_STATE64) {
        printf("Unsupported thread state flavor: %d\n", *flavor);
        return KERN_FAILURE;
    }
    
    memcpy(new_state, old_state, sizeof(arm_thread_state64_internal));
    *new_stateCnt = old_stateCnt;
    _newState = new_state;
    
    if (_numExceptionsHandled == 0) {
        DumpRegisters(old_state);
        printf("Got task port: %d\n", task);
        _taskPort = task;
    }
    
    if (_numExceptionsHandled > 0) {
        BOOL hasPAC = !(old_state->__flags & __DARWIN_ARM_THREAD_STATE64_FLAGS_NO_PTRAUTH);
        uint64_t ptrL = (uint64_t)(code[1] & 0xFFFFFFFFF);
        uint64_t ptrR = (uint64_t)(_lastPC & 0xFFFFFFFFF);
        if (hasPAC && exception == EXC_BAD_ACCESS && codeCnt == 2 &&
            (code[0] == 1 || code[0] == 257) &&
            (ptrL == ptrR || code[1] == 0xffffffffffffffff)) {
            new_state->__pc = _lastPC;
            new_state->__flags &= ~__DARWIN_ARM_THREAD_STATE64_FLAGS_KERNEL_SIGNED_PC;
            return KERN_SUCCESS;
        }
        
        dispatch_semaphore_signal(_outputReadySemaphore);
        if (_expectedLR == (uint64_t)-1) {
            // skip lr check
            printf("Skipping check for lr value: 0x%llx\n", old_state->__lr);
        } else if ((uint32_t)old_state->__lr != (uint32_t)_expectedLR || wantsDetach) {
            wantsDetach = NO;
            printf("Process might have crashed! unexpected lr value: 0x%llx (expected: 0x%llx)\n", old_state->__lr, _expectedLR);
            DumpRegisters(old_state);
            return KERN_FAILURE;
        }
    }
    
    dispatch_semaphore_wait(_inputReadySemaphore, DISPATCH_TIME_FOREVER);
    _lastPC = new_state->__pc;
    
    _numExceptionsHandled++;
    return KERN_SUCCESS;
}
- (void)exceptionServer {
    mach_msg_return_t rt;
    __Request__mach_exception_raise_state_identity_t msg;
    __Reply__mach_exception_raise_state_identity_t reply;
    
    while(_exceptionPort != MACH_PORT_NULL) {
        rt = mach_msg((mach_msg_header_t *)&msg, MACH_RCV_MSG, 0, sizeof(msg), _exceptionPort, 0, MACH_PORT_NULL);
        assert(rt == MACH_MSG_SUCCESS);
        
        [self mach_exc_server:(mach_msg_header_t *)&msg reply:(mach_msg_header_t *)&reply];
        
        // Send the now-initialized reply
        rt = mach_msg((mach_msg_header_t *)&reply, MACH_SEND_MSG, reply.Head.msgh_size, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
        assert(rt == MACH_MSG_SUCCESS);
    }
}
// from mach_excServer.c
- (BOOL)mach_exc_server:(mach_msg_header_t *)InHeadP reply:(mach_msg_header_t *)OutHeadP {
    mig_routine_t routine;
    
    OutHeadP->msgh_bits = MACH_MSGH_BITS(MACH_MSGH_BITS_REPLY(InHeadP->msgh_bits), 0);
    OutHeadP->msgh_remote_port = InHeadP->msgh_reply_port;
    /* Minimal size: routine() will update it if different */
    OutHeadP->msgh_size = (mach_msg_size_t)sizeof(mig_reply_error_t);
    OutHeadP->msgh_local_port = MACH_PORT_NULL;
    OutHeadP->msgh_id = InHeadP->msgh_id + 100;
    OutHeadP->msgh_reserved = 0;
    
//    if ((InHeadP->msgh_id > 2409) || (InHeadP->msgh_id < 2405) ||
//        ((routine = catch_mach_exc_subsystem.routine[InHeadP->msgh_id - 2405].stub_routine) == 0)) {
    if (InHeadP->msgh_id != 2407) {
        ((mig_reply_error_t *)OutHeadP)->NDR = NDR_record;
        ((mig_reply_error_t *)OutHeadP)->RetCode = MIG_BAD_ID;
        return FALSE;
    }
    //(*routine) (InHeadP, OutHeadP);
    [self _Xmach_exception_raise_state_identity:InHeadP reply:OutHeadP];
    return TRUE;
}
- (void)_Xmach_exception_raise_state_identity:(mach_msg_header_t *)InHeadP reply:(mach_msg_header_t *)OutHeadP {
#ifdef  __MigPackStructs
#pragma pack(push, 4)
#endif
    typedef struct {
        mach_msg_header_t Head;
        /* start of the kernel processed data */
        mach_msg_body_t msgh_body;
        mach_msg_port_descriptor_t thread;
        mach_msg_port_descriptor_t task;
        /* end of the kernel processed data */
        NDR_record_t NDR;
        exception_type_t exception;
        mach_msg_type_number_t codeCnt;
        int64_t code[2];
        int flavor;
        mach_msg_type_number_t old_stateCnt;
        natural_t old_state[1296];
        mach_msg_trailer_t trailer;
    } Request __attribute__((unused));
#ifdef  __MigPackStructs
#pragma pack(pop)
#endif
    typedef __Request__mach_exception_raise_state_identity_t __Request;
    typedef __Reply__mach_exception_raise_state_identity_t Reply __attribute__((unused));

    /*
     * typedef struct {
     *     mach_msg_header_t Head;
     *     NDR_record_t NDR;
     *     kern_return_t RetCode;
     * } mig_reply_error_t;
     */

    Request *In0P = (Request *) InHeadP;
    Request *In1P = In0P;
    Reply *OutP = (Reply *) OutHeadP;
#ifdef    __MIG_check__Request__mach_exception_raise_state_identity_t__defined
    kern_return_t check_result;
#endif    /* __MIG_check__Request__mach_exception_raise_state_identity_t__defined */

    //__DeclareRcvRpc(2407, "mach_exception_raise_state_identity")
    //__BeforeRcvRpc(2407, "mach_exception_raise_state_identity")

#if    defined(__MIG_check__Request__mach_exception_raise_state_identity_t__defined)
    check_result = __MIG_check__Request__mach_exception_raise_state_identity_t((__Request *)In0P, (__Request **)&In1P);
    if (check_result != MACH_MSG_SUCCESS)
        { MIG_RETURN_ERROR(OutP, check_result); }
#endif    /* defined(__MIG_check__Request__mach_exception_raise_state_identity_t__defined) */

    OutP->new_stateCnt = 1296;

    OutP->RetCode = [self catch_mach_exception_raise_state_identity:In0P->thread.name
        task:In0P->task.name
        exception:In0P->exception
        code:In0P->code
        codeCnt:In0P->codeCnt
        flavor:&In1P->flavor
        old_state:(const arm_thread_state64_internal *)In1P->old_state
        old_stateCnt:In1P->old_stateCnt
        new_state:(arm_thread_state64_internal *)OutP->new_state
        new_stateCnt:&OutP->new_stateCnt];
    //catch_mach_exception_raise_state_identity(In0P->Head.msgh_request_port, In0P->thread.name, In0P->task.name, In0P->exception, In0P->code, In0P->codeCnt, &In1P->flavor, In1P->old_state, In1P->old_stateCnt, OutP->new_state, &OutP->new_stateCnt);
    if (OutP->RetCode != KERN_SUCCESS) {
        MIG_RETURN_ERROR(OutP, OutP->RetCode);
    }

    OutP->NDR = NDR_record;


    OutP->flavor = In1P->flavor;
    OutP->Head.msgh_size = (mach_msg_size_t)(sizeof(Reply) - 5184) + (((4 * OutP->new_stateCnt)));

    //__AfterRcvRpc(2407, "mach_exception_raise_state_identity")
}
@end
