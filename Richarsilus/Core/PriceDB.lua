-- Precios observados. Los listados completos viven en memoria (solo valen mientras la subasta
-- está abierta); en disco se guarda el precio mínimo, la hora del escaneo y si es commodity.
local _, ns = ...

local PriceDB = {}
PriceDB.__index = PriceDB
ns.PriceDB = PriceDB

local EMPTY = {}

local function byUnitPrice(first, second)
  return first.unitPrice < second.unitPrice
end

-- saved = { prices = {}, vendor = {} }; clock() devuelve la hora actual en segundos.
function PriceDB.New(saved, clock)
  local self = setmetatable({}, PriceDB)
  self.saved = saved
  self.clock = clock
  self.listings = {}
  return self
end

function PriceDB:SetListings(itemID, listings, isCommodity)
  local sorted = {}
  for index, entry in ipairs(listings) do
    sorted[index] = entry
  end
  table.sort(sorted, byUnitPrice)
  self.listings[itemID] = sorted
  self.saved.prices[itemID] = {
    min = sorted[1] and sorted[1].unitPrice or nil,
    t = self.clock(),
    commodity = isCommodity,
  }
end

function PriceDB:GetListings(itemID)
  return self.listings[itemID] or EMPTY
end

function PriceDB:HasScanned(itemID)
  return self.listings[itemID] ~= nil
end

function PriceDB:GetMinPrice(itemID)
  local entry = self.saved.prices[itemID]
  if not entry then
    return nil, nil
  end
  return entry.min, entry.t
end

function PriceDB:IsCommodity(itemID)
  local entry = self.saved.prices[itemID]
  if not entry then
    return nil
  end
  return entry.commodity
end

function PriceDB:SetVendorPrice(itemID, unitPrice)
  self.saved.vendor[itemID] = unitPrice
end

function PriceDB:GetVendorPrice(itemID)
  return self.saved.vendor[itemID]
end
