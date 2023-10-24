"""
When saving reports John Smith started the counter off 0, instead of 1. All of the reports need to be shifted by +1.
Reports are located in different folders, but John cannot remember which ones he ran the faulty script on.
John said 
"""

import os


#prep files with: cp main_reports_folder backup; cd main_reports_folder; locate . 0.txt | grep /0 > ./filestofix.txt

EXTENSION = ".txt"
ROOTFOLDER = "/home/johnsmith/main_reports_folder/filestofix.txt"
impacted_folders = []
with open(ROOTFOLDER, "r") as file:
  file_output = file.read()
  impacted_folders = file_output.split("\n")
for folder in impacted_folders:
  try:
    if folder == []: continue # skip empty lines (usually at least 1 at the end of the file)
    folder_path = os.path.dirname(folder)  # Replace with the path to your folder
    
    # Get a list of all files in the folder
    files = os.listdir(folder_path)
    
    # Loop through the files and rename them to start with "1.txt"
    for i, file_name in enumerate(files):
      
      # If int is sorted & has a no padding 0's it gets sorted in a funky way
      new_name = os.path.join(folder_path, str(int(file_name[:-1*len(EXTENSION)]) + 1) + EXTENSION)
      old_name = os.path.join(folder_path, file_name)
      
      # Rename the file
      os.rename(old_name, new_name)
      print(f"{i}: Renamed {old_name} to {new_name}")
  
    print(f"Files in folder {folder_path} renamed successfully.")
  except Exception as ex: print(folder,ex)
