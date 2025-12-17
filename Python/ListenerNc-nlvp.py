#!/usr/bin/env python3

import socket
import sys
import threading

HOST = "0.0.0.0"
PORT = 2020

def recv_loop(conn: socket.socket, peer: tuple):
    try:
        while True:
            data = conn.recv(4096)
            if not data:
                print(f"\n[!] Connection closed by {peer[0]}:{peer[1]}")
                break
            # Write raw bytes to stdout safely
            sys.stdout.write(data.decode(errors="replace"))
            sys.stdout.flush()
    except Exception as e:
        print(f"\n[!] Receive error: {e}")

def main():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((HOST, PORT))
        s.listen(1)
        print(f"[+] Listening on {HOST}:{PORT} ...")

        conn, addr = s.accept()
        print(f"[+] Connection from {addr[0]}:{addr[1]}")
        print("[*] Type to send. Ctrl+C to quit.\n")

        t = threading.Thread(target=recv_loop, args=(conn, addr), daemon=True)
        t.start()

        try:
            while True:
                line = sys.stdin.readline()
                if not line:  # stdin closed
                    break
                conn.sendall(line.encode())
        except KeyboardInterrupt:
            print("\n[*] Exiting...")
        finally:
            try:
                conn.shutdown(socket.SHUT_RDWR)
            except Exception:
                pass
            conn.close()

if __name__ == "__main__":
    main()
