-- Ventana principal: estado del escaneo, tabla de recetas por beneficio y detalle con botones.
-- Las acciones protegidas (comprar, confirmar, craftear, publicar) solo se ejecutan dentro de
-- los OnClick de los botones de abajo: un clic, una acción.
local _, ns = ...
local L = ns.L

local UI = {}
ns.UI = UI

local FRAME_WIDTH = 640
local FRAME_HEIGHT = 640
local ROW_COUNT = 12
local ROW_HEIGHT = 18
local LIST_TOP = -88
local MAX_CRAFTS = 200

local GREEN = "|cff40ff40"
local RED = "|cffff4040"
local GREY = "|cff999999"
local COLOR_END = "|r"

local COLUMNS = {
  { key = "product", label = "COL_PRODUCT", width = 230, justify = "LEFT" },
  { key = "cost", label = "COL_COST", width = 85, justify = "RIGHT" },
  { key = "sale", label = "COL_SALE", width = 85, justify = "RIGHT" },
  { key = "profit", label = "COL_PROFIT", width = 95, justify = "RIGHT" },
  { key = "margin", label = "COL_MARGIN", width = 65, justify = "RIGHT" },
  { key = "have", label = "COL_HAVE", width = 50, justify = "RIGHT" },
}

UI.results = {}
UI.offset = 0
UI.crafts = 1
UI.selectedRecipeID = nil
UI.message = nil
UI.dirty = false
UI.userMoved = false

local function money(copper)
  return ns.Money.Format(copper)
end

local function signedMoney(copper)
  local color = copper >= 0 and GREEN or RED
  return color .. money(copper) .. COLOR_END
end

local function percent(ratio)
  if not ratio then
    return ""
  end
  local color = ratio >= 0 and GREEN or RED
  return color .. string.format("%d%%", math.floor(ratio * 100 + 0.5)) .. COLOR_END
end

local function createButton(parent, width, text, onClick)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(width, 22)
  button:SetText(text)
  button:SetScript("OnClick", onClick)
  return button
end

local function createText(parent, template, width, justify)
  local text = parent:CreateFontString(nil, "OVERLAY", template)
  if width then
    text:SetWidth(width)
  end
  text:SetJustifyH(justify or "LEFT")
  return text
end

---------------------------------------------------------------------------------------------
-- Resultado seleccionado
---------------------------------------------------------------------------------------------
function UI.SelectedRecipe()
  return UI.selectedRecipeID and ns.recipeDB:GetRecipe(UI.selectedRecipeID) or nil
end

function UI.SelectedResult()
  local recipe = UI.SelectedRecipe()
  if not recipe then
    return nil
  end
  local result = ns.session:Evaluate(recipe, UI.crafts)
  result.craftable = ns.Pricing.MaxCraftable(recipe, function(itemID)
    return ns.inventory:Count(itemID)
  end)
  return result
end

---------------------------------------------------------------------------------------------
-- Clics (únicos puntos que llaman a acciones protegidas)
---------------------------------------------------------------------------------------------
local function onBuyClick()
  UI.SetMessage(nil)
  local purchase = ns.purchase
  if not ns.auctionOpen then
    UI.SetMessage(L.NEEDS_AH)
    return
  end
  if purchase.state == "ready" then
    purchase:Confirm()
  elseif not purchase:IsBusy() then
    local result = UI.SelectedResult()
    local nextPurchase = result and ns.session:NextPurchase(result)
    if nextPurchase then
      purchase:Begin(nextPurchase)
    end
  end
  UI.Refresh()
end

local function onCancelClick()
  ns.purchase:Cancel()
  ns.post:Cancel()
  UI.SetMessage(nil)
  UI.Refresh()
end

local function onCraftClick()
  UI.SetMessage(nil)
  local result = UI.SelectedResult()
  if not result then
    return
  end
  local recipe = result.recipe
  local count = math.min(UI.crafts, result.craftable)
  if count < 1 then
    return
  end
  local isOpen = ns.openProfession ~= nil and ns.openProfession == recipe.profession
  local ok, reasonKey = ns.Actions.Craft(C_TradeSkillUI, isOpen, recipe.recipeID, count)
  if not ok then
    UI.SetMessage(string.format(L[reasonKey], recipe.profession or "?"))
  end
  UI.Refresh()
