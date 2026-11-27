-- Ventana principal: barra de título, barra de herramientas (escanear, estado, comisión), tabla de
-- recetas ordenable y tarjeta de detalle (materiales, lista de la compra y resultado) con los botones
-- de acción abajo. Las acciones protegidas (comprar, confirmar, craftear, publicar) solo se ejecutan
-- dentro de los OnClick de esos botones: un clic, una acción.
local _, ns = ...
local L = ns.L
local W = ns.Widgets
local COLORS = W.COLORS
local CODES = W.CODES

local UI = {}
ns.UI = UI

local FRAME_WIDTH = 640
local FRAME_HEIGHT = 640
local PADDING = 12
local CONTENT_WIDTH = FRAME_WIDTH - 2 * PADDING
local TITLE_HEIGHT = 30
local TOOLBAR_TOP = -40
local TOOLBAR_HEIGHT = 24
local HEADER_TOP = -74
local HEADER_HEIGHT = 20
local ROW_COUNT = 8
local ROW_HEIGHT = 22
local LIST_TOP = HEADER_TOP - HEADER_HEIGHT
local LIST_HEIGHT = ROW_COUNT * ROW_HEIGHT
local SCROLLBAR_WIDTH = 4
local LIST_WIDTH = CONTENT_WIDTH - SCROLLBAR_WIDTH - 2
local CARD_TOP = LIST_TOP - LIST_HEIGHT - 10
local ACTION_HEIGHT = 28
local CARD_BOTTOM = PADDING + ACTION_HEIGHT + 22
local CARD_PADDING = 10
local CARD_WIDTH = CONTENT_WIDTH - 2 * CARD_PADDING
local MATERIAL_ROWS = 6
local MATERIAL_ROW_HEIGHT = 17
local SUMMARY_LINE_HEIGHT = 15
local MAX_CRAFTS = 200
local SCAN_BUTTON_WIDTH = 96
local CUT_BUTTON_WIDTH = 150
local STATUS_WIDTH = CONTENT_WIDTH - SCAN_BUTTON_WIDTH - CUT_BUTTON_WIDTH - 16

-- Columnas de la tabla de recetas. `sort` es la clave de Session.SORT_KEYS.
local COLUMNS = {
  { key = "product", label = "COL_PRODUCT", width = 252, justify = "LEFT", sort = "product" },
  { key = "cost", label = "COL_COST", width = 84, justify = "RIGHT", sort = "cost" },
  { key = "sale", label = "COL_SALE", width = 84, justify = "RIGHT", sort = "sale" },
  { key = "profit", label = "COL_PROFIT", width = 84, justify = "RIGHT", sort = "profit" },
  { key = "margin", label = "COL_MARGIN", width = 54, justify = "RIGHT", sort = "margin" },
  { key = "have", label = "COL_HAVE", width = 52, justify = "RIGHT", sort = "have" },
}
local PRODUCT_ICON_SIZE = 16

-- Columnas de la tabla de materiales.
local MATERIAL_COLUMNS = {
  { key = "name", label = "COL_MATERIAL", width = 230, justify = "LEFT" },
  { key = "needed", label = "COL_NEED", width = 66, justify = "RIGHT" },
  { key = "owned", label = "COL_OWNED", width = 56, justify = "RIGHT" },
  { key = "toBuy", label = "COL_TO_BUY", width = 62, justify = "RIGHT" },
  { key = "source", label = "COL_SOURCE", width = 92, justify = "RIGHT" },
  { key = "cost", label = "COL_PAY", width = 90, justify = "RIGHT" },
}
local MATERIAL_ICON_SIZE = 14

UI.results = {}
UI.offset = 0
UI.crafts = 1
UI.selectedRecipeID = nil
UI.message = nil
UI.dirty = false
UI.userMoved = false

local function money(copper)
  return ns.Money.FormatColored(copper)
end

local function colored(code, text)
  return code .. text .. CODES.stop
end

local function signedMoney(copper)
  return colored(copper >= 0 and CODES.green or CODES.red, ns.Money.Format(copper))
end

local function percent(ratio)
  if not ratio then
    return ""
  end
  return colored(ratio >= 0 and CODES.green or CODES.red, string.format("%d%%", math.floor(ratio * 100 + 0.5)))
end

local function muted(text)
  return colored(CODES.muted, text)
end

local function recipeName(recipe)
  return recipe.name or ns.ItemName(recipe.outputItemID)
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

function UI.Select(recipeID)
  UI.selectedRecipeID = recipeID
  UI.crafts = 1
  UI.SetMessage(nil)
end

