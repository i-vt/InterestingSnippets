import argparse
import requests
import subprocess

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
        print(count1, count2)
        if count1 == count2:
            break
        count2 = count1
    return pages

def download_github_pages(pages_passed, force=False):
    for page in pages_passed:
        print("=====================//\nAttempting to download:", page.split("/")[2])
        if force:
            run_shell_command("git clone --force https://github.com" + page)
        else:
            run_shell_command("git clone https://github.com" + page)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Download GitHub repositories of a user (requires GIT installed).")
    parser.add_argument("username", help="GitHub username to fetch repositories for")
    parser.add_argument("--force", action="store_true", help="Force clone the repositories")

    args = parser.parse_args()

    pages = get_github_pages(args.username)
    download_github_pages(pages, force=args.force)
