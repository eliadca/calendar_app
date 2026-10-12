"""OPTIONAL intelligibility test: transcribe synthesized wavs with Whisper (sherpa-onnx) and report word error rate.

    python tools/asr_eval.py MODEL_DIR  file1.wav "expected text"  file2.wav "expected text" ...
(MODEL_DIR = unpacked sherpa-onnx-whisper-small; see tools/transcribe_whisper.py.)
"""
import os
import re
import sys
import unicodedata

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from voxforge import dsp   # noqa: E402


def norm(t):
    t = unicodedata.normalize("NFD", t.lower())
    t = "".join(c for c in t if unicodedata.category(c) != "Mn")
    return re.sub(r"[^a-z0-9ñ ]+", " ", t).split()


def wer(ref, hyp):
    r, h = norm(ref), norm(hyp)
    d = np.zeros((len(r) + 1, len(h) + 1), int)
    d[:, 0], d[0, :] = np.arange(len(r) + 1), np.arange(len(h) + 1)
    for i in range(1, len(r) + 1):
        for j in range(1, len(h) + 1):
            d[i, j] = min(d[i - 1, j] + 1, d[i, j - 1] + 1, d[i - 1, j - 1] + (r[i - 1] != h[j - 1]))
    return d[-1, -1] / max(len(r), 1)


def make_recognizer(model_dir):
    import sherpa_onnx
    p = lambda n: os.path.join(model_dir, n)
    name = [f for f in os.listdir(model_dir) if f.endswith("-encoder.int8.onnx")][0][:-len("-encoder.int8.onnx")]
    return sherpa_onnx.OfflineRecognizer.from_whisper(
        encoder=p(name + "-encoder.int8.onnx"), decoder=p(name + "-decoder.int8.onnx"), tokens=p(name + "-tokens.txt"),
        language="es", task="transcribe", num_threads=1)


def transcribe(rec, wav):
    x, sr = dsp.read_wav(wav)
    y = np.ascontiguousarray(dsp.resample(x, sr, 16000).astype(np.float32))
    s = rec.create_stream()
    s.accept_waveform(16000, y)
    rec.decode_stream(s)
    return s.result.text.strip()


if __name__ == "__main__":
    rec = make_recognizer(sys.argv[1])
    args = sys.argv[2:]
    for wav, ref in zip(args[::2], args[1::2]):
        hyp = transcribe(rec, wav)
        print("%-34s WER %3.0f%%  | heard: %s" % (os.path.basename(wav), 100 * wer(ref, hyp), hyp))
