-- Prueba los botones planos de UI/Widgets.lua sobre el cliente simulado.
local stub = require("wow_stub")
local loader = require("loader")

describe("Widgets", function()
  local W

  before_each(function()
    stub.install({ itemNames = {}, merchant = {}, tradeSkill = {} })
    W = loader.load({ "Core/Init.lua", "UI/Widgets.lua" }).Widgets
  end)

  it("shows a button's text in its own label", function()
    local button = W.Button(UIParent, 100, 24, function() end)
    button:SetText("Escanear")
    assert.are.equal("Escanear", button:GetText())
    assert.are.equal("Escanear", button.label:GetText())
  end)

  it("repaints a button when it is disabled, enabled or restyled", function()
    local button = W.Button(UIParent, 100, 24, function() end, "primary")
    local primaryText = button.label.textColor
    button:Disable()
    assert.are_not.same(primaryText, button.label.textColor)
    button:Enable()
    assert.are.same(primaryText, button.label.textColor)
    W.SetButtonStyle(button, "secondary")
    assert.are.equal("secondary", button.style)
    assert.are_not.same(primaryText, button.label.textColor)
  end)

  it("shows a tooltip with a title and lines on hover", function()
    local button = W.Button(UIParent, 100, 24, function() end)
    button.tooltip = { title = "Comprar", lines = { "Primero pide el precio." } }
    button:GetScript("OnEnter")(button)
    assert.are.equal("Comprar", stub.tooltip.title)
    assert.are.same({ "Primero pide el precio." }, stub.tooltip.lines)
    button:GetScript("OnLeave")(button)
    assert.is_false(stub.tooltip.shown)
  end)

  it("shows the item icon or hides it", function()
    local icon = W.Icon(UIParent, 16)
    W.SetIcon(icon, 42)
    assert.are.equal(100042, icon.image.texture)
    assert.is_true(icon:IsShown())
    W.SetIcon(icon, nil)
    assert.is_false(icon:IsShown())
  end)
end)
