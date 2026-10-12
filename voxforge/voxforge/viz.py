"""Spectrogram PNG renderer (PIL + numpy only)."""
import numpy as np
from PIL import Image, ImageDraw
from . import dsp


def spectrogram_png(x, sr, path, fmax=8000, win=512, hop=128, f0=None, width_scale=1, title=None):
    w = np.hanning(win)
    n = 1 + (len(x) - win) // hop
    idx = np.arange(win)[None, :] + hop * np.arange(n)[:, None]
    S = np.abs(np.fft.rfft(x[idx] * w, 1024, axis=-1)).T
    f = np.fft.rfftfreq(1024, 1 / sr)
    S = S[f <= fmax]
    L = 20 * np.log10(S + 1e-6)
    L = np.clip((L - (L.max() - 70)) / 70, 0, 1)
    img = (255 * (1 - L[::-1] ** 0.9)).astype(np.uint8)
    im = Image.fromarray(img).convert("RGB")
    if width_scale != 1:
        im = im.resize((int(im.width * width_scale), im.height))
    if f0 is not None:
        d = ImageDraw.Draw(im)
        H = im.height
        for i, v in enumerate(f0):
            if v > 0:
                px = int(i * dsp.HOP / hop * width_scale)
                py = H - int(v / fmax * H)
                d.point((px, py), fill=(255, 0, 0))
    if title:
        ImageDraw.Draw(im).text((4, 2), title, fill=(0, 0, 160))
    im.save(path)
