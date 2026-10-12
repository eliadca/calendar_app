"""Analysis of a reference recording -> frame tracks + a tiny speaker profile."""
import json
import numpy as np
from . import dsp
from .dsp import SR, HOP, NFFT, NCEP

# ------------------------------------------------------------------ pitch
def yin_f0(x, sr=SR, hop=HOP, fmin=60.0, fmax=420.0, thresh=0.18):
    """YIN pitch tracker (FFT difference function) + octave-error repair.
    Returns f0 (0 = unvoiced), clarity (1 - cmnd), rms per frame."""
    win = int(sr / fmin * 2.2)
    tau_max = int(sr / fmin) + 1
    tau_min = int(sr / fmax)
    nfr = 1 + (len(x) - win) // hop
    pad = win // 2
    xp = np.concatenate([np.zeros(pad), x, np.zeros(win)])
    f0 = np.zeros(nfr)
    clar = np.zeros(nfr)
    rms = np.zeros(nfr)
    m = 1 << (2 * win - 1).bit_length()
    for i in range(nfr):
        seg = xp[i * hop:i * hop + win]
        rms[i] = np.sqrt(np.mean(seg ** 2))
        if rms[i] < 3e-3:
            continue
        w = win - tau_max
        a = seg[:w]
        fa = np.fft.rfft(seg, m)
        fb = np.fft.rfft(a, m)
        corr = np.fft.irfft(fa * np.conj(fb), m)[:tau_max]
        cs = np.concatenate([[0], np.cumsum(seg ** 2)])
        e0 = cs[w]
        en = cs[w + np.arange(tau_max)] - cs[np.arange(tau_max)]
        d = e0 + en - 2 * corr
        d[0] = 0
        cm = np.ones(tau_max)
        cm[1:] = d[1:] * np.arange(1, tau_max) / (np.cumsum(d[1:]) + 1e-12)
        t = tau_min
        pick = -1
        while t < tau_max - 1:
            if cm[t] < thresh:
                while t + 1 < tau_max - 1 and cm[t + 1] < cm[t]:
                    t += 1
                pick = t
                break
            t += 1
        if pick < 0:
            seg_cm = cm[tau_min:tau_max - 1]
            pick = tau_min + int(np.argmin(seg_cm))
            if cm[pick] > 0.4:
                continue
        t = pick
        if 1 <= t < tau_max - 1:
            s0, s1, s2 = cm[t - 1], cm[t], cm[t + 1]
            den = s0 - 2 * s1 + s2
            t = t + (0.5 * (s0 - s2) / den if abs(den) > 1e-12 else 0.0)
        f0[i] = sr / t
        clar[i] = 1 - cm[pick]
    f0 = _repair_octaves(f0)
    return f0, clar, rms


def _repair_octaves(f0):
    out = f0.copy()
    v = np.where(f0 > 0)[0]
    if len(v) < 5:
        return out
    ref = np.median(f0[v])
    # local median filter on voiced runs
    for _ in range(2):
        for i in v:
            lo, hi = max(0, i - 6), min(len(out), i + 7)
            nb = out[lo:hi]
            nb = nb[nb > 0]
            if len(nb) < 3:
                continue
            med = np.median(nb)
            r = out[i] / med
            if r > 1.8:
                out[i] /= 2
            elif r < 0.56:
                out[i] *= 2
    out[(out > 0) & ((out < 0.5 * ref) | (out > 2.2 * ref))] = 0
    return out


