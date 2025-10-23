using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

// no FORMS usings
class Program
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    // monitor delegate
    private delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor, IntPtr dwData);

    [DllImport("user32.dll")]
    private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);

    [DllImport("user32.dll")]
    private static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);

    [StructLayout(LayoutKind.Sequential)]
    public struct MONITORINFO
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }

    static RECT virtualScreen = new RECT { Left = int.MaxValue, Top = int.MaxValue, Right = int.MinValue, Bottom = int.MinValue };

    static void Main()
    {
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, MonitorEnum, IntPtr.Zero);

        int width = virtualScreen.Right - virtualScreen.Left;
        int height = virtualScreen.Bottom - virtualScreen.Top;

        using (var bmp = new Bitmap(width, height))
        {
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.CopyFromScreen(virtualScreen.Left, virtualScreen.Top, 0, 0, bmp.Size);
            }

            bmp.Save("screenshot.png", ImageFormat.Png);
        }

        Console.WriteLine("Screenshot taken.");
    }

    private static bool MonitorEnum(IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor, IntPtr dwData)
    {
        MONITORINFO info = new MONITORINFO();
        info.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
        if (GetMonitorInfo(hMonitor, ref info))
        {
            if (info.rcMonitor.Left < virtualScreen.Left) virtualScreen.Left = info.rcMonitor.Left;
            if (info.rcMonitor.Top < virtualScreen.Top) virtualScreen.Top = info.rcMonitor.Top;
            if (info.rcMonitor.Right > virtualScreen.Right) virtualScreen.Right = info.rcMonitor.Right;
            if (info.rcMonitor.Bottom > virtualScreen.Bottom) virtualScreen.Bottom = info.rcMonitor.Bottom;
        }
        return true;
    }
}
