-- Piezas visuales de la ventana: colores del tema, paneles, bordes, textos, botones, iconos y tooltips.
-- Todo se dibuja con texturas de color liso (SetColorTexture), sin depender de las plantillas de
-- Blizzard, para que la ventana se vea igual en cualquier cliente y en la vista previa del README.
local _, ns = ...

local Widgets = {}
ns.Widgets = Widgets

-- Colores RGBA (0-1).
local COLORS = {
  window = { 0.051, 0.055, 0.067, 0.97 },
  titleBar = { 0.078, 0.082, 0.098, 1 },
  card = { 0.075, 0.08, 0.094, 1 },
  well = { 0.043, 0.047, 0.055, 1 },
  border = { 0.2, 0.21, 0.24, 1 },
  divider = { 0.15, 0.16, 0.19, 1 },
  stripe = { 1, 1, 1, 0.025 },
  hover = { 1, 1, 1, 0.06 },
  selected = { 1, 0.82, 0, 0.1 },
  accent = { 1, 0.82, 0, 1 },
  progress = { 1, 0.82, 0, 0.22 },
  scrollTrack = { 1, 1, 1, 0.05 },
  scrollThumb = { 1, 1, 1, 0.25 },
  title = { 1, 0.82, 0, 1 },
  text = { 0.92, 0.91, 0.88, 1 },
  muted = { 0.56, 0.58, 0.62, 1 },
}
Widgets.COLORS = COLORS

-- Códigos de color para dentro de los textos.
Widgets.CODES = {
  green = "|cff4cd07d",
  red = "|cffff5f5f",
  muted = "|cff8f949c",
  gold = "|cffffd100",
  vendor = "|cfff0b44c",
  text = "|cffebe8e0",
  stop = "|r",
}

-- Estilos de botón: principal (el siguiente paso recomendado), secundario y fantasma (sin fondo).
local BUTTON_STYLES = {
  primary = {
    background = { 0.5, 0.36, 0.05, 1 },
    hover = { 0.62, 0.45, 0.08, 1 },
    border = { 0.85, 0.65, 0.18, 1 },
    text = { 1, 0.95, 0.8, 1 },
  },
  secondary = {
    background = { 0.13, 0.14, 0.165, 1 },
    hover = { 0.18, 0.19, 0.225, 1 },
    border = { 0.26, 0.275, 0.31, 1 },
    text = { 0.92, 0.91, 0.88, 1 },
  },
  ghost = {
    background = { 0, 0, 0, 0 },
    hover = { 0.75, 0.2, 0.2, 0.5 },
    border = { 0, 0, 0, 0 },
    text = { 0.7, 0.72, 0.76, 1 },
  },
}
local DISABLED_STYLE = {
  background = { 0.085, 0.09, 0.105, 1 },
  border = { 0.15, 0.16, 0.18, 1 },
  text = { 0.38, 0.4, 0.43, 1 },
}

local QUESTION_MARK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function setColor(texture, color)
  texture:SetColorTexture(color[1], color[2], color[3], color[4])
end

function Widgets.Texture(parent, color, layer)
  local texture = parent:CreateTexture(nil, layer or "ARTWORK")
  setColor(texture, color)
  return texture
end

-- Textura que cubre todo el marco.
function Widgets.Fill(parent, color, layer)
  local texture = Widgets.Texture(parent, color, layer or "BACKGROUND")
  texture:SetAllPoints()
  return texture
end

