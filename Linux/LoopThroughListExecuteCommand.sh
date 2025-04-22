#!/bin/bash
while IFS= read -r file; do
  command "$file"
done < filelist.txt
