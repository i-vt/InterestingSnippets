import os
import sys
import shutil
import pandas as pd

def main():
    if len(sys.argv) < 2:
        print("Usage: python script.py <data_dir> [csv_filename]")
        sys.exit(1)

    data_dir = sys.argv[1]
    csv_filename = sys.argv[2] if len(sys.argv) > 2 else "image_clusters.csv"

    csv_path = os.path.join(data_dir, csv_filename)
    output_base = os.path.join(data_dir, "clustered")

    # Read CSV
    df = pd.read_csv(csv_path)

    # Create output folders and move files
    for _, row in df.iterrows():
        filename = row['filename']
        cluster = str(row['cluster'])

        src_path = os.path.join(data_dir, filename)
        dst_dir = os.path.join(output_base, cluster)
        dst_path = os.path.join(dst_dir, filename)

        if not os.path.exists(dst_dir):
            os.makedirs(dst_dir)

        if os.path.exists(src_path):
            shutil.move(src_path, dst_path)
        else:
            print(f"⚠️ File not found: {src_path}")

    print("✅ All files moved into cluster folders.")

if __name__ == "__main__":
    main()
