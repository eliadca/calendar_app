# VoxForge

Sintetizador de voz con clonación, **100 % código, solo `numpy`** (sin modelos, sin pesos, sin GPU).
Aprende tu voz desde un WAV de 20 s, guarda un perfil de **~7 kB** y habla español sintetizando
**~50× más rápido que tiempo real en CPU**.

```bash
python -m voxforge clone  mi_voz.wav --transcript mi_voz.tsv -o voz.json   # perfil + banco de unidades reales
python -m voxforge speak  voz.json "Hola, ¿cómo estás?" -o hola.wav
python -m voxforge report mi_voz.wav --transcript mi_voz.tsv -o out         # clona + batería completa de pruebas
python -m unittest discover -s tests                                        # 14 tests
```

## Cómo funciona (lo que es nuevo aquí)

| etapa | técnica | archivo |
|---|---|---|
| Análisis | YIN (F0) + *true envelope* cepstral (48 coef.) por frame de 5 ms | `analyze.py` |
| Perfil | F0, vocales **descubiertas por clustering** semillado con las 5 del español, ecualizador residual, ruido de /s/ medido, ritmo | `analyze.build_profile` |
| Texto | G2P del español por reglas (acentos, diptongos, silabeo, números) – sin diccionario | `g2p_es.py` |
| Prosodia | contorno de F0 por frase (declinación, acentos, subida en preguntas), alargamiento final | `synth.f0_contour` |
| Alineación | plantilla sintética de la transcripción + **DTW** (MFCC + sonoridad) → límites de fonema reales, sin ASR | `units.build_db` |
| Unidades | cada fonema de tu grabación guarda *tus* trayectorias reales (envolvente, ruido, sonoridad, F0); selección por **Viterbi** (coste de contexto + coste de unión) | `units.UnitDB` |
| Motor | **respuestas al impulso de fase mínima, pitch‑síncronas**, retardo fraccionario exacto, **dispersión de fase opcional** (`dispersion_ms`, desactivada: a tu oído sonó peor) + ruido en STFT; todo filtrado por *tu* envolvente | `synth.render` |

Todo lo específico de tu voz se calibra por **análisis‑por‑síntesis** (se mide con la misma función en tu audio
y en el sintetizado, así el sesgo del medidor se cancela): tempo, contraste de formantes, ecualización.

## Inteligibilidad (medida con Whisper en el circuito)

Las métricas espectrales de más abajo **no miden si se entiende**. Lo que sí: transcribir el audio con un reconocedor
(`tools/asr_eval.py`, herramienta de desarrollo, no dependencia) y contar palabras mal entendidas (WER, menor = mejor).

| audio | WER |
|---|---|
| tu voz real | 10 % |
| copy‑synthesis (parámetros reales de tu audio) | **3.6 %** |
| ídem con el pitch plano | 3.6 % (el pitch no afecta a entenderse) |
| ídem con envolventes suavizadas ±60 ms | 8.8 % |
| tu audio con las **vocales** sustituidas por mis prototipos | 18 % |
| ídem fricativas / sonorantes / oclusivas sustituidas (una clase cada vez) | 5 % cada una |
| ídem con **todos** los fonemas por modelos estáticos (tiempos y pitch reales) | 43 % |
| **texto nuevo, reglas + tu perfil (ajustado)** | **~48–53 %** (8–10 oraciones variadas) |
| texto nuevo, reglas con voz genérica sin tu perfil | 96 % |
| texto nuevo, banco de unidades de 20 s | 56 % (peor que reglas → desactivado por defecto) |

Conclusión medida: el vocoder y el pitch están bien; lo que falla es el **contenido espectral y las transiciones** que
el modelo de reglas predice para texto nuevo (los errores de vocales y transiciones se acumulan). Lo que movió la aguja
al barrer con el reconocedor: tempo 1.0 (igualar tu ritmo rápido lo empeoraba: 75 %), vocales más articuladas
(`articulation=0.9`, `clarity=1.7`) y transiciones más largas (`trans_scale=2.2`). Afinar más las reglas se estanca en ~40–50 %.

## Resultados medidos (métricas de PARECIDO, no de inteligibilidad) (tu `audioclone.wav`, transcrito)

Reproducibles con `python -m voxforge report mi_voz.wav --transcript mi_voz.tsv`; ver `out/report.md`.

| prueba | resultado |
|---|---|
| Copy‑synthesis (fidelidad del motor) | log‑mel **4.5 dB** (4.2 sin dispersión de fase; control desalineado 23 dB); F0 19 cents |
| Timbre del texto→voz (reglas) vs. tu voz | **3.1 dB** (voz genérica: 8.1 dB); generalización a mitad no vista: 3.3 dB |
| Alineación vs. verdad conocida (sintético, con ruido y desajuste de EQ) | error mediano **~3 ms**, 99 % < 20 ms |
| Alineación en tu audio real (sin verdad disponible) | vocales sonoras 90 %, /s/ sordas 96 % |
| Unidades vs. tu grabación, **frase que está en el banco** | distancia **16.6** (reglas: 33.4) → casi la mitad |
| Unidades vs. tu grabación, **texto nuevo** (frase retenida) | **30.5** (reglas: 33.4) → mejora **modesta (~9 %)** |
| Banco + perfil | 574 kB + 7.7 kB; ~50× tiempo real |

### Lo que NO está resuelto

- **«100 % exacto» solo se cumple para lo que ya dijiste**: re‑sintetizar una frase del banco queda a la mitad de
  distancia de las reglas. Para texto nuevo, con 4 frases de datos solo el **18 %** de los fonemas encuentra una unidad
  con *ambos* vecinos iguales a lo que se necesita; el resto se pega con vecinos distintos. Es un límite de **datos**,
  no del método: con el guion de abajo (70 frases) la cobertura sube drásticamente.
- Las métricas objetivas no miden naturalidad. Lo que decide es escuchar.
- La dispersión de fase iguala la «impulsividad» de pulso de tu voz (nuestro indicador), pero baja un poco la
  distancia log‑mel (4.2→4.5 dB): se cambia fidelidad espectral por menos zumbido. `dispersion_ms=0` la desactiva.
- Consonantes sin unidad real (p. ej. /b/, /g/, /ŋ/, /r/ en tus datos) caen a reglas y suenan más artificiales.

## Cómo llegar de verdad a calidad profesional

1. Graba el guion `samples/recording_script.txt` (70 frases, ~5.5 min, cubre 93 % de fonemas‑en‑contexto de un
   corpus variado; cada fonema ≥ 11 veces). Una sola toma larga, 0.7 s de silencio entre frases, mismo micro y
   distancia, sala silenciosa.
2. `python tools/split_by_script.py grabacion.wav samples/recording_script.txt -o samples/mi_voz.tsv`
   (sin transcribir a mano: el guion *es* la transcripción).
3. `python -m voxforge clone grabacion.wav --transcript samples/mi_voz.tsv -o voz.json`.

Siguientes mejoras de motor: regresor de prosodia diminuto sobre el F0 alineado, selección con coste de unión
espectral más fino, ruido de sala medido en las pausas, port a Dart/JS para la app Flutter.
