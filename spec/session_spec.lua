local loader = require("loader")

describe("Session", function()
  local ns
  local priceDB
  local recipeDB
  local owned
  local settings
  local mapID
  local session

  local function listing(unitPrice, quantity, extra)
    local entry = { unitPrice = unitPrice, quantity = quantity, own = false }
    for key, value in pairs(extra or {}) do
      entry[key] = value
    end
    return entry
  end

  before_each(function()
    ns = loader.load({
      "Core/Init.lua", "Core/Pricing.lua", "Core/PriceDB.lua", "Core/RecipeDB.lua", "Core/Session.lua",
    })
    priceDB = ns.PriceDB.New({ prices = {}, vendor = {} }, function() return 1 end)
    recipeDB = ns.RecipeDB.New({}, function() return 1 end)
    owned = {}
    settings = { cut = "auto", undercut = 1, duration = 2, includeDeposit = true }
    mapID = 1453
    session = ns.Session.New({
      priceDB = priceDB,
      recipeDB = recipeDB,
      inventory = { Count = function(_, itemID) return owned[itemID] or 0 end },
      settings = settings,
      deposit = function() return 0 end,
      mapID = function() return mapID end,
    })
  end)

  describe("CurrentCut", function()
    it("uses the faction cut by default", function()
      local cut, isAuto = session:CurrentCut()
      assert.are.equal(0.05, cut)
      assert.is_true(isAuto)
    end)

    it("detects neutral auction house zones", function()
      for _, neutralMap in ipairs({ 71, 83, 210, 224, 1446, 1452, 1434 }) do
        mapID = neutralMap
        assert.are.equal(0.15, (session:CurrentCut()))
      end
    end)

    it("uses the manual setting when there is one", function()
      settings.cut = 0.15
      local cut, isAuto = session:CurrentCut()
      assert.are.equal(0.15, cut)
      assert.is_false(isAuto)
    end)

    it("handles an unknown map", function()
      mapID = nil
      assert.are.equal(0.05, (session:CurrentCut()))
    end)
  end)

  describe("EvaluateAll", function()
    before_each(function()
      recipeDB:SaveProfession("Alchemy", {
        { recipeID = 1, name = "Cheap", outputItemID = 101, quantityMin = 1, reagents = { { itemID = 1, quantity = 1 } } },
        { recipeID = 2, name = "Rich", outputItemID = 102, quantityMin = 1, reagents = { { itemID = 1, quantity = 1 } } },
        { recipeID = 3, name = "Unsold", outputItemID = 103, quantityMin = 1, reagents = { { itemID = 1, quantity = 1 } } },
        { recipeID = 4, name = "Unknown", outputItemID = 104, quantityMin = 1, reagents = { { itemID = 9, quantity = 1 } } },
      })
      priceDB:SetListings(1, { listing(10, 100) }, true)
      priceDB:SetListings(101, { listing(21, 5) }, true)
      priceDB:SetListings(102, { listing(1001, 5) }, true)
      priceDB:SetListings(104, { listing(500, 5) }, true)
      owned[1] = 3
    end)

    it("sorts profitable recipes first, by profit", function()
      local results = session:EvaluateAll()
      assert.are.equal(4, #results)
      assert.are.equal("Rich", results[1].recipe.name)
      assert.are.equal("Cheap", results[2].recipe.name)
      assert.are.equal("ok", results[1].status)
      assert.are.equal(3, results[1].craftable)
    end)

    it("lists recipes without prices after the priced ones", function()
      local results = session:EvaluateAll()
      local trailing = { results[3].status, results[4].status }
      table.sort(trailing)
      assert.are.same({ "missing_materials", "no_sale_price" }, trailing)
    end)

    it("uses the configured undercut and cut", function()
      settings.cut = 0.15
      local result = session:Evaluate(recipeDB:GetRecipe(2), 1)
      assert.are.equal(1000, result.salePrice)
      assert.are.equal(150, result.cutAmount)
    end)
  end)

  describe("NextPurchase", function()
    local recipe

    before_each(function()
      recipe = {
        recipeID = 5,
        name = "Potion",
        outputItemID = 200,
        quantityMin = 1,
        reagents = { { itemID = 1, quantity = 2 }, { itemID = 2, quantity = 1 }, { itemID = 3, quantity = 1 } },
      }
      priceDB:SetListings(200, { listing(1000, 1) }, true)
      priceDB:SetVendorPrice(3, 5)
    end)

    it("buys commodities that are missing from the bags", function()
      priceDB:SetListings(1, { listing(10, 1), listing(12, 10) }, true)
      priceDB:SetListings(2, { listing(50, 4) }, true)
      owned[2] = 1
      local purchase = session:NextPurchase(session:Evaluate(recipe, 3))
      assert.are.same({ itemID = 1, quantity = 6, expectedTotal = 70, isCommodity = true }, purchase)
    end)

    it("skips materials that are already owned or cheaper at a vendor", function()
      priceDB:SetListings(1, { listing(10, 10) }, true)
      priceDB:SetListings(2, { listing(50, 4) }, true)
      priceDB:SetListings(3, { listing(40, 4) }, true)
      owned[1] = 2
      local purchase = session:NextPurchase(session:Evaluate(recipe, 1))
      assert.are.same({ itemID = 2, quantity = 1, expectedTotal = 50, isCommodity = true }, purchase)
    end)

    it("buys the cheapest auction from someone else for non-commodities", function()
      priceDB:SetListings(1, {
        listing(10, 1, { own = true, auctionID = 8, buyout = 10 }),
        listing(15, 2, { auctionID = 9, buyout = 30 }),
      }, false)
      owned[2] = 5
      local purchase = session:NextPurchase(session:Evaluate(recipe, 1))
      assert.are.same({ itemID = 1, quantity = 2, expectedTotal = 30, isCommodity = false, auctionID = 9, buyout = 30 }, purchase)
    end)

    it("returns nil when nothing needs buying at the auction house", function()
      owned[1] = 2
      owned[2] = 1
      priceDB:SetListings(1, { listing(10, 10) }, true)
      priceDB:SetListings(2, { listing(50, 4) }, true)
      assert.is_nil(session:NextPurchase(session:Evaluate(recipe, 1)))
    end)
  end)

  describe("ShoppingList", function()
    local recipe

    before_each(function()
      recipe = {
        recipeID = 6,
        name = "Elixir",
        outputItemID = 300,
        quantityMin = 1,
        reagents = {
          { itemID = 1, quantity = 2 },
          { itemID = 2, quantity = 2 },
          { itemID = 3, quantity = 1 },
          { itemID = 4, quantity = 1 },
          { itemID = 5, quantity = 1 },
        },
      }
      priceDB:SetListings(1, { listing(10, 2), listing(12, 10) }, true)
      priceDB:SetListings(2, { listing(20, 10) }, true)
      priceDB:SetVendorPrice(3, 5)
      priceDB:SetListings(4, { listing(30, 1) }, true)
      priceDB:SetListings(5, { listing(7, 10) }, true)
      owned[3] = 1
      owned[5] = 3
    end)

    it("lists every material to buy at the auction house and at vendors, with totals", function()
      local shopping = session:ShoppingList(session:Evaluate(recipe, 3))
      assert.are.same({
        { itemID = 1, quantity = 6, cost = 68 },
        { itemID = 2, quantity = 6, cost = 120 },
      }, shopping.auction)
      assert.are.equal(188, shopping.auctionTotal)
      assert.are.same({ { itemID = 3, quantity = 2, cost = 10 } }, shopping.vendor)
      assert.are.equal(10, shopping.vendorTotal)
      assert.are.same({ { itemID = 4, quantity = 3 } }, shopping.missing)
      assert.are.equal(198, shopping.total)
    end)

    it("is empty when the bags already hold everything", function()
      for itemID = 1, 5 do
        owned[itemID] = 10
      end
      local shopping = session:ShoppingList(session:Evaluate(recipe, 1))
      assert.are.same({}, shopping.auction)
      assert.are.same({}, shopping.vendor)
      assert.are.same({}, shopping.missing)
      assert.are.equal(0, shopping.total)
    end)
  end)

  it("computes the price to post at", function()
    priceDB:SetListings(200, { listing(1000, 1) }, true)
    assert.are.equal(999, session:SaleUnitPrice(200))
    assert.is_nil(session:SaleUnitPrice(201))
  end)
end)
