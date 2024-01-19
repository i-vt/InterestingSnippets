using iTextSharp.text;
using iTextSharp.text.pdf;
using System;
using System.IO;


string[] imageFiles = Directory.GetFiles("image_directory_path");
string outputPdf = "output.pdf";

using (FileStream fs = new FileStream(outputPdf, FileMode.Create))
{
    using (Document document = new Document())
    {
        using (PdfWriter writer = PdfWriter.GetInstance(document, fs))
        {
            document.Open();
            
            foreach (string imageFile in imageFiles)
            {
                if (IsImageFile(imageFile))
                {
                    Image image = Image.GetInstance(imageFile);
                    document.Add(image);
                }
            }
            
            document.Close();
        }
    }
}

private static bool IsImageFile(string filePath)
{
    string[] imageExtensions = { ".jpg", ".jpeg", ".png", ".gif", ".bmp" }; 
    string fileExtension = Path.GetExtension(filePath).ToLower();
    return Array.Exists(imageExtensions, ext => ext == fileExtension);
}
