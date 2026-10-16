import whisper
import argparse
import os
from typing import Optional
from pathlib import Path


class WhisperTranscriber:
    """
    A class to handle Whisper model loading and audio transcription/translation.
    The model is loaded once during instantiation and can be reused for multiple files.
    """
    
    def __init__(self, model_size: str = "base"):
        """
        Initialize the transcriber with a specific Whisper model.
        
        Args:
            model_size: Whisper model size (tiny, base, small, medium, large)
        """
        self.model_size = model_size
        self.model = None
        self._load_model()
    
    def _load_model(self) -> None:
        """Load the Whisper model into memory."""
        print(f"Loading Whisper model: {self.model_size}")
        self.model = whisper.load_model(self.model_size)
        print(f"✅ Model '{self.model_size}' loaded successfully")
    
    def process_audio(
        self, 
        audio_path: str, 
        task: str = "transcribe",
        output_path: Optional[str] = None
    ) -> str:
        """
        Process an audio file using the loaded model.
        
        Args:
            audio_path: Path to the input audio file
            task: Either "transcribe" or "translate"
            output_path: Optional path to save the output text file
            
        Returns:
            The transcribed/translated text
            
        Raises:
            FileNotFoundError: If the audio file doesn't exist
            ValueError: If task is not 'transcribe' or 'translate'
        """
        if not os.path.exists(audio_path):
            raise FileNotFoundError(f"Audio file not found: {audio_path}")
        
        if task not in ["transcribe", "translate"]:
            raise ValueError(f"Invalid task: {task}. Must be 'transcribe' or 'translate'")
        
        print(f"Processing audio: {audio_path}")
        print(f"Task: {task}")
        
        result = self.model.transcribe(audio_path, task=task)
        text = result["text"].strip()
        
        if output_path:
            self._save_output(text, output_path)
        
        return text
    
    def _save_output(self, text: str, output_path: str) -> None:
        """
        Save the transcribed text to a file.
        
        Args:
            text: The text to save
            output_path: Path to the output file
        """
        output_file = Path(output_path)
        output_file.parent.mkdir(parents=True, exist_ok=True)
        
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(text)
        
        print(f"✅ Output saved to: {output_path}")
    
    def translate(self, audio_path: str, output_path: Optional[str] = None) -> str:
        """
        Translate audio to English.
        
        Args:
            audio_path: Path to the input audio file
            output_path: Optional path to save the output
            
        Returns:
            The translated text
        """
        return self.process_audio(audio_path, task="translate", output_path=output_path)
    
    def transcribe(self, audio_path: str, output_path: Optional[str] = None) -> str:
        """
        Transcribe audio in its original language.
        
        Args:
            audio_path: Path to the input audio file
            output_path: Optional path to save the output
            
        Returns:
            The transcribed text
        """
        return self.process_audio(audio_path, task="transcribe", output_path=output_path)


def main():
    """CLI entry point for the Whisper transcriber."""
    parser = argparse.ArgumentParser(
        description="Transcribe or translate audio using Whisper"
    )
    parser.add_argument("audio", help="Path to input audio file")
    parser.add_argument(
        "--model", 
        default="base", 
        help="Whisper model size (tiny, base, small, medium, large)"
    )
    parser.add_argument(
        "--translate", 
        action="store_true", 
        help="Translate to English instead of transcribing"
    )
    parser.add_argument(
        "--output", 
        default="output.txt", 
        help="Output text file"
    )
    
    args = parser.parse_args()
    
    try:
        # Initialize the transcriber (model is loaded once)
        transcriber = WhisperTranscriber(model_size=args.model)
        
        # Process the audio file
        task = "translate" if args.translate else "transcribe"
        text = transcriber.process_audio(
            audio_path=args.audio,
            task=task,
            output_path=args.output
        )
        
        # Display results
        print("\n--- RESULT ---")
        print(text)
        
    except FileNotFoundError as e:
        print(f"❌ Error: {e}")
        return 1
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return 1
    
    return 0


if __name__ == "__main__":
    exit(main())
