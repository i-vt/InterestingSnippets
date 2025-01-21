clear; cat build.gradle > ../summary.txt; find ./src -type f -exec cat {} + >>../summary.txt; tree . >> ../summary.txt
