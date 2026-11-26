-- Formato de cantidades de dinero (cobre) como texto "1g 2s 3c".
local _, ns = ...

local Money = {}
ns.Money = Money

local COPPER_PER_SILVER = 100
local COPPER_PER_GOLD = 10000

function Money.Format(copper)
  local rounded = math.floor((copper or 0) + 0.5)
  local sign = rounded < 0 and "-" or ""
  local absolute = math.abs(rounded)

  local gold = math.floor(absolute / COPPER_PER_GOLD)
  local silver = math.floor((absolute % COPPER_PER_GOLD) / COPPER_PER_SILVER)
  local remainingCopper = absolute % COPPER_PER_SILVER

  local parts = {}
  if gold > 0 then
    parts[#parts + 1] = gold .. "g"
  end
  if silver > 0 then
    parts[#parts + 1] = silver .. "s"
  end
  if remainingCopper > 0 or #parts == 0 then
    parts[#parts + 1] = remainingCopper .. "c"
  end
  return sign .. table.concat(parts, " ")
end
