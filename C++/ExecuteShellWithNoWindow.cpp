#include <windows.h>
#include <iostream>
//x86_64-w64-mingw32-g++ -o execps05.exe execps05.cpp -mwindows -static-libgcc -static-libstdc++
//mad respect to OGs from cplusplus.com (specifically Disch) https://cplusplus.com/forum/general/105589/
// To run this without impacting UX/UI the following was done as per Disch's post:
//1) He needs to change his program to be a make it a Windows program rather than a console program.
//2) Change the entry point from main to WinMain int WINAPI WinMain(HINSTANCE,HINSTANCE,LPSTR,int)
//3) Simply do not create a window (no created window = your program will run in the background) 

void ExecutePowerShell(const std::wstring &command) {
    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW | STARTF_USESTDHANDLES;
    si.wShowWindow = SW_HIDE;

    // Redirect standard error and output
    si.hStdError = GetStdHandle(STD_ERROR_HANDLE);
    si.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);

    ZeroMemory(&pi, sizeof(pi));

    // Prepare the full command to execute PowerShell with hidden window
    std::wstring full_command = L"powershell.exe -NoProfile -ExecutionPolicy Bypass -Command " + command;
    if (!CreateProcessW(NULL, &full_command[0], NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
        std::wcerr << L"CreateProcessW failed (" << GetLastError() << L").\n";
    } else {
        // Wait until child process exits.
        WaitForSingleObject(pi.hProcess, INFINITE);

        // Close process and thread handles. 
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
    }
}

// Change the entry point to WinMain instead of main
int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    // Example command to get the list of processes and redirect output to a file
    ExecutePowerShell(L"Get-Process > C:\\Temp\\process.txt");

    return 0;
}
