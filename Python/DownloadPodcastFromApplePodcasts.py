import time
from seleniumwire import webdriver
from selenium.webdriver.common.by import By

# Initialize the Chrome driver using selenium-wire
driver = webdriver.Chrome()

# URL of the website
url = "https://podcasts.apple.com/us/podcast/podcastgoesherelmao"

# Open the website
driver.get(url)

# Wait for the page to load and for the play button to become clickable
time.sleep(5)

# Find and click the play button by its data-testid attribute
button = driver.find_element(By.CSS_SELECTOR, '[data-testid="button-icon-play"]')
button.click()

# Wait a few seconds for the MP3 file request to be made
time.sleep(5)

# Capture network requests and find the one related to the MP3 file
mp3_url = None
for request in driver.requests:
    if request.response:
        if "mp3" in request.url:  # Check if the URL contains 'mp3' (adjust if needed)
            mp3_url = request.url
            print("MP3 URL:", mp3_url)
            break  # Stop after finding the first match

# If an MP3 URL is found, download the file
if mp3_url:
    import requests

    # Download the MP3 file using the requests library
    response = requests.get(mp3_url)

    # Save the file locally
    with open("downloaded_podcast.mp3", "wb") as file:
        file.write(response.content)
    
    print("Download completed successfully!")
else:
    print("MP3 URL not found.")

# Optionally close the browser
driver.quit()
