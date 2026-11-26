-- Acciones que tocan funciones protegidas de Blizzard (comprar, publicar, craftear).
-- Norma del addon: cada método que llama a una de esas funciones (Begin, Confirm, Craft) se
-- invoca exclusivamente desde el OnClick de un botón, una vez por clic. Los eventos solo
-- cambian el estado; nunca encadenan otra acción protegida.
local _, ns = ...

local Actions = {}
ns.Actions = Actions

local DEFAULT_COMMODITY_STATUS = 2 -- Enum.ItemCommodityStatus.Commodity

local function noop() end

local function commodityStatusValue()
  local enumTable = Enum and Enum.ItemCommodityStatus
  return enumTable and enumTable.Commodity or DEFAULT_COMMODITY_STATUS
end

local function pack(...)
  return { n = select("#", ...), ... }
end

---------------------------------------------------------------------------------------------
-- Compra. Commodities: dos clics (pedir precio al servidor y confirmar), como la UI de Blizzard.
-- Objetos sueltos: un clic compra una subasta con su precio de compra inmediata.
---------------------------------------------------------------------------------------------
local Purchase = {}
Purchase.__index = Purchase

local BUSY_STATES = { quoting = true, ready = true, purchasing = true }

function Actions.NewPurchase(api, maxPriceIncrease)
  local self = setmetatable({}, Purchase)
  self.api = api
  self.maxPriceIncrease = maxPriceIncrease
  self.state = "idle"
  self.item = nil
  self.quote = nil
  self.onPurchased = noop
  self.onStateChanged = noop
  return self
end

function Purchase:SetState(state)
  self.state = state
  self.onStateChanged(state)
end

function Purchase:IsBusy()
  return BUSY_STATES[self.state] == true
end

-- item = { itemID, quantity, expectedTotal, isCommodity, auctionID, buyout }
function Purchase:Begin(item)
  if self:IsBusy() then
    return false
  end
  self.item = item
  self.quote = nil
  if item.isCommodity then
    local expectedUnitPrice = math.ceil(item.expectedTotal / item.quantity)
    self.api.StartCommoditiesPurchase(item.itemID, item.quantity, expectedUnitPrice)
    self:SetState("quoting")
  else
    self.api.PlaceBid(item.auctionID, item.buyout)
    self:SetState("purchasing")
  end
  return true
end

function Purchase:Confirm()
  if self.state ~= "ready" then
    return false
  end
  self.api.ConfirmCommoditiesPurchase(self.item.itemID, self.item.quantity)
  self:SetState("purchasing")
  return true
end

function Purchase:Cancel()
  if self.state == "quoting" or self.state == "ready" then
    self.api.CancelCommoditiesPurchase()
  end
  self.quote = nil
  self:SetState("idle")
end

function Purchase:Succeeded()
  local itemID = self.item and self.item.itemID
  self.quote = nil
  self:SetState("idle")
  self.onPurchased(itemID)
end

function Purchase:OnEvent(event, ...)
  if event == "AUCTION_HOUSE_CLOSED" then
    self.quote = nil
    self:SetState("idle")
  elseif event == "COMMODITY_PRICE_UPDATED" then
    if self.state ~= "quoting" then
      return
    end
    local unitPrice, totalPrice = ...
    local expectedUnitPrice = self.item.expectedTotal / self.item.quantity
    if unitPrice > expectedUnitPrice * self.maxPriceIncrease then
      self.api.CancelCommoditiesPurchase()
      self:SetState("price_changed")
    else
      self.quote = { unitPrice = unitPrice, totalPrice = totalPrice }
      self:SetState("ready")
    end
  elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
    if self.state == "quoting" or self.state == "ready" then
      self.api.CancelCommoditiesPurchase()
      self:SetState("unavailable")
    end
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    if self.state == "purchasing" and self.item.isCommodity then
      self:Succeeded()
    end
  elseif event == "COMMODITY_PURCHASE_FAILED" then
    if self.state == "purchasing" then
      self:SetState("failed")
    end
  elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
    local auctionID = ...
    if self.state == "purchasing" and not self.item.isCommodity and auctionID == self.item.auctionID then
      self:Succeeded()
    end
  end
end

---------------------------------------------------------------------------------------------
-- Publicación. Commodities: todas las unidades de una vez. Objetos: uno por clic.
-- Si el juego pide confirmación (needsConfirmation), hace falta un segundo clic.
---------------------------------------------------------------------------------------------
local Post = {}
Post.__index = Post

function Actions.NewPost(api, inventory)
  local self = setmetatable({}, Post)
  self.api = api
  self.inventory = inventory
  self.state = "idle"
  self.pending = nil
  self.itemID = nil
  self.onPosted = noop
  self.onStateChanged = noop
  return self
end

function Post:SetState(state)
  self.state = state
  self.onStateChanged(state)
end

function Post:Begin(itemID, quantity, unitPrice, duration)
  local location = self.inventory:FindItemLocation(itemID)
  if not location then
    self:SetState("no_item")
    return false
  end
  self.itemID = itemID

  local isCommodity = self.api.GetItemCommodityStatus(location) == commodityStatusValue()
  local arguments
  local needsConfirmation
  if isCommodity then
    local postQuantity = math.min(quantity, self.inventory:Count(itemID))
    arguments = pack(location, duration, postQuantity, unitPrice)
    needsConfirmation = self.api.PostCommodity(location, duration, postQuantity, unitPrice)
  else
    arguments = pack(location, duration, 1, nil, unitPrice)
    needsConfirmation = self.api.PostItem(location, duration, 1, nil, unitPrice)
  end

  if needsConfirmation then
    self.pending = { isCommodity = isCommodity, arguments = arguments }
    self:SetState("confirm")
  else
    self.pending = nil
    self:SetState("posting")
  end
  return true
end

function Post:Confirm()
  if self.state ~= "confirm" or not self.pending then
    return false
  end
  local arguments = self.pending.arguments
  if self.pending.isCommodity then
    self.api.ConfirmPostCommodity(unpack(arguments, 1, arguments.n))
  else
    self.api.ConfirmPostItem(unpack(arguments, 1, arguments.n))
  end
  self.pending = nil
  self:SetState("posting")
  return true
end

function Post:Cancel()
  self.pending = nil
  self:SetState("idle")
end

function Post:OnEvent(event)
  if event == "AUCTION_HOUSE_CLOSED" then
    self.pending = nil
    self:SetState("idle")
  elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
    if self.state == "posting" then
      self:SetState("posted")
      self.onPosted(self.itemID)
    end
  elseif event == "AUCTION_HOUSE_POST_ERROR" then
    if self.state == "posting" or self.state == "confirm" then
      self.pending = nil
      self:SetState("error")
    end
  end
end

---------------------------------------------------------------------------------------------
-- Crafteo: la misma llamada que el botón "Crear" de la ventana de profesión.
---------------------------------------------------------------------------------------------
function Actions.Craft(api, isProfessionOpen, recipeID, count)
  if not isProfessionOpen then
    return false, "PROFESSION_CLOSED"
  end
  api.CraftRecipe(recipeID, count)
  return true
end
