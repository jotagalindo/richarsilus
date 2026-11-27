# Propuesta de mejoras de Richarsilus

Fecha: 2026-11-27. Punto de partida: versión 0.0.2 con el rediseño de la ventana.

Todas las propuestas respetan las normas que ya sigue el addon: solo API del juego, **una acción protegida por
clic** (comprar, cancelar, craftear, publicar) y escaneo limitado a los objetos que hacen falta.

## Ya incluido en este rediseño

| Mejora | Qué resuelve |
|---|---|
| Tema oscuro propio, con iconos de objeto y jerarquía clara (título, barra de herramientas, tabla, tarjeta de detalle, botones) | La ventana parecía un volcado de texto; ahora se escanea con la vista |
| Tabla de materiales (necesitas / tienes / comprar / dónde / pagas) en vez de frases | Se compara de un vistazo, sin leer línea a línea |
| Resultado como factura (venta, comisión, depósito, materiales, beneficio) | Se ve de dónde sale el beneficio |
| Botón del **siguiente paso** en dorado y una pista debajo ("Siguiente paso: ...") | El jugador nuevo no tiene que saber el orden comprar → craftear → publicar |
| Tooltips en todos los botones, cabeceras, depósito y objetos (también con el botón desactivado) | Explica cada control sin ir al README |
| Ordenar por cualquier columna (se guarda en `RicharsilusDB.settings.sortKey`) | Buscar lo más barato, lo de más margen o lo que ya puedes hacer |
| Barra de estado con progreso del escaneo y hora de los precios | Saber si los precios son de ahora o de hace una hora |
| La receta más rentable queda elegida al abrir; *Escanear* desactivado (con el motivo) si no hay recetas | Menos clics y menos errores al empezar |
| Estados vacíos con instrucciones ("Aún no conozco tus recetas...") | La primera vez se sabe qué hacer |

## Propuestas

Esfuerzo: **S** = una tarde, **M** = 1-3 días, **L** = una semana o más.

### Prioridad alta: mucho valor, poco esfuerzo

1. **Buscador y filtros en la tabla** (S). Un cuadro de búsqueda por nombre y tres filtros: *solo rentables*, *solo lo
   que puedo hacer ya* y *por profesión*. Con 100+ recetas la tabla ordenada no basta. Un `EditBox` sobre la tabla y
   un filtro en `Session:EvaluateAll()` antes de ordenar.

2. **Precio de venta robusto** (S). Hoy se vende 1 cobre por debajo de la subasta más barata, aunque sea una sola
   unidad puesta a precio de saldo. Propuesta: ignorar las subastas por debajo de un porcentaje de la mediana de las
   primeras N unidades (por ejemplo, < 70 %) y mostrar en el tooltip de la columna *Venta* el precio usado y las
   subastas descartadas. Evita craftear por un precio que en realidad no existe.

3. **Competencia y cantidad recomendada** (S). Mostrar cuántas unidades del producto hay en venta (ya está en los
   listados escaneados) y avisar si eliges más crafteos de los que el mercado parece absorber ("hay 6 a la venta;
   publicar 20 bajará el precio"). Columna nueva *En venta* o dato en el detalle.

4. **Vender al vendedor cuando paga más** (S). El addon ya lee el precio de venta al vendedor del producto (para el
   depósito). Si es mayor que el beneficio neto de la subasta, decirlo en el resultado ("Mejor venderlo al vendedor:
   +12s").

5. **Recordar posición de la ventana entre sesiones** (S). Hoy solo se recuerda mientras dura la sesión
   (`UI.userMoved`). Guardar el punto de anclaje en `RicharsilusDB` y añadir `/rs reset` para volver a pegarla a la
   subasta.

6. **Opciones en la propia ventana** (S-M). Un botón de engranaje con rebaja, duración, contar depósito y comisión,
   en vez de solo comandos de chat. Se puede registrar además en el panel de opciones del juego
   (`Settings.RegisterCanvasLayoutCategory`, si existe en Forever).

### Prioridad media: cambian cómo se usa el addon

7. **Escaneo incremental** (M). Volver a escanear solo los objetos cuyo precio tenga más de X minutos (la hora ya se
   guarda en `RicharsilusDB.prices[itemID].t`) y un botón *Escanear esta receta* en el detalle. Ahorra minutos cuando
   hay muchas recetas.

8. **Historial y tendencia de precios** (M). Guardar el mínimo de cada escaneo (un valor por día, 30 días) y mostrar
   una flecha de tendencia y la media de 7 días en el tooltip. Evita craftear justo cuando el producto está caro de
   forma puntual o comprar materiales en un pico.

9. **Favoritos** (S-M). Fijar recetas arriba de la tabla (clic derecho o estrella) y un escaneo rápido solo de
   favoritos al abrir la subasta.

10. **Gestión de subastas propias** (M). Leer tus subastas (`C_AuctionHouse.GetOwnedAuctions`) y marcar las que alguien
    ha superado. Un botón *Cancelar superada* y otro *Volver a publicar*, uno por clic, igual que el resto de
    acciones.

11. **Registro de ganancias** (M). Apuntar lo que compras, publicas y vendes (eventos de compra y del correo de la
    subasta) para mostrar el beneficio real por receta y por día/semana, no solo el estimado.

### Prioridad baja o grande

12. **Cola de crafteo con varias recetas** (L). Añadir varias recetas con su cantidad a una cola; una única lista de la
    compra combinada (materiales compartidos sumados), *Comprar* recorre toda la lista y *Craftear* va receta a
    receta. Es la mejora más pedida en addons de este tipo, pero toca `Session`, la interfaz y las pruebas.

13. **Intermedios: fabricar o comprar** (L). Cuando un material es a su vez producto de una de tus recetas (barras,
    telas, viales), calcular si sale más barato fabricarlo y usar ese coste. Requiere un árbol de recetas y evitar
    ciclos.

14. **Materiales en el banco y en otros personajes** (M-L). Contar lo que hay en el banco (al abrirlo) y en tus alters
    (guardado por personaje) en la columna *Tienes*, con el detalle en el tooltip.

15. **Ventana redimensionable y escala** (M). Más filas visibles en pantallas grandes; hoy el tamaño es fijo
    (640 × 640).

## Orden sugerido

1. Buscador y filtros (1), precio robusto (2) y competencia (3): son los que más cambian la calidad de las decisiones.
2. Opciones en la ventana (6) y posición recordada (5): pulido que se nota a diario.
3. Escaneo incremental (7) y favoritos (9): tiempo ahorrado en cada visita a la subasta.
4. Historial (8), subastas propias (10) y registro de ganancias (11).
5. Cola de crafteo (12) e intermedios (13) como siguiente versión grande (1.x).

Antes de nada de esto conviene probar la 0.0.x en el cliente real (ver *Qué conviene comprobar en el juego* en el
README), porque varias propuestas dependen de APIs que solo se pueden confirmar allí.
