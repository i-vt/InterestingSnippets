using System;
using System.Net;
using System.Diagnostics;
using System.ComponentModel;

class Program
{
    static void Main()
    {
        string pythonInstallerURL = "https://www.python.org/ftp/python/3.9.0/python-3.9.0.exe"; // Change this URL to the desired version
        string installerPath = @"C:\path\to\download\python-3.9.0.exe"; // Specify the path where you want to save the installer

        try
        {
            // Download Python installer
            using (WebClient client = new WebClient())
            {
                Console.WriteLine("Downloading Python installer...");
                client.DownloadFile(pythonInstallerURL, installerPath);
                Console.WriteLine("Download completed.");
            }

            // Install Python with default configurations
            ProcessStartInfo startInfo = new ProcessStartInfo(installerPath)
            {
                Arguments = "/quiet InstallAllUsers=1 PrependPath=1", // Silent install with default settings
                UseShellExecute = false
            };

            using (Process process = Process.Start(startInfo))
            {
                process.WaitForExit();
                Console.WriteLine("Python installed successfully.");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine("An error occurred: " + ex.Message);
        }
    }
}
