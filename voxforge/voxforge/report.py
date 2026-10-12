"""Full objective test of the cloned voice. Writes wavs, spectrogram PNGs, report.json and report.md."""
import json
import os
import time
import numpy as np
from . import analyze, dsp, evaluate, phones, synth, units as units_mod, viz
from .dsp import SR

TEXTS = {
    "saludo": "Hola, ¿cómo estás? Esta es mi voz sintética, hecha completamente con código.",
    "pangrama": "El veloz murciélago hindú comía feliz cardillo y kiwi, mientras la cigüeña tocaba el saxofón detrás del palenque.",
    "numeros": "Hoy es doce de octubre, y son las tres y veinte de la tarde. Quedan quinientos cuarenta y siete días.",
    "pregunta": "¿Puedes creer que una voz entera cabe en menos de treinta kilobytes?",
    "trabalenguas": "Tres tristes tigres tragaban trigo en un trigal, y el perro de San Roque no tiene rabo.",
}


def _vowel_accuracy(voice):
    """Synthesize t-V-t syllables and classify the vowel by nearest *textbook* band-profile."""
    nb = 5            # F1/F2 region only (500-3000 Hz): upper bands mostly encode the recording's tilt
    prof_of = lambda c: (lambda b: b - b.mean())(analyze.band_profile(c)[0][:nb])
    seeds = np.array([prof_of(phones.formant_cep(phones.VOWEL_F[v]) + voice.res) for v in phones.VOWELS])   # textbook vowels in the speaker's EQ
    hits, conf = 0, np.zeros((5, 5), int)
    total = 0
    for vi, v in enumerate(phones.VOWELS):
        for ctx in ("tá", "pá", "ká", "sá"):
            word = ctx[:-1] + {"a": "á", "e": "é", "i": "í", "o": "ó", "u": "ú"}[v]
            y = voice.synthesize(word + " " + word)
            segs, T = voice.last["segs"], voice.last["T"]
            for j, s in enumerate(segs):
                if s["kind"] == "V" and s["ph"] == v:
                    mid = int((T["t_start"][j] + 0.5 * s["dur"]) / (dsp.HOP / SR))
                    prof = prof_of(T["ch"][mid])
                    k = int(((seeds - prof) ** 2).sum(1).argmin())
                    conf[vi, k] += 1
                    hits += int(k == vi)
                    total += 1
    return hits / max(total, 1), conf


