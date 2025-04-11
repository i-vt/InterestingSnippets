;nasm -f elf64 detect_vm.asm -o detect_vm.o
;ld detect_vm.o -o detect_vm

section .data
    idtr_value dq 0

section .text
    global _start

_start:
    ; Get IDT register into memory
    sidt [idtr_value]

    ; Load upper 16 bits of IDTR base address into AX
    mov eax, [idtr_value + 2]

    ; Compare with a known threshold for detection
    cmp eax, 0xD0000000
    ja  real_hardware
    jmp virtualized_env

real_hardware:
    ; Put your real-environment-only code here
    ; For demonstration: exit(0)
    mov eax, 60        ; syscall: exit
    xor edi, edi       ; status = 0
    syscall

virtualized_env:
    ; Infinite loop to hang or break execution in VM
    jmp $
