"""Unit database built from the speaker's own recording (+ transcript) and unit selection.

Pipeline
  1. For every transcribed sentence, synthesize a *template* with the rule engine (it already has the
     speaker's timbre) and DTW-align it to the real audio (MFCC + voicing cues). No ASR / no external model.
  2. Phone boundaries of the template are projected through the warp path -> real phone instances.
  3. Each instance keeps the speaker's *real* parameter trajectories (envelope, noise, voicing, F0).
  4. At synthesis time units are chosen by Viterbi (target context cost + join cost) and rendered with the
     same engine used for copy-synthesis.
"""
import json
import numpy as np
from . import dsp
from .dsp import SR, HOP, NCEP

DT = HOP / SR
CLASS = {}
for p_ in "aeiou":
    CLASS[p_] = "V"
for p_ in ("j", "w"):
    CLASS[p_] = "G"
for p_ in ("m", "n", "ɲ", "ŋ"):
    CLASS[p_] = "N"
for p_ in ("l", "ɾ", "r"):
    CLASS[p_] = "L"
for p_ in ("p", "t", "k", "tʃ"):
    CLASS[p_] = "T"
for p_ in ("b", "d", "g"):
    CLASS[p_] = "B"
for p_ in ("β", "ð", "ɣ", "ʝ"):
    CLASS[p_] = "A"
for p_ in ("s", "θ", "f", "x", "ʃ", "z"):
    CLASS[p_] = "F"
CLASS["_"] = "_"


