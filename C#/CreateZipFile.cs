using System.IO;
using System.IO.Compression;

public static void CreateZipFile(string fileToZip, string destinationZipFullPath)
{
    // Ensure the file exists
    if (File.Exists(fileToZip))
    {
        // Create a zip that contains the file
        using (var zipArchive = ZipFile.Open(destinationZipFullPath, ZipArchiveMode.Create))
        {
            zipArchive.CreateEntryFromFile(fileToZip, Path.GetFileName(fileToZip));
        }
    }
    else
    {
        throw new FileNotFoundException("The specified file to zip was not found.", fileToZip);
    }
}