end

local function onPostClick()
  UI.SetMessage(nil)
  local post = ns.post
  if not ns.auctionOpen then
    UI.SetMessage(L.NEEDS_AH)
    return
  end
  if post.state == "confirm" then
    post:Confirm()
  elseif post.state ~= "posting" then
    local recipe = UI.SelectedRecipe()
    if not recipe then
      return
    end
    local unitPrice = ns.session:SaleUnitPrice(recipe.outputItemID)
    if not unitPrice then
      UI.SetMessage(L.NO_SALE_PRICE)
    else
      post:Begin(recipe.outputItemID, ns.inventory:Count(recipe.outputItemID), unitPrice, ns.db.settings.duration)
    end
  end
  UI.Refresh()
end

local function onCutClick()
  local settings = ns.db.settings
  if settings.cut == "auto" then
    settings.cut = ns.FACTION_CUT
  elseif settings.cut == ns.FACTION_CUT then
    settings.cut = ns.NEUTRAL_CUT
  else
    settings.cut = "auto"
  end
  UI.Refresh()
end

local function changeCrafts(delta)
  local step = IsShiftKeyDown() and delta * 10 or delta
  UI.crafts = math.max(1, math.min(MAX_CRAFTS, UI.crafts + step))
  UI.Refresh()
end

---------------------------------------------------------------------------------------------
-- Construcción
---------------------------------------------------------------------------------------------
local function createRows(frame)
  UI.rows = {}
  for index = 1, ROW_COUNT do
    local row = CreateFrame("Button", nil, frame)
    row:SetSize(FRAME_WIDTH - 40, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, LIST_TOP - (index - 1) * ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.selectedTexture = row:CreateTexture(nil, "BACKGROUND")
    row.selectedTexture:SetAllPoints()
    row.selectedTexture:SetColorTexture(1, 0.82, 0, 0.15)
    row.cells = {}
    local x = 0
    for _, column in ipairs(COLUMNS) do
      local cell = createText(row, "GameFontHighlightSmall", column.width - 6, column.justify)
      cell:SetPoint("LEFT", row, "LEFT", x, 0)
      cell:SetWordWrap(false)
      row.cells[column.key] = cell
      x = x + column.width
    end
    row:SetScript("OnClick", function(self)
      if self.recipeID then
        UI.selectedRecipeID = self.recipeID
        UI.crafts = 1
        UI.SetMessage(nil)
        UI.Refresh()
      end
    end)
    UI.rows[index] = row
  end
end

local function createHeader(frame)
  local x = 20
  for _, column in ipairs(COLUMNS) do
    local header = createText(frame, "GameFontNormalSmall", column.width - 6, column.justify)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", x, LIST_TOP + 18)
    header:SetText(L[column.label])
    x = x + column.width
  end
end

local function createDetail(frame)
  local detail = {}
  UI.detail = detail

  detail.title = createText(frame, "GameFontNormal", 420)
  detail.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, LIST_TOP - ROW_COUNT * ROW_HEIGHT - 14)

  detail.plus = createButton(frame, 26, "+", function() changeCrafts(1) end)
  detail.plus:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -20, LIST_TOP - ROW_COUNT * ROW_HEIGHT - 10)
  detail.craftsText = createText(frame, "GameFontHighlight", 50, "CENTER")
  detail.craftsText:SetPoint("RIGHT", detail.plus, "LEFT", -4, 0)
  detail.minus = createButton(frame, 26, "-", function() changeCrafts(-1) end)
  detail.minus:SetPoint("RIGHT", detail.craftsText, "LEFT", -4, 0)

  detail.materials = createText(frame, "GameFontHighlightSmall", FRAME_WIDTH - 40)
  detail.materials:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -8)
  detail.materials:SetJustifyV("TOP")
  detail.materials:SetSpacing(2)

  detail.summary = createText(frame, "GameFontHighlightSmall", FRAME_WIDTH - 40)
  detail.summary:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 82)

  detail.profit = createText(frame, "GameFontNormal", FRAME_WIDTH - 40)
  detail.profit:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 62)

  detail.message = createText(frame, "GameFontRedSmall", FRAME_WIDTH - 40)
  detail.message:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 44)

  detail.buy = createButton(frame, 250, L.BUY_NOTHING, onBuyClick)
  detail.buy:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 16)
  detail.cancel = createButton(frame, 90, L.CANCEL, onCancelClick)
  detail.cancel:SetPoint("LEFT", detail.buy, "RIGHT", 6, 0)
  detail.craft = createButton(frame, 120, L.CRAFT, onCraftClick)
  detail.craft:SetPoint("LEFT", detail.cancel, "RIGHT", 6, 0)
  detail.post = createButton(frame, 130, L.POST, onPostClick)
  detail.post:SetPoint("LEFT", detail.craft, "RIGHT", 6, 0)
