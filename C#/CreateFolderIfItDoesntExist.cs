using System.IO;
using System;

class Program
{
    static void Main()
    {
        string folderPath = @"C:\path\to\your\folder";

        bool a = EnsureDirectoryExists(folderPath);

        string path = GetPath(folderPath);
    }

    /// <summary>
    /// Checks for a directory and creates it if necessary.
    /// Returns true if the directory has been created.
    /// </summary>
    private static bool EnsureDirectoryExists(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);

        if (Directory.Exists(path))
            return false;

        Directory.CreateDirectory(path);
        return true;
    }

    /// <summary>
    /// Checks for a directory and creates it if necessary.
    /// Returns the directory path.
    /// </summary>
    private static string GetPath(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);

        if (!Directory.Exists(path))
            Directory.CreateDirectory(path);

        return path;
    }
}
