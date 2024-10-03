import ctypes
from ctypes import wintypes
import struct
import os

# Define necessary Windows API constants
SRCCOPY = 0x00CC0020

# Define the BITMAPINFO structure
class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [
        ('biSize', wintypes.DWORD),
        ('biWidth', wintypes.LONG),
        ('biHeight', wintypes.LONG),
        ('biPlanes', wintypes.WORD),
        ('biBitCount', wintypes.WORD),
        ('biCompression', wintypes.DWORD),
        ('biSizeImage', wintypes.DWORD),
        ('biXPelsPerMeter', wintypes.LONG),
        ('biYPelsPerMeter', wintypes.LONG),
        ('biClrUsed', wintypes.DWORD),
        ('biClrImportant', wintypes.DWORD)
    ]

class BITMAPINFO(ctypes.Structure):
    _fields_ = [
        ('bmiHeader', BITMAPINFOHEADER),
        ('bmiColors', wintypes.DWORD * 3)
    ]

# Load user32 and gdi32 libraries
user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32

# Get the screen width and height
screen_width = user32.GetSystemMetrics(0)
screen_height = user32.GetSystemMetrics(1)

# Create a device context and a memory device context
desktop_dc = user32.GetDC(0)
memory_dc = gdi32.CreateCompatibleDC(desktop_dc)
bitmap = gdi32.CreateCompatibleBitmap(desktop_dc, screen_width, screen_height)

if not bitmap:
    raise Exception("Could not create compatible bitmap.")

gdi32.SelectObject(memory_dc, bitmap)

# BitBlt function to copy the screen into the bitmap
success = gdi32.BitBlt(
    memory_dc, 0, 0, screen_width, screen_height,
    desktop_dc, 0, 0, SRCCOPY
)

if not success:
    raise Exception("BitBlt failed.")

# Prepare BMP headers
bmp_header = struct.pack('<2sL2HL', b'BM', 14 + 40 + screen_width * screen_height * 3, 0, 0, 14 + 40)
dib_header = BITMAPINFO()
dib_header.bmiHeader.biSize = ctypes.sizeof(BITMAPINFOHEADER)
dib_header.bmiHeader.biWidth = screen_width
dib_header.bmiHeader.biHeight = screen_height
dib_header.bmiHeader.biPlanes = 1
dib_header.bmiHeader.biBitCount = 24
dib_header.bmiHeader.biCompression = 0  # BI_RGB
dib_header.bmiHeader.biSizeImage = screen_width * screen_height * 3

# File path for the screenshot
file_path = os.path.join(os.getcwd(), 'screenshot.bmp')

# Create a buffer for pixel data
buffer_size = screen_width * screen_height * 3
buffer = ctypes.create_string_buffer(buffer_size)

# Get the bitmap data
gdi32.GetDIBits(
    memory_dc, bitmap, 0, screen_height, buffer,
    ctypes.byref(dib_header), 0
)

# Write the bitmap data to file
with open(file_path, 'wb') as f:
    f.write(bmp_header)
    f.write(ctypes.string_at(ctypes.byref(dib_header), ctypes.sizeof(dib_header)))
    f.write(buffer)

# Clean up
gdi32.DeleteObject(bitmap)
gdi32.DeleteDC(memory_dc)
user32.ReleaseDC(0, desktop_dc)

print(f'Screenshot saved as {file_path}')
