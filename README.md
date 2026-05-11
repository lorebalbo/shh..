# Shh..

**Voice dictation for macOS — local, private, LLM-powered.**

Hold **Fn / Globe** to record. Release to transcribe. Text lands on your clipboard instantly.

<video src="https://github.com/user-attachments/assets/52ea7ee6-fcda-47d6-91d1-b03a810777ce" autoplay loop muted playsinline width="100%"></video>

---

## What it does

Shh.. lives in your menu bar and listens only when you tell it to. Speech is transcribed **on-device** via [Whisper.cpp](https://github.com/ggerganov/whisper.cpp) — nothing leaves your machine unless you enable an LLM provider. When a Style is active, the raw transcript is optionally refined by an LLM before hitting your clipboard.

## Features

- **Hold-to-record** — press Fn/Globe to start, release to stop; Esc cancels
- **On-device transcription** — Whisper models run locally, no cloud required
- **Styles** — custom LLM prompts that reshape text (formal, bullet points, code comments, etc.)
- **LLM providers** — bring your own API key (Anthropic Claude and compatible providers)
- **Dictation history** — searchable log of every transcription in the dashboard
- **Overlay widget** — floating waveform indicator shows recording state at a glance
- **Language detection** — auto-detect or pin a specific language for transcription

## Requirements

- macOS 14 Sonoma or later
- Microphone permission
- Accessibility permission (for the global Fn key tap)
- A Whisper model file (download via the app or `scripts/download-model.sh`)

## Getting Started

1. **Download** the latest `.dmg` from [Releases](../../releases) and drag Shh.. to Applications.
2. **Launch** — grant Microphone and Accessibility permissions when prompted.
3. **Download a Whisper model** from the *Whisper Models* section in the dashboard (tiny or base are good starting points).
4. **Hold Fn / Globe** anywhere on your Mac to record. Release to transcribe and copy.

### Optional: enable LLM Styles

1. Open the dashboard → **LLM Providers** → add your API key.
2. Go to **Styles** → create a style with a system prompt (e.g. *"Rewrite as concise bullet points"*).
3. The overlay widget shows a style picker — select a style before recording.

## Building from source

```bash
# Install dependencies
brew install xcodegen
scripts/download-model.sh   # downloads whisper-base.bin into the app's support directory

# Generate the Xcode project and build
xcodegen generate
xcodebuild build -project SHH.xcodeproj -scheme SHH -configuration Release
```

## Privacy

All audio is processed locally. Transcription never leaves your device. An LLM provider is contacted only when a Style is active and you have configured an API key — the text sent is limited to the transcribed excerpt.
