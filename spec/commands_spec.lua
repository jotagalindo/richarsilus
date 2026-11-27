local loader = require("loader")

describe("ParseCommand", function()
  local ParseCommand

  before_each(function()
    ParseCommand = loader.load({ "Core/Init.lua", "Core/Commands.lua" }).ParseCommand
  end)

  it("toggles the window without arguments", function()
    assert.are.same({ action = "toggle" }, ParseCommand(""))
    assert.are.same({ action = "toggle" }, ParseCommand("   "))
  end)

  it("accepts Spanish and English words", function()
    assert.are.same({ action = "scan" }, ParseCommand("escanear"))
    assert.are.same({ action = "scan" }, ParseCommand("SCAN"))
    assert.are.same({ action = "help" }, ParseCommand("ayuda"))
    assert.are.same({ action = "help" }, ParseCommand("help"))
  end)

  it("parses the auction house cut", function()
    assert.are.same({ action = "cut", value = 0.05 }, ParseCommand("comision 5"))
    assert.are.same({ action = "cut", value = 0.15 }, ParseCommand("cut 15"))
    assert.are.same({ action = "cut", value = "auto" }, ParseCommand("comision auto"))
    assert.are.same({ action = "invalid", command = "cut" }, ParseCommand("comision 7"))
  end)

  it("parses the undercut in copper", function()
    assert.are.same({ action = "undercut", value = 25 }, ParseCommand("rebaja 25"))
    assert.are.same({ action = "undercut", value = 0 }, ParseCommand("undercut 0"))
    assert.are.same({ action = "invalid", command = "undercut" }, ParseCommand("rebaja -3"))
    assert.are.same({ action = "invalid", command = "undercut" }, ParseCommand("rebaja abc"))
  end)

  it("parses the deposit option", function()
    assert.are.same({ action = "deposit", value = true }, ParseCommand("deposito on"))
    assert.are.same({ action = "deposit", value = false }, ParseCommand("deposit off"))
    assert.are.same({ action = "deposit", value = true }, ParseCommand("depósito si"))
    assert.are.same({ action = "invalid", command = "deposit" }, ParseCommand("deposito quizas"))
  end)

  it("parses the posting duration in hours", function()
    -- Las horas válidas las da el juego al ejecutar el comando; aquí solo se lee el número.
    assert.are.same({ action = "duration", value = 24 }, ParseCommand("duracion 24"))
    assert.are.same({ action = "duration", value = 8 }, ParseCommand("duración 8"))
    assert.are.same({ action = "duration" }, ParseCommand("duration"))
    assert.are.same({ action = "invalid", command = "duration" }, ParseCommand("duracion larga"))
  end)

  it("parses the command that forgets saved recipes", function()
    assert.are.same({ action = "forget" }, ParseCommand("olvidar"))
    assert.are.same({ action = "forget" }, ParseCommand("forget"))
  end)

  it("reports unknown commands", function()
    assert.are.same({ action = "unknown", word = "bailar" }, ParseCommand("bailar"))
  end)
end)
