local loader = require("loader")

describe("PriceDB", function()
  local PriceDB
  local saved
  local now

  local function clock()
    return now
  end

  before_each(function()
    PriceDB = loader.load({ "Core/Init.lua", "Core/PriceDB.lua" }).PriceDB
    saved = { prices = {}, vendor = {} }
    now = 1000
  end)

  it("sorts listings from cheapest to most expensive", function()
    local database = PriceDB.New(saved, clock)
    database:SetListings(1, { { unitPrice = 30, quantity = 1 }, { unitPrice = 10, quantity = 2 } }, true)
    local listings = database:GetListings(1)
    assert.are.equal(10, listings[1].unitPrice)
    assert.are.equal(30, listings[2].unitPrice)
  end)

  it("does not modify the list it receives", function()
    local database = PriceDB.New(saved, clock)
    local original = { { unitPrice = 30, quantity = 1 }, { unitPrice = 10, quantity = 2 } }
    database:SetListings(1, original, true)
    assert.are.equal(30, original[1].unitPrice)
  end)

  it("saves the minimum price and scan time", function()
    local database = PriceDB.New(saved, clock)
    database:SetListings(1, { { unitPrice = 30, quantity = 1 }, { unitPrice = 10, quantity = 2 } }, true)
    local price, scannedAt = database:GetMinPrice(1)
    assert.are.equal(10, price)
    assert.are.equal(1000, scannedAt)
    assert.are.same({ min = 10, t = 1000, commodity = true }, saved.prices[1])
  end)

  it("remembers saved minimum prices across sessions but not listings", function()
    PriceDB.New(saved, clock):SetListings(1, { { unitPrice = 10, quantity = 2 } }, false)
    local reloaded = PriceDB.New(saved, clock)
    assert.are.equal(10, (reloaded:GetMinPrice(1)))
    assert.are.same({}, reloaded:GetListings(1))
    assert.is_false(reloaded:IsCommodity(1))
  end)

  it("records an empty market", function()
    local database = PriceDB.New(saved, clock)
    database:SetListings(5, {}, true)
    assert.is_nil((database:GetMinPrice(5)))
    assert.is_true(database:HasScanned(5))
    assert.is_false(database:HasScanned(6))
  end)

  it("reports unknown commodity status as nil", function()
    assert.is_nil(PriceDB.New(saved, clock):IsCommodity(42))
  end)

  it("stores vendor prices", function()
    local database = PriceDB.New(saved, clock)
    assert.is_nil(database:GetVendorPrice(3371))
    database:SetVendorPrice(3371, 4)
    assert.are.equal(4, database:GetVendorPrice(3371))
    assert.are.equal(4, saved.vendor[3371])
  end)
end)
