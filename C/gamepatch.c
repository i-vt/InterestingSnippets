#include <stdio.h>
#include <stdlib.h>
//x86_64-w64-mingw32-gcc -o gamepatch.exe gamepatch.c 

int main() {
    // Define the file that will indicate the patch execution
    const char *filePath = "C:\\Game\\patch_success.txt";
    
    // Open the file for writing (create or overwrite)
    FILE *file = fopen(filePath, "w");
    
    // Check if the file opened successfully
    if (file == NULL) {
        printf("Error: Could not create or write to the file.\n");
        return 1;  // Return a non-zero exit code to indicate failure
    }
    
    // Write a success message to the file
    fprintf(file, "Patch executed successfully.\n");
    
    // Close the file
    fclose(file);
    
    // Optionally, print a message to the console (can be viewed if executed manually)
    printf("Dummy patch executed successfully. Check %s for confirmation.\n", filePath);
    
    return 0;  // Return zero to indicate success
}
