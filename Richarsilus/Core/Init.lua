-- Richarsilus: tabla compartida del addon, valores por defecto y base de datos guardada.
-- Este fichero no usa ninguna API de WoW para poder probarse fuera del juego.
local addonName, ns = ...

ns.name = addonName

ns.defaults = {
  -- "auto" detecta casa de subastas neutral por mapa; también admite 0.05 o 0.15.
  cut = "auto",
  -- Cobre que se rebaja respecto a la subasta ajena más barata al publicar.
  undercut = 1,
  -- Índice de duración de la API: 1 = la más corta, 2 = la del medio, 3 = la más larga.
  -- Las horas de cada una las dice el propio juego (ver ns.DurationOptions).
  duration = 2,
  -- El depósito se devuelve al vender; contarlo como coste es la opción conservadora.
  includeDeposit = true,
  -- Igual que la interfaz de Blizzard: si el precio confirmado sube más de un 5 %, no se compra.
  maxPriceIncrease = 1.05,
  -- Columna por la que se ordena la tabla de recetas (ver Session.SORT_KEYS).
  sortKey = "profit",
}

-- Textos del juego con las duraciones de subasta (los mismos que muestra el desplegable de la ventana de
-- venta de Blizzard), por índice de la API. Más duración = más depósito.
ns.DURATION_STRINGS = { "AUCTION_DURATION_ONE", "AUCTION_DURATION_TWO", "AUCTION_DURATION_THREE" }

-- Opciones de duración tal y como las nombra el juego: { { label = "8 Horas", hours = 8 }, ... }.
-- `strings` es la tabla de textos globales (_G en el juego). Si falta un texto, label y hours son nil.
function ns.DurationOptions(strings)
  local source = strings or _G
  local options = {}
  for index, name in ipairs(ns.DURATION_STRINGS) do
    local label = source[name]
    if type(label) ~= "string" or label == "" then
      label = nil
    end
    options[index] = { label = label, hours = label and tonumber(string.match(label, "%d+")) or nil }
  end
  return options
end

-- Índice de la duración que corresponde a `number`: primero se busca por horas ("/rs duracion 24");
-- si el juego no da horas en ninguno de sus textos, se acepta el número de opción (1, 2 o 3).
function ns.DurationIndex(options, number)
  local anyHours = false
  for index, option in ipairs(options) do
    if option.hours then
      anyHours = true
      if option.hours == number then
        return index
      end
    end
  end
  if not anyHours and options[number] then
    return number
  end
  return nil
end

ns.FACTION_CUT = 0.05
ns.NEUTRAL_CUT = 0.15

-- Traducciones: los ficheros de Locales rellenan esta tabla. Si falta una clave, se muestra la clave.
ns.L = setmetatable({}, {
  __index = function(_, key)
    return key
  end,
})

local function ensureTable(parent, key)
  if type(parent[key]) ~= "table" then
    parent[key] = {}
  end
  return parent[key]
end

-- Prepara la base de datos guardada (SavedVariables) y devuelve la tabla lista para usar.
function ns.InitDB(saved, characterKey)
  local database = type(saved) == "table" and saved or {}
  local settings = ensureTable(database, "settings")
  for key, value in pairs(ns.defaults) do
    if settings[key] == nil then
      settings[key] = value
    end
  end
  ensureTable(database, "prices")
  ensureTable(database, "vendor")
  ensureTable(database, "deposits")
  local characters = ensureTable(database, "characters")
  local character = ensureTable(characters, characterKey)
  ensureTable(character, "professions")
  return database
end
