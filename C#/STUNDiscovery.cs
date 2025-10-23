using System;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Threading.Tasks;

class Program
{
    static async Task Main()
    {
        // example with public STUN
        string stunHost = "stun.l.google.com";
        int stunPort = 19302;

        var externalEndpoint = await StunDiscoverExternalEndPoint(stunHost, stunPort);
        if (externalEndpoint != null)
        {
            Console.WriteLine($"external IP and PORT: {externalEndpoint.Address}:{externalEndpoint.Port}");
        }
        else
        {
            Console.WriteLine("ERR");
        }
    }

    // --- STUN probe implementation (minimal, supports XOR-MAPPED-ADDRESS for IPv4) ---
    static async Task<IPEndPoint?> StunDiscoverExternalEndPoint(string stunHost, int stunPort)
    {
        // Resolve host
        var addresses = await Dns.GetHostAddressesAsync(stunHost);
        if (addresses == null || addresses.Length == 0) return null;
        var server = new IPEndPoint(addresses[0], stunPort);

        using var udp = new UdpClient();
        udp.Client.SendTimeout = 3000;
        udp.Client.ReceiveTimeout = 3000;

        // Build STUN binding request
        var tranId = RandomNumberGenerator.GetBytes(12);
        const uint MagicCookie = 0x2112A442;
        byte[] header = new byte[20];
        // Message Type: 0x0001 (Binding Request)
        header[0] = 0x00; header[1] = 0x01;
        // Message Length: 0x0000 (no attributes)
        header[2] = 0x00; header[3] = 0x00;
        // Magic cookie
        header[4] = (byte)((MagicCookie >> 24) & 0xFF);
        header[5] = (byte)((MagicCookie >> 16) & 0xFF);
        header[6] = (byte)((MagicCookie >> 8) & 0xFF);
        header[7] = (byte)((MagicCookie >> 0) & 0xFF);
        // Transaction ID
        Buffer.BlockCopy(tranId, 0, header, 8, 12);

        await udp.SendAsync(header, header.Length, server);

        var receiveTask = udp.ReceiveAsync();
        var completed = await Task.WhenAny(receiveTask, Task.Delay(3000));
        if (completed != receiveTask) return null;

        var res = receiveTask.Result;
        byte[] data = res.Buffer;
        if (data.Length < 20) return null;

        // Verify transaction ID and magic cookie
        if (data[0] != 0x01 || data[1] != 0x01) return null; // not Binding Success Response
                                                             // Check transaction id
        for (int i = 0; i < 12; i++) if (data[8 + i] != tranId[i]) return null;

        // Parse attributes
        int offset = 20;
        while (offset + 4 <= data.Length)
        {
            ushort attrType = (ushort)((data[offset] << 8) | data[offset + 1]);
            ushort attrLen = (ushort)((data[offset + 2] << 8) | data[offset + 3]);
            offset += 4;
            if (offset + attrLen > data.Length) break;

            if (attrType == 0x0020) // XOR-MAPPED-ADDRESS
            {
                // Format: 0x00 | family(1) | X-Port(2) | X-Address
                if (attrLen >= 8)
                {
                    byte family = data[offset + 1];
                    if (family == 0x01) // IPv4
                    {
                        ushort xport = (ushort)((data[offset + 2] << 8) | data[offset + 3]);
                        uint xaddr = (uint)((data[offset + 4] << 24) | (data[offset + 5] << 16) | (data[offset + 6] << 8) | (data[offset + 7]));
                        ushort port = (ushort)(xport ^ (MagicCookie >> 16));
                        uint addr = xaddr ^ MagicCookie;
                        var ipBytes = new byte[4]
                        {
                                (byte)((addr >> 24) & 0xFF),
                                (byte)((addr >> 16) & 0xFF),
                                (byte)((addr >> 8) & 0xFF),
                                (byte)(addr & 0xFF)
                        };
                        var ip = new IPAddress(ipBytes);
                        return new IPEndPoint(ip, port);
                    }
                }
            }

            // advance (attributes are padded to 4-byte boundary)
            int pad = (4 - (attrLen % 4)) % 4;
            offset += attrLen + pad;
        }

        return null;
    }
}