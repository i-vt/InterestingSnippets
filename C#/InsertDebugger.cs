// Can be used to understand how software works via debugging DLLs as it specifies DLLs to be loaded into each process that calls User32.dll. 
// Requires to be ran as an admin


using System;
using Microsoft.Win32;

namespace AppInit_DLL_Example
{
    class Program
    {
        static void Main(string[] args)
        {
            try
            {
                // Path to the AppInit_DLLs registry key
                string keyPath = @"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows";

                // Open the registry key with write access
                RegistryKey key = Registry.LocalMachine.OpenSubKey(keyPath, true);

                if (key == null)
                {
                    Console.WriteLine("Failed to open the registry key.");
                    return;
                }

                // Specify the path to your debugger DLL
                string dllPath = @"C:\Path\To\Your\DLL.dll";

                // Set the value of the AppInit_DLLs key
                key.SetValue("AppInit_DLLs", dllPath, RegistryValueKind.String);

                // Enable AppInit_DLLs - IMPORTANT: This makes the system load the specified DLLs
                key.SetValue("LoadAppInit_DLLs", 1, RegistryValueKind.DWord);

                Console.WriteLine("AppInit_DLLs updated successfully.");
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error: " + ex.Message);
            }
        }
    }
}
