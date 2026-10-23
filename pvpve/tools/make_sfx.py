#!/usr/bin/env python3
"""Synthesizes the placeholder sound effects in assets/sfx/ (no dependencies).

They are deliberately simple and original (noise, sine sweeps, envelopes) so the game
has sound for every action while real audio is still to come in M7.
Run: python3 pvpve/tools/make_sfx.py
"""
import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")


def write(name, samples):
    peak = max(max(abs(s) for s in samples), 1e-9)
    scale = min(1.0, 0.9 / peak)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples))
    print("wrote", os.path.relpath(path), len(samples) / RATE, "s")


def n(seconds):
    return int(seconds * RATE)


def noise(rng, count):
    return [rng.uniform(-1.0, 1.0) for _ in range(count)]


def lowpass(samples, amount):
    out, prev = [], 0.0
    for s in samples:
        prev += (s - prev) * amount
        out.append(prev)
    return out


def sweep(f0, f1, seconds, shape=1.0):
    out, phase = [], 0.0
    count = n(seconds)
    for i in range(count):
        t = i / max(count - 1, 1)
        freq = f0 + (f1 - f0) * (t ** shape)
        phase += 2 * math.pi * freq / RATE
        out.append(math.sin(phase))
    return out


def decay(samples, rate):
    count = len(samples)
    return [s * math.exp(-rate * i / count) for i, s in enumerate(samples)]


def mix(*tracks):
    length = max(len(t) for t in tracks)
    return [sum(t[i] for t in tracks if i < len(t)) for i in range(length)]


def gain(samples, g):
    return [s * g for s in samples]


def delay(samples, seconds):
    return [0.0] * n(seconds) + samples


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = random.Random(7)

    write("shot", mix(
        decay(noise(rng, n(0.14)), 9.0),
        gain(decay(sweep(190, 55, 0.14), 6.0), 0.9)))
    write("hit", gain(decay(sweep(1500, 1250, 0.06), 5.0), 1.0))
    write("kill", mix(
        decay(sweep(700, 700, 0.09), 3.0),
        delay(decay(sweep(1050, 1050, 0.14), 4.0), 0.09)))
    write("hurt", mix(
        decay(sweep(110, 60, 0.18), 5.0),
        gain(decay(lowpass(noise(rng, n(0.18)), 0.25), 8.0), 0.8)))
    write("reload", mix(
        decay(lowpass(noise(rng, n(0.05)), 0.7), 7.0),
        delay(decay(lowpass(noise(rng, n(0.06)), 0.45), 6.0), 0.42)))
    write("empty", decay(lowpass(noise(rng, n(0.04)), 0.6), 6.0))
    swing = lowpass(noise(rng, n(0.32)), 0.18)
    write("swing", [s * math.sin(math.pi * i / len(swing)) ** 1.5 for i, s in enumerate(swing)])
    write("bow", mix(
        decay(sweep(240, 215, 0.4), 6.0),
        gain(decay(sweep(480, 430, 0.4), 8.0), 0.45),
        gain(decay(lowpass(noise(rng, n(0.05)), 0.8), 10.0), 0.5)))
    orb = sweep(220, 900, 0.34, 1.6)
    write("orb", [s * (0.75 + 0.25 * math.sin(i * 0.05)) * math.sin(math.pi * min(1.0, i / len(orb) * 1.1)) for i, s in enumerate(orb)])
    write("explosion", mix(
        decay(lowpass(noise(rng, n(0.8)), 0.12), 4.0),
        gain(decay(sweep(90, 35, 0.8), 3.5), 1.1)))
    write("respawn", mix(
        decay(sweep(440, 440, 0.12), 3.0),
        delay(decay(sweep(660, 660, 0.12), 3.0), 0.09),
        delay(decay(sweep(880, 880, 0.2), 3.5), 0.18)))
    write("draw", mix(
        gain(decay(lowpass(noise(rng, n(0.45)), 0.05), 2.0), 0.7),
        gain(sweep(80, 130, 0.45), 0.15)))


if __name__ == "__main__":
    main()
