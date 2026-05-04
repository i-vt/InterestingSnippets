"""Generate a CSV of realistic fake female email addresses with weighted domain distribution."""

import csv
import random
import argparse
from faker import Faker

fake = Faker()

DOMAINS = {
    "gmail.com": 0.40,
    "outlook.com": 0.25,
    "hotmail.com": 0.15,
    "yahoo.com": 0.10,
    "icloud.com": 0.05,
    "protonmail.com": 0.03,
    "aol.com": 0.02,
}

DOMAIN_NAMES = list(DOMAINS.keys())
DOMAIN_WEIGHTS = list(DOMAINS.values())

USERNAME_PATTERNS = [
    # first.last / last.first
    lambda f, l: f"{f}.{l}",
    lambda f, l: f"{l}.{f}",
    # concatenated
    lambda f, l: f"{f}{l}",
    lambda f, l: f"{l}{f}",
    # separated
    lambda f, l: f"{f}_{l}",
    lambda f, l: f"{f}-{l}",
    lambda f, l: f"{l}_{f}",
    lambda f, l: f"{l}-{f}",
    # initial-based
    lambda f, l: f"{f[0]}{l}",
    lambda f, l: f"{f[0]}.{l}",
    lambda f, l: f"{f[0]}_{l}",
    lambda f, l: f"{f}{l[0]}",
    lambda f, l: f"{f[0]}{l[0]}{random.randint(100, 9999)}",
    # with numbers
    lambda f, l: f"{f}{random.randint(10, 9999)}",
    lambda f, l: f"{f}.{l}{random.randint(1, 99)}",
    lambda f, l: f"{l}{f[0]}{random.randint(1, 99)}",
    lambda f, l: f"{f[0]}.{l}{random.randint(10, 999)}",
    lambda f, l: f"{f}_{l}{random.randint(1, 999)}",
    lambda f, l: f"{f}-{l}{random.randint(1, 99)}",
    lambda f, l: f"{f}{l}{random.randint(1, 99)}",
    lambda f, l: f"{l}{f}{random.randint(10, 99)}",
    # with birth-year-style suffix
    lambda f, l: f"{f}.{l}{random.randint(80, 99)}",
    lambda f, l: f"{f}{l}{random.choice(['00', '01', '02', '03', '04', '05'])}",
    lambda f, l: f"{f}.{l}.{random.randint(1, 99)}",
    # double-dot / underscore combos
    lambda f, l: f"{f[0]}.{l}.{random.randint(1, 999)}",
    lambda f, l: f"{f}_{random.randint(100, 9999)}",
    lambda f, l: f"{l}_{f}{random.randint(1, 9)}",
    # name-only / nickname-style
    lambda f, l: f"{f}{f[-1]}{random.randint(10, 999)}",
    lambda f, l: f"{''.join([f[0], l[0], f[-1]])}{random.randint(10, 999)}",
    # truncated last name
    lambda f, l: f"{f}.{l[:4]}",
    lambda f, l: f"{f}_{l[:3]}{random.randint(1, 99)}",
    lambda f, l: f"{f}{l[:3]}",
    # double initial
    lambda f, l: f"{f[0]}{f[0]}{l}",
    lambda f, l: f"{f[0]}{l[0]}{l}",
    lambda f, l: f"{f}.{f[0]}.{l}",
    # middle-initial-style (faked)
    lambda f, l: f"{f}.{random.choice('abcdefghijklmnoprstw')}.{l}",
    lambda f, l: f"{f}{random.choice('abcdefghijklmnoprstw')}{l}",
    lambda f, l: f"{f[0]}{random.choice('abcdefghijklmnoprstw')}{l}",
    # repeated first name chars (cutesy)
    lambda f, l: f"{f}{f[0:2]}{random.randint(1, 99)}",
    lambda f, l: f"{'x' * random.randint(1, 3)}{f}{random.randint(1, 99)}",
    # the / real / official prefix
    lambda f, l: f"the.{f}.{l}",
    lambda f, l: f"real{f}{l}",
    lambda f, l: f"its{f}{l}",
    lambda f, l: f"the{f}{random.randint(1, 99)}",
    # common word + name combos
    lambda f, l: f"{random.choice(['miss', 'lady', 'lil', 'just'])}{f}",
    lambda f, l: f"{random.choice(['miss', 'lady', 'lil', 'just'])}.{f}.{l}",
    lambda f, l: f"{random.choice(['miss', 'mz', 'ms'])}{f}{random.randint(1, 999)}",
    # reversed name
    lambda f, l: f"{f[::-1]}{random.randint(10, 99)}",
    lambda f, l: f"{f[::-1]}.{l}",
    # full year suffixes (2000s kid style)
    lambda f, l: f"{f}.{l}{random.randint(1990, 2006)}",
    lambda f, l: f"{f}{l}{random.randint(1985, 2005)}",
    lambda f, l: f"{f}_{random.randint(1990, 2006)}",
    lambda f, l: f"{f[0]}{l}{random.randint(1990, 2005)}",
    # short number padding
    lambda f, l: f"{f}.{l}{str(random.randint(1, 9)).zfill(2)}",
    lambda f, l: f"{f}{str(random.randint(1, 99)).zfill(3)}",
    # underscore + dot mixed
    lambda f, l: f"{f}_{l}.{random.randint(1, 99)}",
    lambda f, l: f"{f[0]}_{l}.{random.randint(10, 999)}",
    # triple combo (first + last + first initial)
    lambda f, l: f"{f}{l}{f[0]}",
    lambda f, l: f"{l}{f}{l[0]}",
    # name + random word
    lambda f, l: f"{f}.{random.choice(['love', 'star', 'rose', 'grace', 'belle', 'sky', 'joy', 'luna', 'gem', 'angel'])}",
    lambda f, l: f"{random.choice(['sweet', 'happy', 'cool', 'cute', 'bright', 'sunny', 'lovely'])}{f}",
    lambda f, l: f"{f}{random.choice(['xo', 'xx', 'luv', 'babe', 'angel', 'star'])}{random.randint(1, 99)}",
    # all-initials + numbers
    lambda f, l: f"{f[0]}{l[0]}{random.randint(1000, 99999)}",
    lambda f, l: f"{f[0]}.{l[0]}.{random.randint(100, 9999)}",
    # name doubling
    lambda f, l: f"{f}{f}",
    lambda f, l: f"{f}{f}{random.randint(1, 99)}",
    # hyphenated with number in the middle
    lambda f, l: f"{f}{random.randint(1, 9)}{l}",
    lambda f, l: f"{f}.{random.randint(1, 9)}.{l}",
]


