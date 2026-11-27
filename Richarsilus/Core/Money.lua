-- Formato de cantidades de dinero (cobre) como texto "1g 2s 3c".
local _, ns = ...

local Money = {}
ns.Money = Money

local COPPER_PER_SILVER = 100
local COPPER_PER_GOLD = 10000

-- Colores de las monedas del juego para las letras g, s y c (como en la interfaz de Blizzard).
Money.COIN_COLORS = { g = "|cffffd100", s = "|cffc7c7cf", c = "|cffeda55f" }

-- Devuelve las partes ("1g", "2s", "3c") y el signo de una cantidad.
local function splitCoins(copper)
  local rounded = math.floor((copper or 0) + 0.5)
  local sign = rounded < 0 and "-" or ""
  local absolute = math.abs(rounded)

  local gold = math.floor(absolute / COPPER_PER_GOLD)
  local silver = math.floor((absolute % COPPER_PER_GOLD) / COPPER_PER_SILVER)
  local remainingCopper = absolute % COPPER_PER_SILVER

  local list = {}
  if gold > 0 then
    list[#list + 1] = gold .. "g"
  end
  if silver > 0 then
    list[#list + 1] = silver .. "s"
  end
  if remainingCopper > 0 or #list == 0 then
    list[#list + 1] = remainingCopper .. "c"
  end
  return list, sign
end

function Money.Format(copper)
  local list, sign = splitCoins(copper)
  return sign .. table.concat(list, " ")
end

-- Igual que Format, pero con la letra de cada moneda en su color: "1|cffffd100g|r 2|cffc7c7cfs|r".
-- Úsalo en textos sin color propio (un |r dentro de otro color lo cortaría).
function Money.FormatColored(copper)
  local list, sign = splitCoins(copper)
  for index, part in ipairs(list) do
    local unit = string.sub(part, -1)
    list[index] = string.sub(part, 1, -2) .. Money.COIN_COLORS[unit] .. unit .. "|r"
  end
  return sign .. table.concat(list, " ")
end
