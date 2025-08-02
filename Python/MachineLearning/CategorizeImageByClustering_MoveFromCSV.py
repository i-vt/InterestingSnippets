import os
import shutil
import pandas as pd

# Config
CSV_PATH = './image_clusters1.csv'     # Input CSV with filenames and cluster numbers
INGESTION_DIR = '/home/User/Documents/Memes'            # Folder containing original images
OUTPUT_DIR = './sorted1/'      # Destination folder for clustered images

# Load CSV
df = pd.read_csv(CSV_PATH)

# Ensure output directory exists
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Move images
for _, row in df.iterrows():
    filename = row['filename']
    cluster = str(row['cluster'])

    src_path = os.path.join(INGESTION_DIR, filename)
    cluster_dir = os.path.join(OUTPUT_DIR, cluster)
    dst_path = os.path.join(cluster_dir, filename)

    # Create cluster folder if it doesn't exist
    os.makedirs(cluster_dir, exist_ok=True)

    # Move file
    if os.path.exists(src_path):
        shutil.copy2(src_path, dst_path)
    else:
        print(f"⚠️ File not found: {src_path}")

print("✅ Images moved to cluster folders.")
