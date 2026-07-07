#!/usr/bin/env python3
"""Video → Ly .dur — cream █ on black, motion from luminance (or tech green)."""

from __future__ import annotations

import argparse
import gzip
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

try:
    from PIL import Image, ImageEnhance, ImageFilter
except ImportError:
    Image = None  # type: ignore[misc, assignment]
    ImageEnhance = None  # type: ignore[misc, assignment]
    ImageFilter = None  # type: ignore[misc, assignment]

from dataclasses import dataclass

DURDRAW_REPO = Path("/tmp/durdraw")
if DURDRAW_REPO.is_dir():
    sys.path.insert(0, str(DURDRAW_REPO))

from durdraw.durdraw_file import serialize_to_json_file  # noqa: E402
from durdraw.durdraw_appstate import AppState  # noqa: E402
from durdraw.durdraw_movie import Frame, Movie  # noqa: E402
from durdraw.durdraw_options import Options  # noqa: E402

TECH_FG = [16, 22, 23, 28, 29, 30, 34, 35, 36, 40, 41, 42, 46, 47, 50, 51, 86]
CELL_CHAR = "\u2580"
SOLID_CHAR = "\u2588"
BG_COLOR = 0

DEFAULT_SOURCE = (
    "https://www.shutterstock.com/shutterstock/videos/3446957693/preview/"
    "stock-footage-ascii-technological-background-fractal-motion.webm"
)
BUNDLED_ASSET = (
    Path(__file__).resolve().parents[1] / "assets/fractal-ascii-preview.webm"
)


def find_next_alpha(text: str, i: int) -> int | None:
    for j in range(i, len(text)):
        if text[j].isalpha():
            return j
    return None


def rgb_to_256(r: int, g: int, b: int) -> int:
    if r == g == b:
        if r < 8:
            return 16
        if r > 248:
            return 231
        return 232 + round((r - 8) / 10)
    return (
        16
        + 36 * round(r / 255 * 5)
        + 6 * round(g / 255 * 5)
        + round(b / 255 * 5)
    )


