import re
import json

# Read the file content
with open('dictionary.json', 'r') as file:
    content = file.read()

# Remove all characters that are not a-z or spaces
cleaned_content = re.sub(r'[^a-z ]', '', content)

# Replace multiple spaces with a single space
cleaned_content = re.sub(r'\s+', ' ', cleaned_content).strip()

# Split the cleaned content into words
words = cleaned_content.split()

# Place words into a dictionary with their index
word_dict = {index: word for index, word in enumerate(words)}

# Save the dictionary to a JSON file
with open('word_dict.json', 'w') as json_file:
    json.dump(word_dict, json_file, indent=4)

print("Dictionary saved to 'word_dict.json'.")
