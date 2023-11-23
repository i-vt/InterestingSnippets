using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Threading;

public class MousePointerJitter : Form
{
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);

    private System.Windows.Forms.Timer timer;
    private Random random = new Random();

    public MousePointerJitter()
    {
        timer = new System.Windows.Forms.Timer();
        timer.Interval = 5000; // 5 seconds
        timer.Tick += new EventHandler(TimerEventProcessor);
        timer.Start();
    }

    private void TimerEventProcessor(Object myObject, EventArgs myEventArgs)
    {
        Cursor.Position = new System.Drawing.Point(Cursor.Position.X + random.Next(-10, 10), Cursor.Position.Y + random.Next(-10, 10));
    }

    public static void Main()
    {
        Application.Run(new MousePointerJitter());
    }
}
