import sys
from PIL import Image
import pytesseract

def load_image(path):
    """Load an image from a file path."""
    return Image.open(path)

def resize_image(image, scale_factor=0.25):
    """Resize image by a scale factor."""
    new_size = (int(image.width * scale_factor), int(image.height * scale_factor))
    return image.resize(new_size, Image.Resampling.LANCZOS)

def extract_text(image):
    """Extract text from an image using Tesseract."""
    return pytesseract.image_to_string(image)

def main():
    if len(sys.argv) != 2:
        print("Usage: python script.py <image_path>")
        sys.exit(1)

    image_path = sys.argv[1]

    try:
        original_img = load_image(image_path)
    except Exception as e:
        print(f"Error loading image: {e}")
        sys.exit(1)

    # Resize and extract text
    resized_img = resize_image(original_img)

    print("Text from resized image:\n")
    print(extract_text(resized_img))
    print("\n" + "="*50 + "\n")

    print("Text from original image:\n")
    print(extract_text(original_img))

if __name__ == "__main__":
    main()
