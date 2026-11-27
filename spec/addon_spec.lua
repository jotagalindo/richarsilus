-- Prueba de integración: carga el addon en el orden del TOC sobre un WoW simulado y recorre
-- el flujo completo con eventos y clics, comprobando qué funciones de Blizzard se llaman.
local stub = require("wow_stub")

local HERB = 6001
local VIAL = 6002
local ELIXIR = 5001
local RECIPE = 1001

-- Texto sin códigos de color (|cAARRGGBB ... |r), tal y como lo lee el jugador.
local function plain(text)
  return (string.gsub(string.gsub(text or "", "|c%x%x%x%x%x%x%x%x", ""), "|r", ""))
end

local function containsText(list, expected)
  for _, text in ipairs(list) do
    if string.find(text, expected, 1, true) then
      return true
    end
  end
  return false
end

local function fakeTradeSkill()
  return {
    GetAllRecipeIDs = function() return { RECIPE } end,
    GetBaseProfessionInfo = function() return { professionName = "Alquimia" } end,
    IsTradeSkillReady = function() return true end,
    GetRecipeInfo = function() return { recipeID = RECIPE, name = "Elixir de prueba", learned = true } end,
    GetRecipeSchematic = function()
      return {
        outputItemID = ELIXIR,
        quantityMin = 1,
        quantityMax = 1,
        reagentSlotSchematics = {
          { reagents = { { itemID = HERB } }, quantityRequired = 2, required = true, dataSlotType = 1, reagentType = 1 },
          { reagents = { { itemID = VIAL } }, quantityRequired = 1, required = true, dataSlotType = 1, reagentType = 1 },
        },
      }
    end,
  }
end

-- Fila de la tabla de materiales del detalle con ese nombre, como { name, needed, owned, ... } en texto plano.
local function materialRow(UI, name)
  for _, row in ipairs(UI.detail.materialRows) do
    if row:IsShown() and plain(row.cells.name:GetText()) == name then
      local cells = {}
      for key, cell in pairs(row.cells) do
        cells[key] = plain(cell:GetText())
      end
      return cells
    end
  end
  error("no material row for " .. name)
end

