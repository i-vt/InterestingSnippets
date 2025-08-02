import os
import argparse


def split_file(input_file, output_dir, lines_per_file):
    """Splits a large file into smaller files with a specified number of lines."""
    with open(input_file, 'r') as file:
        lines = file.readlines()

    num_files = len(lines) // lines_per_file + (1 if len(lines) % lines_per_file else 0)

    for i in range(num_files):
        file_name = f'{i}.txt'
        file_path = os.path.join(output_dir, file_name)
        with open(file_path, 'w') as file:
            start = i * lines_per_file
            end = start + lines_per_file
            file.writelines(lines[start:end])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Split a large file into smaller files with a specified number of lines.')
    parser.add_argument('input_file', help='The path to the input file.')
    parser.add_argument('output_dir', help='The path to the output directory.')
    parser.add_argument('lines_per_file', type=int, help='The number of lines per file.')

    args = parser.parse_args()

    input_file = args.input_file
    output_dir = args.output_dir
    lines_per_file = args.lines_per_file

    split_file(input_file, output_dir, lines_per_file)