def run(wav_path, outdir, transcript=None):
    os.makedirs(outdir, exist_ok=True)
    rep = {}
    x, sr = dsp.read_wav(wav_path)
    t0 = time.time()
    prof, y_ref, fr = analyze.build_profile(x, sr)
    rep["clone_seconds"] = time.time() - t0
    analyze.save_profile(prof, os.path.join(outdir, "voice.json"))
    rep["profile_kB"] = os.path.getsize(os.path.join(outdir, "voice.json")) / 1024
    rep["profile"] = dict(f0=prof["f0"], vowel_counts=prof["vowel_counts"], sharpen=prof["sharpen"],
                          syll_rate=prof["syll_rate"], stats=prof["stats"])
    voice = synth.Voice(prof)
    generic = synth.Voice(None)

    # ---- A. engine fidelity: copy-synthesis of the reference itself
    t0 = time.time()
    y_copy = synth.copy_synthesis(fr, voice, len(y_ref))
    cs = time.time() - t0
    y_copy *= np.sqrt((y_ref ** 2).sum() / (y_copy ** 2).sum())
    d, bias = evaluate.mel_distance(y_ref, y_copy)
    rep["copy_synthesis"] = dict(
        logmel_distance_db=d, mean_abs_band_bias_db=float(np.abs(bias[1:]).mean()), f0=evaluate.f0_error(y_ref, y_copy),
        realtime_factor=(len(y_ref) / SR) / cs)
    # control: same metric against a *different* signal (time-shifted by 1 s) -> what "no match" looks like
    sh = np.roll(y_ref, SR)
    rep["copy_synthesis"]["control_shifted_reference_db"] = evaluate.mel_distance(y_ref, sh)[0]
    dsp.write_wav(os.path.join(outdir, "reference_22k.wav"), y_ref)
    dsp.write_wav(os.path.join(outdir, "copy_synthesis.wav"), y_copy)
    # A/B: phase-dispersed vocoder (fewer pulse spikes, but judged worse by ear -> not the default)
    y_disp = synth.copy_synthesis(fr, synth.Voice(prof, dispersion_ms=2.5), len(y_ref))
    y_disp *= np.sqrt((y_ref ** 2).sum() / (y_disp ** 2).sum())
    dsp.write_wav(os.path.join(outdir, "copy_synthesis_dispersion.wav"), y_disp)
    rep["copy_synthesis"]["logmel_dispersion_db"] = evaluate.mel_distance(y_ref, y_disp)[0]

    # ---- B. text-to-speech samples + speaker similarity vs. reference and vs. generic baseline
    ref_stats = evaluate.speaker_stats(y_ref)
    tts = {}
    total_audio, total_time = 0.0, 0.0
    for name, text in TEXTS.items():
        t0 = time.time()
        y = voice.synthesize(text)
        total_time += time.time() - t0
        total_audio += len(y) / SR
        dsp.write_wav(os.path.join(outdir, "tts_%s.wav" % name), y)
        yg = generic.synthesize(text)
        dsp.write_wav(os.path.join(outdir, "generic_%s.wav" % name), yg)
        st, sg = evaluate.speaker_stats(y), evaluate.speaker_stats(yg)
        tts[name] = dict(text=text, seconds=len(y) / SR,
                         clone=dict(f0_median=st["f0_median"], f0_sd_st=st["f0_sd_st"],
                                    ltas_dist_db=evaluate.ltas_distance(st["ltas"], ref_stats["ltas"]),
                                    band_err_db=float(np.abs(st["bands"] - ref_stats["bands"]).mean())),
                         generic=dict(f0_median=sg["f0_median"], f0_sd_st=sg["f0_sd_st"],
                                      ltas_dist_db=evaluate.ltas_distance(sg["ltas"], ref_stats["ltas"]),
                                      band_err_db=float(np.abs(sg["bands"] - ref_stats["bands"]).mean())))
        if name == "saludo":
            viz.spectrogram_png(y, SR, os.path.join(outdir, "spec_tts_saludo.png"), fmax=6000, title="VoxForge clone")
            viz.spectrogram_png(y_ref[:len(y)], SR, os.path.join(outdir, "spec_reference.png"), fmax=6000, title="reference")
    rep["reference"] = dict(f0_median=ref_stats["f0_median"], f0_sd_st=ref_stats["f0_sd_st"])
    rep["tts"] = tts
    rep["tts_summary"] = dict(
        ltas_dist_clone_db=float(np.mean([v["clone"]["ltas_dist_db"] for v in tts.values()])),
        ltas_dist_generic_db=float(np.mean([v["generic"]["ltas_dist_db"] for v in tts.values()])),
        band_err_clone_db=float(np.mean([v["clone"]["band_err_db"] for v in tts.values()])),
        band_err_generic_db=float(np.mean([v["generic"]["band_err_db"] for v in tts.values()])),
        f0_median_clone=float(np.mean([v["clone"]["f0_median"] for v in tts.values()])),
        f0_median_generic=float(np.mean([v["generic"]["f0_median"] for v in tts.values()])),
        realtime_factor=total_audio / total_time, audio_seconds=total_audio)

    # ---- B2. held-out generalisation: learn from the first half, test against the unseen second half
    half = len(x) // 2
    p1, y1, _ = analyze.build_profile(x[:half], sr)
    v1 = synth.Voice(p1)
    second = dsp.resample(x[half:], sr, SR)
    second = second / (np.abs(second).max() + 1e-9) * 0.9
    st2 = evaluate.speaker_stats(second)
    ho = {"clone_first_half": [], "generic": [], "clone_full_in_sample": []}
    for name, text in TEXTS.items():
        for key, vv in (("clone_first_half", v1), ("generic", generic), ("clone_full_in_sample", voice)):
            sv = evaluate.speaker_stats(vv.synthesize(text))
            ho[key].append(evaluate.ltas_distance(sv["ltas"], st2["ltas"]))
    rep["held_out"] = {k: float(np.mean(v)) for k, v in ho.items()}
    rep["held_out"]["f0_median_second_half"] = st2["f0_median"]
    rep["held_out"]["f0_median_clone_first_half"] = p1["f0"]["median"]

    # ---- B3. recorded-unit bank (needs a transcript)
    if transcript:
        rep["units"] = _unit_tests(prof, y_ref, fr, transcript, outdir, ref_stats)

    # ---- C. vowel discriminability
    acc, conf = _vowel_accuracy(voice)
    rep["vowel_accuracy_vs_textbook"] = acc
    rep["vowel_confusion"] = conf.tolist()

    with open(os.path.join(outdir, "report.json"), "w") as f:
        json.dump(rep, f, indent=1, default=float)
    _write_md(rep, outdir)
    return rep


