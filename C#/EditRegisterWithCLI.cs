using System;
using Microsoft.Win32;

namespace cliRegedit
{
    class Program
    {
        static void Main(string[] args)
        {
            try
            {
                if(args.Length < 3)
                {
                    Console.WriteLine("Usage: cliRegedit <Hive> <Path> <Name> <Value>");
                    Console.WriteLine("Example: cliRegedit HKLM SOFTWARE\\MyApp KeyName KeyValue");
                    return;
                }

                string hive = args[0];
                string path = args[1];
                string name = args[2];
                string value = args[3];

                RegistryKey baseKey;

                switch (hive.ToUpper())
                {
                    case "HKLM":
                        baseKey = Registry.LocalMachine;
                        break;
                    case "HKCU":
                        baseKey = Registry.CurrentUser;
                        break;
                    case "HKCR":
                        baseKey = Registry.ClassesRoot;
                        break;
                    case "HKU":
                        baseKey = Registry.Users;
                        break;
                    case "HKCC":
                        baseKey = Registry.CurrentConfig;
                        break;
                    default:
                        Console.WriteLine("Invalid hive. Choose from: HKLM, HKCU, HKCR, HKU, HKCC");
                        return;
                }

                using (RegistryKey key = baseKey.OpenSubKey(path, true))
                {
                    if (key == null)
                    {
                        Console.WriteLine($"Path not found: {path}");
                        return;
                    }
                    key.SetValue(name, value);
                    Console.WriteLine($"Value set successfully: {name} = {value}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error: " + ex.Message);
            }
        }
    }
}
