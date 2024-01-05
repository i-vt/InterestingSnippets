using System.IO;

public static List<string> GetAllSubDirectories(string strDirectoryPath)
{
    // Create a new DirectoryInfo object
    DirectoryInfo directory = new DirectoryInfo(strDirectoryPath);

    // Get all sub-directories
    DirectoryInfo[] subdirs = directory.GetDirectories();

    // Convert DirectoryInfo objects to string (full path)
    List<string> subdirPaths = subdirs.Select(d => d.FullName).ToList();

    return subdirPaths;
}
