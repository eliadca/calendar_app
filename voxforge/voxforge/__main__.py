"""CLI:  python -m voxforge clone|speak|report ..."""
import argparse
import sys
import time

from . import analyze, dsp, synth


def _y_fr(x, sr):
    y = dsp.resample(x, sr, dsp.SR)
    y = y / (abs(y).max() + 1e-9) * 0.9
    return y, analyze.analyze_frames(y)


def main(argv=None):
    ap = argparse.ArgumentParser(prog="voxforge", description="Tiny numpy-only voice cloning TTS (Spanish).")
    sub = ap.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("clone", help="learn a voice profile from a reference wav")
    c.add_argument("wav")
    c.add_argument("-o", "--out", default="voice.json")
    c.add_argument("--transcript", help="TSV: start_s<TAB>end_s<TAB>text. Enables the recorded-unit bank (much more natural)")

    s = sub.add_parser("speak", help="synthesize text with a learned voice")
    s.add_argument("profile")
    s.add_argument("text")
    s.add_argument("-o", "--out", default="speech.wav")
    s.add_argument("--tempo", type=float, default=None, help="speaking-rate factor (1.0 = profile default)")
    s.add_argument("--expressiveness", type=float, default=1.0)
    s.add_argument("--no-units", action="store_true", help="ignore the recorded-unit bank (rule-based voice)")
    s.add_argument("--distincion", action="store_true", help="Castilian c/z = [θ] instead of seseo")

    r = sub.add_parser("report", help="clone + run the full objective test suite + write samples")
    r.add_argument("wav")
    r.add_argument("-o", "--outdir", default="out")
    r.add_argument("--transcript", help="TSV transcript (enables unit-bank tests)")

    a = ap.parse_args(argv)
    if a.cmd == "clone":
        x, sr = dsp.read_wav(a.wav)
        t = time.time()
        prof, _, _ = analyze.build_profile(x, sr, verbose=True)
        if a.transcript:
            import os
            from . import units
            y, fr = _y_fr(x, sr)
            sents = units.read_transcript(a.transcript)
            v = synth.Voice(prof)
            db, cost = units.build_db(v, y, fr, sents)
            prof["dur_scale"] = v.dur_scale
            db.save(os.path.splitext(a.out)[0] + ".units.npz")
            print("unit bank: %d units from %d sentences" % (len(db.units), len(sents)))
        analyze.save_profile(prof, a.out)
        print("profile written to %s (%.1f s)" % (a.out, time.time() - t))
    elif a.cmd == "speak":
        v = synth.load_voice(a.profile, use_units=not a.no_units, tempo=a.tempo, seseo=not a.distincion,
                             expressiveness=a.expressiveness)
        y = v.synthesize(a.text)
        dsp.write_wav(a.out, y)
        print("wrote %s (%.2f s of audio)" % (a.out, len(y) / dsp.SR))
    elif a.cmd == "report":
        from . import report
        report.run(a.wav, a.outdir, a.transcript)
    return 0


if __name__ == "__main__":
    sys.exit(main())
