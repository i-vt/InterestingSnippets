import re
import argparse

def clean_string(input_string):
    # This regex keeps letters (A-Z, a-z), digits (0-9), spaces, and standard keyboard punctuation
    allowed_chars_pattern = r'[^A-Za-z0-9\s!"#$%&\'()*+,-./:;<=>?@[\\]^_`{|\n\t}~]'
    cleaned = re.sub(allowed_chars_pattern, '', input_string)
    return cleaned

# Predefined characters, currently not used
def keep_predefined_chars(input_str):
    predefined_keys_list = [
        "'", ",", ".", "p", "y", "f", "g", "c", "r", "l", "/", "=", "[", "]", "\\",
        "a", "o", "e", "u", "i", "d", "h", "t", "n", "s", "-", ";",
        "q", "j", "k", "x", "b", "m", "w", "v", "z",
        "\"", "<", ">", "P", "Y", "F", "G", "C", "R", "L", "?", "+", "{", "}", "|",
        "A", "O", "E", "U", "I", "D", "H", "T", "N", "S", "_", ":",
        "Q", "J", "K", "X", "B", "M", "W", "V", "Z", " "
    ]
    
    predefined_keys = set(predefined_keys_list)

    # Keep only characters in the Dvorak key set
    filtered = ''.join(char for char in input_str if char in predefined_keys)
    return filtered


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Clean a string or file by removing disallowed characters.')
    parser.add_argument('-t', '--text', type=str, help='Text to be cleaned')
    parser.add_argument('-i', '--input', type=argparse.FileType('r'), help='Input file to be cleaned')
    parser.add_argument('-o', '--output', type=argparse.FileType('w'), help='File to write cleaned output to')
    args = parser.parse_args()

    if args.input:
        input_text = args.input.read()
    elif args.text:
        input_text = args.text
    else:
        parser.error('Either --text or --input must be provided.')

    cleaned_text = clean_string(input_text)

    if args.output:
        args.output.write(cleaned_text)
        args.output.close()
    else:
        print("Original:", input_text)
        print("Cleaned:", cleaned_text)
