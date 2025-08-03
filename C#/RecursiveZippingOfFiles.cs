using System;
using System.IO;
using System.IO.Compression;
using System.Security;

class Program
{
    static void Main(string[] args)
    {
        if(args.Length < 2)
        {
            Console.WriteLine("Usage: cliZIP.exe <sourcePath> <destinationZipPath>");
            Console.WriteLine("  sourcePath can be a file or directory");
            return;
        }
        
        string sourcePath = args[0];
        string destinationZip = args[1];
        
        if(!File.Exists(sourcePath) && !Directory.Exists(sourcePath))
        {
            Console.WriteLine($"Error: Path '{sourcePath}' does not exist.");
            return;
        }
        
        try
        {
            using (FileStream zipToOpen = new FileStream(destinationZip, FileMode.Create))
            {
                using (ZipArchive archive = new ZipArchive(zipToOpen, ZipArchiveMode.Create))
                {
                    if (File.Exists(sourcePath))
                    {
                        // Single file
                        AddFileToArchive(archive, sourcePath, Path.GetFileName(sourcePath));
                    }
                    else if (Directory.Exists(sourcePath))
                    {
                        // Directory - add recursively
                        AddDirectoryToArchive(archive, sourcePath, "");
                    }
                }
            }
            Console.WriteLine($"Successfully compressed '{sourcePath}' to '{destinationZip}'!");
        }
        catch(Exception ex)
        {
            Console.WriteLine($"An error occurred creating the archive: {ex.Message}");
        }
    }
    
    static void AddDirectoryToArchive(ZipArchive archive, string directoryPath, string entryPrefix)
    {
        try
        {
            // Add all files in current directory
            foreach (string filePath in Directory.GetFiles(directoryPath))
            {
                string fileName = Path.GetFileName(filePath);
                string entryName = string.IsNullOrEmpty(entryPrefix) ? fileName : $"{entryPrefix}/{fileName}";
                AddFileToArchive(archive, filePath, entryName);
            }
            
            // Recursively add subdirectories
            foreach (string subdirectory in Directory.GetDirectories(directoryPath))
            {
                string dirName = Path.GetFileName(subdirectory);
                string newPrefix = string.IsNullOrEmpty(entryPrefix) ? dirName : $"{entryPrefix}/{dirName}";
                AddDirectoryToArchive(archive, subdirectory, newPrefix);
            }
        }
        catch (UnauthorizedAccessException)
        {
            Console.WriteLine($"Warning: Access denied to directory '{directoryPath}' - skipping");
        }
        catch (SecurityException)
        {
            Console.WriteLine($"Warning: Security exception accessing directory '{directoryPath}' - skipping");
        }
        catch (DirectoryNotFoundException)
        {
            Console.WriteLine($"Warning: Directory '{directoryPath}' not found - skipping");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Warning: Error accessing directory '{directoryPath}': {ex.Message} - skipping");
        }
    }
    
    static void AddFileToArchive(ZipArchive archive, string filePath, string entryName)
    {
        try
        {
            archive.CreateEntryFromFile(filePath, entryName);
            Console.WriteLine($"Added: {entryName}");
        }
        catch (UnauthorizedAccessException)
        {
            Console.WriteLine($"Warning: Access denied to file '{filePath}' - skipping");
        }
        catch (SecurityException)
        {
            Console.WriteLine($"Warning: Security exception accessing file '{filePath}' - skipping");
        }
        catch (FileNotFoundException)
        {
            Console.WriteLine($"Warning: File '{filePath}' not found - skipping");
        }
        catch (IOException ex)
        {
            Console.WriteLine($"Warning: IO error with file '{filePath}': {ex.Message} - skipping");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Warning: Error adding file '{filePath}': {ex.Message} - skipping");
        }
    }
}
