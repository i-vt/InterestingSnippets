import http.server
import socketserver
import os
import tempfile
from urllib.parse import parse_qs
from http import HTTPStatus
from io import BytesIO

PORT = 2020

class SimpleHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        if self.headers.get('X-Forwarded-Proto') == 'https':
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b"HTTPS not supported, please use HTTP.")
            return

        content_type = self.headers.get('Content-Type')
        if not content_type or not content_type.startswith('multipart/form-data'):
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b'Content-Type must be multipart/form-data')
            return

        boundary = content_type.split("boundary=")[-1].encode()
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)

        parts = body.split(b"--" + boundary)
        for part in parts:
            if b'Content-Disposition' in part and b'name="file"' in part:
                headers, file_data = part.split(b'\r\n\r\n', 1)
                file_data = file_data.rstrip(b"\r\n")

                filename = None
                for line in headers.split(b"\r\n"):
                    if b"Content-Disposition" in line:
                        parts = line.decode().split(';')
                        for p in parts:
                            if p.strip().startswith("filename="):
                                filename = p.split('=')[1].strip().strip('"')

                if filename:
                    with open(filename, 'wb') as f:
                        f.write(file_data)
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(b'File uploaded successfully!')
                    return

        self.send_response(400)
        self.end_headers()
        self.wfile.write(b'No file uploaded!')

    def do_GET(self):
        if self.headers.get('X-Forwarded-Proto') == 'https':
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b"HTTPS not supported, please use HTTP.")
            return

        if self.path == '/':
            self.path = 'index.html'

        return http.server.SimpleHTTPRequestHandler.do_GET(self)

Handler = SimpleHTTPRequestHandler

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    print("\n" + "-" * 60)
    print(f"Server is running on port {PORT}.")
    print("You can upload files using the following methods:\n")

    print("Upload Instructions:")
    print("  • Linux/macOS:")
    print('    curl -F "file=@<filename>" http://localhost:2020/')
    print("  • Windows (PowerShell script):")
    print("    https://raw.githubusercontent.com/i-vt/InterestingSnippets/refs/heads/main/Windows/Powershell/UploadFilePOST.ps1\n")

    print("Notes:")
    print("  • Ensure that 'index.html' is present in the same directory.")
    print("  • Files in this directory can be accessed directly by URL, e.g., /someotherfile.txt")
    print("-" * 60 + "\n")


    httpd.serve_forever()
