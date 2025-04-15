#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>

//Anti-Debugging
//Before proceeding with its main activity, GorillaBot performs checks to detect the presence of debugging
//tools. One of its first actions is to read the /proc/self/status file and inspect the TracerPid field. This
//field indicates whether the process is being traced – a value of 0 means it’s not, while a non-zero value
//suggests a debugger is attached.

//https://any.run/cybersecurity-blog/gorillabot-malware-analysis/

// Signal handler for SIGTRAP
void handle_sigtrap(int sig) {
    printf("[!] SIGTRAP caught: No debugger detected (or it's ignoring the signal).\n");
    printf("[!] Exiting...\n");
    exit(0);
}

// Main logic
int main() {
    // Register SIGTRAP handler
    signal(SIGTRAP, handle_sigtrap);

    printf("[*] Raising SIGTRAP...\n");

    // Raise SIGTRAP — a debugger will usually catch this
    raise(SIGTRAP);

    // If we reach here, SIGTRAP wasn't handled properly — likely a debugger interfered
    printf("[!] SIGTRAP not handled as expected. A debugger might be present.\n");

    return 0;
}
