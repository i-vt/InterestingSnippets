import os
import requests
import argparse

def search_samples(api_key, search_rule, limit):
    """
    Get hashes by given rule
    :param api_key: string - VirusTotal API key
    :param search_rule: string - the given rule
    :param limit: int - hash list length limit
    :return: list[string] - list of file hashes
    """
    url = "https://www.virustotal.com/api/v3/intelligence/search"
    headers = {
        "x-apikey": api_key
    }
    all_hashes = []
    max_limit = 300
    next_cursor = ""

    while limit > 0:
        params = {
            "query": search_rule,
            "limit": min(limit, max_limit),
        }
        if next_cursor:
            params["cursor"] = next_cursor

        response = requests.get(url, headers=headers, params=params)

        if response.status_code == 200:
            json_response = response.json()
            samples = json_response.get("data", [])
            hashes = [sample["id"] for sample in samples]
            all_hashes.extend(hashes)
            limit -= max_limit

            next_cursor = json_response.get("meta", {}).get("cursor", "")
            if not next_cursor:
                break
        else:
            print(f"Error: Unable to search samples. Status code: {response.status_code}")
            print(response.content)
            return []

    return all_hashes

def download_samples(api_key, hashes, path):
    """
    Download samples to the given file path
    :param api_key: string - VirusTotal API key
    :param hashes: list[string] - the given hash list
    :param path: string - the target download path
    """
    os.makedirs(path, exist_ok=True)
    for file_hash in hashes:
        url = f"https://www.virustotal.com/api/v3/files/{file_hash}/download"
        headers = {
            "x-apikey": api_key
        }
        response = requests.get(url, headers=headers)
        if response.status_code == 200:
            file_path = os.path.join(path, f"{file_hash}.bin")
            with open(file_path, "wb") as f:
                f.write(response.content)
            print(f"Sample saved as {file_path}")
        else:
            print(f"Error: Unable to download sample {file_hash}. Status code: {response.status_code}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Search and download malware samples from VirusTotal.")
    parser.add_argument("--api_key", required=True, help="Your VirusTotal API key")
    parser.add_argument("--search_rule", required=True, help="Search rule for samples")
    parser.add_argument("--limit", type=int, default=20, help="Maximum number of samples to fetch")
    parser.add_argument("--download_path", default="./downloads", help="Directory to save downloaded samples")

    args = parser.parse_args()

    hashes = search_samples(args.api_key, args.search_rule, args.limit)
    if hashes:
        download_samples(args.api_key, hashes, args.download_path)
