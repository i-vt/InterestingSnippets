from TimeBasedOneTimePasswordTOTP import get_valid_totp_codes
import hashlib
import datetime
import random

DEFAULT_CONFIG = {
    "app_name": "TokenTrackerInMemory",
    "version": "1.0",
    "debug": True,
    "tokens": 500000,
    "hashing": "sha256",
    "token_length": 12,
    "preserve_token_time": 3600
}

class TokenGenerator:
    def __init__(self, config=None):
        self.config = config or DEFAULT_CONFIG
        self.debug = self.config.get("debug", False)
        self.hashing = self.config.get("hashing", "sha256").lower()
        self.num_tokens = self.config.get("tokens", 500000)
        self.token_length = self.config.get("token_length", 12)
        self.preserve_token_time = self.config.get("preserve_token_time", 3600)

        # In-memory state
        self.valid_tokens = []
        self.used_tokens = []
        self.last_updated = None

    def log(self, msg: str) -> None:
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

        timestamp = self.timestamp()
        self.used_tokens.append((timestamp, token))
        self.valid_tokens = [t for t in self.valid_tokens if t != token]

    def remove_old_used_tokens(self) -> None:
        now = datetime.datetime.utcnow()
        self.used_tokens = [
            (ts, token) for ts, token in self.used_tokens
            if self.is_within_preserve_token_time(ts)
        ]

    def remove_invalid_tokens_from_valid(self) -> None:
        used_hashes = {token for _, token in self.used_tokens}
        self.valid_tokens = [t for t in self.valid_tokens if t not in used_hashes]

    def generate_tokens(self, secret: str) -> None:
        valid_codes = get_valid_totp_codes(secret, time_step_minutes=5, skew_steps=1, length=self.token_length)
        self.remove_old_used_tokens()

        used_hashes = {token for _, token in self.used_tokens}
        result = []

        for seq in range(self.num_tokens):
            hashed = self.hash_token(valid_codes[1], seq)
            if hashed not in used_hashes:
                result.append(hashed)

        self.valid_tokens = result
        self.last_updated = datetime.datetime.utcnow()

    def current_tokens_expired(self) -> bool:
        if not self.last_updated:
            return True
        return (datetime.datetime.utcnow() - self.last_updated) > datetime.timedelta(minutes=5)

    def get_valid_tokens(self, secret: str):
        if self.current_tokens_expired():
            self.generate_tokens(secret)
        self.remove_invalid_tokens_from_valid()
        return self.valid_tokens

    def use_one_valid_token(self):
        if not self.valid_tokens:
            return None
        return self.valid_tokens[0]

    def use_one_valid_token_then_set_as_used(self):
        token = self.use_one_valid_token()
        if token:
            self.use_token(token)
        return token

if __name__ == "__main__":
    import sys
    tg = TokenGenerator()

    if len(sys.argv) < 2 or sys.argv[1].lower() != "generate":
        print("Usage:")
        print("  generate <secret> <quantity>")
        sys.exit(1)

    secret = sys.argv[2]
    tokens = tg.get_valid_tokens(secret)
    quantity = int(sys.argv[3])
    if quantity >= len(tokens): 
        print("Requesting too many tokens, check quantity parameter")
        sys.exit(1)
    tokens = random.sample(tokens,quantity)
    for token in tokens: print(token)
