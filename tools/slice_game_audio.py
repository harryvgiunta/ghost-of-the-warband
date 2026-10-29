"""Build the game's audio assets from the raw recording library.

The sources are the recordings the warband was scored and foleyed with; this
script is the one place that says which part of which file became which sound.
It is deterministic (fixed windows, fixed seeds, no detection at run time), so
re-running it reproduces the exact tree the game ships.

    python tools/slice_game_audio.py                 # write assets/audio
    python tools/slice_game_audio.py --check         # verify the built tree
    python tools/slice_game_audio.py --sources DIR   # other raw library root

Every slice is trimmed to mono 48 kHz, peak-normalised to -1 dBFS with a short
fade on both ends (a hard cut clicks), then encoded as Vorbis with `-bitexact`,
so the same window always produces the same bytes. Mono is not a
downgrade here: the engine pans a 3D one-shot itself, and a stereo stream on an
`AudioStreamPlayer3D` cannot be placed in the world.

The music is copied verbatim - both files are already mastered - and is looped
by the runtime (`AudioManager`), not by the file.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCES = Path.home() / "Downloads"
AUDIO_LAB = Path.home() / "game-audio-lab" / "outputs"

RATE = 48000
PEAK = 10.0 ** (-1.0 / 20.0)  # -1 dBFS
FADE = 0.004  # seconds

MUSIC = {
    "menu_theme.ogg": AUDIO_LAB / "mastered" / "ashgate_theme_loop.ogg",
    "warband_soundtrack.ogg": AUDIO_LAB / "warband_soundtrack" / "warband_soundtrack.ogg",
}

# Sources that are cut into several one-shots. `windows` are (start, end) in
# seconds of the source, the order is the variant order the game plays.
SLICED = {
    # 1H swing. The recording is thirteen takes, one after another.
    "short_whoosh": {
        "source": "427979__kinoton__short-whoosh-13x.wav",
        "windows": [
            (0.22, 0.52), (1.27, 1.57), (2.27, 2.57), (3.42, 3.77),
            (4.67, 4.97), (5.77, 6.02), (6.82, 7.12), (7.97, 8.32),
            (9.17, 9.52), (10.22, 10.62), (11.42, 11.77), (12.42, 12.82),
            (13.52, 13.87),
        ],
    },
    # Dagger swing: the same thirteen takes cut to their leading third, because a
    # dagger is not a sword swung by a smaller man - it is a flick, and the sound
    # has to be over before a sword's would still be travelling.
    "dagger_whoosh": {
        "source": "427979__kinoton__short-whoosh-13x.wav",
        "windows": [
            (0.26, 0.40), (2.31, 2.45), (4.71, 4.85),
            (6.86, 7.00), (9.21, 9.35), (11.46, 11.60),
        ],
    },
    # 2H swing: one long bamboo whoosh, the arc a two-handed piece draws.
    "long_whoosh": {
        "source": "855844__sadiquecat__whoosh-long-bamboo-stick-os-st-13.wav",
        "windows": [(0.02, 0.44)],
    },
    # Blunt impact: three hits with a fist, one per variant.
    "blunt": {
        "source": "460509__florianreichelt__hitting-in-a-face.mp3",
        "windows": [(0.37, 0.74), (1.67, 2.04), (2.91, 3.13)],
    },
    # Landed blade: the eight clearest takes of the sixteen.
    "slit": {
        "source": "873151__artninja__sword_throat_slitting_sound_10032026.wav",
        "windows": [
            (24.61, 25.02), (19.07, 19.40), (33.69, 34.02), (8.39, 8.72),
            (22.39, 22.68), (11.53, 11.82), (42.07, 42.38), (36.73, 37.08),
        ],
    },
    # Steel on steel, split by what the ear needs: the short bright takes snap
    # (a parry), the longer ringing ones carry weight (a held block).
    "parry": {
        "source": "568790__fenodyrie__sword-against-sword.wav",
        "windows": [(2.30, 2.84), (3.68, 4.30), (52.40, 52.72), (20.38, 20.74)],
    },
    "clash": {
        "source": "568790__fenodyrie__sword-against-sword.wav",
        "windows": [(25.68, 26.50), (19.42, 20.28), (13.76, 14.60), (10.86, 11.80)],
    },
    # A blade let go of: the throw's leading whoosh and two later arcs.
    "blade": {
        "source": "334167__loudernoises__flying-blade.wav",
        "windows": [(0.00, 0.52), (0.45, 1.10), (2.15, 2.65)],
    },
    # The bow releases: one arrow, whole.
    "arrow": {
        "source": "205563__everheat__arrow.wav",
        "windows": [(0.00, 0.56)],
    },
}

# Output folder per group. The game loads `res://assets/audio/sfx/<group>/`.
GROUPS = {
    "short_whoosh": "swing",
    "dagger_whoosh": "swing",
    "long_whoosh": "swing",
    "blunt": "impact",
    "slit": "impact",
    "parry": "defense",
    "clash": "defense",
    "blade": "thrown",
    "arrow": "bow",
}


def scaled(samples: np.ndarray) -> np.ndarray:
    """Peak-normalise to `PEAK` and fade both ends. Silence stays silent."""
    peak = float(np.abs(samples).max()) if samples.size else 0.0
    if peak > 1e-6:
        samples = samples * (PEAK / peak)
    count = min(int(FADE * RATE), samples.size // 2)
    if count > 1:
        ramp = np.linspace(0.0, 1.0, count, dtype=np.float32)
        samples[:count] *= ramp
        samples[-count:] *= ramp[::-1]
    return samples


def encode(samples: np.ndarray, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as scratch:
        raw = Path(scratch) / "slice.wav"
        sf.write(raw, samples, RATE, subtype="PCM_16")
        subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-i", str(raw),
             "-c:a", "libvorbis", "-q:a", "5",
             # Without these two the Ogg muxer stamps a random stream serial and
             # an encoder tag, so the same window re-encodes to different bytes
             # and every re-run dirties the tree.
             "-fflags", "+bitexact", "-map_metadata", "-1", str(destination)],
            check=True,
        )


def build(sources: Path, out: Path) -> list[tuple[str, float, float]]:
    built: list[tuple[str, float, float]] = []
    music_dir = out / "music"
    music_dir.mkdir(parents=True, exist_ok=True)
    for name, source in MUSIC.items():
        if not source.exists():
            raise SystemExit(f"missing music source: {source}")
        shutil.copy2(source, music_dir / name)
        with sf.SoundFile(source) as handle:
            built.append((str(music_dir / name), len(handle) / handle.samplerate, 0.0))

    for group, recipe in SLICED.items():
        source = sources / recipe["source"]
        if not source.exists():
            raise SystemExit(f"missing source: {source}")
        samples, rate = sf.read(source, always_2d=True, dtype="float32")
        mono = samples.mean(axis=1)
        for index, (start, end) in enumerate(recipe["windows"], start=1):
            window = mono[int(start * rate):int(end * rate)]
            if window.size == 0:
                raise SystemExit(f"{group}: empty window {start}-{end}")
            resampled = window if rate == RATE else np.interp(
                np.linspace(0.0, 1.0, int(window.size * RATE / rate), endpoint=False),
                np.linspace(0.0, 1.0, window.size, endpoint=False),
                window).astype(np.float32)
            destination = out / "sfx" / GROUPS[group] / f"{group}_{index:02d}.ogg"
            encode(scaled(resampled.astype(np.float32)), destination)
            built.append((str(destination), resampled.size / RATE, PEAK))
    return built


def check(out: Path) -> int:
    expected = [out / "music" / name for name in MUSIC]
    for group, recipe in SLICED.items():
        expected += [out / "sfx" / GROUPS[group] / f"{group}_{index:02d}.ogg"
                     for index in range(1, len(recipe["windows"]) + 1)]
    missing = [str(path) for path in expected if not path.exists()]
    for path in missing:
        print(f"MISSING {path}")
    print(f"{len(expected) - len(missing)}/{len(expected)} audio assets present")
    return 1 if missing else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", type=Path, default=DEFAULT_SOURCES)
    parser.add_argument("--out", type=Path, default=ROOT / "assets" / "audio")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        return check(args.out)
    for path, seconds, level in build(args.sources, args.out):
        print(f"{path}  {seconds:6.2f}s  {level:.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
