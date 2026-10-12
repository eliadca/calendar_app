"""Sweep helper: mean WER of a Voice on a fixed set of unseen sentences (Whisper in the loop; dev tool only)."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np                       # noqa: E402
from voxforge import dsp                 # noqa: E402
import asr_eval                          # noqa: E402

SENTENCES = [
    "Hola, ¿cómo estás? Hace mucho que no hablábamos.",
    "Mañana por la mañana tengo que llevar a mi hermana al aeropuerto.",
    "Quisiera una taza de café con leche y un pedazo de pastel.",
    "La reunión empieza a las nueve y media, así que no llegues tarde.",
    "El niño pequeño corría detrás del perro por el jardín.",
    "Necesito que me expliques otra vez cómo funciona esta máquina.",
    "Ayer llovió toda la tarde y las calles se llenaron de agua.",
    "Si quieres, podemos cenar juntos el viernes en un restaurante.",
]
_rec = None


def mean_wer(voice, verbose=False, tmp="/tmp/_intel.wav", **synth_kw):
    global _rec
    if _rec is None:
        _rec = asr_eval.make_recognizer(os.environ["ASR_MODEL"])
    w = []
    for t in SENTENCES:
        dsp.write_wav(tmp, voice.synthesize(t, **synth_kw))
        hyp = asr_eval.transcribe(_rec, tmp)
        w.append(asr_eval.wer(t, hyp))
        if verbose:
            print("   %3.0f%% | %s" % (100 * w[-1], hyp))
    return float(np.mean(w))
