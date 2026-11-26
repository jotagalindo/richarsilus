-- Comandos de chat /rs y /richarsilus. ParseCommand es puro; RunCommand aplica el resultado.
local _, ns = ...

local ACTION_WORDS = {
  escanear = "scan", scan = "scan",
  comision = "cut", ["comisión"] = "cut", cut = "cut",
  rebaja = "undercut", undercut = "undercut",
  deposito = "deposit", ["depósito"] = "deposit", deposit = "deposit",
  duracion = "duration", ["duración"] = "duration", duration = "duration",
  ayuda = "help", help = "help",
  olvidar = "forget", forget = "forget",
}

local CUT_VALUES = { ["5"] = ns.FACTION_CUT, ["15"] = ns.NEUTRAL_CUT, auto = "auto" }
local BOOLEAN_VALUES = { on = true, si = true, ["sí"] = true, yes = true, off = false, no = false }
local DURATION_VALUES = { ["12"] = 1, ["24"] = 2, ["48"] = 3 }

function ns.ParseCommand(text)
  local words = {}
  for word in string.gmatch(string.lower(text or ""), "%S+") do
    words[#words + 1] = word
  end
  if #words == 0 then
    return { action = "toggle" }
  end

  local action = ACTION_WORDS[words[1]]
  local argument = words[2]
  if not action then
    return { action = "unknown", word = words[1] }
  end

  if action == "scan" or action == "help" or action == "forget" then
    return { action = action }
  elseif action == "cut" then
    local value = CUT_VALUES[argument or ""]
    if value then
      return { action = "cut", value = value }
    end
  elseif action == "undercut" then
    local value = argument and string.match(argument, "^%d+$") and tonumber(argument)
    if value then
      return { action = "undercut", value = value }
    end
  elseif action == "deposit" then
    local value = BOOLEAN_VALUES[argument or ""]
    if value ~= nil then
      return { action = "deposit", value = value }
    end
  elseif action == "duration" then
    local value = DURATION_VALUES[argument or ""]
    if value then
      return { action = "duration", value = value }
    end
  end
  return { action = "invalid", command = action }
end

-- Aplica un comando ya analizado. `output(text)` escribe en el chat.
function ns.RunCommand(command, output)
  local L = ns.L
  local settings = ns.db and ns.db.settings
  if command.action == "toggle" then
    ns.UI.Toggle()
  elseif command.action == "scan" then
    ns.StartScan()
  elseif command.action == "help" or command.action == "unknown" or command.action == "invalid" then
    output(L.HELP)
  elseif command.action == "forget" then
    ns.recipeDB:Clear()
    output(L.RECIPES_FORGOTTEN)
  elseif command.action == "cut" then
    settings.cut = command.value
    output(L.CUT_SET)
  elseif command.action == "undercut" then
    settings.undercut = command.value
    output(string.format(L.UNDERCUT_SET, ns.Money.Format(command.value)))
  elseif command.action == "deposit" then
    settings.includeDeposit = command.value
    output(command.value and L.DEPOSIT_ON or L.DEPOSIT_OFF)
  elseif command.action == "duration" then
    settings.duration = command.value
    output(L.DURATION_SET)
  end
  ns.UI.Refresh()
end
