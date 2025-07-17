from TOTP import *  
import hashlib
import datetime
import os
import sys
import json

CONFIG_FILE = "TokenTracker.json"
DEFAULT_CONFIG = {
    "app_name": "TokenTracker",
    "version": "1.0",
    "debug": True,
    "tokens": 500000,
    "hashing": "sha256",
    "token_length": 12,
    "preserve_token_time": 3600,
    "valid_tokens_file": "valid_tokens.txt",
    "used_tokens_file": "used_tokens.txt",
    "last_updated_tokens_file": "last_updated_tokens_file.txt"
}

class TokenGenerator:
    def __init__(self):
        self.config = self.load_config()
        self.debug = self.config.get("debug", False)
        self.hashing = self.config.get("hashing", "sha256").lower()
        self.num_tokens = self.config.get("tokens", 500000)
        self.token_length = self.config.get("token_length", 12)
        self.preserve_token_time = self.config.get("preserve_token_time", 3600)
        self.valid_tokens_file = self.config.get("valid_tokens_file", "valid_tokens.txt")
        self.used_tokens_file = self.config.get("used_tokens_file", "used_tokens.txt")
        self.last_updated_tokens_file = self.config.get("last_updated_tokens_file", "last_updated_tokens_file.txt")

    def load_config(self):
        if not os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, "w") as f:
                json.dump(DEFAULT_CONFIG, f, indent=4)
        with open(CONFIG_FILE, "r") as f:
            return json.load(f)

    def log(self, msg: str):
        if self.debug:
            print(f"[DEBUG] {msg}")

    def timestamp(self) -> str:
        return datetime.datetime.utcnow().strftime("%Y%m%d%H%M%S")

    def is_within_preserve_token_time(self, other_ts: str) -> bool:
        fmt = "%Y%m%d%H%M%S"
        current_time = datetime.datetime.utcnow()
        other_time = datetime.datetime.strptime(other_ts, fmt)
        return abs((current_time - other_time).total_seconds()) <= self.preserve_token_time

    def hash_string(self, text: str) -> str:
        if self.hashing == "md5":
            return hashlib.md5(text.encode()).hexdigest()
        return hashlib.sha256(text.encode()).hexdigest()

    def hash_token(self, valid_code: str, sequence: int) -> str:
        return self.hash_string(valid_code + str(sequence))

    def use_token(self, token: str) -> None:
        if not token:
            raise ValueError("token_used should not be empty")
        entry = "\n" + self.timestamp() + "|" + token
        with open(self.used_tokens_file, "a") as f:
            f.write(entry)
        with open(self.valid_tokens_file, "r") as f:
            tokens = f.read().splitlines()
        with open(self.valid_tokens_file, "w") as f:
            f.write("\n".join(tokens[1:]) + "\n")

    def remove_old_used_tokens(self) -> None:
        if not os.path.exists(self.used_tokens_file):
            return
        with open(self.used_tokens_file, "r") as f:
            tokens = f.read().splitlines()
        relevant = [line for line in tokens if line and self.is_within_preserve_token_time(line.split("|")[0])]
        with open(self.used_tokens_file, "w") as f:
            f.write("\n".join(relevant) + "\n")

    def remove_invalid_tokens_from_new(self) -> None:
        if not os.path.exists(self.used_tokens_file) or not os.path.exists(self.valid_tokens_file):
            return
        with open(self.used_tokens_file, "r") as f:
            used_hashes = {line.split("|")[1] for line in f.read().splitlines() if line}
        with open(self.valid_tokens_file, "r") as f:
            valid = [line for line in f.read().splitlines()]
        filtered = [v for v in valid if v not in used_hashes]
        with open(self.valid_tokens_file, "w") as f:
            f.write("\n".join(filtered) + "\n")

    def generate_tokens(self, secret: str) -> list:
        valid_codes = get_valid_totp_codes(secret, time_step_minutes=5, skew_steps=1, length=self.token_length)
        self.remove_old_used_tokens()

        used_tokens = set()
        if os.path.exists(self.used_tokens_file):
            with open(self.used_tokens_file, "r") as f:
                used_tokens = {line.split("|")[1] for line in f.read().splitlines() if line}

        result = []
        for seq in range(self.num_tokens):
            hashed = self.hash_token(valid_codes[1], seq)
            if hashed not in used_tokens:
                result.append(hashed)

        with open(self.valid_tokens_file, "w") as f:
            f.write("\n".join(result) + "\n")
        open(self.last_updated_tokens_file, "w").write(self.timestamp())
        return result


    def current_tokens_in_file_expired(self):
        try:
            with open(self.last_updated_tokens_file, 'r') as file:
                timestamp_str = file.read().strip()

            last_updated = datetime.datetime.strptime(timestamp_str, '%Y%m%d%H%M%S')
            current_time = datetime.datetime.utcnow()
            time_diff = current_time - last_updated

            return time_diff > datetime.timedelta(minutes=5)

        except Exception as e:
            print(f"Error checking token timestamp: {e}")
            return True

    def get_current_tokens_from_file(self) -> list:
        if not os.path.exists(self.valid_tokens_file) or self.current_tokens_in_file_expired():
            return []
        with open(self.valid_tokens_file, "r") as f:
            return f.read().splitlines()

    def get_valid_tokens(self, secret: str) -> list:
        self.generate_tokens(secret)
        self.remove_invalid_tokens_from_new()
        return self.get_current_tokens_from_file()

    def use_one_valid_token(self) -> str:
        tokens = self.get_current_tokens_from_file()
        if not tokens:
            return None
        token = tokens[0]
        return token

    def use_one_valid_token_then_set_as_used(self) -> str:
        tokens = self.get_current_tokens_from_file()
        if not tokens:
            return None
        token = tokens[0]
        self.use_token(token)
        return token




# CLI interface
if __name__ == "__main__":
    tg = TokenGenerator()
    APP_NAME = tg.config.get("app_name", "TokenTracker")
    VERSION = tg.config.get("version", "1.0")

    if len(sys.argv) < 2:
        print(f"{APP_NAME} v{VERSION}")
        print("Usage:")
        print("  python script.py get <secret>")
        print("  python script.py getanduse")
        print("  python script.py getvalid")
        print("  python script.py use <token>")
        sys.exit(1)

    action = sys.argv[1]

    if action == "generate":
        if len(sys.argv) < 3:
            print("Error: Missing <secret> for get.")
            sys.exit(1)
        secret = sys.argv[2]
        tokens = tg.get_valid_tokens(secret)
        print(f"Tokens generated.")

    elif action == "getanduse":
        token = tg.use_one_valid_token_then_set_as_used()
        if token:
            print(f"Token issued (and marked as used): {token}")
        else:
            print("No valid tokens available, tokens missing or outdated.")

    elif action == "getvalid":
        token = tg.use_one_valid_token()
        if token:
            print(f"Token issued (and marked as used): {token}")
        else:
            print("No valid tokens available, tokens missing or outdated.")

    elif action == "use":
        if len(sys.argv) < 3:
            print("Error: Missing <token> to use.")
            sys.exit(1)

        token = sys.argv[2]
        valid_tokens = tg.get_current_tokens_from_file()
        if valid_tokens == []:
            print("Missing or outdated valid tokens.")
            sys.exit(1)
        elif token not in valid_tokens:
            print("Invalid or already used token.")
            sys.exit(1)
        tg.use_token(token)
        print(f"Token used: {token}")
