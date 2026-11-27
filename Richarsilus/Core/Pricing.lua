-- Cálculo de rentabilidad. Funciones puras: no usan ninguna API de WoW.
-- Un "listing" es { unitPrice = cobre, quantity = unidades, own = es del jugador }
-- y las listas llegan ordenadas de más barata a más cara (ver PriceDB).
local _, ns = ...

local Pricing = {}
ns.Pricing = Pricing

local function lowestOf(first, second)
  if first and second then
    return math.min(first, second)
  end
  return first or second
end

-- Coste de comprar `quantity` unidades recorriendo las subastas de más barata a más cara.
-- Devuelve el coste y las unidades que realmente hay disponibles (puede ser menos de lo pedido).
function Pricing.BuyCost(listings, quantity)
  local totalCost, bought = 0, 0
  if not listings or quantity <= 0 then
    return totalCost, bought
  end
  for _, entry in ipairs(listings) do
    local take = math.min(entry.quantity, quantity - bought)
    totalCost = totalCost + take * entry.unitPrice
    bought = bought + take
    if bought >= quantity then
      break
    end
  end
  return totalCost, bought
end

function Pricing.LowestPrice(listings)
  local first = listings and listings[1]
  return first and first.unitPrice or nil
end

-- Precio unitario al que publicar: rebaja la subasta ajena más barata, o la iguala si es tuya.
function Pricing.SalePrice(listings, undercut)
  local first = listings and listings[1]
  if not first then
    return nil
  end
  if first.own then
    return first.unitPrice
  end
  return math.max(first.unitPrice - (undercut or 0), 1)
end

-- Subastas que el jugador puede comprar (no se puede comprar las propias).
function Pricing.OthersListings(listings)
  local others = {}
  for _, entry in ipairs(listings or {}) do
    if not entry.own then
      others[#others + 1] = entry
    end
  end
  return others
end

-- Coste de un material para una cantidad. Lo que ya tienes se valora a precio de mercado
-- (el menor entre subasta y vendedor); lo que falta se compra donde salga más barato.
function Pricing.MaterialCost(params)
  local needed = params.needed
  local ownedUsed = math.min(params.owned or 0, needed)
  local toBuy = needed - ownedUsed
  local listings = Pricing.OthersListings(params.listings)
  local vendorPrice = params.vendorPrice
  local marketUnitValue = lowestOf(Pricing.LowestPrice(listings), vendorPrice)

  local result = {
    needed = needed,
    ownedUsed = ownedUsed,
    toBuy = toBuy,
    ownedValue = 0,
    buyCost = 0,
    cost = 0,
    source = "none",
    complete = true,
  }

  if ownedUsed > 0 then
    if marketUnitValue then
      result.ownedValue = ownedUsed * marketUnitValue
      result.source = "owned"
    else
      result.complete = false
    end
  end

  if toBuy > 0 then
    local auctionCost, available = Pricing.BuyCost(listings, toBuy)
    local auctionCovers = available >= toBuy
    local vendorCost = vendorPrice and vendorPrice * toBuy
    if vendorCost and (not auctionCovers or vendorCost <= auctionCost) then
      result.source = "vendor"
      result.buyCost = vendorCost
    elseif auctionCovers then
      result.source = "auction"
      result.buyCost = auctionCost
    else
      result.source = "none"
      result.buyCost = auctionCost
      result.complete = false
    end
  end

  result.cost = result.ownedValue + result.buyCost
  return result
end

-- Evalúa `crafts` crafteos de una receta con los precios del contexto.
-- ctx = { listings(itemID), vendorPrice(itemID), owned(itemID), cut, undercut,
--         deposit(itemID, units) -> cantidad, origen, includeDeposit }
function Pricing.Evaluate(recipe, crafts, ctx)
  local craftCount = math.max(1, math.floor(crafts or 1))
  local units = craftCount * (recipe.quantityMin or 1)

  local materials = {}
  local materialCost = 0
  local materialsComplete = true
  for _, reagent in ipairs(recipe.reagents) do
    local material = Pricing.MaterialCost({
      needed = reagent.quantity * craftCount,
      owned = ctx.owned(reagent.itemID),
      listings = ctx.listings(reagent.itemID),
      vendorPrice = ctx.vendorPrice(reagent.itemID),
    })
    material.itemID = reagent.itemID
    materials[#materials + 1] = material
    materialCost = materialCost + material.cost
    if not material.complete then
      materialsComplete = false
    end
  end

  local result = {
    recipe = recipe,
    crafts = craftCount,
    units = units,
    materials = materials,
    materialCost = materialCost,
    deposit = 0,
  }

  local salePrice = Pricing.SalePrice(ctx.listings(recipe.outputItemID), ctx.undercut)
  result.salePrice = salePrice
  if salePrice then
    result.gross = salePrice * units
    result.cutAmount = math.floor(result.gross * ctx.cut + 0.5)
    -- ctx.deposit devuelve cantidad y origen ("game", "remembered", "estimated"); nil = desconocido.
    local deposit, depositSource = ctx.deposit(recipe.outputItemID, units)
    result.deposit = deposit or 0
    result.depositSource = deposit and (depositSource or "game") or "unknown"
    local depositCost = ctx.includeDeposit and result.deposit or 0
    result.profit = result.gross - result.cutAmount - materialCost - depositCost
    if materialCost > 0 then
      result.margin = result.profit / materialCost
    end
  end

  if not materialsComplete then
    result.status = "missing_materials"
  elseif not salePrice then
    result.status = "no_sale_price"
  else
    result.status = "ok"
  end
  return result
end

-- Cuántos crafteos puedes hacer solo con lo que llevas en las bolsas.
function Pricing.MaxCraftable(recipe, owned)
  local maximum
  for _, reagent in ipairs(recipe.reagents) do
    local possible = math.floor(owned(reagent.itemID) / reagent.quantity)
    maximum = maximum and math.min(maximum, possible) or possible
  end
  return maximum or 0
end
