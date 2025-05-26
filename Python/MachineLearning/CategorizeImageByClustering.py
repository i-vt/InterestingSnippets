import os
import time
import numpy as np
import cv2
import tensorflow as tf
from tensorflow.keras.applications import MobileNetV2
from tensorflow.keras.applications.mobilenet_v2 import preprocess_input
import pandas as pd
from sklearn.cluster import KMeans
from tqdm import tqdm

# Configuration
IMG_DIR = "/data"
IMAGE_SIZE = 224
BATCH_SIZE = 64
N_CLUSTERS = 30
OUTPUT_CSV = "/data/image_clusters.csv"

# Load model
print("🔧 Loading model...")
model = MobileNetV2(include_top=False, pooling='avg', input_shape=(IMAGE_SIZE, IMAGE_SIZE, 3))

# Load image paths
image_files = [os.path.join(IMG_DIR, fname) for fname in os.listdir(IMG_DIR)]
total_images = len(image_files)
print(f"🖼️ Found {total_images} images")

# Functions
def load_images_batch(img_paths):
    batch = []
    valid_paths = []

    for path in img_paths:
        img = cv2.imread(path)
        if img is None:
            continue
        img = cv2.resize(img, (IMAGE_SIZE, IMAGE_SIZE))
        img = preprocess_input(img.astype(np.float32))
        batch.append(img)
        valid_paths.append(path)

    return np.array(batch), valid_paths

# Feature extraction
print("🔍 Extracting features...")
start_time = time.time()

features = []
valid_filenames = []

for i in tqdm(range(0, total_images, BATCH_SIZE), desc="Processing batches"):
    batch_paths = image_files[i:i + BATCH_SIZE]
    imgs, paths = load_images_batch(batch_paths)
    if len(imgs) == 0:
        continue
    feats = model.predict(imgs, verbose=0)
    features.append(feats)
    valid_filenames.extend([os.path.basename(p) for p in paths])

features = np.concatenate(features, axis=0)
duration = time.time() - start_time
print(f"✅ Feature extraction completed in {duration:.2f} seconds")

# Clustering
print("🧠 Clustering with KMeans...")
start_time = time.time()
kmeans = KMeans(n_clusters=N_CLUSTERS, random_state=42)
labels = kmeans.fit_predict(features)
duration = time.time() - start_time
print(f"✅ Clustering completed in {duration:.2f} seconds")

# Save results
print(f"💾 Saving results to {OUTPUT_CSV}...")
df = pd.DataFrame({'filename': valid_filenames, 'cluster': labels})
df.to_csv(OUTPUT_CSV, index=False)
print("🎉 Done!")
