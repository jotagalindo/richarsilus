-- Conexión con el juego: crea los módulos con la API real de WoW y reparte los eventos.
-- Ningún evento llama a funciones protegidas: solo actualizan estado e interfaz.
local _, ns = ...
local L = ns.L

local TICK_SECONDS = 0.1

local AUCTION_EVENTS = {
  "AUCTION_HOUSE_SHOW",
  "AUCTION_HOUSE_CLOSED",
  "COMMODITY_SEARCH_RESULTS_UPDATED",
  "ITEM_SEARCH_RESULTS_UPDATED",
  "COMMODITY_PRICE_UPDATED",
  "COMMODITY_PRICE_UNAVAILABLE",
  "COMMODITY_PURCHASE_SUCCEEDED",
  "COMMODITY_PURCHASE_FAILED",
  "AUCTION_HOUSE_PURCHASE_COMPLETED",
  "AUCTION_HOUSE_AUCTION_CREATED",
  "AUCTION_HOUSE_POST_ERROR",
}

local OTHER_EVENTS = {
  "PLAYER_LOGIN",
  "TRADE_SKILL_SHOW",
  "TRADE_SKILL_LIST_UPDATE",
  "TRADE_SKILL_DATA_SOURCE_CHANGED",
  "TRADE_SKILL_CLOSE",
  "MERCHANT_SHOW",
  "MERCHANT_UPDATE",
  "BAG_UPDATE_DELAYED",
  "GET_ITEM_INFO_RECEIVED",
}

local PURCHASE_MESSAGES = {
  price_changed = "PRICE_CHANGED",
  unavailable = "PRICE_UNAVAILABLE",
  failed = "PURCHASE_FAILED",
}

local POST_MESSAGES = {
  no_item = "NO_ITEM",
  error = "POST_ERROR",
}

