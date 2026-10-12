import os
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from voxforge import analyze, dsp, evaluate, g2p_es, phones, synth, units   # noqa: E402

TEXT = "Hola, ¿cómo estás? Hoy hace muy buen día para pasear por el parque con todos los amigos."


def syls(word):
    toks = [t for t in g2p_es.g2p(word) if t["type"] == "word"][0]
    out = {}
    for p in toks["phones"]:
        out.setdefault(p["syl"], []).append(p["p"])
    return ".".join("".join(out[k]) for k in sorted(out)), toks["stressed_syl"]


class G2P(unittest.TestCase):
    def test_syllables_and_stress(self):
        cases = {
            "murciélago": ("muɾ.sje.la.ɣo", 1),
            "aeropuerto": ("a.e.ɾo.pweɾ.to", 3),
            "ciudad": ("sju.ðað", 1),
            "guitarra": ("gi.ta.ra", 1),
            "instrucción": ("ins.tɾuk.sjon", 2),
            "país": ("pa.is", 1),
            "árbol": ("aɾ.βol", 0),
            "hablar": ("a.βlaɾ", 1),
        }
        for w, exp in cases.items():
            self.assertEqual(syls(w), exp, w)

    def test_numbers(self):
        self.assertEqual(g2p_es.num2words(21), "veintiuno")
        self.assertEqual(g2p_es.num2words(547), "quinientos cuarenta y siete")
        self.assertEqual(g2p_es.num2words(2025), "dos mil veinticinco")
        self.assertEqual(g2p_es.num2words(100), "cien")

    def test_digraphs(self):
        ph = lambda w: [p["p"] for t in g2p_es.g2p(w) if t["type"] == "word" for p in t["phones"]]
        self.assertEqual(ph("queso"), ["k", "e", "s", "o"])
        self.assertEqual(ph("noche")[1:3], ["o", "tʃ"])
        self.assertIn("ɲ", ph("año"))
        self.assertIn("r", ph("perro"))
        self.assertEqual(ph("hola")[0], "o")


class DSP(unittest.TestCase):
    def test_resample_tone(self):
        sr = 44100
        x = np.sin(2 * np.pi * 1000 * np.arange(sr) / sr)
        y = dsp.resample(x, sr, 22050)
        self.assertAlmostEqual(len(y) / 22050, 1.0, places=2)
        f = np.fft.rfftfreq(len(y), 1 / 22050)
        self.assertAlmostEqual(f[np.abs(np.fft.rfft(y)).argmax()], 1000, delta=2)

    def test_cepstrum_roundtrip_and_minphase(self):
        cep = phones.formant_cep(phones.VOWEL_F["a"])
        lm = dsp.cep_to_logmag(cep[None, :])[0]
        np.testing.assert_allclose(dsp.logmag_to_cep(lm[None, :])[0], cep, atol=1e-9)
        h = dsp.minphase_ir(cep, 1024)[0]
        mag = np.log(np.abs(np.fft.rfft(h, dsp.NFFT)) + 1e-12)
        self.assertLess(np.abs(mag - lm)[:300].max(), 0.15)      # IR realises the envelope (<1.3 dB)
        self.assertGreater(np.abs(h[:20]).sum(), np.abs(h[500:]).sum())   # energy up front = minimum phase


