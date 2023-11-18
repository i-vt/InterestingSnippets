using Microsoft.Win32;

public static void AddToStartupHKCU()
{
    string appName = "App";
    string appPath = @"C:\path\to\your\app.exe";

    RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true);
    key.SetValue(appName, appPath);
}
