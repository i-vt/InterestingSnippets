string inputPdf = "input.pdf"; 

using (PdfReader reader = new PdfReader(inputPdf))
{
    int pageCount = reader.NumberOfPages;

    for (int pageIndex = 1; pageIndex <= pageCount; pageIndex++)
    {
        PdfDictionary page = reader.GetPageN(pageIndex);
        PdfArray content = page.GetAsArray(PdfName.CONTENTS);

        if (content != null)
        {
            foreach (PdfObject obj in content.ArrayList)
            {
                if (obj is PRStream stream)
                {
                    PdfImageObject image = new PdfImageObject(stream);
                    
                    if (image.GetImageBytes() != null)
                    {
                        byte[] imageData = image.GetImageAsBytes();

                        File.WriteAllBytes($"image_page_{pageIndex}.png", imageData);
                    }
                }
            }
        }
    }
}
