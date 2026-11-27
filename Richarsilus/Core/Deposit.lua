-- Depósitos de la casa de subastas para objetos que no se apilan.
-- El juego solo calcula su depósito si el objeto está en tus bolsas (CalculateItemDeposit pide un
-- ItemLocation), así que se guarda cada depósito que da el juego y, para los objetos que nunca se han
-- visto, se estima: en Forever el depósito es un porcentaje del precio de venta al vendedor que
-- depende de la duración y del tipo de casa de subastas, con un mínimo por subasta.
-- La clave de cada depósito es "duración:faction" o "duración:neutral".
local _, ns = ...

local DepositBook = {}
DepositBook.__index = DepositBook
ns.DepositBook = DepositBook

local function ensureTable(parent, key)
  if type(parent[key]) ~= "table" then
    parent[key] = {}
  end
  return parent[key]
end

-- saved = tabla guardada: { items = { [itemID] = { [clave] = depósitoPorUnidad } },
--                           rates = { [clave] = { ratio, sellPrice } }, minimum = { [clave] = depósito } }
function DepositBook.New(saved)
  local self = setmetatable({}, DepositBook)
  self.items = ensureTable(saved, "items")
  self.rates = ensureTable(saved, "rates")
  self.minimum = ensureTable(saved, "minimum")
  return self
end

-- Apunta el depósito por unidad que ha dado el juego para un objeto (y su precio de venta al vendedor).
function DepositBook:Observe(itemID, key, perUnit, sellPrice)
  if not perUnit or perUnit <= 0 then
    return
  end
  ensureTable(self.items, itemID)[key] = perUnit
  if not self.minimum[key] or perUnit < self.minimum[key] then
    self.minimum[key] = perUnit
  end
  if sellPrice and sellPrice > 0 then
    local rate = self.rates[key]
    if not rate or sellPrice > rate.sellPrice then
      self.rates[key] = { ratio = perUnit / sellPrice, sellPrice = sellPrice }
    end
  end
end

-- Depósito para `units` unidades sin el objeto en las bolsas.
-- Devuelve cantidad, origen: "remembered" (dado antes por el juego), "estimated" o nil, "unknown".
function DepositBook:Estimate(itemID, key, units, sellPrice)
  local remembered = self.items[itemID] and self.items[itemID][key]
  if remembered then
    return math.floor(remembered * units + 0.5), "remembered"
  end
  local rate = self.rates[key]
  if rate and sellPrice and sellPrice > 0 then
    local perUnit = math.max(sellPrice * rate.ratio, self.minimum[key] or 0)
    return math.floor(perUnit * units + 0.5), "estimated"
  end
  return nil, "unknown"
end
