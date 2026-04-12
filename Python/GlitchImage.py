#!/usr/bin/env python3
"""
Batch Image Glitcher - Process all images in wallpapers directory
"""

import numpy as np
from PIL import Image
import random
import uuid
import os
import glob


def channel_shift(img_array, shift_amount=20):
    """Shift RGB channels to create color distortion"""
    result = img_array.copy()
    result[:, shift_amount:, 0] = img_array[:, :-shift_amount, 0]
    result[:, :-shift_amount, 2] = img_array[:, shift_amount:, 2]
    return result


def pixel_sort(img_array, intensity=0.3):
    """Sort pixels in random rows/columns for a glitch effect"""
    result = img_array.copy()
    height, width = result.shape[:2]
    
    for _ in range(int(height * intensity)):
        row = random.randint(0, height - 1)
        start_col = random.randint(0, max(0, width - 100))
        end_col = start_col + random.randint(50, min(200, width - start_col))
        end_col = min(end_col, width)
        
        if end_col > start_col:
            segment = result[row, start_col:end_col]
            brightness = np.sum(segment, axis=1)
            sorted_indices = np.argsort(brightness)
            result[row, start_col:end_col] = segment[sorted_indices]
    
    return result


def scanlines(img_array, line_spacing=4, intensity=0.5):
    """Add scanline effect"""
    result = img_array.copy().astype(float)
    for i in range(0, result.shape[0], line_spacing):
        result[i] *= (1 - intensity)
    return np.clip(result, 0, 255).astype(np.uint8)


def random_noise(img_array, amount=0.02):
    """Add random pixel noise"""
    result = img_array.copy()
    height, width = result.shape[:2]
    num_pixels = int(height * width * amount)
    
    for _ in range(num_pixels):
        x = random.randint(0, width - 1)
        y = random.randint(0, height - 1)
        result[y, x] = [random.randint(0, 255) for _ in range(3)]
    
    return result


def block_corruption(img_array, num_blocks=15):
    """Corrupt random blocks of the image"""
    result = img_array.copy()
    height, width = result.shape[:2]
    
    for _ in range(num_blocks):
        block_height = random.randint(5, 50)
        block_width = random.randint(20, 150)
        
        y = random.randint(0, max(0, height - block_height))
        x = random.randint(0, max(0, width - block_width))
        
        corruption_type = random.choice(['shift', 'duplicate', 'noise', 'color'])
        
        if corruption_type == 'shift':
            shift = random.randint(-30, 30)
            if 0 <= x + shift < width - block_width:
                result[y:y+block_height, x:x+block_width] = result[y:y+block_height, x+shift:x+shift+block_width]
        
        elif corruption_type == 'duplicate':
            source_y = random.randint(0, max(0, height - block_height))
            result[y:y+block_height, x:x+block_width] = result[source_y:source_y+block_height, x:x+block_width]
        
        elif corruption_type == 'noise':
            result[y:y+block_height, x:x+block_width] = np.random.randint(0, 255, (block_height, block_width, 3))
        
        elif corruption_type == 'color':
            color = [random.randint(0, 255) for _ in range(3)]
            result[y:y+block_height, x:x+block_width] = color
    
    return result


def horizontal_glitch(img_array, num_glitches=10):
    """Create horizontal line displacement glitches"""
    result = img_array.copy()
    height, width = result.shape[:2]
    
    for _ in range(num_glitches):
        y = random.randint(0, height - 1)
        glitch_height = random.randint(1, 10)
        shift = random.randint(-50, 50)
        
        if y + glitch_height < height:
            row_section = result[y:y+glitch_height].copy()
            result[y:y+glitch_height] = np.roll(row_section, shift, axis=1)
    
    return result


def color_corruption(img_array, intensity=0.3):
    """Corrupt color channels randomly"""
    result = img_array.copy().astype(float)
    height, width = result.shape[:2]
    
    for _ in range(int(height * intensity)):
        y = random.randint(0, height - 1)
        start_x = random.randint(0, max(0, width - 50))
        end_x = start_x + random.randint(30, min(150, width - start_x))
        end_x = min(end_x, width)
        
        if end_x > start_x:
            channel = random.randint(0, 2)
            operation = random.choice(['add', 'multiply', 'invert'])
            
            if operation == 'add':
                result[y, start_x:end_x, channel] += random.randint(30, 100)
            elif operation == 'multiply':
                result[y, start_x:end_x, channel] *= random.uniform(1.5, 3.0)
            elif operation == 'invert':
                result[y, start_x:end_x, channel] = 255 - result[y, start_x:end_x, channel]
    
    return np.clip(result, 0, 255).astype(np.uint8)