function ns.Print(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99" .. L.TITLE .. "|r: " .. text)
end

function ns.ItemName(itemID)
  local name = C_Item.GetItemNameByID(itemID)
  if name then
    return name
  end
  C_Item.RequestLoadItemDataByID(itemID)
  return string.format(L.UNKNOWN_ITEM, itemID)
end

local function characterKey()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function bagIDs()
  local ids = {}
  for bagID = 0, NUM_BAG_SLOTS or 4 do
    ids[#ids + 1] = bagID
  end
  local reagentBag = Enum.BagIndex and Enum.BagIndex.ReagentBag
  if reagentBag then
    ids[#ids + 1] = reagentBag
  end
  return ids
end

local function priceSorts()
  local priceOrder = Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
  return { { sortOrder = priceOrder, reverseSort = false } }
end

-- Precio de venta al vendedor (base del depósito en Forever); nil si el juego aún no tiene el objeto cargado.
local function sellPriceOf(itemID)
  if not (C_Item and C_Item.GetItemInfo) then
    return nil
  end
  local sellPrice = select(11, C_Item.GetItemInfo(itemID))
  if sellPrice == nil and C_Item.RequestLoadItemDataByID then
    C_Item.RequestLoadItemDataByID(itemID)
  end
  return sellPrice
end

-- El depósito depende de la duración y de si la casa de subastas es neutral.
local function depositKey()
  local cut = ns.session:CurrentCut()
  return ns.db.settings.duration .. ":" .. (cut >= ns.NEUTRAL_CUT and "neutral" or "faction")
end

-- Depósito para publicar `units` del objeto (solo con la subasta abierta). Devuelve cantidad y origen:
-- "game" si lo calcula el juego, "remembered"/"estimated" si sale de lo aprendido, nil y "unknown" si no.
local function depositFor(itemID, units)
  if not ns.auctionOpen then
    return nil, "unknown"
  end
  local duration = ns.db.settings.duration
  local key = depositKey()
  local sellPrice = sellPriceOf(itemID)
  if ns.priceDB:IsCommodity(itemID) == false then
    local location = ns.inventory:FindItemLocation(itemID)
    local perItem = location and C_AuctionHouse.CalculateItemDeposit(location, duration, 1)
    if perItem then
      ns.depositBook:Observe(itemID, key, perItem, sellPrice)
      return perItem * units, "game"
    end
  else
    local total = C_AuctionHouse.CalculateCommodityDeposit(itemID, duration, units)
    if total then
      ns.depositBook:Observe(itemID, key, total / units, sellPrice)
      return total, "game"
    end
  end
  return ns.depositBook:Estimate(itemID, key, units, sellPrice)
end

local function rescanItem(itemID)
  if ns.auctionOpen and itemID and not ns.scanner:IsRunning() then
    ns.scanner:Start({ itemID })
  end
end

function ns.StartScan()
  if not ns.auctionOpen then
    ns.Print(L.SCAN_NEEDS_AH)
    return
  end
  if not ns.recipeDB:HasRecipes() then
    ns.Print(L.NO_RECIPES)
    return
  end
  ns.UI.SetMessage(nil)
  ns.scanner:Start(ns.recipeDB:ItemIDsToScan())
  ns.UI.RequestRefresh()
end

local function isOwnProfession()
  local api = C_TradeSkillUI
  if api.IsTradeSkillLinked and api.IsTradeSkillLinked() then
    return false
  end
  if api.IsTradeSkillGuild and api.IsTradeSkillGuild() then
    return false
  end
  if api.IsNPCCrafting and api.IsNPCCrafting() then
    return false
  end
  return true
end

local announcedProfessions = {}

function ns.ReadProfession()
  if C_TradeSkillUI.IsTradeSkillReady and not C_TradeSkillUI.IsTradeSkillReady() then
    return
  end
  if not isOwnProfession() then
    ns.openProfession = nil
    return
  end
  local professionName, recipes = ns.RecipeDB.ReadOpenProfession(C_TradeSkillUI)
  ns.openProfession = professionName
  if professionName and #recipes > 0 then
    ns.recipeDB:SaveProfession(professionName, recipes)
    if not announcedProfessions[professionName] then
      announcedProfessions[professionName] = true
      ns.Print(string.format(L.RECIPES_SAVED, professionName, #recipes))
    end
  end
  ns.UI.RequestRefresh()
end

function ns.RecordVendorPrices()
  if not (GetMerchantNumItems and GetMerchantItemID and C_MerchantFrame and C_MerchantFrame.GetItemInfo) then
    return
  end
  for index = 1, GetMerchantNumItems() do
    local itemID = GetMerchantItemID(index)
    local info = C_MerchantFrame.GetItemInfo(index)
    if itemID and info and info.price and info.price > 0 and not info.hasExtendedCost and not info.currencyID then
      local stackCount = math.max(info.stackCount or 1, 1)
      ns.priceDB:SetVendorPrice(itemID, info.price / stackCount)
    end
  end
end

local function setup()
  local key = characterKey()
  RicharsilusDB = ns.InitDB(RicharsilusDB, key)
  ns.db = RicharsilusDB

  ns.priceDB = ns.PriceDB.New(ns.db, time)
  ns.depositBook = ns.DepositBook.New(ns.db.deposits)
  ns.recipeDB = ns.RecipeDB.New(ns.db.characters[key].professions, time)
  ns.inventory = ns.Inventory.New({
    bagIDs = bagIDs(),
    getItemCount = function(itemID)
      return C_Item.GetItemCount(itemID)
    end,
    getNumSlots = C_Container.GetContainerNumSlots,
    getItemID = C_Container.GetContainerItemID,
    makeLocation = function(bagID, slotIndex)
      return ItemLocation:CreateFromBagAndSlot(bagID, slotIndex)
    end,
  })
  ns.scanner = ns.Scanner.New(C_AuctionHouse, ns.priceDB, GetTime, priceSorts())
  ns.purchase = ns.Actions.NewPurchase(C_AuctionHouse, ns.db.settings.maxPriceIncrease)
  ns.post = ns.Actions.NewPost(C_AuctionHouse, ns.inventory)
  ns.session = ns.Session.New({
    priceDB = ns.priceDB,
    recipeDB = ns.recipeDB,
    inventory = ns.inventory,
    settings = ns.db.settings,
    deposit = depositFor,
    mapID = function()
      return C_Map.GetBestMapForUnit("player")
    end,
  })

  ns.scanner.onProgress = function()
    ns.UI.RequestRefresh()
  end
  ns.scanner.onFinished = function(done, total, aborted)
    if total > 1 then
      if aborted then
        ns.Print(L.SCAN_ABORTED)
      else
        ns.Print(string.format(L.SCAN_DONE, done, ns.scanner:SkippedCount()))
      end
    end
    ns.UI.RequestRefresh()
  end

  ns.purchase.onPurchased = function(itemID)
    ns.Print(string.format(L.PURCHASED, ns.ItemName(itemID)))
    rescanItem(itemID)
  end
  ns.purchase.onStateChanged = function(state)
    local messageKey = PURCHASE_MESSAGES[state]
    if messageKey then
      ns.UI.SetMessage(L[messageKey])
    end
    ns.UI.RequestRefresh()
  end

  ns.post.onPosted = function(itemID)
    ns.Print(string.format(L.POSTED, ns.ItemName(itemID)))
    rescanItem(itemID)
  end
  ns.post.onStateChanged = function(state)
    local messageKey = POST_MESSAGES[state]
    if messageKey then
      ns.UI.SetMessage(L[messageKey])
    end
    ns.UI.RequestRefresh()
  end

  SLASH_RICHARSILUS1 = "/rs"
  SLASH_RICHARSILUS2 = "/richarsilus"
  SlashCmdList.RICHARSILUS = function(text)
    ns.RunCommand(ns.ParseCommand(text), ns.Print)
  end
end

local eventFrame = CreateFrame("Frame")
for _, event in ipairs(OTHER_EVENTS) do
  eventFrame:RegisterEvent(event)
end
for _, event in ipairs(AUCTION_EVENTS) do
  eventFrame:RegisterEvent(event)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    setup()
    return
  end
  if not ns.db then
    return
  end

  if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
    ns.ReadProfession()
  elseif event == "TRADE_SKILL_CLOSE" then
    ns.openProfession = nil
    ns.UI.RequestRefresh()
  elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
    ns.RecordVendorPrices()
  elseif event == "BAG_UPDATE_DELAYED" or event == "GET_ITEM_INFO_RECEIVED" then
    ns.UI.RequestRefresh()
  elseif event == "AUCTION_HOUSE_SHOW" then
    ns.auctionOpen = true
    ns.UI.ShowAtAuctionHouse()
  else
    if event == "AUCTION_HOUSE_CLOSED" then
      ns.auctionOpen = false
    end
    ns.scanner:OnEvent(event, ...)
    ns.purchase:OnEvent(event, ...)
    ns.post:OnEvent(event, ...)
    if event == "AUCTION_HOUSE_CLOSED" then
      ns.UI.Hide()
    else
      ns.UI.RequestRefresh()
    end
  end
end)

local secondsSinceTick = 0
eventFrame:SetScript("OnUpdate", function(_, elapsed)
  secondsSinceTick = secondsSinceTick + elapsed
  if secondsSinceTick < TICK_SECONDS then
    return
  end
  secondsSinceTick = 0
  if ns.scanner then
    ns.scanner:Tick()
  end
  ns.UI.FlushRefresh()
end)
