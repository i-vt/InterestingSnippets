/*
README: Wayland Screenshot Tool using sdbus-c++

This C++ program takes a screenshot on Wayland by using xdg-desktop-portal D-Bus API.

# Requirements:
- Linux with Wayland compositor (e.g., GNOME, KDE, Sway, etc.)
- `xdg-desktop-portal` installed and running (should be already if using Wayland)
- C++17 compatible compiler (g++ 7.0+)
- sdbus-c++ library installed

# Install dependencies:

On Ubuntu/Debian:

    sudo apt update
    sudo apt install libsdbus-c++-dev libglib2.0-dev g++ pkg-config

If libsdbus-c++-dev is not available, you must build sdbus-c++ manually:
    https://github.com/Kistler-Group/sdbus-cpp

# Compilation:

    g++ screenshot.cpp -o screenshot -std=c++17 -lsdbus-c++

# Running:

Simply run the compiled binary:

    ./screenshot

It will trigger a permission popup asking for screenshot permission via xdg-desktop-portal.
After approval, it will capture the screen and save the screenshot to ~/Pictures/myscreenshot.png.

# Notes:
- On first use, your Wayland compositor (GNOME/KDE) will ask you to approve the screenshot.
- The saved file will overwrite `~/Pictures/myscreenshot.png` if it already exists.
- This program uses synchronous waiting on D-Bus signals to detect screenshot completion.

*/

#include <sdbus-c++/sdbus-c++.h>
#include <iostream>
#include <string>
#include <filesystem>
#include <cstring>
#include <chrono>
#include <thread>

namespace fs = std::filesystem;

int main(int argc, char* argv[])
{
    // Default target path
    fs::path targetPath = fs::path(getenv("HOME")) / "Pictures" / "myscreenshot.png";

    // If a path is provided as argument, use it
    if (argc > 1) {
        targetPath = fs::path(argv[1]);
    }

    try {
        auto connection = sdbus::createSessionBusConnection();

        // Create a proxy
        auto portalProxy = sdbus::createProxy(
            *connection,
            "org.freedesktop.portal.Desktop",
            "/org/freedesktop/portal/desktop"
        );

        portalProxy->finishRegistration();

        // Call Screenshot method
        sdbus::ObjectPath requestPath;

        {
            auto method = portalProxy->createMethodCall(
                "org.freedesktop.portal.Screenshot", // interface
                "Screenshot"                         // method
            );

            method << std::string("") << std::map<std::string, sdbus::Variant>();

            auto reply = portalProxy->callMethod(method);
            reply >> requestPath;
        }

        std::cout << "Screenshot request path: " << requestPath << std::endl;

        // Now listen for the Response signal
        bool finished = false;
        std::string imageUri;

        auto requestProxy = sdbus::createProxy(
            *connection,
            "org.freedesktop.portal.Desktop",
            static_cast<std::string>(requestPath)
        );

        requestProxy->uponSignal("Response")
            .onInterface("org.freedesktop.portal.Request")
            .call([&finished, &imageUri](uint32_t response, std::map<std::string, sdbus::Variant> results) {
                if (response == 0) {
                    if (results.count("uri")) {
                        imageUri = results["uri"].get<std::string>();
                        std::cout << "Screenshot saved at: " << imageUri << std::endl;
                    }
                } else {
                    std::cerr << "Screenshot failed with code: " << response << std::endl;
                }
                finished = true;
            });

        requestProxy->finishRegistration();

        while (!finished) {
            connection->processPendingRequest();
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
        }

        if (!imageUri.empty()) {
            auto sourcePath = fs::path(imageUri.substr(strlen("file://")));

            try {
                fs::copy_file(sourcePath, targetPath, fs::copy_options::overwrite_existing);
                std::cout << "Screenshot copied to: " << targetPath << std::endl;
            } catch (const std::exception& e) {
                std::cerr << "Error copying file: " << e.what() << std::endl;
            }
        }

    } catch (const sdbus::Error& e) {
        std::cerr << "D-Bus error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
