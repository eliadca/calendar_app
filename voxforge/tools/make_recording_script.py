"""Pick a recording script by greedy coverage of phone-in-context units (phone + previous phone + next phone,
with the word boundary and stress marked), using VoxForge's own G2P. Writes samples/recording_script.txt."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from voxforge import g2p_es   # noqa: E402

POOL = """
Hola, ¿cómo estás? Hace mucho que no hablábamos.
Mañana por la mañana tengo que llevar a mi hermana al aeropuerto.
¿Dónde dejaste las llaves del coche que compramos el año pasado?
El niño pequeño corría detrás del perro por el jardín de la abuela.
Quisiera una taza de café con leche y un pedazo de pastel de chocolate.
La reunión empieza a las nueve y media, así que no llegues tarde.
Nunca imaginé que el viaje a la montaña sería tan largo y cansado.
¡Qué sorpresa tan agradable verte por aquí después de tantos años!
Los científicos descubrieron una nueva especie de pez en el fondo del océano.
Necesito que me expliques otra vez cómo funciona esta máquina tan extraña.
Ayer llovió toda la tarde y las calles se llenaron de agua.
Mi primo trabaja en una empresa que fabrica juguetes para niños.
Si quieres, podemos cenar juntos el viernes en ese restaurante italiano.
El tren sale de la estación a las seis y cuarto de la tarde.
Aunque estaba muy cansado, decidió terminar el trabajo antes de dormir.
¿Cuántos kilómetros hay desde la ciudad hasta la playa más cercana?
Perdona, ¿sabes si hay una farmacia abierta cerca de aquí?
Cuando era pequeña, pasaba los veranos en el pueblo con mis abuelos.
El presidente anunció que habrá nuevas medidas para mejorar la educación.
Me gusta caminar por el parque cuando el cielo está despejado.
Tres tristes tigres tragaban trigo en un trigal.
El perro de San Roque no tiene rabo porque Ramón Rodríguez se lo ha robado.
La lluvia cae suavemente sobre los tejados de la vieja ciudad.
Compré cinco kilos de naranjas, dos de manzanas y un racimo de uvas.
Esa chica china toca la guitarra mientras su hermano escucha la radio.
¿Por qué no me llamaste cuando llegaste a la estación?
Un ingeniero joven inventó un aparato que purifica el agua del río.
Los domingos mi padre prepara una paella enorme para toda la familia.
La biblioteca cierra los sábados, pero el museo permanece abierto hasta tarde.
Hay quienes piensan que la imaginación vale más que el conocimiento.
El cuadro que colgaba sobre la chimenea era un regalo de mi tía Josefina.
Quince jóvenes viajaron a Guatemala para ayudar a reconstruir una escuela.
Dijo que volvería pronto, pero nadie volvió a saber de él.
Estoy buscando un libro sobre la historia de las civilizaciones antiguas.
Zacarías vendió su bicicleta azul para comprar un boleto de avión.
El gato saltó desde la ventana y aterrizó sin hacer ruido.
¡Cuidado con el escalón, que está resbaladizo después de la lluvia!
Debemos proteger los bosques, los ríos y los animales que viven en ellos.
La profesora explicó con paciencia la diferencia entre ambas teorías.
Mi abuela guardaba las fotografías antiguas dentro de una caja de madera.
Todavía recuerdo el olor del pan recién horneado por las mañanas.
¿Te importaría cerrar la puerta? Entra mucho frío por la escalera.
El equipo trabajó durante semanas para resolver un problema muy complejo.
Los pájaros cantaban en las ramas mientras amanecía lentamente.
Ese hombre alto lleva un sombrero negro y un abrigo gris muy elegante.
La economía del país creció un tres por ciento durante el último año.
Vamos a necesitar más harina, huevos frescos y un poco de mantequilla.
No sé si podré ir, porque tengo muchísimo trabajo acumulado.
La luna llena iluminaba el camino que atravesaba el campo de trigo.
Unos dicen que sí y otros dicen que no, pero nadie lo sabe con certeza.
El agua hierve a cien grados cuando se encuentra al nivel del mar.
Había una vez un rey que gobernaba un reino lejano, rodeado de montañas.
Gracias por tu paciencia; sé que no ha sido fácil esperar tanto tiempo.
Estudiar idiomas abre muchas puertas y permite conocer otras culturas.
Los vecinos organizaron una fiesta para celebrar el cumpleaños del abuelo.
Llevaba una mochila llena de libros, cuadernos y lápices de colores.
El médico me recomendó descansar, beber agua y evitar el exceso de azúcar.
¿Quién fue el primero en llegar a la cima de aquella enorme montaña?
Compartimos un taxi hasta el centro y después caminamos por la plaza.
La ley establece que todos los ciudadanos tienen derecho a la salud.
Mi hermano pequeño aprendió a nadar durante las vacaciones de verano.
Esa película me hizo reír y llorar al mismo tiempo.
Un joven periodista entrevistó a la famosa escritora en su casa de campo.
El tráfico estaba tan pesado que tardamos dos horas en llegar.
Entre los árboles se escuchaba el murmullo de un arroyo escondido.
La mejor manera de aprender es practicar todos los días un poco.
¡Feliz cumpleaños! Espero que todos tus deseos se hagan realidad.
El examen incluía preguntas de matemáticas, física y química.
Hablaron durante horas sobre el futuro, los sueños y las decisiones difíciles.
Una abeja zumbaba alrededor de las flores amarillas del balcón.
Me dolía la garganta, así que tomé té con miel y limón.
La pregunta no es si podemos hacerlo, sino cuándo vamos a empezar.
El cartero dejó un paquete grande delante de la puerta del vecino.
Pasamos la noche junto a la hoguera contando historias de miedo.
Es importante que revises bien el contrato antes de firmar nada.
Las estrellas brillaban sobre el desierto con una claridad increíble.
Probablemente llegaremos a tiempo si salimos ahora mismo.
Esos zapatos son demasiado caros, pero me encanta el color.
La conferencia sobre inteligencia artificial atrajo a cientos de asistentes.
Antes de salir, apaga las luces, cierra las ventanas y revisa el gas.
Ojalá pudiéramos volver a aquel verano en la costa del Pacífico.
¿Vas a quedarte en casa o prefieres venir al cine con nosotros?
Cada mañana, el panadero abría su tienda mucho antes de que saliera el sol.
Una gota de agua puede cambiar el rumbo de un río entero.
El escritor argentino ganó el premio con una novela sobre su infancia.
Aquel invierno fue el más frío que se recordaba en la región.
Tienes que girar a la derecha, seguir recto y cruzar el puente.
Necesito veinte euros, un sello y una bolsa para llevar las verduras.
Mis amigos y yo organizamos una excursión para el próximo fin de semana.
Los resultados del estudio sugieren que el sueño mejora la memoria.
Quiero agradecerles a todos por haber venido hoy; significa muchísimo para mí.
""".strip().split("\n")


def contexts(text):
    toks = [t for t in g2p_es.g2p(text) if t["type"] == "word"]
    seq = []
    for w in toks:
        for k, p in enumerate(w["phones"]):
            seq.append((p["p"], p["stress"], k == 0, k == len(w["phones"]) - 1))
    out = set()
    for i, (p, st, ini, fin) in enumerate(seq):
        prev = seq[i - 1][0] if i else "_"
        nxt = seq[i + 1][0] if i + 1 < len(seq) else "_"
        out.add((prev, p, nxt))
    return out


def main(n_max=70):
    ctx = {s: contexts(s) for s in POOL}
    covered, chosen = set(), []
    while len(chosen) < n_max:
        best = max(POOL, key=lambda s: len(ctx[s] - covered) / max(len(s), 1) ** 0.5 if s not in chosen else -1)
        gain = len(ctx[best] - covered)
        if gain < 4:
            break
        chosen.append(best)
        covered |= ctx[best]
    allctx = set().union(*ctx.values())
    out = os.path.join(os.path.dirname(__file__), "..", "samples", "recording_script.txt")
    open(out, "w", encoding="utf-8").write("\n".join(chosen) + "\n")
    words = sum(len(s.split()) for s in chosen)
    print("%d sentences, ~%d words (~%.1f min at 150 wpm), covers %d of %d phone-in-context units in the pool (%.0f%%)" % (
        len(chosen), words, words / 150, len(covered), len(allctx), 100 * len(covered) / len(allctx)))
    phones = {}
    for s in chosen:
        for t in g2p_es.g2p(s):
            if t["type"] == "word":
                for p in t["phones"]:
                    phones[p["p"]] = phones.get(p["p"], 0) + 1
    print("phone counts:", dict(sorted(phones.items(), key=lambda kv: kv[1])))


if __name__ == "__main__":
    main()
