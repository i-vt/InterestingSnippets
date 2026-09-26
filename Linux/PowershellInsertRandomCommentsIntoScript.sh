#!/bin/bash
if [[ -z "$1" ]]; then
    echo "Usage: $0 <file> <dictionary> <number_of_lines> <max_words_per_line>"
    exit 1
fi

num_lines=$3
dict_file=$2
output_file=$1
total_words=$(wc -l < "$dict_file")

for _ in $(seq 1 "$num_lines"); do
    line="#"
    words_in_line=$(( RANDOM % $4 + 1 )
    for _ in $(seq 1 "$words_in_line"); do
        random_word=$(awk "NR == $(( RANDOM % total_words + 1 ))" "$dict_file")
        line="${line}${random_word} "
    done

    echo "$line" >> "$output_file"
done

echo "Appended $num_lines lines to $output_file."
