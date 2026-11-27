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
    assert.are.same({}, database.deposits)
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

  it("reads the auction durations from the game's own texts", function()
    local options = ns.DurationOptions({
      AUCTION_DURATION_ONE = "2 Horas", AUCTION_DURATION_TWO = "8 Horas", AUCTION_DURATION_THREE = "24 Horas",
    })
    assert.are.same({
      { label = "2 Horas", hours = 2 }, { label = "8 Horas", hours = 8 }, { label = "24 Horas", hours = 24 },
    }, options)
    assert.are.same({ {}, {}, {} }, ns.DurationOptions({}))
  end)

  it("finds a duration by its hours, or by option number when the game gives no hours", function()
    local hours = ns.DurationOptions({
      AUCTION_DURATION_ONE = "12 Hours", AUCTION_DURATION_TWO = "24 Hours", AUCTION_DURATION_THREE = "48 Hours",
    })
    assert.are.equal(2, ns.DurationIndex(hours, 24))
    assert.is_nil(ns.DurationIndex(hours, 2))
    local named = ns.DurationOptions({
      AUCTION_DURATION_ONE = "Short", AUCTION_DURATION_TWO = "Medium", AUCTION_DURATION_THREE = "Long",
    })
    assert.are.equal(2, ns.DurationIndex(named, 2))
    assert.is_nil(ns.DurationIndex(named, 24))
  end)
end)