def _unit_tests(prof, y_ref, fr, transcript, outdir, ref_stats):
    sents = units_mod.read_transcript(transcript)
    vb = synth.Voice(prof)
    t0 = time.time()
    db, _ = units_mod.build_db(vb, y_ref, fr, sents, verbose=False)
    out = dict(build_seconds=time.time() - t0, n_units=len(db.units), n_sentences=len(sents))
    db.save(os.path.join(outdir, "voice.units.npz"))
    out["bank_kB"] = os.path.getsize(os.path.join(outdir, "voice.units.npz")) / 1024
    prof["dur_scale"] = vb.dur_scale                      # keep profile and bank consistent on disk
    analyze.save_profile(prof, os.path.join(outdir, "voice.json"))
    p2 = dict(prof)
    vu = synth.Voice(p2)
    vu.units = db
    # alignment sanity on the REAL recording (independent evidence the phone boundaries are meaningful)
    vow = [np.mean(db.t["gh"][u["a"]:u["b"]]) for u in db.units if u["phone"] in "aeiou"]
    sv = [np.mean(db.t["gh"][u["a"]:u["b"]]) for u in db.units if u["phone"] == "s"]
    out["align_sanity"] = dict(vowel_units_voiced=float(np.mean(vow)), s_units_voiced=float(np.mean(sv)) if sv else None)
    # leave-one-sentence-out distance to the real recording
    n_real = len(fr["f0"])
    mel_r = units_mod.mel_power(y_ref, n_real)
    floor = max(3 * np.percentile(mel_r.sum(1), 5) / 40, 1e-6)

    def dist(ys, r0, r1):
        ns = len(ys) // dsp.HOP
        Fs = units_mod.features(units_mod.mel_power(ys, ns), floor, np.zeros(ns, bool))
        Fr = units_mod.features(mel_r[r0:r1], floor, np.zeros(r1 - r0, bool))
        return units_mod.dtw(Fs, Fr)[1]

    rows, cov = [], []
    for k, (t0_, t1_, text) in enumerate(sents):
        r0, r1 = int(t0_ / (dsp.HOP / dsp.SR)), min(n_real, int(t1_ / (dsp.HOP / dsp.SR)))
        y_rule = vu.synthesize(text, use_units=False)
        y_held = vu.synthesize(text, exclude={k})
        y_in = vu.synthesize(text)
        segs, _ = vu.plan(text)
        ch = db.select(segs, {k})
        pids = {s["pid"]: s for s in segs if s["kind"] != "P"}
        both = sum(1 for p, ui in ch.items() if db.units[ui]["prev"] == pids[p]["prev"] and db.units[ui]["next"] == pids[p]["next"])
        cov.append((len(ch) / len(pids), both / len(pids)))
        rows.append((dist(y_rule, r0, r1), dist(y_held, r0, r1), dist(y_in, r0, r1)))
        if k == 1:
            dsp.write_wav(os.path.join(outdir, "unit_heldout_S2.wav"), y_held)
            dsp.write_wav(os.path.join(outdir, "rules_S2.wav"), y_rule)
            dsp.write_wav(os.path.join(outdir, "unit_insample_S2.wav"), y_in)
            dsp.write_wav(os.path.join(outdir, "real_S2.wav"), y_ref[int(t0_ * dsp.SR):int(t1_ * dsp.SR)])
    rows = np.array(rows)
    out["distance_to_real"] = dict(rules=float(rows[:, 0].mean()), units_held_out=float(rows[:, 1].mean()),
                                   units_in_sample=float(rows[:, 2].mean()))
    out["coverage_held_out"] = dict(phones_with_unit=float(np.mean([c[0] for c in cov])),
                                    both_neighbours_match=float(np.mean([c[1] for c in cov])))
    # new-text demos
    demos = {"nuevo1": "Hola, ¿cómo estás? Ciertos cristales minerales actuaron como plantillas.",
             "nuevo2": "Otras estrellas sugieren que la preferencia se pasa de una molécula a otra."}
    for name, text in demos.items():
        dsp.write_wav(os.path.join(outdir, "unit_%s.wav" % name), vu.synthesize(text))
    for name, text in TEXTS.items():
        dsp.write_wav(os.path.join(outdir, "unit_%s.wav" % name), vu.synthesize(text))
    return out


