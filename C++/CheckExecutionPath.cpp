// g++ -o CheckExecutionPath CheckExecutionPath.cpp
#include <iostream>
#include <string>

#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#include <limits.h>
#endif

std::string getExecutionPath() {
    char pathBuffer[1024];

#ifdef _WIN32
    DWORD length = GetModuleFileNameA(NULL, pathBuffer, sizeof(pathBuffer));
    if (length == 0 || length >= sizeof(pathBuffer)) {
        return "Error retrieving path";
    }
#else
    ssize_t length = readlink("/proc/self/exe", pathBuffer, sizeof(pathBuffer) - 1);
    if (length == -1) {
        return "Error retrieving path";
    }
    pathBuffer[length] = '\0';  // Null-terminate the string
#endif

    return std::string(pathBuffer);
}

int main() {
    std::string executionPath = getExecutionPath();
    std::cout << "Execution Path: " << executionPath << std::endl;
    return 0;
}
