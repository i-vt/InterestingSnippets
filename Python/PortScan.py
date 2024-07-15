import socket

def scan_ports(host, start_port, end_port):
    open_ports = []
    for port in range(start_port, end_port + 1):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            print("scanning: ", port) 
            s.settimeout(1)
            result = s.connect_ex((host, port))
            if result == 0:
                open_ports.append(port)
    return open_ports

if __name__ == "__main__":
    host = input("Enter the host to scan: ")
    start_port = int(input("Enter the start port: "))
    end_port = int(input("Enter the end port: "))

    print(f"Scanning {host} from port {start_port} to {end_port}...")

    open_ports = scan_ports(host, start_port, end_port)

    if open_ports:
        print("Open ports:")
        for port in open_ports:
            print(f"Port {port} is open")
    else:
        print("No open ports found")
