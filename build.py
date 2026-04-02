#!/usr/bin/env python3
"""
Build script for Devin Smells Of Dog Farts and Soup.

Scans pics/ for images, generates fart sounds, base64-encodes everything,
and injects it all into src/template.html to produce a single index.html.

Usage:
    python build.py
"""

import base64
import io
import json
import math
import mimetypes
import os
import random
import struct
import wave
from pathlib import Path

# --- Configuration ---
PROJECT_ROOT = Path(__file__).parent
PICS_DIR = PROJECT_ROOT / "pics"
TEMPLATE_PATH = PROJECT_ROOT / "src" / "template.html"
OUTPUT_PATH = PROJECT_ROOT / "index.html"
SUPPORTED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".webp"}
MAX_SIZE_WARNING_MB = 10

# Photo captions to rotate through
CAPTIONS = [
    "Exhibit A",
    "The Proof",
    "Caught in 4K",
    "Smells Confirmed",
    "Evidence #{}",
    "Viewer Discretion Advised",
    "Undeniable",
    "The Stench Source",
    "Ground Zero",
    "Smell-o-Vision",
    "Case Closed",
    "*gag*",
    "The Nose Knows",
    "Fragrance Model",
    "Eau de Devin",
]

# Fart sound definitions
FART_SOUNDS = [
    {
        "name": "The Silent But Deadly",
        "emoji": "🤫",
        "freq_start": 80,
        "freq_end": 40,
        "duration": 0.6,
        "noise_mix": 0.7,
    },
    {
        "name": "The Wet One",
        "emoji": "💦",
        "freq_start": 120,
        "freq_end": 60,
        "duration": 0.8,
        "noise_mix": 0.9,
    },
    {
        "name": "The Squeaker",
        "emoji": "🐭",
        "freq_start": 300,
        "freq_end": 500,
        "duration": 0.3,
        "noise_mix": 0.3,
    },
    {
        "name": "The Foghorn",
        "emoji": "📯",
        "freq_start": 60,
        "freq_end": 45,
        "duration": 1.5,
        "noise_mix": 0.4,
    },
    {
        "name": "Soup Bubble",
        "emoji": "🍲",
        "freq_start": 200,
        "freq_end": 100,
        "duration": 0.4,
        "noise_mix": 0.6,
    },
]


def find_images(pics_dir: Path) -> list[Path]:
    """Find all supported image files in the pics directory."""
    if not pics_dir.exists():
        return []
    images = []
    for f in sorted(pics_dir.iterdir()):
        if f.is_file() and f.suffix.lower() in SUPPORTED_EXTENSIONS:
            images.append(f)
    return images


def encode_file_b64(filepath: Path) -> str:
    """Read a file and return its base64-encoded string."""
    with open(filepath, "rb") as f:
        return base64.b64encode(f.read()).decode("ascii")


def get_mime_type(filepath: Path) -> str:
    """Get MIME type for a file, with sensible defaults."""
    mime, _ = mimetypes.guess_type(str(filepath))
    if mime:
        return mime
    ext = filepath.suffix.lower()
    mime_map = {
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".gif": "image/gif",
        ".webp": "image/webp",
    }
    return mime_map.get(ext, "application/octet-stream")


def build_image_manifest(images: list[Path]) -> str:
    """Build a JSON payload so the template can render multiple layouts client-side."""
    manifest = []
    roast_lines = [
        "Documented odor event",
        "Flagged by the family nostrils",
        "Soup-adjacent behavior observed",
        "Public nuisance energy",
        "Witnesses advised to crack a window",
        "Confirmed by independent sniffers",
    ]

    for i, img_path in enumerate(images):
        mime = get_mime_type(img_path)
        b64 = encode_file_b64(img_path)
        data_uri = f"data:{mime};base64,{b64}"

        caption = CAPTIONS[i % len(CAPTIONS)]
        if "{}" in caption:
            caption = caption.format(i + 1)

        manifest.append(
            {
                "src": data_uri,
                "alt": f"Devin photo {i + 1}",
                "caption": caption,
                "case_number": f"CASE-{i + 1:02d}",
                "headline": roast_lines[i % len(roast_lines)],
                "odor_rating": 72 + ((i * 9) % 28),
            }
        )

    return json.dumps(manifest, separators=(",", ":"))


