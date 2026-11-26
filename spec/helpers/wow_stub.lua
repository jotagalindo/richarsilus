-- Entorno de WoW simulado para probar Events.lua y MainFrame.lua fuera del juego.
-- Solo implementa lo que el addon usa; cualquier método que falte provoca un error en el test.
local stub = {}

local Region = {}
Region.__index = Region

local function newRegion(kind)
  return setmetatable({ kind = kind, scripts = {}, shown = true, enabled = true, text = nil, events = {} }, Region)
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
function Region:SetText(text) self.text = text end
function Region:GetText() return self.text end
function Region:Enable() self.enabled = true end
function Region:Disable() self.enabled = false end
function Region:SetEnabled(enabled) self.enabled = enabled and true or false end
function Region:IsEnabled() return self.enabled end
function Region:SetPoint(...) self.point = { ... } end
function Region:ClearAllPoints() self.point = nil end
function Region:RegisterEvent(event)
  self.events[event] = true
  stub.eventFrames[#stub.eventFrames + 1] = self
end
function Region.CreateFontString() return newRegion("FontString") end
function Region.CreateTexture() return newRegion("Texture") end
function Region:Click(...)
  assert(self.enabled, "clicked a disabled button: " .. tostring(self.text))
  self.scripts.OnClick(self, ...)
end

local NO_OPS = {
  "SetSize", "SetFrameStrata", "SetBackdrop", "SetClampedToScreen", "SetMovable", "EnableMouse",
  "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "SetHighlightTexture", "SetAllPoints",
  "SetColorTexture", "SetWidth", "SetJustifyH", "SetJustifyV", "SetSpacing", "SetWordWrap", "EnableMouseWheel",
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

  _G.CreateFrame = function(kind, name)
    local region = newRegion(kind)
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
  _G.NUM_BAG_SLOTS = 4
  _G.BACKDROP_DIALOG_32_32 = {}
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
