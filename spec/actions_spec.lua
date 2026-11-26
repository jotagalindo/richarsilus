local loader = require("loader")

local function recordingApi(names, returns)
  local api = { calls = {} }
  for _, name in ipairs(names) do
    api[name] = function(...)
      api.calls[#api.calls + 1] = { name = name, args = { n = select("#", ...), ... } }
      if returns and returns[name] ~= nil then
        return returns[name]
      end
    end
  end
  function api.last()
    return api.calls[#api.calls]
  end
  return api
end

describe("Actions", function()
  local Actions

  before_each(function()
    Actions = loader.load({ "Core/Init.lua", "Core/Actions.lua" }).Actions
  end)

  describe("commodity purchase", function()
    local api
    local purchase
    local purchased

    before_each(function()
      api = recordingApi({ "StartCommoditiesPurchase", "ConfirmCommoditiesPurchase", "CancelCommoditiesPurchase", "PlaceBid" })
      purchase = Actions.NewPurchase(api, 1.05)
      purchased = {}
      purchase.onPurchased = function(itemID) purchased[#purchased + 1] = itemID end
    end)

    local function begin()
      return purchase:Begin({ itemID = 2447, quantity = 4, expectedTotal = 402, isCommodity = true })
    end

    it("starts by asking the server for a quote", function()
      assert.is_true(begin())
      assert.are.equal("quoting", purchase.state)
      assert.are.equal("StartCommoditiesPurchase", api.last().name)
      assert.are.same({ n = 3, 2447, 4, 101 }, api.last().args)
    end)

    it("refuses to start a second purchase while one is in progress", function()
      begin()
      assert.is_false(begin())
      assert.are.equal(1, #api.calls)
    end)

    it("becomes ready when the quoted price is within the tolerance", function()
      begin()
      purchase:OnEvent("COMMODITY_PRICE_UPDATED", 105, 420)
      assert.are.equal("ready", purchase.state)
      assert.are.same({ unitPrice = 105, totalPrice = 420 }, purchase.quote)
    end)

    it("cancels when the price rose more than the tolerance", function()
      begin()
      purchase:OnEvent("COMMODITY_PRICE_UPDATED", 110, 440)
      assert.are.equal("price_changed", purchase.state)
      assert.are.equal("CancelCommoditiesPurchase", api.last().name)
    end)

    it("cancels when the price is unavailable", function()
      begin()
      purchase:OnEvent("COMMODITY_PRICE_UNAVAILABLE")
      assert.are.equal("unavailable", purchase.state)
      assert.are.equal("CancelCommoditiesPurchase", api.last().name)
    end)

    it("only confirms a ready quote", function()
      begin()
      assert.is_false(purchase:Confirm())
      purchase:OnEvent("COMMODITY_PRICE_UPDATED", 100, 400)
      assert.is_true(purchase:Confirm())
      assert.are.equal("purchasing", purchase.state)
      assert.are.equal("ConfirmCommoditiesPurchase", api.last().name)
      assert.are.same({ n = 2, 2447, 4 }, api.last().args)
    end)

    it("reports a successful purchase", function()
      begin()
      purchase:OnEvent("COMMODITY_PRICE_UPDATED", 100, 400)
      purchase:Confirm()
      purchase:OnEvent("COMMODITY_PURCHASE_SUCCEEDED")
      assert.are.equal("idle", purchase.state)
      assert.are.same({ 2447 }, purchased)
    end)

    it("reports a failed purchase", function()
      begin()
      purchase:OnEvent("COMMODITY_PRICE_UPDATED", 100, 400)
      purchase:Confirm()
      purchase:OnEvent("COMMODITY_PURCHASE_FAILED")
      assert.are.equal("failed", purchase.state)
    end)

    it("ignores price updates when it did not ask for a quote", function()
      purchase:OnEvent("COMMODITY_PRICE_UPDATED", 100, 400)
      assert.are.equal("idle", purchase.state)
    end)

    it("cancels a pending quote", function()
      begin()
      purchase:Cancel()
      assert.are.equal("idle", purchase.state)
      assert.are.equal("CancelCommoditiesPurchase", api.last().name)
    end)

    it("resets when the auction house closes", function()
      begin()
      purchase:OnEvent("AUCTION_HOUSE_CLOSED")
      assert.are.equal("idle", purchase.state)
    end)
  end)

  describe("item purchase", function()
    it("buys one auction with its buyout", function()
      local api = recordingApi({ "StartCommoditiesPurchase", "ConfirmCommoditiesPurchase", "CancelCommoditiesPurchase", "PlaceBid" })
      local purchase = Actions.NewPurchase(api, 1.05)
      local purchased = {}
      purchase.onPurchased = function(itemID) purchased[#purchased + 1] = itemID end

      assert.is_true(purchase:Begin({ itemID = 5, quantity = 1, isCommodity = false, auctionID = 77, buyout = 900 }))
      assert.are.equal("purchasing", purchase.state)
      assert.are.equal("PlaceBid", api.last().name)
      assert.are.same({ n = 2, 77, 900 }, api.last().args)

      purchase:OnEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", 76)
      assert.are.equal("purchasing", purchase.state)
      purchase:OnEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", 77)
      assert.are.equal("idle", purchase.state)
      assert.are.same({ 5 }, purchased)
    end)
  end)

  describe("post", function()
    local api
    local inventory
    local location
    local post
    local posted

    before_each(function()
      location = { bag = 0, slot = 1 }
      inventory = {
        FindItemLocation = function(_, itemID) return itemID == 118 and location or nil end,
        Count = function(_, itemID) return itemID == 118 and 5 or 0 end,
      }
      posted = {}
    end)

    local function makePost(commodityStatus, needsConfirmation)
      api = recordingApi(
        { "PostCommodity", "ConfirmPostCommodity", "PostItem", "ConfirmPostItem" },
        { PostCommodity = needsConfirmation, PostItem = needsConfirmation }
      )
      api.GetItemCommodityStatus = function() return commodityStatus end
      post = Actions.NewPost(api, inventory)
      post.onPosted = function(itemID) posted[#posted + 1] = itemID end
    end

    it("reports when the item is not in the bags", function()
      makePost(2, false)
      assert.is_false(post:Begin(999, 1, 100, 2))
      assert.are.equal("no_item", post.state)
      assert.are.equal(0, #api.calls)
    end)

    it("posts a commodity without confirmation", function()
      makePost(2, false)
      assert.is_true(post:Begin(118, 3, 99, 2))
      assert.are.equal("posting", post.state)
      assert.are.equal("PostCommodity", api.last().name)
      assert.are.same({ n = 4, location, 2, 3, 99 }, api.last().args)
      post:OnEvent("AUCTION_HOUSE_AUCTION_CREATED", 1234)
      assert.are.equal("posted", post.state)
      assert.are.same({ 118 }, posted)
    end)

    it("never posts more than the bags hold", function()
      makePost(2, false)
      post:Begin(118, 50, 99, 2)
      assert.are.equal(5, api.last().args[3])
    end)

    it("asks for a second click when the game needs confirmation", function()
      makePost(2, true)
      post:Begin(118, 3, 99, 2)
      assert.are.equal("confirm", post.state)
      assert.is_true(post:Confirm())
      assert.are.equal("ConfirmPostCommodity", api.last().name)
      assert.are.same({ n = 4, location, 2, 3, 99 }, api.last().args)
      assert.are.equal("posting", post.state)
    end)

    it("does not confirm without a pending post", function()
      makePost(2, false)
      assert.is_false(post:Confirm())
    end)

    it("posts a non-commodity item one at a time with a buyout", function()
      makePost(1, true)
      post:Begin(118, 3, 500, 3)
      assert.are.equal("PostItem", api.last().name)
      assert.are.same({ n = 5, location, 3, 1, nil, 500 }, api.last().args)
      post:Confirm()
      assert.are.equal("ConfirmPostItem", api.last().name)
      assert.are.same({ n = 5, location, 3, 1, nil, 500 }, api.last().args)
    end)

    it("reports posting errors", function()
      makePost(2, false)
      post:Begin(118, 3, 99, 2)
      post:OnEvent("AUCTION_HOUSE_POST_ERROR")
      assert.are.equal("error", post.state)
    end)
  end)

  describe("Craft", function()
    it("refuses when the profession window is closed", function()
      local api = recordingApi({ "CraftRecipe" })
      local ok, reason = Actions.Craft(api, false, 2330, 3)
      assert.is_false(ok)
      assert.are.equal("PROFESSION_CLOSED", reason)
      assert.are.equal(0, #api.calls)
    end)

    it("crafts the requested amount", function()
      local api = recordingApi({ "CraftRecipe" })
      assert.is_true((Actions.Craft(api, true, 2330, 3)))
      assert.are.same({ n = 2, 2330, 3 }, api.last().args)
    end)
  end)
end)
