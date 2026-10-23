#!/usr/bin/env python3
"""Drive noise augmentation over a whole source dataset.

For each entry in the source manifest:
  1. pick a noise file from the noise manifest (deterministic, seeded),
  2. convert both the speech and noise clips to 16 kHz mono 16-bit WAV,
  3. mix them at the requested SNR via mix_audio.py,
  4. write the mixed clip into <output-dir>/audio/ and record a new manifest
     entry that keeps the original clean reference.

Audio decoding to WAV uses `afconvert` (always present on macOS). The clean
reference text is preserved verbatim so WER is scored against ground truth.
"""
import argparse
import json
import os
import random
import subprocess
import sys
import tempfile


def to_wav_16k_mono(src: str, dst: str) -> bool:
    """Convert any afconvert-readable file to 16 kHz mono 16-bit WAV."""
    try:
        subprocess.run(
            [
                "afconvert", src, dst,
                "-f", "WAVE",
                "-d", "LEI16@16000",
                "-c", "1",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-manifest", required=True)
    parser.add_argument("--noise-manifest", required=True)
    parser.add_argument("--snr", type=float, required=True)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--mixer", required=True, help="path to mix_audio.py")
    args = parser.parse_args()

    source_dir = os.path.dirname(os.path.abspath(args.source_manifest))
    noise_dir = os.path.dirname(os.path.abspath(args.noise_manifest))
    out_dir = os.path.abspath(args.output_dir)
    audio_out = os.path.join(out_dir, "audio")
    os.makedirs(audio_out, exist_ok=True)

    with open(args.source_manifest, encoding="utf-8") as handle:
        source_entries = json.load(handle)
    with open(args.noise_manifest, encoding="utf-8") as handle:
        noise_entries = json.load(handle)

    if not noise_entries:
        print("error: noise manifest is empty", file=sys.stderr)
        return 1

    rng = random.Random(args.seed)
    records = []

    with tempfile.TemporaryDirectory() as tmp:
        for index, entry in enumerate(source_entries):
            speech_src = os.path.join(source_dir, entry["audio"])
            noise_entry = noise_entries[rng.randrange(len(noise_entries))]
            noise_src = os.path.join(noise_dir, noise_entry["audio"])

            speech_wav = os.path.join(tmp, f"speech_{index}.wav")
            noise_wav = os.path.join(tmp, f"noise_{index}.wav")
            if not to_wav_16k_mono(speech_src, speech_wav):
                print(f"warning: could not decode {speech_src}; skipping", file=sys.stderr)
                continue
            if not to_wav_16k_mono(noise_src, noise_wav):
                print(f"warning: could not decode {noise_src}; skipping", file=sys.stderr)
                continue

            out_name = f"{index:06d}.wav"
            out_path = os.path.join(audio_out, out_name)
            mix = subprocess.run(
                [
                    sys.executable, args.mixer,
                    "--speech", speech_wav,
                    "--noise", noise_wav,
                    "--snr", str(args.snr),
                    "--output", out_path,
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
            )
            if mix.returncode != 0:
                sys.stderr.write(mix.stderr.decode("utf-8", "replace"))
                continue

            records.append(
                {
                    "audio": os.path.join("audio", out_name),
                    "reference": entry["reference"],
                    "duration_seconds": entry.get("duration_seconds", 0.0),
                }
            )

    if not records:
        print("error: no clips were augmented", file=sys.stderr)
        return 1

    manifest_path = os.path.join(out_dir, "manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump(records, handle, ensure_ascii=False, indent=2)

    print(f"wrote {len(records)} augmented clips to {manifest_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
