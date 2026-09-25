using System;
using System.IO;
using System.Net.Sockets;

class Program
{
    static void Main(string[] args)
    {
        if (args.Length < 3)
        {
            Console.WriteLine("Usage: uloader.exe [Destination IP] [Destination Port] [FilePath]");
            return;
        }

        string destIP = args[0];
        int destPort = int.Parse(args[1]);
        string filePath = args[2];

        try
        {
            using (TcpClient client = new TcpClient(destIP, destPort))
            using (NetworkStream stream = client.GetStream())
            using (FileStream fs = new FileStream(filePath, FileMode.Open, FileAccess.Read))
            {
                Console.WriteLine($"Uploading file {filePath} to {destIP}:{destPort}...");
                fs.CopyTo(stream);
                Console.WriteLine($"File uploaded successfully.");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"An error occurred: {ex.Message}");
        }
    }
}
