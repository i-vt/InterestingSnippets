#include <windows.h>
//x86_64-w64-mingw32-g++ -shared -o ArbitraryTestMessage.dll ArbitraryTestMessageWindowsDLL.cpp -static -Wl,--subsystem,windows
BOOL APIENTRY DllMain(HMODULE hModule, DWORD  ul_reason_for_call, LPVOID lpReserved) {
    if (ul_reason_for_call == DLL_PROCESS_ATTACH) {
        MessageBoxA(NULL, "DLL Injected!", "Success", MB_OK);
    }
    return TRUE;
}

