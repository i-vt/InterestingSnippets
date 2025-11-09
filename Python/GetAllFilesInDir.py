import os

def get_all_dirs(start_dir: str = "/"):
    pages = []
    for root, dirs, files in os.walk(start_dir):
        for filename in files:
            page_path = os.path.join(root, filename)
            pages.append(page_path)
    return pages
