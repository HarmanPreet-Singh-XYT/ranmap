#!/usr/bin/env python3
"""Synthesizes the app's UI sound effects into assets/sounds/*.wav.

Short, soft, sine-based cues (no samples, no licensing): each is a handful of
notes with a fast attack and exponential decay, in the spirit of Discord's
join/leave/mute tones. Re-run after tweaking:  python3 tool/generate_sounds.py
"""
import math, struct, wave, os

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sounds")
os.makedirs(OUT, exist_ok=True)


def note(freq, dur, vol=0.5, attack=0.004, decay=6.0, sweep=None, harmonics=(1.0, 0.25, 0.08)):
    """One enveloped tone; `sweep` glides the pitch to a target frequency."""
    n = int(RATE * dur)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = freq if sweep is None else freq + (sweep - freq) * (i / n)
        phase += 2 * math.pi * f / RATE
        s = sum(a * math.sin(phase * (k + 1)) for k, a in enumerate(harmonics))
        s /= sum(harmonics)
        env = min(1.0, t / attack) * math.exp(-decay * t / dur)
        # Short release so a clipped tail never clicks.
        rel = min(1.0, (n - i) / (RATE * 0.004))
        out.append(s * env * rel * vol)
    return out


def silence(dur):
    return [0.0] * int(RATE * dur)


def mix(*parts):
    n = max(len(p) for p in parts)
    return [sum(p[i] for p in parts if i < len(p)) for i in range(n)]


def seq(*parts):
    out = []
    for p in parts:
        out += p
    return out


def write(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = min(1.0, 0.9 / peak)
    path = os.path.join(OUT, f"{name}.wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767)) for s in samples))
    print(f"{name}.wav  {len(samples) / RATE * 1000:.0f} ms")


# Pitches
C5, D5, E5, G5, A5, B5, C6, E6 = 523.25, 587.33, 659.25, 783.99, 880.0, 987.77, 1046.5, 1318.5
G4, A4, B4 = 392.0, 440.0, 493.88

write("tap", note(1900, 0.03, 0.35, decay=9, harmonics=(1.0,)))
write("send", note(520, 0.11, 0.45, decay=4, sweep=980, harmonics=(1.0, 0.15)))
write("receive", seq(note(A5, 0.07, 0.4, decay=5), note(E6, 0.11, 0.4, decay=6)))
write("notify", mix(note(E6, 0.42, 0.45, decay=5, harmonics=(1.0, 0.5, 0.2)),
                    seq(silence(0.0), note(C6, 0.42, 0.25, decay=5))))
write("success", seq(note(C5, 0.08, 0.4), note(E5, 0.08, 0.4), note(G5, 0.18, 0.45, decay=5)))
write("error", seq(note(311, 0.11, 0.5, decay=3, harmonics=(1.0, 0.6, 0.3)),
                   note(233, 0.18, 0.5, decay=3, harmonics=(1.0, 0.6, 0.3))))
# Discord-style presence tones: join rises, leave falls.
write("voice_join", seq(note(G5, 0.09, 0.45), note(C6, 0.16, 0.45, decay=5)))
write("voice_leave", seq(note(C6, 0.09, 0.4), note(G5, 0.16, 0.4, decay=5)))
write("mute", note(660, 0.1, 0.4, decay=5, sweep=440, harmonics=(1.0, 0.1)))
write("unmute", note(440, 0.1, 0.4, decay=5, sweep=700, harmonics=(1.0, 0.1)))
write("trip_start", seq(note(C5, 0.1, 0.45), note(E5, 0.1, 0.45), note(G5, 0.1, 0.45),
                        note(C6, 0.34, 0.5, decay=4, harmonics=(1.0, 0.4, 0.15))))
write("trip_end", seq(note(G5, 0.12, 0.42), note(E5, 0.12, 0.42), note(C5, 0.36, 0.45, decay=4)))
write("nav_start", seq(note(A4, 0.09, 0.4), note(E5, 0.15, 0.42, decay=5)))
write("turn", note(B5, 0.16, 0.4, decay=6, harmonics=(1.0, 0.3)))
write("reroute", seq(note(E5, 0.07, 0.38), note(C5, 0.07, 0.38), note(E5, 0.12, 0.4)))
write("arrive", seq(note(E5, 0.12, 0.42), note(G5, 0.12, 0.42), note(C6, 0.4, 0.5, decay=4, harmonics=(1.0, 0.4, 0.15))))
write("refresh", note(700, 0.08, 0.35, decay=6, sweep=900, harmonics=(1.0,)))