-- Siguiente paso que conviene dar con la receta elegida: "buy", "craft", "post" o nil.
-- El botón de ese paso se pinta como principal para guiar al jugador: si ya tienes materiales para
-- todos los crafteos elegidos, craftear; si tienes producto y nada que craftear, publicarlo; si no,
-- comprar lo que falta; y con lo que quede, craftear o publicar lo que se pueda.
function UI.RecommendedStep(result)
  local purchaseState = ns.purchase.state
  if purchaseState == "quoting" or purchaseState == "ready" or purchaseState == "purchasing" then
    return "buy"
  end
  if ns.post.state == "confirm" or ns.post.state == "posting" then
    return "post"
  end
  if not result then
    return nil
  end
  local products = ns.inventory:Count(result.recipe.outputItemID)
  if result.craftable >= UI.crafts then
    return "craft"
  end
  if products > 0 and result.craftable == 0 then
    return "post"
  end
  if ns.auctionOpen and ns.session:NextPurchase(result) then
    return "buy"
  end
  if result.craftable > 0 then
    return "craft"
  end
  if products > 0 then
    return "post"
  end
  return nil
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

local function onSortClick(sortKey)
  ns.db.settings.sortKey = sortKey
  UI.offset = 0
  UI.Refresh()
end

local function changeCrafts(delta)
  local step = IsShiftKeyDown() and delta * 10 or delta
  UI.crafts = math.max(1, math.min(MAX_CRAFTS, UI.crafts + step))
  UI.Refresh()
end

local function scroll(delta)
  local maximumOffset = math.max(0, #UI.results - ROW_COUNT)
  UI.offset = math.max(0, math.min(maximumOffset, UI.offset - delta))
  UI.RefreshRows()
end

---------------------------------------------------------------------------------------------
-- Construcción
---------------------------------------------------------------------------------------------
local function tooltipText(titleKey, ...)
  local lines = {}
  for index = 1, select("#", ...) do
    lines[index] = L[select(index, ...)]
  end
  return { title = L[titleKey], lines = lines }
end

local function createTitleBar(frame)
  local bar = CreateFrame("Frame", nil, frame)
  bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
  bar:SetHeight(TITLE_HEIGHT - 1)
  W.Fill(bar, COLORS.titleBar)
  local line = W.Texture(bar, COLORS.divider, "BORDER")
  line:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
  line:SetHeight(1)

  local accent = W.Texture(bar, COLORS.accent, "ARTWORK")
  accent:SetSize(3, 14)
  accent:SetPoint("LEFT", bar, "LEFT", PADDING - 1, 0)

  local title = W.Text(bar, "GameFontNormal", COLORS.title)
  title:SetPoint("LEFT", accent, "RIGHT", 7, 0)
  title:SetText(L.TITLE)

  UI.subtitle = W.Text(bar, "GameFontHighlightSmall", COLORS.muted)
  UI.subtitle:SetPoint("LEFT", title, "RIGHT", 10, 0)

  local close = W.Button(bar, 22, 22, function()
    frame:Hide()
  end, "ghost")
  close:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
  close:SetText("X")
  UI.closeButton = close
end

local function createToolbar(frame)
  UI.scanButton = W.Button(frame, SCAN_BUTTON_WIDTH, TOOLBAR_HEIGHT, function()
    ns.StartScan()
  end, "primary")
  UI.scanButton:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, TOOLBAR_TOP)
  UI.scanButton:SetText(L.SCAN)
  UI.scanButton.tooltip = tooltipText("SCAN", "TOOLTIP_SCAN", "TOOLTIP_SCAN_TIME")

  local status = CreateFrame("Frame", nil, frame)
  status:SetSize(STATUS_WIDTH, TOOLBAR_HEIGHT)
  status:SetPoint("LEFT", UI.scanButton, "RIGHT", 8, 0)
  W.Panel(status, COLORS.well, COLORS.divider)
  status.fill = W.Texture(status, COLORS.progress, "ARTWORK")
  status.fill:SetPoint("TOPLEFT", status, "TOPLEFT", 1, -1)
  status.fill:SetSize(1, TOOLBAR_HEIGHT - 2)
  status.label = W.Text(status, "GameFontHighlightSmall", COLORS.text)
  status.label:SetPoint("LEFT", status, "LEFT", 8, 0)
  status.label:SetPoint("RIGHT", status, "RIGHT", -8, 0)
  status.label:SetWordWrap(false)
  UI.status = status
  UI.statusText = status.label

  UI.cutButton = W.Button(frame, CUT_BUTTON_WIDTH, TOOLBAR_HEIGHT, onCutClick, "secondary")
  UI.cutButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, TOOLBAR_TOP)
  UI.cutButton.tooltip = tooltipText("TOOLTIP_CUT_TITLE", "TOOLTIP_CUT", "TOOLTIP_CUT_CLICK")
end

