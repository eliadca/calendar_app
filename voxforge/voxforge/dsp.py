"""Core DSP helpers for VoxForge. Only depends on numpy + stdlib."""
import wave
import numpy as np

SR = 22050          # internal sampling rate
NFFT = 1024         # envelope FFT size
NCEP = 48           # cepstral coefficients kept per envelope (c0 = level)
HOP = 110           # samples per parameter frame (~5 ms @ 22.05 kHz)


# ----------------------------------------------------------------- wav io
def read_wav(path):
    with wave.open(str(path), "rb") as w:
        sr, n, ch, sw = w.getframerate(), w.getnframes(), w.getnchannels(), w.getsampwidth()
        raw = w.readframes(n)
    if sw == 2:
        x = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    elif sw == 4:
        x = np.frombuffer(raw, dtype="<i4").astype(np.float64) / 2147483648.0
    elif sw == 1:
        x = (np.frombuffer(raw, dtype=np.uint8).astype(np.float64) - 128) / 128.0
    else:
        raise ValueError("unsupported sample width %d" % sw)
    if ch > 1:
        x = x.reshape(-1, ch).mean(axis=1)
    return x, sr


def write_wav(path, x, sr=SR):
    y = np.clip(np.asarray(x), -1.0, 1.0)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(int(sr))
        w.writeframes((y * 32767).astype("<i2").tobytes())


def fftconv(a, b):
    n = len(a) + len(b) - 1
    m = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(a, m) * np.fft.rfft(b, m), m)[:n]


def resample(x, sr_in, sr_out):
    """Rational resampler with a Kaiser windowed-sinc low-pass."""
    if sr_in == sr_out:
        return np.asarray(x, dtype=np.float64)
    g = int(np.gcd(int(sr_in), int(sr_out)))
    up, down = int(sr_out) // g, int(sr_in) // g
    cutoff = 0.46 / max(up, down)                 # relative to the upsampled rate
    half = 16 * max(up, down)
    n = np.arange(-half, half + 1)
    h = 2 * cutoff * np.sinc(2 * cutoff * n) * np.kaiser(len(n), 8.0) * up
    z = np.zeros(len(x) * up)
    z[::up] = x
    y = fftconv(z, h)[half:half + len(z)]
    return y[::down]


# -------------------------------------------------------- cepstral envelopes
_k = np.arange(NFFT // 2 + 1)
_n = np.arange(NCEP)
# logmag[k] = c0 + 2 * sum_n c_n cos(2 pi n k / NFFT)
_BASIS = 2.0 * np.cos(2 * np.pi * np.outer(_k, _n) / NFFT)
_BASIS[:, 0] = 1.0
FREQS = _k * SR / NFFT


def logmag_to_cep(logmag):
    """logmag: (..., NFFT/2+1) natural-log magnitude -> (..., NCEP) cepstrum."""
    full = np.concatenate([logmag, logmag[..., -2:0:-1]], axis=-1)
    c = np.fft.ifft(full, axis=-1).real
    return c[..., :NCEP]


def cep_to_logmag(cep):
    return cep @ _BASIS.T


def true_envelope(logmag, iters=12):
    """Iterative 'true envelope' (Imai/Röbel): envelope hugs the harmonic peaks."""
    env = logmag.copy()
    cep = None
    for _ in range(iters):
        cep = logmag_to_cep(env)
        smooth = cep_to_logmag(cep)
        env = np.maximum(logmag, smooth)
    return cep


def minphase_ir(cep, length):
    """Minimum-phase impulse response whose log-magnitude is cep_to_logmag(cep). Batched."""
    cep = np.atleast_2d(cep)
    fold = np.zeros((cep.shape[0], NFFT))
    fold[:, 0] = cep[:, 0]
    fold[:, 1:NCEP] = 2.0 * cep[:, 1:]
    H = np.exp(np.fft.fft(fold, axis=-1))
    h = np.fft.ifft(H, axis=-1).real[:, :length]
    return h


def hz_to_mel(f):
    return 2595.0 * np.log10(1 + np.asarray(f) / 700.0)


def mel_filterbank(n_mel=40, nfft=NFFT, sr=SR, fmax=10000.0):
    mels = np.linspace(0, hz_to_mel(fmax), n_mel + 2)
    hz = 700 * (10 ** (mels / 2595.0) - 1)
    bins = np.fft.rfftfreq(nfft, 1.0 / sr)
    fb = np.zeros((n_mel, len(bins)))
    for i in range(n_mel):
        l, c, r = hz[i], hz[i + 1], hz[i + 2]
        fb[i] = np.clip(np.minimum((bins - l) / (c - l), (r - bins) / (r - c)), 0, None)
    return fb


def stft_logmel(x, n_mel=40, win=1024, hop=256):
    w = np.hanning(win)
    n = 1 + max(0, (len(x) - win) // hop)
    idx = np.arange(win)[None, :] + hop * np.arange(n)[:, None]
    S = np.abs(np.fft.rfft(x[idx] * w, NFFT, axis=-1)) ** 2
    return np.log(S @ mel_filterbank(n_mel).T + 1e-10)
