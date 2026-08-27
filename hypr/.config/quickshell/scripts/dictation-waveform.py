#!/usr/bin/env python3
"""Voice-gated dictation waveform — FFT bands, smoothed, speech-gated."""

from __future__ import annotations

import fcntl
import math
import os
import struct
import subprocess
import sys
import time

try:
    import webrtcvad
except ImportError:
    sys.stderr.write("python-webrtcvad missing (pacman: python-webrtcvad)\n")
    sys.exit(1)

BARS = 48
SAMPLE_RATE = 16000
FRAME_MS = 20
FRAME_BYTES = SAMPLE_RATE * FRAME_MS // 1000 * 2  # 640 @ 16 kHz mono s16le
FFT_SIZE = 256
MIN_BAR = 0.05
IDLE_BAR = 0.06
SNR_OPEN = 3.2   # ~10 dB above noise floor to open gate
SNR_HOLD = 2.0   # lower threshold while speech already active
SPEECH_BAND_LO = 5   # ~200 Hz
SPEECH_BAND_HI = 36  # ~4 kHz
VAD_HISTORY = 3      # require 2 of last 3 VAD-positive frames

# Reused FFT buffers (avoid per-frame alloc).
_FFT_RE = [0.0] * FFT_SIZE
_FFT_IM = [0.0] * FFT_SIZE

