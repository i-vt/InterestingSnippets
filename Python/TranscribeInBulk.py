import os
import json
import argparse
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed

import torch
import whisper


gpu_lock = threading.Lock()
write_lock = threading.Lock()


def collect_input_files(input_path):
    """
    Accept either a directory or a single audio file.
    Returns a sorted list of audio file paths.
    """
    supported_exts = (".ogg", ".mp3", ".wav", ".m4a", ".flac", ".aac", ".mp4", ".mpeg", ".mpga", ".webm")

    if os.path.isfile(input_path):
        if not input_path.lower().endswith(supported_exts):
            raise ValueError(f"Unsupported input file type: {input_path}")
        return [input_path]

    if os.path.isdir(input_path):
        files = [
            os.path.join(input_path, f)
            for f in sorted(os.listdir(input_path))
            if os.path.isfile(os.path.join(input_path, f)) and f.lower().endswith(supported_exts)
        ]
        return files

    raise ValueError(f"Invalid input path: {input_path}")


def transcribe_one(model, device, file_path):
    filename = os.path.basename(file_path)

    with gpu_lock:
        result = model.transcribe(
            file_path,
            fp16=(device == "cuda"),
            verbose=False,
        )

    return {
        "filename": filename,
        "transcript": result["text"].strip(),
        "context": [
            {
                "start": seg["start"],
                "end": seg["end"],
                "text": seg["text"].strip(),
            }
            for seg in result.get("segments", [])
        ],
    }


def ensure_output_path(output_path, split_output):
    """
    Create needed parent directories.
    - split_output=False: output_path is a file path
    - split_output=True: output_path is a directory path
    """
    if split_output:
        os.makedirs(output_path, exist_ok=True)
    else:
        parent = os.path.dirname(os.path.abspath(output_path))
        if parent:
            os.makedirs(parent, exist_ok=True)


def save_split_result(output_dir, item):
    """
    Save one transcription result as:
    original_audio_name.json
    """
    base_name = os.path.splitext(item["filename"])[0] + ".json"
    out_path = os.path.join(output_dir, base_name)

    with write_lock:
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(item, f, indent=2, ensure_ascii=False)


def transcribe_folder(input_path, output_path, model_size="medium", workers=4, split_output=False):
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Using device: {device}")

    model = whisper.load_model(model_size).to(device)
    input_files = collect_input_files(input_path)

    if not input_files:
        print("No supported audio files found.")
        return

    ensure_output_path(output_path, split_output)

    results = []
    results_lock = threading.Lock()

    def worker(file_path):
        print(f"Transcribing: {os.path.basename(file_path)}")
        item = transcribe_one(model, device, file_path)

        if split_output:
            save_split_result(output_path, item)
        else:
            with results_lock:
                results.append(item)

    max_workers = max(1, min(workers, len(input_files)))

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [executor.submit(worker, file_path) for file_path in input_files]
        for future in as_completed(futures):
            future.result()

    if split_output:
        print(f"Saved {len(input_files)} JSON file(s) to {output_path}")
        return

    results.sort(key=lambda x: x["filename"])

    if len(input_files) == 1:
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(results[0], f, indent=2, ensure_ascii=False)
        print(f"Saved single file output to {output_path}")
        return

    payload = {
        "model": model_size,
        "device": device,
        "count": len(results),
        "files": results,
    }

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)

    print(f"Saved combined output to {output_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Transcribe audio file(s) with Whisper into one JSON file or split JSON files"
    )
    parser.add_argument(
        "-i",
        "--input",
        required=True,
        help="Input audio file or directory containing audio files",
    )
    parser.add_argument(
        "-o",
        "--output",
        default="transcripts.json",
        help="Output JSON file, or output directory when --split-output is used",
    )
    parser.add_argument(
        "-m",
        "--model",
        default="medium",
        choices=["tiny", "base", "small", "medium", "large", "turbo"],
        help="Whisper model size",
    )
    parser.add_argument(
        "-w",
        "--workers",
        type=int,
        default=4,
        help="Number of worker threads",
    )
    parser.add_argument(
        "--split-output",
        action="store_true",
        help="Write one JSON file per input audio file; in this mode -o is an output directory",
    )

    args = parser.parse_args()

    transcribe_folder(
        input_path=args.input,
        output_path=args.output,
        model_size=args.model,
        workers=args.workers,
        split_output=args.split_output,
    )
