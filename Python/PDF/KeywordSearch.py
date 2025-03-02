# pip3 install pdfplumber
# python3 keyword_search08.py ~/ "route","null"  --ignore_case --window 100
import os
import argparse
import json
import pdfplumber

def find_context(content, keywords, window=100, ignore_case=True):
    """Find and return the context where all provided keywords appear within the specified window size, along with the position in the text, avoiding overlapping contexts."""
    words = content.split()
    positions = {keyword: [] for keyword in keywords}
    for index, word in enumerate(words):
        for keyword in keywords:
            if (keyword.lower() in word.lower() if ignore_case else keyword in word):
                positions[keyword].append(index)

    valid_contexts = []
    last_end_index = -1
    for start_index in range(len(words) - window):
        if all(any(start_index <= pos <= start_index + window for pos in positions[keyword]) for keyword in keywords):
            end_index = min(start_index + window, len(words) - 1)
            if start_index > last_end_index:  # Ensure this start is beyond the last end to avoid overlaps
                context = " ".join(words[start_index:end_index + 1])
                snippet_position = f"{start_index} - {end_index}"
                valid_contexts.append((context, snippet_position))
                last_end_index = end_index

    return valid_contexts

def search_file(file_path, keywords, window=100, ignore_case=True):
    """Search for multiple keywords in a text or PDF file and provide context where all keywords are within the specified window, including the location."""
    try:
        content = ""
        if file_path.endswith('.txt'):
            with open(file_path, 'r', encoding='utf-8') as file:
                content = file.read()
        elif file_path.endswith('.pdf'):
            with pdfplumber.open(file_path) as pdf:
                content = ' '.join(page.extract_text() or '' for page in pdf.pages)
        else:
            return {}
    except Exception as e:
        print(f"Failed to read {file_path}: {str(e)}")
        return {}

    results = find_context(content, keywords, window=window, ignore_case=ignore_case)
    return {file_path: results} if results else {}

def search_files(directory, keywords, window=100, ignore_case=True):
    """Recursively search for keywords in all .txt and .pdf files in the directory with the specified window and provide context where all keywords are present, along with position."""
    matches = {}
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith(('.txt', '.pdf')):
                file_path = os.path.join(root, file)
                result = search_file(file_path, keywords, window=window, ignore_case=ignore_case)
                if result:
                    matches.update(result)
    return matches

def save_results_as_json(results, output_path):
    """Save the search results into a JSON file, including the context and position."""
    with open(output_path, 'w') as f:
        json.dump(results, f, indent=4)

def main():
    parser = argparse.ArgumentParser(description="Search for multiple keywords in all .txt and .pdf files within a directory and ensure they are within a specified word proximity, including the location of the snippet, avoiding overlapping entries.")
    parser.add_argument('directory', type=str, help="The directory to search in")
    parser.add_argument('keywords', type=str, help="Comma-separated keywords to search for")
    parser.add_argument('--window', type=int, default=100, help="Number of words around the keyword to consider as context")
    parser.add_argument('--ignore_case', action='store_true', help="Ignore case when searching for keywords")
    parser.add_argument('--output', type=str, help="Optional JSON file to save the results")
    args = parser.parse_args()

    keywords = args.keywords.split(',')
    matches = search_files(args.directory, keywords, window=args.window, ignore_case=args.ignore_case)
    if matches:
        if args.output:
            save_results_as_json(matches, args.output)
        else:
            print("Found contexts with all keywords in the following files, including snippet positions:")
            for file_path, contexts in matches.items():
                print(f"\n{file_path}:")
                for context, position in contexts:
                    print(f"Context at {position}: {context}")
    else:
        print("No keywords found in close proximity in any files.")

if __name__ == "__main__":
    main()