class Engine(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.voice = synth.Voice(None)          # generic voice, f0 median 118 Hz
        cls.y = cls.voice.synthesize(TEXT)

    def test_output_sane(self):
        y = self.y
        self.assertTrue(np.isfinite(y).all())
        self.assertGreater(len(y) / dsp.SR, 3.0)
        self.assertLessEqual(np.abs(y).max(), 0.951)

    def test_pitch_is_what_we_asked_for(self):
        f0, _, _ = analyze.yin_f0(self.y)
        med = np.median(f0[f0 > 0])
        self.assertAlmostEqual(med, 118, delta=12)

    def test_edge_inputs(self):
        for t in ["", "...", "¿?", "x", "MÉXICO", "1234567", "güero", "a\nb"]:
            y = self.voice.synthesize(t)
            self.assertTrue(np.isfinite(y).all(), t)

    def test_question_rises_statement_falls(self):
        def slope(y):
            f0, _, _ = analyze.yin_f0(y)
            v = np.where(f0 > 0)[0]
            return np.median(f0[v[-12:]]) / np.median(f0[v[-45:-25]])     # end pitch / earlier pitch
        for t in ("Vienes mañana", "Puedes venir hoy"):
            q = slope(self.voice.synthesize("¿%s?" % t))
            s = slope(self.voice.synthesize("%s." % t))
            self.assertGreater(q, 1.08, t)           # question: clear final rise
            self.assertLess(s, 0.92, t)              # statement: clear final fall
            self.assertGreater(q - s, 0.3, t)

    def test_clone_round_trip_recovers_parameters(self):
        prof, _, fr = analyze.build_profile(self.y, dsp.SR)
        self.assertAlmostEqual(prof["f0"]["median"], 118, delta=15)
        self.assertEqual(sorted(prof["vowels"]), sorted(phones.VOWELS))
        # engine fidelity on a signal we know the answer for
        yc = synth.copy_synthesis(fr, synth.Voice(prof), len(self.y))
        d, _ = evaluate.mel_distance(self.y, yc)
        self.assertLess(d, 6.0)

    def test_profile_is_tiny(self):
        import json
        prof, _, _ = analyze.build_profile(self.y, dsp.SR)
        self.assertLess(len(json.dumps(prof, default=float)) / 1024, 40)


class Units(unittest.TestCase):
    """Alignment is tested against ground truth: audio whose phone boundaries we know exactly."""

    SENTS = ["Proponen que la luz polarizada de ciertas estrellas podría haber destruido un tipo de molécula.",
             "Otras sugieren que ciertos cristales minerales actuaron como plantillas."]

    def _truth_audio(self, text, tempo, noise, seed=3):
        g = synth.Voice(None, tempo=tempo, seed=seed)
        rng = np.random.default_rng(seed)
        segs, ph = g.plan(text)
        for s in segs:
            if s["kind"] != "P":
                s["dur"] *= float(np.exp(rng.normal(0, 0.25)))      # random per-phone timing the template cannot know
        T = g.tracks(segs, ph)
        y = g.render(T) + np.random.default_rng(seed).normal(0, noise, T["n"] * dsp.HOP)
        gt = {}
        for j, s in enumerate(segs):
            if s["kind"] != "P":
                gt.setdefault(s["pid"], [T["t_start"][j], 0])[1] = T["t_start"][j] + s["dur"]
        return y, gt

    def test_alignment_recovers_boundaries(self):
        errs = []
        for text in self.SENTS:
            y, gt = self._truth_audio(text, tempo=1.0, noise=0.004)
            fr = analyze.analyze_frames(y)
            g = synth.Voice(None, tempo=1.4, seed=9)                  # template with a *different* rhythm
            tr = units.real_tracks(fr, g)
            mel_r = units.mel_power(y, len(fr["f0"]))
            floor = max(3 * np.percentile(mel_r.sum(1), 5) / 40, 1e-6)
            Fr = units.features(mel_r, floor, tr["v"])
            segs, ph = g.plan(text)
            T = g.tracks(segs, ph)
            Ft = units.features(units.mel_power(g.render(T), T["n"]), floor, T["gh"] > 0.5)
            path, _ = units.dtw(Ft, Fr)
            gm = units.warp_map(path, T["n"])
            groups = {}
            for j, s in enumerate(segs):
                if s["kind"] != "P":
                    groups.setdefault(s["pid"], []).append(j)
            for pid, js in groups.items():
                a = int(round(T["t_start"][js[0]] / units.DT))
                b = int(round((T["t_start"][js[-1]] + segs[js[-1]]["dur"]) / units.DT))
                errs += [abs(gm[a] * units.DT - gt[pid][0]), abs(gm[min(b, T["n"])] * units.DT - gt[pid][1])]
        errs = np.array(errs) * 1000
        self.assertLess(np.median(errs), 15)             # ms
        self.assertGreater((errs < 40).mean(), 0.9)

    def test_unit_bank_and_selection(self):
        y, _ = self._truth_audio(self.SENTS[0] + " " + self.SENTS[1], tempo=1.0, noise=0.002)
        prof, yy, fr = analyze.build_profile(y, dsp.SR)
        v = synth.Voice(prof)
        n = len(yy) / dsp.SR
        db, _ = units.build_db(v, yy, fr, [(0.0, n / 2, self.SENTS[0]), (n / 2, n, self.SENTS[1])], verbose=False)
        self.assertGreater(len(db.units), 80)
        v.units = db
        out = v.synthesize("Otras estrellas sugieren que los cristales actuaron como plantillas.")
        self.assertTrue(np.isfinite(out).all())
        self.assertGreater(len(out) / dsp.SR, 2.0)
        # held-out run must never use units of the excluded sentence
        segs, _ = v.plan(self.SENTS[0])
        chosen = db.select(segs, exclude={0})
        self.assertTrue(all(db.units[u]["sent"] != 0 for u in chosen.values()))
        # round trip through disk
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            db.save(os.path.join(d, "u.npz"))
            db2 = units.UnitDB.load(os.path.join(d, "u.npz"))
            self.assertEqual(len(db2.units), len(db.units))

    def test_dispersion_keeps_magnitude_and_reduces_pulsiness(self):
        v0, v1 = synth.Voice(None, dispersion_ms=0.0), synth.Voice(None, dispersion_ms=2.5)
        self.assertTrue(np.allclose(np.abs(v1._dispersion()), 1.0))      # all-pass: magnitude untouched
        y0, y1 = v0.synthesize("La casa de papel."), v1.synthesize("La casa de papel.")
        def hf_peakiness(y):
            n = len(y) // 44
            e = np.abs(np.fft.rfft(y[:n * 44].reshape(n, 44) * np.hanning(44), 64, axis=1))[:, 20:].sum(1)
            return e.max() / (e.mean() + 1e-12)
        self.assertLess(hf_peakiness(y1), hf_peakiness(y0))


if __name__ == "__main__":
    unittest.main(verbosity=2)
