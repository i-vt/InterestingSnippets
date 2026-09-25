using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Threading.Tasks;

class ForwardProxy
{
    private static async Task HandleRequestAsync(HttpListenerContext context)
    {
        var request = context.Request;
        var response = context.Response;

        using (var client = new HttpClient())
        {
            try
            {
                // Create a new request with the original request's url.
                var forwardRequest = new HttpRequestMessage()
                {
                    RequestUri = request.Url,
                    Method = new HttpMethod(request.HttpMethod)
                };

                // Copy original request headers to the new request.
                foreach (string headerKey in request.Headers.AllKeys)
                {
                    forwardRequest.Headers.TryAddWithoutValidation(headerKey, request.Headers[headerKey]);
                }

                // Send the request and get the response.
                var forwardResponse = await client.SendAsync(forwardRequest);

                // Copy the response information to the original response.
                response.StatusCode = (int)forwardResponse.StatusCode;
                response.StatusDescription = forwardResponse.ReasonPhrase;
                foreach (var header in forwardResponse.Headers)
                {
                    response.Headers.Add(header.Key, string.Join(", ", header.Value));
                }

                // Copy the response content to the original response stream.
                var responseContent = await forwardResponse.Content.ReadAsStreamAsync();
                await responseContent.CopyToAsync(response.OutputStream);
            }
            catch (Exception ex)
            {
                Console.WriteLine("Exception: " + ex.Message);
                response.StatusCode = 500;
            }
            finally
            {
                response.Close();
            }
        }
    }

    static void Main(string[] args)
    {
        if (args.Length != 1)
        {
            Console.WriteLine("Usage: ForwardProxy <port>");
            return;
        }

        int port;
        if (!int.TryParse(args[0], out port))
        {
            Console.WriteLine("Invalid port number");
            return;
        }

        var listener = new HttpListener();
        listener.Prefixes.Add($"http://*:{port}/");
        listener.Start();

        Console.WriteLine($"Proxy is running on port {port}...");
        Console.WriteLine("Press Ctrl+C to stop.");

        while (true)
        {
            var context = listener.GetContext();
            Task.Run(() => HandleRequestAsync(context));
        }
    }
}
