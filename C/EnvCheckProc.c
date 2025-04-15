#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

int file_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0;
}

int detect_kubernetes_container() {
    FILE *fp = fopen("/proc/1/cgroup", "r");
    if (!fp) {
        return 0;
    }

    char line[512];
    while (fgets(line, sizeof(line), fp)) {
        if (strstr(line, "kubepods")) {
            fclose(fp);
            return 1;
        }
    }

    fclose(fp);
    return 0;
}

int main() {
    // Check for the presence of /proc
    if (!file_exists("/proc")) {
        fprintf(stderr, "Environment appears non-standard (no /proc). Exiting.\n");
        exit(EXIT_FAILURE);
    }

    // Detect if running inside a Kubernetes container
    if (detect_kubernetes_container()) {
        fprintf(stderr, "Kubernetes environment detected. Exiting.\n");
        exit(EXIT_FAILURE);
    }

    // If all checks pass
    printf("Running in standard environment. Continuing execution...\n");

    // Your main application logic here
    // ...

    return 0;
}