local function createHeader(frame)
  UI.headers = {}
  local x = PADDING
  for _, column in ipairs(COLUMNS) do
    local header = CreateFrame("Button", nil, frame)
    header:SetSize(column.width, HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", x, HEADER_TOP)
    header.label = W.Text(header, "GameFontNormalSmall", COLORS.muted, column.justify)
    header.label:SetPoint("LEFT", header, "LEFT", column.key == "product" and 6 or 0, 0)
    header.label:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    header.label:SetText(L[column.label])
    header.underline = W.Texture(header, COLORS.accent, "ARTWORK")
    header.underline:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", column.key == "product" and 6 or 8, 0)
    header.underline:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -6, 0)
    header.underline:SetHeight(2)
    header.sortKey = column.sort
    header:SetScript("OnClick", function(self)
      onSortClick(self.sortKey)
    end)
    W.SetTooltip(header, tooltipText(column.label, "TOOLTIP_SORT"))
    UI.headers[column.key] = header
    x = x + column.width
  end
  W.Divider(frame, "TOPLEFT", PADDING, HEADER_TOP - HEADER_HEIGHT, "TOPRIGHT", -PADDING)
end

local function createRows(frame)
  local list = CreateFrame("Frame", nil, frame)
  list:SetSize(CONTENT_WIDTH, LIST_HEIGHT)
  list:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, LIST_TOP)
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(_, delta)
    scroll(delta)
  end)
  UI.list = list

  UI.rows = {}
  for index = 1, ROW_COUNT do
    local row = CreateFrame("Button", nil, list)
    row:SetSize(LIST_WIDTH, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    if index % 2 == 0 then
      W.Fill(row, COLORS.stripe)
    end
    row.selectedTexture = W.Fill(row, COLORS.selected)
    row.selectedBar = W.Texture(row, COLORS.accent, "ARTWORK")
    row.selectedBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.selectedBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.selectedBar:SetWidth(2)
    row.hover = W.Fill(row, COLORS.hover, "ARTWORK")
    row.hover:Hide()

    row.icon = W.Icon(row, PRODUCT_ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)

    row.cells = {}
    local x = 0
    for _, column in ipairs(COLUMNS) do
      local cell = W.Text(row, "GameFontHighlightSmall", COLORS.text, column.justify)
      if column.key == "product" then
        cell:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        cell:SetWidth(column.width - PRODUCT_ICON_SIZE - 18)
      else
        cell:SetPoint("RIGHT", row, "LEFT", x + column.width - 6, 0)
        cell:SetWidth(column.width - 6)
      end
      cell:SetWordWrap(false)
      row.cells[column.key] = cell
      x = x + column.width
    end

    row:SetScript("OnClick", function(self)
      if self.recipeID then
        UI.Select(self.recipeID)
        UI.Refresh()
      end
    end)
    row:SetScript("OnEnter", function(self)
      self.hover:Show()
      if self.itemID and GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemID)
        GameTooltip:Show()
      end
    end)
    row:SetScript("OnLeave", function(self)
      self.hover:Hide()
      if GameTooltip then
        GameTooltip:Hide()
      end
    end)
    UI.rows[index] = row
  end

  local track = W.Texture(list, COLORS.scrollTrack, "BACKGROUND")
  track:SetSize(SCROLLBAR_WIDTH, LIST_HEIGHT)
  track:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)
  local thumb = W.Texture(list, COLORS.scrollThumb, "ARTWORK")
  thumb:SetWidth(SCROLLBAR_WIDTH)
  thumb:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)
  UI.scrollTrack = track
  UI.scrollThumb = thumb

  UI.emptyText = W.Text(list, "GameFontHighlight", COLORS.muted, "CENTER", CONTENT_WIDTH - 80)
  UI.emptyText:SetPoint("CENTER", list, "CENTER", 0, 0)
  UI.emptyText:SetSpacing(4)
end

-- Fila "etiqueta ........ valor" del resumen.
local function createSummaryLine(parent, x, y, width, template)
  local line = {}
  line.label = W.Text(parent, template or "GameFontHighlightSmall", COLORS.text, "LEFT")
  line.label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  line.label:SetWidth(width - 96)
  line.label:SetWordWrap(false)
  line.value = W.Text(parent, template or "GameFontHighlightSmall", COLORS.text, "RIGHT")
  line.value:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
  line.value:SetWidth(120)
  line.value:SetWordWrap(false)
  return line
end

local function setLine(line, label, value)
  line.label:SetText(label or "")
  line.value:SetText(value or "")
end

