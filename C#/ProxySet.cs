using Microsoft.Win32;
using System;

namespace SetProxy
{
    class Program
    {
        static void SetProxy(string proxyAddress)
        {
            try
            {
                const string userRoot = "HKEY_CURRENT_USER";
                const string subkey = "Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings";
                const string keyName = userRoot + "\\" + subkey;

                // Enable proxy
                Registry.SetValue(keyName, "ProxyEnable", 1);

                // Set proxy address
                Registry.SetValue(keyName, "ProxyServer", proxyAddress);
            }
            catch (Exception ex)
            {
                Console.WriteLine("Failed to set proxy: " + ex.Message);
            }
        }

        static void DisableProxy()
        {
            try
            {
                const string userRoot = "HKEY_CURRENT_USER";
                const string subkey = "Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings";
                const string keyName = userRoot + "\\" + subkey;

                // Disable proxy
                Registry.SetValue(keyName, "ProxyEnable", 0);
            }
            catch (Exception ex)
            {
                Console.WriteLine("Failed to disable proxy: " + ex.Message);
            }
        }

        static void Main(string[] args)
        {
            if (args.Length < 1)
            {
                Console.WriteLine("Usage: cliSetProxy.exe <proxy_address>");
                Console.WriteLine("To disable the proxy, use: cliSetProxy.exe disable");
                return;
            }

            if (args[0].ToLower() == "disable")
            {
                DisableProxy();
            }
            else
            {
                SetProxy(args[0]);
            }
        }
    }
}
