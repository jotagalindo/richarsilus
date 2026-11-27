-- Une precios, recetas, bolsas y ajustes para responder a la interfaz:
-- comisión actual, ranking de recetas, siguiente material a comprar y precio de venta.
local _, ns = ...

local Session = {}
Session.__index = Session
ns.Session = Session

-- Mapas con casa de subastas neutral (Gadgetzan, Bahía del Botín, Vista Eterna).
-- Incluye los identificadores de mapa del cliente moderno y del clásico.
Session.NEUTRAL_AUCTION_MAPS = {
  [71] = true, -- Tanaris
  [83] = true, -- Cuna del Invierno
  [210] = true, -- Cabo de Tuercespina
  [224] = true, -- Vega de Tuercespina
  [1446] = true, -- Tanaris (clásico)
  [1452] = true, -- Cuna del Invierno (clásico)
  [1434] = true, -- Vega de Tuercespina (clásico)
}

local STATUS_ORDER = { ok = 1, no_sale_price = 2, missing_materials = 3 }

-- deps = { priceDB, recipeDB, inventory, settings, deposit(itemID, units), mapID() }
function Session.New(deps)
  local self = setmetatable({}, Session)
  self.priceDB = deps.priceDB
  self.recipeDB = deps.recipeDB
  self.inventory = deps.inventory
  self.settings = deps.settings
  self.deposit = deps.deposit
  self.mapID = deps.mapID
  return self
end

-- Devuelve la comisión (0.05 o 0.15) y si se ha detectado automáticamente.
function Session:CurrentCut()
  if self.settings.cut ~= "auto" then
    return self.settings.cut, false
  end
  local mapID = self.mapID()
  if mapID and Session.NEUTRAL_AUCTION_MAPS[mapID] then
    return ns.NEUTRAL_CUT, true
  end
  return ns.FACTION_CUT, true
end

function Session:Context()
  local priceDB = self.priceDB
  local inventory = self.inventory
  return {
    listings = function(itemID) return priceDB:GetListings(itemID) end,
    vendorPrice = function(itemID) return priceDB:GetVendorPrice(itemID) end,
    owned = function(itemID) return inventory:Count(itemID) end,
    cut = (self:CurrentCut()),
    undercut = self.settings.undercut,
    deposit = self.deposit,
    includeDeposit = self.settings.includeDeposit,
  }
end

function Session:Evaluate(recipe, crafts)
  return ns.Pricing.Evaluate(recipe, crafts, self:Context())
end

-- Columnas por las que se puede ordenar la tabla. Cada una tiene su orden natural (el que más interesa
-- arriba): beneficio, margen, venta y "puedes" de mayor a menor; coste de menor a mayor; nombre de la A a la Z.
Session.SORT_KEYS = {
  profit = { field = "profit", descending = true },
  margin = { field = "margin", descending = true },
  sale = { field = "salePrice", descending = true },
  cost = { field = "materialCost", descending = false },
  have = { field = "craftable", descending = true },
  product = { field = "name", descending = false },
}

local function resultName(result)
  return result.recipe.name or ""
end

local function sortValue(result, field)
  if field == "name" then
    return resultName(result)
  end
  return result[field]
end

-- Ordena `results` por la columna `key` (ver SORT_KEYS). Las recetas sin precio de venta o con
-- materiales sin precio van siempre al final, para que lo rentable quede arriba en cualquier orden.
function Session.SortResults(results, key)
  local sortKey = Session.SORT_KEYS[key] or Session.SORT_KEYS.profit
  local field = sortKey.field
  table.sort(results, function(first, second)
    local firstOrder = STATUS_ORDER[first.status]
    local secondOrder = STATUS_ORDER[second.status]
    if firstOrder ~= secondOrder then
      return firstOrder < secondOrder
    end
    local firstValue = sortValue(first, field)
    local secondValue = sortValue(second, field)
    if firstValue ~= nil and secondValue ~= nil and firstValue ~= secondValue then
      if sortKey.descending then
        return firstValue > secondValue
      end
      return firstValue < secondValue
    end
    if (firstValue == nil) ~= (secondValue == nil) then
      return firstValue ~= nil
    end
    return resultName(first) < resultName(second)
  end)
  return results
end

-- Evalúa un crafteo de cada receta conocida y las ordena: rentables primero, por beneficio
-- (o por la columna elegida en los ajustes).
function Session:EvaluateAll()
  local context = self:Context()
  local results = {}
  for _, recipe in ipairs(self.recipeDB:AllRecipes()) do
    local result = ns.Pricing.Evaluate(recipe, 1, context)
    result.craftable = ns.Pricing.MaxCraftable(recipe, context.owned)
    results[#results + 1] = result
  end
  return Session.SortResults(results, self.settings.sortKey)
end

-- Siguiente compra en la subasta para cubrir los materiales de `result`, o nil si no falta nada.
function Session:NextPurchase(result)
  for _, material in ipairs(result.materials) do
    if material.toBuy > 0 and material.source == "auction" then
      if self.priceDB:IsCommodity(material.itemID) ~= false then
        return {
          itemID = material.itemID,
          quantity = material.toBuy,
          expectedTotal = material.buyCost,
          isCommodity = true,
        }
      end
      local cheapest = ns.Pricing.OthersListings(self.priceDB:GetListings(material.itemID))[1]
      if cheapest then
        return {
          itemID = material.itemID,
          quantity = cheapest.quantity,
          expectedTotal = cheapest.buyout,
          isCommodity = false,
          auctionID = cheapest.auctionID,
          buyout = cheapest.buyout,
        }
      end
    end
  end
  return nil
end

-- Lista de la compra de `result`: qué falta comprar en la subasta y al vendedor (con su coste)
-- y qué no se puede comprar porque no hay suficientes subastas ni vendedor conocido.
function Session.ShoppingList(_, result)
  local shopping = { auction = {}, vendor = {}, missing = {}, auctionTotal = 0, vendorTotal = 0 }
  for _, material in ipairs(result.materials) do
    if material.toBuy > 0 then
      if material.source == "auction" then
        shopping.auction[#shopping.auction + 1] = {
          itemID = material.itemID,
          quantity = material.toBuy,
          cost = material.buyCost,
        }
        shopping.auctionTotal = shopping.auctionTotal + material.buyCost
      elseif material.source == "vendor" then
        shopping.vendor[#shopping.vendor + 1] = {
          itemID = material.itemID,
          quantity = material.toBuy,
          cost = material.buyCost,
        }
        shopping.vendorTotal = shopping.vendorTotal + material.buyCost
      else
        shopping.missing[#shopping.missing + 1] = { itemID = material.itemID, quantity = material.toBuy }
      end
    end
  end
  shopping.total = shopping.auctionTotal + shopping.vendorTotal
  return shopping
end

function Session:SaleUnitPrice(itemID)
  return ns.Pricing.SalePrice(self.priceDB:GetListings(itemID), self.settings.undercut)
end