def _write_md(r, outdir):
    cs, ts = r["copy_synthesis"], r["tts_summary"]
    f0e = cs["f0"] or {}
    L = []
    L.append("# VoxForge – informe de pruebas objetivas\n")
    L.append("## 1. Perfil de voz aprendido de tu WAV\n")
    L.append("- Tamaño del perfil: **%.1f kB** (JSON), clonado en %.1f s" % (r["profile_kB"], r["clone_seconds"]))
    L.append("- F0 mediana **%.0f Hz** (p5–p95: %.0f–%.0f Hz), desviación %.1f semitonos" % (
        r["profile"]["f0"]["median"], r["profile"]["f0"]["p5"], r["profile"]["f0"]["p95"], r["profile"]["f0"]["sd_semitones"]))
    L.append("- Vocales descubiertas (frames): %s" % r["profile"]["vowel_counts"])
    L.append("- Factor de nitidez de formantes aprendido: x%.2f\n" % r["profile"]["sharpen"])
    L.append("## 2. Fidelidad del motor (copy-synthesis de tu propio audio)\n")
    L.append("| métrica | valor |\n|---|---|")
    L.append("| distancia log-mel | **%.2f dB** (control con audio desalineado: %.1f dB) |" % (cs["logmel_distance_db"], cs["control_shifted_reference_db"]))
    L.append("| sesgo medio por banda | %.2f dB |" % cs["mean_abs_band_bias_db"])
    if f0e:
        L.append("| error F0 mediano | **%.0f cents** (voz/sorda coinciden en %.0f%% de frames) |" % (f0e["median_abs_cents"], 100 * f0e["voicing_agreement"]))
    L.append("| velocidad | **%.0f×** tiempo real |\n" % cs["realtime_factor"])
    L.append("## 3. Texto→voz: parecido a tu voz vs. voz genérica sin clonar\n")
    L.append("| métrica (menor = más parecido) | clon | genérica |\n|---|---|---|")
    L.append("| distancia de timbre medio LTAS | **%.2f dB** | %.2f dB |" % (ts["ltas_dist_clone_db"], ts["ltas_dist_generic_db"]))
    L.append("| error por bandas | **%.2f dB** | %.2f dB |" % (ts["band_err_clone_db"], ts["band_err_generic_db"]))
    L.append("| F0 mediana (ref: %.0f Hz) | **%.0f Hz** | %.0f Hz |" % (r["reference"]["f0_median"], ts["f0_median_clone"], ts["f0_median_generic"]))
    L.append("| velocidad TTS | **%.0f×** tiempo real | |\n" % ts["realtime_factor"])
    h = r["held_out"]
    L.append("### Prueba de generalización (perfil aprendido con la 1ª mitad, comparado con la 2ª mitad nunca vista)\n")
    L.append("| distancia de timbre LTAS a la 2ª mitad | dB |\n|---|---|")
    L.append("| clon aprendido sólo con la 1ª mitad | **%.2f** |" % h["clone_first_half"])
    L.append("| clon completo (in-sample, optimista) | %.2f |" % h["clone_full_in_sample"])
    L.append("| voz genérica sin clonar | %.2f |\n" % h["generic"])
    L.append("## 4. Discriminabilidad de vocales sintetizadas\n")
    L.append("Clasificación de /a e i o u/ sintetizadas frente a las vocales teóricas del español ecualizadas con tu voz: **%.0f%%**\n" % (100 * r["vowel_accuracy_vs_textbook"]))
    if "units" in r:
        u = r["units"]
        d = u["distance_to_real"]
        L.append("## 4b. Banco de unidades reales (con transcripción)\n")
        L.append("- %d unidades de %d frases, banco de **%.0f kB**, construido en %.1f s" % (u["n_units"], u["n_sentences"], u["bank_kB"], u["build_seconds"]))
        L.append("- Sanidad de la alineación sobre tu grabación real: vocales sonoras %.0f %%, /s/ sordas %.0f %%" % (
            100 * u["align_sanity"]["vowel_units_voiced"], 100 * (1 - (u["align_sanity"]["s_units_voiced"] or 0))))
        L.append("\n**Distancia a tu grabación real, frase retenida** (menor = más cercano; otra frase tuya distinta ≈ 44):\n")
        L.append("| método | distancia |\n|---|---|")
        L.append("| reglas (sin unidades) | %.1f |" % d["rules"])
        L.append("| unidades, texto NUEVO (frase retenida del banco) | **%.1f** |" % d["units_held_out"])
        L.append("| unidades, texto que está en el banco | **%.1f** |\n" % d["units_in_sample"])
        c = u["coverage_held_out"]
        L.append("Cobertura con texto nuevo: %.0f %% de los fonemas hallan unidad real, pero solo **%.0f %%** con ambos vecinos iguales (los datos son escasos).\n" % (100 * c["phones_with_unit"], 100 * c["both_neighbours_match"]))
    L.append("## 5. Audios generados\n")
    for k, v in r["tts"].items():
        L.append("- `tts_%s.wav` (clon) / `generic_%s.wav` (sin clonar): «%s»" % (k, k, v["text"]))
    L.append("- `copy_synthesis.wav` vs `reference_22k.wav`: tu audio re-sintetizado desde sus parámetros\n")
    open(os.path.join(outdir, "report.md"), "w").write("\n".join(L))
