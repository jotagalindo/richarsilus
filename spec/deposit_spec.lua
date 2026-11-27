local loader = require("loader")

describe("DepositBook", function()
  local DepositBook
  local saved
  local book

  before_each(function()
    DepositBook = loader.load({ "Core/Init.lua", "Core/Deposit.lua" }).DepositBook
    saved = {}
    book = DepositBook.New(saved)
  end)

  it("knows nothing at first", function()
    local amount, source = book:Estimate(10, "2:faction", 3, 500)
    assert.is_nil(amount)
    assert.are.equal("unknown", source)
  end)

  it("remembers the deposit the game gave for an item, per duration and auction house", function()
    book:Observe(10, "2:faction", 120, 400)
    assert.are.same({ 360, "remembered" }, { book:Estimate(10, "2:faction", 3, 400) })
    assert.are.same({ nil, "unknown" }, { book:Estimate(10, "3:faction", 3, nil) })
    assert.are.equal(120, saved.items[10]["2:faction"])
  end)

  it("estimates unseen items from their vendor sell price with the rate learned from another item", function()
    book:Observe(10, "2:faction", 300, 1000)
    -- 30 % del precio de venta al vendedor, por unidad.
    assert.are.same({ 1200, "estimated" }, { book:Estimate(20, "2:faction", 2, 2000) })
    assert.are.same({ nil, "unknown" }, { book:Estimate(20, "2:neutral", 2, 2000) })
    assert.are.same({ nil, "unknown" }, { book:Estimate(20, "2:faction", 2, nil) })
  end)

  it("learns the rate from the item with the highest sell price, where the minimum deposit distorts least", function()
    book:Observe(10, "2:faction", 100, 10)
    book:Observe(11, "2:faction", 600, 2000)
    book:Observe(12, "2:faction", 100, 50)
    assert.are.same({ ratio = 0.3, sellPrice = 2000 }, saved.rates["2:faction"])
  end)

  it("never estimates below the smallest deposit seen, which works as the minimum per auction", function()
    book:Observe(10, "2:faction", 100, 10)
    book:Observe(11, "2:faction", 600, 2000)
    assert.are.same({ 200, "estimated" }, { book:Estimate(20, "2:faction", 2, 5) })
  end)

  it("ignores observations that cannot teach a rate", function()
    book:Observe(10, "2:faction", 0, 1000)
    book:Observe(11, "2:faction", 50, 0)
    book:Observe(12, "2:faction", 50, nil)
    assert.is_nil(saved.rates["2:faction"])
    assert.are.same({ 100, "remembered" }, { book:Estimate(11, "2:faction", 2, 0) })
  end)

  it("keeps working with a saved table from an older version", function()
    saved = { items = "broken" }
    book = DepositBook.New(saved)
    book:Observe(10, "1:faction", 40, 100)
    assert.are.same({ 40, "remembered" }, { book:Estimate(10, "1:faction", 1, 100) })
  end)
end)
