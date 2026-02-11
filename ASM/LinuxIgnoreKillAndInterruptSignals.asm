mov     esi, (offset dword_0+1)  ; Load 1 (SIG_IGN) into esi (Arg 2)
mov     edi, SIGQUIT             ; Load SIGQUIT into edi (Arg 1)
call    _signal                  ; Call signal(SIGQUIT, SIG_IGN)

mov     esi, (offset dword_0+1)  ; Load 1 (SIG_IGN)
mov     edi, SIGTERM             ; Load SIGTERM
call    _signal                  ; Call signal(SIGTERM, SIG_IGN)

mov     esi, (offset dword_0+1)  ; Load 1 (SIG_IGN)
mov     edi, SIGHUP              ; Load SIGHUP
call    _signal                  ; Call signal(SIGHUP, SIG_IGN)

mov     esi, (offset dword_0+1)  ; Load 1 (SIG_IGN)
mov     edi, SIGINT              ; Load SIGINT
call    _signal                  ; Call signal(SIGINT, SIG_IGN)

mov     esi, (offset dword_0+1)  ; Load 1 (SIG_IGN)
mov     edi, SIGPIPE             ; Load SIGPIPE
call    _signal                  ; Call signal(SIGPIPE, SIG_IGN)
