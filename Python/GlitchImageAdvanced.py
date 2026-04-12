#!/usr/bin/env python3
"""
Batch Image Glitcher - Process all images in wallpapers directory

Features:
  - 16 glitch effects (channel shift, pixel sort, scanlines, noise,
    block corruption, horizontal glitch, color corruption, JPEG artifacts,
    chromatic aberration, interlace, data bending, VHS tracking,
    posterization, wave distortion, RGB channel swap, ghost/echo)
  - CLI arguments for full control
  - Reproducible results via seed logging
  - Multi-pass mode for heavy destruction
  - Parallel batch processing
  - EXIF/metadata preservation
  - Animated GIF support (per-frame glitching)
  - Preview contact-sheet generation
"""

import numpy as np
from PIL import Image, ImageDraw, ImageFont
import random
import uuid
import os
import glob
import io
import json
import argparse
import struct
import math
from concurrent.futures import ProcessPoolExecutor, as_completed
from datetime import datetime


# ---------------------------------------------------------------------------
# EFFECTS
# ---------------------------------------------------------------------------

def channel_shift(img_array, shift_amount=20):
    """Shift RGB channels to create color distortion"""
    result = img_array.copy()
    if shift_amount >= result.shape[1]:
        shift_amount = max(1, result.shape[1] // 10)
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

    ys = np.random.randint(0, height, num_pixels)
    xs = np.random.randint(0, width, num_pixels)
    colors = np.random.randint(0, 256, (num_pixels, 3), dtype=np.uint8)
    result[ys, xs] = colors

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
                result[y:y+block_height, x:x+block_width] = \
                    result[y:y+block_height, x+shift:x+shift+block_width]

        elif corruption_type == 'duplicate':
            source_y = random.randint(0, max(0, height - block_height))
            result[y:y+block_height, x:x+block_width] = \
                result[source_y:source_y+block_height, x:x+block_width]

        elif corruption_type == 'noise':
            result[y:y+block_height, x:x+block_width] = \
                np.random.randint(0, 255, (block_height, block_width, 3))

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
                result[y, start_x:end_x, channel] = \
                    255 - result[y, start_x:end_x, channel]

    return np.clip(result, 0, 255).astype(np.uint8)


# ---- NEW EFFECTS ----------------------------------------------------------

def jpeg_artifacts(img_array, quality=5):
    """Simulate heavy JPEG compression artifacts"""
    img = Image.fromarray(img_array)
    buf = io.BytesIO()
    img.save(buf, format='JPEG', quality=quality)
    buf.seek(0)
    return np.array(Image.open(buf).convert('RGB'))


def chromatic_aberration(img_array, offset=6):
    """Offset each channel with slight scaling for rainbow fringing"""
    h, w = img_array.shape[:2]
    result = np.zeros_like(img_array)

    # Red channel – shift right and down
    result[offset:, offset:, 0] = img_array[:h-offset, :w-offset, 0]
    # Green channel – keep centered
    result[:, :, 1] = img_array[:, :, 1]
    # Blue channel – shift left and up
    result[:h-offset, :w-offset, 2] = img_array[offset:, offset:, 2]

    return result


def interlace(img_array, shift=8):
    """Interlace / field-separation effect"""
    result = img_array.copy()
    shifted = np.roll(img_array, shift, axis=1)
    result[1::2] = shifted[1::2]  # every other row from the shifted copy
    return result


def data_bend(img_array, num_corruptions=20):
    """Save to BMP bytes, corrupt the data region, reload"""
    img = Image.fromarray(img_array)
    buf = io.BytesIO()
    img.save(buf, format='BMP')
    data = bytearray(buf.getvalue())

    # BMP pixel data offset is at bytes 10-13 (little-endian)
    pixel_offset = struct.unpack_from('<I', data, 10)[0]
    data_len = len(data)

    for _ in range(num_corruptions):
        pos = random.randint(pixel_offset + 100, max(pixel_offset + 101, data_len - 4))
        corruption = random.choice(['swap', 'set', 'xor'])
        if corruption == 'swap' and pos + 1 < data_len:
            data[pos], data[pos+1] = data[pos+1], data[pos]
        elif corruption == 'set':
            data[pos] = random.randint(0, 255)
        elif corruption == 'xor':
            data[pos] ^= random.randint(1, 255)

    try:
        buf2 = io.BytesIO(bytes(data))
        return np.array(Image.open(buf2).convert('RGB'))
    except Exception:
        return img_array  # fallback if corruption breaks the file


def vhs_tracking(img_array, wobble_amp=12, color_bleed=3):
    """VHS tracking effect: horizontal wobble + color bleed + noise band"""
    h, w = img_array.shape[:2]
    result = img_array.copy().astype(float)

    # Horizontal wobble per row
    for y in range(h):
        shift = int(wobble_amp * math.sin(y * 0.03 + random.random() * 2))
        result[y] = np.roll(result[y], shift, axis=0)

    # Color bleed: smear red channel horizontally
    for _ in range(color_bleed):
        result[:, 1:, 0] = result[:, 1:, 0] * 0.5 + result[:, :-1, 0] * 0.5

    # Random noisy tracking band
    band_y = random.randint(0, max(0, h - 40))
    band_h = random.randint(15, 40)
    result[band_y:band_y+band_h] = (
        result[band_y:band_y+band_h] * 0.3
        + np.random.randint(0, 100, (min(band_h, h - band_y), w, 3)) * 0.7
    )

    return np.clip(result, 0, 255).astype(np.uint8)


def posterize(img_array, levels=4):
    """Reduce bit depth / posterization"""
    factor = 256 // max(levels, 2)
    return ((img_array // factor) * factor).astype(np.uint8)


def wave_distortion(img_array, amplitude=12, frequency=0.02):
    """Displace rows with a sine wave"""
    result = img_array.copy()
    h = result.shape[0]
    phase = random.uniform(0, 2 * math.pi)

    for y in range(h):
        shift = int(amplitude * math.sin(y * frequency + phase))
        result[y] = np.roll(result[y], shift, axis=0)

    return result


def rgb_channel_swap(img_array):
    """Randomly remap RGB channels"""
    order = list(range(3))
    random.shuffle(order)
    # Make sure it's actually different
    while order == [0, 1, 2]:
        random.shuffle(order)
    return img_array[:, :, order]


def ghost_echo(img_array, offset_x=15, offset_y=10, alpha=0.4):
    """Blend the image with a shifted, semi-transparent copy"""
    h, w = img_array.shape[:2]
    result = img_array.copy().astype(float)

    ghost = np.zeros_like(result)
    src_y = slice(max(0, -offset_y), min(h, h - offset_y))
    src_x = slice(max(0, -offset_x), min(w, w - offset_x))
    dst_y = slice(max(0, offset_y), min(h, h + offset_y))
    dst_x = slice(max(0, offset_x), min(w, w + offset_x))

    ghost[dst_y, dst_x] = img_array[src_y, src_x]
    result = result * (1 - alpha) + ghost * alpha

    return np.clip(result, 0, 255).astype(np.uint8)


# ---------------------------------------------------------------------------
# EFFECT REGISTRY  (name -> function)
# ---------------------------------------------------------------------------

ALL_EFFECTS = {
    'channel_shift':        channel_shift,
    'pixel_sort':           pixel_sort,
    'scanlines':            scanlines,
    'random_noise':         random_noise,
    'block_corruption':     block_corruption,
    'horizontal_glitch':    horizontal_glitch,
    'color_corruption':     color_corruption,
    'jpeg_artifacts':       jpeg_artifacts,
    'chromatic_aberration':  chromatic_aberration,
    'interlace':            interlace,
    'data_bend':            data_bend,
    'vhs_tracking':         vhs_tracking,
    'posterize':            posterize,
    'wave_distortion':      wave_distortion,
    'rgb_channel_swap':     rgb_channel_swap,
    'ghost_echo':           ghost_echo,
}


# ---------------------------------------------------------------------------
# GLITCH PIPELINE
# ---------------------------------------------------------------------------

def build_params(intensity_level):
    """Build effect parameters for a given intensity level"""
    if intensity_level == 'light':
        return {
            'shift': random.randint(5, 15),
            'sort_intensity': random.uniform(0.1, 0.2),
            'noise': random.uniform(0.005, 0.015),
            'blocks': random.randint(5, 12),
            'h_glitches': random.randint(3, 8),
            'color': random.uniform(0.1, 0.2),
            'jpeg_q': random.randint(8, 15),
            'chroma_offset': random.randint(2, 5),
            'interlace_shift': random.randint(3, 8),
            'data_corruptions': random.randint(8, 15),
            'vhs_wobble': random.randint(4, 10),
            'poster_levels': random.randint(6, 10),
            'wave_amp': random.randint(4, 10),
            'wave_freq': random.uniform(0.01, 0.025),
            'ghost_ox': random.randint(5, 12),
            'ghost_oy': random.randint(3, 8),
            'ghost_alpha': random.uniform(0.15, 0.3),
        }
    elif intensity_level == 'heavy':
        return {
            'shift': random.randint(25, 40),
            'sort_intensity': random.uniform(0.4, 0.6),
            'noise': random.uniform(0.03, 0.05),
            'blocks': random.randint(20, 30),
            'h_glitches': random.randint(15, 25),
            'color': random.uniform(0.4, 0.6),
            'jpeg_q': random.randint(1, 4),
            'chroma_offset': random.randint(10, 20),
            'interlace_shift': random.randint(15, 30),
            'data_corruptions': random.randint(40, 80),
            'vhs_wobble': random.randint(20, 35),
            'poster_levels': random.randint(2, 3),
            'wave_amp': random.randint(20, 40),
            'wave_freq': random.uniform(0.03, 0.06),
            'ghost_ox': random.randint(20, 40),
            'ghost_oy': random.randint(15, 30),
            'ghost_alpha': random.uniform(0.45, 0.65),
        }
    else:  # medium
        return {
            'shift': random.randint(15, 25),
            'sort_intensity': random.uniform(0.25, 0.35),
            'noise': random.uniform(0.015, 0.025),
            'blocks': random.randint(12, 20),
            'h_glitches': random.randint(8, 15),
            'color': random.uniform(0.25, 0.35),
            'jpeg_q': random.randint(3, 8),
            'chroma_offset': random.randint(5, 10),
            'interlace_shift': random.randint(8, 15),
            'data_corruptions': random.randint(15, 40),
            'vhs_wobble': random.randint(10, 20),
            'poster_levels': random.randint(3, 6),
            'wave_amp': random.randint(10, 20),
            'wave_freq': random.uniform(0.02, 0.04),
            'ghost_ox': random.randint(12, 20),
            'ghost_oy': random.randint(8, 15),
            'ghost_alpha': random.uniform(0.3, 0.45),
        }


def _effect_call(effect_name, img_array, params):
    """Dispatch a single effect by name"""
    p = params
    dispatch = {
        'channel_shift':       lambda a: channel_shift(a, p['shift']),
        'pixel_sort':          lambda a: pixel_sort(a, p['sort_intensity']),
        'horizontal_glitch':   lambda a: horizontal_glitch(a, p['h_glitches']),
        'block_corruption':    lambda a: block_corruption(a, p['blocks']),
        'scanlines':           lambda a: scanlines(a),
        'color_corruption':    lambda a: color_corruption(a, p['color']),
        'random_noise':        lambda a: random_noise(a, p['noise']),
        'jpeg_artifacts':      lambda a: jpeg_artifacts(a, p['jpeg_q']),
        'chromatic_aberration': lambda a: chromatic_aberration(a, p['chroma_offset']),
        'interlace':           lambda a: interlace(a, p['interlace_shift']),
        'data_bend':           lambda a: data_bend(a, p['data_corruptions']),
        'vhs_tracking':        lambda a: vhs_tracking(a, p['vhs_wobble']),
        'posterize':           lambda a: posterize(a, p['poster_levels']),
        'wave_distortion':     lambda a: wave_distortion(a, p['wave_amp'], p['wave_freq']),
        'rgb_channel_swap':    lambda a: rgb_channel_swap(a),
        'ghost_echo':          lambda a: ghost_echo(a, p['ghost_ox'], p['ghost_oy'], p['ghost_alpha']),
    }
    return dispatch[effect_name](img_array)


# Probability that each effect is selected when running random selection
EFFECT_PROBABILITIES = {
    'channel_shift':       0.80,
    'pixel_sort':          0.70,
    'horizontal_glitch':   0.80,
    'block_corruption':    0.70,
    'scanlines':           0.50,
    'color_corruption':    0.70,
    'random_noise':        0.60,
    'jpeg_artifacts':      0.45,
    'chromatic_aberration': 0.55,
    'interlace':           0.40,
    'data_bend':           0.35,
    'vhs_tracking':        0.40,
    'posterize':           0.35,
    'wave_distortion':     0.50,
    'rgb_channel_swap':    0.30,
    'ghost_echo':          0.45,
}


def apply_random_glitches(img_array, intensity_level='random',
                          only_effects=None, passes=1):
    """
    Apply a random selection of glitch effects.

    Parameters
    ----------
    img_array : np.ndarray
    intensity_level : str  ('light', 'medium', 'heavy', or 'random')
    only_effects : list[str] | None
        If given, only these effects can be selected.
    passes : int
        How many times the full pipeline is run (multi-pass mode).

    Returns
    -------
    (np.ndarray, dict)
        Glitched image array and a metadata dict describing what was applied.
    """
    if intensity_level == 'random':
        intensity_level = random.choice(['light', 'medium', 'heavy'])

    params = build_params(intensity_level)

    # Select effects
    available = list(EFFECT_PROBABILITIES.keys())
    if only_effects:
        available = [e for e in available if e in only_effects]

    applied_effects = []
    for pass_num in range(passes):
        effects = []
        for name in available:
            prob = EFFECT_PROBABILITIES.get(name, 0.5)
            if random.random() < prob:
                effects.append(name)

        random.shuffle(effects)

        result = img_array if pass_num == 0 else result  # noqa: F821
        for effect_name in effects:
            try:
                result = _effect_call(effect_name, result, params)
            except Exception as e:
                print(f"      [warn] effect '{effect_name}' failed: {e}")

        applied_effects.append(effects)

    meta = {
        'intensity': intensity_level,
        'passes': passes,
        'effects_per_pass': applied_effects,
    }

    return result, meta


# ---------------------------------------------------------------------------
# GIF SUPPORT
# ---------------------------------------------------------------------------

def process_gif(image_path, output_path, intensity_level='random',
                only_effects=None, passes=1, seed=None):
    """Glitch each frame of an animated GIF and save a new GIF."""
    img = Image.open(image_path)
    frames = []
    durations = []

    try:
        while True:
            durations.append(img.info.get('duration', 100))
            frame = img.convert('RGB')
            arr = np.array(frame)

            if seed is not None:
                random.seed(seed)
                np.random.seed(seed & 0xFFFFFFFF)

            glitched, _ = apply_random_glitches(
                arr, intensity_level=intensity_level,
                only_effects=only_effects, passes=passes,
            )
            frames.append(Image.fromarray(glitched))
            img.seek(img.tell() + 1)
    except EOFError:
        pass

    if frames:
        frames[0].save(
            output_path, save_all=True, append_images=frames[1:],
            duration=durations, loop=img.info.get('loop', 0),
        )

    return len(frames)


# ---------------------------------------------------------------------------
# PREVIEW / CONTACT SHEET
# ---------------------------------------------------------------------------

def make_contact_sheet(pairs, thumb_width=480, columns=2, output_path='contact_sheet.jpg'):
    """
    Generate a contact sheet showing original vs glitched side-by-side.

    Parameters
    ----------
    pairs : list of (original_path, glitched_path)
    thumb_width : int  width of each thumbnail
    columns : int  number of pair-columns (each pair = 2 images)
    output_path : str
    """
    if not pairs:
        return

    thumbs = []
    for orig_path, glitch_path in pairs:
        try:
            orig = Image.open(orig_path).convert('RGB')
            glitched = Image.open(glitch_path).convert('RGB')

            # Resize to consistent thumbnail width
            aspect = orig.height / orig.width
            th = int(thumb_width * aspect)
            orig_thumb = orig.resize((thumb_width, th), Image.LANCZOS)
            glitched_thumb = glitched.resize((thumb_width, th), Image.LANCZOS)
            thumbs.append((orig_thumb, glitched_thumb, os.path.basename(orig_path)))
        except Exception:
            continue

    if not thumbs:
        return

    padding = 10
    label_height = 24
    pair_width = thumb_width * 2 + padding
    col_width = pair_width + padding

    rows = math.ceil(len(thumbs) / columns)

    # Compute max thumb height per row
    row_heights = []
    for r in range(rows):
        max_h = 0
        for c in range(columns):
            idx = r * columns + c
            if idx < len(thumbs):
                max_h = max(max_h, thumbs[idx][0].height)
        row_heights.append(max_h)

    total_w = col_width * columns + padding
    total_h = sum(h + padding + label_height for h in row_heights) + padding

    sheet = Image.new('RGB', (total_w, total_h), (30, 30, 30))
    draw = ImageDraw.Draw(sheet)

    y_offset = padding
    for r in range(rows):
        for c in range(columns):
            idx = r * columns + c
            if idx >= len(thumbs):
                break
            orig_t, glitch_t, name = thumbs[idx]
            x_offset = padding + c * col_width

            # Label
            label = f"{name}"
            draw.text((x_offset, y_offset), label, fill=(200, 200, 200))

            # Original
            sheet.paste(orig_t, (x_offset, y_offset + label_height))
            # Glitched
            sheet.paste(glitch_t, (x_offset + thumb_width + padding, y_offset + label_height))

        y_offset += row_heights[r] + padding + label_height

    sheet.save(output_path, quality=92)
    print(f"  ✓ Contact sheet saved: {output_path}")


# ---------------------------------------------------------------------------
# SINGLE IMAGE PROCESSING (used by both serial and parallel paths)
# ---------------------------------------------------------------------------

def _build_output_name(original_path, ext, max_len=60):
    """Build output filename: name_uuid.ext, truncated to max_len chars."""
    stem = os.path.splitext(os.path.basename(original_path))[0]
    short_id = uuid.uuid4().hex[:8]
    # Reserve space for: _<8-char-id><ext>
    suffix = f'_{short_id}{ext}'
    max_stem = max_len - len(suffix)
    if max_stem < 1:
        max_stem = 1
    stem = stem[:max_stem]
    return f'{stem}{suffix}'


def process_single_image(image_path, output_dir, intensity_level='random',
                         only_effects=None, passes=1, seed=None,
                         preserve_exif=False, make_gif=False):
    """
    Process one image. Returns (original_path, output_path, meta_dict) or None on failure.
    """
    try:
        # Seed for reproducibility
        if seed is not None:
            random.seed(seed)
            np.random.seed(seed & 0xFFFFFFFF)

        original_ext = os.path.splitext(image_path)[1].lower()

        # Animated GIF handling
        if original_ext == '.gif' and make_gif:
            out_name = _build_output_name(image_path, '.gif')
            output_path = os.path.join(output_dir, out_name)
            n_frames = process_gif(
                image_path, output_path,
                intensity_level=intensity_level,
                only_effects=only_effects,
                passes=passes, seed=seed,
            )
            meta = {'frames': n_frames, 'gif': True}
            return image_path, output_path, meta

        # Standard still image
        output_ext = original_ext if original_ext in ('.jpg', '.jpeg', '.png') else '.png'
        out_name = _build_output_name(image_path, output_ext)
        output_path = os.path.join(output_dir, out_name)

        img = Image.open(image_path)
        exif_data = None
        if preserve_exif:
            exif_data = img.info.get('exif')

        if img.mode != 'RGB':
            img = img.convert('RGB')

        img_array = np.array(img)
        glitched_array, meta = apply_random_glitches(
            img_array,
            intensity_level=intensity_level,
            only_effects=only_effects,
            passes=passes,
        )

        result_img = Image.fromarray(glitched_array)

        save_kwargs = {'quality': 95}
        if exif_data:
            save_kwargs['exif'] = exif_data

        result_img.save(output_path, **save_kwargs)

        meta['seed'] = seed
        return image_path, output_path, meta

    except Exception as e:
        print(f"    ✗ Error processing {image_path}: {e}")
        return None


# ---------------------------------------------------------------------------
# BATCH PROCESSING
# ---------------------------------------------------------------------------

def collect_images(input_dir):
    """Return a list of image file paths found in input_dir."""
    image_extensions = ['*.jpg', '*.jpeg', '*.png', '*.bmp', '*.gif', '*.webp']
    image_files = []
    for ext in image_extensions:
        image_files.extend(glob.glob(os.path.join(input_dir, ext)))
        image_files.extend(glob.glob(os.path.join(input_dir, ext.upper())))
    return sorted(set(image_files))


def process_wallpapers(args):
    """Main batch processing routine."""

    input_dir = args.input_dir
    output_dir = args.output_dir
    os.makedirs(output_dir, exist_ok=True)

    image_files = collect_images(input_dir)
    if not image_files:
        print(f"No images found in {input_dir}")
        return

    print(f"Found {len(image_files)} images to process")
    print(f"  Intensity : {args.intensity}")
    print(f"  Passes    : {args.passes}")
    print(f"  Workers   : {args.workers}")
    if args.effects:
        print(f"  Effects   : {', '.join(args.effects)}")
    if args.seed is not None:
        print(f"  Base seed : {args.seed}")
    print("-" * 56)

    results = []   # (orig_path, output_path)
    log_entries = []

    only_effects = args.effects if args.effects else None

    def _make_seed(index):
        if args.seed is not None:
            return args.seed + index
        return random.randint(0, 2**31)

    # ----- parallel processing -----
    if args.workers > 1:
        futures = {}
        with ProcessPoolExecutor(max_workers=args.workers) as pool:
            for i, path in enumerate(image_files):
                seed = _make_seed(i)
                fut = pool.submit(
                    process_single_image, path, output_dir,
                    intensity_level=args.intensity,
                    only_effects=only_effects,
                    passes=args.passes,
                    seed=seed,
                    preserve_exif=args.preserve_exif,
                    make_gif=args.gif,
                )
                futures[fut] = (i, path, seed)

            for fut in as_completed(futures):
                i, path, seed = futures[fut]
                res = fut.result()
                if res:
                    orig, out, meta = res
                    print(f"  [{i+1}/{len(image_files)}] {os.path.basename(orig)} -> {os.path.basename(out)}")
                    results.append((orig, out))
                    log_entries.append({
                        'original': orig,
                        'output': out,
                        'seed': seed,
                        **meta,
                    })
    # ----- serial processing -----
    else:
        for i, path in enumerate(image_files):
            seed = _make_seed(i)
            print(f"  [{i+1}/{len(image_files)}] Processing: {os.path.basename(path)}")
            res = process_single_image(
                path, output_dir,
                intensity_level=args.intensity,
                only_effects=only_effects,
                passes=args.passes,
                seed=seed,
                preserve_exif=args.preserve_exif,
                make_gif=args.gif,
            )
            if res:
                orig, out, meta = res
                print(f"    ✓ Saved: {os.path.basename(out)}")
                results.append((orig, out))
                log_entries.append({
                    'original': orig,
                    'output': out,
                    'seed': seed,
                    **meta,
                })

    # ----- write log -----
    log_path = os.path.join(output_dir, 'glitch_log.json')
    with open(log_path, 'w') as f:
        json.dump({
            'timestamp': datetime.now().isoformat(),
            'args': vars(args),
            'images': log_entries,
        }, f, indent=2)
    print(f"  ✓ Log saved: {log_path}")

    # ----- contact sheet -----
    if args.contact_sheet and results:
        sheet_path = os.path.join(output_dir, 'contact_sheet.jpg')
        make_contact_sheet(results, output_path=sheet_path)

    print("-" * 56)
    print(f"✓ Done — {len(results)}/{len(image_files)} images processed -> {output_dir}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args():
    parser = argparse.ArgumentParser(
        description='Batch Image Glitcher — apply glitch art effects to images',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"Available effects:\n  {', '.join(sorted(ALL_EFFECTS.keys()))}",
    )

    parser.add_argument(
        '-i', '--input-dir', default='./wallpapers',
        help='Directory containing source images (default: ./wallpapers)',
    )
    parser.add_argument(
        '-o', '--output-dir', default='./glitched',
        help='Directory for glitched output (default: ./glitched)',
    )
    parser.add_argument(
        '--intensity', choices=['light', 'medium', 'heavy', 'random'],
        default='random',
        help='Glitch intensity level (default: random)',
    )
    parser.add_argument(
        '--effects', nargs='+', metavar='EFFECT',
        choices=sorted(ALL_EFFECTS.keys()),
        help='Only apply these specific effects',
    )
    parser.add_argument(
        '--passes', type=int, default=1,
        help='Number of glitch passes per image (default: 1)',
    )
    parser.add_argument(
        '--seed', type=int, default=None,
        help='Base random seed for reproducibility',
    )
    parser.add_argument(
        '--workers', type=int, default=1,
        help='Number of parallel workers (default: 1 = serial)',
    )
    parser.add_argument(
        '--preserve-exif', action='store_true',
        help='Copy EXIF metadata from originals to outputs',
    )
    parser.add_argument(
        '--gif', action='store_true',
        help='Process animated GIFs frame-by-frame',
    )
    parser.add_argument(
        '--contact-sheet', action='store_true',
        help='Generate a side-by-side preview grid (contact_sheet.jpg)',
    )
    parser.add_argument(
        '--list-effects', action='store_true',
        help='List all available effects and exit',
    )

    args = parser.parse_args()

    if args.list_effects:
        print("Available effects:")
        for name in sorted(ALL_EFFECTS.keys()):
            doc = ALL_EFFECTS[name].__doc__ or ''
            print(f"  {name:24s}  {doc.strip().split(chr(10))[0]}")
        raise SystemExit(0)

    return args


# ---------------------------------------------------------------------------
# ENTRY POINT
# ---------------------------------------------------------------------------

if __name__ == '__main__':
    args = parse_args()
    process_wallpapers(args)
