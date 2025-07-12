import ssl
import socket
from datetime import datetime

def test_domain(domain):
    context = ssl.create_default_context()

    try:
        with socket.create_connection((domain, 443), timeout=5) as sock:
            with context.wrap_socket(sock, server_hostname=domain) as ssock:
                cert = ssock.getpeercert()
                print(f"\n✅ {domain} is HTTPS reachable")
                print("-" * 40)
                print(f"Issuer       : {cert.get('issuer')}")
                print(f"Subject      : {cert.get('subject')}")
                print(f"Valid From   : {cert.get('notBefore')}")
                print(f"Valid Until  : {cert.get('notAfter')}")
                print("SANs         :", end=" ")

                sans = next((ext[1] for ext in cert.get('subjectAltName', [])), None)
                if sans:
                    print(", ".join([s[1] for s in cert['subjectAltName']]))
                else:
                    print("None")
                print("-" * 40)

    except Exception as e:
        print(f"❌ {domain} failed TLS check: {e}")

# --------- Test List of Domains ----------
domains = open("domains.txt").read().split("\n")
for domain in domains:
    if len(domain) < 3 or " " in domain: continue
    test_domain(domain)
