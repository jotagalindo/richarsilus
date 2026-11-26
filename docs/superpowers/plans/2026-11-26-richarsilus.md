# Richarsilus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Addon de WoW: Forever que calcula la rentabilidad de craftear con tus recetas comprando en la subasta y asiste con compra, crafteo y publicación de un clic por acción.

**Architecture:** Módulos Lua 5.1 compartiendo la tabla `ns` del addon. La lógica (precios, recetas, escaneo, acciones) recibe la API de WoW inyectada (`C_AuctionHouse`, `C_TradeSkillUI`, contenedores) para poder probarla con dobles en `busted`. La UI es una ventana Lua pura que llama a esos módulos.

**Tech Stack:** Lua 5.1, API de WoW Forever (Interface 16001), busted, luacheck, Docker (`tools/Dockerfile`).

Especificación: `docs/superpowers/specs/2026-11-26-richarsilus-design.md`.

Comando de verificación (desde la raíz del repo):

```powershell
docker run --rm -v "${PWD}:/addon" richarsilus-dev
```

Ejecuta `luacheck .` y `busted`. Esperado: `0 warnings / 0 errors` y `N successes / 0 failures / 0 errors`.

---

## Estructura de ficheros

```
Richarsilus/
  Richarsilus.toc
  Core/Init.lua        ns, defaults, DB, bus de eventos
  Core/Money.lua       ns.Money.Format(copper)
  Core/Pricing.lua     ns.Pricing.*
  Core/PriceDB.lua     ns.PriceDB.New(saved, clock)
  Core/RecipeDB.lua    ns.RecipeDB.New(store); ns.RecipeDB.ReadOpenProfession(api, enum)
  Core/Scanner.lua     ns.Scanner.New(api, priceDB, clock, sorts)
  Core/Inventory.lua   ns.Inventory.New(itemApi, containerApi, makeLocation, bagIDs)
  Core/Actions.lua     ns.Actions.NewPurchase / NewPost / Craft
  Core/Session.lua     ns.Session.New(deps): comisión, ranking, siguiente compra (añadido al implementar)
  Core/Commands.lua    /rs
  Core/Events.lua      creación de módulos con la API real y reparto de eventos (añadido al implementar)
  Locales/enUS.lua, Locales/esES.lua
  UI/MainFrame.lua
spec/                  tests busted (+ spec/helpers/loader.lua, spec/helpers/wow_stub.lua)
.luacheckrc, .busted
```

## Interfaces (contrato entre tareas)

```lua
-- listing = { unitPrice = number, quantity = number, own = bool, auctionID = number }
ns.Money.Format(copper) --> "12g 3s 4c" (omite partes a cero a la izquierda; "0c"; negativo con "-")

ns.Pricing.BuyCost(listings, quantity) --> totalCost, boughtQuantity
ns.Pricing.SalePrice(listings, undercut) --> unitPrice | nil
ns.Pricing.MaterialCost{ needed, owned, listings, vendorPrice }
  --> { needed, ownedUsed, toBuy, ownedValue, buyCost, cost, source = "vendor"|"auction"|"owned"|"none", complete }
ns.Pricing.Evaluate(recipe, crafts, ctx) --> result
  -- recipe = { recipeID, name, outputItemID, quantityMin, reagents = { { itemID, quantity } } }
  -- ctx = { listings(itemID), vendorPrice(itemID), owned(itemID), cut, undercut, deposit(itemID, units), includeDeposit }
  -- result = { recipe, crafts, units, materials, materialCost, salePrice, gross, cutAmount, deposit,
  --            profit, margin, status = "ok"|"no_sale_price"|"missing_materials" }
ns.Pricing.MaxCraftable(recipe, owned) --> number

PriceDB:SetListings(itemID, listings, isCommodity) / :GetListings(itemID) / :GetMinPrice(itemID) --> price, time
PriceDB:IsCommodity(itemID) / :SetVendorPrice(itemID, unitPrice) / :GetVendorPrice(itemID)

ns.RecipeDB.ReadOpenProfession(api) --> professionName, recipes
RecipeDB:SaveProfession(name, recipes) / :AllRecipes() / :GetRecipe(recipeID) / :ItemIDsToScan() / :HasRecipes()

Scanner:Start(itemIDs) / :Stop() / :Tick() / :OnEvent(event, ...) / :IsRunning() / :Progress() --> done, total
Scanner.onProgress(done, total), Scanner.onFinished(done, total, aborted)

Inventory:Count(itemID) / :FindItemLocation(itemID) --> ItemLocation | nil

Purchase:Begin(item) / :Confirm() / :Cancel() / :OnEvent(event, ...) / .state
  -- item = { itemID, quantity, expectedTotal, isCommodity, auctionID, buyout }
Post:Begin(itemID, quantity, unitPrice, duration) / :Confirm() / :OnEvent(event, ...) / .state
ns.Actions.Craft(api, isProfessionOpen, recipeID, count) --> ok, reasonKey
```