# ------------------------------------------------------------------ features
def mel_power(x, n):
    win = 512
    xp = np.concatenate([np.zeros(win // 2), x, np.zeros(win + HOP)])
    idx = np.arange(win)[None, :] + HOP * np.arange(n)[:, None]
    S = np.abs(np.fft.rfft(xp[idx] * np.hanning(win), dsp.NFFT, axis=-1)) ** 2
    return S @ dsp.mel_filterbank(40).T


_DCT = np.cos(np.pi / 40 * (np.arange(40)[:, None] + 0.5) * np.arange(1, 14)[None, :])


def features(mel, floor, voiced):
    L = np.log(mel + max(floor, 1e-6))
    c = L @ _DCT                                 # 13 cepstral coeffs (c0 = energy)
    c[:, 1:] -= c[:, 1:].mean(0, keepdims=True)
    c[:, 0] = 0.25 * (c[:, 0] - c[:, 0].mean())
    return np.concatenate([c, 6.0 * voiced[:, None].astype(float)], axis=1)


def dtw(A, B, pen=0.15):
    """Classic 3-step DTW, vectorised along rows. A: template (n,d), B: real (m,d). Returns path array."""
    a2, b2 = (A ** 2).sum(1)[:, None], (B ** 2).sum(1)[None, :]
    C = np.sqrt(np.maximum(a2 + b2 - 2 * A @ B.T, 0)).astype(np.float32)
    pen = pen * float(C.mean())
    n, m = C.shape
    D = np.empty((n, m), np.float32)
    D[0] = np.cumsum(C[0] + pen) - pen
    for i in range(1, n):
        cand = np.empty(m, np.float32)
        cand[0] = D[i - 1, 0] + pen
        cand[1:] = np.minimum(D[i - 1, :-1], D[i - 1, 1:] + pen)
        P = np.cumsum(C[i] + pen)
        D[i] = P + np.minimum.accumulate(cand + C[i] - P)
    i, j = n - 1, m - 1
    path = [(i, j)]
    while i > 0 or j > 0:
        if i == 0:
            j -= 1
        elif j == 0:
            i -= 1
        else:
            opts = (D[i - 1, j - 1], D[i - 1, j] + pen, D[i, j - 1] + pen)
            k = int(np.argmin(opts))
            if k == 0:
                i, j = i - 1, j - 1
            elif k == 1:
                i -= 1
            else:
                j -= 1
        path.append((i, j))
    return np.array(path[::-1]), float(D[-1, -1] / len(path))


def warp_map(path, n_template):
    """template frame -> real frame (monotone). Index n_template maps to path end."""
    g = np.zeros(n_template + 1)
    for i in range(n_template):
        js = path[path[:, 0] == i, 1]
        g[i] = js.mean() if len(js) else g[i - 1]
    g[n_template] = path[-1, 1] + 1
    return np.maximum.accumulate(g)


def read_transcript(path):
    out = []
    for line in open(path, encoding="utf-8"):
        if line.strip():
            a, b, text = line.rstrip("\n").split("\t")
            out.append((float(a), float(b), text))
    return out


# ---------------------------------------------------------------- real tracks
def real_tracks(fr, voice):
    """Per-frame parameters of the real recording in exactly the form the renderer consumes."""
    f0 = fr["f0"].copy()
    v = f0 > 0
    n = len(f0)
    idx = np.arange(n)
    f0[~v] = np.interp(idx[~v], idx[v], f0[v])
    gh = np.convolve(np.pad(v.astype(float), 1, mode="edge"), [0.25, 0.5, 0.25], "valid")
    ch = fr["cep_h"].copy()
    cn = np.array([voice.noise_of(ch[i], 0.0) if v[i] else fr["cep_n"][i] for i in range(n)])
    return dict(ch=ch, cn=cn, gh=gh, gn=np.ones(n), f0=f0, v=v)


# --------------------------------------------------------------------- DB
class UnitDB:
    def __init__(self, tracks, units, f0_med):
        self.t = tracks
        self.units = units
        self.f0_med = f0_med
        self.by_phone = {}
        for k, u in enumerate(units):
            self.by_phone.setdefault(u["phone"], []).append(k)

    # ---- persistence
    def save(self, path):
        t = self.t
        np.savez_compressed(path, ch=t["ch"].astype(np.float16), cn=t["cn"].astype(np.float16),
                            gh=t["gh"].astype(np.float16), f0=t["f0"].astype(np.float32),
                            meta=np.frombuffer(json.dumps(dict(units=self.units, f0_med=self.f0_med)).encode(), np.uint8))

    @classmethod
    def load(cls, path):
        z = np.load(path)
        meta = json.loads(bytes(z["meta"]).decode())
        t = dict(ch=z["ch"].astype(np.float64), cn=z["cn"].astype(np.float64), gh=z["gh"].astype(np.float64),
                 f0=z["f0"].astype(np.float64))
        t["gn"] = np.ones(len(t["gh"]))
        return cls(t, meta["units"], meta["f0_med"])

    # ---- selection
    def _edge(self, u, which):
        a, b = u["a"], u["b"]
        sl = slice(a, a + 2) if which == 0 else slice(b - 2, b)
        gh = self.t["gh"][sl].mean()
        v = self.t["ch"][sl] if gh > 0.5 else self.t["cn"][sl]
        return v.mean(0)[1:14], gh, self.t["f0"][sl].mean()

    def select(self, segs, exclude=()):
        """Viterbi over phone groups. Returns {pid: unit_index} (groups without candidates are absent)."""
        groups = []
        seen = set()
        for s in segs:
            if s["kind"] == "P" or s["pid"] in seen:
                continue
            seen.add(s["pid"])
            members = [x for x in segs if x["pid"] == s["pid"]]
            groups.append((s, sum(x["dur"] for x in members)))
        cands = []
        for s, dur in groups:
            ks = [k for k in self.by_phone.get(s["phone"], []) if self.units[k]["sent"] not in exclude]
            costs = []
            for k in ks:
                u = self.units[k]
                c = 0.0
                for key, w in (("prev", 0.8), ("next", 1.0)):
                    if u[key] != s[key]:
                        c += w * (0.5 if CLASS.get(u[key]) == CLASS.get(s[key]) else 1.0)
                c += 0.8 * (u["stress"] != s.get("pstress", False)) if s["phone"] in "aeiou" else 0
                c += 0.4 * (u["wpos"] != s["wpos"]) + 0.8 * (u["pfinal"] != s["pfinal"])
                c += 0.6 * abs(np.log((u["b"] - u["a"]) * DT / max(dur, 1e-3)))
                costs.append(c)
            order = np.argsort(costs)[:14]
            cands.append([(ks[i], costs[i]) for i in order])
        # Viterbi
        best = []
        prev_scores, prev_ptr = None, None
        chosen = {}
        layers = []
        for gi, cl in enumerate(cands):
            if not cl:
                layers.append(None)
                continue
            layers.append(cl)
        # split into runs separated by groups without candidates
        runs, cur = [], []
        for gi, cl in enumerate(layers):
            if cl is None:
                if cur:
                    runs.append(cur)
                cur = []
            else:
                cur.append(gi)
        if cur:
            runs.append(cur)
        for run in runs:
            scores = [np.array([c for _, c in layers[run[0]]])]
            ptrs = []
            for a, b in zip(run[:-1], run[1:]):
                La, Lb = layers[a], layers[b]
                join = np.zeros((len(La), len(Lb)))
                for i, (ka, _) in enumerate(La):
                    ea = self._edge(self.units[ka], 1)
                    for j, (kb, _) in enumerate(Lb):
                        if self.units[ka]["b"] == self.units[kb]["a"]:
                            join[i, j] = -0.6                       # natural continuation in the recording
                        else:
                            sb = self._edge(self.units[kb], 0)
                            d = np.abs(ea[0] - sb[0]).mean()
                            if (ea[1] > 0.5) != (sb[1] > 0.5):
                                d += 0.5
                            join[i, j] = 0.35 * d + 0.4 * abs(12 * np.log2(ea[2] / sb[2])) / 6
                tot = scores[-1][:, None] + join
                ptrs.append(tot.argmin(0))
                scores.append(tot.min(0) + np.array([c for _, c in Lb]))
            j = int(scores[-1].argmin())
            for t_ in range(len(run) - 1, -1, -1):
                chosen[groups[run[t_]][0]["pid"]] = layers[run[t_]][j][0]
                if t_ > 0:
                    j = int(ptrs[t_ - 1][j])
        return chosen


def _trim(phone, v, a, b):
    """Snap unit edges to the voicing evidence: vowels/sonorants keep their longest voiced run,
    voiceless fricatives keep their longest unvoiced run."""
    if phone in "aeiou" or phone in ("j", "w", "m", "n", "ɲ", "ŋ", "l", "r", "ɾ"):
        want = True
    elif phone in ("s", "θ", "f", "x", "ʃ"):
        want = False
    else:
        return a, b
    best, cur0, best_len = None, None, 0
    for k in range(a, b + 1):
        ok = k < b and bool(v[k]) == want
        if ok and cur0 is None:
            cur0 = k
        if (not ok) and cur0 is not None:
            if k - cur0 > best_len:
                best, best_len = (cur0, k), k - cur0
            cur0 = None
    return best if best and best_len >= 3 else (a, b)


# --------------------------------------------------------------- alignment
def build_db(voice, y_real, fr_real, sentences, iterations=2, verbose=True, pen=0.15, trim=True):
    """sentences: list of (t_start, t_end, text) in seconds of y_real. Returns UnitDB."""
    n_real = len(fr_real["f0"])
    tr = real_tracks(fr_real, voice)
    mel_r = mel_power(y_real, n_real)
    floor = max(3.0 * np.percentile(mel_r.sum(1), 5) / 40, 1e-6)
    F_real = features(mel_r, floor, tr["v"])
    voice.dur_scale = {}
    units = []
    for it in range(iterations):
        ratios, units, costs = {}, [], []
        for si, (t0, t1, text) in enumerate(sentences):
            segs, phrases = voice.plan(text)
            T = voice.tracks(segs, phrases)
            y_t = voice.render(T)
            n_t = T["n"]
            mel_t = mel_power(y_t, n_t)
            F_t = features(mel_t, floor, T["gh"] > 0.5)
            r0, r1 = max(0, int((t0 - 0.05) / DT)), min(n_real, int((t1 + 0.05) / DT))
            path, cost = dtw(F_t, F_real[r0:r1], pen)
            costs.append(cost)
            g = warp_map(path, n_t) + r0
            groups = {}
            for j, s in enumerate(segs):
                if s["kind"] != "P":
                    groups.setdefault(s["pid"], []).append(j)
            for pid, js in groups.items():
                f_a = int(round(T["t_start"][js[0]] / DT))
                f_b = int(round((T["t_start"][js[-1]] + segs[js[-1]]["dur"]) / DT))
                a, b = int(round(g[min(f_a, n_t)])), int(round(g[min(f_b, n_t)]))
                s0 = segs[js[0]]
                ratios.setdefault(s0["phone"], []).append(((b - a) + 1e-6) / max(f_b - f_a, 1))
                if trim:
                    a, b = _trim(s0["phone"], tr["v"], a, b)
                if b - a >= 3:
                    units.append(dict(phone=s0["phone"], prev=s0["prev"], next=s0["next"], stress=bool(s0.get("pstress")),
                                      wpos=s0["wpos"], pfinal=bool(s0["pfinal"]), sent=si, a=a, b=b, pid=int(pid),
                                      word=s0.get("word", "")))
        if verbose:
            print("  alignment pass %d: mean DTW cost %.3f, %d units" % (it, np.mean(costs), len(units)))
        if it < iterations - 1:                       # EM-style: learn per-phone duration scale for the template
            for p, r in ratios.items():
                if len(r) >= 2:
                    voice.dur_scale[p] = float(np.clip(voice.dur_scale.get(p, 1.0) * np.median(r), 0.5, 2.0))
    units.sort(key=lambda u: (u["a"], u["b"]))
    return UnitDB(tr, units, voice.f0_med), float(np.mean(costs))
