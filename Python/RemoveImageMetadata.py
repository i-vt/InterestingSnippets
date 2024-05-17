from PIL import Image
import os

def remove_metadata(image_path, output_path):
  
    with Image.open(image_path) as img:
        if img.mode == 'RGBA':  # Check if image is in RGBA mode
            img = img.convert('RGB')  # Convert to RGB to remove transparency

        data = img.getdata()
        new_img = Image.new(img.mode, img.size)
        new_img.putdata(data)

        # Save the image without metadata
        new_img.save(output_path, "JPEG")  

def get_all_files(directory):
    file_list = []
    for root, dirs, files in os.walk(directory):
        for file in files:
            file_list.append(os.path.join(root, file))
    return file_list


def clean_directory(directory, image_extensions: list = ["jpg", "jpeg", "png"]):
    images_original = []
    images_cleaned = []
    
    for file in get_all_files(directory):
        extension = file.split(".")[-1]
        if extension in image_extensions:
            images_original.append(file)
            image_cleaned_name = os.path.join(os.path.dirname(file), "cleaned_" + os.path.basename(file))
            images_cleaned.append(image_cleaned_name)
            try:
                remove_metadata(file, image_cleaned_name)
            except Exception as ex:
                print(ex)
                if images_cleaned != 0 and images_original != 0:
                    images_cleaned[-1] = "FAILED TO OUTPUT"
                    print(f"FAILED TO OUTPUT: [{images_original[-1]}]")
            
        else: continue
    return images_original, images_cleaned


if __name__ == "__main__":
    laundermatdir = "/home/user/Projects/"
    original, cleaned = clean_directory(laundermatdir)
    for index in range(len(original)):
        print(original[index], " -> ", cleaned[index])
