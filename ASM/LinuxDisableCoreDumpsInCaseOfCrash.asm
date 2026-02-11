lea     rsi, rlimits             ; Load address of rlimits struct into rsi (Arg 2)
mov     edi, RLIMIT_CORE         ; Load RLIMIT_CORE constant into edi (Arg 1)
mov     cs:rlimits.rlim_cur, 0   ; Set current limit to 0
mov     cs:rlimits.rlim_max, 0   ; Set max limit to 0
lea     rbx, [rsp+0B38h+timeout] ; (Compiler optimization/interleaving)
lea     r12, [rsp+0B38h+writefds]; (Compiler optimization/interleaving)
call    _setrlimit               ; Call setrlimit(RLIMIT_CORE, &rlimits)
