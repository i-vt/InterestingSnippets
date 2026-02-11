#include <unistd.h>

// Assuming the global root directory string is defined somewhere
const char* g_RootDir = "/"; 

void jail_directory() {
    chdir(g_RootDir);
}