def apply_random_glitches(img_array):
    """Apply a random selection of glitch effects"""
    
    # Randomly select intensity
    intensity_level = random.choice(['light', 'medium', 'heavy'])
    
    if intensity_level == 'light':
        params = {
            'shift': random.randint(5, 15),
            'sort_intensity': random.uniform(0.1, 0.2),
            'noise': random.uniform(0.005, 0.015),
            'blocks': random.randint(5, 12),
            'h_glitches': random.randint(3, 8),
            'color': random.uniform(0.1, 0.2)
        }
    elif intensity_level == 'heavy':
        params = {
            'shift': random.randint(25, 40),
            'sort_intensity': random.uniform(0.4, 0.6),
            'noise': random.uniform(0.03, 0.05),
            'blocks': random.randint(20, 30),
            'h_glitches': random.randint(15, 25),
            'color': random.uniform(0.4, 0.6)
        }
    else:  # medium
        params = {
            'shift': random.randint(15, 25),
            'sort_intensity': random.uniform(0.25, 0.35),
            'noise': random.uniform(0.015, 0.025),
            'blocks': random.randint(12, 20),
            'h_glitches': random.randint(8, 15),
            'color': random.uniform(0.25, 0.35)
        }
    
    # Randomly select which effects to apply
    effects = []
    
    if random.random() > 0.2:  # 80% chance
        effects.append(('channel_shift', params['shift']))
    if random.random() > 0.3:  # 70% chance
        effects.append(('pixel_sort', params['sort_intensity']))
    if random.random() > 0.2:  # 80% chance
        effects.append(('horizontal_glitch', params['h_glitches']))
    if random.random() > 0.3:  # 70% chance
        effects.append(('block_corruption', params['blocks']))
    if random.random() > 0.5:  # 50% chance
        effects.append(('scanlines', None))
    if random.random() > 0.3:  # 70% chance
        effects.append(('color_corruption', params['color']))
    if random.random() > 0.4:  # 60% chance
        effects.append(('random_noise', params['noise']))
    
    # Shuffle effects for variety
    random.shuffle(effects)
    
    # Apply selected effects
    result = img_array.copy()
    
    for effect_name, param in effects:
        if effect_name == 'channel_shift':
            result = channel_shift(result, param)
        elif effect_name == 'pixel_sort':
            result = pixel_sort(result, param)
        elif effect_name == 'horizontal_glitch':
            result = horizontal_glitch(result, param)
        elif effect_name == 'block_corruption':
            result = block_corruption(result, param)
        elif effect_name == 'scanlines':
            result = scanlines(result)
        elif effect_name == 'color_corruption':
            result = color_corruption(result, param)
        elif effect_name == 'random_noise':
            result = random_noise(result, param)
    
    return result


def process_wallpapers():
    """Process all images in ./wallpapers/ and save to ./glitched/"""
    
    # Create output directory
    os.makedirs('./glitched', exist_ok=True)
    
    # Find all image files
    image_extensions = ['*.jpg', '*.jpeg', '*.png', '*.bmp', '*.gif', '*.webp']
    image_files = []
    
    for ext in image_extensions:
        image_files.extend(glob.glob(f'./wallpapers/{ext}'))
        image_files.extend(glob.glob(f'./wallpapers/{ext.upper()}'))
    
    if not image_files:
        print("No images found in ./wallpapers/")
        return
    
    print(f"Found {len(image_files)} images to process")
    print("-" * 50)
    
    for i, image_path in enumerate(image_files, 1):
        try:
            # Generate UUID for output filename
            unique_id = str(uuid.uuid4())
            
            # Get original extension
            original_ext = os.path.splitext(image_path)[1]
            output_ext = original_ext if original_ext.lower() in ['.jpg', '.jpeg', '.png'] else '.png'
            
            output_path = f'./glitched/uuid_{unique_id}{output_ext}'
            
            print(f"[{i}/{len(image_files)}] Processing: {os.path.basename(image_path)}")
            
            # Load image
            img = Image.open(image_path)
            
            # Convert to RGB if necessary
            if img.mode != 'RGB':
                img = img.convert('RGB')
            
            img_array = np.array(img)
            
            # Apply random glitches
            glitched_array = apply_random_glitches(img_array)
            
            # Save result
            result_img = Image.fromarray(glitched_array)
            result_img.save(output_path, quality=95)
            
            print(f"    ✓ Saved: {os.path.basename(output_path)}")
            
        except Exception as e:
            print(f"    ✗ Error processing {image_path}: {str(e)}")
    
    print("-" * 50)
    print(f"✓ Processing complete! Check ./glitched/ directory")


if __name__ == '__main__':
    process_wallpapers()
