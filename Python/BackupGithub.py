import argparse
import requests
import subprocess
import os
import shutil
import datetime

def timestamp() -> str:
    current = datetime.datetime.now()
    return current.strftime("%Y%m%d%H%M%S")

def run_shell_command(command):
    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            shell=True
        )
        if result.returncode == 0:
            print("Command succeeded with output:")
            print(result.stdout)
            return {"success": True, "stdout": result.stdout, "stderr": ""}
        else:
            print("Command failed with error:")
            print(result.stderr)
            return {"success": False, "stdout": "", "stderr": result.stderr}
    except Exception as e:
        print(f"An error occurred: {e}")
        return {"success": False, "stdout": "", "stderr": str(e)}

def curl(url, user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.3"):
    headers = {
        "User-Agent": user_agent
    }
    try:
        response = requests.get(url, headers=headers)
        response.raise_for_status()
        return response.text
    except requests.RequestException as e:
        return f"Request failed: {e}"

def get_github_pages(username_passed, limit_pages=10000):
    count1, count2 = 0, 0
    pages = []
    for page in range(1, limit_pages):
        url = f"https://github.com/{username_passed}?page={page}&tab=repositories"
        curl_response = curl(url)
        for dir in curl_response.split('"'):
            if username_passed in dir and list(dir).count("/") == 2 and "?" not in dir and "<" not in dir:
                pages.append(dir)
                print(dir, len(pages))
                count1 = len(pages)
        if count1 == count2:
            break
        count2 = count1
    return pages

def ensure_folder_exists(path):
    if not os.path.exists(path):
        os.makedirs(path)
        print(f"Created directory: {path}")

def download_github_pages(pages_passed, dir_passed="./"):
    now = timestamp()
    filepath = os.path.join(dir_passed, now)
    ensure_folder_exists(filepath)
    for page in pages_passed:
        repo_name = page.split("/")[2]
        print("=====================//\nAttempting to download:", repo_name)
        run_shell_command(f"git clone https://github.com{page} {filepath}/{repo_name}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Download GitHub repositories of a user.")
    parser.add_argument("username", help="GitHub username to fetch repositories for")
    parser.add_argument("--path", default="./", help="Directory to save downloaded repositories")
    args = parser.parse_args()

    pages = get_github_pages(args.username)
    download_github_pages(pages, dir_passed=args.path)
