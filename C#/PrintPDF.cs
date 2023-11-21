using System;
using System.Diagnostics;

class Program
{
    static void Main(string[] args)
    {
        PrintPDF(@"C:\path\to\your\file.pdf");
    }

    static void PrintPDF(string filePath)
    {
        try
        {
            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = "AcroRd32.exe"; // Path to Adobe Reader. Change if necessary.
            startInfo.Arguments = $"/p /h {filePath}";
            startInfo.CreateNoWindow = true;
            startInfo.UseShellExecute = false;

            using (Process exeProcess = Process.Start(startInfo))
            {
                exeProcess.WaitForExit();
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error: {ex.Message}");
        }
    }
}