def remap_tech_fg(fg: int) -> int:
    if fg <= 16:
        return 16
    idx = min(len(TECH_FG) - 1, (fg * len(TECH_FG)) // 256)
    return TECH_FG[idx]


def warm_cream_rgb(r: int, g: int, b: int) -> tuple[int, int, int]:
    return (
        min(255, int(r * 0.92 + 24)),
        min(255, int(g * 0.88 + 20)),
        min(255, int(b * 0.72 + 6)),
    )


def luminance(r: int, g: int, b: int) -> int:
    return int(0.299 * r + 0.587 * g + 0.114 * b)


def rgb_to_cream_fg(r: int, g: int, b: int, threshold: int) -> int | None:
    """Cream xterm grays 247–255; None = leave cell black (space)."""
    r, g, b = warm_cream_rgb(r, g, b)
    lum = luminance(r, g, b)
    if lum < threshold:
        return None
    t = (lum - threshold) / max(1, 255 - threshold)
    return int(247 + t * 8)


def fg_from_rgb(
    r: int, g: int, b: int, palette: str, threshold: int
) -> int | None:
    if palette == "tech":
        return remap_tech_fg(rgb_to_256(r, g, b))
    return rgb_to_cream_fg(r, g, b, threshold)


def preprocess_frame(
    img: Image.Image, style: str, blur: float = 0.0, palette: str = "cream"
) -> Image.Image:
    img = img.convert("RGB")
    if style in ("ascii", "solid", "halfblock"):
        if palette == "cream" and style == "solid":
            img = ImageEnhance.Brightness(img).enhance(0.34)
            img = ImageEnhance.Contrast(img).enhance(1.65)
            img = ImageEnhance.Color(img).enhance(0.12)
        else:
            img = ImageEnhance.Brightness(img).enhance(0.42 if style == "solid" else 0.32)
            img = ImageEnhance.Contrast(img).enhance(1.35 if style == "solid" else 1.55)
            if palette == "tech":
                r, g, b = img.split()
                g = g.point(lambda p: min(255, int(p * 1.14)))
                b = b.point(lambda p: max(0, int(p * 0.72)))
                img = Image.merge("RGB", (r, g, b))
    if blur > 0 and ImageFilter is not None:
        img = img.filter(ImageFilter.GaussianBlur(radius=blur))
    return img


RgbGrid = list[list[tuple[int, int, int]]]


def load_rgb_grid(
    png: Path,
    width: int,
    height: int,
    style: str,
    blur: float,
    palette: str,
) -> RgbGrid:
    img = preprocess_frame(Image.open(png), style, blur=blur, palette=palette)
    img = img.resize((width, height), Image.Resampling.LANCZOS)
    pixels = img.load()
    grid: RgbGrid = []
    for y in range(height):
        row: list[tuple[int, int, int]] = []
        for x in range(width):
            row.append(pixels[x, y])
        grid.append(row)
    return grid


def blend_grids(prev: RgbGrid | None, cur: RgbGrid, alpha: float) -> RgbGrid:
    """EMA blend — lower alpha = smoother, less flicker between frames."""
    if prev is None or alpha >= 1.0:
        return cur
    if alpha <= 0.0:
        return prev
    out: RgbGrid = []
    for y in range(len(cur)):
        row: list[tuple[int, int, int]] = []
        for x in range(len(cur[y])):
            pr, pg, pb = prev[y][x]
            cr, cg, cb = cur[y][x]
            row.append(
                (
                    int(pr * (1 - alpha) + cr * alpha),
                    int(pg * (1 - alpha) + cg * alpha),
                    int(pb * (1 - alpha) + cb * alpha),
                )
            )
        out.append(row)
    return out


def frame_from_rgb_grid(
    grid: RgbGrid,
    width: int,
    height: int,
    palette: str,
    luma_threshold: int,
    fill_char: str = SOLID_CHAR,
) -> Frame:
    frame = Frame(width, height)
    for y in range(height):
        for x in range(width):
            r, g, b = grid[y][x]
            fg = fg_from_rgb(r, g, b, palette, luma_threshold)
            if palette == "cream" and fg is None:
                frame.content[y][x] = " "
                frame.newColorMap[y][x] = [BG_COLOR, BG_COLOR]
            else:
                frame.content[y][x] = fill_char
                frame.newColorMap[y][x] = [fg if fg is not None else BG_COLOR, BG_COLOR]
    return frame


@dataclass
class SmoothOpts:
    blur: float = 0.6
    luma_threshold: int = 85
    temporal: float = 0.65
    palette: str = "cream"


def parse_ansi_line(
    line: str, width: int, app: AppState, palette: str
) -> tuple[list[str], list[list[int]]]:
    row_chars = [" "] * width
    row_colors = [[16, 0] for _ in range(width)]
    fg = app.defaultFgColor
    bg = 0
    bold = False
    col = 0
    i = 0
    while i < len(line) and col < width:
        if line[i : i + 2] == "\x1b[":
            end = find_next_alpha(line, i + 1)
            if end is None:
                i += 1
                continue
            if line[end] != "m":
                i = end + 1
                continue
            codes = line[i + 2 : end].split(";")
            nums = [int(c) for c in codes if c.isdigit()]
            j = 0
            while j < len(nums):
                code = nums[j]
                if code == 0:
                    fg, bg, bold = app.defaultFgColor, 0, False
                elif code == 1:
                    bold = True
                elif code == 38 and j + 2 < len(nums) and nums[j + 1] == 5:
                    fg = nums[j + 2]
                    j += 2
                elif code == 48 and j + 2 < len(nums) and nums[j + 1] == 5:
                    bg = nums[j + 2]
                    j += 2
                elif 30 <= code <= 37:
                    from durdraw import durdraw_color_curses as cmod

                    fg = cmod.ansi_code_to_dur_16_color.get(str(code), fg)
                    if bold and fg < 9:
                        fg += 8
                elif 40 <= code <= 47:
                    from durdraw import durdraw_color_curses as cmod

                    bg = max(0, cmod.ansi_code_to_dur_16_color.get(str(code), 1) - 1)
                j += 1
            i = end + 1
            continue
        ch = line[i]
        if ch == "\n":
            break
        row_chars[col] = ch
        if palette == "tech":
            pair = [remap_tech_fg(fg), 0 if bg == 0 else remap_tech_fg(bg)]
        else:
            g = min(255, max(0, int(fg * 12)))
            cf = rgb_to_cream_fg(g, g, g, 32)
            pair = [cf if cf is not None else BG_COLOR, BG_COLOR]
        row_colors[col] = pair
        col += 1
        i += 1
    return row_chars, row_colors


def frame_ascii(
    png: Path, width: int, height: int, app: AppState, palette: str
) -> Frame:
    if not shutil.which("img2txt"):
        raise SystemExit("img2txt required: sudo pacman -S libcaca")
    img = preprocess_frame(Image.open(png), "ascii", palette=palette)
    tmp = png.with_suffix(".prep.png")
    img.resize((width, height), Image.Resampling.LANCZOS).save(tmp)
    raw = subprocess.check_output(
        ["img2txt", "-W", str(width), "-H", str(height), "-f", "ansi", str(tmp)],
        text=True,
        stderr=subprocess.DEVNULL,
    )
    raw = re.sub(
        r"\x1b\[[0-9;]*[A-Za-z]",
        lambda m: m.group(0) if m.group(0).endswith("m") else "",
        raw,
    )
    lines = raw.split("\n")[:height]
    while len(lines) < height:
        lines.append("")
    frame = Frame(width, height)
    for y, line in enumerate(lines):
        chars, colors = parse_ansi_line(line, width, app, palette)
        frame.content[y] = chars
        for x in range(width):
            if chars[x] == " ":
                frame.newColorMap[y][x] = [BG_COLOR, BG_COLOR]
            else:
                frame.newColorMap[y][x] = colors[x]
    return frame


def load_rgb_grid_halfblock(
    png: Path, width: int, height: int, smooth: SmoothOpts
) -> RgbGrid:
    img = preprocess_frame(
        Image.open(png), "halfblock", blur=smooth.blur, palette=smooth.palette
    )
    img = img.resize((width, height * 2), Image.Resampling.LANCZOS)
    pixels = img.load()
    grid: RgbGrid = []
    for y in range(height):
        row: list[tuple[int, int, int]] = []
        for x in range(width):
            r1, g1, b1 = pixels[x, y * 2]
            r2, g2, b2 = pixels[x, y * 2 + 1]
            row.append(
                (
                    (r1 + r2) // 2,
                    (g1 + g2) // 2,
                    (b1 + b2) // 2,
                )
            )
        grid.append(row)
    return grid


def build_dur(
    frames_dir: Path,
    out_path: Path,
    width: int,
    height: int,
    playback_fps: float,
    style: str,
    name: str,
    artist: str,
    smooth: SmoothOpts,
) -> None:
    app = AppState()
    app.colorMode = "256"
    app.charEncoding = "utf-8"
    opts = Options(width, height)
    opts.framerate = playback_fps
    opts.saveFileFormat = 7

    movie = Movie(opts)
    movie.frames.clear()
    movie.frameCount = 0

    paths = sorted(frames_dir.glob("frame_*.png"))
    if not paths:
        raise SystemExit(f"No frames in {frames_dir}")

    prev_grid: RgbGrid | None = None

    for i, png in enumerate(paths, 1):
        if style == "ascii":
            frame = frame_ascii(png, width, height, app, smooth.palette)
        else:
            if style == "solid":
                cur = load_rgb_grid(png, width, height, "solid", smooth.blur, smooth.palette)
            else:
                cur = load_rgb_grid_halfblock(png, width, height, smooth)
            prev_grid = blend_grids(prev_grid, cur, smooth.temporal)
            fill = SOLID_CHAR if style == "solid" else CELL_CHAR
            frame = frame_from_rgb_grid(
                prev_grid, width, height, smooth.palette, smooth.luma_threshold, fill
            )
        frame.setDelayValue(0)
        movie.addFrame(frame)
        if i % 25 == 0 or i == len(paths):
            print(f"  frame {i}/{len(paths)}", flush=True)

    serialize_to_json_file(opts, app, movie, str(out_path), gzipped=True)
    patch_dur_metadata(out_path, name, artist, width, height, playback_fps)
    print(f"  {len(paths)} frames, ~{len(paths) / playback_fps:.1f}s per loop @ {playback_fps} fps")


def patch_dur_metadata(
    path: Path, name: str, artist: str, columns: int, lines: int, fps: float
) -> None:
    with gzip.open(path, "rt", encoding="utf-8") as f:
        data = json.load(f)
    m = data["DurMovie"]
    m["name"] = name
    m["artist"] = artist
    m["columns"] = columns
    m["lines"] = lines
    m.pop("sizeX", None)
    m.pop("sizeY", None)
    m["framerate"] = fps
    with gzip.open(path, "wt", encoding="utf-8") as f:
        json.dump(data, f, indent=2)


def resolve_video(source: str, workdir: Path) -> Path:
    workdir.mkdir(parents=True, exist_ok=True)
    if source.startswith(("http://", "https://")):
        if BUNDLED_ASSET.is_file() and DEFAULT_SOURCE in source:
            dest = workdir / "source.webm"
            if not dest.exists() or dest.stat().st_size != BUNDLED_ASSET.stat().st_size:
                shutil.copy2(BUNDLED_ASSET, dest)
            return dest
        dest = workdir / "source.%(ext)s"
        run(
            [
                "yt-dlp",
                "-f",
                "bv*+ba/b",
                "--merge-output-format",
                "mp4",
                "-o",
                str(dest),
                source,
            ]
        )
        files = list(workdir.glob("source.*"))
        return files[0] if files else workdir / "source.mp4"
    path = Path(source).expanduser()
    if not path.is_file():
        raise SystemExit(f"Not found: {path}")
    return path


def run(cmd: list[str], **kw) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True, **kw)


