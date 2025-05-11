// g++ -std=c++17 -o eraser eraser.cpp


#include <fstream>
#include <iostream>
#include <string>
#include <random>
#include <cstdio>
#include <filesystem>

bool secureErase(const std::string& filepath, int passes = 3) {
    namespace fs = std::filesystem;

    if (!fs::exists(filepath)) {
        std::cerr << "File does not exist: " << filepath << '\n';
        return false;
    }

    std::error_code ec;
    std::uintmax_t filesize = fs::file_size(filepath, ec);
    if (ec) {
        std::cerr << "Error reading file size: " << ec.message() << '\n';
        return false;
    }

    std::fstream file(filepath, std::ios::in | std::ios::out | std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "Failed to open file: " << filepath << '\n';
        return false;
    }

    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_int_distribution<unsigned char> dis(0, 255);

    for (int pass = 0; pass < passes; ++pass) {
        file.seekp(0, std::ios::beg);
        for (std::uintmax_t i = 0; i < filesize; ++i) {
            char byte = static_cast<char>(dis(gen));
            file.put(byte);
        }
        file.flush();
    }

    file.close();

    if (std::remove(filepath.c_str()) != 0) {
        std::cerr << "Failed to delete file: " << filepath << '\n';
        return false;
    }

    return true;
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <file_path>\n";
        return 1;
    }

    std::string filepath = argv[1];

    if (secureErase(filepath)) {
        std::cout << "File securely erased: " << filepath << '\n';
        return 0;
    } else {
        std::cerr << "Failed to erase file: " << filepath << '\n';
        return 1;
    }
}
