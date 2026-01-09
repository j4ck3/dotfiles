#!/usr/bin/env python3
"""
Speech-to-Text transcription using Faster Whisper.
Optimized for CPU with the small model.
"""

import sys
from faster_whisper import WhisperModel

def transcribe(audio_file: str) -> str:
    """Transcribe audio file to text using Whisper."""
    # Use small model for good balance of speed/accuracy on CPU
    # You can change to "tiny" for faster but less accurate, 
    # or "medium" for more accurate but slower
    model = WhisperModel("small", device="cpu", compute_type="int8")
    
    segments, info = model.transcribe(
        audio_file,
        beam_size=5,
        language="en",  # Set to None for auto-detect, or "sv" for Swedish
        vad_filter=True,  # Filter out silence
    )
    
    # Collect all transcribed text
    text_parts = []
    for segment in segments:
        text_parts.append(segment.text.strip())
    
    return " ".join(text_parts)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: transcribe.py <audio_file>", file=sys.stderr)
        sys.exit(1)
    
    audio_path = sys.argv[1]
    result = transcribe(audio_path)
    print(result)

