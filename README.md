# Richarsilus

Addon para **World of Warcraft: Forever** que te dice qué crafteos dan dinero comprando los materiales en la
casa de subastas y vendiendo el resultado allí mismo, y te ayuda a hacerlo: un clic por acción.

- Lee tus recetas aprendidas de cualquier profesión (Alquimia, Sastrería, Herrería...).
- Escanea en la subasta solo los materiales y productos de tus recetas.
- Calcula el beneficio real: venta − **comisión** de la casa de subastas − **depósito** − materiales.
- Te arma la lista de la compra y te deja comprar, craftear y publicar con botones.

## Instalación

1. Copia la carpeta `Richarsilus` (la que contiene `Richarsilus.toc`) dentro de `Interface\AddOns` del cliente de
   Forever. Para encontrarla: launcher de Battle.net → WoW: Forever → ⚙ → *Mostrar en el explorador*.
   Si `Interface\AddOns` no existe, créala.
2. Entra en el juego y comprueba en *AddOns* (pantalla de selección de personaje) que Richarsilus está activado.

## Uso

1. **Abre la ventana de tu profesión** una vez. El addon guarda tus recetas (verás
   `Alquimia: N recetas guardadas` en el chat). Repítelo cuando aprendas recetas nuevas.
2. *(Opcional)* **Habla con un vendedor de suministros** (frascos, hilos...). El addon apunta sus precios y, si son
   más baratos que la subasta, te dirá "comprar al vendedor".
3. **Ve a la casa de subastas.** La ventana de Richarsilus se abre a su lado. Pulsa **Escanear** (tarda ~1 s por objeto).
4. La tabla queda ordenada por **beneficio**. *Puedes* = cuántos crafteos puedes hacer con lo que ya llevas.
5. Elige una receta y la cantidad de crafteos con **− / +** (Mayús = de 10 en 10). Verás cada material: cuánto
   necesitas, cuánto tienes, cuánto comprar y dónde.
6. **Comprar**: el primer clic pide precio al servidor; el segundo (*Confirmar X*) compra. Si el precio ha subido más
   de un 5 % el addon cancela solo y te pide volver a escanear (igual que la interfaz de Blizzard).
7. **Craftear**: abre la ventana de la profesión (puedes hacerlo en la misma subasta) y pulsa *Craftear N*.
8. **Publicar**: publica todo lo que tengas del producto a 1 cobre por debajo de la subasta ajena más barata (o igual
   que la tuya si la más barata ya es tuya). Si el juego pide confirmación, pulsa otra vez.

## Cómo calcula

| Concepto | Regla |
|---|---|
| Materiales que compras | Se recorren las subastas de más barata a más cara para la cantidad exacta (comprar 20 hierbas cuesta lo que cuestan esas 20, no 20 × la más barata). Tus propias subastas no cuentan. Si el vendedor es más barato, se usa el vendedor. |
| Materiales que ya tienes | Valen su precio de mercado (lo que ganarías vendiéndolos). Así, si la hierba vale más que la poción, lo verás. |
| Precio de venta | Subasta ajena más barata − rebaja (1 cobre por defecto). |
| Comisión | 5 % en casas de subastas de facción, 15 % en las neutrales (Gadgetzan, Bahía del Botín, Vista Eterna). Se detecta por zona; el botón de la comisión la cambia a mano (auto → 5 % → 15 %). |
| Depósito | El que calcula el propio juego para la duración elegida. Se te devuelve si vendes, pero por defecto cuenta como coste (opción conservadora). |
| Producción | Se usa la cantidad mínima que da la receta. |

## Comandos

| Comando | Qué hace |
|---|---|
| `/rs` | Muestra u oculta la ventana |
| `/rs escanear` | Escanea (con la subasta abierta) |
| `/rs comision 5\|15\|auto` | Fija la comisión |
| `/rs rebaja <cobre>` | Cuánto rebajar al publicar (por defecto 1) |
| `/rs deposito on\|off` | Contar o no el depósito como coste |
| `/rs duracion 12\|24\|48` | Duración de las subastas (por defecto 24 h) |
| `/rs olvidar` | Borra las recetas guardadas de este personaje |

También funcionan en inglés (`scan`, `cut`, `undercut`, `deposit`, `duration`, `forget`) y con `/richarsilus`.

## Normas de Blizzard

El addon está hecho para cumplir los Términos de uso y la política de addons de Blizzard:

- Solo usa la API del propio juego. No hay programas externos, ni lectura de memoria, ni simulación de teclas.
- **Toda compra, crafteo y publicación es un clic tuyo**, y cada clic hace una sola acción. Ningún evento,
  temporizador ni bucle compra, confirma, craftea o publica por ti (puedes comprobarlo: esas llamadas solo están en
  `Core/Actions.lua` y solo se invocan desde los `OnClick` de `UI/MainFrame.lua`).
- El escaneo busca únicamente los objetos de tus recetas, uno a uno, a un ritmo máximo de 60 búsquedas por minuto
  (el límite documentado por Blizzard es 100/min) y respetando su sistema de espera.
- Es gratuito, el código es legible y no contiene anuncios ni peticiones de donativos.

## Qué conviene comprobar en el juego

El código se ha verificado contra la interfaz oficial de Forever (build 1.60.1) y con pruebas automáticas sobre un
cliente simulado, pero no en el cliente real. La primera vez que lo uses, fíjate en:

- Que tras abrir la profesión aparezca el mensaje de recetas guardadas.
- Que la comisión mostrada coincida con la casa de subastas en la que estás (si no, cámbiala con el botón).
- Que el depósito mostrado coincida con el que enseña la ventana de venta de Blizzard.

Si algo falla, `/console scriptErrors 1` muestra los errores de Lua en pantalla.

## Desarrollo

Requisitos: Docker. El contenedor trae Lua 5.1 (la versión del cliente), [busted](https://lunarmodules.github.io/busted/)
y [luacheck](https://github.com/lunarmodules/luacheck).

```powershell
docker build -t richarsilus-dev tools
```

```powershell
docker run --rm -v "${PWD}:/addon" richarsilus-dev
```

El segundo comando ejecuta `luacheck .` y `busted`. Las pruebas están en `spec/`: unitarias por módulo y
`spec/addon_spec.lua`, que carga el addon en el orden del TOC sobre un cliente simulado (`spec/helpers/wow_stub.lua`)
y recorre el flujo completo de escanear, comprar, craftear y publicar.

| Fichero | Responsabilidad |
|---|---|
| `Core/Init.lua` | Tabla del addon, valores por defecto, base de datos guardada |
| `Core/Money.lua` | Formato `1g 2s 3c` |
| `Core/Pricing.lua` | Cálculo de costes, venta, comisión, depósito y beneficio |
| `Core/PriceDB.lua` | Precios escaneados y de vendedor |
| `Core/RecipeDB.lua` | Recetas leídas de `C_TradeSkillUI` |
| `Core/Scanner.lua` | Escaneo con límite de ritmo |
| `Core/Inventory.lua` | Bolsas |
| `Core/Actions.lua` | Compra, publicación y crafteo (únicas llamadas protegidas) |
| `Core/Session.lua` | Une todo lo anterior para la interfaz |
| `Core/Commands.lua` | `/rs` |
| `Core/Events.lua` | Eventos del juego |
| `UI/MainFrame.lua` | Ventana |

Diseño: [docs/superpowers/specs/2026-11-26-richarsilus-design.md](docs/superpowers/specs/2026-11-26-richarsilus-design.md).
