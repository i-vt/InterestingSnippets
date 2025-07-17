import os
import sys
import time
import hmac
import base64
import struct
import hashlib
from datetime import datetime

def get_time_counter(time_step_minutes=5, skew_steps=1):
    now = datetime.utcnow()
    epoch = datetime(1970, 1, 1)
    seconds_since_epoch = int((now - epoch).total_seconds())
    time_step_seconds = time_step_minutes * 60
    current_counter = seconds_since_epoch // time_step_seconds
    return [current_counter + i for i in range(-skew_steps, skew_steps + 1)]

def generate_totp(secret: str, time_counter: int, length=12):
    counter_bytes = struct.pack(">Q", time_counter)
    hmac_hash = hmac.new(secret.encode(), counter_bytes, hashlib.sha512).digest()
    offset = hmac_hash[-1] & 0x0F
    truncated = hmac_hash[offset:offset + 10]
    base32_code = base64.b32encode(truncated).decode('utf-8').replace('=', '')
    return base32_code[:length]

def get_valid_totp_codes(secret: str, time_step_minutes=5, skew_steps=1, length=12):
    counters = get_time_counter(time_step_minutes, skew_steps)
    return [generate_totp(secret, counter, length) for counter in counters]

if __name__ == "__main__":
    if len(sys.argv) > 1:
        secret = sys.argv[1]
    else:
        secret = os.getenv("TOTP_SECRET")

    if not secret:
        print("Usage: python script.py <secret> or set TOTP_SECRET env variable")
        sys.exit(1)

    while True:
        print(datetime.utcnow())
        valid_codes = get_valid_totp_codes(secret, time_step_minutes=5, skew_steps=1, length=12)
        print("Valid TOTP codes:", valid_codes)
        time.sleep(60)
