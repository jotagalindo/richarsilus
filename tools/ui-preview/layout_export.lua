-- Ejecuta el addon real sobre el cliente simulado (spec/helpers/wow_stub.lua) con datos de ejemplo
-- y exporta el diseño de la ventana (tamaños, anclajes, textos, botones activos) para dibujarla en
-- tools/ui-preview/preview.html. Las capturas del README salen de aquí: no son del juego.
local stub = require("wow_stub")

local exporter = {}

-- Datos de ejemplo (precios en cobre). Los IDs son ficticios. `color` es el tono con el que la vista
-- previa dibuja el icono (no tiene los iconos del juego).
local ITEMS = {
  dreamfoil = { id = 8001, name = "Flor de sueño", color = "#7fb24a" },
  bloodRoot = { id = 8002, name = "Raíz de sangre", color = "#b2453a" },
  graveMoss = { id = 8003, name = "Musgo de tumba", color = "#5f8a5a" },
  crystalVial = { id = 8004, name = "Vial de cristal", color = "#8fb6c9" },
  lotusPetal = { id = 8005, name = "Pétalo de loto", color = "#c98fc4" },
  blackLily = { id = 8006, name = "Lirio negro", color = "#5b4a7a" },
  imbuedVial = { id = 8007, name = "Vial imbuido", color = "#5aa0d6" },
  mongoose = { id = 7001, name = "Elixir de la mangosta", color = "#d2a13c" },
  manaPotion = { id = 7002, name = "Poción de maná superior", color = "#3f6fd8" },
  healingPotion = { id = 7003, name = "Poción de sanación superior", color = "#d84a4a" },
  agility = { id = 7004, name = "Elixir de agilidad mayor", color = "#4fb07a" },
  titans = { id = 7005, name = "Frasco de titanes", color = "#9a7bd0" },
  wisdom = { id = 7006, name = "Elixir de sabiduría", color = "#4fb6c4" },
}

-- El cliente simulado devuelve como icono 100000 + ID del objeto.
local ICON_BASE = 100000

local RECIPES = {
  { id = 2001, output = ITEMS.mongoose, reagents = { { ITEMS.dreamfoil, 2 }, { ITEMS.imbuedVial, 1 } } },
  { id = 2002, output = ITEMS.manaPotion, reagents = { { ITEMS.bloodRoot, 2 }, { ITEMS.imbuedVial, 1 } } },
  {
    id = 2003,
    output = ITEMS.healingPotion,
    reagents = { { ITEMS.bloodRoot, 1 }, { ITEMS.graveMoss, 1 }, { ITEMS.crystalVial, 1 } },
  },
  {
    id = 2004,
    output = ITEMS.agility,
    reagents = { { ITEMS.lotusPetal, 1 }, { ITEMS.dreamfoil, 1 }, { ITEMS.imbuedVial, 1 } },
  },
  { id = 2005, output = ITEMS.titans, reagents = { { ITEMS.blackLily, 30 }, { ITEMS.lotusPetal, 10 } } },
  { id = 2006, output = ITEMS.wisdom, reagents = { { ITEMS.graveMoss, 1 }, { ITEMS.crystalVial, 1 } } },
}

-- Subastas de cada objeto: { precio por unidad, cantidad }. Sin entrada = nadie lo vende.
local LISTINGS = {
  [ITEMS.dreamfoil.id] = { { 1200, 40 }, { 1250, 60 } },
  [ITEMS.bloodRoot.id] = { { 850, 25 }, { 900, 80 } },
  [ITEMS.graveMoss.id] = { { 2200, 12 } },
  [ITEMS.lotusPetal.id] = { { 1500, 20 } },
  [ITEMS.mongoose.id] = { { 14500, 6 }, { 14800, 10 } },
  [ITEMS.manaPotion.id] = { { 4200, 15 } },
  [ITEMS.healingPotion.id] = { { 2900, 30 } },
  [ITEMS.wisdom.id] = { { 3800, 8 } },
}

