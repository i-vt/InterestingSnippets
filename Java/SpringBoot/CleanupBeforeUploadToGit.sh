#!/bin/bash

# Define directories and files to be cleaned
CLEAN_DIRS=("build" "gradle" "tmp")
CLEAN_FILES=("gradlew" "gradlew.bat")

# Function to remove unwanted files and directories
clean_repo() {
    # Remove specific files like gradlew and gradlew.bat
    for file in "${CLEAN_FILES[@]}"; do
        if [ -f "$file" ]; then
            echo "Removing file: $file"
            rm -f "$file"
        fi
    done

    # Clean up specified directories and their contents
    for dir in "${CLEAN_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            echo "Cleaning up directory: $dir"
            rm -rf "$dir"/*
        fi
    done

    # Remove specific file types that should not be in the repo
    echo "Removing unnecessary file types..."

    # Remove .class files
    find . -type f -name "*.class" -exec rm -f {} \;
    
    # Remove .log files
    find . -type f -name "*.log" -exec rm -f {} \;
    
    # Remove .tmp files
    find . -type f -name "*.tmp" -exec rm -f {} \;
    
    # Optionally, clean up IDE files
    find . -type f -name "*.iml" -exec rm -f {} \;
    find . -type d -name ".idea" -exec rm -rf {} \;

    # Clean up .DS_Store (macOS specific)
    find . -type f -name ".DS_Store" -exec rm -f {} \;

    # Clean up any other unwanted files
    echo "Cleanup complete!"
}

# Run the cleanup function
clean_repo
