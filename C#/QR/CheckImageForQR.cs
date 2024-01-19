//using ZXing;
//using System.Drawing;

string imagePath = "image_path.png"; 
string specificPayload = "your_specific_payload"; 

using (Bitmap bitmap = (Bitmap)Image.FromFile(imagePath))
{
    BarcodeReader barcodeReader = new BarcodeReader();
    Result result = barcodeReader.Decode(bitmap);

    if (result != null && result.Text == specificPayload)
    {
        Console.WriteLine("Image contains a QR code with the specific payload.");
    }
    else
    {
        Console.WriteLine("Image does not contain a QR code with the specific payload.");
    }
}
