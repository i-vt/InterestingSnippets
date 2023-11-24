from PIL import Image

def remove_metadata(image_path, output_path):
  
    with Image.open(image_path) as img:
        data = img.getdata()
        new_img = Image.new(img.mode, img.size)
        new_img.putdata(data)

        # Save the image without metadata
        new_img.save(output_path, "JPEG")  
      
remove_metadata("path/to/your/image.jpg", "path/to/save/new_image.jpg")
