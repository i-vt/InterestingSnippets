#include <windows.h>
#include <stdio.h>

// :: MSVC
// cl mousehook.c
// :: MinGW / gcc
// gcc mousehook.c -o mousehook.exe -mconsole

HHOOK hMouseHook = NULL;

LRESULT CALLBACK LowLevelMouseProc(int nCode, WPARAM wParam, LPARAM lParam)
{
    if (nCode == HC_ACTION)
    {
        switch (wParam)
        {
        case WM_LBUTTONDOWN:
            printf("Clicked! (Left button)\n");
            break;
        case WM_RBUTTONDOWN:
            printf("Clicked! (Right button)\n");
            break;
        case WM_MBUTTONDOWN:
            printf("Clicked! (Middle button)\n");
            break;
        }
        fflush(stdout);
    }

    // Pass the event on so other apps still receive mouse input
    return CallNextHookEx(hMouseHook, nCode, wParam, lParam);
}

int main(void)
{
    printf("Low-level mouse hook installed. Press Ctrl+C to exit.\n");

    hMouseHook = SetWindowsHookEx(WH_MOUSE_LL, LowLevelMouseProc,
                                  GetModuleHandle(NULL), 0);
    if (hMouseHook == NULL)
    {
        fprintf(stderr, "SetWindowsHookEx failed, error %lu\n", GetLastError());
        return 1;
    }

    // WH_MOUSE_LL is delivered via the thread's message queue,
    // so a message loop is mandatory here.
    MSG msg;
    while (GetMessage(&msg, NULL, 0, 0))
    {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }

    UnhookWindowsHookEx(hMouseHook);
    return 0;
}
