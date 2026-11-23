#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["httpx==0.28.1", "pillow==12.0.0"]
# ///
"""Generate the face pool with FLUX.1 [schnell] on Replicate.

Usage: REPLICATE_API_TOKEN=... scripts/generate-faces.py OUTPUT_DIR [--count 300]

Writes OUTPUT_DIR/NNN.jpg (512x512) and OUTPUT_DIR/manifest.json, which records the
model, prompt and seed of every face. Faces that already exist are skipped, so an
interrupted run can be resumed. Look through the results and delete any you don't like
before running scripts/upload-faces.sh, which renumbers what is left.

Each face is its own prediction, with a prompt built from a fixed list of attributes
chosen by seed, so the pool varies in age, appearance and setting. They never name a real
person (docs/decisions.md #25).
"""

import argparse
import io
import json
import os
import random
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import httpx
from PIL import Image

MODEL = "black-forest-labs/flux-schnell"
ENDPOINT = f"https://api.replicate.com/v1/models/{MODEL}/predictions"
SIZE = (512, 512)

AGES = [
    "in their twenties",
    "in their thirties",
    "in their forties",
    "in their fifties",
    "in their sixties",
]
PEOPLE = ["man", "woman", "person"]
ANCESTRY = [
    "East Asian",
    "South Asian",
    "Southeast Asian",
    "Black",
    "white",
    "Latino",
    "Middle Eastern",
    "mixed-race",
    "Pacific Islander",
    "Indigenous",
]
HAIR = [
    "short hair",
    "long hair",
    "curly hair",
    "wavy hair",
    "close-cropped hair",
    "grey hair",
    "a shaved head",
    "braided hair",
    "hair tied back",
]
CLOTHING = [
    "a plain T-shirt",
    "a knitted jumper",
    "a collared shirt",
    "a casual jacket",
    "a hoodie",
    "a denim shirt",
    "a blazer",
]
SETTINGS = [
    "a plain light grey background",
    "a plain warm beige background",
    "a softly blurred office",
    "a softly blurred park",
    "a softly blurred city street",
    "a plain muted blue background",
]


def prompt_for(seed: int) -> str:
    pick = random.Random(seed).choice  # noqa: S311 - variety, not security
    subject = f"{pick(ANCESTRY)} {pick(PEOPLE)}"
    article = "an" if subject[0] in "AEIOU" else "a"
    return (
        f"Natural head-and-shoulders portrait photograph of {article} {subject} "
        f"{pick(AGES)} with {pick(HAIR)}, wearing {pick(CLOTHING)}, in front of {pick(SETTINGS)}. "
        "Looking at the camera with a relaxed expression, soft natural light, sharp focus, "
        "realistic skin texture, centred, face fully visible."
    )


def predict(client: httpx.Client, prompt: str, seed: int) -> str:
    body = {
        "input": {
            "prompt": prompt,
            "seed": seed,
            "num_outputs": 1,
            "aspect_ratio": "1:1",
            "megapixels": "0.25",
            "num_inference_steps": 4,
            "output_format": "jpg",
            "output_quality": 90,
        }
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
        time.sleep(1)
        prediction = client.get(prediction["urls"]["get"]).raise_for_status().json()
    if prediction["status"] != "succeeded":
        raise RuntimeError(
            f"prediction {prediction['id']} {prediction['status']}: {prediction.get('error')}"
        )
    return str(prediction["output"][0])


def generate(client: httpx.Client, out: Path, index: int) -> dict[str, object]:
    # Seeds are fixed per face, so a resumed run asks for the same prompts.
    seed = 1000 + index
    prompt = prompt_for(seed)
    # The file host doesn't need the API token, so it doesn't get it.
    url = predict(client, prompt, seed)
    data = httpx.get(url, timeout=60, follow_redirects=True).raise_for_status().content
    with Image.open(io.BytesIO(data)) as image:
        if image.format != "JPEG" or image.size != SIZE:
            raise RuntimeError(f"unexpected output {image.format} {image.size} for face {index}")
    name = f"{index:03d}.jpg"
    (out / name).write_bytes(data)
    print(f"{name} {prompt[:80]}...", flush=True)
    return {"file": name, "model": MODEL, "prompt": prompt, "seed": seed}


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("output", type=Path)
    parser.add_argument("--count", type=int, default=300, help="faces to generate (default 300)")
    parser.add_argument("--workers", type=int, default=4, help="concurrent predictions (default 4)")
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

    headers = {"Authorization": f"Bearer {token}"}
    with (
        httpx.Client(headers=headers, timeout=120, follow_redirects=True) as client,
        ThreadPoolExecutor(max_workers=args.workers) as pool,
    ):
        for record in pool.map(lambda i: generate(client, out, i), todo):
            manifest = [r for r in manifest if r["file"] != record["file"]] + [record]
            manifest.sort(key=lambda r: str(r["file"]))
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

    print(f"Done: {args.count} faces in {out}. Review them, then run scripts/upload-faces.sh {out}")


if __name__ == "__main__":
    main()
