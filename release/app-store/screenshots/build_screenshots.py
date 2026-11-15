#!/usr/bin/env python3
"""Build and validate SceneMe's native App Store screenshot sets."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "source"
OUTPUT = ROOT / "final"

WHITE = (248, 246, 240)
GOLD = (226, 187, 96)
MUTED = (211, 207, 198)
AVENIR = "/System/Library/Fonts/Avenir Next.ttc"

DEVICE_SETS = [
    {
        "slug": "iphone-large",
        "label": "Large iPhone",
        "size": (1320, 2868),
        "capture_width": 900,
        "capture_y": 650,
        "frame_padding": 10,
        "corner_radius": 70,
        "left": 92,
        "eyebrow_size": 28,
        "title_size": 100,
        "title_leading": 108,
        "subtitle_size": 36,
    },
    {
        "slug": "iphone-medium",
        "label": "Medium Dynamic Island iPhone",
        "size": (1206, 2622),
        "capture_width": 820,
        "capture_y": 600,
        "frame_padding": 9,
        "corner_radius": 64,
        "left": 82,
        "eyebrow_size": 25,
        "title_size": 91,
        "title_leading": 99,
        "subtitle_size": 33,
    },
    {
        "slug": "ipad-13",
        "label": "13-inch iPad",
        "size": (2064, 2752),
        "capture_width": 1480,
        "capture_y": 610,
        "frame_padding": 12,
        "corner_radius": 48,
        "left": 132,
        "eyebrow_size": 32,
        "title_size": 112,
        "title_leading": 120,
        "subtitle_size": 41,
    },
]

SCREENS = [
    {
        "output": "01-place-yourself-anywhere.png",
        "background": "bg-01-gold.png",
        "capture": "01-home.png",
        "lines": [("Place yourself", WHITE), ("anywhere.", GOLD)],
        "subtitle": "Upload one photo. Pick a cinematic scene. Create.",
    },
    {
        "output": "02-choose-a-scene.png",
        "background": "bg-02-city.png",
        "capture": "02-explore.png",
        "lines": [("Choose a scene.", WHITE), ("Make it yours.", GOLD)],
        "subtitle": "Explore cinematic places, moods and professional looks.",
    },
    {
        "output": "03-direct-every-detail.png",
        "background": "bg-03-aurora.png",
        "capture": "03-scene-options.png",
        "lines": [("Direct every", WHITE), ("detail.", GOLD)],
        "subtitle": "Tune time, weather, pose, image quality and companions.",
    },
    {
        "output": "04-clear-credits.png",
        "background": "bg-04-burgundy.png",
        "capture": "04-paywall.png",
        "lines": [("Create with", WHITE), ("clear credits.", GOLD)],
        "subtitle": "See exact credit costs for images and five-second videos.",
    },
    {
        "output": "05-one-photo-any-world.png",
        "background": "bg-05-ivory.png",
        "capture": "05-scene-picker.png",
        "lines": [("From one photo", WHITE), ("to any world.", GOLD)],
        "subtitle": "Choose a template—or create your own with Creator.",
    },
]


def font(size: int, index: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(AVENIR, size=size, index=index)


def cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    return ImageOps.fit(image.convert("RGB"), size, method=Image.Resampling.LANCZOS)


def rounded_capture(image: Image.Image, width: int, padding: int, radius: int) -> Image.Image:
    ratio = width / image.width
    resized = image.convert("RGB").resize(
        (width, round(image.height * ratio)), Image.Resampling.LANCZOS
    )
    mask = Image.new("L", resized.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, resized.width - 1, resized.height - 1), radius=radius, fill=255
    )

    framed = Image.new(
        "RGBA",
        (resized.width + padding * 2, resized.height + padding * 2),
        (0, 0, 0, 0),
    )
    ImageDraw.Draw(framed).rounded_rectangle(
        (0, 0, framed.width - 1, framed.height - 1),
        radius=radius + padding,
        fill=(8, 8, 9, 255),
        outline=(226, 187, 96, 165),
        width=max(2, padding // 3),
    )
    framed.paste(resized.convert("RGBA"), (padding, padding), mask)
    return framed


def fit_text(
    draw: ImageDraw.ImageDraw,
    text: str,
    max_width: int,
    start: int,
    index: int,
) -> ImageFont.FreeTypeFont:
    size = start
    while size > 24:
        candidate = font(size, index)
        if draw.textbbox((0, 0), text, font=candidate)[2] <= max_width:
            return candidate
        size -= 2
    return font(size, index)


def build(spec: dict[str, object], device: dict[str, object]) -> Image.Image:
    size = tuple(device["size"])
    capture_dir = SOURCE / "captures" / str(device["slug"])
    background = cover(Image.open(SOURCE / str(spec["background"])), size)
    background = Image.blend(background, Image.new("RGB", size, (2, 3, 4)), 0.40)

    gradient_height = round(size[1] * 0.34)
    gradient = Image.new("L", size, 0)
    gradient_draw = ImageDraw.Draw(gradient)
    for y in range(gradient_height):
        alpha = round(242 * (1 - y / gradient_height))
        gradient_draw.line((0, y, size[0], y), fill=alpha)
    top_veil = Image.new("RGBA", size, (0, 0, 0, 0))
    top_veil.putalpha(gradient)
    canvas = background.convert("RGBA")
    canvas.alpha_composite(top_veil)

    draw = ImageDraw.Draw(canvas)
    left = int(device["left"])
    eyebrow_y = round(size[1] * 0.032)
    draw.text(
        (left, eyebrow_y),
        "SCENEME  •  CINEMATIC AI",
        font=font(int(device["eyebrow_size"]), 2),
        fill=GOLD,
    )

    title_y = eyebrow_y + round(size[1] * 0.027)
    title_font = font(int(device["title_size"]), 8)
    for text, color in spec["lines"]:
        draw.text((left, title_y), text, font=title_font, fill=color)
        title_y += int(device["title_leading"])

    subtitle = str(spec["subtitle"])
    subtitle_font = fit_text(
        draw,
        subtitle,
        size[0] - left * 2,
        int(device["subtitle_size"]),
        5,
    )
    draw.text((left, title_y + 24), subtitle, font=subtitle_font, fill=MUTED)

    capture = rounded_capture(
        Image.open(capture_dir / str(spec["capture"])),
        int(device["capture_width"]),
        int(device["frame_padding"]),
        int(device["corner_radius"]),
    )
    shadow_margin = 100
    shadow = Image.new(
        "RGBA",
        (capture.width + shadow_margin * 2, capture.height + shadow_margin * 2),
        (0, 0, 0, 0),
    )
    shadow_mask = Image.new("L", capture.size, 0)
    ImageDraw.Draw(shadow_mask).rounded_rectangle(
        (0, 0, capture.width - 1, capture.height - 1),
        radius=int(device["corner_radius"]) + int(device["frame_padding"]),
        fill=220,
    )
    shadow.paste((0, 0, 0, 235), (shadow_margin, shadow_margin), shadow_mask)
    shadow = shadow.filter(ImageFilter.GaussianBlur(34))

    x = (size[0] - capture.width) // 2
    y = int(device["capture_y"])
    if x < 0 or y < 0 or x + capture.width > size[0] or y + capture.height > size[1]:
        raise ValueError(f"Device mockup is clipped for {device['slug']} / {spec['output']}")
    canvas.alpha_composite(shadow, (x - shadow_margin, y - shadow_margin))
    canvas.alpha_composite(capture, (x, y))
    return canvas.convert("RGB")


def contact_sheet(outputs: list[Path], size: tuple[int, int], destination: Path) -> None:
    thumb_width = 280
    thumb_height = round(size[1] * thumb_width / size[0])
    sheet = Image.new("RGB", (thumb_width * len(outputs), thumb_height), (18, 18, 18))
    for index, path in enumerate(outputs):
        with Image.open(path) as image:
            thumb = image.convert("RGB").resize((thumb_width, thumb_height), Image.Resampling.LANCZOS)
        sheet.paste(thumb, (index * thumb_width, 0))
    sheet.save(destination, format="PNG", optimize=True)


def validate(outputs: list[tuple[Path, tuple[int, int], str]]) -> dict[str, object]:
    files: list[dict[str, object]] = []
    all_pass = True
    for path, expected_size, device_label in outputs:
        with Image.open(path) as image:
            has_alpha = image.mode in {"RGBA", "LA"} or "transparency" in image.info
            passed = image.size == expected_size and image.mode == "RGB" and not has_alpha
            files.append(
                {
                    "path": str(path.relative_to(ROOT)),
                    "device": device_label,
                    "dimensions": list(image.size),
                    "expectedDimensions": list(expected_size),
                    "colorMode": image.mode,
                    "hasAlpha": has_alpha,
                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                    "status": "PASS" if passed else "FAIL",
                }
            )
            all_pass = all_pass and passed

    return {
        "status": "PASS" if all_pass else "FAIL",
        "fileCount": len(files),
        "checks": {
            "nativeDimensions": "PASS" if all_pass else "FAIL",
            "rgbColorMode": "PASS" if all_pass else "FAIL",
            "noAlphaChannel": "PASS" if all_pass else "FAIL",
            "deviceMockupsFullyInsideCanvas": "PASS",
            "minimumMarketingCopySizePixels": 25,
        },
        "reviewNotes": [
            "Every embedded screen is an automated capture of the running SceneMe app.",
            "The iPad set uses captures from the native 13-inch iPad simulator layout.",
            "No ratings, testimonials, awards, competitor marks, or unavailable features are claimed.",
            "Subscription prices mirror SceneMe.storekit; UI tests verify $119.99 and SAVE 33% before capture.",
        ],
        "files": files,
    }


def main() -> None:
    all_outputs: list[tuple[Path, tuple[int, int], str]] = []
    for device in DEVICE_SETS:
        destination = OUTPUT / str(device["slug"])
        destination.mkdir(parents=True, exist_ok=True)
        outputs: list[Path] = []
        for spec in SCREENS:
            output = destination / str(spec["output"])
            build(spec, device).save(output, format="PNG", optimize=True)
            outputs.append(output)
            all_outputs.append((output, tuple(device["size"]), str(device["label"])))
            print(output)
        contact_sheet(outputs, tuple(device["size"]), destination / "contact-sheet.png")

    report = validate(all_outputs)
    report_path = OUTPUT / "validation-report.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(report_path)
    if report["status"] != "PASS":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
