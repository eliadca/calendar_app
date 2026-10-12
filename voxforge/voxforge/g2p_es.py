"""Rule-based Spanish grapheme-to-phoneme, syllabifier and stress assigner (no dictionary)."""
import re
import unicodedata

VOW = "aeiou"
ACC = {"á": "a", "é": "e", "í": "i", "ó": "o", "ú": "u"}
FUNCTION_WORDS = set("""el la los las un una unos unas de del al a ante con en por para sin sobre tras y e o u ni que se su sus mi mis
tu tus lo le les me te nos os es son fue era ha han he hay si como pero mas cuando donde""".split())
ONSET_CLUSTERS = {"pl", "pɾ", "bl", "bɾ", "fl", "fɾ", "kl", "kɾ", "gl", "gɾ", "tɾ", "dɾ"}

_UNITS = "cero uno dos tres cuatro cinco seis siete ocho nueve diez once doce trece catorce quince dieciséis diecisiete dieciocho diecinueve veinte".split()
_TENS = {20: "veinte", 30: "treinta", 40: "cuarenta", 50: "cincuenta", 60: "sesenta", 70: "setenta", 80: "ochenta", 90: "noventa"}
_HUND = {100: "cien", 200: "doscientos", 300: "trescientos", 400: "cuatrocientos", 500: "quinientos", 600: "seiscientos",
         700: "setecientos", 800: "ochocientos", 900: "novecientos"}


def num2words(n):
    if n < 0:
        return "menos " + num2words(-n)
    if n <= 20:
        return _UNITS[n]
    if n < 30:
        return "veinti" + _UNITS[n - 20]
    if n < 100:
        t, u = divmod(n, 10)
        return _TENS[t * 10] + ("" if u == 0 else " y " + _UNITS[u])
    if n < 1000:
        h, r = divmod(n, 100)
        if n == 100:
            return "cien"
        return ("ciento" if h == 1 else _HUND[h * 100]) + ("" if r == 0 else " " + num2words(r))
    if n < 1_000_000:
        m, r = divmod(n, 1000)
        head = "mil" if m == 1 else num2words(m) + " mil"
        return head + ("" if r == 0 else " " + num2words(r))
    m, r = divmod(n, 1_000_000)
    head = "un millón" if m == 1 else num2words(m) + " millones"
    return head + ("" if r == 0 else " " + num2words(r))


def normalize(text):
    text = text.lower().replace("\n", " . ")
    text = re.sub(r"\d+", lambda m: " " + num2words(int(m.group())) + " ", text)
    text = text.replace("¿", " ").replace("¡", " ")
    text = re.sub(r"[“”\"'()\[\]«»]", " ", text)
    return text


def tokenize(text):
    """-> list of ('w', word) / ('p', punct)"""
    out = []
    for m in re.finditer(r"[a-záéíóúüñ]+|[,.;:?!…]", normalize(text)):
        t = m.group()
        out.append(("w", t) if t[0].isalpha() else ("p", "." if t == "…" else t))
    return out


def word_to_phones(w, seseo=True):
    """Return list of [phone, stressed_by_accent(bool)] for one word (stress marks only on vowels)."""
    w = unicodedata.normalize("NFC", w)
    out = []
    i, n = 0, len(w)

    def nxt(k=1):
        return w[i + k] if i + k < n else ""

    while i < n:
        c = w[i]
        acc = c in ACC
        base = ACC.get(c, c)
        if base in VOW:
            out.append([base, acc, "hiatus" if c in "íú" else ""])
        elif c == "ü":
            out.append(["u", False, ""])
        elif c == "c":
            if nxt() == "h":
                out.append(["tʃ", False, ""]); i += 1
            elif nxt() in ("e", "i", "é", "í"):
                out.append(["s" if seseo else "θ", False, ""])
            else:
                out.append(["k", False, ""])
        elif c == "q":
            out.append(["k", False, ""])
            if nxt() == "u":
                i += 1
        elif c == "g":
            if nxt() in ("e", "i", "é", "í"):
                out.append(["x", False, ""])
            elif nxt() == "u" and nxt(2) in ("e", "i", "é", "í"):
                out.append(["g", False, ""]); i += 1
            else:
                out.append(["g", False, ""])
        elif c == "j":
            out.append(["x", False, ""])
        elif c == "z":
            out.append(["s" if seseo else "θ", False, ""])
        elif c == "h":
            pass
        elif c == "ñ":
            out.append(["ɲ", False, ""])
        elif c == "l":
            if nxt() == "l":
                out.append(["ʝ", False, ""]); i += 1
            else:
                out.append(["l", False, ""])
        elif c == "r":
            if nxt() == "r":
                out.append(["r", False, ""]); i += 1
            elif i == 0 or w[i - 1] in "nls":
                out.append(["r", False, ""])
            else:
                out.append(["ɾ", False, ""])
        elif c == "v" or c == "b":
            out.append(["b", False, ""])
        elif c == "w":
            out.append(["w", False, ""])
        elif c == "y":
            if i == n - 1 or not nxt() in VOW + "áéíóú":
                out.append(["i", False, "glide"] if i > 0 else ["i", False, ""])
            else:
                out.append(["ʝ", False, ""])
        elif c == "x":
            out.append(["k", False, ""]); out.append(["s", False, ""])
        elif c in "pdtfkmns":
            out.append([c, False, ""])
        i += 1
    return out


