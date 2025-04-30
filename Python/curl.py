import requests

def curl(url, user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.3"):
    """
    Mimics a curl request with a custom User-Agent header.

    Parameters:
        url (str): The URL to fetch.
        user_agent (str): The User-Agent string to use in the request.

    Returns:
        str: The content of the response.

    Raises:
        requests.RequestException: If the request fails.
    """
    headers = {
        "User-Agent": user_agent
    }

    try:
        response = requests.get(url, headers=headers)
        response.raise_for_status()  # Raises an error for bad responses (4xx or 5xx)
        return response.text
    except requests.RequestException as e:
        return f"Request failed: {e}"

# Example usage:
# html = curl_with_user_agent("https://httpbin.org/user-agent", "CustomUserAgent/1.0")
# print(html)