local function createMaterialTable(card, detail)
  local top = -CARD_PADDING - 40
  local x = CARD_PADDING
  for _, column in ipairs(MATERIAL_COLUMNS) do
    local header = W.Text(card, "GameFontNormalSmall", COLORS.muted, column.justify, column.width - 6)
    if column.justify == "LEFT" then
      header:SetPoint("TOPLEFT", card, "TOPLEFT", x, top)
    else
      header:SetPoint("TOPRIGHT", card, "TOPLEFT", x + column.width - 6, top)
    end
    header:SetText(L[column.label])
    x = x + column.width
  end
  W.Divider(card, "TOPLEFT", CARD_PADDING, top - 14, "TOPRIGHT", -CARD_PADDING)

  detail.materialRows = {}
  for index = 1, MATERIAL_ROWS do
    local row = CreateFrame("Button", nil, card)
    row:SetSize(CARD_WIDTH, MATERIAL_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PADDING, top - 16 - (index - 1) * MATERIAL_ROW_HEIGHT)
    row.icon = W.Icon(row, MATERIAL_ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.cells = {}
    local cellX = 0
    for _, column in ipairs(MATERIAL_COLUMNS) do
      local cell = W.Text(row, "GameFontHighlightSmall", COLORS.text, column.justify)
      if column.key == "name" then
        cell:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        cell:SetWidth(column.width - MATERIAL_ICON_SIZE - 12)
      else
        cell:SetPoint("RIGHT", row, "LEFT", cellX + column.width - 6, 0)
        cell:SetWidth(column.width - 6)
      end
      cell:SetWordWrap(false)
      row.cells[column.key] = cell
      cellX = cellX + column.width
    end
    row:SetScript("OnEnter", function(self)
      if self.itemID and GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemID)
        GameTooltip:Show()
      end
    end)
    row:SetScript("OnLeave", function()
      if GameTooltip then
        GameTooltip:Hide()
      end
    end)
    detail.materialRows[index] = row
  end
end

local function createSummaries(card, detail)
  local top = -CARD_PADDING - 40 - 16 - MATERIAL_ROWS * MATERIAL_ROW_HEIGHT - 12
  local columnWidth = (CARD_WIDTH - 24) / 2
  local rightX = CARD_PADDING + columnWidth + 24

  W.Divider(card, "TOPLEFT", CARD_PADDING, top + 6, "TOPRIGHT", -CARD_PADDING)
  local separator = W.Texture(card, COLORS.divider, "BORDER")
  separator:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PADDING + columnWidth + 12, top - 4)
  separator:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", CARD_PADDING + columnWidth + 12, CARD_PADDING)
  separator:SetWidth(1)

  -- Lista de la compra (izquierda).
  detail.shoppingTitle = W.Text(card, "GameFontNormalSmall", COLORS.title)
  detail.shoppingTitle:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PADDING, top)
  detail.shoppingTitle:SetText(L.SHOPPING_TITLE)
  detail.shopping = {}
  for index = 1, 4 do
    detail.shopping[index] = createSummaryLine(card, CARD_PADDING, top - 4 - index * SUMMARY_LINE_HEIGHT, columnWidth)
  end
  detail.shoppingTotal = createSummaryLine(card, CARD_PADDING, top - 4 - 5 * SUMMARY_LINE_HEIGHT - 6, columnWidth,
    "GameFontNormal")
  detail.shoppingTotal.label:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3], COLORS.text[4])

  -- Resultado (derecha).
  detail.resultTitle = W.Text(card, "GameFontNormalSmall", COLORS.title)
  detail.resultTitle:SetPoint("TOPLEFT", card, "TOPLEFT", rightX, top)
  detail.receipt = {}
  for index, key in ipairs({ "sale", "cut", "deposit", "materials" }) do
    detail.receipt[key] = createSummaryLine(card, rightX, top - 4 - index * SUMMARY_LINE_HEIGHT, columnWidth)
  end
  detail.depositRow = CreateFrame("Frame", nil, card)
  detail.depositRow:SetSize(columnWidth, SUMMARY_LINE_HEIGHT)
  detail.depositRow:SetPoint("TOPLEFT", card, "TOPLEFT", rightX, top - 4 - 3 * SUMMARY_LINE_HEIGHT)
  W.SetTooltip(detail.depositRow, nil)
  detail.profit = createSummaryLine(card, rightX, top - 4 - 5 * SUMMARY_LINE_HEIGHT - 6, columnWidth, "GameFontNormal")
  detail.profit.label:SetText(L.RECEIPT_PROFIT)
  detail.profit.value:SetWidth(200)
end