def _glides(ph):
    """Turn unstressed i/u next to another vowel into glides (diphthongs/triphthongs)."""
    n = len(ph)
    isv = [p[0] in VOW for p in ph]
    for k in range(n):
        p, acc, tag = ph[k]
        if p in "iu" and not acc and tag != "hiatus":
            prev_v = k > 0 and isv[k - 1]
            next_v = k + 1 < n and isv[k + 1]
            if next_v or prev_v:
                # glide only if the neighbour vowel can be the nucleus
                if next_v and not (ph[k + 1][0] == p):
                    ph[k][0] = "j" if p == "i" else "w"
                    isv[k] = False
                elif prev_v and not (ph[k - 1][0] == p):
                    ph[k][0] = "j" if p == "i" else "w"
                    isv[k] = False
    return ph


def syllabify(ph):
    """ph: list of [phone, accent, tag]. Returns list of syllables (lists of indices)."""
    nuclei = [k for k, p in enumerate(ph) if p[0] in VOW]
    if not nuclei:
        return [list(range(len(ph)))]
    glide = lambda k: ph[k][0] in ("j", "w")
    cuts = []
    for a, b in zip(nuclei[:-1], nuclei[1:]):
        S = list(range(a + 1, b))
        if not S:
            cuts.append(b)
            continue
        rest = S[1:] if (glide(S[0]) and len(S) > 1) else S          # offglide stays with the left nucleus
        core = list(rest)
        while core and glide(core[-1]):                               # onglide stays with its onset
            core.pop()
        if not core:
            cuts.append(rest[0])
        elif len(core) == 1:
            cuts.append(core[0])
        elif ph[core[-2]][0] + ph[core[-1]][0] in ONSET_CLUSTERS:
            cuts.append(core[-2])
        else:
            cuts.append(core[-1])
    sylls, start = [], 0
    for cut in cuts:
        sylls.append(list(range(start, cut)))
        start = cut
    sylls.append(list(range(start, len(ph))))
    return [s for s in sylls if s]


def stress_index(ph, sylls, word):
    for si, s in enumerate(sylls):
        if any(ph[k][1] for k in s):
            return si
    if len(sylls) == 1:
        return 0 if word not in FUNCTION_WORDS else -1
    last = word[-1]
    if last in "aeiouns" and not (last == "s" and len(word) > 1 and word[-2] in "ns"):
        return len(sylls) - 2
    return len(sylls) - 1


def g2p(text, seseo=True):
    """Text -> list of phrase-level items.

    Returns a list of tokens: {"type":"word","phones":[{"p":..,"syl":i,"stress":bool}], "stressed_syl":i, "nsyl":n}
    and {"type":"punct","p":","}.
    """
    out = []
    for kind, tok in tokenize(text):
        if kind == "p":
            out.append({"type": "punct", "p": tok})
            continue
        ph = _glides(word_to_phones(tok, seseo))
        if not ph:
            continue
        sylls = syllabify(ph)
        st = stress_index(ph, sylls, tok)
        phones = []
        for si, s in enumerate(sylls):
            for k in s:
                p = ph[k][0]
                if p == "ʝ" or p == "tʃ" or p in "bdg" or p in ("j", "w"):
                    pass
                phones.append({"p": p, "syl": si, "stress": si == st, "word": tok})
        # contextual allophones: voiced stops -> approximants between continuants
        for k, d in enumerate(phones):
            if d["p"] in ("b", "d", "g"):
                prev = phones[k - 1]["p"] if k > 0 else None
                hard = prev is None or prev in ("m", "n", "ɲ", "ŋ") or (d["p"] == "d" and prev == "l")
                if not hard:
                    d["p"] = {"b": "β", "d": "ð", "g": "ɣ"}[d["p"]]
            if d["p"] == "n" and k + 1 < len(phones):
                nx = phones[k + 1]["p"]
                if nx in ("p", "b", "m", "β"):
                    d["p"] = "m"
                elif nx in ("k", "g", "x", "ɣ"):
                    d["p"] = "ŋ"
        out.append({"type": "word", "word": tok, "phones": phones, "stressed_syl": st, "nsyl": len(sylls)})
    return out