---

### Task 1: Herramientas y esqueleto

**Files:** Create `.luacheckrc`, `.busted`, `spec/helpers/loader.lua`, `Richarsilus/Richarsilus.toc`, `Richarsilus/Core/Init.lua`, `Richarsilus/Locales/enUS.lua`, `Richarsilus/Locales/esES.lua`, `spec/init_spec.lua`.

- [ ] Test: `loader.load({"Core/Init.lua"})` devuelve `ns` con `ns.defaults.cut == "auto"`, `ns.defaults.undercut == 1`, `ns.defaults.duration == 2`, `ns.defaults.includeDeposit == true`; `ns.InitDB(nil)` devuelve tabla con esos valores y `ns.InitDB({undercut = 5}).undercut == 5`; `ns.L.SCAN` devuelve una cadena (fallback a la clave si falta).
- [ ] Ejecutar → falla (no existe). Implementar. Ejecutar → pasa.

### Task 2: Money

- [ ] Tests: `Format(0) == "0c"`, `Format(5) == "5c"`, `Format(10203) == "1g 2s 3c"`, `Format(10000) == "1g"`, `Format(150) == "1s 50c"`, `Format(-250) == "-2s 50c"`, `Format(12.6)` redondea a `"13c"`.
- [ ] Implementar `Core/Money.lua`. Pasar.

### Task 3: Pricing

- [ ] Tests `BuyCost`: listados `{10x5,20x5}` y 7 → `90, 7`; cantidad 0 → `0, 0`; más de lo disponible → coste de todo, cantidad disponible.
- [ ] Tests `SalePrice`: vacío → nil; más barato ajeno 100 y rebaja 1 → 99; más barato propio 100 → 100; rebaja mayor que el precio → 1.
- [ ] Tests `MaterialCost`: vendedor 50 vs subastas 40 → `source="auction"`; vendedor 30 vs subastas 40 → `"vendor"`; todo en bolsa → `toBuy=0`, `ownedValue = owned * min(subasta, vendedor)`, `source="owned"`; sin subastas ni vendedor y faltan → `complete=false`, `source="none"`; subastas insuficientes sin vendedor → `complete=false`.
- [ ] Tests `Evaluate`: receta 2×A(10c)+1×B(vendedor 5c) → 1 unidad; venta más barata 100 ajena, rebaja 1, comisión 0.05, depósito 3 → `gross=99`, `cutAmount=5` (`floor(99*0.05+0.5)`), `profit = 99-5-25-3 = 66`; con `includeDeposit=false` → 69; sin listados del producto → `status="no_sale_price"`; material sin precio → `status="missing_materials"`; `crafts=3` y `quantityMin=2` → `units=6`.
- [ ] Tests `MaxCraftable`: 7 de A (necesita 2) y 10 de B (necesita 1) → 3.
- [ ] Implementar `Core/Pricing.lua`. Pasar.

### Task 4: PriceDB

- [ ] Tests: `SetListings(1, {{unitPrice=30},{unitPrice=10}}, true)` ordena ascendente, `GetMinPrice(1) == 10` y fecha del reloj inyectado; persiste `saved.prices[1] = {min=10, t=...}`; un `PriceDB` nuevo sobre la misma tabla devuelve `GetMinPrice` guardado y `GetListings` vacío; `IsCommodity`; precios de vendedor.
- [ ] Implementar. Pasar.

### Task 5: RecipeDB

