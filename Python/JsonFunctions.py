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

