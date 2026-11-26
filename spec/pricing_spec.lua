local loader = require("loader")

local function listing(unitPrice, quantity, own)
  return { unitPrice = unitPrice, quantity = quantity, own = own or false }
end

describe("Pricing", function()
  local Pricing

  before_each(function()
    Pricing = loader.load({ "Core/Init.lua", "Core/Pricing.lua" }).Pricing
  end)

  describe("BuyCost", function()
    it("walks listings from cheapest to most expensive", function()
      local totalCost, bought = Pricing.BuyCost({ listing(10, 5), listing(20, 5) }, 7)
      assert.are.equal(90, totalCost)
      assert.are.equal(7, bought)
    end)

    it("costs nothing for zero quantity", function()
      local totalCost, bought = Pricing.BuyCost({ listing(10, 5) }, 0)
      assert.are.equal(0, totalCost)
      assert.are.equal(0, bought)
    end)

    it("returns only what is available when the market is too thin", function()
      local totalCost, bought = Pricing.BuyCost({ listing(10, 2), listing(15, 1) }, 10)
      assert.are.equal(35, totalCost)
      assert.are.equal(3, bought)
    end)

    it("handles missing listings", function()
      local totalCost, bought = Pricing.BuyCost(nil, 3)
      assert.are.equal(0, totalCost)
      assert.are.equal(0, bought)
    end)
  end)

  describe("SalePrice", function()
    it("returns nil when nothing is listed", function()
      assert.is_nil(Pricing.SalePrice({}, 1))
    end)

    it("undercuts the cheapest listing from someone else", function()
      assert.are.equal(99, Pricing.SalePrice({ listing(100, 3), listing(120, 1) }, 1))
    end)

    it("matches the cheapest listing when it is the player's own", function()
      assert.are.equal(100, Pricing.SalePrice({ listing(100, 3, true) }, 1))
    end)

    it("never goes below one copper", function()
      assert.are.equal(1, Pricing.SalePrice({ listing(3, 1) }, 10))
    end)
  end)

  describe("MaterialCost", function()
    it("buys from the auction house when cheaper than the vendor", function()
      local result = Pricing.MaterialCost({ needed = 2, owned = 0, listings = { listing(40, 5) }, vendorPrice = 50 })
      assert.are.equal("auction", result.source)
      assert.are.equal(80, result.cost)
      assert.are.equal(2, result.toBuy)
      assert.is_true(result.complete)
    end)

    it("buys from the vendor when cheaper than the auction house", function()
      local result = Pricing.MaterialCost({ needed = 2, owned = 0, listings = { listing(40, 5) }, vendorPrice = 30 })
      assert.are.equal("vendor", result.source)
      assert.are.equal(60, result.cost)
    end)

    it("values owned materials at the lowest market price", function()
      local result = Pricing.MaterialCost({ needed = 3, owned = 5, listings = { listing(40, 5) }, vendorPrice = 70 })
      assert.are.equal("owned", result.source)
      assert.are.equal(0, result.toBuy)
      assert.are.equal(3, result.ownedUsed)
      assert.are.equal(120, result.ownedValue)
      assert.are.equal(120, result.cost)
      assert.is_true(result.complete)
    end)

    it("combines owned and bought materials", function()
      local result = Pricing.MaterialCost({ needed = 4, owned = 1, listings = { listing(10, 1), listing(20, 9) } })
      assert.are.equal(1, result.ownedUsed)
      assert.are.equal(3, result.toBuy)
      assert.are.equal(10, result.ownedValue)
      assert.are.equal(50, result.buyCost)
      assert.are.equal(60, result.cost)
      assert.are.equal("auction", result.source)
    end)

    it("is incomplete when there is no price at all", function()
      local result = Pricing.MaterialCost({ needed = 1, owned = 0, listings = {} })
      assert.are.equal("none", result.source)
      assert.is_false(result.complete)
    end)

    it("is incomplete when the auction house does not have enough and there is no vendor", function()
      local result = Pricing.MaterialCost({ needed = 5, owned = 0, listings = { listing(10, 2) } })
      assert.is_false(result.complete)
    end)

    it("ignores the player's own auctions when buying and valuing", function()
      local result = Pricing.MaterialCost({ needed = 2, owned = 1, listings = { listing(5, 10, true), listing(30, 10) } })
      assert.are.equal(30, result.ownedValue)
      assert.are.equal(30, result.buyCost)
      assert.are.equal(60, result.cost)
    end)

    it("is incomplete when only the player's own auctions are listed", function()
      local result = Pricing.MaterialCost({ needed = 1, owned = 0, listings = { listing(5, 10, true) } })
      assert.is_false(result.complete)
    end)

    it("uses the vendor when the auction house does not have enough", function()
      local result = Pricing.MaterialCost({ needed = 5, owned = 0, listings = { listing(10, 2) }, vendorPrice = 50 })
      assert.are.equal("vendor", result.source)
      assert.are.equal(250, result.cost)
      assert.is_true(result.complete)
    end)
  end)

  describe("Evaluate", function()
    local recipe
    local listingsByItem
    local vendorByItem
    local ownedByItem

    local function context(overrides)
      local ctx = {
        listings = function(itemID) return listingsByItem[itemID] or {} end,
        vendorPrice = function(itemID) return vendorByItem[itemID] end,
        owned = function(itemID) return ownedByItem[itemID] or 0 end,
        cut = 0.05,
        undercut = 1,
        deposit = function() return 3 end,
        includeDeposit = true,
      }
      for key, value in pairs(overrides or {}) do
        ctx[key] = value
      end
      return ctx
    end

    before_each(function()
      recipe = {
        recipeID = 7,
        name = "Potion",
        outputItemID = 100,
        quantityMin = 1,
        reagents = { { itemID = 1, quantity = 2 }, { itemID = 2, quantity = 1 } },
      }
      listingsByItem = { [1] = { listing(10, 50) }, [100] = { listing(100, 10) } }
      vendorByItem = { [2] = 5 }
      ownedByItem = {}
    end)

    it("computes profit after cut, materials and deposit", function()
      local result = Pricing.Evaluate(recipe, 1, context())
      assert.are.equal("ok", result.status)
      assert.are.equal(1, result.units)
      assert.are.equal(99, result.salePrice)
      assert.are.equal(99, result.gross)
      assert.are.equal(5, result.cutAmount)
      assert.are.equal(25, result.materialCost)
      assert.are.equal(3, result.deposit)
      assert.are.equal(66, result.profit)
      assert.are.equal(66 / 25, result.margin)
    end)

    it("does not subtract the deposit when disabled", function()
      local result = Pricing.Evaluate(recipe, 1, context({ includeDeposit = false }))
      assert.are.equal(3, result.deposit)
      assert.are.equal(69, result.profit)
    end)

    it("reports a missing sale price", function()
      listingsByItem[100] = nil
      local result = Pricing.Evaluate(recipe, 1, context())
      assert.are.equal("no_sale_price", result.status)
      assert.is_nil(result.profit)
    end)

    it("reports missing material prices", function()
      vendorByItem[2] = nil
      local result = Pricing.Evaluate(recipe, 1, context())
      assert.are.equal("missing_materials", result.status)
    end)

    it("scales by crafts and units per craft", function()
      recipe.quantityMin = 2
      local result = Pricing.Evaluate(recipe, 3, context())
      assert.are.equal(6, result.units)
      assert.are.equal(6, result.materials[1].needed)
      assert.are.equal(3, result.materials[2].needed)
      assert.are.equal(1, result.materials[1].itemID)
    end)

    it("treats a missing deposit as zero", function()
      local result = Pricing.Evaluate(recipe, 1, context({ deposit = function() return nil end }))
      assert.are.equal(0, result.deposit)
      assert.are.equal(69, result.profit)
    end)
  end)

  describe("MaxCraftable", function()
    it("is limited by the scarcest reagent", function()
      local recipe = { reagents = { { itemID = 1, quantity = 2 }, { itemID = 2, quantity = 1 } } }
      local owned = { [1] = 7, [2] = 10 }
      assert.are.equal(3, Pricing.MaxCraftable(recipe, function(itemID) return owned[itemID] or 0 end))
    end)

    it("is zero without reagents", function()
      assert.are.equal(0, Pricing.MaxCraftable({ reagents = {} }, function() return 99 end))
    end)
  end)
end)
