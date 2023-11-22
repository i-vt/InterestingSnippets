using System;
using System.Drawing;
using AForge.Video;
using AForge.Video.DirectShow;

class CameraCapture
{
    private FilterInfoCollection videoDevices;
    private VideoCaptureDevice videoSource;

    public CameraCapture()
    {
        // Enumerate video devices
        videoDevices = new FilterInfoCollection(FilterCategory.VideoInputDevice);

        if (videoDevices.Count == 0)
            throw new ApplicationException("No video devices found.");

        // Create video source
        videoSource = new VideoCaptureDevice(videoDevices[0].MonikerString);
        videoSource.NewFrame += new NewFrameEventHandler(video_NewFrame);
        
        // Start the video source
        videoSource.Start();
    }

    private void video_NewFrame(object sender, NewFrameEventArgs eventArgs)
    {
        // Get new frame
        Bitmap bitmap = (Bitmap)eventArgs.Frame.Clone();
        
        // Process the frame (for example, save it to a file)
        bitmap.Save("camera_snapshot.jpg", System.Drawing.Imaging.ImageFormat.Jpeg);

        // Stop the video source after capturing the image
        videoSource.SignalToStop();
    }
}

class Program
{
    static void Main(string[] args)
    {
        try
        {
            CameraCapture capture = new CameraCapture();
        }
        catch (ApplicationException ex)
        {
            Console.WriteLine("Error: " + ex.Message);
        }
    }
}
