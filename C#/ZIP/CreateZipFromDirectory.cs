using System.IO;
using System.IO.Compression;

public static void CreateZipFromDirectory(string strFolderToZip, string strDestinationDirectory)
{
    if (Directory.Exists(strFolderToZip))
    {
        var folderName = new DirectoryInfo(strFolderToZip).Name;
        string zipFilePath = Path.Combine(strDestinationDirectory, strFolderToZip + ".zip");
        ZipFile.CreateFromDirectory(strFolderToZip, zipFilePath);
    }
    else
    {
        throw new DirectoryNotFoundException("The specified folder to zip was not found.");
    }
}
