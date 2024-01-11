import requests

def send_telegram_message(bot_token, chat_id, message):
    send_message_url = f"https://api.telegram.org/bot{bot_token}/sendMessage"

    # Parameters of the message
    params = {
        "chat_id": chat_id,
        "text": message
    }

    # Making the POST request to the Telegram Bot API
    response = requests.post(send_message_url, data=params)

    # Check for success
    if response.status_code == 200:
        print("Message sent successfully:",message)
    else:
        print(f"Failed to send message: {response.status_code}\n{response.text}")

def send_telegram_photo(bot_token, chat_id, photo, caption=''):
    # Telegram Bot API endpoint for sending photos
    send_photo_url = f"https://api.telegram.org/bot{bot_token}/sendPhoto"

    # Parameters of the message
    params = {
        "chat_id": chat_id,
        "photo": photo,
        "caption": caption
    }

    # Making the POST request to the Telegram Bot API
    response = requests.post(send_photo_url, data=params)

    # Check for success
    if response.status_code == 200:
        print("Photo sent successfully")
    else:
        print(f"Failed to send photo: {response.status_code}\n{response.text}")


