#!/usr/bin/env python3
"""
Speech-to-Text transcription using OpenAI Whisper.
Optimized for CPU with the small model.
"""

import sys
import whisper

def transcribe(audio_file: str) -> str:
    """Transcribe audio file to text using Whisper."""
    # Use tiny model for fast CPU transcription
    # Options: tiny (~1s), base (~2s), small (~5s), medium (~15s)
    model = whisper.load_model("tiny")
    
    result = model.transcribe(
        audio_file,
        language="en",  # Set to None for auto-detect, or "sv" for Swedish
        fp16=False,     # Disable fp16 for CPU (avoids warnings)
    )
    
    return result["text"].strip()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: transcribe.py <audio_file>", file=sys.stderr)
        sys.exit(1)
    
    audio_path = sys.argv[1]
    result = transcribe(audio_path)
    print(result)
