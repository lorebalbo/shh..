#!/usr/bin/env python3
"""Convert a raw downloaded dataset layout into the benchmark manifest schema.

Emits a JSON array of objects:
    {"audio": <relative_path>, "reference": <utf8_text>, "duration_seconds": <float>}

For the MUSAN noise corpus there are no transcripts; entries carry an empty
reference and exist only so the augmentation script can enumerate noise files.

Audio paths in the manifest are stored relative to the manifest's own
directory so the dataset cache is relocatable.
"""
import argparse
import json
import os
import sys
import wave


def audio_duration_seconds(path: str) -> float:
    """Best-effort duration. Uses the stdlib wave module for WAV; for FLAC and
    other formats, returns 0.0 (the benchmark reads the true duration from the
    decoded audio, so this hint is optional)."""
    if path.lower().endswith(".wav"):
        try:
            with wave.open(path, "rb") as handle:
                frames = handle.getnframes()
                rate = handle.getframerate()
                return frames / float(rate) if rate else 0.0
        except (wave.Error, OSError):
            return 0.0
    return 0.0


def collect_librispeech(raw_root: str):
    """Walk a LibriSpeech tree, reading *.trans.txt transcript indexes."""
    entries = []
    for dirpath, _dirs, files in os.walk(raw_root):
        trans_files = [f for f in files if f.endswith(".trans.txt")]
        for trans in trans_files:
            with open(os.path.join(dirpath, trans), encoding="utf-8") as handle:
                for line in handle:
                    line = line.strip()
                    if not line:
                        continue
                    utt_id, _, text = line.partition(" ")
                    audio = os.path.join(dirpath, utt_id + ".flac")
                    if not os.path.exists(audio):
                        audio = os.path.join(dirpath, utt_id + ".wav")
                    if os.path.exists(audio):
                        entries.append((audio, text))
    return entries


def collect_musan(raw_root: str):
    """Enumerate MUSAN noise audio files (no references)."""
    entries = []
    for dirpath, _dirs, files in os.walk(raw_root):
        for name in files:
            if name.lower().endswith((".wav", ".flac")):
                entries.append((os.path.join(dirpath, name), ""))
    return entries


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--kind", required=True, choices=["librispeech", "musan"])
    parser.add_argument("--raw", required=True, help="Extracted dataset root")
    parser.add_argument("--output", required=True, help="manifest.json path")
    args = parser.parse_args()

    if args.kind == "librispeech":
        raw_entries = collect_librispeech(args.raw)
    else:
        raw_entries = collect_musan(args.raw)

    if not raw_entries:
        print(f"error: no audio found under {args.raw}", file=sys.stderr)
        return 1

    manifest_dir = os.path.dirname(os.path.abspath(args.output))
    os.makedirs(manifest_dir, exist_ok=True)

    records = []
    for audio_path, text in raw_entries:
        rel = os.path.relpath(os.path.abspath(audio_path), manifest_dir)
        records.append(
            {
                "audio": rel,
                "reference": text,
                "duration_seconds": audio_duration_seconds(audio_path),
            }
        )

    records.sort(key=lambda record: record["audio"])
    with open(args.output, "w", encoding="utf-8") as handle:
        json.dump(records, handle, ensure_ascii=False, indent=2)

    print(f"wrote {len(records)} entries to {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
