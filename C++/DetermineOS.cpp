#include <iostream>
#include <string>

std::string getOperatingSystem() {
    #if defined(_WIN32) || defined(_WIN64)
        return "Windows";
    #elif defined(__APPLE__) || defined(__MACH__)
        return "macOS";
    #elif defined(__linux__)
        return "Linux";
    #elif defined(__unix__)
        return "Unix";
    #else
        return "Unknown Operating System";
    #endif
}

int main() {
    std::string os = getOperatingSystem();
    std::cout << "Operating System: " << os << std::endl;
    return 0;
}