local VENDOR = {
  { itemID = ITEMS.imbuedVial.id, price = 1800, stackCount = 1, numAvailable = -1, hasExtendedCost = false },
  { itemID = ITEMS.crystalVial.id, price = 100, stackCount = 1, numAvailable = -1, hasExtendedCost = false },
}

local BAGS = {
  { ITEMS.dreamfoil.id, 6 },
  { ITEMS.imbuedVial.id, 2 },
  { ITEMS.bloodRoot.id, 3 },
}

local STORMWIND_MAP_ID = 1453
local SELECTED_CRAFTS = 5

local function tradeSkillFor(recipes)
  local byID = {}
  local recipeIDs = {}
  for _, recipe in ipairs(recipes) do
    byID[recipe.id] = recipe
    recipeIDs[#recipeIDs + 1] = recipe.id
  end
  return {
    GetAllRecipeIDs = function() return recipeIDs end,
    GetBaseProfessionInfo = function() return { professionName = "Alquimia" } end,
    IsTradeSkillReady = function() return true end,
    GetRecipeInfo = function(recipeID)
      return { recipeID = recipeID, name = byID[recipeID].output.name, learned = true }
    end,
    GetRecipeSchematic = function(recipeID)
      local slots = {}
      for _, reagent in ipairs(byID[recipeID].reagents) do
        slots[#slots + 1] = {
          reagents = { { itemID = reagent[1].id } },
          quantityRequired = reagent[2],
          required = true,
          dataSlotType = 1,
          reagentType = 1,
        }
      end
      return { outputItemID = byID[recipeID].output.id, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = slots }
    end,
  }
end

local function itemNames()
  local names = {}
  for _, item in pairs(ITEMS) do
    names[item.id] = item.name
  end
  return names
end

-- Contesta cada búsqueda del escáner hasta que termina, como hace spec/addon_spec.lua.
local function runScan(ns)
  local answered = #stub.sentQueries
  for _ = 1, 200 do
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

-- Copia el árbol de regiones en tablas planas con un id por región y anclajes por id.
local function iconColors()
  local colors = {}
  for _, item in pairs(ITEMS) do
    colors[tostring(ICON_BASE + item.id)] = item.color
  end
  return colors
end

local function snapshot(root)
  local ids = {}
  local ordered = {}

  local function assign(region)
    ordered[#ordered + 1] = region
    ids[region] = #ordered
    for _, child in ipairs(region.children) do
      assign(child)
    end
  end
  assign(root)

  local regions = {}
  for index, region in ipairs(ordered) do
    local exported = {
      id = index,
      kind = region.kind,
      template = region.template,
      parent = region.parent and ids[region.parent] or nil,
      width = region.width,
      height = region.height,
      text = region.text,
      shown = region.shown,
      enabled = region.enabled,
      justifyH = region.justifyH,
      justifyV = region.justifyV,
      spacing = region.spacing,
      wordWrap = region.wordWrap,
      color = region.color,
      textColor = region.textColor,
      texture = region.texture,
      layer = region.layer,
      allPoints = region.allPoints,
    }
    if region.points and region ~= root then
      exported.points = {}
      for pointIndex, point in ipairs(region.points) do
        if type(point[2]) == "table" then
          exported.points[pointIndex] = {
            point = point[1],
            relativeTo = assert(ids[point[2]], "anchored to a region outside the window"),
            relativePoint = point[3] or point[1],
            x = point[4] or 0,
            y = point[5] or 0,
          }
        else
          exported.points[pointIndex] = {
            point = point[1],
            relativeTo = exported.parent,
            relativePoint = point[1],
            x = point[2] or 0,
            y = point[3] or 0,
          }
        end
      end
    end
    regions[index] = exported
  end
  return { root = 1, regions = regions, iconColors = iconColors() }
end

-- Devuelve { { name = "main", layout = ... }, { name = "confirm", layout = ... } }.
function exporter.BuildScenes()
  stub.install({
    locale = "esES",
    mapID = STORMWIND_MAP_ID,
    itemNames = itemNames(),
    merchant = VENDOR,
    tradeSkill = tradeSkillFor(RECIPES),
  })
  local ns = stub.loadAddon()
  local UI = ns.UI

  for itemID, listings in pairs(LISTINGS) do
    local results = {}
    for index, listing in ipairs(listings) do
      results[index] = {
        unitPrice = listing[1],
        quantity = listing[2],
        containsOwnerItem = false,
        auctionID = itemID * 100 + index,
      }
    end
    stub.commodityResults[itemID] = results
  end
  for _, bagItem in ipairs(BAGS) do
    stub.addToBags(bagItem[1], bagItem[2])
  end

  stub.fire("PLAYER_LOGIN")
  stub.fire("TRADE_SKILL_SHOW")
  stub.fire("MERCHANT_SHOW")
  stub.fire("AUCTION_HOUSE_SHOW")
  UI.scanButton:Click()
  runScan(ns)
  stub.update(0.2)

  UI.rows[1]:Click()
  for _ = 2, SELECTED_CRAFTS do
    UI.detail.plus:Click()
  end
  stub.update(0.2)
  local scenes = { { name = "main", layout = snapshot(UI.frame) } }

  -- Primer clic de compra: el servidor responde con el precio y el botón pasa a "Confirmar".
  UI.detail.buy:Click()
  local purchaseCall = assert(stub.lastCall("StartCommoditiesPurchase"), "the buy button did not start a purchase")
  local quantity, unitPrice = purchaseCall.args[2], purchaseCall.args[3]
  stub.fire("COMMODITY_PRICE_UPDATED", unitPrice, unitPrice * quantity)
  stub.update(0.2)
  scenes[#scenes + 1] = { name = "confirm", layout = snapshot(UI.frame) }

  return scenes
end

---------------------------------------------------------------------------------------------
-- JSON (solo lo necesario: tablas, cadenas, números, booleanos)
---------------------------------------------------------------------------------------------
local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function encodeString(text)
  return '"' .. string.gsub(text, '[%c"\\]', function(character)
    return ESCAPES[character] or string.format("\\u%04x", string.byte(character))
  end) .. '"'
end

local function isArray(value)
  local count = 0
  for _ in pairs(value) do
    count = count + 1
  end
  for index = 1, count do
    if value[index] == nil then
      return false
    end
  end
  return true
end

function exporter.EncodeJson(value)
  local valueType = type(value)
  if valueType == "string" then
    return encodeString(value)
  elseif valueType == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      error("cannot encode a non-finite number")
    end
    if value == math.floor(value) then
      return string.format("%d", value)
    end
    return string.format("%.14g", value)
  elseif valueType == "boolean" then
    return tostring(value)
  elseif valueType == "nil" then
    return "null"
  elseif valueType == "table" then
    local parts = {}
    if next(value) ~= nil and isArray(value) then
      for index = 1, #value do
        parts[index] = exporter.EncodeJson(value[index])
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for key in pairs(value) do
      if type(key) ~= "string" then
        error("cannot encode a non-string object key: " .. tostring(key))
      end
      keys[#keys + 1] = key
    end
    table.sort(keys)
    for index, key in ipairs(keys) do
      parts[index] = encodeString(key) .. ":" .. exporter.EncodeJson(value[key])
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  error("cannot encode a " .. valueType)
end

-- Fichero que carga preview.html (con <script>, para que funcione abriéndolo con file://).
function exporter.ToJavaScript(scenes)
  local byName = {}
  for _, scene in ipairs(scenes) do
    byName[scene.name] = scene.layout
  end
  return "window.RICHARSILUS_SCENES = " .. exporter.EncodeJson(byName) .. ";\n"
end

return exporter
