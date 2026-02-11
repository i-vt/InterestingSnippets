lea     rsi, handler             ; Load address of the custom handler into rsi (Arg 2)
mov     edi, SIGCHLD             ; Load SIGCHLD constant into edi (Arg 1)
xor     r15d, r15d               ; Clear r15d (likely preparing a variable for later)
call    _signal                  ; Call signal(SIGCHLD, handler)
