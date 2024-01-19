using iTextSharp.text;
using iTextSharp.text.pdf;
using System;
using System.IO;

private void IsImageFile(string directoryPathWithImages, string pdfOutputPath, bool bolScalePageToImageSize)
{
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
                        
                        iTextSharp.text.Image image = iTextSharp.text.Image.GetInstance(imageFile);
                        if (bolScalePageToImageSize)
                        {
                            float imageWidth = image.ScaledWidth;
                            float imageHeight = image.ScaledHeight;
                            document.SetPageSize(new iTextSharp.text.Rectangle(imageWidth, imageHeight)
                        }
                        else
                        {
                            image.ScaleToFit(document.PageSize.Width, document.PageSize.Height);
                        }
                        image.SetAbsolutePosition(0,0);
                        document.NewPage();
                        document.Add(image);
                    }
                }
                
                document.Close();
            }
        }
    }
}
private bool IsImageFile(string filePath)
{
    string[] imageExtensions = { ".jpg", ".jpeg", ".png", ".gif", ".bmp" }; 
    string fileExtension = System.IO.Path.GetExtension(filePath).ToLower();
    return Array.Exists(imageExtensions, ext => ext == fileExtension);
}
