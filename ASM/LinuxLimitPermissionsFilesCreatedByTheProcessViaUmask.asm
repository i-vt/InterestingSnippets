mov     edi, 3Fh                 ; Load 0x3F (Octal 077) into edi (Arg 1)
call    _umask                   ; Call umask(077)
