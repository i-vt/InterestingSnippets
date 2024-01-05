using System.IO;
using System.IO.Compression;

public static void CreateZipFromDirectory(string strFolderToZip, string strDestinationDirectory)
{
    // Ensure the folder exists
    if (Directory.Exists(strFolderToZip))
    {
        // Get the folder name from the folder path
        var folderName = new DirectoryInfo(strFolderToZip).Name;

        // Construct the full path for the zip file
        string zipFilePath = Path.Combine(strDestinationDirectory, strFolderToZip + ".zip");

        // Create a zip from the directory
        ZipFile.CreateFromDirectory(strFolderToZip, zipFilePath);
    }
    else
    {
        throw new DirectoryNotFoundException("The specified folder to zip was not found.");
    }
}
