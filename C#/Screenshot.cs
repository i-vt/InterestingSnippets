using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Windows.Forms;

class Program
{
    static void Main()
    {
        // Calculate the total size of all screens combined
        int screenWidth = SystemInformation.VirtualScreen.Width;
        int screenHeight = SystemInformation.VirtualScreen.Height;
        int screenLeft = SystemInformation.VirtualScreen.Left;
        int screenTop = SystemInformation.VirtualScreen.Top;

        // Create a bitmap with the total size of all screens
        using (Bitmap bmp = new Bitmap(screenWidth, screenHeight))
        {
            // Draw the screens into the bitmap
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.CopyFromScreen(screenLeft, screenTop, 0, 0, bmp.Size);
            }

            // Save the bitmap to a file
            bmp.Save("screenshot.png", ImageFormat.Png);
        }

        Console.WriteLine("Screenshot taken.");
    }
}
