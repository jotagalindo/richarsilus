-- Prueba el exportador de tools/ui-preview, del que salen las imágenes de la interfaz del README.
package.path = "./tools/ui-preview/?.lua;" .. package.path
local exporter = require("layout_export")

local function regionWithText(layout, expected)
  for _, region in ipairs(layout.regions) do
    if region.text and string.find(region.text, expected, 1, true) then
      return region
    end
  end
  return nil
end

local function sceneNamed(scenes, name)
  for _, scene in ipairs(scenes) do
    if scene.name == name then
      return scene.layout
    end
  end
  error("no scene named " .. name)
end

describe("UI preview exporter", function()
  local scenes

  before_each(function()
    scenes = exporter.BuildScenes()
  end)

  it("exports the addon window with its real size and anchors", function()
    local layout = sceneNamed(scenes, "main")
    local root = layout.regions[layout.root]
    assert.are.equal(640, root.width)
    assert.are.equal(640, root.height)
    assert.is_nil(root.points)
    local twoPointRegions = 0
    for _, region in ipairs(layout.regions) do
      if region.id ~= layout.root then
        assert.is_true(region.points ~= nil or region.allPoints == true, "region without anchor: " .. region.id)
        for _, point in ipairs(region.points or {}) do
          assert.is_table(layout.regions[point.relativeTo])
        end
        if region.points and #region.points == 2 then
          twoPointRegions = twoPointRegions + 1
        end
      end
    end
    -- El fondo opaco se ancla por dos esquinas.
    assert.are.equal(1, twoPointRegions)
  end)

  it("shows the most profitable recipe selected with five crafts and the shopping list", function()
    local layout = sceneNamed(scenes, "main")
    assert.is_table(regionWithText(layout, "Escanear"))
    assert.is_table(regionWithText(layout, "Comisión 5% (auto)"))
    assert.is_table(regionWithText(layout, "x5"))
    assert.is_table(regionWithText(layout, "Flor de sueño: necesitas 10, tienes 6 - comprar 4 en la subasta (48s)"))
    assert.is_table(regionWithText(layout, "Subasta (botón Comprar, uno por clic): 4 Flor de sueño = 48s"))
    assert.is_table(regionWithText(layout, "Vendedor|r: 3 Vial imbuido = 54s"))
    assert.is_table(regionWithText(layout, "Total a gastar: 1g 2s"))
    local buy = assert(regionWithText(layout, "Comprar 4 Flor de sueño"))
    assert.is_true(buy.enabled)
    local craft = assert(regionWithText(layout, "Craftear 2"))
    assert.is_true(craft.enabled)
  end)

  it("shows the confirmation step after the first buy click", function()
    local layout = sceneNamed(scenes, "confirm")
    local confirm = assert(regionWithText(layout, "Confirmar 48s"))
    assert.is_true(confirm.enabled)
    assert.is_true(assert(regionWithText(layout, "Cancelar")).enabled)
  end)

  it("writes a script that defines every scene", function()
    local script = exporter.ToJavaScript(scenes)
    assert.is_truthy(string.find(script, "^window%.RICHARSILUS_SCENES = {"))
    assert.is_truthy(string.find(script, '"main":{', 1, true))
    assert.is_truthy(string.find(script, '"confirm":{', 1, true))
  end)

  it("escapes strings and keeps numbers and booleans as JSON", function()
    assert.are.equal('"a\\"b\\\\c\\nd\\u0001"', exporter.EncodeJson('a"b\\c\nd\1'))
    assert.are.equal('{"a":[1,2.5,true],"b":"ñ"}', exporter.EncodeJson({ b = "ñ", a = { 1, 2.5, true } }))
    assert.are.equal("-18", exporter.EncodeJson(-18))
    assert.has_error(function() exporter.EncodeJson({ [true] = 1 }) end)
  end)
end)
