//mkdir MyZipApp
//cd MyZipApp
//dotnet new console
// vi Program.cs
//dotnet publish -c Release -r win-x64 --self-contained -p:PublishSingleFile=true
///cp /home/usernamegohere/Downloads/MyZipApp/bin/Release/net7.0/win-x64/publish/MyZipApp.exe ../

using System;
using System.IO;
using System.IO.Compression;

class Program
{
    static void Main(string[] args)
    {
        // Ensure the user has provided a directory path as an argument
        if (args.Length < 1)
        {
            Console.WriteLine("Please provide a directory path.");
            return;
        }

        string targetDirectory = args[0];

        // Check if the provided directory exists
        if (!Directory.Exists(targetDirectory))
        {
            Console.WriteLine($"The directory {targetDirectory} does not exist.");
            return;
        }

        // Get all the subdirectories in the target directory
        string[] directories = Directory.GetDirectories(targetDirectory);

        // Check if there are any folders to zip
        if (directories.Length == 0)
        {
            Console.WriteLine("No folders found to zip.");
            return;
        }

        // Define the path for the output zip file
        string zipFilePath = Path.Combine(targetDirectory, "FoldersArchive.zip");

        // Create the zip archive
        using (ZipArchive archive = ZipFile.Open(zipFilePath, ZipArchiveMode.Create))
        {
            foreach (string directory in directories)
            {
                string folderName = Path.GetFileName(directory);
                Console.WriteLine($"Adding folder: {folderName}");

                try
                {
                    // Recursively add files from the folder to the archive
                    AddFolderToZip(directory, archive, folderName);
                }
                catch (UnauthorizedAccessException ex)
                {
                    // Handle access denied issues and continue
                    Console.WriteLine($"Error: Access denied to folder '{folderName}'. Skipping.");
                }
                catch (Exception ex)
                {
                    // Handle any other errors and continue
                    Console.WriteLine($"Error: {ex.Message}. Skipping folder '{folderName}'.");
                }
            }
        }

        Console.WriteLine($"All accessible folders have been zipped into: {zipFilePath}");
    }

    // Helper method to recursively add a folder and its contents to the zip archive
    static void AddFolderToZip(string folderPath, ZipArchive archive, string entryPath)
    {
        try
        {
            // Get all files in the current folder
            foreach (string filePath in Directory.GetFiles(folderPath))
            {
                try
                {
                    // Add individual files to the zip archive
                    string relativePath = Path.GetRelativePath(folderPath, filePath);
                    string zipEntryPath = Path.Combine(entryPath, relativePath);
                    archive.CreateEntryFromFile(filePath, zipEntryPath);
                    Console.WriteLine($"Added file: {filePath}");
                }
                catch (UnauthorizedAccessException)
                {
                    Console.WriteLine($"Warning: Access denied to file '{filePath}'. Skipping.");
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"Error while zipping file '{filePath}': {ex.Message}. Skipping.");
                }
            }

            // Get all subdirectories in the current folder and process them recursively
            foreach (string subFolder in Directory.GetDirectories(folderPath))
            {
                string subFolderName = Path.GetFileName(subFolder);
                string newEntryPath = Path.Combine(entryPath, subFolderName);
                
                try
                {
                    // Recursively add subfolder contents
                    AddFolderToZip(subFolder, archive, newEntryPath);
                }
                catch (UnauthorizedAccessException)
                {
                    Console.WriteLine($"Warning: Access denied to folder '{subFolderName}'. Skipping.");
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"Error while zipping folder '{subFolderName}': {ex.Message}. Skipping.");
                }
            }
        }
        catch (UnauthorizedAccessException)
        {
            // Handle access denied issues for the entire folder and continue processing files
            Console.WriteLine($"Warning: Access denied to folder '{folderPath}'. Attempting to zip files inside.");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error while accessing folder '{folderPath}': {ex.Message}. Skipping this folder.");
        }
    }
}
