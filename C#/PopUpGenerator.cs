using System;
using System.Windows.Forms;
using System.Threading;

public class PopupGenerator : Form
{
    private System.Windows.Forms.Timer timer;

    public PopupGenerator()
    {
        timer = new System.Windows.Forms.Timer();
        timer.Interval = 5000; // 5 seconds
        timer.Tick += new EventHandler(TimerEventProcessor);
        timer.Start();
    }

    private void TimerEventProcessor(Object myObject, EventArgs myEventArgs)
    {
        MessageBox.Show("Surprise!", "Popup");
    }

    public static void Main()
    {
        Application.Run(new PopupGenerator());
    }
}
