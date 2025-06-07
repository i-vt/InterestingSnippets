# FYI: non-compliant w/ RFC 6238; pyotp can be used for that.

from datetime import datetime
import hmac
import hashlib
import struct
import time
import base64

def get_time_counter(time_step_minutes=5, skew_steps=1):
    """
    Returns a list of time counters (integers) for current, previous, and next steps
    """
    now = datetime.utcnow()
    epoch = datetime(1970, 1, 1)
    seconds_since_epoch = int((now - epoch).total_seconds())
    time_step_seconds = time_step_minutes * 60
    current_counter = seconds_since_epoch // time_step_seconds
    return [current_counter + i for i in range(-skew_steps, skew_steps + 1)]

def generate_totp(secret: str, time_counter: int, length=12):
    """
    Generates alphanumeric TOTP code from a secret and time counter using HMAC-SHA512 and Base32 encoding
    """
    counter_bytes = struct.pack(">Q", time_counter)
    hmac_hash = hmac.new(secret.encode(), counter_bytes, hashlib.sha512).digest()

    # Use dynamic truncation to get a 4-byte slice (optional but consistent with TOTP)
    offset = hmac_hash[-1] & 0x0F
    truncated = hmac_hash[offset:offset + 10]  # use more bytes for longer codes

    # Base32 encode and clean up
    base32_code = base64.b32encode(truncated).decode('utf-8').replace('=', '')
    return base32_code[:length]

def get_valid_totp_codes(secret: str, time_step_minutes=5, skew_steps=1, length=12):
    """
    Returns a list of valid alphanumeric TOTP codes for the current ± skew time windows
    """
    counters = get_time_counter(time_step_minutes, skew_steps)
    return [generate_totp(secret, counter, length) for counter in counters]

if __name__ == "__main__":
    while True:
        print(datetime.utcnow())
        secret = "bob"  # Replace with your shared secret
        valid_codes = get_valid_totp_codes(secret, time_step_minutes=5, skew_steps=1, length=12)
        print("Valid TOTP codes:", valid_codes)
        time.sleep(60)
