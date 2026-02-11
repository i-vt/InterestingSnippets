lea     rdi, g_RootDir           ; Load the address of the target path string into rdi (Arg 1)
call    _chdir                   ; Call chdir(g_RootDir)
