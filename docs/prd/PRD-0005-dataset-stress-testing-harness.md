---
status: Implemented
---
# PRD-0005: Dataset Stress Testing Harness

## 1. Problem

The benchmark suite from PRD-0004 only proves what we feed it. If we only
ever feed it ten ad-hoc clips a developer recorded at their desk, we'll
optimise the pipeline for one quiet room with one microphone and one voice,
and ship a transcriber that falls over the first time a user dictates from
a coffee shop, in a car, or with a fan running.

The field has standard datasets for exactly this reason:

- **LibriSpeech `test-clean` / `test-other`** — read English speech from
  audiobooks, with published Whisper baselines we can target.
- **MUSAN** — a corpus of music, speech, and ambient noise, used by the
  speech-recognition community to synthesise noise-augmented variants of
  clean datasets at controlled SNR levels.
- **CHiME** (CHiME-4 or CHiME-6) — real-world noisy recordings from buses,
  cafés, and public spaces. The gold standard for adversarial conditions.

We need a reproducible way to fetch these, generate noise-augmented mixes
on demand, and point PRD-0004's benchmark at any of them.

## 2. Objective

The system is able, via a documented script, to download a chosen public
dataset to a local cache directory, normalise its layout into the
`(audio, reference)` pair format PRD-0004 consumes, and — for noise
augmentation — mix LibriSpeech clean audio with MUSAN noise samples at
configurable signal-to-noise ratios, producing new augmented dataset
directories that PRD-0004 can benchmark against without code changes.

Verifiable outcomes:

- A developer is able to run one command per dataset to fetch and prepare
  it; subsequent runs are instant (idempotent).
- A developer is able to generate a `librispeech-test-clean+musan@10dB`
  augmented dataset directory with one command and feed it directly to
  PRD-0004's benchmark CLI.
- All dataset files live under a gitignored cache directory and never enter
  the app bundle or the git history.

## 3. User Flow

1. A developer wants to benchmark transcription quality on clean speech.
2. They run `./scripts/fetch-dataset.sh librispeech-test-clean`. The script
   downloads the upstream archive to `~/.cache/shh-benchmarks/librispeech/`,
   extracts it, and writes `~/.cache/shh-benchmarks/datasets/librispeech-
   test-clean/manifest.json` listing `(audio_path, reference_text)` pairs.
3. They run `./scripts/benchmark-transcription.sh --dataset librispeech-
   test-clean` (from PRD-0004). The benchmark resolves the dataset from
   the manifest and produces a report.
4. They now want to stress the pipeline with background noise. They run
   `./scripts/fetch-dataset.sh musan` once to grab the MUSAN noise corpus.
5. They run `./scripts/augment-dataset.sh --source librispeech-test-clean
   --noise musan --snr 10 --output librispeech-clean-musan-10db`. The
   script mixes each LibriSpeech clip with a randomly-chosen MUSAN
   noise sample at 10 dB SNR, writes the mixed audio to the cache, and
   produces a new manifest pointing at the mixed files with the **original
   clean references** preserved.
6. They run the benchmark against the new augmented dataset and compare
   WER vs. the clean run using PRD-0004's `--compare` mode.
7. Alternative: a CHiME dataset is licence-restricted and requires manual
   download. The fetch script detects that case, prints a clear message
   with the required download URL and the target path, and exits non-zero
   without attempting to download.
8. Alternative: the user re-runs `fetch-dataset.sh` on an already-fetched
   dataset. The script verifies a checksum, prints "already up to date",
   and exits zero immediately.

## 4. Acceptance Criteria

- [ ] A `scripts/fetch-dataset.sh` script supports at minimum the names
  `librispeech-test-clean`, `librispeech-test-other`, and `musan`. Adding a
  new dataset is a matter of registering one new entry in a data table at
  the top of the script.
- [ ] Each fetch downloads to a single configurable cache root
  (defaults to `~/.cache/shh-benchmarks/`), verifies a published checksum,
  and is idempotent on re-run.
- [ ] CHiME (and any other licence-restricted dataset) is supported as a
  registered name that emits a clear manual-download instruction instead of
  attempting an unauthorised download.
- [ ] After fetch, each dataset has a `manifest.json` (or `.jsonl`) at a
  predictable path listing `{audio: relative_path, reference: utf8_text,
  duration_seconds: float}` entries. PRD-0004's benchmark consumes that
  schema.
- [ ] A `scripts/augment-dataset.sh` script generates noise-augmented
  variants of any registered source dataset by mixing with samples from
  any registered noise dataset (MUSAN today; extensible to CHiME backgrounds
  or recorded room tone).
- [ ] The augmentation script accepts at minimum: `--source`, `--noise`,
  `--snr` (in dB, may be a single value or a list), `--output` (the name
  of the new dataset directory), and `--seed` (for reproducible random
  noise selection).
- [ ] Augmentation preserves the **clean** reference transcript in the new
  manifest. The hypothesis is generated from the noisy audio; the WER is
  measured against the clean reference; that is the whole point of the
  stress test.
- [ ] All dataset cache paths, manifest files, and augmented outputs are
  covered by `.gitignore` (top-level rule plus `scripts/benchmark/`-local
  rule as needed). A `git status` after fetching the largest dataset shows
  zero untracked files inside the repo.
- [ ] Disk usage is documented per dataset in `docs/benchmarks.md` (e.g.
  "LibriSpeech test-clean: ~350 MB; MUSAN: ~11 GB"). A `--dry-run` flag on
  the fetch script prints the disk requirement without downloading.
- [ ] PRD-0004's benchmark, run against each of the prepared datasets,
  produces a non-empty JSON report and a non-degenerate WER (i.e. not 0.0,
  not 1.0) on at least the LibriSpeech test-clean condition with the
  default model. This is the end-to-end smoke test that proves PRDs 0004
  and 0005 fit together.
- [ ] A short developer guide in `docs/benchmarks.md` walks through the
  full workflow: fetch clean → benchmark → fetch noise → augment →
  benchmark noisy → compare reports.