def generate_female_email() -> str:
    first = fake.first_name_female()
    last = fake.last_name()
    username = random.choice(USERNAME_PATTERNS)(first, last).lower()
    domain = random.choices(DOMAIN_NAMES, weights=DOMAIN_WEIGHTS, k=1)[0]
    return f"{username}@{domain}"


def main():
    parser = argparse.ArgumentParser(description="Generate fake female email addresses.")
    parser.add_argument("-n", "--count", type=int, default=6000, help="Number of emails to generate (default: 6000)")
    parser.add_argument("-o", "--output", default="female_emails.csv", help="Output CSV filename (default: female_emails.csv)")
    parser.add_argument("--seed", type=int, default=None, help="Random seed for reproducibility")
    args = parser.parse_args()

    if args.seed is not None:
        Faker.seed(args.seed)
        random.seed(args.seed)

    emails: set[str] = set()
    max_attempts = args.count * 10  # safety valve to avoid infinite loops
    attempts = 0

    while len(emails) < args.count and attempts < max_attempts:
        emails.add(generate_female_email())
        attempts += 1

    if len(emails) < args.count:
        print(f"Warning: only generated {len(emails)}/{args.count} unique emails after {max_attempts} attempts.")

    with open(args.output, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["email"])
        for email in sorted(emails):
            writer.writerow([email])

    print(f"Generated {len(emails)} emails → {args.output}")


if __name__ == "__main__":
    main()
