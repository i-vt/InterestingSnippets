using System;
using System.Net;
using System.Net.Sockets;
using System.Threading.Tasks;

class PortForwardWithCLI
{
    private readonly int _sourcePort;
    private readonly string _destinationHost;
    private readonly int _destinationPort;

    public pforward(int sourcePort, string destinationHost, int destinationPort)
    {
        _sourcePort = sourcePort;
        _destinationHost = destinationHost;
        _destinationPort = destinationPort;
    }

    public void Start()
    {
        var listener = new TcpListener(IPAddress.Any, _sourcePort);
        listener.Start();
        Console.WriteLine($"Listening on port {_sourcePort}...");

        while (true)
        {
            var client = listener.AcceptTcpClient();
            Task.Run(() => HandleClient(client));
        }
    }

    private void HandleClient(TcpClient client)
    {
        using (client)
        using (var destination = new TcpClient(_destinationHost, _destinationPort))
        {
            var clientStream = client.GetStream();
            var destinationStream = destination.GetStream();

            var clientToDestinationTask = Task.Run(() => Redirect(clientStream, destinationStream));
            var destinationToClientTask = Task.Run(() => Redirect(destinationStream, clientStream));

            Task.WaitAll(clientToDestinationTask, destinationToClientTask);
        }
    }

    private static async void Redirect(NetworkStream source, NetworkStream destination)
    {
        var buffer = new byte[4096];
        int bytesRead;
        while ((bytesRead = await source.ReadAsync(buffer, 0, buffer.Length)) > 0)
        {
            await destination.WriteAsync(buffer, 0, bytesRead);
        }
    }

    static void Main(string[] args)
    {
        if (args.Length < 3)
        {
            Console.WriteLine("Usage: pforward.exe <sourcePort> <destinationHost> <destinationPort>");
            return;
        }

        int sourcePort = int.Parse(args[0]);
        string destinationHost = args[1];
        int destinationPort = int.Parse(args[2]);

        var forwarder = new pforward(sourcePort, destinationHost, destinationPort);
        forwarder.Start();
    }
}
