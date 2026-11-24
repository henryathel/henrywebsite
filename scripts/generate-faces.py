#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["httpx==0.28.1", "pillow==12.0.0"]
# ///
"""Generate the face pool with FLUX.1 [dev] and XLabs' realism LoRA on Replicate.

Usage: REPLICATE_API_TOKEN=$(cat ~/.config/replicate/token) \\
           scripts/generate-faces.py OUTPUT_DIR [--count 300]

Writes OUTPUT_DIR/NNN.jpg (512x512, downscaled from 1024) and OUTPUT_DIR/manifest.json,
which records the model, version, shot, prompt and seed of every face. Faces that already
exist are skipped, so an interrupted run can be resumed. Look through the results and
delete any you don't like before running scripts/upload-faces.sh, which renumbers what is
left.

The faces are stand-ins matching Henry's broad profile (young white men), so the page
doesn't suggest he looks like someone he doesn't. Even-numbered faces are portraits and
odd-numbered ones are candid speaking shots. Each prompt is built from the attribute lists
below, chosen by a generator seeded from the face's number, so the pool varies in
appearance and setting and a resumed run asks for the same faces. Prompts never name a
real person (docs/decisions.md #25).
"""

import argparse
import io
import json
import os
import random
import sys
import time
from pathlib import Path

import httpx
from PIL import Image

MODEL = "xlabs-ai/flux-dev-realism"
# Pinned, so the model can't change under us between runs.
VERSION = "39b3434f194f87a900d1bc2b6d4b983e90f0dde1d5022c27b52c143d670758fa"
ENDPOINT = "https://api.replicate.com/v1/predictions"
# Generated at the model's native ~1 megapixel, where it renders skin and hair detail,
# then downscaled: the site shows faces at 256 CSS pixels, so 512 covers 2x screens.
SOURCE_SIZE = (1024, 1024)
SIZE = (512, 512)

# Repeats weight the pool towards the younger end; the model tends to age faces up.
AGES = [
    "aged about 25",
    "in his mid twenties",
    "in his mid twenties",
    "in his late twenties",
    "in his late twenties",
    "in his early thirties",
]
HERITAGE = [
    "British", "Irish", "Scottish", "Welsh", "American", "Scandinavian", "Norwegian",
    "Danish", "Swedish", "Finnish", "Dutch", "Belgian", "German", "Swiss", "French",
    "Italian", "Spanish", "Polish", "Greek", "Eastern European",
]  # fmt: skip
HAIR_COLOUR = ["blond", "ginger", "light brown", "dark brown", "black", "sandy"]
HAIR = [
    "short neat", "short wavy", "close-cropped", "curly", "tousled medium-length",
    "swept-back", "buzz-cut",
]  # fmt: skip
FACE = [
    "a round face", "a long narrow face", "a strong square jaw", "soft rounded features",
    "a slim angular face", "a broad face", "prominent cheekbones", "a boyish face",
]  # fmt: skip
BUILD = ["a skinny build", "a slim build", "an athletic build", "an average build"]
# Blank entries leave most faces without an extra detail.
EXTRAS = [
    "", "", "", "glasses", "freckles", "rosy cheeks", "thick eyebrows", "light stubble",
    "a clean-shaven face",
]  # fmt: skip
CLOTHING = [
    "a hoodie", "a blazer over a plain T-shirt", "a smart knitted jumper",
    "a fitted crew-neck top", "a casual overshirt", "a polo shirt", "a cardigan over a shirt",
]  # fmt: skip
BACKDROPS = [
    "a plain light grey studio backdrop", "a plain off-white studio backdrop",
    "a plain muted blue studio backdrop", "a softly blurred modern office",
    "a softly blurred city street", "a softly blurred park",
]  # fmt: skip
SCENES = [
    "giving a talk on a conference stage under spotlights",
    "speaking on a panel discussion, seated with a microphone",
    "presenting at a podium in a lecture theatre",
    "talking at a busy tech meetup",
    "chatting enthusiastically in a coworking space with daylight from large windows",
    "speaking at an outdoor rooftop event",
]
CAMERA = ["Three-quarter view", "Front view", "Slight side angle"]


