using System;
using System.IO;
using System.Net.Http;
using System.Threading.Tasks;

class Program
{
    static async Task<int> Main(string[] args)
    {
        if (args.Length < 2)
        {
            Console.WriteLine("Usage: dloader.exe [URL] [Destination Path]");
            return 1;
        }

        string url = args[0];
        string destinationPath = args[1];

        // Validate URL
        if (!Uri.TryCreate(url, UriKind.Absolute, out Uri? validatedUrl))
        {
            Console.WriteLine("Error: Invalid URL format.");
            return 1;
        }

        // Validate file path
        try
        {
            string fullPath = Path.GetFullPath(destinationPath);
            string? directory = Path.GetDirectoryName(fullPath);
            if (!string.IsNullOrEmpty(directory) && !Directory.Exists(directory))
            {
                Directory.CreateDirectory(directory);
            }
        }
        catch
        {
            Console.WriteLine("Error: Invalid destination path.");
            return 1;
        }

        try
        {
            using HttpClient client = new HttpClient();

            Console.WriteLine($"Starting download from: {url}");

            using HttpResponseMessage response = await client.GetAsync(validatedUrl, HttpCompletionOption.ResponseHeadersRead);
            response.EnsureSuccessStatusCode();

            long? totalBytes = response.Content.Headers.ContentLength;

            using Stream contentStream = await response.Content.ReadAsStreamAsync(),
                          fileStream = new FileStream(destinationPath, FileMode.Create, FileAccess.Write, FileShare.None, 8192, true);

            var buffer = new byte[8192];
            long totalRead = 0;
            int read;

            var lastReportedProgress = -1;

            while ((read = await contentStream.ReadAsync(buffer.AsMemory(0, buffer.Length))) > 0)
            {
                await fileStream.WriteAsync(buffer.AsMemory(0, read));
                totalRead += read;

                if (totalBytes.HasValue)
                {
                    int progress = (int)((totalRead * 100L) / totalBytes.Value);
                    if (progress != lastReportedProgress)
                    {
                        Console.Write($"\rProgress: {progress}%   ");
                        lastReportedProgress = progress;
                    }
                }
            }

            Console.WriteLine($"\nDownload complete. File saved to: {destinationPath}");
            return 0;
        }
        catch (HttpRequestException hre)
        {
            Console.WriteLine($"Network error: {hre.Message}");
        }
        catch (IOException ioe)
        {
            Console.WriteLine($"File error: {ioe.Message}");
        }
        catch (UnauthorizedAccessException uae)
        {
            Console.WriteLine($"Permission error: {uae.Message}");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Unexpected error: {ex.Message}");
        }

        return 1;
    }
}
