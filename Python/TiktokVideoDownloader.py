import requests
import re
import json
import os
import argparse
from urllib.parse import urlparse


class TikTokDownloader:
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/120.0.0.0 Safari/537.36"
            ),
            "Accept-Language": "en-US,en;q=0.9",
            "Referer": "https://www.tiktok.com/",
        })

    # ----------------------------
    # Step 1: Fetch HTML
    # ----------------------------
    def fetch_page(self, url: str) -> str:
        resp = self.session.get(url, timeout=30)
        resp.raise_for_status()
        return resp.text

    # ----------------------------
    # Step 2: Extract JSON blob
    # ----------------------------
    def extract_json(self, html: str) -> dict:
        patterns = [
            r'<script id="SIGI_STATE"[^>]*>(.*?)</script>',
            r'<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>(.*?)</script>',
        ]

        for pattern in patterns:
            match = re.search(pattern, html)
            if match:
                try:
                    return json.loads(match.group(1))
                except json.JSONDecodeError:
                    continue

        raise RuntimeError("Could not find TikTok JSON data in page")

    # ----------------------------
    # Step 3: Get video URL
    # ----------------------------
    def extract_video_url(self, data: dict) -> str:
        if "ItemModule" in data:
            item_module = data["ItemModule"]
            video_id = next(iter(item_module))
            video_info = item_module[video_id]["video"]

            for key in [
                "downloadAddr",
                "playAddr",
                "playAddrH264",
                "playAddrBytevc1",
            ]:
                if key in video_info and video_info[key]:
                    return video_info[key]

        try:
            scope = data["__DEFAULT_SCOPE__"]["webapp.video-detail"]
            video_info = scope["itemInfo"]["itemStruct"]["video"]

            for key in [
                "downloadAddr",
                "playAddr",
                "playAddrH264",
                "playAddrBytevc1",
            ]:
                if key in video_info and video_info[key]:
                    return video_info[key]
        except Exception:
            pass

        raise RuntimeError("Could not locate video URL in JSON")

    # ----------------------------
    # Step 4: Download video
    # ----------------------------
    def download_video(self, video_url: str, output_path: str):
        with self.session.get(video_url, stream=True, timeout=60) as r:
            r.raise_for_status()
            with open(output_path, "wb") as f:
                for chunk in r.iter_content(chunk_size=1024 * 1024):
                    if chunk:
                        f.write(chunk)

    # ----------------------------
    # Main method
    # ----------------------------
    def download(self, tiktok_url: str, output_path: str = None):
        print("Fetching page...")
        html = self.fetch_page(tiktok_url)

        print("Extracting JSON...")
        data = self.extract_json(html)

        print("Finding video URL...")
        video_url = self.extract_video_url(data)
        print(f"Video URL found:\n{video_url}\n")

        if not output_path:
            parsed = urlparse(tiktok_url)
            video_id = parsed.path.rstrip("/").split("/")[-1]
            output_path = f"tiktok_{video_id}.mp4"

        print("Downloading video...")
        self.download_video(video_url, output_path)

        print(f"✅ Saved to: {os.path.abspath(output_path)}")


# -----------------------------------
# CLI ENTRYPOINT
# -----------------------------------
def main():
    parser = argparse.ArgumentParser(description="Download TikTok video")
    parser.add_argument("url", help="TikTok video URL")
    parser.add_argument(
        "-o",
        "--output",
        help="Output file path (optional)",
        default=None,
    )

    args = parser.parse_args()

    downloader = TikTokDownloader()
    downloader.download(args.url, args.output)


if __name__ == "__main__":
    main()
