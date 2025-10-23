using System;
using System.Runtime.InteropServices;
using System.Threading;

public class MousePointerJitter
{
    [DllImport("user32.dll")]
    static extern bool SetCursorPos(int X, int Y);

    [DllImport("user32.dll")]
    static extern bool GetCursorPos(out POINT lpPoint);

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int X;
        public int Y;
    }

    static void Main()
    {
        Random random = new Random();

        while (true)
        {
            // ms
            Thread.Sleep(5000);

            GetCursorPos(out POINT pos);

            int newX = pos.X + random.Next(-10, 11);
            int newY = pos.Y + random.Next(-10, 11);

            SetCursorPos(newX, newY);
        }
    }
}