# Log-spaced speech bands (~120 Hz – 7 kHz).
_BAND_EDGES = [
    int((120 * (8000 / 120) ** (i / BARS)) * FFT_SIZE / SAMPLE_RATE)
    for i in range(BARS + 1)
]
_BAND_EDGES[0] = max(2, _BAND_EDGES[0])
_BAND_EDGES[-1] = min(FFT_SIZE // 2 - 1, _BAND_EDGES[-1])

# Hann window (precomputed).
_HANN = [0.5 * (1 - math.cos(2 * math.pi * i / (FFT_SIZE - 1))) for i in range(FFT_SIZE)]


def pcm_rms(pcm: bytes) -> float:
    n = len(pcm) // 2
    if n <= 0:
        return 0.0
    samples = struct.unpack(f"<{n}h", pcm)
    mean_sq = sum(s * s for s in samples) / n
    return mean_sq**0.5


def speech_band_ratio(raw: list[float]) -> float:
    core = sum(raw[SPEECH_BAND_LO:SPEECH_BAND_HI])
    total = sum(raw) + 1e-6
    return core / total


class SpeechGate:
    """VAD + noise floor + spectral shape — reject ambient noise."""

    __slots__ = ("active", "floor", "hits", "vad_ring")

    def __init__(self) -> None:
        self.active = False
        self.floor = 180.0
        self.hits = 0
        self.vad_ring: list[bool] = []

    def _update_floor(self, rms: float, vad_hit: bool) -> None:
        if vad_hit or rms > self.floor * SNR_OPEN:
            return
        if rms < self.floor * 1.6:
            self.floor = self.floor * 0.992 + rms * 0.008

    def classify(self, pcm: bytes, raw: list[float], vad_hit: bool) -> bool:
        rms = pcm_rms(pcm)
        self._update_floor(rms, vad_hit)

        self.vad_ring.append(vad_hit)
        if len(self.vad_ring) > VAD_HISTORY:
            self.vad_ring.pop(0)
        vad_votes = sum(self.vad_ring)

        ratio = speech_band_ratio(raw)
        snr_min = SNR_HOLD if self.active else SNR_OPEN
        rms_ok = rms > self.floor * snr_min
        spectral_ok = ratio > 0.52
        vad_ok = vad_votes >= 2

        if self.active:
            self.hits = min(6, self.hits + 1) if (vad_ok and rms_ok) else max(0, self.hits - 1)
            self.active = self.hits > 0 and (vad_ok or rms_ok)
        else:
            open_ok = vad_ok and rms_ok and spectral_ok and vad_hit
            if open_ok:
                self.hits = min(6, self.hits + 2)
            else:
                self.hits = max(0, self.hits - 1)
            self.active = self.hits >= 2

        return self.active


def _fft(re: list[float], im: list[float]) -> None:
    n = len(re)
    j = 0
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j ^= bit
        if i < j:
            re[i], re[j] = re[j], re[i]
            im[i], im[j] = im[j], im[i]

    length = 2
    while length <= n:
        ang = -2 * math.pi / length
        w_re = math.cos(ang)
        w_im = math.sin(ang)
        for i in range(0, n, length):
            wr, wi = 1.0, 0.0
            for k in range(length // 2):
                u = i + k
                v = i + k + length // 2
                tr = wr * re[v] - wi * im[v]
                ti = wr * im[v] + wi * re[v]
                re[v] = re[u] - tr
                im[v] = im[u] - ti
                re[u] += tr
                im[u] += ti
                nwr = wr * w_re - wi * w_im
                wi = wr * w_im + wi * w_re
                wr = nwr
        length <<= 1


def spectrum_bars(pcm: bytes) -> list[float]:
    samples = struct.unpack(f"<{len(pcm) // 2}h", pcm)
    re, im = _FFT_RE, _FFT_IM
    for i in range(FFT_SIZE):
        re[i] = 0.0
        im[i] = 0.0
    n = min(len(samples), FFT_SIZE)
    for i in range(n):
        re[i] = samples[i] * _HANN[i]

    _fft(re, im)

    out: list[float] = []
    for b in range(BARS):
        lo, hi = _BAND_EDGES[b], _BAND_EDGES[b + 1]
        if hi <= lo:
            hi = lo + 1
        acc = 0.0
        count = 0
        for i in range(lo, hi):
            acc += math.hypot(re[i], im[i])
            count += 1
        out.append(acc / count if count else 0.0)
    return out


def resolve_mic_source() -> str:
    env = os.environ.get("PULSE_SOURCE")
    if env:
        return env
    exact = (
        "alsa_input.usb-Creative_Technology_Ltd_Sound_Blaster_Play__3_"
        "YDSB1730541001069B-00.analog-stereo"
    )
    try:
        out = subprocess.check_output(["pactl", "list", "short", "sources"], text=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return exact
    for line in out.splitlines():
        parts = line.split("\t", 2)
        if len(parts) >= 2 and parts[1] == exact:
            return exact
        if len(parts) >= 2 and "blaster" in parts[1].lower() and ".monitor" not in parts[1]:
            return parts[1]
    try:
        return subprocess.check_output(["pactl", "get-default-source"], text=True).strip()
    except subprocess.CalledProcessError:
        return exact


class Smoother:
    """Attack/release EMA — only tracks levels during confirmed speech."""

    __slots__ = ("bars", "speech", "peak")

    def __init__(self) -> None:
        self.bars = [IDLE_BAR] * BARS
        self.speech = 0.0
        self.peak = 1200.0

    def update(self, raw: list[float], speech: bool) -> list[float]:
        target_speech = 1.0 if speech else 0.0
        if target_speech > self.speech:
            self.speech += (target_speech - self.speech) * 0.55
        else:
            self.speech += (target_speech - self.speech) * 0.48

        norm = 1.0
        if speech and raw:
            frame_peak = max(raw)
            if frame_peak > 1:
                self.peak = self.peak * 0.76 + frame_peak * 0.24
            norm = 1.0 / max(200.0, self.peak)

        gate = self.speech * self.speech
        out: list[float] = []
        for i, band in enumerate(raw):
            if gate < 0.04:
                prev = self.bars[i]
                blended = max(IDLE_BAR, prev * 0.55)
                self.bars[i] = blended
                out.append(blended)
                continue

            v = min(1.0, (band * norm) ** 0.72)
            v *= gate
            prev = self.bars[i]
            if v > prev:
                blended = prev * 0.18 + v * 0.82
            else:
                blended = prev * 0.52 + v * 0.48
            blended = max(MIN_BAR, min(1.0, blended * 0.94 + 0.05))
            self.bars[i] = blended
            out.append(blended)

        return out


def emit(levels: list[float]) -> None:
    body = ",".join(f"{v:.3f}" for v in levels)
    print(f"[{body}]", flush=True)


def main() -> int:
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    os.environ.setdefault("XDG_RUNTIME_DIR", runtime)
    os.environ.setdefault("DBUS_SESSION_BUS_ADDRESS", f"unix:path={runtime}/bus")
    os.environ.setdefault("PULSE_SERVER", f"unix:{runtime}/pulse/native")

    lock_path = f"{runtime}/qs-dictation-waveform.lock"
    lock_fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        subprocess.run(
            ["pkill", "-o", "-f", "dictation-waveform.py"],
            stderr=subprocess.DEVNULL,
        )
        time.sleep(0.2)
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0

    source = resolve_mic_source()
    vad = webrtcvad.Vad(3)
    gate = SpeechGate()
    smoother = Smoother()

    proc = subprocess.Popen(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-fflags",
            "nobuffer",
            "-flags",
            "low_delay",
            "-probesize",
            "32",
            "-analyzeduration",
            "0",
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
            "-",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        bufsize=0,
    )
    if not proc.stdout:
        return 1

    buf = b""
    try:
        while True:
            chunk = proc.stdout.read(FRAME_BYTES)
            if not chunk:
                break
            buf += chunk
            while len(buf) >= FRAME_BYTES:
                pcm = buf[:FRAME_BYTES]
                buf = buf[FRAME_BYTES:]
                raw = spectrum_bars(pcm)
                vad_hit = vad.is_speech(pcm, SAMPLE_RATE)
                speech = gate.classify(pcm, raw, vad_hit)
                emit(smoother.update(raw, speech))
    except KeyboardInterrupt:
        pass
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            proc.kill()
    return 0


if __name__ == "__main__":
    sys.exit(main())