end

function UI.Create()
  if UI.frame then
    return UI.frame
  end
  local frame = CreateFrame("Frame", "RicharsilusFrame", UIParent, "BackdropTemplate")
  UI.frame = frame
  frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("HIGH")
  frame:SetBackdrop(BACKDROP_DIALOG_32_32)
  -- El fondo del diálogo de Blizzard es semitransparente: sin esto se leen los nombres de detrás.
  local background = frame:CreateTexture(nil, "BACKGROUND")
  background:SetPoint("TOPLEFT", frame, "TOPLEFT", 11, -12)
  background:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 11)
  background:SetColorTexture(0.04, 0.04, 0.05, 0.95)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    UI.userMoved = true
  end)
  frame:SetScript("OnShow", function()
    UI.Refresh()
  end)
  frame:Hide()
  if UISpecialFrames then
    table.insert(UISpecialFrames, "RicharsilusFrame")
  end

  local title = createText(frame, "GameFontNormalLarge", 300, "CENTER")
  title:SetPoint("TOP", frame, "TOP", 0, -18)
  title:SetText(L.TITLE)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

  UI.scanButton = createButton(frame, 100, L.SCAN, function()
    ns.StartScan()
  end)
  UI.scanButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -42)

  UI.statusText = createText(frame, "GameFontHighlightSmall", 330)
  UI.statusText:SetPoint("LEFT", UI.scanButton, "RIGHT", 10, 0)

  UI.cutButton = createButton(frame, 150, "", onCutClick)
  UI.cutButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -42)

  createHeader(frame)
  createRows(frame)

  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, delta)
    local maximumOffset = math.max(0, #UI.results - ROW_COUNT)
    UI.offset = math.max(0, math.min(maximumOffset, UI.offset - delta))
    UI.RefreshRows()
  end)

  createDetail(frame)
  return frame
end

---------------------------------------------------------------------------------------------
-- Pintado
---------------------------------------------------------------------------------------------
local function statusLabel(result)
  if result.status == "no_sale_price" then
    return GREY .. L.STATUS_NO_SALE_PRICE .. COLOR_END
  end
  return RED .. L.STATUS_MISSING .. COLOR_END
end

function UI.RefreshRows()
  for index, row in ipairs(UI.rows) do
    local result = UI.results[UI.offset + index]
    if result then
      local cells = row.cells
      row.recipeID = result.recipe.recipeID
      cells.product:SetText(result.recipe.name or ns.ItemName(result.recipe.outputItemID))
      cells.cost:SetText(money(result.materialCost))
      if result.status == "ok" then
        cells.sale:SetText(money(result.salePrice * result.units))
        cells.profit:SetText(signedMoney(result.profit))
        cells.margin:SetText(percent(result.margin))
      else
        cells.sale:SetText(result.salePrice and money(result.salePrice * result.units) or statusLabel(result))
        cells.profit:SetText(statusLabel(result))
        cells.margin:SetText("")
      end
      cells.have:SetText(result.craftable > 0 and tostring(result.craftable) or GREY .. "0" .. COLOR_END)
      row.selectedTexture:SetShown(result.recipe.recipeID == UI.selectedRecipeID)
      row:Show()
    else
      row.recipeID = nil
      row:Hide()
    end
  end
end

