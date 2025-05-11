#include <iostream>
#include <chrono>
#include <ctime>
#include <iomanip>

void print_utc_time() {
    // Get current time as system clock time point
    auto now = std::chrono::system_clock::now();

    // Convert to time_t for ctime/gmtime usage
    std::time_t now_c = std::chrono::system_clock::to_time_t(now);

    // Convert to UTC/GMT/Zulu time
    std::tm* utc_tm = std::gmtime(&now_c);  // gmtime gives UTC (same as GMT/Zulu)

    std::cout << "UTC / GMT / Zulu time: "
              << std::put_time(utc_tm, "%Y-%m-%d %H:%M:%S") << "Z" << std::endl;
}

int main() {

    print_utc_time();

    return 0;
}
