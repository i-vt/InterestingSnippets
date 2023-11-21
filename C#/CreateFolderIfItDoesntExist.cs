using System;
using System.IO;

class Program
{
    static void Main()
    {
        string folderPath = @"C:\path\to\your\folder";

        // Check if the folder exists
        if (!Directory.Exists(folderPath))
        {
            Console.WriteLine("Folder does not exist. Creating...");
            // Create the folder
            Directory.CreateDirectory(folderPath);
            Console.WriteLine("Folder created.");
        }
        else
        {
            Console.WriteLine("Folder already exists.");
        }
    }
}
