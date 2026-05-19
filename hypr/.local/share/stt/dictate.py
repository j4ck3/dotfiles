#!/usr/bin/env python3
"""
Live speech-to-text: stream microphone audio, type into the focused window.

Uses Vosk for streaming recognition and wtype for Wayland text injection.
"""

from __future__ import annotations

import json
import os
import signal
import stat
import subprocess
import sys
from datetime import datetime

from vosk import KaldiRecognizer, Model, SetLogLevel

SAMPLE_RATE = 16000
CHUNK_BYTES = 4000
DEFAULT_MODEL = os.path.expanduser("~/.local/share/vosk-model-small-en-us-0.15")
LOG_FILE = os.environ.get("STT_DICTATE_LOG", "/tmp/stt-dictate.log")
FOCUS_ADDRESS = os.environ.get("STT_FOCUS_ADDRESS", "").strip()


def wayland_env() -> dict[str, str]:
    env = os.environ.copy()
    env.setdefault("WAYLAND_DISPLAY", "wayland-1")
    env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    return env


def log(msg: str) -> None:
    line = f"[{datetime.now():%H:%M:%S}] {msg}\n"
    with open(LOG_FILE, "a", encoding="utf-8") as fh:
        fh.write(line)


def refocus_target() -> None:
    """Restore the window focused when dictation started (status UI may steal focus)."""
    if not FOCUS_ADDRESS or FOCUS_ADDRESS == "0x0":
        return
    env = wayland_env()
    try:
        active = subprocess.run(
            ["hyprctl", "activewindow", "-j"],
            capture_output=True,
            text=True,
            timeout=2,
            check=True,
            env=env,
        )
        current = json.loads(active.stdout).get("address", "")
        if current == FOCUS_ADDRESS:
            return
        subprocess.run(
            ["hyprctl", "dispatch", "focuswindow", f"address:{FOCUS_ADDRESS}"],
            check=False,
            timeout=2,
            env=env,
        )
    except (subprocess.SubprocessError, json.JSONDecodeError, OSError) as exc:
        log(f"refocus failed: {exc}")


def wtype_text(text: str) -> bool:
    if not text:
        return True
    refocus_target()
    try:
        subprocess.run(
            ["wtype", "-"],
            input=text.encode("utf-8"),
            check=True,
            timeout=30,
            env=wayland_env(),
        )
        return True
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError) as exc:
        log(f"wtype failed for {text!r}: {exc}")
        return False


def wtype_backspaces(count: int) -> None:
    if count <= 0:
        return
    refocus_target()
    env = wayland_env()
    for _ in range(count):
        subprocess.run(
            ["wtype", "-k", "BackSpace"],
            check=False,
            timeout=5,
            env=env,
        )


def parse_text(payload: str) -> str:
    if not payload:
        return ""
    data = json.loads(payload)
    return (data.get("text") or data.get("partial") or "").strip()


class LiveTyper:
    """Type partial results incrementally; commit finals with a trailing space."""

    def __init__(self, *, partials: bool) -> None:
        self._typed = ""
        self._partials = partials

    def sync(self, text: str, *, final: bool) -> None:
        if not text:
            return
        if not self._partials and not final:
            return

        if text.startswith(self._typed):
            delta = text[len(self._typed) :]
            if delta:
                wtype_text(delta)
            self._typed = text
        else:
            wtype_backspaces(len(self._typed))
            wtype_text(text)
            self._typed = text

        if final:
            if self._typed and not self._typed.endswith(" "):
                wtype_text(" ")
            log(f"typed: {text!r}")
            self._typed = ""


def stdin_is_audio_pipe() -> bool:
    """True only when audio is piped in (e.g. stt-dictate-test), not /dev/null from Hyprland."""
    if os.environ.get("STT_DICTATE_FROM_STDIN") == "1":
        return True
    try:
        return stat.S_ISFIFO(os.fstat(0).st_mode)
    except OSError:
        return False


def audio_source() -> list[str]:
    # parec often returns no audio on PipeWire; ffmpeg -f pulse matches stt-record.
    source = os.environ.get("PULSE_SOURCE", "").strip() or "default"
    return [
        "ffmpeg",
        "-nostdin",
        "-hide_banner",
        "-f",
        "pulse",
        "-i",
        source,
        "-ar",
        str(SAMPLE_RATE),
        "-ac",
        "1",
        "-f",
        "s16le",
        "-loglevel",
        "error",
        "pipe:1",
    ]


def run_from_stdin(model_path: str, *, partials: bool) -> int:
    SetLogLevel(-1)
    log("loading model")
    model = Model(model_path)
    rec = KaldiRecognizer(model, SAMPLE_RATE)
    rec.SetWords(False)
    log("model ready")

    typer = LiveTyper(partials=partials)
    audio = sys.stdin.buffer

    while True:
        chunk = audio.read(CHUNK_BYTES)
        if not chunk:
            break
        if rec.AcceptWaveform(chunk):
            typer.sync(parse_text(rec.Result()), final=True)
        else:
            typer.sync(parse_text(rec.PartialResult()), final=False)

    typer.sync(parse_text(rec.FinalResult()), final=True)
    return 0


def run_live(model_path: str, *, partials: bool) -> int:
    """Load model first, then capture mic (avoids losing audio during model load)."""
    SetLogLevel(-1)
    log("loading model")
    model = Model(model_path)
    rec = KaldiRecognizer(model, SAMPLE_RATE)
    rec.SetWords(False)
    cmd = audio_source()
    source = os.environ.get("PULSE_SOURCE", "").strip() or "default"
    log(f"model ready, capturing from {source}")

    capture = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    typer = LiveTyper(partials=partials)
    bytes_in = 0

    try:
        assert capture.stdout is not None
        while True:
            chunk = capture.stdout.read(CHUNK_BYTES)
            if not chunk:
                err = capture.stderr.read().decode("utf-8", errors="replace") if capture.stderr else ""
                if err.strip():
                    log(f"capture stderr: {err.strip()}")
                log(f"capture ended (code {capture.poll()}, {bytes_in} bytes)")
                break
            bytes_in += len(chunk)
            if rec.AcceptWaveform(chunk):
                typer.sync(parse_text(rec.Result()), final=True)
            else:
                typer.sync(parse_text(rec.PartialResult()), final=False)
    finally:
        if capture.poll() is None:
            capture.terminate()
            capture.wait(timeout=2)

    typer.sync(parse_text(rec.FinalResult()), final=True)
    return 0


def main() -> int:
    model_path = os.environ.get("VOSK_MODEL_PATH", DEFAULT_MODEL)
    partials = os.environ.get("STT_DICTATE_PARTIALS", "0") == "1"

    if not os.path.isdir(model_path):
        print(
            f"Vosk model not found at {model_path}\n"
            "https://alphacephei.com/vosk/models",
            file=sys.stderr,
        )
        return 1

    def on_stop(*_: object) -> None:
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, on_stop)

    if stdin_is_audio_pipe():
        return run_from_stdin(model_path, partials=partials)
    return run_live(model_path, partials=partials)


if __name__ == "__main__":
    sys.exit(main())
