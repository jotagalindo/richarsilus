# Richarsilus — diseño

Addon para **World of Warcraft: Forever** (cliente 1.60.x, `## Interface: 16001`) que ayuda a ganar oro
desde la casa de subastas con una profesión: compara el coste de los materiales con el precio de venta del
producto, descuenta comisión y depósito, y asiste (un clic = una acción) para comprar, craftear y publicar.

## Fuentes de la API

Verificado contra el código de interfaz oficial de Forever (mirror `Gethe/wow-ui-source`, rama `forever`,
build 1.60.1 71139):

- Subasta: `C_AuctionHouse` moderno. `SendSearchQuery(itemKey, sorts, separateOwnerItems)` (máx. 100/min,
  documentado "no usar para consultar toda la casa de subastas"), `GetCommoditySearchResultsQuantity`,
  `GetCommoditySearchResultInfo`, `HasFullCommoditySearchResults`, `GetItemSearchResultsQuantity`,
  `GetItemSearchResultInfo`, `HasFullItemSearchResults`, `IsThrottledMessageSystemReady`,
  `CalculateCommodityDeposit(itemID, duration, quantity)`.
- Compra de commodities en dos pasos (igual que `AuctionHouseBuyDialog` de Blizzard):
  `StartCommoditiesPurchase` → evento `COMMODITY_PRICE_UPDATED(unitPrice, totalPrice)` →
  `ConfirmCommoditiesPurchase`; `CancelCommoditiesPurchase` al cancelar.
  Blizzard marca "precio no disponible" si el precio sube más de un 5 % (`MAXIMUM_PREVIEW_PRICE_DIFFERENTIAL = 1.05`).
- Compra de objetos no-commodity: `PlaceBid(auctionID, buyout)`.
- Publicar: `PostCommodity(itemLocation, duration, quantity, unitPrice)` devuelve `needsConfirmation`;
  si es `true`, un segundo clic llama a `ConfirmPostCommodity` con los mismos argumentos.
- Profesiones: `C_TradeSkillUI` moderno. `GetFilteredRecipeIDs` (lo usa la UI de Blizzard),
  `GetRecipeInfo`, `GetRecipeSchematic(recipeID, false)` con `outputItemID`, `quantityMin/Max` y
  `reagentSlotSchematics` (`reagents[].itemID`, `quantityRequired`, `required`, `reagentType`,
  `dataSlotType`), `GetBaseProfessionInfo`, `CraftRecipe(recipeID, numCasts)`.
- Vendedor: `GetMerchantNumItems`, `GetMerchantItemID(i)`, `C_MerchantFrame.GetItemInfo(i)` (`price`, `stackCount`).
- No existe API para la comisión de la casa de subastas.

## Normas de Blizzard (obligatorias)

- Solo API del cliente; ningún programa externo, lectura de memoria ni envío de pulsaciones.
- Toda función protegida (`StartCommoditiesPurchase`, `ConfirmCommoditiesPurchase`, `PlaceBid`,
  `PostCommodity`, `ConfirmPostCommodity`, `CraftRecipe`) se llama **solo** desde el `OnClick` de un botón,
  una vez por clic. Nada de bucles, temporizadores ni eventos que encadenen acciones protegidas.
- El escaneo solo busca los ítems de las recetas conocidas, uno a uno, respetando
  `IsThrottledMessageSystemReady` y como máximo 60 búsquedas por minuto (margen bajo el límite de 100).
- Política de addons: gratuito, código legible sin ofuscar, sin anuncios ni peticiones de donativos en el juego.

## Reglas de cálculo

Para una receta y un número de crafteos `n`:

- **Producción** por crafteo = `quantityMin` (conservador).
- **Coste de cada material** = el menor de: precio de vendedor conocido, o coste real de comprar la cantidad
  necesaria recorriendo las subastas de más barata a más cara. Los materiales que ya están en la bolsa se
  valoran a precio de subasta (coste de oportunidad); si no hay subastas, a precio de vendedor; si no hay
  ninguno, la receta queda marcada "sin precio" y no se ordena como rentable.
- **Precio de venta unitario** = subasta más barata del producto − rebaja (por defecto 1 cobre); si la más
  barata es tuya, se iguala a ella. Sin subastas del producto → "sin precio de venta".
- **Comisión** = 5 % (casa de subastas de facción) o 15 % (neutral). Detección automática por mapa
  (Tanaris, Cuna del Invierno, Cabo de Tuercespina / Tuercespina) con selector manual en la UI y `/rs comision`.
