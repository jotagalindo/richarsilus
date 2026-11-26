-- Prueba de integración: carga el addon en el orden del TOC sobre un WoW simulado y recorre
-- el flujo completo con eventos y clics, comprobando qué funciones de Blizzard se llaman.
local stub = require("wow_stub")

local HERB = 6001
local VIAL = 6002
local ELIXIR = 5001
local RECIPE = 1001

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
    assert.are.equal("80c", row.cells.cost:GetText())
    -- 499 venta - 25 comisión - 80 materiales - 5 depósito = 389
    assert.is_truthy(string.find(row.cells.profit:GetText(), "3s 89c", 1, true))

    row:Click()
    assert.are.equal("Comprar 2 Hierba (60c)", UI.detail.buy:GetText())

    -- Compra en dos clics, como la interfaz de Blizzard.
    UI.detail.buy:Click()
    assert.are.same({ HERB, 2, 30 }, stub.lastCall("StartCommoditiesPurchase").args)
    assert.is_false(UI.detail.buy:IsEnabled())
    stub.fire("COMMODITY_PRICE_UPDATED", 30, 60)
    stub.update(0.2)
    assert.are.equal("Confirmar 60c", UI.detail.buy:GetText())
    UI.detail.buy:Click()
    assert.are.same({ HERB, 2 }, stub.lastCall("ConfirmCommoditiesPurchase").args)
    stub.addToBags(HERB, 2)
    stub.fire("COMMODITY_PURCHASE_SUCCEEDED")
    assert.is_true(containsText(stub.chat, "Comprado: Hierba."))
    runScan(ns)
    stub.update(0.2)

    -- El vial se compra al vendedor: no hay nada más que comprar en la subasta.
    assert.are.equal("Nada que comprar", UI.detail.buy:GetText())
    assert.is_truthy(string.find(UI.detail.materials:GetText(), "comprar al vendedor", 1, true))

    stub.addToBags(VIAL, 1)
    stub.fire("BAG_UPDATE_DELAYED")
    stub.update(0.2)
    assert.are.equal("Craftear 1", UI.detail.craft:GetText())
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

    stub.addToBags(ELIXIR, 1)
    stub.fire("BAG_UPDATE_DELAYED")
    stub.update(0.2)
    assert.are.equal("Publicar 1", UI.detail.post:GetText())
    UI.detail.post:Click()
    local postCall = stub.lastCall("PostCommodity")
    assert.are.same({ { bag = 0, slot = 3 }, 2, 1, 499 }, postCall.args)
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

  it("asks to learn recipes before scanning", function()
    stub.fire("PLAYER_LOGIN")
    stub.fire("AUCTION_HOUSE_SHOW")
    UI.scanButton:Click()
    assert.is_true(containsText(stub.chat, "Abre una vez la ventana de tu profesión"))
    assert.are.same({}, stub.sentQueries)
  end)

  it("toggles the window with the slash command", function()
    stub.fire("PLAYER_LOGIN")
    SlashCmdList.RICHARSILUS("")
    assert.is_true(_G.RicharsilusFrame:IsShown())
    SlashCmdList.RICHARSILUS("")
    assert.is_false(_G.RicharsilusFrame:IsShown())
  end)
end)
