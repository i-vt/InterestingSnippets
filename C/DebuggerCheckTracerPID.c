#include <stdio.h>
#include <stdlib.h>
#include <string.h>

//Anti-Debugging
//Before proceeding with its main activity, GorillaBot performs checks to detect the presence of debugging
//tools. One of its first actions is to read the /proc/self/status file and inspect the TracerPid field. This
//field indicates whether the process is being traced – a value of 0 means it’s not, while a non-zero value
//suggests a debugger is attached.

//https://any.run/cybersecurity-blog/gorillabot-malware-analysis/

int is_being_debugged() {
    FILE *status_file = fopen("/proc/self/status", "r");
    if (!status_file) {
        perror("fopen");
        return -1;
    }

    char line[256];
    while (fgets(line, sizeof(line), status_file)) {
        if (strncmp(line, "TracerPid:", 10) == 0) {
            int tracer_pid = atoi(line + 10);
            fclose(status_file);
            return tracer_pid != 0;
        }
    }

    fclose(status_file);
    return -1; // TracerPid not found
}

int main() {
    if (is_being_debugged()) {
        printf("Debugger detected! Exiting...\n");
        return 1;
    } else {
        printf("No debugger detected. Continuing execution...\n");
    }

    // Rest of the program logic here
    return 0;
}
