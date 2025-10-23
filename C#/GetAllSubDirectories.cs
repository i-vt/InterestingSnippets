using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

class Program
{
    public static void Main()
    {
        foreach (var item in DirectoryHelper.GetAllSubDirectories("[PATH]"))
        {
            Console.WriteLine(item);
        }
    }
}

public static class DirectoryHelper
{
    /// <summary>
    /// Retrieves all subdirectories for a given directory path.
    /// </summary>
    /// <param name="directoryPath">The path to the directory.</param>
    /// <param name="recursive">If true, includes all nested subdirectories; otherwise, only immediate subdirectories.</param>
    /// <returns>A list of full paths to subdirectories.</returns>
    /// <exception cref="ArgumentNullException">Thrown when directoryPath is null or empty.</exception>
    /// <exception cref="DirectoryNotFoundException">Thrown when the directory does not exist.</exception>
    /// <exception cref="UnauthorizedAccessException">Thrown when access to the directory is denied.</exception>
    public static IReadOnlyList<string> GetAllSubDirectories(string? directoryPath, bool recursive = false)
    {
        if (string.IsNullOrWhiteSpace(directoryPath))
        {
            throw new ArgumentNullException(nameof(directoryPath), "Directory path cannot be null or empty.");
        }

        try
        {
            DirectoryInfo directory = new(directoryPath);

            if (!directory.Exists)
            {
                throw new DirectoryNotFoundException($"Directory does not exist: {directoryPath}");
            }

            return recursive
                ? directory.EnumerateDirectories("*", SearchOption.AllDirectories)
                           .Select(d => d.FullName)
                           .ToList()
                           .AsReadOnly()
                : directory.EnumerateDirectories()
                           .Select(d => d.FullName)
                           .ToList()
                           .AsReadOnly();
        }
        catch (UnauthorizedAccessException ex)
        {
            throw new UnauthorizedAccessException($"Access denied to directory: {directoryPath}", ex);
        }
        catch (PathTooLongException ex)
        {
            throw new PathTooLongException($"Path is too long: {directoryPath}", ex);
        }
        catch (IOException ex)
        {
            throw new IOException($"Error accessing directory: {directoryPath}", ex);
        }
    }
}
