import os, json
def make_jsons(file, content) -> bool:
    try:
        with open(file, 'w', encoding='utf-8') as json_file:
            json.dump(content, json_file, ensure_ascii=False, indent=4)
    except Exception as e:
        print(f"An error occurred: {e}")
        return False


def combine_json(output_filename: str="combined.json", json_filepaths: list = []) -> bool:
    combined_data = []
    
    try:
        for filepath in json_filepaths:
            with open(filepath, 'r') as file:
                data = json.load(file)
                combined_data.extend(data)
        
        with open(output_filename, 'w') as output_file:
            json.dump(combined_data, output_file, indent=4)
        
        return True
    
    except Exception as e:
        print(f"An error occurred: {e}")
        return False

def json_to_list(filepath: str = "") -> list:
    try:
        with open(filepath, 'r') as file:
            data = json.load(file)
            if isinstance(data, list):
                return data
            else:
                raise ValueError("JSON content is not a list")
    except Exception as e:
        print(f"An error occurred: {e}")
        return []

def read_json(filepath: str) -> dict:
    try:
        with open(filepath, 'r') as file:
            data = json.load(file)
            return data
    except Exception as e:
        print(f"An error occurred: {e}")
        return {}

# Other
## Accessing JSON: 
data = read_json("/example/dir/file.json")
print(data['car']['license'])

