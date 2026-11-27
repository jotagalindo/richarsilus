-- Entorno de WoW simulado para probar Events.lua y MainFrame.lua fuera del juego.
-- Solo implementa lo que el addon usa; cualquier método que falte provoca un error en el test.
local stub = {}

local Region = {}
Region.__index = Region

-- Además del estado, cada región guarda su diseño (padre, plantilla, tamaño, anclaje, alineación)
-- para que tools/ui-preview pueda dibujar la ventana tal y como la construye el addon.
local function newRegion(kind, parent, template)
  local region = setmetatable({
    kind = kind,
    parent = parent,
    template = template,
    children = {},
    scripts = {},
    shown = true,
    enabled = true,
    text = nil,
    events = {},
  }, Region)
  if parent then
    parent.children[#parent.children + 1] = region
  end
  return region
end

function Region:SetScript(name, handler) self.scripts[name] = handler end
function Region:GetScript(name) return self.scripts[name] end
function Region:IsShown() return self.shown end
function Region:Show()
  local wasHidden = not self.shown
  self.shown = true
  if wasHidden and self.scripts.OnShow then
    self.scripts.OnShow(self)
  end
end
function Region:Hide() self.shown = false end
function Region:SetShown(shown)
  if shown then self:Show() else self:Hide() end
end
-- Un botón con SetFontString muestra su texto en esa FontString, como en el juego.
function Region:SetText(text)
  self.text = text
  if self.fontString then
    self.fontString.text = text
  end
end
function Region:GetText() return self.text end
function Region:SetFontString(fontString) self.fontString = fontString end
-- Como en el juego, cambiar el estado de un botón ejecuta OnEnable / OnDisable.
function Region:SetEnabled(enabled)
  local wasEnabled = self.enabled
  self.enabled = enabled and true or false
  if wasEnabled ~= self.enabled then
    local handler = self.scripts[self.enabled and "OnEnable" or "OnDisable"]
    if handler then
      handler(self)
    end
  end
end
function Region:Enable() self:SetEnabled(true) end
function Region:Disable() self:SetEnabled(false) end
function Region:IsEnabled() return self.enabled end
-- `point` es el último anclaje y `points` todos (una región puede anclarse por dos esquinas).
function Region:SetPoint(...)
  self.point = { ... }
  self.points = self.points or {}
  self.points[#self.points + 1] = self.point
end
function Region:ClearAllPoints()
  self.point = nil
  self.points = nil
  self.allPoints = nil
end
function Region:SetAllPoints() self.allPoints = true end
function Region:SetSize(width, height)
  self.width = width
  self.height = height
end
function Region:SetWidth(width) self.width = width end
function Region:SetHeight(height) self.height = height end
function Region:SetJustifyH(justify) self.justifyH = justify end
function Region:SetJustifyV(justify) self.justifyV = justify end
function Region:SetSpacing(spacing) self.spacing = spacing end
function Region:SetWordWrap(wordWrap) self.wordWrap = wordWrap end
function Region:SetColorTexture(red, green, blue, alpha)
  self.color = { red, green, blue, alpha or 1 }
  self.texture = nil
end
function Region:SetTexture(texture)
  self.texture = texture
  self.color = nil
end
function Region:SetTextColor(red, green, blue, alpha) self.textColor = { red, green, blue, alpha or 1 } end
function Region:RegisterEvent(event)
  self.events[event] = true
  stub.eventFrames[#stub.eventFrames + 1] = self
end
function Region:CreateFontString(_, layer, template)
  local fontString = newRegion("FontString", self, template)
  fontString.layer = layer
  return fontString
end
function Region:CreateTexture(_, layer)
  local texture = newRegion("Texture", self)
  texture.layer = layer
  return texture
end
function Region:Click(...)
  assert(self.enabled, "clicked a disabled button: " .. tostring(self.text))
  self.scripts.OnClick(self, ...)
end

local NO_OPS = {
  "SetFrameStrata", "SetBackdrop", "SetClampedToScreen", "SetMovable", "EnableMouse",
  "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "SetHighlightTexture", "EnableMouseWheel",
  "SetTexCoord",
}
for _, name in ipairs(NO_OPS) do
  Region[name] = function() end
end

function stub.install(options)
  stub.eventFrames = {}
  stub.chat = {}
  stub.calls = {}
  stub.bags = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {} }
  stub.now = 1000
  stub.commodityResults = {}
  stub.sentQueries = {}

  local function record(name)
    return function(...)
      stub.calls[#stub.calls + 1] = { name = name, args = { ... } }
    end
  end

  _G.CreateFrame = function(kind, name, parent, template)
    local region = newRegion(kind, parent, template)
    if name then
      _G[name] = region
    end
    return region
  end
  _G.UIParent = newRegion("Frame")
  _G.AuctionHouseFrame = newRegion("Frame")
  _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) stub.chat[#stub.chat + 1] = text end }
  _G.GetLocale = function() return options.locale or "enUS" end
  _G.UnitName = function() return "Tester" end
  _G.GetRealmName = function() return "Realm" end
  _G.GetTime = function() return stub.now end
  _G.time = function() return 1700000000 end
  _G.IsShiftKeyDown = function() return false end
  -- Textos de las duraciones de subasta del juego: solo los hay si la prueba los pide.
  local durations = options.durations or {}
  _G.AUCTION_DURATION_ONE, _G.AUCTION_DURATION_TWO, _G.AUCTION_DURATION_THREE = durations[1], durations[2], durations[3]
  -- Hora en UTC para que las pruebas y las capturas no dependan de la zona horaria.
  _G.date = function(format, when) return os.date("!" .. format, when) end
  stub.tooltip = { shown = false, lines = {} }
  _G.GameTooltip = {
    SetOwner = function(_, owner) stub.tooltip.owner = owner end,
    SetItemByID = function(_, itemID) stub.tooltip.itemID = itemID end,
    SetText = function(_, text) stub.tooltip.title = text end,
    AddLine = function(_, text) stub.tooltip.lines[#stub.tooltip.lines + 1] = text end,
    Show = function() stub.tooltip.shown = true end,
    Hide = function()
      stub.tooltip = { shown = false, lines = {} }
    end,
  }
  _G.NUM_BAG_SLOTS = 4
  _G.UISpecialFrames = {}
  _G.SlashCmdList = {}
  _G.RicharsilusDB = nil
  _G.Enum = {
    AuctionHouseSortOrder = { Price = 0 },
    ItemCommodityStatus = { Item = 1, Commodity = 2 },
    TradeskillSlotDataType = { Reagent = 1 },
    CraftingReagentType = { Basic = 1 },
    BagIndex = {},
  }

  local function count(itemID)
    local total = 0
    for _, slots in pairs(stub.bags) do
      for _, slot in pairs(slots) do
        if slot.itemID == itemID then
          total = total + slot.count
        end
      end
    end
    return total
  end
  stub.count = count

  _G.C_Item = {
    GetItemNameByID = function(itemID) return options.itemNames[itemID] end,
    GetItemIconByID = function(itemID) return 100000 + itemID end,
    -- Solo interesa el precio de venta al vendedor (11.º valor); sin él, el objeto "no está cargado".
    GetItemInfo = function(itemID)
      local sellPrice = options.sellPrices and options.sellPrices[itemID]
      if sellPrice == nil then
        return nil
      end
      return options.itemNames[itemID], nil, nil, nil, nil, nil, nil, nil, nil, nil, sellPrice
    end,
    RequestLoadItemDataByID = record("RequestLoadItemDataByID"),
    GetItemCount = count,
  }
  _G.C_Container = {
    GetContainerNumSlots = function() return 16 end,
    GetContainerItemID = function(bagID, slotIndex)
      local slot = stub.bags[bagID][slotIndex]
      return slot and slot.itemID or nil
    end,
  }
  _G.ItemLocation = {
    CreateFromBagAndSlot = function(_, bagID, slotIndex) return { bag = bagID, slot = slotIndex } end,
  }
  _G.C_Map = { GetBestMapForUnit = function() return options.mapID end }
  _G.GetMerchantNumItems = function() return #options.merchant end
  _G.GetMerchantItemID = function(index) return options.merchant[index].itemID end
  _G.C_MerchantFrame = {
    GetItemInfo = function(index) return options.merchant[index] end,
  }

  _G.C_TradeSkillUI = options.tradeSkill
  _G.C_TradeSkillUI.CraftRecipe = record("CraftRecipe")

  _G.C_AuctionHouse = {
    IsThrottledMessageSystemReady = function() return true end,
    MakeItemKey = function(itemID) return { itemID = itemID } end,
    SendSearchQuery = function(itemKey) stub.sentQueries[#stub.sentQueries + 1] = itemKey.itemID end,
    GetNumCommoditySearchResults = function(itemID) return #(stub.commodityResults[itemID] or {}) end,
    GetCommoditySearchResultInfo = function(itemID, index) return stub.commodityResults[itemID][index] end,
    GetNumItemSearchResults = function() return 0 end,
    GetItemSearchResultInfo = function() return nil end,
    CalculateCommodityDeposit = function(_, _, quantity) return 5 * quantity end,
    CalculateItemDeposit = function() return 5 end,
    GetItemCommodityStatus = function() return 2 end,
    StartCommoditiesPurchase = record("StartCommoditiesPurchase"),
    ConfirmCommoditiesPurchase = record("ConfirmCommoditiesPurchase"),
    CancelCommoditiesPurchase = record("CancelCommoditiesPurchase"),
    PlaceBid = record("PlaceBid"),
    PostCommodity = function(...)
      record("PostCommodity")(...)
      return false
    end,
    ConfirmPostCommodity = record("ConfirmPostCommodity"),
    PostItem = record("PostItem"),
    ConfirmPostItem = record("ConfirmPostItem"),
  }
end

function stub.fire(event, ...)
  for _, frame in ipairs(stub.eventFrames) do
    if frame.events[event] and frame.scripts.OnEvent then
      frame.scripts.OnEvent(frame, event, ...)
    end
  end
end

function stub.update(seconds)
  stub.now = stub.now + seconds
  local seen = {}
  for _, frame in ipairs(stub.eventFrames) do
    if not seen[frame] and frame.scripts.OnUpdate then
      seen[frame] = true
      frame.scripts.OnUpdate(frame, seconds)
    end
  end
end

function stub.addToBags(itemID, amount)
  for bagID = 0, 4 do
    for slotIndex = 1, 16 do
      if not stub.bags[bagID][slotIndex] then
        stub.bags[bagID][slotIndex] = { itemID = itemID, count = amount }
        return
      end
    end
  end
end

function stub.lastCall(name)
  for index = #stub.calls, 1, -1 do
    if stub.calls[index].name == name then
      return stub.calls[index]
    end
  end
  return nil
end

-- Carga los ficheros en el orden del TOC, igual que el cliente.
function stub.loadAddon()
  local addonTable = {}
  for line in io.lines("Richarsilus/Richarsilus.toc") do
    local path = line:match("^%s*([^#%s].-)%s*$")
    if path then
      local chunk = assert(loadfile("Richarsilus/" .. path:gsub("\\", "/")))
      chunk("Richarsilus", addonTable)
    end
  end
  return addonTable
end

return stub
