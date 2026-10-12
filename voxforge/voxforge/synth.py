"""VoxForge synthesis engine: text -> phone plan -> parameter tracks -> waveform.

Harmonic part : minimum-phase impulse responses of the speaker's spectral envelope,
                overlap-added at pitch epochs (pitch-synchronous, fractional-delay exact).
Noise part    : independent white-noise frames shaped by the envelope in the STFT domain.
Everything speaker specific comes from a ~10 kB profile learned from the reference wav.
"""
import numpy as np
from . import dsp, phones as ph, g2p_es
from .dsp import SR, HOP, NCEP, NFFT
from .analyze import LIFT_FROM as analyze_lift

DT = HOP / SR
IR_LEN = 640


def _db(x):
    return x / 8.686


def _smooth(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


class Voice:
    def __init__(self, profile=None, tempo=None, seseo=True, seed=1, aspiration=None, expressiveness=1.0,
                 clarity=1.25, sharpen=1.0, articulation=0.6):
        self.profile = profile
        self.rng = np.random.default_rng(seed)
        self.seseo = seseo
        self.expr = expressiveness
        f0 = (profile or {}).get("f0", dict(median=118.0, sd_semitones=3.5, jitter=0.004))
        self.f0_med = f0["median"]
        self.f0_sd = float(np.clip(f0["sd_semitones"], 2.5, 5.0))
        self.jitter = 0.0025        # real micro-jitter; the profile's frame-to-frame value is dominated by intonation
        self.tempo = 1.0 if tempo is None else tempo
        self._auto_tempo = tempo is None and bool(profile)
        self.asp = 0.12 if aspiration is None else aspiration
        self.res = np.array(profile["residual"]) if profile else np.zeros(NCEP)
        self.level_db = (profile or {}).get("level_db", -16.0)
        # --- vowel prototypes (real envelopes when available), with clarity expansion
        self.vow = {}
        for v in ph.VOWELS:
            if profile and v in profile["vowels"]:
                self.vow[v] = np.array(profile["vowels"][v])
            else:
                self.vow[v] = ph.formant_cep(ph.VOWEL_F[v]) + self.res
        # casual speech under-articulates (e.g. /a/ and /o/ collapse): pull the vowel's spectral shape toward the
        # textbook vowel, but keep level (c0) and tilt (c1) - i.e. the speaker's timbre - from the real recording
        for v in ph.VOWELS:
            par = ph.formant_cep(ph.VOWEL_F[v]) + self.res
            self.vow[v][2:] = (1 - articulation) * self.vow[v][2:] + articulation * par[2:]
        # undo averaging blur: lift the fine (formant) structure of the prototypes to the real per-frame contrast
        self.sharpen = float((profile or {}).get("sharpen", 1.0)) * sharpen
        for v in ph.VOWELS:
            self.vow[v][analyze_lift:] *= self.sharpen
        grand = np.mean([self.vow[v] for v in ph.VOWELS], axis=0)
        for v in ph.VOWELS:
            c = grand + clarity * (self.vow[v] - grand)
            c[0] = self.vow[v][0]                 # keep each vowel's own level
            self.vow[v] = c
        self.grand = np.mean([self.vow[v] for v in ph.VOWELS], axis=0)
        # --- noise references
        if profile and profile.get("fricatives", {}).get("s"):
            self.s_cep = np.array(profile["fricatives"]["s"]["cep"])
        else:
            self.s_cep = ph.band_cep(6200, width_oct=0.5)
            self.s_cep[0] += np.log(0.02) - dsp.cep_to_logmag(self.s_cep[None, :]).max()
        self.s_peak = float(dsp.cep_to_logmag(self.s_cep[None, :]).max())
        ff = dsp.FREQS
        hf_db = -10.0 + 10.0 * _smooth((ff - 1500.0) / 4500.0)
        self.hf_cep = dsp.logmag_to_cep(_db(hf_db)[None, :])[0]
        self.hf_cep[0] = 0.0
        self.cache = {}
        if self._auto_tempo:
            self.calibrate_tempo(profile["syll_rate"])

    CAL_TEXT = ("El veloz murciélago hindú comía feliz cardillo y kiwi, mientras la cigüeña tocaba el saxofón. "
                "Tres tristes tigres tragaban trigo en un trigal.")

    def calibrate_tempo(self, target_rate):
        """Analysis-by-synthesis: choose the tempo whose measured syllable rate equals the speaker's
        (same estimator on both signals, so its bias cancels)."""
        from .analyze import syllable_rate
        self.tempo = 1.0
        measured = syllable_rate(self.synthesize(self.CAL_TEXT, normalize=False))[0]
        self.tempo = float(np.clip(target_rate / max(measured, 1e-3), 0.75, 1.5))
        return self.tempo

    # ------------------------------------------------------------- spectra
    def par(self, F, zeros=(), gain_db=0.0):
        c = ph.formant_cep(F, None, zeros) + self.res
        c[0] += _db(gain_db)
        return c

    def noise_of(self, ch, rel_db):
        """Noise-gain cepstrum for aspiration-like noise riding on a harmonic envelope."""
        c = ch + self.hf_cep
        c[0] = ch[0] + np.log(self.asp) + _db(rel_db) + 0.5 * np.log(SR / (4 * self.f0_med))
        return c

    def band(self, centre, width, db):
        key = ("band", centre, width, db)
        if key not in self.cache:
            c = ph.band_cep(centre, width_oct=width)
            c = c.copy()
            c[0] += self.s_peak + _db(db) - dsp.cep_to_logmag(c[None, :]).max()
            self.cache[key] = c
        return self.cache[key]

    # --------------------------------------------------------------- plan
    def plan(self, text):
        """Return list of segments (dicts) + phrase descriptors."""
        toks = g2p_es.g2p(text, self.seseo)
        segs, phrases = [], []
        cur = dict(start=None, kind=".", nuclei=[])
        segs.append(self._pause(0.12))
        words_phones = []
        for ti, t in enumerate(toks):
            if t["type"] == "punct":
                if segs and segs[-1]["kind"] != "P":
                    if cur["start"] is not None:
                        cur["kind"] = t["p"]
                        phrases.append(cur)
                        cur = dict(start=None, kind=".", nuclei=[])
                    segs.append(self._pause({",": 0.26, ";": 0.32, ":": 0.32, ".": 0.50, "?": 0.52, "!": 0.52}[t["p"]]))
                continue
            func = t["stressed_syl"] < 0
            last_syl = t["nsyl"] - 1
            P = t["phones"]
            for k, d in enumerate(P):
                prev_p = P[k - 1]["p"] if k > 0 else ("_" if True else None)
                next_p = P[k + 1]["p"] if k + 1 < len(P) else "_"
                new = self._phone_segs(d, prev_p, next_p, func)
                for s in new:
                    s["word"] = t["word"]
                    s["syl_last"] = d["syl"] == last_syl
                    if cur["start"] is None:
                        cur["start"] = len(segs)
                    segs.append(s)
                    if s["kind"] == "V":
                        cur["nuclei"].append(len(segs) - 1)
        if cur["start"] is not None:
            phrases.append(cur)
        segs.append(self._pause(0.18))
        self._fill_obstruent_envelopes(segs)
        self._durations(segs, phrases)
        return segs, phrases

    def _pause(self, d):
        z = np.zeros(NCEP)
        return dict(kind="P", ph="_", dur=d, ch=z, cn=z, gh=0.0, gn=0.0)

    def _phone_segs(self, d, prev_p, next_p, func):
        p, stress = d["p"], d["stress"]
        out = []
        if p in ph.VOWELS:
            dur = 0.090
            dur *= 1.22 if stress else (0.85 if func else 0.88)
            ch = self.vow[p].copy()
            out.append(dict(kind="V", ph=p, dur=dur, ch=ch, cn=self.noise_of(ch, 0.0), gh=1.0, gn=1.0, stress=stress))
        elif p in ph.SONOR:
            s = ph.SONOR[p]
            ch = self.par(s["F"], s.get("zeros", ()), s["gain"])
            gh = 1.0
            nz = s.get("noise")
            cn = self.noise_of(ch, nz + 20 * np.log10(1 / self.asp) if nz else -80.0) if nz else np.zeros(NCEP)
            kind = "S"
            seg = dict(kind=kind, ph=p, dur=s["dur"] / 1000.0 * (0.8 if func else 1.0), ch=ch, cn=cn, gh=gh,
                       gn=1.0 if nz else 0.0, stress=False)
            if p == "ɾ":
                seg["gh"] = 0.5
            if p == "r":
                seg["trill"] = 28.0
            out.append(seg)
        elif p in ph.STOPS:
            s = ph.STOPS[p]
            voiced = s["voiced"]
            hard_voiced_after_pause = voiced and prev_p in ("_", "m", "n", "ɲ", "ŋ", "l")
            clos = s["clos"] / 1000.0 * (0.85 if func else 1.0)
            z = np.zeros(NCEP)
            out.append(dict(kind="C", ph=p, dur=clos, ch=None, cn=z, gh=0.07 if voiced else 0.0, gn=0.0,
                            locus=s["locus"], stop=p))
            bc = {"i": 3200, "e": 2800, "a": 1800, "o": 1200, "u": 1000}.get(next_p, s["burst"])
            centre = bc if p in ("k", "g") else s["burst"]
            rel = {"p": -13, "t": -5, "k": -7, "b": -19, "d": -14, "g": -16}[p]
            out.append(dict(kind="B", ph=p, dur=0.011 if p != "k" else 0.014, ch=None, cn=self.band(centre, s["bw"], rel),
                            gh=0.0, gn=1.0))
            if not voiced:
                out.append(dict(kind="A", ph=p, dur=0.016 if p != "t" else 0.012, ch=None,
                                cn=self.band(2200, 1.3, -17), gh=0.0, gn=1.0))
        elif p == "tʃ":
            z = np.zeros(NCEP)
            out.append(dict(kind="C", ph=p, dur=0.048, ch=None, cn=z, gh=0.0, gn=0.0, locus=2000, stop="t"))
            out.append(dict(kind="F", ph=p, dur=0.085, ch=None, cn=self.band(3700, 0.6, -2), gh=0.0, gn=1.0))
        elif p in ph.FRIC:
            s = ph.FRIC[p]
            if p == "s":
                cn = self.s_cep.copy()
            else:
                cn = self.band(s["centre"], s["width"], s["gain"])
            out.append(dict(kind="F", ph=p, dur=s["dur"] / 1000.0 * (0.8 if func else 1.0), ch=None, cn=cn, gh=0.0,
                            gn=1.0))
        else:
            return []
        return out

    def _fill_obstruent_envelopes(self, segs):
        """Obstruents carry no harmonic envelope of their own: they inherit the neighbours' (formants glide through)."""
        n = len(segs)
        for i, s in enumerate(segs):
            if s["ch"] is not None:
                continue
            L = next((segs[j]["ch"] for j in range(i - 1, -1, -1) if segs[j]["ch"] is not None and segs[j]["kind"] in ("V", "S")), None)
            R = next((segs[j]["ch"] for j in range(i + 1, n) if segs[j]["ch"] is not None and segs[j]["kind"] in ("V", "S")), None)
            base = self.grand
            L = base if L is None else L
            R = base if R is None else R
            ch = 0.5 * (L + R)
            if s["kind"] == "C" and "locus" in s:
                loc = ph.formant_cep((300, s["locus"], 2400, 3400)) + self.res
                w = 0.35 if s["stop"] in ("k", "g") else 0.6
                nxt = R
                ch = (1 - w) * nxt + w * (0.5 * loc + 0.5 * L if s["stop"] not in ("p", "b") else 0.5 * loc + 0.5 * R)
            s["ch"] = ch

    def _durations(self, segs, phrases):
        for s in segs:
            s["dur"] = s["dur"] / self.tempo if s["kind"] != "P" else s["dur"]
        # phrase-final lengthening
        for pr in phrases:
            idx = [i for i in range(pr["start"], len(segs)) if segs[i]["kind"] != "P"]
            if not idx:
                continue
            end = idx[0]
            for i in idx:
                if segs[i]["kind"] == "P":
                    break
                end = i
            last_word = segs[end].get("word")
            for i in range(end, pr["start"] - 1, -1):
                if segs[i].get("word") != last_word:
                    break
                if segs[i].get("syl_last"):
                    segs[i]["dur"] *= 1.28 if segs[i]["kind"] in ("V", "S") else 1.1

    # ------------------------------------------------------------ prosody
    def f0_contour(self, segs, phrases, t_start, n_frames):
        f0_st = np.zeros(n_frames)
        ts = np.arange(n_frames) * DT
        amp = 3.0 * np.clip(self.f0_sd / 4.2, 0.7, 1.3) * self.expr
        pts = []        # (time, st) breakpoints globally
        for pr in phrases:
            nuc = pr["nuclei"]
            if not nuc:
                continue
            t0 = t_start[nuc[0]]
            t1 = t_start[nuc[-1]] + segs[nuc[-1]]["dur"]
            span = max(t1 - t0, 1e-3)
            for j, si in enumerate(nuc):
                s = segs[si]
                tc = t_start[si] + 0.45 * s["dur"]
                decl = 1.8 - 3.6 * (tc - t0) / span
                st = decl + (amp if s.get("stress") else -0.4 * self.expr)
                if j == 0:
                    st += 0.8 * self.expr
                pts.append((tc, st))
            last = segs[nuc[-1]]
            te = t_start[nuc[-1]] + last["dur"]
            decl_end = -1.8
            if pr["kind"] == "?":
                # Spanish questions: low on the last stressed syllable, then rise through the post-tonic syllables
                stressed = [j for j, si in enumerate(nuc) if segs[si].get("stress")]
                js = stressed[-1] if stressed else len(nuc) - 1
                t_lo = t_start[nuc[js]] + 0.5 * segs[nuc[js]]["dur"]
                top = decl_end + 6.0 * self.expr
                low = decl_end - 1.0
                pts = [p for p in pts if not (p[0] >= t_lo and p[0] <= te)]
                pts.append((t_lo, low))
                for j in range(js + 1, len(nuc)):
                    tj = t_start[nuc[j]] + 0.5 * segs[nuc[j]]["dur"]
                    pts.append((tj, low + (top - low) * (tj - t_lo) / max(te - t_lo, 1e-3)))
                pts.append((te - 0.01, top))
            elif pr["kind"] in (",", ";", ":"):
                pts.append((te - 0.02, decl_end + 2.2 * self.expr))
            elif pr["kind"] == "!":
                pts.append((te - 0.02, decl_end - 1.0))
            else:
                pts.append((te - 0.02, decl_end - 3.5 * self.expr))
        pts.sort()
        if not pts:
            return np.full(n_frames, self.f0_med)
        pt, ps = np.array([p[0] for p in pts]), np.array([p[1] for p in pts])
        # cosine interpolation between breakpoints
        idx = np.clip(np.searchsorted(pt, ts) - 1, 0, len(pt) - 2) if len(pt) > 1 else np.zeros(n_frames, int)
        if len(pt) > 1:
            w = np.clip((ts - pt[idx]) / np.maximum(pt[idx + 1] - pt[idx], 1e-6), 0, 1)
            w = 0.5 - 0.5 * np.cos(np.pi * w)
            f0_st = ps[idx] * (1 - w) + ps[idx + 1] * w
        else:
            f0_st[:] = ps[0]
        # gentle drift + smoothing
        drift = np.convolve(self.rng.standard_normal(n_frames + 200), np.ones(200) / 200, "same")[100:100 + n_frames]
        f0_st = f0_st + 3.0 * drift * self.expr
        k = np.hanning(9)
        k /= k.sum()
        f0_st = np.convolve(np.pad(f0_st, 4, mode="edge"), k, "valid")
        return self.f0_med * 2.0 ** (f0_st / 12.0)

    # ------------------------------------------------------------- tracks
    def tracks(self, segs, phrases):
        durs = np.array([s["dur"] for s in segs])
        t_start = np.concatenate([[0.0], np.cumsum(durs)[:-1]])
        n = int(np.ceil(durs.sum() / DT)) + 2
        ts = np.arange(n) * DT
        seg_idx = np.clip(np.searchsorted(np.cumsum(durs), ts, side="right"), 0, len(segs) - 1)
        ch = np.array([s["ch"] for s in segs])[seg_idx]
        cn = np.array([s["cn"] for s in segs])[seg_idx]
        gh = np.array([s["gh"] for s in segs])[seg_idx].astype(float)
        gn = np.array([s["gn"] for s in segs])[seg_idx].astype(float)
        # smooth the boundaries
        kinds = [s["kind"] for s in segs]
        for j in range(len(segs) - 1):
            a, b = segs[j], segs[j + 1]
            tb = t_start[j + 1]
            sharp = {"C", "B", "A", "P", "F"}
            we = min(0.040, 0.9 * min(a["dur"], b["dur"]))
            wg = 0.008 if (a["kind"] in sharp or b["kind"] in sharp) else min(0.022, 0.9 * min(a["dur"], b["dur"]))
            if a["kind"] == "B" or b["kind"] == "B":
                wg = 0.003
            if a["kind"] == "F" and b["kind"] in ("V", "S"):
                wg = 0.018
            for width, arrs in ((we, (ch,)), (wg, (gh, gn, cn))):
                lo, hi = int((tb - width / 2) / DT), int((tb + width / 2) / DT) + 1
                lo, hi = max(lo, 0), min(hi, n)
                if hi <= lo:
                    continue
                w = _smooth((ts[lo:hi] - (tb - width / 2)) / max(width, 1e-6))
                for arr in arrs:
                    A = {"ch": a["ch"], "cn": a["cn"], "gh": a["gh"], "gn": a["gn"]}
                    if arr is ch:
                        va, vb = a["ch"], b["ch"]
                    elif arr is cn:
                        va, vb = a["cn"], b["cn"]
                    elif arr is gh:
                        va, vb = a["gh"], b["gh"]
                    else:
                        va, vb = a["gn"], b["gn"]
                    if arr.ndim == 2:
                        arr[lo:hi] = va[None, :] * (1 - w[:, None]) + vb[None, :] * w[:, None]
                    else:
                        arr[lo:hi] = va * (1 - w) + vb * w
        # trills
        for j, s in enumerate(segs):
            if "trill" in s:
                lo, hi = int(t_start[j] / DT), min(n, int((t_start[j] + s["dur"]) / DT))
                tt = ts[lo:hi] - t_start[j]
                gh[lo:hi] *= 0.12 + 0.88 * (0.5 + 0.5 * np.cos(2 * np.pi * s["trill"] * tt)) ** 1.5
        f0 = self.f0_contour(segs, phrases, t_start, n)
        voiced = gh > 0.5
        if voiced.sum() > 20:            # centre the contour so the *voiced* median equals the speaker's median
            f0 = f0 * (self.f0_med / np.median(f0[voiced]))
        return dict(ch=ch, cn=cn, gh=gh, gn=gn, f0=f0, n=n, t_start=t_start)

    # ------------------------------------------------------------- render
    def render(self, T):
        n = T["n"]
        N = n * HOP + IR_LEN
        y = np.zeros(N)
        # ---- harmonic: pitch epochs
        f0 = T["f0"]
        f0_s = np.interp(np.arange(n * HOP) / HOP, np.arange(n), f0)
        phase = np.cumsum(f0_s / SR)
        ks = np.arange(1, int(phase[-1]) + 1)
        pos = np.searchsorted(phase, ks)
        pos = np.clip(pos, 1, len(phase) - 1)
        frac = (ks - phase[pos - 1]) / np.maximum(phase[pos] - phase[pos - 1], 1e-9)
        tp = (pos - 1) + frac                                  # fractional sample positions
        Tper = SR / np.interp(tp / HOP, np.arange(n), f0)
        tp = tp + self.rng.standard_normal(len(tp)) * self.jitter * Tper * 0.5
        fi = tp / HOP
        i0 = np.clip(np.floor(fi).astype(int), 0, n - 2)
        w = (fi - i0)[:, None]
        gh = T["gh"][i0] * (1 - w[:, 0]) + T["gh"][i0 + 1] * w[:, 0]
        keep = gh > 1e-3
        tp, Tper, i0, w, gh = tp[keep], Tper[keep], i0[keep], w[keep], gh[keep]
        cep = T["ch"][i0] * (1 - w) + T["ch"][i0 + 1] * w
        shimmer = 1.0 + 0.03 * self.rng.standard_normal(len(tp))
        fade = np.ones(IR_LEN)
        fade[-160:] = 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, 160))
        base = np.floor(tp).astype(int)
        delta = tp - base
        omega = 2 * np.pi * np.fft.fftfreq(NFFT)          # signed bin frequencies (rad/sample)
        for a in range(0, len(tp), 256):
            sl = slice(a, a + 256)
            c = cep[sl]
            fold = np.zeros((len(c), NFFT))
            fold[:, 0] = c[:, 0]
            fold[:, 1:NCEP] = 2.0 * c[:, 1:]
            H = np.exp(np.fft.fft(fold, axis=-1))
            H *= np.exp(-1j * omega[None, :] * delta[sl, None])
            ir = np.fft.ifft(H, axis=-1).real[:, :IR_LEN] * fade
            ir *= (gh[sl] * shimmer[sl] * Tper[sl] / 2.0)[:, None]
            for r, b in zip(ir, base[sl]):
                y[b:b + IR_LEN] += r
        # ---- noise: STFT-shaped independent white frames
        Nf, hop = 256, 64
        win = np.sin(np.pi * (np.arange(Nf) + 0.5) / Nf)
        nfr = (n * HOP) // hop
        lm = dsp.cep_to_logmag(T["cn"])[:, ::4]               # (n, 129)
        yn = np.zeros(n * HOP + Nf)
        for m in range(nfr):
            t = m * hop / HOP
            i = min(int(t), n - 2)
            fr = t - i
            g = T["gn"][i] * (1 - fr) + T["gn"][i + 1] * fr
            if g < 1e-3:
                continue
            G = np.exp(lm[i] * (1 - fr) + lm[i + 1] * fr) * g
            wn = self.rng.standard_normal(Nf)
            yn[m * hop:m * hop + Nf] += np.fft.irfft(np.fft.rfft(wn) * G, Nf) * win
        yn *= 1 / np.sqrt(2.0)
        y[:len(yn)] += yn[:len(y)]
        return y[:n * HOP]

    def synthesize(self, text, normalize=True):
        segs, phrases = self.plan(text)
        T = self.tracks(segs, phrases)
        y = self.render(T)
        if normalize:
            y = self._level(y, T)
        self.last = dict(segs=segs, T=T)
        return y

    def _level(self, y, T):
        hop = HOP
        n = len(y) // hop
        r = np.sqrt((y[:n * hop].reshape(n, hop) ** 2).mean(1))
        v = T["gh"][:n] > 0.5
        if v.sum() > 10:
            cur = np.percentile(r[v], 75)
            y = y * (10 ** (self.level_db / 20) / (cur + 1e-9))
        pk = np.abs(y).max()
        if pk > 0.95:
            y = y * 0.95 / pk
        return y


def copy_synthesis(fr, voice, n_samples=None):
    """Analysis -> synthesis of a recording's own parameters (engine fidelity test)."""
    f0 = fr["f0"].copy()
    v = f0 > 0
    n = len(f0)
    idx = np.arange(n)
    f0[~v] = np.interp(idx[~v], idx[v], f0[v]) if v.any() else voice.f0_med
    gh = v.astype(float)
    gn = np.ones(n)
    ch = fr["cep_h"].copy()
    cn = np.zeros_like(ch)
    for i in range(n):
        cn[i] = voice.noise_of(ch[i], 0.0) if v[i] else fr["cep_n"][i]
    # smooth voicing edges slightly
    k = np.array([0.25, 0.5, 0.25])
    gh = np.convolve(np.pad(gh, 1, mode="edge"), k, "valid")
    T = dict(ch=ch, cn=cn, gh=gh, gn=gn, f0=f0, n=n, t_start=None)
    y = voice.render(T)
    return y if n_samples is None else y[:n_samples]
