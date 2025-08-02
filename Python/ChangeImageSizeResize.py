import os
from PIL import Image

# Define source and destination directories
source_dir = './fullsize'               # current directory
destination_dir = '../smaller'  # target directory

# Create destination directory if it doesn't exist
os.makedirs(destination_dir, exist_ok=True)

# Loop through image files in the source directory
for filename in os.listdir(source_dir):
    if filename.lower().endswith(('.png', '.jpg', '.jpeg', '.webp', '.bmp')):
        img_path = os.path.join(source_dir, filename)
        img = Image.open(img_path)

        # Resize image to 500x500
        img_resized = img.resize((500, 500))

        # Save to destination directory
        save_path = os.path.join(destination_dir, filename)
        img_resized.save(save_path)

        print(f"Resized and saved: {save_path}")
