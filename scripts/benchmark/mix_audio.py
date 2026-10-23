#!/usr/bin/env python3
"""Mix a clean speech clip with a noise clip at a target signal-to-noise ratio.

Reads two 16-bit PCM WAV files, resamples the noise to the speech sample rate
if needed (nearest-neighbour; adequate for broadband noise), scales the noise to
hit the requested SNR in dB, sums them, and writes a 16-bit PCM WAV.

Uses only the Python standard library (wave, audioop) so no third-party audio
packages are required. Non-WAV inputs must be converted to WAV upstream.
"""
import argparse
import array
import audioop
import math
import sys
import wave


def read_wav_mono16(path: str):
    with wave.open(path, "rb") as handle:
        channels = handle.getnchannels()
        width = handle.getsampwidth()
        rate = handle.getframerate()
        frames = handle.readframes(handle.getnframes())
    if width != 2:
        frames = audioop.lin2lin(frames, width, 2)
        width = 2
    if channels > 1:
        frames = audioop.tomono(frames, width, 0.5, 0.5)
    return frames, rate


def rms(frames: bytes) -> float:
    return audioop.rms(frames, 2)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--speech", required=True)
    parser.add_argument("--noise", required=True)
    parser.add_argument("--snr", type=float, required=True, help="target SNR in dB")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    speech, speech_rate = read_wav_mono16(args.speech)
    noise, noise_rate = read_wav_mono16(args.noise)

    # Match the noise sample rate to the speech rate.
    if noise_rate != speech_rate:
        noise, _ = audioop.ratecv(noise, 2, 1, noise_rate, speech_rate, None)

    # Tile or trim the noise to the speech length (in bytes).
    if len(noise) < len(speech):
        repeats = (len(speech) // max(len(noise), 1)) + 1
        noise = (noise * repeats)[: len(speech)]
    else:
        noise = noise[: len(speech)]

    speech_rms = rms(speech)
    noise_rms = rms(noise)
    if speech_rms == 0:
        print("error: speech signal is silent", file=sys.stderr)
        return 1
    if noise_rms == 0:
        # No noise energy: emit the clean speech unchanged.
        scaled_noise = noise
    else:
        # Solve for the noise gain that yields the target SNR:
        #   SNR_dB = 20 * log10(speech_rms / (noise_rms * gain))
        target_ratio = 10 ** (args.snr / 20.0)
        gain = speech_rms / (noise_rms * target_ratio)
        scaled_noise = audioop.mul(noise, 2, gain)

    mixed = audioop.add(speech, scaled_noise, 2)

    with wave.open(args.output, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(speech_rate)
        handle.writeframes(mixed)

    return 0


if __name__ == "__main__":
    sys.exit(main())
