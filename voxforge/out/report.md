# VoxForge – informe de pruebas objetivas

## 1. Perfil de voz aprendido de tu WAV

- Tamaño del perfil: **7.0 kB** (JSON), clonado en 2.2 s
- F0 mediana **122 Hz** (p5–p95: 82–217 Hz), desviación 5.0 semitonos
- Vocales descubiertas (frames): {'a': 433, 'e': 458, 'i': 332, 'o': 300, 'u': 224}
- Factor de nitidez de formantes aprendido: x1.40

## 2. Fidelidad del motor (copy-synthesis de tu propio audio)

| métrica | valor |
|---|---|
| distancia log-mel | **4.21 dB** (control con audio desalineado: 23.0 dB) |
| sesgo medio por banda | 0.39 dB |
| error F0 mediano | **19 cents** (voz/sorda coinciden en 93% de frames) |
| velocidad | **45×** tiempo real |

## 3. Texto→voz: parecido a tu voz vs. voz genérica sin clonar

| métrica (menor = más parecido) | clon | genérica |
|---|---|---|
| distancia de timbre medio LTAS | **2.77 dB** | 9.46 dB |
| error por bandas | **1.72 dB** | 12.96 dB |
| F0 mediana (ref: 122 Hz) | **123 Hz** | 119 Hz |
| velocidad TTS | **55×** tiempo real | |

### Prueba de generalización (perfil aprendido con la 1ª mitad, comparado con la 2ª mitad nunca vista)

| distancia de timbre LTAS a la 2ª mitad | dB |
|---|---|
| clon aprendido sólo con la 1ª mitad | **3.32** |
| clon completo (in-sample, optimista) | 3.12 |
| voz genérica sin clonar | 9.70 |

## 4. Discriminabilidad de vocales sintetizadas

Clasificación de /a e i o u/ sintetizadas frente a las vocales teóricas del español ecualizadas con tu voz: **100%**

## 5. Audios generados

- `tts_saludo.wav` (clon) / `generic_saludo.wav` (sin clonar): «Hola, ¿cómo estás? Esta es mi voz sintética, hecha completamente con código.»
- `tts_pangrama.wav` (clon) / `generic_pangrama.wav` (sin clonar): «El veloz murciélago hindú comía feliz cardillo y kiwi, mientras la cigüeña tocaba el saxofón detrás del palenque.»
- `tts_numeros.wav` (clon) / `generic_numeros.wav` (sin clonar): «Hoy es doce de octubre, y son las tres y veinte de la tarde. Quedan quinientos cuarenta y siete días.»
- `tts_pregunta.wav` (clon) / `generic_pregunta.wav` (sin clonar): «¿Puedes creer que una voz entera cabe en menos de treinta kilobytes?»
- `tts_trabalenguas.wav` (clon) / `generic_trabalenguas.wav` (sin clonar): «Tres tristes tigres tragaban trigo en un trigal, y el perro de San Roque no tiene rabo.»
- `copy_synthesis.wav` vs `reference_22k.wav`: tu audio re-sintetizado desde sus parámetros
