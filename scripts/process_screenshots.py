#!/usr/bin/env python3
"""Process WoW screenshots for QuickRoute addon listings.

Reads raw screenshots, crops/resizes to consistent dimensions,
optimizes file size, and saves to screenshots/ directory.
"""

import argparse
import os
import sys

try:
    from PIL import Image
except ImportError:
    print("Error: Pillow is required. Install with: pip install Pillow")
    sys.exit(1)

MAX_WIDTH = 1920
MAX_HEIGHT = 1080
OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "screenshots")

VALID_NAMES = [
    "route-panel",
    "teleport-panel",
    "destination-search",
    "minimap-button",
    "world-map-button",
    "quest-teleport",
]


def find_latest_screenshot(input_dir: str) -> str | None:
    """Find the most recently modified screenshot in input_dir."""
    candidates = []
    for f in os.listdir(input_dir):
        if f.lower().endswith((".png", ".jpg", ".jpeg", ".tga")):
            full = os.path.join(input_dir, f)
            candidates.append((os.path.getmtime(full), full))
    if not candidates:
        return None
    candidates.sort(reverse=True)
    return candidates[0][1]


def process_image(
    src_path: str,
    name: str,
    crop_region: tuple[int, int, int, int] | None = None,
) -> str:
    """Process a single screenshot: crop, resize, optimize, save as PNG."""
    img = Image.open(src_path)

    # Crop if region specified (left, top, right, bottom)
    if crop_region:
        img = img.crop(crop_region)

    # Resize to fit within max dimensions, preserving aspect ratio
    if img.width > MAX_WIDTH or img.height > MAX_HEIGHT:
        img.thumbnail((MAX_WIDTH, MAX_HEIGHT), Image.LANCZOS)

    # Ensure output directory exists
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Save as optimized PNG
    out_path = os.path.join(OUTPUT_DIR, f"{name}.png")
    img.save(out_path, "PNG", optimize=True)

    size_kb = os.path.getsize(out_path) / 1024
    print(f"Saved: {out_path} ({img.width}x{img.height}, {size_kb:.0f} KB)")
    return out_path


def main():
    parser = argparse.ArgumentParser(description="Process WoW screenshots for QuickRoute")
    parser.add_argument(
        "--input", "-i",
        help="Input directory (default: WoW Screenshots folder)",
        default=None,
    )
    parser.add_argument(
        "--file", "-f",
        help="Specific input file to process",
        default=None,
    )
    parser.add_argument(
        "--name", "-n",
        help=f"Output name (one of: {', '.join(VALID_NAMES)})",
    )
    parser.add_argument(
        "--crop",
        help="Crop region as left,top,right,bottom (pixels)",
        default=None,
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List expected screenshot names and exit",
    )

    args = parser.parse_args()

    if args.list:
        print("Expected screenshot names:")
        for n in VALID_NAMES:
            path = os.path.join(OUTPUT_DIR, f"{n}.png")
            exists = "EXISTS" if os.path.exists(path) else "missing"
            print(f"  {n}.png  [{exists}]")
        return

    if not args.name or args.name not in VALID_NAMES:
        print(f"Error: --name must be one of: {', '.join(VALID_NAMES)}")
        sys.exit(1)

    # Determine source file
    if args.file:
        src = args.file
    elif args.input:
        src = find_latest_screenshot(args.input)
        if not src:
            print(f"Error: No screenshots found in {args.input}")
            sys.exit(1)
        print(f"Using latest screenshot: {src}")
    else:
        # Try common WoW screenshot locations
        wow_paths = [
            os.path.expanduser("~/Games/World of Warcraft/_retail_/Screenshots"),
            os.path.expanduser("~/World of Warcraft/_retail_/Screenshots"),
            "C:\\Program Files (x86)\\World of Warcraft\\_retail_\\Screenshots",
        ]
        src = None
        for p in wow_paths:
            if os.path.isdir(p):
                src = find_latest_screenshot(p)
                if src:
                    print(f"Found WoW screenshots in: {p}")
                    print(f"Using latest: {src}")
                    break
        if not src:
            print("Error: No WoW Screenshots folder found. Use --input or --file.")
            sys.exit(1)

    if not os.path.isfile(src):
        print(f"Error: File not found: {src}")
        sys.exit(1)

    # Parse crop region
    crop = None
    if args.crop:
        try:
            parts = [int(x.strip()) for x in args.crop.split(",")]
            if len(parts) != 4:
                raise ValueError
            crop = tuple(parts)
        except ValueError:
            print("Error: --crop must be 4 integers: left,top,right,bottom")
            sys.exit(1)

    process_image(src, args.name, crop)


if __name__ == "__main__":
    main()