- **Depósito** = `CalculateCommodityDeposit(outputItemID, duración, unidades)` dado por el juego para lo que se
  apila. Para lo que no se apila, `CalculateItemDeposit` solo funciona con el objeto en las bolsas: cada valor del
  juego se guarda (`Core/Deposit.lua`, por duración y tipo de casa de subastas) y, para objetos nunca vistos, se
  estima con el precio de venta al vendedor × la proporción aprendida (con el depósito más bajo visto como mínimo).
  La interfaz marca el depósito como estimado o desconocido. Se devuelve si se vende; por defecto cuenta como coste
  (opción `/rs deposito on|off`).
- **Recetas repetidas**: el juego puede dar dos recetas distintas para el mismo producto con los mismos materiales,
  o el nombre de la profesión de dos formas. La tabla muestra una sola entrada por recipeID y por
  producto + materiales.
- **Beneficio** = `venta × unidades × (1 − comisión) − coste materiales − depósito`.
  **Margen** = beneficio / coste materiales.

## Módulos

Todos comparten la tabla del addon (`local _, ns = ...`). La lógica pura no toca globales de WoW.

| Fichero | Responsabilidad |
|---|---|
| `Richarsilus/Richarsilus.toc` | Metadatos, `## Interface: 16001`, `SavedVariables: RicharsilusDB`, orden de carga |
| `Core/Init.lua` | Tabla `ns`, valores por defecto, base de datos guardada — puro |
| `Core/Session.lua` | Comisión actual, ranking de recetas, siguiente compra, precio de publicación — puro |
| `Core/Events.lua` | Crea los módulos con la API real y reparte los eventos del juego |
| `Core/Money.lua` | Formato de dinero (oro/plata/cobre) — puro |
| `Core/Pricing.lua` | Recorrer subastas, coste de materiales, venta, comisión, depósito, beneficio — puro |
| `Core/PriceDB.lua` | Precios escaneados (en memoria: listados; guardado: mínimo y fecha) y precios de vendedor |
| `Core/Deposit.lua` | Depósitos aprendidos del juego y estimados para objetos no apilables — puro |
| `Core/RecipeDB.lua` | Lee recetas aprendidas con producto desde `C_TradeSkillUI` y las guarda por personaje |
| `Core/Scanner.lua` | Cola de búsquedas con límite de ritmo y lectura de resultados commodity/objeto |
| `Core/Inventory.lua` | Contar ítems en bolsas y localizar un `ItemLocation` para publicar |
| `Core/Actions.lua` | Máquinas de estado de compra (inicio/confirmación), crafteo y publicación |
| `Core/Commands.lua` | `/rs` y `/richarsilus` |
| `Locales/enUS.lua`, `Locales/esES.lua` | Textos (esES también para esMX) |
| `UI/MainFrame.lua` | Ventana junto a la casa de subastas: barra de estado, tabla de recetas, panel de detalle |

## Interfaz

- Ventana movible anclada a la derecha de `AuctionHouseFrame` al abrir la subasta; `/rs` la muestra/oculta.
- Barra superior: botón **Escanear**, progreso, comisión actual (clic para alternar 5 %/15 %), aviso si no hay recetas.
- Tabla ordenada por beneficio: producto, coste, venta, beneficio, margen, cuántos puedes craftear ya.
- Detalle de la receta seleccionada: selector de cantidad (±), lista de la compra (tienes / necesitas / comprar /
  coste), botones **Comprar siguiente** → **Confirmar (precio)**, **Craftear N** (requiere ventana de profesión
  abierta), **Publicar** → **Confirmar publicación** si el juego la pide.
- Si el precio de compra confirmado supera en más de un 5 % al esperado, no se ofrece confirmar: se cancela y
  se pide reescanear.

## Errores

- Sin recetas guardadas: mensaje "abre tu profesión una vez".
- Escaneo interrumpido al cerrar la subasta: la cola se vacía y se informa.
- Ítem sin información cargada: se reintenta al recibir `ITEM_KEY_ITEM_INFO_RECEIVED`/`GET_ITEM_INFO_RECEIVED`.
- Fallos de compra/publicación (`COMMODITY_PURCHASE_FAILED`, `AUCTION_HOUSE_POST_ERROR`): mensaje y estado reiniciado.

## Pruebas

- `busted` para `Money`, `Pricing`, `PriceDB`, `RecipeDB`, `Scanner`, `Actions` con dobles de `C_AuctionHouse`,
  `C_TradeSkillUI` y `C_Container`.
- `luacheck` con la lista de globales de WoW usadas.
- Todo se ejecuta en el contenedor `tools/Dockerfile` (Lua 5.1 como el cliente).
- CI en GitHub Actions (`.github/workflows/ci.yml`): luacheck, shellcheck, actionlint, busted y empaquetado.
- Releases (`.github/workflows/release.yml`): una etiqueta `vX.Y.Z` igual a `## Version:` del TOC publica el zip
  generado por `tools/package.sh`, que antes comprueba que el TOC y los ficheros `.lua` coinciden. Las versiones
  0.x son beta (pendientes de probar en el cliente real) y se publican como prerelease.
