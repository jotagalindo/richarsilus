-- Carga ficheros del addon igual que el cliente de WoW: cada fichero recibe
-- (nombreDelAddon, tablaCompartida) como argumentos varargs.
local loader = {}

local ADDON_DIR = "Richarsilus/"

function loader.load(files, sharedTable)
  local addonTable = sharedTable or {}
  for _, relativePath in ipairs(files) do
    local chunk, loadError = loadfile(ADDON_DIR .. relativePath)
    if not chunk then
      error(loadError)
    end
    chunk("Richarsilus", addonTable)
  end
  return addonTable
end

return loader
