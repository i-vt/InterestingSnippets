#include <windows.h>
#include <time.h>
#include <stdlib.h>
#include <math.h>  // For math functions like sin()
//x86_64-w64-mingw32-gcc -o screentearing8.exe screentearing8.c -lgdi32 -lm -mwindows
#define SIMULATION_DURATION 15000 // 15 seconds

// Global variables
int screenWidth, screenHeight;
DWORD startTime;

void SimulateScreenTearing(HDC hdc, int screenWidth, int screenHeight) {
    int stripHeight = rand() % 60 + 60;  // Increased strip height (60 to 120 pixels)
    for (int y = 0; y < screenHeight; y += stripHeight) {
        int offset = rand() % 100 - 50;  // Increased offset range (-50 to 50 pixels)
        BitBlt(hdc, offset, y, screenWidth, stripHeight, hdc, 0, y, SRCCOPY);
    }
}

void SimulateColorInversion(HDC hdc, int screenWidth, int screenHeight) {
    int width = rand() % (screenWidth / 2) + 300;  // Increased area for inversion
    int height = rand() % (screenHeight / 2) + 300;
    int x = rand() % (screenWidth - width);
    int y = rand() % (screenHeight - height);

    BitBlt(hdc, x, y, width, height, hdc, x, y, NOTSRCCOPY);
}

void SimulatePixelation(HDC hdc, int screenWidth, int screenHeight) {
    int blockSize = rand() % 60 + 40;  // Larger block size (40 to 100 pixels)
    for (int y = 0; y < screenHeight; y += blockSize) {
        for (int x = 0; x < screenWidth; x += blockSize) {
            BitBlt(hdc, x, y, blockSize, blockSize, hdc, x, y, SRCCOPY);
        }
    }
}

void SimulateFlickering(HDC hdc, int screenWidth, int screenHeight) {
    int flickerWidth = rand() % 500 + 300;  // Larger flicker area (300 to 800 pixels wide)
    int flickerHeight = rand() % 300 + 200;  // Larger flicker height (200 to 500 pixels tall)
    int x = rand() % (screenWidth - flickerWidth);
    int y = rand() % (screenHeight - flickerHeight);

    BitBlt(hdc, x, y, flickerWidth, flickerHeight, hdc, x, y, DSTINVERT);
}

void SimulateScanlines(HDC hdc, int screenWidth, int screenHeight) {
    int lineHeight = 2;
    int lineSpacing = rand() % 6 + 1;  // Smaller line spacing for denser lines
    for (int y = 0; y < screenHeight; y += lineHeight + lineSpacing) {
        BitBlt(hdc, 0, y, screenWidth, lineHeight, hdc, 0, y, SRCCOPY);
    }
}

void SimulateBlur(HDC hdc, int screenWidth, int screenHeight) {
    int blockSize = rand() % 50 + 50;  // Blur block size (50 to 100 pixels)
    for (int y = 0; y < screenHeight; y += blockSize) {
        for (int x = 0; x < screenWidth; x += blockSize) {
            int offsetX = rand() % 5 - 2;  // Small shift left/right
            int offsetY = rand() % 5 - 2;  // Small shift up/down
            BitBlt(hdc, x + offsetX, y + offsetY, blockSize, blockSize, hdc, x, y, SRCCOPY);
        }
    }
}

void SimulateGlitch(HDC hdc, int screenWidth, int screenHeight) {
    int glitchWidth = rand() % 100 + 50;  // Small glitch width (50 to 150 pixels)
    int glitchHeight = rand() % 100 + 50;  // Small glitch height (50 to 150 pixels)
    int x = rand() % (screenWidth - glitchWidth);
    int y = rand() % (screenHeight - glitchHeight);
    int destX = rand() % screenWidth;
    int destY = rand() % screenHeight;

    BitBlt(hdc, destX, destY, glitchWidth, glitchHeight, hdc, x, y, SRCCOPY);
}

void SimulateStatic(HDC hdc, int screenWidth, int screenHeight) {
    int numPixels = rand() % 2000 + 1000;  // Static intensity (1000 to 3000 pixels)
    for (int i = 0; i < numPixels; i++) {
        int x = rand() % screenWidth;
        int y = rand() % screenHeight;
        SetPixel(hdc, x, y, RGB(rand() % 256, rand() % 256, rand() % 256));  // Random color
    }
}

void SimulateRipple(HDC hdc, int screenWidth, int screenHeight) {
    int amplitude = rand() % 30 + 10;  // Wave amplitude (10 to 40 pixels)
    int wavelength = rand() % 50 + 20;  // Wavelength (20 to 70 pixels)
    for (int y = 0; y < screenHeight; y++) {
        int offsetX = (int)(amplitude * sin(2 * 3.14159 * y / wavelength));  // Sine wave distortion
        BitBlt(hdc, offsetX, y, screenWidth, 1, hdc, 0, y, SRCCOPY);
    }
}

void RandomEffect(HDC hdc, int screenWidth, int screenHeight) {
    // Randomly select one or more effects to apply
    int effectCount = rand() % 3 + 1;  // Between 1 and 3 effects per iteration
    for (int i = 0; i < effectCount; i++) {
        int effect = rand() % 9;  // Now we have 9 effects
        switch (effect) {
            case 0:
                SimulateScreenTearing(hdc, screenWidth, screenHeight);
                break;
            case 1:
                SimulateColorInversion(hdc, screenWidth, screenHeight);
                break;
            case 2:
                SimulatePixelation(hdc, screenWidth, screenHeight);
                break;
            case 3:
                SimulateFlickering(hdc, screenWidth, screenHeight);
                break;
            case 4:
                SimulateScanlines(hdc, screenWidth, screenHeight);
                break;
            case 5:
                SimulateBlur(hdc, screenWidth, screenHeight);
                break;
            case 6:
                SimulateGlitch(hdc, screenWidth, screenHeight);
                break;
            case 7:
                SimulateStatic(hdc, screenWidth, screenHeight);
                break;
            case 8:
                SimulateRipple(hdc, screenWidth, screenHeight);
                break;
        }
    }
}

void StartSimulation() {
    // Get the screen dimensions
    screenWidth = GetSystemMetrics(SM_CXSCREEN);
    screenHeight = GetSystemMetrics(SM_CYSCREEN);

    // Get the device context for the entire desktop, including non-client areas (like taskbar)
    HWND desktop = GetDesktopWindow();
    HDC hdc = GetWindowDC(desktop);  // Includes everything: desktop, taskbar, menu bar, etc.

    startTime = GetTickCount();

    while (GetTickCount() - startTime < SIMULATION_DURATION) {
        // Apply random screen effects frequently
        RandomEffect(hdc, screenWidth, screenHeight);
        Sleep(0);  // Reduce delay for more frequent and overlapping effects
    }

    // Release the device context
    ReleaseDC(desktop, hdc);
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    srand((unsigned int)time(NULL));  // Seed the random generator
    StartSimulation();
    return 0;
}
