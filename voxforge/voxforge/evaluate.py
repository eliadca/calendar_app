"""Objective evaluation: copy-synthesis fidelity and speaker-similarity metrics."""
import numpy as np
from . import dsp, analyze
from .dsp import SR, HOP


def _align_gain(ref, test):
    g = np.sqrt((ref ** 2).sum() / ((test ** 2).sum() + 1e-12))
    return test * g


def mel_distance(ref, test, n_mel=40):
    """RMS log-mel difference (dB) over frames where the reference is active. Also returns per-band mean bias."""
    n = min(len(ref), len(test))
    ref, test = ref[:n], _align_gain(ref[:n], test[:n])
    A = stft_db(ref, n_mel)
    B = stft_db(test, n_mel)
    act = A.mean(1) > A.mean(1).max() - 45
    d = (A - B)[act]
    return float(np.sqrt((d ** 2).mean())), d.mean(0)


def stft_db(x, n_mel=40):
    return dsp.stft_logmel(x, n_mel) * 4.343         # 10*log10 of power


def f0_error(ref, test):
    f_r, c_r, _ = analyze.yin_f0(ref)
    f_t, c_t, _ = analyze.yin_f0(test)
    n = min(len(f_r), len(f_t))
    both = (f_r[:n] > 0) & (f_t[:n] > 0)
    if both.sum() < 10:
        return None
    cents = 1200 * np.log2(f_t[:n][both] / f_r[:n][both])
    vu = (f_r[:n] > 0) == (f_t[:n] > 0)
    return dict(rmse_cents=float(np.sqrt((cents ** 2).mean())), median_abs_cents=float(np.median(np.abs(cents))),
                voicing_agreement=float(vu.mean()), frames=int(both.sum()))


def band_levels(x):
    S = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    f = np.fft.rfftfreq(len(x), 1 / SR)
    edges = [(0, 150), (150, 400), (400, 1000), (1000, 2500), (2500, 5000), (5000, 8000), (8000, 11000)]
    out = []
    for a, b in edges:
        m = (f >= a) & (f < b)
        out.append(10 * np.log10(S[m].sum() + 1e-20))
    out = np.array(out)
    return out - out.max()


def speaker_stats(x):
    """Compact speaker descriptor for similarity scoring."""
    f0, clar, rms = analyze.yin_f0(x)
    v = f0 > 0
    st = 12 * np.log2(f0[v] / 100.0)
    fr = analyze.analyze_frames(x)
    loud = v & (rms > 0.3 * np.percentile(rms[v], 90))
    ltas = np.mean(fr["cep_h"][loud], axis=0)
    return dict(f0_median=float(np.median(f0[v])), f0_sd_st=float(np.std(st)), clarity=float(np.median(clar[v])),
                voiced_ratio=float(v.mean()), ltas=ltas, bands=band_levels(x))


def ltas_distance(a, b, fmax=6000):
    la = dsp.cep_to_logmag(a[None, :])[0] * 8.686
    lb = dsp.cep_to_logmag(b[None, :])[0] * 8.686
    m = (dsp.FREQS > 80) & (dsp.FREQS < fmax)
    d = la[m] - lb[m]
    d = d - d.mean()                                   # level-free
    return float(np.sqrt((d ** 2).mean()))
