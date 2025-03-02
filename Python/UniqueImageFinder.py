import cv2
import numpy as np
import argparse
import os
import shutil
from itertools import combinations
from tqdm import tqdm  # Import tqdm for progress bar

def calculate_image_difference(image1_path, image2_path):
    img1 = cv2.imread(image1_path)
    img2 = cv2.imread(image2_path)

    if img1 is None or img2 is None:
        print(f"Error: Could not load one or both of the images: {image1_path}, {image2_path}")
        return None

    if img1.shape != img2.shape:
        img2 = cv2.resize(img2, (img1.shape[1], img1.shape[0]))

    gray1 = cv2.cvtColor(img1, cv2.COLOR_BGR2GRAY)
    gray2 = cv2.cvtColor(img2, cv2.COLOR_BGR2GRAY)

    difference = cv2.absdiff(gray1, gray2)
    _, diff_thresh = cv2.threshold(difference, 30, 255, cv2.THRESH_BINARY)

    num_diff_pixels = np.sum(diff_thresh == 255)
    total_pixels = diff_thresh.size

    percentage_diff = (num_diff_pixels / total_pixels) * 100

    return percentage_diff

def find_high_difference_images(directory, diff_threshold=10):
    files = [f for f in os.listdir(directory) if f.lower().endswith(('.png', '.jpg', '.jpeg'))]
    files = [os.path.join(directory, f) for f in files]
    unique_images = set()  # To track unique frames
    compared_images = set()  # To track already compared images

    # Add progress bar to track the progress of the pairwise comparison
    for img1_path, img2_path in tqdm(combinations(files, 2), desc="Comparing images", unit="pair"):
        # Skip comparisons where either image has already been compared
        if img1_path in compared_images or img2_path in compared_images:
            continue
        
        diff = calculate_image_difference(img1_path, img2_path)
        if diff is not None and diff >= diff_threshold:
            # Add both images to the unique set if they have at least the threshold difference
            unique_images.add(img1_path)
            unique_images.add(img2_path)
        
        # Mark these images as compared
        compared_images.add(img1_path)
        compared_images.add(img2_path)

    return list(unique_images)

def create_unique_folder(destination_folder='./unique'):
    # Check if the "unique" folder exists, and create it if it doesn't
    if not os.path.exists(destination_folder):
        os.makedirs(destination_folder)
        print(f"Created the folder: {destination_folder}")
    else:
        print(f"Folder {destination_folder} already exists.")

def move_images_to_unique_folder(images, destination_folder='./unique'):
    for img_path in images:
        # Get the image filename
        img_filename = os.path.basename(img_path)
        # Define the destination path
        destination_path = os.path.join(destination_folder, img_filename)
        # Copy the image to the unique folder
        shutil.copy(img_path, destination_path)
        print(f"Moved: {img_filename} to {destination_folder}")

def main():
    parser = argparse.ArgumentParser(description="Find images with at least 10% difference in a directory and move them to the 'unique' folder.")
    parser.add_argument("directory", type=str, help="Directory containing images to compare")
    args = parser.parse_args()

    # Create the 'unique' folder if it doesn't exist
    create_unique_folder()

    # Find images with at least a 10% difference
    unique_images = find_high_difference_images(args.directory)
    
    # Move the unique images to the 'unique' folder
    move_images_to_unique_folder(unique_images)

if __name__ == "__main__":
    main()
