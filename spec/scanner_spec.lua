local loader = require("loader")

local function fakeAuctionApi()
  local api = {
    ready = true,
    sent = {},
    commodityResults = {},
    itemResults = {},
  }
  function api.IsThrottledMessageSystemReady()
    return api.ready
  end
  function api.MakeItemKey(itemID)
    return { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
  end
  function api.SendSearchQuery(itemKey, sorts, separateOwnerItems)
    api.sent[#api.sent + 1] = { itemID = itemKey.itemID, sorts = sorts, separateOwnerItems = separateOwnerItems }
  end
  function api.GetNumCommoditySearchResults(itemID)
    return #(api.commodityResults[itemID] or {})
  end
  function api.GetCommoditySearchResultInfo(itemID, index)
    return api.commodityResults[itemID][index]
  end
  function api.GetNumItemSearchResults(itemKey)
    return #(api.itemResults[itemKey.itemID] or {})
  end
  function api.GetItemSearchResultInfo(itemKey, index)
    return api.itemResults[itemKey.itemID][index]
  end
  return api
end

describe("Scanner", function()
  local ns
  local api
  local priceDB
  local now
  local scanner
  local finished
  local progress
  local sorts

  before_each(function()
    ns = loader.load({ "Core/Init.lua", "Core/PriceDB.lua", "Core/Scanner.lua" })
    api = fakeAuctionApi()
    now = 100
    priceDB = ns.PriceDB.New({ prices = {}, vendor = {} }, function() return now end)
    sorts = { { sortOrder = 0, reverseSort = false } }
    scanner = ns.Scanner.New(api, priceDB, function() return now end, sorts)
    finished = nil
    progress = {}
    scanner.onFinished = function(done, total, aborted)
      finished = { done = done, total = total, aborted = aborted }
    end
    scanner.onProgress = function(done, total)
      progress[#progress + 1] = { done, total }
    end
  end)

  it("waits for Tick before sending a query", function()
    scanner:Start({ 1, 2 })
    assert.are.equal(0, #api.sent)
    assert.is_true(scanner:IsRunning())
    scanner:Tick()
    assert.are.equal(1, #api.sent)
    assert.are.equal(1, api.sent[1].itemID)
    assert.are.equal(sorts, api.sent[1].sorts)
    assert.is_true(api.sent[1].separateOwnerItems)
  end)

  it("does not send while the throttle system is busy", function()
    api.ready = false
    scanner:Start({ 1 })
    scanner:Tick()
    assert.are.equal(0, #api.sent)
  end)

  it("sends only one query at a time", function()
    scanner:Start({ 1, 2 })
    scanner:Tick()
    now = now + 5
    scanner:Tick()
    assert.are.equal(1, #api.sent)
  end)

  it("stores commodity results and waits at least one second between queries", function()
    api.commodityResults[1] = {
      { unitPrice = 50, quantity = 3, containsOwnerItem = false, auctionID = 11 },
      { unitPrice = 40, quantity = 2, containsOwnerItem = true, auctionID = 12 },
    }
    scanner:Start({ 1, 2 })
    scanner:Tick()
    scanner:OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 1)

    local listings = priceDB:GetListings(1)
    assert.are.equal(2, #listings)
    assert.are.same({ unitPrice = 40, quantity = 2, own = true, auctionID = 12 }, listings[1])
    assert.is_true(priceDB:IsCommodity(1))
    assert.are.same({ { 1, 2 } }, progress)

    now = now + 0.5
    scanner:Tick()
    assert.are.equal(1, #api.sent)
    now = now + 0.5
    scanner:Tick()
    assert.are.equal(2, #api.sent)
    assert.are.equal(2, api.sent[2].itemID)
  end)

  it("stores item results using the buyout per unit and skips bid-only auctions", function()
    api.itemResults[2] = {
      { buyoutAmount = 300, quantity = 2, containsOwnerItem = false, auctionID = 21 },
      { buyoutAmount = nil, bidAmount = 10, quantity = 1, containsOwnerItem = false, auctionID = 22 },
      { buyoutAmount = 100, quantity = 1, containsOwnerItem = false, auctionID = 23 },
    }
    scanner:Start({ 2 })
    scanner:Tick()
    scanner:OnEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 2, itemLevel = 0 }, nil)

    local listings = priceDB:GetListings(2)
    assert.are.equal(2, #listings)
    assert.are.same({ unitPrice = 100, quantity = 1, own = false, auctionID = 23, buyout = 100 }, listings[1])
    assert.are.same({ unitPrice = 150, quantity = 2, own = false, auctionID = 21, buyout = 300 }, listings[2])
    assert.is_false(priceDB:IsCommodity(2))
  end)

  it("ignores results for an item it is not waiting for", function()
    scanner:Start({ 1 })
    scanner:Tick()
    scanner:OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 99)
    assert.is_false(priceDB:HasScanned(99))
    assert.are.same({}, progress)
  end)

  it("skips an item that gets no answer within ten seconds", function()
    scanner:Start({ 1, 2 })
    scanner:Tick()
    now = now + 10.5
    scanner:Tick()
    assert.are.same({ { 1, 2 } }, progress)
    assert.is_false(priceDB:HasScanned(1))
    scanner:Tick()
    assert.are.equal(2, #api.sent)
    assert.are.equal(1, scanner:SkippedCount())
  end)

  it("reports completion after the last item", function()
    scanner:Start({ 1 })
    scanner:Tick()
    scanner:OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 1)
    assert.are.same({ done = 1, total = 1, aborted = false }, finished)
    assert.is_false(scanner:IsRunning())
  end)

  it("reports an aborted scan when stopped or when the auction house closes", function()
    scanner:Start({ 1, 2 })
    scanner:OnEvent("AUCTION_HOUSE_CLOSED")
    assert.are.same({ done = 0, total = 2, aborted = true }, finished)
    assert.is_false(scanner:IsRunning())
  end)

  it("finishes immediately with an empty list", function()
    scanner:Start({})
    assert.are.same({ done = 0, total = 0, aborted = false }, finished)
  end)

  it("exposes its progress", function()
    scanner:Start({ 1, 2, 3 })
    local done, total = scanner:Progress()
    assert.are.equal(0, done)
    assert.are.equal(3, total)
  end)
end)
