"""Spanish phone inventory + parametric spectral models (formant cascade, noise bands)."""
import numpy as np
from . import dsp
from .dsp import SR, NCEP, FREQS

# ---------------------------------------------------------------- parametric
def _res_logmag(F, B, f=FREQS):
    r = np.exp(-np.pi * B / SR)
    th = 2 * np.pi * F / SR
    w = 2 * np.pi * f / SR
    z1 = np.exp(-1j * w)
    num = 1 - 2 * r * np.cos(th) + r * r
    den = 1 - 2 * r * np.cos(th) * z1 + r * r * z1 * z1
    return np.log(np.abs(num / den) + 1e-12)


def formant_logmag(F, B=None, zeros=(), tilt_db_oct=-3.0, f=FREQS):
    """Cascade-formant log-magnitude (natural log). F: list of Hz. zeros: [(Hz, bw)]."""
    F = list(F)
    if B is None:
        B = [60 + 0.06 * x for x in F]
    lm = np.zeros_like(f)
    for Fi, Bi in zip(F, B):
        lm += _res_logmag(Fi, Bi, f)
    # fixed higher poles (compensate for formants above F4 that we do not model)
    for Fi in (5200.0, 6600.0, 8000.0):
        lm += _res_logmag(Fi, 500.0, f)
    for Fz, Bz in zeros:
        lm -= _res_logmag(Fz, Bz, f)
    lm += tilt_db_oct / 8.686 * np.log2(np.maximum(f, 100.0) / 500.0)
    return lm


def formant_cep(F, B=None, zeros=(), tilt_db_oct=-3.0):
    c = dsp.logmag_to_cep(formant_logmag(F, B, zeros, tilt_db_oct)[None, :])[0]
    return c


def band_logmag(centre, width_oct=0.6, low_cut=0.0, slope_lo=18.0, slope_hi=-18.0, f=FREQS):
    """Flat-topped band spectrum (dB/oct skirts), natural-log units."""
    ff = np.maximum(f, 50.0)
    d = np.log2(ff / centre)
    db = np.where(d < -width_oct, slope_lo * (d + width_oct),
                  np.where(d > width_oct, slope_hi * (d - width_oct), 0.0))
    if low_cut > 0:
        db = np.where(ff < low_cut, db - 24 * np.log2(low_cut / ff), db)
    return db / 8.686


def band_cep(centre, **kw):
    c = dsp.logmag_to_cep(band_logmag(centre, **kw)[None, :])[0]
    c[24:] = 0
    return c


# ----------------------------------------------------------------- inventory
# Male reference formants (Hz). Scaled per speaker by profile["formant_scale"].
VOWEL_F = {
    "a": (730, 1250, 2550, 3500),
    "e": (500, 1850, 2550, 3500),
    "i": (290, 2200, 3050, 3700),
    "o": (510, 960, 2500, 3500),
    "u": (320, 800, 2400, 3450),
}
# consonant formant targets (F1..F4) and optional nasal zero
SONOR = {
    "j": dict(F=(280, 2150, 3050, 3700), dur=55, gain=-3),
    "w": dict(F=(300, 750, 2300, 3400), dur=55, gain=-3),
    "m": dict(F=(260, 1100, 2200, 3300), zeros=[(900, 150)], dur=70, gain=-9),
    "n": dict(F=(260, 1500, 2400, 3300), zeros=[(1500, 200)], dur=62, gain=-9),
    "ɲ": dict(F=(260, 2050, 2900, 3500), zeros=[(2200, 250)], dur=75, gain=-10),
    "ŋ": dict(F=(260, 1300, 2300, 3300), zeros=[(1400, 200)], dur=62, gain=-10),
    "l": dict(F=(370, 1250, 2600, 3500), zeros=[(1900, 300)], dur=62, gain=-6),
    "ɾ": dict(F=(420, 1450, 2400, 3400), dur=26, gain=-8),
    "r": dict(F=(430, 1400, 2400, 3400), dur=95, gain=-7),
    "ʝ": dict(F=(270, 2250, 3000, 3600), dur=65, gain=-6, noise=-26),
    "β": dict(F=(330, 1000, 2300, 3300), dur=50, gain=-11, noise=-24),
    "ð": dict(F=(330, 1650, 2500, 3400), dur=45, gain=-12, noise=-24),
    "ɣ": dict(F=(360, 1450, 2300, 3300), dur=45, gain=-12, noise=-24),
}
# stops: (F2 locus, burst centre Hz, burst dur ms, closure ms, voiced)
STOPS = {
    "p": dict(locus=900, burst=1200, bw=1.3, voiced=False, clos=62),
    "t": dict(locus=1750, burst=4800, bw=0.7, voiced=False, clos=58),
    "k": dict(locus=1700, burst=2300, bw=0.9, voiced=False, clos=62),
    "b": dict(locus=900, burst=1000, bw=1.3, voiced=True, clos=48),
    "d": dict(locus=1750, burst=4000, bw=0.8, voiced=True, clos=44),
    "g": dict(locus=1700, burst=2000, bw=0.9, voiced=True, clos=46),
}
FRIC = {
    "s": dict(centre=6200, width=0.5, dur=95, gain=0, voiced=False),
    "θ": dict(centre=6800, width=1.3, dur=90, gain=-10, voiced=False),
    "f": dict(centre=5000, width=2.0, dur=82, gain=-12, voiced=False),
    "x": dict(centre=2600, width=0.9, dur=88, gain=-4, voiced=False),
    "ʃ": dict(centre=3600, width=0.6, dur=100, gain=-2, voiced=False),
    "z": dict(centre=6200, width=0.5, dur=70, gain=-3, voiced=True),
}
VOWELS = tuple(VOWEL_F)
ALL = set(VOWELS) | set(SONOR) | set(STOPS) | set(FRIC) | {"tʃ", "_"}
