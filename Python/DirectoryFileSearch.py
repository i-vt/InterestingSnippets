import os, fnmatch

# Directory to start the search from
start_dir = '/path/to/your/directory'

# Pattern to match files with the ".xml" extension
pattern = '*.xml'

# List to store the matched file paths
xml_files = []

# Recursively search for XML files
for root, dirs, files in os.walk(start_dir):
    for filename in fnmatch.filter(files, pattern):
        xml_file_path = os.path.join(root, filename)
        xml_files.append(xml_file_path)

# Print the list of XML file paths
for xml_file in xml_files:
    print(xml_file)
