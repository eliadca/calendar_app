"""Turn ONE long recording + the script (one sentence per line) into the TSV `voxforge clone --transcript` needs.

    python tools/split_by_script.py recording.wav samples/recording_script.txt -o samples/my_voice.tsv

Leave >= 0.7 s of silence between sentences while recording. Sentence boundaries are the centres of the long
pauses; the number of segments must equal the number of script lines (otherwise it tells you how to adjust).
"""
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from voxforge import dsp   # noqa: E402


def split(x, sr, n_expected, min_pause=0.7):
    hop = int(sr * 0.01)
    n = len(x) // hop
    r = np.sqrt((x[:n * hop].reshape(n, hop) ** 2).mean(1))
    thr = max(0.02 * np.percentile(r, 95), 1.5 * np.percentile(r, 5))
    quiet = r < thr
    pauses, i = [], 0
    while i < n:
        if quiet[i]:
            j = i
            while j < n and quiet[j]:
                j += 1
            if (j - i) * hop / sr >= min_pause and i > 0 and j < n:
                pauses.append((i + j) / 2 * hop / sr)
            i = j
        else:
            i += 1
    cuts = [0.0] + pauses + [len(x) / sr]
    return cuts, len(cuts) - 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("wav")
    ap.add_argument("script")
    ap.add_argument("-o", "--out", default="my_voice.tsv")
    ap.add_argument("--min-pause", type=float, default=0.7)
    a = ap.parse_args()
    lines = [l.strip() for l in open(a.script, encoding="utf-8") if l.strip()]
    x, sr = dsp.read_wav(a.wav)
    cuts, n = split(x, sr, len(lines), a.min_pause)
    if n != len(lines):
        sys.exit("found %d segments but the script has %d lines. Try --min-pause %.2f" % (
            n, len(lines), a.min_pause * (0.8 if n < len(lines) else 1.25)))
    with open(a.out, "w", encoding="utf-8") as f:
        for (t0, t1), text in zip(zip(cuts[:-1], cuts[1:]), lines):
            f.write("%.3f\t%.3f\t%s\n" % (t0, t1, text))
    print("wrote %s (%d sentences, %.1f s)" % (a.out, n, len(x) / sr))


if __name__ == "__main__":
    main()