-- Una línea por material: cuánto necesitas, cuánto tienes y, si falta, dónde comprarlo y lo que pagas.
local function materialLine(material)
  local action
  if material.toBuy == 0 then
    action = L.MATERIAL_HAVE_ALL
  elseif material.source == "auction" then
    action = string.format(L.MATERIAL_BUY_AUCTION, material.toBuy, money(material.buyCost))
  elseif material.source == "vendor" then
    action = string.format(L.MATERIAL_BUY_VENDOR, material.toBuy, money(material.buyCost))
  else
    action = string.format(L.MATERIAL_MISSING, material.toBuy)
  end
  return string.format(
    L.MATERIAL_LINE,
    ns.ItemName(material.itemID),
    material.needed,
    ns.inventory:Count(material.itemID),
    action
  )
end

local function itemList(entries)
  local parts = {}
  for index, entry in ipairs(entries) do
    parts[index] = string.format(L.SHOPPING_ITEM, entry.quantity, ns.ItemName(entry.itemID))
  end
  return table.concat(parts, ", ")
end

-- Lista de la compra completa: todo lo que hay que comprar en la subasta y al vendedor, con totales.
local function shoppingLines(shopping)
  local lines = { L.SHOPPING_TITLE }
  if #shopping.auction > 0 then
    lines[#lines + 1] = string.format(L.SHOPPING_AUCTION, itemList(shopping.auction), money(shopping.auctionTotal))
  end
  if #shopping.vendor > 0 then
    lines[#lines + 1] = string.format(L.SHOPPING_VENDOR, itemList(shopping.vendor), money(shopping.vendorTotal))
  end
  if #shopping.missing > 0 then
    lines[#lines + 1] = string.format(L.SHOPPING_MISSING, itemList(shopping.missing))
  end
  if #shopping.auction > 0 and #shopping.vendor > 0 then
    lines[#lines + 1] = string.format(L.SHOPPING_TOTAL, money(shopping.total))
  end
  if #shopping.auction == 0 and #shopping.vendor == 0 and #shopping.missing == 0 then
    lines[#lines + 1] = L.SHOPPING_NOTHING
  end
  return lines
end

local function refreshBuyButton(detail, result)
  local purchase = ns.purchase
  local button = detail.buy
  if purchase.state == "quoting" then
    button:SetText(L.BUY_WAITING)
    button:Disable()
  elseif purchase.state == "ready" then
    button:SetText(string.format(L.BUY_CONFIRM, money(purchase.quote.totalPrice)))
    button:Enable()
  elseif purchase.state == "purchasing" then
    button:SetText(L.BUY_PURCHASING)
    button:Disable()
  else
    local nextPurchase = result and ns.auctionOpen and ns.session:NextPurchase(result)
    if nextPurchase then
      button:SetText(string.format(L.BUY_NEXT, nextPurchase.quantity, ns.ItemName(nextPurchase.itemID))
        .. " (" .. money(nextPurchase.expectedTotal) .. ")")
      button:Enable()
    else
      button:SetText(L.BUY_NOTHING)
      button:Disable()
    end
  end
end

local function refreshPostButton(detail, recipe)
  local post = ns.post
  local button = detail.post
  if post.state == "confirm" then
    button:SetText(L.POST_CONFIRM)
    button:Enable()
  elseif post.state == "posting" then
    button:SetText(L.POSTING)
    button:Disable()
  else
    local count = recipe and ns.inventory:Count(recipe.outputItemID) or 0
    button:SetText(string.format(L.POST, count))
    button:SetEnabled(ns.auctionOpen == true and count > 0)
  end
end

function UI.RefreshDetail()
  local detail = UI.detail
  local result = UI.SelectedResult()
  detail.message:SetText(UI.message or "")

  local purchaseCancelable = ns.purchase.state == "quoting" or ns.purchase.state == "ready"
  detail.cancel:SetEnabled(purchaseCancelable or ns.post.state == "confirm")
  refreshBuyButton(detail, result)
  refreshPostButton(detail, result and result.recipe)

  if not result then
    detail.title:SetText(L.SELECT_RECIPE)
    detail.craftsText:SetText("")
    detail.materials:SetText("")
    detail.summary:SetText("")
    detail.profit:SetText("")
    detail.craft:SetText(string.format(L.CRAFT, 0))
    detail.craft:Disable()
    detail.minus:Disable()
    detail.plus:Disable()
    return
  end

  local recipe = result.recipe
  detail.title:SetText(recipe.name or ns.ItemName(recipe.outputItemID))
  detail.craftsText:SetText(string.format(L.CRAFTS, UI.crafts))
  detail.minus:SetEnabled(UI.crafts > 1)
  detail.plus:SetEnabled(UI.crafts < MAX_CRAFTS)

  local lines = { L.MATERIALS }
  for _, material in ipairs(result.materials) do
    lines[#lines + 1] = materialLine(material)
  end
  lines[#lines + 1] = " "
  for _, line in ipairs(shoppingLines(ns.session:ShoppingList(result))) do
    lines[#lines + 1] = line
  end
  detail.materials:SetText(table.concat(lines, "\n"))

  if result.salePrice then
    local depositText = money(result.deposit)
    local depositNote = ""
    if result.depositSource == "estimated" then
      depositText = "~" .. depositText
      depositNote = L.DEPOSIT_ESTIMATED
    elseif result.depositSource == "unknown" then
      depositText = "?"
      depositNote = L.DEPOSIT_UNKNOWN
    end
    if not ns.db.settings.includeDeposit then
      depositNote = depositNote .. L.DEPOSIT_NOT_COUNTED
    end
    detail.summary:SetText(string.format(
      L.SUMMARY,
      result.units,
      money(result.salePrice),
      money(result.gross),
      money(result.cutAmount),
      depositText,
      depositNote,
      money(result.materialCost)
    ))
  else
    detail.summary:SetText(statusLabel(result))
  end

  if result.status == "ok" then
    detail.profit:SetText(string.format(L.PROFIT_LINE, signedMoney(result.profit), percent(result.margin)))
  else
    detail.profit:SetText(statusLabel(result))
  end

  local craftCount = math.min(UI.crafts, result.craftable)
  detail.craft:SetText(string.format(L.CRAFT, craftCount))
  detail.craft:SetEnabled(craftCount > 0)
end

function UI.RefreshStatus()
  local scanning = ns.scanner:IsRunning()
  if scanning then
    local done, total = ns.scanner:Progress()
    UI.statusText:SetText(string.format(L.SCANNING, done, total))
  elseif not ns.recipeDB:HasRecipes() then
    UI.statusText:SetText(L.NO_RECIPES)
  elseif not ns.auctionOpen then
    UI.statusText:SetText(L.NEEDS_AH)
  else
    UI.statusText:SetText(L.READY)
  end
  UI.scanButton:SetEnabled(ns.auctionOpen == true and not scanning)

  local cut, isAuto = ns.session:CurrentCut()
  UI.cutButton:SetText(string.format(L.CUT_LABEL, math.floor(cut * 100 + 0.5), isAuto and L.CUT_AUTO or L.CUT_MANUAL))
end

function UI.Refresh()
  UI.dirty = false
  if not (UI.frame and UI.frame:IsShown() and ns.session) then
    return
  end
  UI.results = ns.session:EvaluateAll()
  UI.offset = math.max(0, math.min(UI.offset, #UI.results - ROW_COUNT))
  UI.RefreshStatus()
  UI.RefreshRows()
  UI.RefreshDetail()
end

---------------------------------------------------------------------------------------------
-- API usada por el resto del addon
---------------------------------------------------------------------------------------------
function UI.RequestRefresh()
  UI.dirty = true
end

function UI.FlushRefresh()
  if UI.dirty then
    UI.Refresh()
  end
end

function UI.SetMessage(text)
  UI.message = text
  UI.dirty = true
end

function UI.ShowAtAuctionHouse()
  local frame = UI.Create()
  if not UI.userMoved and AuctionHouseFrame then
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0)
  end
  frame:Show()
end

function UI.Toggle()
  local frame = UI.Create()
  frame:SetShown(not frame:IsShown())
end

function UI.Hide()
  if UI.frame then
    UI.frame:Hide()
  end
end
