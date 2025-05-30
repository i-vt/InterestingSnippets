import random
import html
import re
import codecs
import sys
import time
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options

def get_html_from_page(url: str) -> str:
    # Set up Chrome options
    chrome_options = Options()
    chrome_options.add_argument("--headless")  # Run in headless mode
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")

    # Set up the Chrome driver
    service = Service()  # Add path if needed: Service(executable_path="path/to/chromedriver")
    driver = webdriver.Chrome(service=service, options=chrome_options)

    try:
        driver.get(url)
        time.sleep(random.randint(2000,4000)/100)  # Wait for the page to load
        html_content = driver.page_source
    finally:
        driver.quit()

    return html_content

def clean_single_url(raw_url):
    url = raw_url.replace('\\/', '/')
    url = url.replace('&amp;', "&")
    url = bytes(url, "utf-8").decode("unicode_escape")
    url = html.unescape(url)
    return url

def clean_instagram_urls(raw_text):
    raw_urls = re.findall(r'https:\\/\\/[^ \n"<>\']+', raw_text)
    cleaned_urls = []

    for raw_url in raw_urls:
        url = clean_single_url(raw_url)
        url = url.replace("</BaseURL><SegmentBase", "")
        cleaned_urls.append(url)

    return cleaned_urls

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python script.py <Instagram URL>")
        sys.exit(1)

    input_url = sys.argv[1]
    page_html = get_html_from_page(input_url)

    for i in page_html.split('"'):
        if "http" not in i:
            continue
        if ".mp4" in i:
            cleaned = clean_instagram_urls(i)
            if cleaned:
                print(cleaned[0])
                break
