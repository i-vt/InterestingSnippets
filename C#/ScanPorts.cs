using System;
using System.Net.Sockets;
using System.Threading.Tasks;

namespace cliPortScan
{
    class Program
    {
        static async Task Main(string[] args)
        {
            if (args.Length < 3)
            {
                Console.WriteLine("Usage: cliPortScan.exe <ip> <startPort> <endPort>");
                return;
            }

            string ip = args[0];
            if (!int.TryParse(args[1], out int startPort) || !int.TryParse(args[2], out int endPort))
            {
                Console.WriteLine("Invalid port number provided. Ports should be integers.");
                return;
            }

            Console.WriteLine($"Scanning ports {startPort} to {endPort} on {ip}...");

            for (int port = startPort; port <= endPort; port++)
            {
                if (await IsPortOpenAsync(ip, port))
                {
                    Console.WriteLine($"Port {port} is OPEN");
                }
                else
                {
                    Console.WriteLine($"Port {port} is CLOSED");
                }
            }
        }

        private static async Task<bool> IsPortOpenAsync(string ip, int port)
        {
            using (TcpClient tcpClient = new TcpClient())
            {
                try
                {
                    await tcpClient.ConnectAsync(ip, port);
                    return true;
                }
                catch (Exception)
                {
                    return false;
                }
            }
        }
    }
}
