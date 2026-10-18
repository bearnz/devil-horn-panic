"""Cut a multi-shot firearm recording into one game-ready file per shot.

Every real gunshot library that turned up for this project ships **montages** —
six to twenty rounds fired into one take, with room tone and a bolt cycle between
them — because that is what is useful to a sound designer with a DAW open. It is
useless to a game, which needs one file per shot, and there is nothing to be
gained by cutting fifty of them by hand.

Three things happen here, and only the first is obvious.

**Slicing.** Each transient becomes its own file with a short pre-roll, since the
crack starts before any level detector can trip on it, and a tail long enough to
keep the report's decay — the decay is most of what makes a gun sound big.

**Downsampling.** The good libraries are mastered at 96kHz/24-bit, which is six
times the bytes a game sound effect can use and audibly no better through it.
Decimation alone would fold everything above the new Nyquist back down as
aliasing, so the anti-alias filter is not optional: it is a windowed-sinc FIR
applied before every second sample is thrown away. Written out here rather than
imported because the alternative was a scipy dependency for one convolution.

**Peak normalising.** Studio recordings are cut with headroom and arrive far
quieter than the CC0 pack material they are auditioned against, and a candidate
that is merely *louder* wins a listening test it did not deserve. Levelling the
peaks is what makes the comparison about character. It deliberately discards the
real loudness difference between a .22 and a .45 — which is a mixing decision,
made later, per weapon, with `volume_db`.

    python tools/audio/split_shots.py <out_dir> <file.wav> [file.wav ...]

Requires numpy. Not part of any build; run by hand when new source audio arrives.
"""

import os
import sys
import wave

import numpy as np

PRE_ROLL = 0.02  # seconds kept ahead of the trigger, so the attack is not clipped
TAIL = 0.45  # seconds kept after the level falls back under the gate
GATE = 0.12  # fraction of peak that counts as "a shot is happening"
MIN_GAP = 0.20  # seconds of quiet before a new transient counts as a new shot
MIN_LENGTH = 0.05  # anything shorter than this is a click, not a shot

TARGET_RATE = 48000  # what the project wants; sources are usually 96k
PEAK = 0.891  # -1 dBFS, leaving room for the odd inter-sample overshoot

# Anti-alias filter. The cutoff sits below the *output* Nyquist rather than at it,
# because a brick wall needs infinite taps and the gap is the transition band.
FILTER_TAPS = 129
CUTOFF_OF_NYQUIST = 0.9


def read_wav(path):
    """Samples as float in [-1, 1], shaped (frames, channels)."""
    with wave.open(path) as w:
        frames, channels = w.getnframes(), w.getnchannels()
        width, rate = w.getsampwidth(), w.getframerate()
        raw = w.readframes(frames)

    if width == 3:
        # 24-bit has no numpy dtype. Widen each 3-byte sample into the *top* three
        # bytes of an int32 so the sign comes out right, then scale it back down.
        packed = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3)
        wide = np.zeros((len(packed), 4), dtype=np.uint8)
        wide[:, 1:] = packed
        data = wide.view(np.int32).squeeze(-1).astype(np.float64) / (1 << 31)
    elif width == 1:
        # 8-bit wav is unsigned, unlike every other width.
        data = (np.frombuffer(raw, dtype=np.uint8).astype(np.float64) - 128) / 128.0
    elif width == 2:
        data = np.frombuffer(raw, dtype=np.int16).astype(np.float64) / (1 << 15)
    elif width == 4:
        data = np.frombuffer(raw, dtype=np.int32).astype(np.float64) / (1 << 31)
    else:
        raise ValueError(f"{path}: unsupported sample width {width}")

    return data.reshape(-1, channels), rate


def write_wav(path, data, rate):
    """16-bit, which is what a game sound effect wants."""
    clipped = np.clip(data, -1.0, 1.0)
    samples = (clipped * ((1 << 15) - 1)).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(samples.shape[1])
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(samples.tobytes())


def low_pass(taps, cutoff):
    """Windowed-sinc FIR. `cutoff` is in cycles per sample of the input rate."""
    n = np.arange(taps) - (taps - 1) / 2.0
    kernel = 2.0 * cutoff * np.sinc(2.0 * cutoff * n)
    kernel *= np.blackman(taps)
    return kernel / kernel.sum()


def resample(data, rate, target):
    """Integer-factor decimation, anti-aliased. Non-integer ratios are refused
    rather than approximated — every source seen so far is a clean multiple, and
    a silently wrong resample is worse than a stop."""
    if rate == target:
        return data, rate
    if rate % target != 0:
        raise ValueError(f"cannot decimate {rate} to {target}: not a multiple")

    factor = rate // target
    kernel = low_pass(FILTER_TAPS, CUTOFF_OF_NYQUIST / (2.0 * factor))
    filtered = np.column_stack([
        np.convolve(data[:, c], kernel, mode="same") for c in range(data.shape[1])
    ])
    return filtered[::factor], target


def normalise(block):
    peak = np.abs(block).max()
    if peak <= 0.0:
        return block
    return block * (PEAK / peak)


def find_shots(data, rate):
    """Spans of (start, end) frames, one per transient."""
    mono = np.abs(data.mean(axis=1))

    # Envelope over a 5 ms window, so a single noisy sample cannot open the gate.
    window = max(1, int(rate * 0.005))
    envelope = np.convolve(mono, np.ones(window) / window, mode="same")
    hot = envelope > envelope.max() * GATE

    gap = int(rate * MIN_GAP)
    spans, start, quiet = [], None, 0
    for i, on in enumerate(hot):
        if on:
            if start is None:
                start = i
            quiet = 0
        elif start is not None:
            quiet += 1
            if quiet > gap:
                spans.append((start, i))
                start, quiet = None, 0
    if start is not None:
        spans.append((start, len(hot)))
    return spans


def split(path, out_dir, stem):
    data, rate = read_wav(path)
    data, rate = resample(data, rate, TARGET_RATE)

    pre, tail = int(rate * PRE_ROLL), int(rate * TAIL)
    written = []
    for k, (a, b) in enumerate(find_shots(data, rate), 1):
        a = max(0, a - pre)
        b = min(len(data), b + tail)
        if (b - a) / rate < MIN_LENGTH:
            continue
        out = os.path.join(out_dir, f"{stem}_{k:02d}.wav")
        write_wav(out, normalise(data[a:b]), rate)
        written.append((out, (b - a) / rate))
    return written


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    for src in sys.argv[2:]:
        stem = os.path.splitext(os.path.basename(src))[0]
        got = split(src, out_dir, stem)
        print(f"{stem}: {len(got)} shots")
        for p, d in got:
            print(f"   {d:5.2f}s  {os.path.basename(p)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
