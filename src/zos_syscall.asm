; Application syscall boundary: the kernel's IM2 table must be active while
; syscalls remap user RAM. ZOS_SYSCALL saves BASIC's alternate register bank.
        INCLUDE "zos_sys.asm"
        MACRO BBC_SYSCALL operation
                ld l, operation
                call ZOS_SYSCALL
        ENDM
