import requests
import time
import csv
import argparse
import sys

API_KEY = 'yourapikeygohere_cuzIaintgivingumine.:)'  # Get your API key from https://ipinfo.io/

def load_ips(filename):
    try:
        with open(filename, 'r') as file:
            return [line.strip() for line in file if line.strip()]
    except FileNotFoundError:
        print(f"Error: Input file '{filename}' not found.")
        sys.exit(1)

def get_ip_info(ip):
    try:
        response = requests.get(f'https://ipinfo.io/{ip}/json?token={API_KEY}', timeout=5)
        response.raise_for_status()
        return response.json()
    except requests.RequestException as e:
        print(f"Error fetching info for IP {ip}: {e}")
        return {}

def save_to_csv(filename, data, headers):
    try:
        with open(filename, 'w', newline='', encoding='utf-8') as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=headers, delimiter='|')
            writer.writeheader()
            writer.writerows(data)
    except Exception as e:
        print(f"Error writing to CSV file '{filename}': {e}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Fetch IP information and save to CSV.")
    parser.add_argument('-i', '--input', type=str, default='ips.txt', help='Input file with list of IPs (default: ips.txt)')
    parser.add_argument('-o', '--output', type=str, default='ips.csv', help='Output CSV file (default: ips.csv)')
    parser.add_argument('-d', '--delay', type=float, default=0.5, help='Delay between requests in seconds (default: 0.5)')

    args = parser.parse_args()

    ips = load_ips(args.input)
    output_data = []
    headers = ["ip", "hostname", "city", "region", "country", "loc", "org", "postal", "timezone"]

    for count, ip in enumerate(ips, start=1):
        info = get_ip_info(ip)
        row = {
            "ip": ip,
            "hostname": info.get("hostname", "Unknown"),
            "city": info.get("city", "Unknown"),
            "region": info.get("region", "Unknown"),
            "country": info.get("country", "Unknown"),
            "loc": info.get("loc", "Unknown"),
            "org": info.get("org", "Unknown"),
            "postal": info.get("postal", "Unknown"),
            "timezone": info.get("timezone", "Unknown"),
        }
        output_data.append(row)
        print(f"[{count}] IP: {ip}, Location: {row['city']}, {row['region']}, {row['country']}, Provider: {row['org']}")
        time.sleep(args.delay)

    save_to_csv(args.output, output_data, headers)
    print(f"\nData saved to '{args.output}'.")

if __name__ == "__main__":
    main()
