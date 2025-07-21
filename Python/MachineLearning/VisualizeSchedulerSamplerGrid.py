import os
from PIL import Image, ImageDraw, ImageFont

# Define the path where images are stored
image_dir = '/home/user/Downloads/generated_images/generated_images2'

# List of scheduler names and sampler names to organize the grid
schedulers = ["DDIM", "DPM2_a", "DPM2", "DPM++_2M", "DPM++_2M_SDE", "DPM++_SDE_Heun", "Euler_a", "Euler", "Heun", "LCM", "LMS", "PLMS", "Restart", "UniPC"]
samplers = ["Align Your Steps", "Automatic", "Beta", "DDIM", "Exponential", "Karras", "KL Optimal", "Normal", "Polyexponential", "SGM Uniform", "Simple", "Uniform"]

# Define image size (assuming all images are the same size)
image_size = (512, 712)  # Modify this to the actual size of your images
label_height = 80  # Space for two lines of text (scheduler and sampler) under each image

# Padding for row and column labels (this space will be reserved for the text labels)
label_padding = 100

# Prepare a dictionary to hold the images sorted by scheduler and sampler
image_grid = {scheduler: {sampler: None for sampler in samplers} for scheduler in schedulers}

# Load images and place them into the correct position in the grid
for file_name in os.listdir(image_dir):
    if file_name.endswith(".png"):  # Only consider PNG images
        # Parse the file name to extract scheduler and sampler
        for scheduler in schedulers:
            if file_name.startswith(scheduler):
                for sampler in samplers:
                    if sampler in file_name:
                        # Open the image and store it in the grid
                        image_path = os.path.join(image_dir, file_name)
                        image_grid[scheduler][sampler] = Image.open(image_path).resize(image_size)
                        break

# Calculate the final grid size (with padding for labels and additional height for image labels)
grid_width = len(samplers) * image_size[0] + label_padding
grid_height = len(schedulers) * (image_size[1] + label_height) + label_padding

# Create a blank canvas for the grid (white background)
grid_image = Image.new("RGB", (grid_width, grid_height), "white")

# Set up drawing context and font
draw = ImageDraw.Draw(grid_image)
try:
    font = ImageFont.truetype("arial.ttf", 40)  # Load a font (adjust size as necessary)
except IOError:
    font = ImageFont.load_default()  # Use default font if arial is not available

# Paste each image into the correct position on the canvas, and add labels (scheduler + sampler) to each image
for row_idx, scheduler in enumerate(schedulers):
    for col_idx, sampler in enumerate(samplers):
        # Paste the image at the calculated position
        img = image_grid[scheduler][sampler]
        if img:
            x_offset = label_padding + col_idx * image_size[0]
            y_offset = label_padding + row_idx * (image_size[1] + label_height)
            grid_image.paste(img, (x_offset, y_offset))

            # Combine scheduler and sampler labels
            img_label_1 = f"{scheduler}"  # Scheduler label
            img_label_2 = f"{sampler}"    # Sampler label

            # Get text width to center the label under the image
            bbox_1 = draw.textbbox((0, 0), img_label_1, font=font)
            text_width_1 = bbox_1[2] - bbox_1[0]
            bbox_2 = draw.textbbox((0, 0), img_label_2, font=font)
            text_width_2 = bbox_2[2] - bbox_2[0]

            # Draw both labels (scheduler and sampler) centered below each image
            draw.text(
                (x_offset + image_size[0] // 2 - text_width_1 // 2, y_offset + image_size[1] + 10),
                img_label_1,
                font=font,
                fill="black"
            )
            draw.text(
                (x_offset + image_size[0] // 2 - text_width_2 // 2, y_offset + image_size[1] + 10 + 40),  # 40 is used to move to the next line
                img_label_2,
                font=font,
                fill="black"
            )

# Save the final image grid with labels
grid_image.save("scheduler_sampler_grid_with_labels_below_each_image.png")