- [ ] Test `ReadOpenProfession` con doble de `C_TradeSkillUI`: incluye recetas `learned` con `outputItemID`; excluye no aprendidas, encantamiento, desguace, recrafteo, sin producto; reactivos solo de ranuras `required` con `dataSlotType` Reagent (1) y `reagentType` Basic (1); nombre de la profesión desde `GetBaseProfessionInfo().professionName`; usa `GetAllRecipeIDs` si existe, si no `GetFilteredRecipeIDs`.
- [ ] Tests de almacén: `SaveProfession` reemplaza la profesión, `AllRecipes` une profesiones, `ItemIDsToScan` sin duplicados y ordenado, `GetRecipe`, `HasRecipes`.
- [ ] Implementar. Pasar.

### Task 6: Scanner

- [ ] Tests con doble de `C_AuctionHouse` y reloj: `Start({1,2})` no envía hasta `Tick`; `Tick` envía si `IsThrottledMessageSystemReady()`; no envía dos seguidas antes de 1 s; `COMMODITY_SEARCH_RESULTS_UPDATED(1)` guarda listados (`own = containsOwnerItem`) como commodity y avanza; `ITEM_SEARCH_RESULTS_UPDATED({itemID=2})` guarda `unitPrice = buyoutAmount/quantity` ignorando subastas sin compra inmediata, no commodity; sin respuesta en 10 s se salta el ítem; al terminar llama `onFinished(2, 2, false)`; `Stop()` llama `onFinished(..., true)`; eventos de otro ítem se ignoran.
- [ ] Implementar. Pasar.

### Task 7: Inventory

- [ ] Tests: `Count` delega en `GetItemCount(itemID)`; `FindItemLocation` recorre bolsas y devuelve la ubicación de la primera ranura con ese `itemID`; nil si no hay.
- [ ] Implementar. Pasar.

### Task 8: Actions

- [ ] Tests compra commodity: `Begin` llama `StartCommoditiesPurchase(id, qty, unitEsperado)` y queda `quoting`; `COMMODITY_PRICE_UPDATED` ≤ 5 % más caro → `ready` con `quote`; > 5 % → `price_changed` y `CancelCommoditiesPurchase`; `Confirm` solo en `ready` llama `ConfirmCommoditiesPurchase` → `purchasing`; `COMMODITY_PURCHASE_SUCCEEDED` → `idle` y `onPurchased(itemID)`; `FAILED` → `failed`; `COMMODITY_PRICE_UNAVAILABLE` → `unavailable`.
- [ ] Tests compra objeto: `Begin{isCommodity=false, auctionID, buyout}` llama `PlaceBid(auctionID, buyout)` → `purchasing`; `AUCTION_HOUSE_PURCHASE_COMPLETED` → `idle`.
- [ ] Tests publicar: sin ítem en bolsas → `no_item`; commodity: `PostCommodity` devuelve false → `posted`; true → `confirm`, y `Confirm` llama `ConfirmPostCommodity` con los mismos argumentos; no-commodity usa `PostItem(loc, dur, 1, nil, buyout)`/`ConfirmPostItem`; `AUCTION_HOUSE_POST_ERROR` → `error`.
- [ ] Tests craftear: profesión cerrada → `false, "PROFESSION_CLOSED"`; abierta → `CraftRecipe(recipeID, count)` y `true`.
- [ ] Implementar. Pasar.

### Task 9: Comandos, eventos, UI y TOC

- [ ] `Core/Commands.lua`: `/rs`, `/richarsilus` con `escanear|scan`, `comision|cut 5|15|auto`, `rebaja|undercut <cobre>`, `deposito|deposit on|off`, `duracion|duration 12|24|48`, `ayuda|help`. Test del parser (`ns.ParseCommand`).
- [ ] `Core/Init.lua`: frame de eventos (`ADDON_LOADED`, `TRADE_SKILL_SHOW`, `TRADE_SKILL_LIST_UPDATE`, `TRADE_SKILL_CLOSE`, `AUCTION_HOUSE_SHOW`, `AUCTION_HOUSE_CLOSED`, `MERCHANT_SHOW`, eventos de subasta para Scanner/Actions) y detección de comisión por mapa.
- [ ] `UI/MainFrame.lua`: ventana con barra, tabla de 12 filas con rueda del ratón, panel de detalle y botones (solo `OnClick` llama acciones protegidas).
- [ ] `luacheck` sin avisos; `busted` en verde.

### Task 10: README

- [ ] `README.md` en español: instalación (carpeta `Richarsilus` en `Interface/AddOns` del cliente de Forever), uso paso a paso, comandos, cálculo, cumplimiento de normas, desarrollo con Docker.
