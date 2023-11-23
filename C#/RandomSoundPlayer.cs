using System;
using System.Media;
using System.Windows.Forms;
using System.Threading;

public class RandomSoundPlayer : Form
{
    private System.Windows.Forms.Timer timer;
    private string[] soundFiles = { "sound1.wav", "sound2.wav", "sound3.wav" }; // Paths to sound files
    private Random random = new Random();

    public RandomSoundPlayer()
    {
        timer = new System.Windows.Forms.Timer();
        timer.Interval = 10000; // 10 seconds
        timer.Tick += new EventHandler(TimerEventProcessor);
        timer.Start();
    }

    private void TimerEventProcessor(Object myObject, EventArgs myEventArgs)
    {
        int index = random.Next(soundFiles.Length);
        SoundPlayer player = new SoundPlayer(soundFiles[index]);
        player.Play();
    }

    public static void Main()
    {
        Application.Run(new RandomSoundPlayer());
    }
}
