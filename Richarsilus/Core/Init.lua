-- Richarsilus: tabla compartida del addon, valores por defecto y base de datos guardada.
-- Este fichero no usa ninguna API de WoW para poder probarse fuera del juego.
local addonName, ns = ...

ns.name = addonName

ns.defaults = {
  -- "auto" detecta casa de subastas neutral por mapa; también admite 0.05 o 0.15.
  cut = "auto",
  -- Cobre que se rebaja respecto a la subasta ajena más barata al publicar.
  undercut = 1,
  -- Índice de duración de la API (ver ns.DURATION_HOURS): 1 = 2 h, 2 = 8 h, 3 = 24 h.
  duration = 2,
  -- El depósito se devuelve al vender; contarlo como coste es la opción conservadora.
  includeDeposit = true,
  -- Igual que la interfaz de Blizzard: si el precio confirmado sube más de un 5 %, no se compra.
  maxPriceIncrease = 1.05,
  -- Columna por la que se ordena la tabla de recetas (ver Session.SORT_KEYS).
  sortKey = "profit",
}

-- Horas de cada duración de subasta en Forever, por índice de la API. Más horas = más depósito.
ns.DURATION_HOURS = { 2, 8, 24 }

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
