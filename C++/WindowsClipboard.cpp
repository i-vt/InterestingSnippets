#include <windows.h>
#include <string>
#include <iostream>

// Function to get clipboard contents as a string
std::string GetClipboardText() {
    if (!OpenClipboard(nullptr)) {
        return ""; // Failed to open clipboard
    }

    HANDLE hData = GetClipboardData(CF_TEXT);
    if (!hData) {
        CloseClipboard();
        return "";
    }

    char* pszText = static_cast<char*>(GlobalLock(hData));
    if (!pszText) {
        CloseClipboard();
        return "";
    }

    std::string text(pszText);
    GlobalUnlock(hData);
    CloseClipboard();

    return text;
}

// Function to set clipboard contents
bool SetClipboardText(const std::string& text) {
    if (!OpenClipboard(nullptr)) {
        return false; // Failed to open clipboard
    }

    EmptyClipboard(); // Clear existing content

    // Allocate global memory
    HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, text.size() + 1);
    if (!hMem) {
        CloseClipboard();
        return false;
    }

    // Copy text to global memory
    char* pMem = static_cast<char*>(GlobalLock(hMem));
    if (pMem) {
        memcpy(pMem, text.c_str(), text.size() + 1);
        GlobalUnlock(hMem);
    } else {
        GlobalFree(hMem);
        CloseClipboard();
        return false;
    }

    // Set clipboard data
    SetClipboardData(CF_TEXT, hMem);
    CloseClipboard();

    return true;
}

// Example usage
int main() {
    // Test setting clipboard text
    std::string textToCopy = "Hello, Clipboard!";
    if (SetClipboardText(textToCopy)) {
        std::cout << "Text successfully copied to clipboard." << std::endl;
    } else {
        std::cout << "Failed to copy text to clipboard." << std::endl;
    }

    // Test retrieving clipboard text
    std::string clipboardText = GetClipboardText();
    if (!clipboardText.empty()) {
        std::cout << "Clipboard contents: " << clipboardText << std::endl;
    } else {
        std::cout << "Clipboard is empty or could not be accessed." << std::endl;
    }

    return 0;
}
