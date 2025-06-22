#include <iostream>
#include <windows.h>
#include <tlhelp32.h>
#include <string>

//x86_64-w64-mingw32-g++ InjectDllIntoTargetProcessUsingCreateRemoteThreadWithPrivilegeElevation.cpp -o injector64.exe -static -lwinmm -lws2_32 -ladvapi32 -lkernel32
// .\injector64.exe processthatexistsonthesameprivilege.exe ArbitraryTestMessage.dll

using std::cout;
using std::endl;
using std::string;

BOOL InjectDllToProcess(DWORD dwTargetPid, const std::string& DllPath);
DWORD ProcesstoPid(const std::string& ProcessName);
BOOL EnableDebugPrivilege();

int main(int argc, char* argv[]) {
    std::string szProcName = "HostProc.exe";
    std::string szDllPath = "MsgDll.dll";

    if (argc == 3) {
        szProcName = argv[1];
        szDllPath = argv[2];
    } else {
        cout << "Usage: " << argv[0] << " <ProcessName> <DllPath>\n";
        cout << "Defaulting to: HostProc.exe and MsgDll.dll\n";
    }

    DWORD dwPid = ProcesstoPid(szProcName);
    if (dwPid == 0) {
        cout << "Failed to find process.\n";
        return 1;
    }

    if (!EnableDebugPrivilege()) {
        cout << "Failed to enable debug privileges.\n";
        return 1;
    }

    if (!InjectDllToProcess(dwPid, szDllPath)) {
        cout << "DLL injection failed.\n";
        return 1;
    }

    return 0;
}

BOOL InjectDllToProcess(DWORD dwTargetPid, const std::string& DllPath) {
    HANDLE hProc = OpenProcess(PROCESS_ALL_ACCESS, FALSE, dwTargetPid);
    if (hProc == NULL) {
        cout << "Failed to open target process. Error: " << GetLastError() << "\n";
        return FALSE;
    }

    LPVOID psLibFileRemote = VirtualAllocEx(hProc, NULL, DllPath.size() + 1, MEM_COMMIT, PAGE_READWRITE);
    if (psLibFileRemote == NULL) {
        cout << "VirtualAllocEx failed. Error: " << GetLastError() << "\n";
        CloseHandle(hProc);
        return FALSE;
    }

    if (!WriteProcessMemory(hProc, psLibFileRemote, DllPath.c_str(), DllPath.size() + 1, NULL)) {
        cout << "WriteProcessMemory failed. Error: " << GetLastError() << "\n";
        VirtualFreeEx(hProc, psLibFileRemote, 0, MEM_RELEASE);
        CloseHandle(hProc);
        return FALSE;
    }

    FARPROC pfnStartAddr = GetProcAddress(GetModuleHandleA("kernel32.dll"), "LoadLibraryA");
    if (pfnStartAddr == NULL) {
        cout << "GetProcAddress failed. Error: " << GetLastError() << "\n";
        VirtualFreeEx(hProc, psLibFileRemote, 0, MEM_RELEASE);
        CloseHandle(hProc);
        return FALSE;
    }

    HANDLE hThread = CreateRemoteThread(hProc, NULL, 0,
                                        (LPTHREAD_START_ROUTINE)pfnStartAddr,
                                        psLibFileRemote, 0, NULL);
    if (hThread == NULL) {
        cout << "CreateRemoteThread failed. Error: " << GetLastError() << "\n";
        VirtualFreeEx(hProc, psLibFileRemote, 0, MEM_RELEASE);
        CloseHandle(hProc);
        return FALSE;
    }

    WaitForSingleObject(hThread, INFINITE);

    cout << "DLL injection succeeded.\n";
    cout << "DLL: " << DllPath << " injected into PID: " << dwTargetPid << "\n";

    CloseHandle(hThread);
    CloseHandle(hProc);
    return TRUE;
}

DWORD ProcesstoPid(const std::string& ProcessName) {
    HANDLE hProcessSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hProcessSnap == INVALID_HANDLE_VALUE) {
        cout << "CreateToolhelp32Snapshot failed. Error: " << GetLastError() << "\n";
        return 0;
    }

    PROCESSENTRY32 pe32 = { 0 };
    pe32.dwSize = sizeof(PROCESSENTRY32);

    if (Process32First(hProcessSnap, &pe32)) {
        do {
            if (_stricmp(ProcessName.c_str(), pe32.szExeFile) == 0) {
                CloseHandle(hProcessSnap);
                return pe32.th32ProcessID;
            }
        } while (Process32Next(hProcessSnap, &pe32));
    } else {
        cout << "Process32First failed. Error: " << GetLastError() << "\n";
    }

    CloseHandle(hProcessSnap);
    return 0;
}

BOOL EnableDebugPrivilege() {
    HANDLE hToken;
    TOKEN_PRIVILEGES tkp;

    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &hToken)) {
        return FALSE;
    }

    if (!LookupPrivilegeValue(NULL, SE_DEBUG_NAME, &tkp.Privileges[0].Luid)) {
        CloseHandle(hToken);
        return FALSE;
    }

    tkp.PrivilegeCount = 1;
    tkp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;

    if (!AdjustTokenPrivileges(hToken, FALSE, &tkp, 0, NULL, 0)) {
        CloseHandle(hToken);
        return FALSE;
    }

    CloseHandle(hToken);
    return TRUE;
}