def main() -> None:
    p = argparse.ArgumentParser(description= __doc__)
    p.add_argument(
        "source",
        nargs="?",
        default=str(BUNDLED_ASSET if BUNDLED_ASSET.is_file() else DEFAULT_SOURCE),
        help="Video file or URL (default: fractal ASCII preview)",
    )
    p.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path(__file__).resolve().parents[1]
        / "etc/ly/backgrounds/fractal-ascii.dur",
    )
    p.add_argument("--width", type=int, default=430)
    p.add_argument("--height", type=int, default=102)
    p.add_argument(
        "--style",
        choices=("ascii", "halfblock", "solid"),
        default="solid",
        help="solid = full block █; halfblock = ▀; ascii = img2txt glyphs",
    )
    p.add_argument(
        "--capture-fps",
        type=float,
        default=30.0,
        help="ffmpeg extract rate (more frames = smoother)",
    )
    p.add_argument(
        "--loop-sec",
        type=float,
        default=30.0,
        help="Target loop length on Ly; playback fps = frames / loop-sec",
    )
    p.add_argument(
        "--playback-fps",
        type=float,
        default=None,
        help="Override loop speed (default: auto from --loop-sec)",
    )
    p.add_argument("--duration", type=float, default=10.0, help="Seconds of source video")
    p.add_argument("--blur", type=float, default=1.2, help="Spatial blur radius (solid/halfblock)")
    p.add_argument(
        "--temporal",
        type=float,
        default=0.65,
        help="New-frame blend 0–1; higher = more visible motion (default 0.65)",
    )
    p.add_argument(
        "--luma-threshold",
        type=int,
        default=85,
        help="Below = black (space); above = cream █ (default ~55%% fill)",
    )
    p.add_argument(
        "--palette",
        choices=("cream", "tech"),
        default="cream",
        help="cream = █ on bright areas only, black elsewhere; tech = green",
    )
    p.add_argument("--workdir", type=Path, default=Path(__file__).resolve().parents[1] / "work")
    p.add_argument("--skip-download", action="store_true")
    args = p.parse_args()

    if Image is None:
        sys.exit("Pillow required: sudo pacman -S python-pillow")
    if args.style == "ascii" and not shutil.which("img2txt"):
        sys.exit("img2txt required for ascii style: sudo pacman -S libcaca")
    for bin_name in ("yt-dlp", "ffmpeg"):
        if not shutil.which(bin_name):
            sys.exit(f"{bin_name} not found")

    if not DURDRAW_REPO.is_dir():
        run(["git", "clone", "--depth", "1", "https://github.com/cmang/durdraw.git", str(DURDRAW_REPO)])

    video = args.workdir / "source.webm"
    if args.skip_download:
        if not video.is_file():
            for ext in ("webm", "mp4", "mkv"):
                cand = args.workdir / f"source.{ext}"
                if cand.is_file():
                    video = cand
                    break
        if not video.is_file():
            raise SystemExit(f"No source video in {args.workdir}")
    else:
        video = resolve_video(args.source, args.workdir)

    frames = args.workdir / "frames"
    if frames.exists():
        shutil.rmtree(frames)
    frames.mkdir()
    vf = f"fps={args.capture_fps}"
    if args.style in ("solid", "halfblock"):
        vf += ",gblur=sigma=0.8"
    run(
        [
            "ffmpeg",
            "-y",
            "-i",
            str(video),
            "-t",
            str(args.duration),
            "-vf",
            vf,
            str(frames / "frame_%05d.png"),
        ]
    )

    n = len(list(frames.glob("frame_*.png")))
    if args.playback_fps is not None:
        playback_fps = args.playback_fps
    else:
        playback_fps = n / args.loop_sec
    loop_sec = n / playback_fps
    args.output.parent.mkdir(parents=True, exist_ok=True)
    print(
        f"Building {args.output} ({args.width}x{args.height}, style={args.style}, "
        f"capture={args.capture_fps} → {n} frames, playback={playback_fps:.2f} fps, "
        f"~{loop_sec:.1f}s loop)..."
    )
    smooth = SmoothOpts(
        blur=args.blur,
        luma_threshold=args.luma_threshold,
        temporal=args.temporal,
        palette=args.palette,
    )
    build_dur(
        frames,
        args.output,
        args.width,
        args.height,
        playback_fps,
        args.style,
        name="ASCII fractal",
        artist="shutterstock-preview",
        smooth=smooth,
    )
    print(f"Wrote {args.output} ({args.output.stat().st_size / 1024 / 1024:.1f} MiB)")
    print("Install: sudo bash ly/install-ly-background.sh fractal-ascii.dur")


if __name__ == "__main__":
    main()