def prompt_for(index: int) -> tuple[str, str]:
    """Return the shot type and prompt for face `index`."""
    # Seeded from a string, which is hashed: consecutive integer seeds can start with
    # the same choices, giving neighbouring faces the same traits.
    pick = random.Random(f"face-{index}").choice  # noqa: S311 - variety, not security
    heritage, extra = pick(HERITAGE), pick(EXTRAS)
    article = "an" if heritage[0] in "AEIOU" else "a"
    person = (
        f"{article} {heritage} man {pick(AGES)} with {pick(HAIR)} {pick(HAIR_COLOUR)} hair, "
        f"{pick(FACE)} and {pick(BUILD)}"
        + (f", {extra}" if extra else "")
        + f", wearing {pick(CLOTHING)}"
    )
    if index % 2 == 0:
        return "portrait", (
            f"Professional portrait photograph of {person}, in front of {pick(BACKDROPS)}. "
            "He is alone in the frame, looking at the camera with a relaxed, friendly "
            "expression. Head and shoulders, natural light, visible skin texture, no retouching."
        )
    return "speaking", (
        f"Candid photograph of {person}, {pick(SCENES)}. He is speaking animatedly "
        "mid-sentence with a friendly expression, the only person in focus. "
        f"{pick(CAMERA)}, tight head-and-shoulders framing with his face large in the frame, "
        "natural light, visible skin texture, no retouching."
    )


def predict(client: httpx.Client, prompt: str, seed: int) -> str:
    body = {
        "version": VERSION,
        "input": {
            "prompt": prompt,
            "seed": seed,
            "num_outputs": 1,
            "aspect_ratio": "1:1",
            "num_inference_steps": 30,
            # Below the default 3.5: lower guidance gives more natural, more varied faces.
            "guidance": 2.5,
            "lora_strength": 0.8,
            "output_format": "png",
        },
    }
    while True:
        response = client.post(ENDPOINT, json=body, headers={"Prefer": "wait"})
        if response.status_code == 429:
            time.sleep(float(response.headers.get("retry-after", "10")))
            continue
        response.raise_for_status()
        prediction = response.json()
        break
    while prediction["status"] in {"starting", "processing"}:
        time.sleep(2)
        prediction = client.get(prediction["urls"]["get"]).raise_for_status().json()
    if prediction["status"] != "succeeded":
        raise RuntimeError(
            f"prediction {prediction['id']} {prediction['status']}: {prediction.get('error')}"
        )
    return str(prediction["output"][0])


def generate(client: httpx.Client, out: Path, index: int) -> dict[str, object]:
    seed = 1000 + index
    shot, prompt = prompt_for(index)
    # The file host doesn't need the API token, so it doesn't get it.
    url = predict(client, prompt, seed)
    data = httpx.get(url, timeout=60, follow_redirects=True).raise_for_status().content
    name = f"{index:03d}.jpg"
    with Image.open(io.BytesIO(data)) as image:
        if image.format != "PNG" or image.size != SOURCE_SIZE:
            raise RuntimeError(f"unexpected output {image.format} {image.size} for face {index}")
        small = image.convert("RGB").resize(SIZE, Image.Resampling.LANCZOS)
        small.save(out / name, "JPEG", quality=88, optimize=True, progressive=True)
    print(f"{name} {shot:8} {prompt[:70]}...", flush=True)
    return {
        "file": name,
        "model": MODEL,
        "version": VERSION,
        "shot": shot,
        "prompt": prompt,
        "seed": seed,
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("output", type=Path)
    parser.add_argument("--count", type=int, default=300, help="faces to generate (default 300)")
    args = parser.parse_args()

    token = os.environ.get("REPLICATE_API_TOKEN")
    if not token:
        sys.exit("Set REPLICATE_API_TOKEN (replicate.com -> Account settings -> API tokens).")
    if not 0 < args.count <= 1000:
        sys.exit("--count must be between 1 and 1000.")

    out: Path = args.output
    out.mkdir(parents=True, exist_ok=True)
    manifest_path = out / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else []

    todo = [i for i in range(args.count) if not (out / f"{i:03d}.jpg").exists()]
    print(f"{len(todo)} faces to generate")

    # One at a time: low-credit Replicate accounts are rate-limited to a few predictions
    # at once, and each takes ~16 s, so 300 faces take about 80 minutes.
    headers = {"Authorization": f"Bearer {token}"}
    with httpx.Client(headers=headers, timeout=180, follow_redirects=True) as client:
        for index in todo:
            record = generate(client, out, index)
            manifest = [r for r in manifest if r["file"] != record["file"]] + [record]
            manifest.sort(key=lambda r: str(r["file"]))
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

    print(f"Done: {args.count} faces in {out}. Review them, then run scripts/upload-faces.sh {out}")


if __name__ == "__main__":
    main()
