import os

file_path = r"C:\Temp\abc.1.szya.txt"

directory, file_name = os.path.split(file_path)

result = [directory, file_name]

print(result)
