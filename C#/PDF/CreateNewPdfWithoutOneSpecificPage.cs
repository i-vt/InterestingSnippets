//using iTextSharp.text.pdf;

string inputPdf = "input.pdf"; 
string outputPdf = "output.pdf";

using (FileStream fs = new FileStream(outputPdf, FileMode.Create))
{
    using (PdfReader reader = new PdfReader(inputPdf))
    {
        int pageCount = reader.NumberOfPages;

        using (Document document = new Document())
        {
            using (PdfCopy copy = new PdfCopy(document, fs))
            {
                document.Open();

                for (int pageIndex = 1; pageIndex <= pageCount; pageIndex++)
                {
                    if (pageIndex != 25)
                    {
                        // Copy pages other than page 25 to the output PDF
                        PdfImportedPage page = copy.GetImportedPage(reader, pageIndex);
                        copy.AddPage(page);
                    }
                }

                document.Close();
            }
        }
    }
}