local function createDetail(frame)
  local detail = {}
  UI.detail = detail

  local card = CreateFrame("Frame", nil, frame)
  card:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, CARD_TOP)
  card:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING, CARD_BOTTOM)
  W.Panel(card, COLORS.card)
  detail.card = card

  -- Contenido de la receta elegida (se oculta entero si no hay ninguna).
  local content = CreateFrame("Frame", nil, card)
  content:SetAllPoints()
  detail.content = content

  detail.icon = W.Icon(content, 30)
  detail.icon:SetPoint("TOPLEFT", content, "TOPLEFT", CARD_PADDING, -CARD_PADDING)
  detail.title = W.Text(content, "GameFontNormalLarge", COLORS.title, "LEFT", 360)
  detail.title:SetPoint("TOPLEFT", detail.icon, "TOPRIGHT", 10, 1)
  detail.title:SetWordWrap(false)
  detail.subtitle = W.Text(content, "GameFontHighlightSmall", COLORS.muted, "LEFT", 360)
  detail.subtitle:SetPoint("BOTTOMLEFT", detail.icon, "BOTTOMRIGHT", 10, 1)
  detail.subtitle:SetWordWrap(false)

  detail.plus = W.Button(content, 24, 24, function() changeCrafts(1) end, "secondary")
  detail.plus:SetPoint("TOPRIGHT", content, "TOPRIGHT", -CARD_PADDING, -CARD_PADDING - 3)
  detail.plus:SetText("+")
  local amount = CreateFrame("Frame", nil, content)
  amount:SetSize(46, 24)
  amount:SetPoint("RIGHT", detail.plus, "LEFT", -3, 0)
  W.Panel(amount, COLORS.well, COLORS.divider)
  detail.craftsText = W.Text(amount, "GameFontHighlight", COLORS.text, "CENTER")
  detail.craftsText:SetPoint("CENTER", amount, "CENTER", 0, 0)
  detail.minus = W.Button(content, 24, 24, function() changeCrafts(-1) end, "secondary")
  detail.minus:SetPoint("RIGHT", amount, "LEFT", -3, 0)
  detail.minus:SetText("-")
  detail.craftsLabel = W.Text(content, "GameFontHighlightSmall", COLORS.muted, "RIGHT")
  detail.craftsLabel:SetPoint("RIGHT", detail.minus, "LEFT", -8, 0)
  detail.craftsLabel:SetText(L.CRAFTS_LABEL)
  local stepperTooltip = tooltipText("TOOLTIP_CRAFTS_TITLE", "TOOLTIP_CRAFTS", "TOOLTIP_CRAFTS_SHIFT")
  detail.plus.tooltip = stepperTooltip
  detail.minus.tooltip = stepperTooltip
  W.SetTooltip(amount, stepperTooltip)

  createMaterialTable(content, detail)
  createSummaries(content, detail)

  detail.empty = W.Text(card, "GameFontHighlight", COLORS.muted, "CENTER", CARD_WIDTH - 60)
  detail.empty:SetPoint("CENTER", card, "CENTER", 0, 0)
  detail.empty:SetText(L.SELECT_RECIPE)

  -- Mensaje (errores en rojo) o pista del siguiente paso, justo encima de los botones.
  detail.message = W.Text(frame, "GameFontHighlightSmall", COLORS.muted, "LEFT", CONTENT_WIDTH)
  detail.message:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PADDING, PADDING + ACTION_HEIGHT + 6)
  detail.message:SetWordWrap(false)

  detail.buy = W.Button(frame, 236, ACTION_HEIGHT, onBuyClick, "primary")
  detail.buy:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PADDING, PADDING)
  detail.buy:SetText(L.BUY_NOTHING)
  detail.buy.tooltip = tooltipText("TOOLTIP_BUY_TITLE", "TOOLTIP_BUY", "TOOLTIP_BUY_CONFIRM")
  detail.cancel = W.Button(frame, 85, ACTION_HEIGHT, onCancelClick, "secondary")
  detail.cancel:SetPoint("LEFT", detail.buy, "RIGHT", 5, 0)
  detail.cancel:SetText(L.CANCEL)
  detail.cancel.tooltip = tooltipText("CANCEL", "TOOLTIP_CANCEL")
  detail.craft = W.Button(frame, 140, ACTION_HEIGHT, onCraftClick, "secondary")
  detail.craft:SetPoint("LEFT", detail.cancel, "RIGHT", 5, 0)
  detail.craft.tooltip = tooltipText("TOOLTIP_CRAFT_TITLE", "TOOLTIP_CRAFT", "TOOLTIP_CRAFT_OPEN")
  detail.post = W.Button(frame, 140, ACTION_HEIGHT, onPostClick, "secondary")
  detail.post:SetPoint("LEFT", detail.craft, "RIGHT", 5, 0)
  detail.post.tooltip = function()
    local duration = ns.DurationLabel(ns.db.settings.duration)
    return {
      title = L.TOOLTIP_POST_TITLE,
      lines = { L.TOOLTIP_POST, string.format(L.TOOLTIP_POST_DURATION, duration) },
    }
  end
end

function UI.Create()
  if UI.frame then
    return UI.frame
  end
  local frame = CreateFrame("Frame", "RicharsilusFrame", UIParent)
  UI.frame = frame
  frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("HIGH")
  -- Fondo casi opaco: sin él se leerían los nombres y la interfaz de detrás.
  W.Panel(frame, COLORS.window, COLORS.border)
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

  createTitleBar(frame)
  createToolbar(frame)
  createHeader(frame)
  createRows(frame)
  createDetail(frame)
  return frame
end

---------------------------------------------------------------------------------------------
-- Pintado
---------------------------------------------------------------------------------------------
local function statusLabel(result)
  if result.status == "no_sale_price" then
    return muted(L.STATUS_NO_SALE_PRICE)
  end
  return colored(CODES.red, L.STATUS_MISSING)
end

