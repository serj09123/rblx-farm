#!/usr/bin/env python3
"""Synthesizes the game's placeholder-replacement audio (original, royalty-free).
Usage: python3 scripts/make-audio.py   -> writes assets/audio/*.wav (44.1 kHz mono 16-bit)"""
import math, random, struct, wave, os

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
random.seed(7)

def note(freq, dur, vol=0.5, shape="sine", attack=0.005, decay=None, vibrato=0.0):
    n = int(SR * dur)
    decay = decay if decay is not None else dur
    out = []
    for i in range(n):
        t = i / SR
        f = freq * (1 + vibrato * math.sin(2 * math.pi * 5 * t))
        ph = 2 * math.pi * f * t
        if shape == "sine":
            s = math.sin(ph) + 0.25 * math.sin(2 * ph) + 0.1 * math.sin(3 * ph)
        elif shape == "tri":
            s = 2 / math.pi * math.asin(math.sin(ph))
        else:  # soft square
            s = math.tanh(3 * math.sin(ph))
        env = min(1, t / attack) * math.exp(-4.0 * t / decay)
        env *= min(1, (dur - t) / 0.01)
        out.append(s * env * vol)
    return out

def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, v in enumerate(t):
            out[i] += v
    return out

def at(track, start, length_total):
    pad = int(SR * start)
    out = [0.0] * pad + track
    return out + [0.0] * max(0, int(SR * length_total) - len(out))

def noise(dur, vol=0.3, decay=0.05):
    n = int(SR * dur)
    return [(random.random() * 2 - 1) * vol * math.exp(-t / SR / decay) for t in range(n)]

def seq(notes, total, **kw):
    return mix(*[at(note(f, d, **kw), s, total) for f, s, d in notes])

def save(name, samples, norm=0.85):
    peak = max(1e-9, max(abs(s) for s in samples))
    gain = min(1.0, norm / peak) if peak > norm else 1.0
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * gain)) * 32767)) for s in samples))
    print("wrote", path, f"{len(samples)/SR:.2f}s")

# UI click: soft, short tap
save("click", mix(note(880, 0.07, 0.35, "tri", decay=0.05), noise(0.01, 0.15, 0.004)))
# coins: two bright rising pings
save("coins", seq([(1318, 0, 0.18), (1760, 0.08, 0.3)], 0.45, vol=0.35, decay=0.25))
# hatch: crack (noise burst) + pop + little rise
save("hatch", mix(noise(0.08, 0.5, 0.02), at(note(220, 0.12, 0.5, "tri", decay=0.08), 0.06, 0.6),
                  at(note(660, 0.25, 0.35, decay=0.2), 0.14, 0.6), at(note(990, 0.25, 0.3, decay=0.2), 0.2, 0.6)))
# rare: sparkle arpeggio
save("rare", seq([(f, i * 0.07, 0.4) for i, f in enumerate([784, 988, 1175, 1568, 1976])], 0.9, vol=0.28, decay=0.35))
# mythic: fanfare chord swell
save("mythic", mix(seq([(523, 0, 1.1), (659, 0, 1.1), (784, 0, 1.1)], 1.8, vol=0.22, shape="sine", attack=0.08, decay=1.2, vibrato=0.004),
                   seq([(1047, 0.35, 1.2), (1319, 0.55, 1.0), (1568, 0.75, 0.9)], 1.8, vol=0.2, decay=0.9)))
# bloom: magical upward swell
save("bloom", mix(seq([(392 * 2 ** (k / 12), k * 0.09, 0.5) for k in range(0, 13, 2)], 1.4, vol=0.22, attack=0.03, decay=0.5, vibrato=0.006),
                  seq([(1568, 0.7, 0.6), (2093, 0.78, 0.6)], 1.4, vol=0.15, decay=0.5)))
# trade: friendly two-note chime
save("trade", seq([(659, 0, 0.35), (880, 0.12, 0.5)], 0.8, vol=0.32, shape="tri", decay=0.4))
# error: short muted low buzz
save("error", mix(note(150, 0.16, 0.4, "square", decay=0.12), note(142, 0.16, 0.3, "square", decay=0.12)))

# music: ~48 s calm loop. Slow I-vi-IV-V in C with soft pad + gentle pluck melody.
def chord(freqs, dur, vol=0.12):
    return mix(*[note(f, dur, vol, "sine", attack=0.4, decay=dur * 2.2) for f in freqs])

BEAT = 1.5
progression = [([130.8, 196, 261.6, 329.6], [523, 659, 784, 659]),
               ([110, 164.8, 220, 261.6], [440, 523, 659, 523]),
               ([87.3, 130.8, 174.6, 220], [349, 440, 523, 440]),
               ([98, 146.8, 196, 246.9], [392, 494, 587, 494])]
total = BEAT * 4 * len(progression) * 2
tracks = []
for rep in range(2):
    for i, (pad, mel) in enumerate(progression):
        start = (rep * len(progression) + i) * BEAT * 4
        tracks.append(at(chord(pad, BEAT * 4), start, total))
        order = mel if rep == 0 else mel[::-1]
        for j, f in enumerate(order):
            tracks.append(at(note(f, BEAT * 1.4, 0.16, "tri", attack=0.01, decay=BEAT), start + j * BEAT, total))
music = mix(*tracks)
# fade the tail into the head so the loop is seamless
fade = int(SR * 1.5)
for i in range(fade):
    music[i] *= i / fade
    music[-fade + i] *= 1 - i / fade
save("music", music, norm=0.6)
