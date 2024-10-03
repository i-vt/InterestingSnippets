import ctypes
from ctypes import POINTER, Structure, c_int, c_uint, c_ulong, c_char_p, c_void_p
from ctypes.util import find_library
import struct

# Load X11 library
x11 = ctypes.cdll.LoadLibrary(find_library('X11'))

# Constants
ZPixmap = 2
AllPlanes = 0xFFFFFFFF

# Define XWindowAttributes structure
class XWindowAttributes(Structure):
    _fields_ = [
        ("x", c_int),
        ("y", c_int),
        ("width", c_int),
        ("height", c_int),
        ("border_width", c_int),
        ("depth", c_int),
        ("visual", c_void_p),  # Pointer to a visual structure
        ("root", c_ulong),
        ("class", c_int),
        ("bit_gravity", c_int),
        ("win_gravity", c_int),
        ("backing_store", c_int),
        ("backing_planes", c_ulong),
        ("backing_pixel", c_ulong),
        ("save_under", c_int),
        ("colormap", c_ulong),
        ("map_installed", c_int),
        ("map_state", c_int),
        ("all_event_masks", c_ulong),
        ("your_event_mask", c_ulong),
        ("do_not_propagate_mask", c_ulong),
        ("override_redirect", c_int),
        ("screen", c_void_p)  # Pointer to a screen structure
    ]

# Define XImage structure
class XImage(Structure):
    _fields_ = [
        ("width", c_int),
        ("height", c_int),
        ("xoffset", c_int),
        ("format", c_int),
        ("data", c_void_p),  # This should be c_void_p for raw pointer data
        ("byte_order", c_int),
        ("bitmap_unit", c_int),
        ("bitmap_bit_order", c_int),
        ("bitmap_pad", c_int),
        ("depth", c_int),
        ("bytes_per_line", c_int),
        ("bits_per_pixel", c_int),
        ("red_mask", c_ulong),
        ("green_mask", c_ulong),
        ("blue_mask", c_ulong),
        ("obdata", c_void_p)  # Pointer to some object data
    ]

# Function prototypes
x11.XOpenDisplay.argtypes = [c_char_p]
x11.XOpenDisplay.restype = c_void_p  # Return type should be a void pointer

x11.XDefaultRootWindow.argtypes = [c_void_p]  # Accepts a display pointer
x11.XDefaultRootWindow.restype = c_ulong

x11.XGetWindowAttributes.argtypes = [c_void_p, c_ulong, POINTER(XWindowAttributes)]
x11.XGetWindowAttributes.restype = c_int

x11.XGetImage.argtypes = [c_void_p, c_ulong, c_int, c_int, c_uint, c_uint, c_ulong, c_int]
x11.XGetImage.restype = POINTER(XImage)

x11.XDestroyImage.argtypes = [POINTER(XImage)]
x11.XDestroyImage.restype = c_int

x11.XCloseDisplay.argtypes = [c_void_p]
x11.XCloseDisplay.restype = None

def capture_screen():
    # Open display
    display = x11.XOpenDisplay(None)
    if not display:
        raise Exception("Unable to open display")

    # Get the root window
    root = x11.XDefaultRootWindow(display)

    # Get window attributes
    attributes = XWindowAttributes()
    if x11.XGetWindowAttributes(display, root, ctypes.byref(attributes)) == 0:
        raise Exception("Unable to get window attributes")

    # Ensure attributes width and height are valid
    if attributes.width <= 0 or attributes.height <= 0:
        raise Exception("Invalid screen dimensions")

    # Capture the image
    ximage = x11.XGetImage(display, root, 0, 0, attributes.width, attributes.height, AllPlanes, ZPixmap)
    if not ximage:
        raise Exception("Unable to get image")

    # Extract image data
    try:
        width = ximage.contents.width
        height = ximage.contents.height
        bytes_per_line = ximage.contents.bytes_per_line
        bits_per_pixel = ximage.contents.bits_per_pixel

        # Verify values
        if width <= 0 or height <= 0 or bytes_per_line <= 0 or bits_per_pixel <= 0:
            raise Exception("Invalid image dimensions or format")

        # Retrieve image data
        data_size = height * bytes_per_line
        data = ctypes.string_at(ximage.contents.data, data_size)
    finally:
        # Destroy image to free resources
        x11.XDestroyImage(ximage)

    # Save the image data to a file
    save_image(data, width, height, bytes_per_line, bits_per_pixel)

    # Close display connection
    x11.XCloseDisplay(display)

def save_image(data, width, height, bytes_per_line, bits_per_pixel):
    # Ensure the system is little-endian
    is_little_endian = (struct.unpack('<I', b'\x01\x00\x00\x00')[0] == 1)
    if not is_little_endian:
        raise Exception("Only little-endian systems are supported")

    # Check bytes per pixel
    bytes_per_pixel = bits_per_pixel // 8
    if bytes_per_pixel not in [3, 4]:
        raise Exception(f"Unsupported bytes per pixel: {bytes_per_pixel}")

    # Write BMP header
    bmp_file_header = struct.pack('<2sIHHI', b'BM', 54 + width * height * 3, 0, 0, 54)
    bmp_info_header = struct.pack('<IiiHHIIiiII',
                                  40, width, -height, 1, 24, 0,
                                  width * height * 3, 0, 0, 0, 0)

    # Write pixel data
    with open('screenshot.bmp', 'wb') as f:
        f.write(bmp_file_header)
        f.write(bmp_info_header)

        for y in range(height):
            for x in range(width):
                offset = y * bytes_per_line + x * bytes_per_pixel
                # Pixels are in BGRA or BGR format
                blue = data[offset]
                green = data[offset + 1]
                red = data[offset + 2]
                # Skip alpha if 4 bytes per pixel
                if bytes_per_pixel == 4:
                    alpha = data[offset + 3]  # Read alpha, but ignore for BMP
                f.write(bytes([blue, green, red]))

try:
    capture_screen()
    print("Screenshot captured successfully.")
except Exception as e:
    print(f"Error capturing screenshot: {e}")