local function refreshScrollbar()
  local maximumOffset = #UI.results - ROW_COUNT
  if maximumOffset <= 0 then
    UI.scrollTrack:Hide()
    UI.scrollThumb:Hide()
    return
  end
  local thumbHeight = math.max(16, math.floor(LIST_HEIGHT * ROW_COUNT / #UI.results))
  local thumbTop = math.floor((LIST_HEIGHT - thumbHeight) * UI.offset / maximumOffset)
  UI.scrollThumb:ClearAllPoints()
  UI.scrollThumb:SetPoint("TOPRIGHT", UI.list, "TOPRIGHT", 0, -thumbTop)
  UI.scrollThumb:SetHeight(thumbHeight)
  UI.scrollTrack:Show()
  UI.scrollThumb:Show()
end

function UI.RefreshRows()
  for index, row in ipairs(UI.rows) do
    local result = UI.results[UI.offset + index]
    if result then
      local cells = row.cells
      local recipe = result.recipe
      row.recipeID = recipe.recipeID
      row.itemID = recipe.outputItemID
      W.SetIcon(row.icon, recipe.outputItemID)
      cells.product:SetText(recipeName(recipe))
      cells.cost:SetText(result.status == "missing_materials" and muted("?") or money(result.materialCost))
      if result.status == "ok" then
        cells.sale:SetText(money(result.salePrice * result.units))
        cells.profit:SetText(signedMoney(result.profit))
        cells.margin:SetText(percent(result.margin))
      else
        cells.sale:SetText(result.salePrice and money(result.salePrice * result.units) or muted("-"))
        cells.profit:SetText(statusLabel(result))
        cells.margin:SetText("")
      end
      cells.have:SetText(result.craftable > 0 and tostring(result.craftable) or muted("0"))
      local selected = recipe.recipeID == UI.selectedRecipeID
      row.selectedTexture:SetShown(selected)
      row.selectedBar:SetShown(selected)
      row:Show()
    else
      row.recipeID = nil
      row.itemID = nil
      row:Hide()
    end
  end
  refreshScrollbar()
end

local function refreshHeaders()
  local sortKey = ns.db.settings.sortKey
  for _, header in pairs(UI.headers) do
    local active = header.sortKey == sortKey
    local color = active and COLORS.title or COLORS.muted
    header.label:SetTextColor(color[1], color[2], color[3], color[4])
    header.underline:SetShown(active)
  end
end

local SOURCE_LABELS = {
  auction = function() return L.SOURCE_AUCTION end,
  vendor = function() return colored(CODES.vendor, L.SOURCE_VENDOR) end,
  none = function() return colored(CODES.red, L.SOURCE_MISSING) end,
}

local function clearMaterialRow(row)
  row.itemID = nil
  W.SetIcon(row.icon, nil)
  for _, cell in pairs(row.cells) do
    cell:SetText("")
  end
end

-- Una fila por material. Si no caben todos, la última fila dice cuántos faltan por mostrar.
local function refreshMaterials(detail, result)
  local materials = result.materials
  local visible = #materials > MATERIAL_ROWS and MATERIAL_ROWS - 1 or #materials
  for index, row in ipairs(detail.materialRows) do
    local material = index <= visible and materials[index]
    if material then
      local owned = ns.inventory:Count(material.itemID)
      local cells = row.cells
      row.itemID = material.itemID
      W.SetIcon(row.icon, material.itemID)
      cells.name:SetText(ns.ItemName(material.itemID))
      cells.needed:SetText(tostring(material.needed))
      cells.owned:SetText(owned >= material.needed and colored(CODES.green, tostring(owned))
        or (owned > 0 and tostring(owned) or muted("0")))
      if material.toBuy == 0 then
        cells.toBuy:SetText(muted("-"))
        cells.source:SetText(colored(CODES.green, L.SOURCE_OWNED))
        cells.cost:SetText(muted("-"))
      else
        cells.toBuy:SetText(tostring(material.toBuy))
        cells.source:SetText(SOURCE_LABELS[material.source]())
        cells.cost:SetText(material.source == "none" and muted("-") or money(material.buyCost))
      end
      row:Show()
    elseif index == visible + 1 and #materials > visible then
      clearMaterialRow(row)
      row.cells.name:SetText(muted(string.format(L.MORE_MATERIALS, #materials - visible)))
      row:Show()
    else
      clearMaterialRow(row)
      row:Hide()
    end
  end
end

local function itemList(entries)
  local parts = {}
  for index, entry in ipairs(entries) do
    parts[index] = string.format(L.SHOPPING_ITEM, entry.quantity, ns.ItemName(entry.itemID))
  end
  return table.concat(parts, ", ")
end

-- Lista de la compra: una línea por sitio donde comprar (subasta, vendedor), lo que no se puede
-- comprar y el total a gastar.
local function refreshShopping(detail, shopping)
  local lines = {}
  if #shopping.auction > 0 then
    lines[#lines + 1] = { string.format(L.SHOPPING_AUCTION, itemList(shopping.auction)), money(shopping.auctionTotal) }
  end
  if #shopping.vendor > 0 then
    lines[#lines + 1] = {
      string.format(L.SHOPPING_VENDOR, itemList(shopping.vendor)),
      money(shopping.vendorTotal),
    }
  end
  if #shopping.missing > 0 then
    lines[#lines + 1] = { colored(CODES.red, string.format(L.SHOPPING_MISSING, itemList(shopping.missing))), "" }
  end
  if #lines == 0 then
    lines[1] = { colored(CODES.green, L.SHOPPING_NOTHING), "" }
  end
  for index, line in ipairs(detail.shopping) do
    local entry = lines[index]
    setLine(line, entry and entry[1], entry and entry[2])
  end
  if shopping.total > 0 then
    setLine(detail.shoppingTotal, L.SHOPPING_TOTAL, money(shopping.total))
  else
    setLine(detail.shoppingTotal, "", "")
  end
end

local function depositTexts(result)
  local value = "-" .. money(result.deposit)
  local note = ""
  local tooltip = L.TOOLTIP_DEPOSIT
  if result.depositSource == "estimated" then
    value = "~" .. value
    note = L.DEPOSIT_ESTIMATED
    tooltip = L.TOOLTIP_DEPOSIT_ESTIMATED
  elseif result.depositSource == "unknown" then
    value = "?"
    note = L.DEPOSIT_UNKNOWN
    tooltip = L.TOOLTIP_DEPOSIT_UNKNOWN
  end
  if not ns.db.settings.includeDeposit then
    note = note .. L.DEPOSIT_NOT_COUNTED
    value = muted(ns.Money.Format(result.deposit))
  end
  local option = ns.DurationOptions()[ns.db.settings.duration]
  local label = option and option.label and string.format(L.RECEIPT_DEPOSIT_DURATION, option.label) or L.RECEIPT_DEPOSIT
  return label .. note, value, tooltip
end

local function refreshReceipt(detail, result)
  local receipt = detail.receipt
  local cut = ns.session:CurrentCut()
  detail.resultTitle:SetText(string.format(result.crafts == 1 and L.RESULT_TITLE_ONE or L.RESULT_TITLE, result.crafts))
  if result.salePrice then
    setLine(receipt.sale, string.format(L.RECEIPT_SALE, result.units, ns.Money.Format(result.salePrice)),
      money(result.gross))
    setLine(receipt.cut, string.format(L.RECEIPT_CUT, math.floor(cut * 100 + 0.5)), "-" .. money(result.cutAmount))
    local depositLabel, depositValue, depositTooltip = depositTexts(result)
    setLine(receipt.deposit, depositLabel, depositValue)
    detail.depositRow.tooltip = {
      title = L.RECEIPT_DEPOSIT,
      lines = { L.TOOLTIP_DEPOSIT_WHAT, depositTooltip, L.TOOLTIP_DEPOSIT_DURATION },
    }
  else
    setLine(receipt.sale, L.RECEIPT_SALE_NONE, muted("-"))
    setLine(receipt.cut, string.format(L.RECEIPT_CUT, math.floor(cut * 100 + 0.5)), muted("-"))
    setLine(receipt.deposit, L.RECEIPT_DEPOSIT, muted("-"))
    detail.depositRow.tooltip = nil
  end
  setLine(receipt.materials, L.RECEIPT_MATERIALS, "-" .. money(result.materialCost))
  if result.status == "ok" then
    detail.profit.value:SetText(signedMoney(result.profit) .. "  " .. percent(result.margin))
  else
    detail.profit.value:SetText(statusLabel(result))
  end
end

local function refreshBuyButton(detail, result)
  local purchase = ns.purchase
  local button = detail.buy
  if purchase.state == "quoting" then
    button:SetText(L.BUY_WAITING)
    button:Disable()
  elseif purchase.state == "ready" then
    button:SetText(string.format(L.BUY_CONFIRM, ns.Money.Format(purchase.quote.totalPrice)))
    button:Enable()
  elseif purchase.state == "purchasing" then
    button:SetText(L.BUY_PURCHASING)
    button:Disable()
  else
    local nextPurchase = result and ns.auctionOpen and ns.session:NextPurchase(result)
    if nextPurchase then
      button:SetText(string.format(L.BUY_NEXT, nextPurchase.quantity, ns.ItemName(nextPurchase.itemID))
        .. " (" .. ns.Money.Format(nextPurchase.expectedTotal) .. ")")
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

-- Pista del siguiente paso (en gris) cuando no hay ningún mensaje de error que mostrar.
local function hintFor(step, result)
  if step == "buy" then
    return ns.purchase.state == "ready" and L.HINT_CONFIRM or L.HINT_BUY
  elseif step == "craft" then
    return L.HINT_CRAFT
  elseif step == "post" then
    return L.HINT_POST
  end
  if not result then
    return ""
  end
  local shopping = ns.session:ShoppingList(result)
  if #shopping.vendor > 0 then
    return string.format(L.HINT_VENDOR, itemList(shopping.vendor))
  end
  if #shopping.missing > 0 then
    return L.HINT_MISSING
  end
  if not ns.auctionOpen then
    return L.NEEDS_AH
  end
  return ""
end

local function refreshActions(detail, result)
  local purchaseCancelable = ns.purchase.state == "quoting" or ns.purchase.state == "ready"
  detail.cancel:SetEnabled(purchaseCancelable or ns.post.state == "confirm")
  refreshBuyButton(detail, result)
  refreshPostButton(detail, result and result.recipe)
  local craftCount = result and math.min(UI.crafts, result.craftable) or 0
  detail.craft:SetText(string.format(L.CRAFT, craftCount))
  detail.craft:SetEnabled(craftCount > 0)

  local step = UI.RecommendedStep(result)
  W.SetButtonStyle(detail.buy, step == "buy" and "primary" or "secondary")
  W.SetButtonStyle(detail.craft, step == "craft" and "primary" or "secondary")
  W.SetButtonStyle(detail.post, step == "post" and "primary" or "secondary")

  if UI.message then
    detail.message:SetText(colored(CODES.red, UI.message))
  else
    detail.message:SetText(muted(hintFor(step, result)))
  end
end

function UI.RefreshDetail()
  local detail = UI.detail
  local result = UI.SelectedResult()
  refreshActions(detail, result)

  if not result then
    detail.content:Hide()
    detail.empty:Show()
    detail.minus:Disable()
    detail.plus:Disable()
    return
  end
  detail.empty:Hide()
  detail.content:Show()

  local recipe = result.recipe
  W.SetIcon(detail.icon, recipe.outputItemID)
  detail.title:SetText(recipeName(recipe))
  local subtitle = result.craftable > 0 and string.format(L.DETAIL_CAN_MAKE, result.craftable) or L.DETAIL_CANNOT_MAKE
  if recipe.profession then
    subtitle = recipe.profession .. "  -  " .. subtitle
  end
  detail.subtitle:SetText(subtitle)
  detail.craftsText:SetText(tostring(UI.crafts))
  detail.minus:SetEnabled(UI.crafts > 1)
  detail.plus:SetEnabled(UI.crafts < MAX_CRAFTS)

  refreshMaterials(detail, result)
  refreshShopping(detail, ns.session:ShoppingList(result))
  refreshReceipt(detail, result)
end

local function countProfitable(results)
  local count = 0
  for _, result in ipairs(results) do
    if result.status == "ok" and result.profit > 0 then
      count = count + 1
    end
  end
  return count
end

function UI.RefreshStatus()
  local scanning = ns.scanner:IsRunning()
  local status = UI.status
  local text
  local fraction = 0
  if scanning then
    local done, total = ns.scanner:Progress()
    text = string.format(L.SCANNING, done, total)
    fraction = total > 0 and done / total or 0
  elseif not ns.recipeDB:HasRecipes() then
    text = L.STATUS_NO_RECIPES
  elseif not ns.auctionOpen then
    text = L.STATUS_NEEDS_AH
  elseif ns.lastScanAt then
    text = string.format(L.PRICES_AT, date("%H:%M", ns.lastScanAt))
  else
    text = L.SCAN_HINT
  end
  status.label:SetText(text)
  if fraction > 0 then
    status.fill:SetWidth(math.max(1, math.floor((STATUS_WIDTH - 2) * math.min(1, fraction))))
    status.fill:Show()
  else
    status.fill:Hide()
  end

  UI.scanButton:SetEnabled(ns.auctionOpen == true and not scanning and ns.recipeDB:HasRecipes())
  W.SetButtonStyle(UI.scanButton, ns.lastScanAt and "secondary" or "primary")

  local cut, isAuto = ns.session:CurrentCut()
  UI.cutButton:SetText(string.format(L.CUT_LABEL, math.floor(cut * 100 + 0.5), isAuto and L.CUT_AUTO or L.CUT_MANUAL))

  if #UI.results > 0 then
    UI.subtitle:SetText(string.format(L.SUBTITLE, countProfitable(UI.results), #UI.results))
  else
    UI.subtitle:SetText("")
  end
end

local function containsRecipe(results, recipeID)
  for _, result in ipairs(results) do
    if result.recipe.recipeID == recipeID then
      return true
    end
  end
  return false
end

function UI.Refresh()
  UI.dirty = false
  if not (UI.frame and UI.frame:IsShown() and ns.session) then
    return
  end
  UI.results = ns.session:EvaluateAll()
  UI.offset = math.max(0, math.min(UI.offset, #UI.results - ROW_COUNT))
  -- Si no hay receta elegida (o ya no existe), se elige la más rentable.
  if not (UI.selectedRecipeID and containsRecipe(UI.results, UI.selectedRecipeID)) then
    UI.selectedRecipeID = UI.results[1] and UI.results[1].recipe.recipeID or nil
    UI.crafts = 1
  end
  UI.emptyText:SetText(#UI.results == 0 and L.EMPTY_NO_RECIPES or "")
  UI.RefreshStatus()
  refreshHeaders()
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
