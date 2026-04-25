import http.server
import socketserver
import os

PORT = 2020
# Increased from 64KB to 8MB. This reduces I/O operations by a factor of 128,
# massively speeding up uploads on fast networks/devices.
CHUNK_SIZE = 8 * 1024 * 1024 

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

        if content_length == 0:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b'Empty request!')
            return

        success, message = self.handle_multipart_stream(boundary, content_length)

        if success:
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'File uploaded successfully!\n')
        else:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(message.encode())

    def handle_multipart_stream(self, boundary, content_length):
        stop_boundary = b"\r\n--" + boundary
        
        bytes_read = 0
        # Read the initial chunk to grab headers
        initial_read = min(CHUNK_SIZE, content_length)
        header_chunk = self.rfile.read(initial_read)
        bytes_read += len(header_chunk)

        header_end = header_chunk.find(b'\r\n\r\n')
        if header_end == -1:
            return False, "Could not find file headers in the first chunk."

        part_headers = header_chunk[:header_end]
        filename = None
        for line in part_headers.split(b'\r\n'):
            if b'filename="' in line:
                filename = line.split(b'filename="')[1].split(b'"')[0].decode('utf-8', errors='ignore')
                break

        if not filename:
            return False, "No file found in the request."

        filename = os.path.basename(filename)
        if not filename:
            filename = "uploaded_file.bin"

        # The data payload starts exactly 4 bytes after the \r\n\r\n
        data_start_idx = header_end + 4
        buffer = header_chunk[data_start_idx:]
        
        remaining = content_length - bytes_read

        with open(filename, 'wb') as f:
            while True:
                stop_idx = buffer.find(stop_boundary)
                if stop_idx != -1:
                    # Boundary found! Write the exact payload bytes and stop.
                    f.write(buffer[:stop_idx])
                    
                    # Fast-drain the rest of the socket so the connection doesn't hang
                    while remaining > 0:
                        discard_len = min(CHUNK_SIZE, remaining)
                        self.rfile.read(discard_len)
                        remaining -= discard_len
                    return True, "Success"

                # Write everything except the length of the boundary to avoid chopping it in half
                safe_to_write_len = len(buffer) - len(stop_boundary)
                if safe_to_write_len > 0:
                    f.write(buffer[:safe_to_write_len])
                    buffer = buffer[safe_to_write_len:]

                if remaining <= 0:
                    break

                # Pull the next massive chunk
                read_size = min(CHUNK_SIZE, remaining)
                chunk = self.rfile.read(read_size)
                if not chunk:
                    break # Failsafe for dropped connections
                    
                remaining -= len(chunk)
                buffer += chunk

            if buffer:
                f.write(buffer)
        
        return True, "Success"

    def do_GET(self):
        if self.headers.get('X-Forwarded-Proto') == 'https':
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b"HTTPS not supported.")
            return

        if self.path == '/':
            self.path = 'index.html'

        return http.server.SimpleHTTPRequestHandler.do_GET(self)

Handler = SimpleHTTPRequestHandler

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    print("\n" + "/-" * 60)
    print(f"High-Speed Server running on port {PORT}.")
    print("Test via curl using:\n")
    print('    curl -F "file=@<path_to_large_file>" http://localhost:2020/')
    print("-\\" * 60 + "\n")
    httpd.serve_forever()
