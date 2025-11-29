import whisper
import argparse
import os

def main():
    parser = argparse.ArgumentParser(description="Transcribe or translate audio using Whisper")
    parser.add_argument("audio", help="Path to input .mp3 file")
    parser.add_argument("--model", default="base", help="Whisper model size (tiny, base, small, medium, large)")
    parser.add_argument("--translate", action="store_true", help="Translate to English instead of transcribing")
    parser.add_argument("--output", default="output.txt", help="Output text file")
    args = parser.parse_args()

    if not os.path.exists(args.audio):
        print("Error: Audio file not found")
        return

    print(f"Loading model: {args.model}")
    model = whisper.load_model(args.model)

    print("Processing audio...")
    result = model.transcribe(
        args.audio,
        task="translate" if args.translate else "transcribe"
    )

    text = result["text"]

    with open(args.output, "w", encoding="utf-8") as f:
        f.write(text.strip())

    print(f"\n✅ Done! Output saved to: {args.output}")
    print("\n--- TRANSCRIPTION ---")
    print(text.strip())

if __name__ == "__main__":
    main()