-- Borde de 1 px alrededor del marco (cuatro texturas).
function Widgets.Border(parent, color)
  local edges = {}
  local function edge(firstPoint, secondPoint, horizontal)
    local texture = Widgets.Texture(parent, color, "BORDER")
    texture:SetPoint(firstPoint)
    texture:SetPoint(secondPoint)
    if horizontal then
      texture:SetHeight(1)
    else
      texture:SetWidth(1)
    end
    edges[#edges + 1] = texture
  end
  edge("TOPLEFT", "TOPRIGHT", true)
  edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
  edge("TOPLEFT", "BOTTOMLEFT", false)
  edge("TOPRIGHT", "BOTTOMRIGHT", false)
  return edges
end

function Widgets.SetBorderColor(edges, color)
  for _, texture in ipairs(edges) do
    setColor(texture, color)
  end
end

-- Fondo y borde para un marco.
function Widgets.Panel(frame, background, border)
  frame.background = Widgets.Fill(frame, background)
  frame.border = Widgets.Border(frame, border or COLORS.border)
  return frame
end

-- Línea horizontal de 1 px entre dos puntos: Widgets.Divider(parent, "TOPLEFT", x1, y, "TOPRIGHT", x2, y).
function Widgets.Divider(parent, leftPoint, leftX, y, rightPoint, rightX, rightY)
  local line = Widgets.Texture(parent, COLORS.divider, "BORDER")
  line:SetPoint(leftPoint, parent, leftPoint, leftX, y)
  line:SetPoint(rightPoint, parent, rightPoint, rightX, rightY or y)
  line:SetHeight(1)
  return line
end

function Widgets.Text(parent, template, color, justify, width)
  local text = parent:CreateFontString(nil, "OVERLAY", template)
  if color then
    text:SetTextColor(color[1], color[2], color[3], color[4])
  end
  text:SetJustifyH(justify or "LEFT")
  if width then
    text:SetWidth(width)
  end
  return text
end

---------------------------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------------------------
-- `frame.tooltip` es una tabla { title, lines } o { itemID }, o una función que la devuelve.
local function showTooltip(owner)
  local tooltip = owner.tooltip
  if type(tooltip) == "function" then
    tooltip = tooltip(owner)
  end
  if not (tooltip and GameTooltip) then
    return
  end
  GameTooltip:SetOwner(owner, "ANCHOR_TOP")
  if tooltip.itemID then
    GameTooltip:SetItemByID(tooltip.itemID)
  else
    GameTooltip:SetText(tooltip.title, COLORS.title[1], COLORS.title[2], COLORS.title[3])
    for _, line in ipairs(tooltip.lines or {}) do
      GameTooltip:AddLine(line, COLORS.text[1], COLORS.text[2], COLORS.text[3], true)
    end
  end
  GameTooltip:Show()
end

local function hideTooltip(owner)
  if GameTooltip and owner.tooltip then
    GameTooltip:Hide()
  end
end

-- Muestra un tooltip al pasar el ratón por un marco que no es botón.
function Widgets.SetTooltip(frame, tooltip)
  frame.tooltip = tooltip
  if not frame.hasTooltipScripts then
    frame.hasTooltipScripts = true
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", showTooltip)
    frame:SetScript("OnLeave", hideTooltip)
  end
end

---------------------------------------------------------------------------------------------
-- Botones
---------------------------------------------------------------------------------------------
local function paintButton(button)
  local style = button:IsEnabled() and BUTTON_STYLES[button.style] or DISABLED_STYLE
  local background = button.hovered and button:IsEnabled() and style.hover or style.background
  setColor(button.background, background)
  Widgets.SetBorderColor(button.border, style.border)
  button.label:SetTextColor(style.text[1], style.text[2], style.text[3], style.text[4])
end

function Widgets.SetButtonStyle(button, style)
  if button.style ~= style then
    button.style = style
    paintButton(button)
  end
end

-- Botón plano con texto. `onClick` se ejecuta con el clic del jugador (OnClick).
function Widgets.Button(parent, width, height, onClick, style, template)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(width, height)
  button.style = style or "secondary"
  button.background = Widgets.Fill(button, BUTTON_STYLES[button.style].background)
  button.border = Widgets.Border(button, BUTTON_STYLES[button.style].border)
  button.label = Widgets.Text(button, template or "GameFontHighlight", nil, "CENTER")
  button.label:SetPoint("LEFT", button, "LEFT", 6, 0)
  button.label:SetPoint("RIGHT", button, "RIGHT", -6, 0)
  button.label:SetWordWrap(false)
  button:SetFontString(button.label)
  button:SetScript("OnClick", onClick)
  -- Que el tooltip salga también con el botón desactivado: así explica por qué no se puede pulsar.
  if button.SetMotionScriptsWhileDisabled then
    button:SetMotionScriptsWhileDisabled(true)
  end
  button:SetScript("OnEnable", paintButton)
  button:SetScript("OnDisable", paintButton)
  button:SetScript("OnEnter", function(self)
    self.hovered = true
    paintButton(self)
    showTooltip(self)
  end)
  button:SetScript("OnLeave", function(self)
    self.hovered = false
    paintButton(self)
    hideTooltip(self)
  end)
  paintButton(button)
  return button
end

---------------------------------------------------------------------------------------------
-- Iconos de objeto
---------------------------------------------------------------------------------------------
local function itemIcon(itemID)
  local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
  return icon or QUESTION_MARK_ICON
end

-- Icono cuadrado con borde fino. Widgets.SetIcon(icon, itemID) cambia el objeto.
function Widgets.Icon(parent, size)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetSize(size, size)
  frame.border = Widgets.Fill(frame, COLORS.border)
  frame.image = frame:CreateTexture(nil, "ARTWORK")
  frame.image:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  frame.image:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
  -- Recorta el marco que traen los iconos del juego.
  frame.image:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  return frame
end

function Widgets.SetIcon(icon, itemID)
  if itemID then
    icon.image:SetTexture(itemIcon(itemID))
    icon:Show()
  else
    icon:Hide()
  end
end
