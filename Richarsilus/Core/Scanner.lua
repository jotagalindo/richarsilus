-- Escáner de precios: busca en la subasta solo los ítems de tus recetas, de uno en uno.
-- Respeta el sistema de límites de Blizzard (IsThrottledMessageSystemReady) y además espera
-- al menos 1 segundo entre búsquedas (60/min, por debajo del máximo documentado de 100/min).
local _, ns = ...

local Scanner = {}
Scanner.__index = Scanner
ns.Scanner = Scanner

Scanner.MIN_SECONDS_BETWEEN_QUERIES = 1
Scanner.RESPONSE_TIMEOUT_SECONDS = 10

local function noop() end

-- api = C_AuctionHouse; clock() = hora en segundos; sorts = orden para SendSearchQuery.
function Scanner.New(api, priceDB, clock, sorts)
  local self = setmetatable({}, Scanner)
  self.api = api
  self.priceDB = priceDB
  self.clock = clock
  self.sorts = sorts
  self.queue = {}
  self.nextIndex = 1
  self.done = 0
  self.skipped = 0
  self.running = false
  self.pending = nil
  self.lastSentAt = nil
  self.onProgress = noop
  self.onFinished = noop
  return self
end

function Scanner:Start(itemIDs)
  self.queue = {}
  for index, itemID in ipairs(itemIDs) do
    self.queue[index] = itemID
  end
  self.nextIndex = 1
  self.done = 0
  self.skipped = 0
  self.pending = nil
  self.running = true
  if #self.queue == 0 then
    self:Finish(false)
  end
end

function Scanner:Stop()
  if self.running then
    self:Finish(true)
  end
end

function Scanner:IsRunning()
  return self.running
end

function Scanner:Progress()
  return self.done, #self.queue
end

function Scanner:SkippedCount()
  return self.skipped
end

function Scanner:Finish(aborted)
  self.running = false
  self.pending = nil
  self.onFinished(self.done, #self.queue, aborted)
end

function Scanner:CompleteCurrent()
  self.pending = nil
  self.done = self.done + 1
  self.nextIndex = self.nextIndex + 1
  self.onProgress(self.done, #self.queue)
  if self.nextIndex > #self.queue then
    self:Finish(false)
  end
end

-- Se llama periódicamente (OnUpdate). Envía la siguiente búsqueda cuando está permitido.
function Scanner:Tick()
  if not self.running then
    return
  end
  local now = self.clock()

  if self.pending then
    if now - self.pending.sentAt > Scanner.RESPONSE_TIMEOUT_SECONDS then
      self.skipped = self.skipped + 1
      self:CompleteCurrent()
    end
    return
  end

  if self.lastSentAt and now - self.lastSentAt < Scanner.MIN_SECONDS_BETWEEN_QUERIES then
    return
  end
  if not self.api.IsThrottledMessageSystemReady() then
    return
  end

  local itemID = self.queue[self.nextIndex]
  self.pending = { itemID = itemID, sentAt = now }
  self.lastSentAt = now
  self.api.SendSearchQuery(self.api.MakeItemKey(itemID), self.sorts, true)
end

function Scanner:ReadCommodityResults(itemID)
  local listings = {}
  for index = 1, self.api.GetNumCommoditySearchResults(itemID) do
    local result = self.api.GetCommoditySearchResultInfo(itemID, index)
    if result then
      listings[#listings + 1] = {
        unitPrice = result.unitPrice,
        quantity = result.quantity,
        own = result.containsOwnerItem and true or false,
        auctionID = result.auctionID,
      }
    end
  end
  return listings
end

function Scanner:ReadItemResults(itemKey)
  local listings = {}
  for index = 1, self.api.GetNumItemSearchResults(itemKey) do
    local result = self.api.GetItemSearchResultInfo(itemKey, index)
    if result and result.buyoutAmount and result.quantity and result.quantity > 0 then
      listings[#listings + 1] = {
        unitPrice = math.ceil(result.buyoutAmount / result.quantity),
        quantity = result.quantity,
        own = result.containsOwnerItem and true or false,
        auctionID = result.auctionID,
        buyout = result.buyoutAmount,
      }
    end
  end
  return listings
end

function Scanner:OnEvent(event, ...)
  if event == "AUCTION_HOUSE_CLOSED" then
    self:Stop()
    return
  end
  if not (self.running and self.pending) then
    return
  end

  if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    local itemID = ...
    if itemID == self.pending.itemID then
      self.priceDB:SetListings(itemID, self:ReadCommodityResults(itemID), true)
      self:CompleteCurrent()
    end
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    local itemKey = ...
    if itemKey and itemKey.itemID == self.pending.itemID then
      self.priceDB:SetListings(itemKey.itemID, self:ReadItemResults(itemKey), false)
      self:CompleteCurrent()
    end
  end
end
