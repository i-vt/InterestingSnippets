import http.server
import socketserver
import cgi

PORT = 2020

class SimpleHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        # Downgrade HTTPS message if detected (note: not handled in pure http.server)
        if self.headers.get('X-Forwarded-Proto') == 'https':
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b"HTTPS not supported, please use HTTP.")
            return
        
        form = cgi.FieldStorage(
            fp=self.rfile,
            headers=self.headers,
            environ={'REQUEST_METHOD': 'POST'}
        )
        form_file = form['file']
        
        if form_file.filename:
            with open(form_file.filename, 'wb') as f:
                f.write(form_file.file.read())
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'File uploaded successfully!')
        else:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b'No file uploaded!')
            
    def do_GET(self):
        # Downgrade HTTPS message if detected (note: not handled in pure http.server)
        if self.headers.get('X-Forwarded-Proto') == 'https':
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b"HTTPS not supported, please use HTTP.")
            return

        if self.path == '/':
            self.path = 'index.html'
        elif self.path == '/curl-help':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'Use curl to upload files: curl -F "file=@<filename>" http://localhost:2020/')
            return
        return http.server.SimpleHTTPRequestHandler.do_GET(self)

Handler = SimpleHTTPRequestHandler

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    print(f"Serving on port {PORT}. You can upload files using curl with the following command:")
    print(f'curl -F "file=@path_to_your_file" http://localhost:{PORT}/')
    httpd.serve_forever()