def generate_fart_wav(
    freq_start: float,
    freq_end: float,
    duration: float,
    noise_mix: float,
    sample_rate: int = 22050,
) -> bytes:
    """
    Generate a synthetic fart sound as WAV bytes.

    Uses a combination of frequency-swept sine wave and noise,
    with amplitude envelope for a more natural (?) fart sound.
    """
    num_samples = int(sample_rate * duration)
    samples = []

    # Use a fixed seed offset per call for reproducibility within a build
    rng = random.Random(int(freq_start * 1000 + freq_end * 100 + duration * 10))

    for i in range(num_samples):
        t = i / sample_rate
        progress = i / num_samples

        # Frequency sweep (linear interpolation)
        freq = freq_start + (freq_end - freq_start) * progress

        # Sine wave component
        sine_val = math.sin(2 * math.pi * freq * t)

        # Add harmonics for richness
        sine_val += 0.5 * math.sin(2 * math.pi * freq * 2 * t)
        sine_val += 0.25 * math.sin(2 * math.pi * freq * 3 * t)

        # Noise component
        noise_val = rng.uniform(-1, 1)

        # Mix sine and noise
        mixed = sine_val * (1 - noise_mix) + noise_val * noise_mix

        # Amplitude envelope: quick attack, sustain, gradual decay
        if progress < 0.05:
            envelope = progress / 0.05
        elif progress < 0.7:
            envelope = 1.0
        else:
            envelope = 1.0 - ((progress - 0.7) / 0.3)

        # Add some tremolo for "vibration" effect
        tremolo = 1.0 + 0.3 * math.sin(2 * math.pi * 15 * t)

        sample = mixed * envelope * tremolo

        # Clamp to [-1, 1]
        sample = max(-1.0, min(1.0, sample))

        # Convert to 16-bit PCM
        samples.append(int(sample * 32000))

    # Write WAV to buffer
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(struct.pack(f"<{len(samples)}h", *samples))

    return buf.getvalue()


def generate_soundboard_html() -> str:
    """Generate soundboard buttons with embedded audio data URIs."""
    html_parts = []

    for sound in FART_SOUNDS:
        wav_bytes = generate_fart_wav(
            freq_start=sound["freq_start"],
            freq_end=sound["freq_end"],
            duration=sound["duration"],
            noise_mix=sound["noise_mix"],
        )
        b64 = base64.b64encode(wav_bytes).decode("ascii")
        data_uri = f"data:audio/wav;base64,{b64}"

        html_parts.append(
            f'    <button class="fart-btn" type="button" data-sound="{data_uri}">'
            f'<span class="btn-emoji">{sound["emoji"]}</span>'
            f'{sound["name"]}'
            f"</button>"
        )

    return "\n".join(html_parts)


def build():
    """Main build function."""
    print("=" * 50)
    print("🐕💨 DEVIN SMELLS BUILD SYSTEM 🍲")
    print("=" * 50)

    # Check template exists
    if not TEMPLATE_PATH.exists():
        print(f"ERROR: Template not found at {TEMPLATE_PATH}")
        return False

    # Find images
    images = find_images(PICS_DIR)
    print(f"\n📸 Found {len(images)} image(s) in {PICS_DIR}/")
    for img in images:
        size_kb = img.stat().st_size / 1024
        print(f"   - {img.name} ({size_kb:.0f} KB)")

    # Generate image manifest
    print("\n🖼️  Encoding images to base64...")
    image_manifest = build_image_manifest(images)

    # Generate fart sounds
    print(f"\n💨 Generating {len(FART_SOUNDS)} fart sounds...")
    for sound in FART_SOUNDS:
        print(f"   - {sound['name']} ({sound['duration']}s)")
    soundboard_html = generate_soundboard_html()

    # Read template
    print(f"\n📄 Reading template: {TEMPLATE_PATH}")
    template = TEMPLATE_PATH.read_text(encoding="utf-8")

    # Inject content
    output = template.replace("{{IMAGE_DATA}}", image_manifest)
    output = output.replace("{{FART_SOUNDS}}", soundboard_html)
    output = output.replace("{{IMAGE_COUNT}}", str(len(images)))

    # Write output
    OUTPUT_PATH.write_text(output, encoding="utf-8")

    # Report
    output_size_bytes = OUTPUT_PATH.stat().st_size
    output_size_mb = output_size_bytes / (1024 * 1024)
    print(f"\n✅ Built: {OUTPUT_PATH}")
    print(f"   Size: {output_size_mb:.2f} MB ({output_size_bytes:,} bytes)")

    if output_size_mb > MAX_SIZE_WARNING_MB:
        print(
            f"\n⚠️  WARNING: Output is {output_size_mb:.1f} MB (>{MAX_SIZE_WARNING_MB} MB)."
        )
        print(
            "   Consider resizing images to ~800px wide before building for faster loads."
        )

    print(f"\n🐕 Devin's shame is ready. Open index.html in a browser to verify.")
    print("=" * 50)
    return True


if __name__ == "__main__":
    success = build()
    raise SystemExit(0 if success else 1)
