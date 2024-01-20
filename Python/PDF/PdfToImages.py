import fitz  # PyMuPDF

# Input PDF file path
pdf_file = 'your_pdf_file.pdf'

# Output folder where images will be saved
output_folder = 'output_images/'

# Open the PDF file
pdf_document = fitz.open(pdf_file)

# Iterate through each page in the PDF
for page_number in range(pdf_document.page_count):
    page = pdf_document.load_page(page_number)
    
    # Convert the page to an image
    pix = page.get_pixmap()
    
    # Save the image with the desired file extension (e.g., 'png', 'jpeg', 'tiff')
    image_file_path = f'{output_folder}page_{page_number + 1}.png'
    pix.writePNG(image_file_path)

# Close the PDF document
pdf_document.close()
