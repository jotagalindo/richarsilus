local loader = require("loader")

local REAGENT_SLOT = 1
local MODIFIED_REAGENT_SLOT = 2
local BASIC = 1
local MODIFYING = 0

local function slot(itemID, quantity, overrides)
  local result = {
    reagents = { { itemID = itemID } },
    quantityRequired = quantity,
    required = true,
    dataSlotType = REAGENT_SLOT,
    reagentType = BASIC,
  }
  for key, value in pairs(overrides or {}) do
    result[key] = value
  end
  return result
end

local function fakeTradeSkillApi(recipes, options)
  local api = {}
  local ids = {}
  for recipeID in pairs(recipes) do
    ids[#ids + 1] = recipeID
  end
  table.sort(ids)
  api.recipeIDCalls = {}
  if not (options and options.noGetAll) then
    api.GetAllRecipeIDs = function()
      api.recipeIDCalls[#api.recipeIDCalls + 1] = "all"
      return ids
    end
  end
  api.GetFilteredRecipeIDs = function()
    api.recipeIDCalls[#api.recipeIDCalls + 1] = "filtered"
    return ids
  end
  api.GetBaseProfessionInfo = function()
    return { professionName = "Alchemy", professionID = 171 }
  end
  api.GetRecipeInfo = function(recipeID)
    return recipes[recipeID] and recipes[recipeID].info
  end
  api.GetRecipeSchematic = function(recipeID, isRecraft)
    assert(isRecraft == false)
    return recipes[recipeID] and recipes[recipeID].schematic
  end
  return api
end

local function potion(recipeID, outputItemID, infoOverrides, slots)
  local info = { recipeID = recipeID, name = "Recipe " .. recipeID, learned = true, icon = 136 }
  for key, value in pairs(infoOverrides or {}) do
    info[key] = value
  end
  return {
    info = info,
    schematic = {
      recipeID = recipeID,
      name = "Schematic " .. recipeID,
      outputItemID = outputItemID,
      quantityMin = 1,
      quantityMax = 1,
      reagentSlotSchematics = slots or { slot(2447, 1), slot(765, 1), slot(3371, 1) },
    },
  }
end

describe("RecipeDB", function()
  local RecipeDB

  before_each(function()
    RecipeDB = loader.load({ "Core/Init.lua", "Core/RecipeDB.lua" }).RecipeDB
  end)

  describe("ReadOpenProfession", function()
    it("reads learned recipes that produce an item", function()
      local api = fakeTradeSkillApi({ [2330] = potion(2330, 118) })
      local professionName, recipes = RecipeDB.ReadOpenProfession(api)
      assert.are.equal("Alchemy", professionName)
      assert.are.equal(1, #recipes)
      assert.are.same({
        recipeID = 2330,
        name = "Recipe 2330",
        icon = 136,
        outputItemID = 118,
        quantityMin = 1,
        quantityMax = 1,
        reagents = {
          { itemID = 2447, quantity = 1 },
          { itemID = 765, quantity = 1 },
          { itemID = 3371, quantity = 1 },
        },
      }, recipes[1])
    end)

    it("skips recipes that cannot be sold as crafted items", function()
      local api = fakeTradeSkillApi({
        [1] = potion(1, 101, { learned = false }),
        [2] = potion(2, 102, { isEnchantingRecipe = true }),
        [3] = potion(3, 103, { isSalvageRecipe = true }),
        [4] = potion(4, 104, { isRecraft = true }),
        [5] = potion(5, nil),
        [6] = potion(6, 106, { isGatheringRecipe = true }),
        [7] = potion(7, 107, { isDummyRecipe = true }),
        [8] = potion(8, 108),
      })
      local _, recipes = RecipeDB.ReadOpenProfession(api)
      assert.are.equal(1, #recipes)
      assert.are.equal(8, recipes[1].recipeID)
    end)

    it("keeps only required basic reagent slots", function()
      local api = fakeTradeSkillApi({
        [9] = potion(9, 109, nil, {
          slot(1, 2),
          slot(2, 1, { required = false }),
          slot(3, 1, { dataSlotType = MODIFIED_REAGENT_SLOT }),
          slot(4, 1, { reagentType = MODIFYING }),
          slot(5, 3, { dataSlotType = 3, reagents = { { currencyID = 99 } } }),
        }),
      })
      local _, recipes = RecipeDB.ReadOpenProfession(api)
      assert.are.same({ { itemID = 1, quantity = 2 } }, recipes[1].reagents)
    end)

    it("skips recipes without item reagents", function()
      local api = fakeTradeSkillApi({ [10] = potion(10, 110, nil, {}) })
      local _, recipes = RecipeDB.ReadOpenProfession(api)
      assert.are.equal(0, #recipes)
    end)

    it("uses at least one unit of output per craft", function()
      local recipe = potion(11, 111)
      recipe.schematic.quantityMin = 0
      local _, recipes = RecipeDB.ReadOpenProfession(fakeTradeSkillApi({ [11] = recipe }))
      assert.are.equal(1, recipes[1].quantityMin)
    end)

    it("prefers GetAllRecipeIDs and falls back to GetFilteredRecipeIDs", function()
      local withAll = fakeTradeSkillApi({ [12] = potion(12, 112) })
      RecipeDB.ReadOpenProfession(withAll)
      assert.are.same({ "all" }, withAll.recipeIDCalls)

      local withoutAll = fakeTradeSkillApi({ [12] = potion(12, 112) }, { noGetAll = true })
      RecipeDB.ReadOpenProfession(withoutAll)
      assert.are.same({ "filtered" }, withoutAll.recipeIDCalls)
    end)

    it("returns nothing when no profession name is available", function()
      local api = fakeTradeSkillApi({ [13] = potion(13, 113) })
      api.GetBaseProfessionInfo = function() return { professionName = "" } end
      local professionName, recipes = RecipeDB.ReadOpenProfession(api)
      assert.is_nil(professionName)
      assert.are.same({}, recipes)
    end)
  end)

  describe("store", function()
    local store
    local database

    before_each(function()
      store = {}
      database = RecipeDB.New(store, function() return 500 end)
    end)

    it("starts empty", function()
      assert.is_false(database:HasRecipes())
      assert.are.same({}, database:AllRecipes())
    end)

    it("merges recipes when a profession is saved again, so a filtered list loses nothing", function()
      database:SaveProfession("Alchemy", {
        { recipeID = 1, name = "Old", outputItemID = 10, reagents = { { itemID = 20, quantity = 1 } } },
        { recipeID = 3, outputItemID = 12, reagents = { { itemID = 22, quantity = 1 } } },
      })
      database:SaveProfession("Alchemy", {
        { recipeID = 1, name = "New", outputItemID = 10, reagents = { { itemID = 20, quantity = 2 } } },
        { recipeID = 2, outputItemID = 11, reagents = { { itemID = 21, quantity = 1 } } },
      })
      local recipes = database:AllRecipes()
      assert.are.equal(3, #recipes)
      assert.are.same({ 1, 2, 3 }, { recipes[1].recipeID, recipes[2].recipeID, recipes[3].recipeID })
      assert.are.equal("New", database:GetRecipe(1).name)
      assert.are.equal(2, database:GetRecipe(1).reagents[1].quantity)
      assert.are.equal(500, store.Alchemy.t)
    end)

    it("forgets every saved recipe", function()
      database:SaveProfession("Alchemy", { { recipeID = 1, outputItemID = 10, reagents = { { itemID = 20, quantity = 1 } } } })
      database:Clear()
      assert.is_false(database:HasRecipes())
      assert.is_nil(store.Alchemy)
    end)

    it("combines professions and finds recipes by id", function()
      database:SaveProfession("Alchemy", { { recipeID = 1, outputItemID = 10, reagents = { { itemID = 20, quantity = 1 } } } })
      database:SaveProfession("Tailoring", { { recipeID = 2, outputItemID = 11, reagents = { { itemID = 20, quantity = 2 } } } })
      assert.are.equal(2, #database:AllRecipes())
      assert.are.equal(11, database:GetRecipe(2).outputItemID)
      assert.is_nil(database:GetRecipe(3))
      assert.is_true(database:HasRecipes())
    end)

    it("tags each recipe with its profession", function()
      database:SaveProfession("Alchemy", { { recipeID = 1, outputItemID = 10, reagents = { { itemID = 20, quantity = 1 } } } })
      assert.are.equal("Alchemy", database:GetRecipe(1).profession)
    end)

    it("keeps one copy of a recipe when the game reports the profession under another name", function()
      database:SaveProfession("Alchemy", {
        { recipeID = 1, outputItemID = 10, reagents = { { itemID = 20, quantity = 1 } } },
        { recipeID = 2, outputItemID = 11, reagents = { { itemID = 21, quantity = 1 } } },
      })
      database:SaveProfession("Alquimia", { { recipeID = 1, outputItemID = 10, reagents = { { itemID = 20, quantity = 1 } } } })
      local recipes = database:AllRecipes()
      assert.are.same({ 1, 2 }, { recipes[1].recipeID, recipes[2].recipeID })
      assert.are.equal("Alquimia", database:GetRecipe(1).profession)
      assert.are.same({ 2 }, { store.Alchemy.recipes[1].recipeID, store.Alchemy.recipes[2] })

      database:SaveProfession("Alquimia", { { recipeID = 2, outputItemID = 11, reagents = { { itemID = 21, quantity = 1 } } } })
      assert.is_nil(store.Alchemy)
      assert.are.equal(2, #database:AllRecipes())
    end)

    it("shows each recipe once even if older saved data repeats it", function()
      local recipe = { recipeID = 1, outputItemID = 10, reagents = { { itemID = 20, quantity = 1 } } }
      store.Alchemy = { recipes = { recipe }, t = 1 }
      store.Alquimia = { recipes = { recipe }, t = 2 }
      assert.are.equal(1, #database:AllRecipes())
    end)

    it("shows once two recipe ids that craft the same item from the same reagents", function()
      database:SaveProfession("Alchemy", {
        { recipeID = 1, outputItemID = 10, quantityMin = 1, reagents = { { itemID = 20, quantity = 2 }, { itemID = 21, quantity = 1 } } },
        { recipeID = 2, outputItemID = 10, quantityMin = 1, reagents = { { itemID = 21, quantity = 1 }, { itemID = 20, quantity = 2 } } },
        { recipeID = 3, outputItemID = 10, quantityMin = 1, reagents = { { itemID = 20, quantity = 3 }, { itemID = 21, quantity = 1 } } },
      })
      local recipes = database:AllRecipes()
      assert.are.same({ 1, 3 }, { recipes[1].recipeID, recipes[2].recipeID })
      assert.are.equal(2, database:GetRecipe(2).recipeID)
    end)

    it("lists every output and reagent once, sorted", function()
      database:SaveProfession("Alchemy", {
        { recipeID = 1, outputItemID = 30, reagents = { { itemID = 20, quantity = 1 }, { itemID = 5, quantity = 1 } } },
      })
      database:SaveProfession("Tailoring", { { recipeID = 2, outputItemID = 11, reagents = { { itemID = 20, quantity = 2 } } } })
      assert.are.same({ 5, 11, 20, 30 }, database:ItemIDsToScan())
    end)
  end)
end)
