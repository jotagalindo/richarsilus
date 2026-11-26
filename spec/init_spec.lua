local loader = require("loader")

describe("Init", function()
  local ns

  before_each(function()
    ns = loader.load({ "Core/Init.lua" })
  end)

  it("defines default settings", function()
    assert.are.equal("auto", ns.defaults.cut)
    assert.are.equal(1, ns.defaults.undercut)
    assert.are.equal(2, ns.defaults.duration)
    assert.is_true(ns.defaults.includeDeposit)
    assert.are.equal(1.05, ns.defaults.maxPriceIncrease)
  end)

  it("creates a database with defaults when there is none", function()
    local database = ns.InitDB(nil, "Tester-Realm")
    assert.are.equal("auto", database.settings.cut)
    assert.are.same({}, database.prices)
    assert.are.same({}, database.vendor)
    assert.are.same({}, database.characters["Tester-Realm"].professions)
  end)

  it("keeps saved settings and fills in missing ones", function()
    local database = ns.InitDB({ settings = { undercut = 5 } }, "Tester-Realm")
    assert.are.equal(5, database.settings.undercut)
    assert.are.equal(2, database.settings.duration)
  end)

  it("falls back to the key for missing translations", function()
    assert.are.equal("SOME_MISSING_KEY", ns.L.SOME_MISSING_KEY)
  end)
end)
