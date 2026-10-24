<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/readme/banner-dark.svg">
    <img src="docs/readme/banner-light.svg" alt="Shh.." width="400">
  </picture>
</p>

<p align="center">
  Hold fn. Say it. Done.<br>
  Voice dictation for your Mac, <em>on-device and private</em>
</p>

<p align="center">
  <img src="docs/readme/promo.webp" alt="The Shh.. promo: the face-and-hand mark shushes the keyboard, fn is held, and the spoken words fly into a message and get pasted" width="800">
</p>

Shh.. lives in your menu bar. Hold **fn**, say what you want to write, let go: the text is pasted wherever your cursor is.

- **Transcribes on your Mac** with [whisper.cpp](https://github.com/ggml-org/whisper.cpp). Your voice never leaves it.
- **Rewrites it in a Style** when you want one, like turning a ramble into an email, with OpenAI or a local model server.
- **Keeps a history** of everything you said, searchable from the dashboard.

> [!NOTE]
> Styles send the transcript (the text, never the audio) to the provider you set up. With no Style selected, nothing leaves your Mac.

## Install

Requires macOS 14+ on Apple Silicon, Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
git clone https://github.com/lorebalbo/shh...git
cd shh..
scripts/build-and-install.sh
```

The script downloads the Whisper Base model, builds a Release and installs it in `/Applications`. On first launch, grant **Microphone** (to hear you) and **Accessibility** (to notice fn and paste for you).

## Use it

| Do | To |
| --- | --- |
| Hold `fn` | Record, let go to transcribe and paste |
| `esc` | Cancel the recording |
| Click the widget | Record hands-free and pick a Style; click again to stop |
| `⌃⌥⌘V` | Paste the last transcript again |

Open the dashboard from the menu bar icon to write Styles, connect a provider, switch to a bigger Whisper model (Tiny to Large v3) or pin a language.

## Develop

```sh
scripts/dev-build.sh --regen                                  # Debug build, launched in place
xcodebuild test -project SHH.xcodeproj -scheme SHHTests       # unit tests
```

The transcription benchmark is described in [docs/benchmarks.md](docs/benchmarks.md).
