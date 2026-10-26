"""Gera os efeitos sonoros da mesa contra o bot (sintetizados, sem amostras
de terceiros: não há licenças a respeitar).

Saem para android/app/src/main/res/raw/sfx_*.wav (mono, 22 050 Hz, 16 bits)
e tocam-se pelo SoundPool do Android (MainActivity, canal edhere/sfx).

Uso: python -I tool/sfx/gen_sfx.py
"""

import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'android', 'app', 'src', 'main', 'res', 'raw')
random.seed(7)


def env(t, attack, decay):
    """Envolvente: sobe em [attack] segundos e desce exponencialmente."""
    if t < attack:
        return t / attack
    return math.exp(-(t - attack) / decay)


def lowpass(samples, alpha):
    out, y = [], 0.0
    for x in samples:
        y += alpha * (x - y)
        out.append(y)
    return out


def noise(n):
    return [random.uniform(-1, 1) for _ in range(n)]


def tone(freq, dur, attack=0.005, decay=0.15, vol=0.6):
    n = int(dur * RATE)
    return [vol * env(i / RATE, attack, decay) * math.sin(2 * math.pi * freq * i / RATE) for i in range(n)]


def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [sum(t[i] for t in tracks if i < len(t)) for i in range(n)]


def concat(*parts, gap=0.0):
    out = []
    for p in parts:
        out += p + [0.0] * int(gap * RATE)
    return out


def write(name, samples):
    peak = max(1e-6, max(abs(s) for s in samples))
    scale = 0.85 / peak
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f'sfx_{name}.wav')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(struct.pack('<h', int(s * scale * 32767)) for s in samples))
    print(path, os.path.getsize(path))


def card():
    # carta a deslizar na mesa: ruído filtrado, curto
    n = int(0.16 * RATE)
    s = lowpass(noise(n), 0.25)
    return [s[i] * env(i / RATE, 0.02, 0.05) for i in range(n)]


def land():
    # terreno a assentar: baque grave
    return mix(tone(85, 0.22, 0.003, 0.07, 1.0), [x * 0.3 for x in card()[:800]])


def attack():
    # avanço: ruído a subir de tom
    n = int(0.32 * RATE)
    out, y = [], 0.0
    for i in range(n):
        t = i / RATE
        a = 0.05 + 0.5 * (t / 0.32)
        y += a * (random.uniform(-1, 1) - y)
        out.append(y * env(t, 0.12, 0.08))
    return out


def hit():
    # dano: impacto (ruído seco + grave)
    n = int(0.2 * RATE)
    s = lowpass(noise(n), 0.5)
    crack = [s[i] * env(i / RATE, 0.001, 0.03) for i in range(n)]
    return mix(crack, tone(60, 0.2, 0.002, 0.08, 0.9))


def death():
    # criatura que morre: "puf" descendente
    n = int(0.3 * RATE)
    out, y = [], 0.0
    for i in range(n):
        t = i / RATE
        a = 0.4 * (1 - t / 0.3) + 0.03
        y += a * (random.uniform(-1, 1) - y)
        out.append(y * env(t, 0.01, 0.1))
    return out


def gain():
    # ganhar vida: brilho
    return mix(tone(880, 0.45, 0.01, 0.18, 0.5), tone(1320, 0.45, 0.03, 0.15, 0.35))


def turn():
    # início de turno: sino suave
    return mix(tone(660, 0.7, 0.005, 0.3, 0.5), tone(990, 0.7, 0.005, 0.2, 0.25))


def win():
    notes = [523.25, 659.25, 783.99, 1046.5]
    return concat(*[tone(f, 0.16 if i < 3 else 0.6, 0.005, 0.12 if i < 3 else 0.35, 0.6) for i, f in enumerate(notes)])


def lose():
    notes = [392.0, 349.23, 311.13, 261.63]
    return concat(*[tone(f, 0.2 if i < 3 else 0.7, 0.01, 0.15 if i < 3 else 0.4, 0.5) for i, f in enumerate(notes)])


for name, fn in [('card', card), ('land', land), ('attack', attack), ('hit', hit), ('death', death),
                 ('gain', gain), ('turn', turn), ('win', win), ('lose', lose)]:
    write(name, fn())
