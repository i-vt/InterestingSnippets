import os

filepath = "./"  # or any starting directory
all_files = []

for root, dirs, files in os.walk(filepath):
    for file in files:
        full_path = os.path.abspath(os.path.join(root, file))
        all_files.append(full_path)

print(all_files)
