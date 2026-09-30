#!/usr/bin/env python3
"""Generate original short PCM reminder tones; no third-party sound samples."""
import math
import pathlib
import struct
import subprocess
import tempfile
import wave

root = pathlib.Path(__file__).resolve().parents[1]
sounds = root / 'Resources' / 'Sounds'
sounds.mkdir(parents=True, exist_ok=True)
rate = 44100
recipes = {
    'Glass': (1.6, [(880, 1, 3.5), (1762, .3, 5), (2648, .12, 7)]),
    'Ping': (1.0, [(1174.66, 1, 6), (2349.32, .18, 9)]),
    'Pop': (.35, [(523.25, 1, 16), (1046.5, .2, 20)]),
    # A slowly unfolding, harmonically rich tone synthesized from sine waves;
    # this is an original notification tone, not a recorded adhan.
    'Azan': (3.2, [(392, 1, 1.2), (587.33, .52, 1.8), (784, .28, 2.4), (1174.66, .1, 3.2)]),
}
with tempfile.TemporaryDirectory(prefix='pray-daily-tones-') as tmp:
    for name, (duration, partials) in recipes.items():
        samples = []
        for i in range(int(duration * rate)):
            t = i / rate
            attack = min(1, t / .008)
            release = min(1, (duration - t) / .08)
            value = sum(a * math.sin(2 * math.pi * f * t) * math.exp(-decay * t) for f, a, decay in partials)
            samples.append(value * attack * release)
        scale = .52 * 32767 / max(abs(x) for x in samples)
        wav_path = pathlib.Path(tmp) / (name + '.wav')
        with wave.open(str(wav_path), 'wb') as output:
            output.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
            output.writeframes(b''.join(struct.pack('<h', int(x * scale)) for x in samples))
        subprocess.run(['afconvert', str(wav_path), str(sounds / (name + '.aiff')), '-f', 'AIFF', '-d', 'BEI16@44100'], check=True)
        print(name, duration, 'seconds')
