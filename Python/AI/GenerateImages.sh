#!/usr/bin/env python3
"""
gemini_image.py — генерация картинок через api.gserver.online (модель gemini-3.1-flash-image).

Только стандартная библиотека Python — никаких pip install.

Прокси зашит в скрипт и включён по умолчанию. Отключить — флагом --no-proxy.

Примеры:
    python gemini_image.py "красное яблоко на белом столе"
    python gemini_image.py "cyberpunk city at night" --size 1024x1024 --out city.jpg
    python gemini_image.py "a cat astronaut" --no-proxy
"""

import argparse
import base64
import json
import os
import re
import sys
import urllib.error
import urllib.request

API_KEY = "sk-ag-123"
BASE_URL = "https://api.gserver.online/v1"
MODEL = "gemini-3.1-flash-image"
PROXY = "http://user123:pass123@proxyprovider.local:4445"


def build_opener(use_proxy: bool) -> urllib.request.OpenerDirector:
    """Opener с зашитым прокси, либо без прокси вовсе (игнорируя *_PROXY из окружения)."""
    if use_proxy:
        return urllib.request.build_opener(
            urllib.request.ProxyHandler({"http": PROXY, "https": PROXY})
        )
    return urllib.request.build_opener(urllib.request.ProxyHandler({}))


def generate_image(prompt: str, size: str, n: int, timeout: int,
                   opener: urllib.request.OpenerDirector) -> dict:
    payload = {"model": MODEL, "prompt": prompt, "n": n, "size": size}
    req = urllib.request.Request(
        f"{BASE_URL}/images/generations",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {API_KEY}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with opener.open(req, timeout=timeout) as resp:
        return json.load(resp)


def save_image(item: dict, out_path: str, opener: urllib.request.OpenerDirector,
               timeout: int) -> tuple[str, int]:
    """API может вернуть b64_json, data-URI в url, или обычную http-ссылку."""
    raw = None
    if item.get("b64_json"):
        raw = base64.b64decode(item["b64_json"])
    elif item.get("url", "").startswith("data:"):
        # data:image/jpeg;base64,/9j/4AAQ...
        raw = base64.b64decode(item["url"].split(",", 1)[1])
    elif item.get("url"):
        with opener.open(item["url"], timeout=timeout) as r:
            raw = r.read()
    if not raw:
        raise RuntimeError(f"Не смог извлечь картинку из ответа: {list(item.keys())}")

    # Расширение по magic bytes, если в имени файла его нет
    if not re.search(r"\.(jpe?g|png|webp)$", out_path, re.I):
        ext = ".png" if raw[:4] == b"\x89PNG" else ".webp" if raw[:4] == b"RIFF" else ".jpg"
        out_path += ext
    with open(out_path, "wb") as f:
        f.write(raw)
    return out_path, len(raw)


def main() -> int:
    p = argparse.ArgumentParser(description="Генерация картинок через gserver.online")
    p.add_argument("prompt", help="текстовое описание картинки")
    p.add_argument("--size", default="1024x1024", help="например 1024x1024 (по умолчанию)")
    p.add_argument("--n", type=int, default=1, help="количество картинок (по умолчанию 1)")
    p.add_argument("--out", default="image", help="имя файла (по умолчанию image.jpg)")
    p.add_argument("--no-proxy", action="store_true",
                   help="отключить встроенный прокси (по умолчанию он включён)")
    p.add_argument("--timeout", type=int, default=300, help="таймаут запроса, сек (по умолчанию 300)")
    args = p.parse_args()

    use_proxy = not args.no_proxy
    opener = build_opener(use_proxy)
    print(f"Модель: {MODEL} | прокси: {'да' if use_proxy else 'нет'} | размер: {args.size}",
          file=sys.stderr)

    try:
        resp = generate_image(args.prompt, args.size, args.n, args.timeout, opener)
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code}: {e.read()[:500].decode(errors='replace')}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Ошибка: {type(e).__name__}: {e}", file=sys.stderr)
        return 1

    for i, item in enumerate(resp.get("data", [])):
        out = args.out if args.n == 1 else f"{args.out}_{i+1}"
        path, nbytes = save_image(item, out, opener, args.timeout)
        print(f"Сохранено: {path} ({nbytes / 1024:.0f} КБ)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