-- Líneas de la lista de la compra como "etiqueta = valor".
local function shoppingLines(UI)
  local lines = {}
  for _, line in ipairs(UI.detail.shopping) do
    local label = plain(line.label:GetText())
    if label ~= "" then
      lines[#lines + 1] = label .. " = " .. plain(line.value:GetText())
    end
  end
  local total = plain(UI.detail.shoppingTotal.label:GetText())
  if total ~= "" then
    lines[#lines + 1] = total .. " = " .. plain(UI.detail.shoppingTotal.value:GetText())
  end
  return lines
end

local function receiptLine(UI, key)
  local line = UI.detail.receipt[key]
  return plain(line.label:GetText()) .. " = " .. plain(line.value:GetText())
end

local function commodity(unitPrice, quantity)
  return { unitPrice = unitPrice, quantity = quantity, containsOwnerItem = false, auctionID = unitPrice }
end

-- Avanza el tiempo y contesta cada búsqueda que el escáner envía, hasta que termina.
local function runScan(ns)
  local answered = #stub.sentQueries
  for _ = 1, 100 do
    stub.update(0.2)
    if #stub.sentQueries > answered then
      answered = #stub.sentQueries
      stub.fire("COMMODITY_SEARCH_RESULTS_UPDATED", stub.sentQueries[answered])
    end
    if not ns.scanner:IsRunning() then
      return
    end
  end
  error("the scan did not finish")
end

describe("Richarsilus in a simulated client", function()
  local ns
  local UI

  before_each(function()
    stub.install({
      locale = "esES",
      mapID = 1453,
      itemNames = { [HERB] = "Hierba", [VIAL] = "Vial", [ELIXIR] = "Elixir de prueba" },
      merchant = { { itemID = VIAL, price = 20, stackCount = 1, numAvailable = -1, hasExtendedCost = false } },
      tradeSkill = fakeTradeSkill(),
    })
    ns = stub.loadAddon()
    UI = ns.UI
    stub.commodityResults[ELIXIR] = { commodity(500, 3) }
    stub.commodityResults[HERB] = { commodity(30, 10) }
    stub.commodityResults[VIAL] = {}
  end)

  it("goes from learning recipes to buying, crafting and posting", function()
    stub.fire("PLAYER_LOGIN")
    assert.is_function(SlashCmdList.RICHARSILUS)
    assert.are.equal("Escanear", ns.L.SCAN)

    stub.fire("TRADE_SKILL_SHOW")
    assert.is_true(containsText(stub.chat, "Alquimia: 1 recetas guardadas."))

    stub.fire("MERCHANT_SHOW")
    assert.are.equal(20, ns.priceDB:GetVendorPrice(VIAL))

    stub.fire("AUCTION_HOUSE_SHOW")
    local frame = _G.RicharsilusFrame
    assert.is_true(frame:IsShown())
    assert.are.equal(AuctionHouseFrame, frame.point[2])
    assert.are.equal("Comisión 5% (auto)", UI.cutButton:GetText())

    UI.scanButton:Click()
    runScan(ns)
    stub.update(0.2)
    assert.are.same({ ELIXIR, HERB, VIAL }, stub.sentQueries)
    assert.is_true(containsText(stub.chat, "Escaneo terminado: 3 objetos (0 sin respuesta)."))

    local row = UI.rows[1]
    assert.are.equal("Elixir de prueba", row.cells.product:GetText())
    assert.are.equal("80c", plain(row.cells.cost:GetText()))
    -- 499 venta - 25 comisión - 80 materiales - 5 depósito = 389
    assert.is_truthy(string.find(row.cells.profit:GetText(), "3s 89c", 1, true))

    -- La receta más rentable queda elegida sin hacer clic.
    assert.are.equal(RECIPE, UI.selectedRecipeID)
    row:Click()
    assert.are.equal("Comprar 2 Hierba (60c)", UI.detail.buy:GetText())
    assert.are.equal("primary", UI.detail.buy.style)
    assert.are.same({
      Hierba = { name = "Hierba", needed = "2", owned = "0", toBuy = "2", source = "Subasta", cost = "60c" },
    }, { Hierba = materialRow(UI, "Hierba") })
    assert.are.same({ "Subasta: 2 Hierba = 60c", "Vendedor: 1 Vial = 20c", "Total a gastar = 80c" }, shoppingLines(UI))
    assert.are.equal("Siguiente paso: compra los materiales que faltan (un material por clic).",
      plain(UI.detail.message:GetText()))

    -- Compra en dos clics, como la interfaz de Blizzard.
    UI.detail.buy:Click()
    assert.are.same({ HERB, 2, 30 }, stub.lastCall("StartCommoditiesPurchase").args)
    assert.is_false(UI.detail.buy:IsEnabled())
    stub.fire("COMMODITY_PRICE_UPDATED", 30, 60)
    stub.update(0.2)
    assert.are.equal("Confirmar 60c", UI.detail.buy:GetText())
    assert.is_true(UI.detail.cancel:IsEnabled())
    UI.detail.buy:Click()
    assert.are.same({ HERB, 2 }, stub.lastCall("ConfirmCommoditiesPurchase").args)
    stub.addToBags(HERB, 2)
    stub.fire("COMMODITY_PURCHASE_SUCCEEDED")
    assert.is_true(containsText(stub.chat, "Comprado: Hierba."))
    runScan(ns)
    stub.update(0.2)

    -- El vial se compra al vendedor: no hay nada más que comprar en la subasta.
    assert.are.equal("Nada que comprar", UI.detail.buy:GetText())
    assert.is_false(UI.detail.buy:IsEnabled())
    local herb = materialRow(UI, "Hierba")
    assert.are.same({ "2", "2", "-", "En tus bolsas" }, { herb.needed, herb.owned, herb.toBuy, herb.source })
    local vial = materialRow(UI, "Vial")
    assert.are.same({ "1", "0", "1", "Vendedor", "20c" }, { vial.needed, vial.owned, vial.toBuy, vial.source, vial.cost })
    assert.are.same({ "Vendedor: 1 Vial = 20c", "Total a gastar = 20c" }, shoppingLines(UI))
    assert.are.equal("Compra al vendedor de tu profesión: 1 Vial.", plain(UI.detail.message:GetText()))

    stub.addToBags(VIAL, 1)
    stub.fire("BAG_UPDATE_DELAYED")
    stub.update(0.2)
    assert.are.equal("Craftear 1", UI.detail.craft:GetText())
    assert.are.equal("primary", UI.detail.craft.style)
    assert.are.equal("secondary", UI.detail.buy.style)
    UI.detail.craft:Click()
    assert.are.same({ RECIPE, 1 }, stub.lastCall("CraftRecipe").args)

    stub.fire("TRADE_SKILL_CLOSE")
    stub.update(0.2)
    UI.detail.craft:Click()
    assert.are.equal(1, #(function()
      local crafts = {}
      for _, call in ipairs(stub.calls) do
        if call.name == "CraftRecipe" then crafts[#crafts + 1] = call end
      end
      return crafts
    end)())
    assert.are.equal("Abre la ventana de Alquimia para craftear.", UI.message)

    -- El crafteo gasta los materiales y deja el elixir en las bolsas.
    stub.bags = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {} }
    stub.addToBags(ELIXIR, 1)
    stub.fire("BAG_UPDATE_DELAYED")
    stub.update(0.2)
    assert.are.equal("Publicar 1", UI.detail.post:GetText())
    assert.are.equal("primary", UI.detail.post.style)
    UI.detail.post:Click()
    local postCall = stub.lastCall("PostCommodity")
    assert.are.same({ { bag = 0, slot = 1 }, 2, 1, 499 }, postCall.args)
    stub.fire("AUCTION_HOUSE_AUCTION_CREATED", 99)
    assert.is_true(containsText(stub.chat, "Publicado: Elixir de prueba."))

    SlashCmdList.RICHARSILUS("comision 15")
    assert.are.equal("Comisión 15% (manual)", UI.cutButton:GetText())
    assert.are.equal(0.15, RicharsilusDB.settings.cut)

    stub.fire("AUCTION_HOUSE_CLOSED")
    assert.is_false(frame:IsShown())
  end)

  it("cancels a purchase whose price rose and never confirms it", function()
    stub.fire("PLAYER_LOGIN")
    stub.fire("TRADE_SKILL_SHOW")
    stub.fire("AUCTION_HOUSE_SHOW")
    UI.scanButton:Click()
    runScan(ns)
    stub.update(0.2)
    UI.rows[1]:Click()

    UI.detail.buy:Click()
    stub.fire("COMMODITY_PRICE_UPDATED", 40, 80)
    stub.update(0.2)
    assert.is_not_nil(stub.lastCall("CancelCommoditiesPurchase"))
    assert.is_nil(stub.lastCall("ConfirmCommoditiesPurchase"))
    assert.are.equal("El precio ha subido más de un 5%. Vuelve a escanear.", UI.message)
  end)

  it("learns the deposit of an item that does not stack and remembers it after selling it", function()
    -- Para un objeto no apilable el juego no calcula el depósito por su ID.
    _G.C_AuctionHouse.CalculateCommodityDeposit = function() return nil end
    stub.fire("PLAYER_LOGIN")
    stub.fire("TRADE_SKILL_SHOW")
    stub.fire("AUCTION_HOUSE_SHOW")
    UI.scanButton:Click()
    runScan(ns)
    -- El elixir resulta no apilable: el juego solo da su depósito si hay uno en las bolsas.
    ns.priceDB:SetListings(ELIXIR, { { unitPrice = 500, quantity = 1, own = false, auctionID = 7, buyout = 500 } }, false)
    stub.update(0.2)
    UI.rows[1]:Click()
    assert.are.equal("Depósito 8 h (desconocido) = ?", receiptLine(UI, "deposit"))
    assert.are.equal("Desconocido hasta que tengas uno en las bolsas: el juego solo lo da para lo que llevas.",
      UI.detail.depositRow.tooltip.lines[2])

    stub.addToBags(ELIXIR, 1)
    stub.fire("BAG_UPDATE_DELAYED")
    stub.update(0.2)
    assert.are.equal("Depósito 8 h = -5c", receiptLine(UI, "deposit"))

    stub.bags = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {} }
    stub.fire("BAG_UPDATE_DELAYED")
    stub.update(0.2)
    assert.are.equal("Depósito 8 h = -5c", receiptLine(UI, "deposit"))
    assert.are.equal(5, RicharsilusDB.deposits.items[ELIXIR]["2:faction"])
  end)

  it("asks to learn recipes before scanning", function()
    stub.fire("PLAYER_LOGIN")
    stub.fire("AUCTION_HOUSE_SHOW")
    assert.is_false(UI.scanButton:IsEnabled())
    assert.are.equal("Abre una vez la ventana de tu profesión para que aprenda tus recetas.", UI.statusText:GetText())
    assert.is_truthy(string.find(UI.emptyText:GetText(), "Aún no conozco tus recetas", 1, true))
    assert.is_false(UI.detail.content:IsShown())
    SlashCmdList.RICHARSILUS("escanear")
    assert.is_true(containsText(stub.chat, "Abre una vez la ventana de tu profesión"))
    assert.are.same({}, stub.sentQueries)
  end)

  it("shows the scan progress and the time of the last full scan", function()
    stub.fire("PLAYER_LOGIN")
    stub.fire("TRADE_SKILL_SHOW")
    stub.fire("MERCHANT_SHOW")
    stub.fire("AUCTION_HOUSE_SHOW")
    assert.are.equal("Pulsa Escanear para consultar los precios actuales de la subasta.", UI.statusText:GetText())
    assert.are.equal("primary", UI.scanButton.style)
    UI.scanButton:Click()
    UI.FlushRefresh()
    assert.are.equal("Escaneando 0/3...", UI.statusText:GetText())
    assert.is_false(UI.scanButton:IsEnabled())
    runScan(ns)
    stub.update(0.2)
    -- time() del cliente simulado = 1700000000 = 22:13 UTC.
    assert.are.equal("Precios de las 22:13", UI.statusText:GetText())
    assert.are.equal("secondary", UI.scanButton.style)
    assert.are.equal("Rentables: 1 de 1", UI.subtitle:GetText())
  end)

  it("sorts the table when a column header is clicked and remembers it", function()
    stub.fire("PLAYER_LOGIN")
    stub.fire("TRADE_SKILL_SHOW")
    stub.fire("AUCTION_HOUSE_SHOW")
    UI.headers.cost:Click()
    assert.are.equal("cost", RicharsilusDB.settings.sortKey)
    assert.is_true(UI.headers.cost.underline:IsShown())
    assert.is_false(UI.headers.profit.underline:IsShown())
  end)

  it("explains buttons and items with tooltips", function()
    stub.fire("PLAYER_LOGIN")
    stub.fire("TRADE_SKILL_SHOW")
    stub.fire("AUCTION_HOUSE_SHOW")
    UI.cutButton:GetScript("OnEnter")(UI.cutButton)
    assert.are.equal("Comisión de la casa de subastas", stub.tooltip.title)
    assert.is_true(stub.tooltip.shown)
    UI.cutButton:GetScript("OnLeave")(UI.cutButton)
    assert.is_false(stub.tooltip.shown)

    UI.rows[1]:GetScript("OnEnter")(UI.rows[1])
    assert.are.equal(ELIXIR, stub.tooltip.itemID)
    assert.is_true(UI.rows[1].hover:IsShown())
  end)

  it("uses the Forever auction durations (2, 8 and 24 hours)", function()
    stub.fire("PLAYER_LOGIN")
    stub.fire("TRADE_SKILL_SHOW")
    stub.fire("AUCTION_HOUSE_SHOW")
    assert.are.equal("Duración: 8 h (cámbiala con /rs duracion 2, 8 o 24; más horas = más depósito).",
      UI.detail.post.tooltip().lines[2])
    SlashCmdList.RICHARSILUS("duracion 24")
    assert.are.equal(3, RicharsilusDB.settings.duration)
    assert.is_true(containsText(stub.chat, "Duración de las subastas: 24 h."))
    assert.are.equal("Duración: 24 h (cámbiala con /rs duracion 2, 8 o 24; más horas = más depósito).",
      UI.detail.post.tooltip().lines[2])
  end)

  it("toggles the window with the slash command", function()
    stub.fire("PLAYER_LOGIN")
    SlashCmdList.RICHARSILUS("")
    assert.is_true(_G.RicharsilusFrame:IsShown())
    SlashCmdList.RICHARSILUS("")
    assert.is_false(_G.RicharsilusFrame:IsShown())
  end)
end)
