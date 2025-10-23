using System.IO;
using System.Threading.Tasks;
using System.Threading;
using System;

public class FileDownloader : IAsyncDisposable
{
    private readonly HttpClient _httpClient;

    public FileDownloader(HttpClient? httpClient = null)
    {
        _httpClient = httpClient ?? new HttpClient
        {
            Timeout = TimeSpan.FromMinutes(5)
        };
    }

    public async Task DownloadFileAsync(
        Uri url,
        string destinationPath,
        IProgress<double>? progress = null,
        CancellationToken cancellationToken = default)
    {
        string fullPath = Path.GetFullPath(destinationPath);
        string? dir = Path.GetDirectoryName(fullPath);
        if (!string.IsNullOrEmpty(dir))
            Directory.CreateDirectory(dir);

        using var response = await _httpClient.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        response.EnsureSuccessStatusCode();

        long? totalBytes = response.Content.Headers.ContentLength;
        await using var contentStream = await response.Content.ReadAsStreamAsync(cancellationToken);
        await using var fileStream = new FileStream(fullPath, FileMode.Create, FileAccess.Write, FileShare.None, 81920, useAsync: true);

        var buffer = new byte[81920];
        long totalRead = 0;
        int read;

        while ((read = await contentStream.ReadAsync(buffer.AsMemory(0, buffer.Length), cancellationToken)) > 0)
        {
            await fileStream.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
            totalRead += read;

            if (totalBytes.HasValue && progress is not null)
            {
                double percent = (double)totalRead / totalBytes.Value * 100;
                progress.Report(percent);
            }
        }
    }

    public async ValueTask DisposeAsync()
    {
        _httpClient.Dispose();
        await Task.CompletedTask;
    }
}

class Program
{
    // progname.exe "example url" "C:\Downloads\[filename]"
    static async Task<int> Main(string[] args)
    {
        if (args.Length < 2)
        {
            Console.WriteLine("Usage: dloader.exe [URL] [Destination Path]");
            return 1;
        }

        if (!Uri.TryCreate(args[0], UriKind.Absolute, out var url))
        {
            Console.WriteLine("Error: Invalid URL format.");
            return 1;
        }

        string path = args[1];

        try
        {
            await using var downloader = new FileDownloader();

            var progress = new Progress<double>(p =>
            {
                Console.Write($"\rProgress: {p:F1}%   ");
            });

            Console.WriteLine($"Starting download from: {url}");

            await downloader.DownloadFileAsync(url, path, progress);

            Console.WriteLine($"\nDownload complete. File saved to: {path}");
            return 0;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"\nError: {ex.Message}");
            return 1;
        }
    }
}