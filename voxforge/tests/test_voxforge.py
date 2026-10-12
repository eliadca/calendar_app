import os
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from voxforge import analyze, dsp, evaluate, g2p_es, phones, synth   # noqa: E402

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


if __name__ == "__main__":
    unittest.main(verbosity=2)
