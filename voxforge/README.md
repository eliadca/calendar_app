# VoxForge

Sintetizador de voz con clonación, **100 % código, solo `numpy`** (sin modelos, sin pesos, sin GPU).
Aprende tu voz desde un WAV de 20 s, guarda un perfil de **~7 kB** y habla español sintetizando
**~50× más rápido que tiempo real en CPU**.

```bash
python -m voxforge clone  mi_voz.wav -o voz.json          # aprende el perfil (2 s)
python -m voxforge speak  voz.json "Hola, ¿cómo estás?" -o hola.wav
python -m voxforge report mi_voz.wav -o out                # clona + batería completa de pruebas
python -m unittest discover -s tests                       # 11 tests
```

## Cómo funciona (lo que es nuevo aquí)

| etapa | técnica | archivo |
|---|---|---|
| Análisis | YIN (F0) + *true envelope* cepstral (48 coef.) por frame de 5 ms | `analyze.py` |
| Perfil | F0, vocales **descubiertas por clustering** semillado con las 5 del español, ecualizador residual, ruido de /s/ medido, ritmo | `analyze.build_profile` |
| Texto | G2P del español por reglas (acentos, diptongos, silabeo, números) – sin diccionario | `g2p_es.py` |
| Prosodia | contorno de F0 por frase (declinación, acentos, subida en preguntas), alargamiento final | `synth.f0_contour` |
| Motor | **respuestas al impulso de fase mínima, pitch‑síncronas**, con retardo fraccionario exacto + ruido en STFT; ambos filtrados por *tu* envolvente | `synth.render` |

Todo lo específico de tu voz se calibra por **análisis‑por‑síntesis** (se mide con la misma función en tu audio
y en el sintetizado, así el sesgo del medidor se cancela): tempo, contraste de formantes, ecualización.

## Resultados medidos (tu `audioclone.wav`)

Reproducibles con `python -m voxforge report`; ver `out/report.md`.

| prueba | resultado |
|---|---|
| Copy‑synthesis de tu audio (fidelidad del motor) | distancia log‑mel **4.2 dB** (control con audio desalineado: 23 dB) |
| Pitch de esa copia | error mediano **19 cents**, voz/sorda coinciden en 93 % |
| Timbre TTS vs. tu voz | **2.8 dB** (voz genérica sin clonar: 9.5 dB) |
| **Generalización**: perfil de la 1ª mitad vs. 2ª mitad nunca vista | **3.3 dB** (genérica: 9.7 dB) |
| Vocales sintetizadas distinguibles | **100 %** (5/5) |
| Velocidad | copy‑synth 45×, TTS 55× tiempo real; perfil 7 kB |

## Límites reales (leer esto)

- **No rivaliza todavía con ElevenLabs.** Esas métricas miden timbre, pitch y espectro; **no miden naturalidad ni
  inteligibilidad** — para eso hay que escuchar. Este sintetizador es paramétrico: suena a voz sintética limpia
  con tu timbre, no a grabación humana.
- Comparado con tu grabación (ver `out/spec_*.png`): tu habla es más *legato* y tiene ruido de sala; la síntesis
  es más silábica, con huecos marcados en las consonantes y silencio digital en las pausas.
- Un solo hablante, un solo clip de 20 s, sin transcripción. En tu habla rápida /a/ y /o/ colapsan, así que el
  perfil se mezcla con el modelo teórico de vocales (`articulation=0.6`): se pierde algo de fidelidad por inteligibilidad.
- Consonantes y duraciones son **reglas**, no datos tuyos. El aspecto «recortado» de /p t k/ viene de ahí.

## Camino hacia la calidad profesional (sin redes gigantes)

1. **Alineación gratis**: con una transcripción, alinear tu audio con la propia síntesis por DTW sobre cepstros
   (sin ASR) → etiquetas de fonema → aprender trayectorias de envolvente, duraciones y F0 *por fonema* de tus datos.
2. Regresor de prosodia diminuto (cientos de parámetros) entrenado con ese F0 alineado.
3. Forma de pulso glotal / dispersión de fase para quitar el «zumbido» de la fase mínima + ruido de sala medido.
4. Port a Dart/JS (todo es FFT + convoluciones simples) para usarlo dentro de la app Flutter.

Lo que más mueve la aguja: **más audio de tu voz con su texto** (5–10 min).