# --------------------------------------------------------------- envelopes
def analyze_frames(x, sr=SR, hop=HOP):
    """Per-frame: f0, voicing, harmonic-amplitude envelope (cep_h), noise-gain envelope (cep_n), rms."""
    f0, clar, rms = yin_f0(x, sr, hop)
    n = len(f0)
    cep_h = np.zeros((n, NCEP))
    cep_n = np.zeros((n, NCEP))
    pad = 1024
    xp = np.concatenate([np.zeros(pad), x, np.zeros(pad)])
    voiced = f0 > 0
    for i in range(n):
        centre = i * hop + pad
        if voiced[i]:
            L = int(np.clip(3.0 * sr / f0[i], 256, 1000))
        else:
            L = 440
        w = np.hanning(L)
        seg = xp[centre - L // 2:centre - L // 2 + L] * w
        X = np.abs(np.fft.rfft(seg, NFFT)) + 1e-9
        lm = np.log(X)
        if voiced[i]:
            cep_h[i] = dsp.true_envelope(lm[None, :], 10)[0]
            cep_h[i, 0] -= np.log(w.sum() / 2)                      # -> sinusoid amplitude units
            cep_n[i] = dsp.logmag_to_cep(lm[None, :])[0] + 0.2886      # smooth + Rayleigh bias
            cep_n[i, 0] -= np.log(np.sqrt((w ** 2).sum()))
        else:
            c = dsp.logmag_to_cep(lm[None, :])[0]
            c[0] += 0.2886 - np.log(np.sqrt((w ** 2).sum()))
            c[24:] = 0
            cep_n[i] = c
            cep_h[i] = c
    return dict(f0=f0, clarity=clar, rms=rms, cep_h=cep_h, cep_n=cep_n)


# ------------------------------------------------------------ profile build
def syllable_rate(x, sr=SR):
    """Estimate syllables/second from the 300-3000 Hz energy envelope."""
    hop = 110
    w = 440
    n = 1 + (len(x) - w) // hop
    idx = np.arange(w)[None, :] + hop * np.arange(n)[:, None]
    S = np.abs(np.fft.rfft(x[idx] * np.hanning(w), 512, axis=-1))
    fr = np.fft.rfftfreq(512, 1 / sr)
    e = np.log((S[:, (fr > 300) & (fr < 3000)] ** 2).sum(1) + 1e-9)
    k = np.ones(9) / 9
    e = np.convolve(e, k, "same")
    active = e > (e.max() - 7.0)
    peaks = 0
    for i in range(8, n - 8):
        if not active[i] or e[i] != e[i - 4:i + 5].max():
            continue
        valley = min(e[i - 8:i + 1].min(), e[i:i + 9].min())
        if e[i] - valley > 0.9:
            peaks += 1
    speech_s = active.sum() * hop / sr
    return peaks / max(speech_s, 1e-3), peaks, speech_s


BANDS = [500, 800, 1200, 1700, 2300, 3000, 4000, 5200]
LIFT_FROM = 10      # cepstral index above which "formant structure" lives (below: tilt / boom)


def formant_contrast(ceps):
    """Mean peak-valley contrast (dB std of fine structure) of cepstral envelopes between 450 and 5000 Hz."""
    ceps = np.atleast_2d(ceps)
    fine = ceps.copy()
    fine[:, :LIFT_FROM] = 0.0
    lm = dsp.cep_to_logmag(fine) * 8.686
    m = (dsp.FREQS > 450) & (dsp.FREQS < 5000)
    return float(np.std(lm[:, m], axis=1).mean())


def band_profile(cep):
    """Level-free spectral shape above the first formant region: 7 band means (dB, mean removed)."""
    lm = dsp.cep_to_logmag(np.atleast_2d(cep)) * 8.686
    out = np.stack([lm[:, (dsp.FREQS >= lo) & (dsp.FREQS < hi)].mean(1) for lo, hi in zip(BANDS[:-1], BANDS[1:])], 1)
    return out - out.mean(1, keepdims=True)


def build_profile(x, sr_in, verbose=False):
    """Learn a compact speaker profile from a (mono) recording."""
    from . import phones
    x = dsp.resample(x, sr_in, SR)
    x = x / (np.abs(x).max() + 1e-9) * 0.9
    fr = analyze_frames(x)
    f0, rms, clar = fr["f0"], fr["rms"], fr["clarity"]
    voiced = f0 > 0
    loud = rms > 0.30 * np.percentile(rms[voiced], 90)
    vo = np.where(voiced & loud & (clar > 0.7))[0]

    # ---- pitch statistics
    st = 12 * np.log2(f0[voiced] / 100.0)
    f0_med = float(np.median(f0[voiced]))
    f0_sd_st = float(np.std(st))
    f0_lo, f0_hi = [float(np.percentile(f0[voiced], p)) for p in (5, 95)]
    d = np.abs(np.diff(f0[voiced]))
    jitter = float(np.median(d[d < 0.05 * f0_med]) / f0_med)

    # ---- steady vowel-like frames
    steady = []
    for i in vo:
        if 3 <= i < len(f0) - 3 and np.abs(fr["cep_h"][i + 3, 1:12] - fr["cep_h"][i - 3, 1:12]).mean() < 0.35:
            steady.append(i)
    steady = np.array(steady)
    feats = band_profile(fr["cep_h"][steady])

    # ---- vowel discovery: k-means seeded with the textbook Spanish vowels' band profiles
    seeds = np.array([band_profile(phones.formant_cep(phones.VOWEL_F[v]))[0] for v in phones.VOWELS])
    cent = seeds.copy()
    for _ in range(30):
        lab = ((feats[:, None, :] - cent[None]) ** 2).sum(-1).argmin(1)
        for k in range(5):
            if (lab == k).sum() >= 5:
                cent[k] = feats[lab == k].mean(0)
    dist = ((feats[:, None, :] - cent[None]) ** 2).sum(-1)
    lab = dist.argmin(1)
    protos, counts = {}, {}
    for k, name in enumerate(phones.VOWELS):
        mem = np.where(lab == k)[0]
        counts[name] = int(len(mem))
        if len(mem) == 0:
            continue
        best = mem[np.argsort(dist[mem, k])][:max(8, len(mem) // 3)]
        protos[name] = np.median(fr["cep_h"][steady[best]], axis=0)
    # fill missing vowels from the closest textbook-shape later (handled by synth via residual)
    grand = np.mean([protos[v] for v in protos], axis=0)
    sep_obs = float(np.mean([np.abs(band_profile(protos[v])[0] - band_profile(grand)[0]).mean() for v in protos]))
    sep_nom = float(np.mean([np.abs(seeds[i] - seeds.mean(0)).mean() for i in range(5)]))

    # ---- formant contrast: real single frames vs. the (blurrier) averaged prototypes
    c_real = formant_contrast(fr["cep_h"][steady])
    c_proto = formant_contrast(np.array(list(protos.values())))
    sharpen = float(np.clip(c_real / max(c_proto, 1e-6), 1.0, 3.0))

    # ---- speaker EQ residual: real vowel prototypes minus parametric model of the same vowels
    resid = []
    for name in protos:
        resid.append(protos[name] - phones.formant_cep(phones.VOWEL_F[name]))
    residual = np.mean(resid, axis=0)
    residual[40:] = 0

    # ---- unvoiced fricative noise: cluster by spectral centroid
    unv = np.where(~voiced & (rms > 0.015))[0]
    fric = {}
    if len(unv) >= 8:
        cents = []
        for i in unv:
            p = np.exp(2 * dsp.cep_to_logmag(fr["cep_n"][i]))
            cents.append((p * dsp.FREQS).sum() / p.sum())
        cents = np.array(cents)
        c_hi, c_lo = np.percentile(cents, 85), np.percentile(cents, 25)
        for _ in range(12):
            to_hi = np.abs(cents - c_hi) < np.abs(cents - c_lo)
            if to_hi.any():
                c_hi = cents[to_hi].mean()
            if (~to_hi).any():
                c_lo = cents[~to_hi].mean()
        hi = unv[to_hi]
        lvl = np.array([fr["cep_n"][i, 0] for i in hi])
        hi = hi[lvl >= np.percentile(lvl, 40)]
        fric["s"] = dict(centroid=float(c_hi), n=int(len(hi)), cep=np.median(fr["cep_n"][hi], axis=0).tolist())

    rate, peaks, speech_s = syllable_rate(x)
    profile = dict(
        version=2, sr=SR,
        f0=dict(median=f0_med, sd_semitones=f0_sd_st, p5=f0_lo, p95=f0_hi, jitter=jitter),
        vowels={k: v.tolist() for k, v in protos.items()}, vowel_counts=counts,
        residual=residual.tolist(), fricatives=fric, sharpen=sharpen, contrast_real_db=c_real, contrast_proto_db=c_proto,
        clarity=float(np.median(clar[vo])),
        syll_rate=float(rate), level_db=float(20 * np.log10(np.percentile(rms[voiced], 75))),
        stats=dict(duration_s=len(x) / SR, voiced_frames=int(voiced.sum()), steady_frames=int(len(steady)),
                   syllable_peaks=int(peaks), speech_s=float(speech_s),
                   vowel_separation_observed_vs_textbook=sep_obs / sep_nom),
    )
    if verbose:
        print(json.dumps({k: v for k, v in profile.items() if k not in ("vowels", "residual", "fricatives")}, indent=1))
        for k, v in protos.items():
            print("vowel", k, "n=%d" % counts[k], "band-profile dB:", np.round(band_profile(v)[0]).astype(int))
        print("textbook band-profiles:")
        for k, v in zip(phones.VOWELS, seeds):
            print("  ", k, np.round(v).astype(int))
        for k, v in fric.items():
            print("fric", k, "centroid=%.0f Hz" % v["centroid"], "n=%d" % v["n"])
    return profile, x, fr


def save_profile(profile, path):
    with open(path, "w") as f:
        json.dump(profile, f, separators=(",", ":"), default=float)


def load_profile(path):
    with open(path) as f:
        return json.load(f)
