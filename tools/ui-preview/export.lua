-- Uso (desde la raíz del repositorio): lua5.1 tools/ui-preview/export.lua [fichero de salida]
-- Escribe el diseño de las escenas para tools/ui-preview/preview.html (por defecto tools/ui-preview/scenes.js).
package.path = "./spec/helpers/?.lua;./tools/ui-preview/?.lua;" .. package.path

local exporter = require("layout_export")

local outputPath = ... or "tools/ui-preview/scenes.js"
local scenes = exporter.BuildScenes()
local file = assert(io.open(outputPath, "w"))
file:write(exporter.ToJavaScript(scenes))
file:close()

local names = {}
for index, scene in ipairs(scenes) do
  names[index] = scene.name
end
print(string.format("%s: %s", outputPath, table.concat(names, ", ")))
