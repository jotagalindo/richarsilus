-- Recetas aprendidas. Se leen de C_TradeSkillUI mientras la ventana de profesión está abierta
-- y se guardan por personaje para poder calcular en la subasta con la profesión cerrada.
local _, ns = ...

local RecipeDB = {}
RecipeDB.__index = RecipeDB
ns.RecipeDB = RecipeDB

-- Valores de Enum.TradeskillSlotDataType.Reagent y Enum.CraftingReagentType.Basic en el cliente 1.60.
local DEFAULT_REAGENT_SLOT_TYPE = 1
local DEFAULT_BASIC_REAGENT_TYPE = 1

local function enumValue(enumName, fieldName, fallback)
  local enumTable = Enum and Enum[enumName]
  local value = enumTable and enumTable[fieldName]
  if value == nil then
    return fallback
  end
  return value
end

local function isCraftableForSale(info)
  return info.learned
    and not info.isEnchantingRecipe
    and not info.isSalvageRecipe
    and not info.isGatheringRecipe
    and not info.isRecraft
    and not info.isDummyRecipe
end

local function readReagents(schematic)
  local reagentSlotType = enumValue("TradeskillSlotDataType", "Reagent", DEFAULT_REAGENT_SLOT_TYPE)
  local basicReagentType = enumValue("CraftingReagentType", "Basic", DEFAULT_BASIC_REAGENT_TYPE)
  local reagents = {}
  for _, reagentSlot in ipairs(schematic.reagentSlotSchematics or {}) do
    local firstReagent = reagentSlot.reagents and reagentSlot.reagents[1]
    local isBasicSlot = reagentSlot.required
      and (reagentSlot.dataSlotType == nil or reagentSlot.dataSlotType == reagentSlotType)
      and (reagentSlot.reagentType == nil or reagentSlot.reagentType == basicReagentType)
    if isBasicSlot and firstReagent and firstReagent.itemID then
      reagents[#reagents + 1] = { itemID = firstReagent.itemID, quantity = reagentSlot.quantityRequired }
    end
  end
  return reagents
end

-- Lee las recetas de la profesión abierta. `api` es C_TradeSkillUI.
-- Devuelve nombreDeProfesión, lista de recetas (o nil, {} si no hay profesión válida).
function RecipeDB.ReadOpenProfession(api)
  local professionInfo = api.GetBaseProfessionInfo and api.GetBaseProfessionInfo()
  local professionName = professionInfo and professionInfo.professionName
  if not professionName or professionName == "" then
    return nil, {}
  end

  local recipeIDs
  if api.GetAllRecipeIDs then
    recipeIDs = api.GetAllRecipeIDs()
  else
    recipeIDs = api.GetFilteredRecipeIDs()
  end

  local recipes = {}
  for _, recipeID in ipairs(recipeIDs or {}) do
    local info = api.GetRecipeInfo(recipeID)
    if info and isCraftableForSale(info) then
      local schematic = api.GetRecipeSchematic(recipeID, false)
      if schematic and schematic.outputItemID then
        local reagents = readReagents(schematic)
        if #reagents > 0 then
          recipes[#recipes + 1] = {
            recipeID = recipeID,
            name = info.name or schematic.name,
            icon = info.icon,
            outputItemID = schematic.outputItemID,
            quantityMin = math.max(1, schematic.quantityMin or 1),
            quantityMax = math.max(1, schematic.quantityMax or 1),
            reagents = reagents,
          }
        end
      end
    end
  end
  return professionName, recipes
end

-- store = tabla guardada del personaje: { [nombreProfesión] = { recipes = {...}, t = hora } }
function RecipeDB.New(store, clock)
  local self = setmetatable({}, RecipeDB)
  self.store = store
  self.clock = clock
  return self
end

local function byRecipeID(first, second)
  return first.recipeID < second.recipeID
end

-- Fusiona por recipeID: las recetas leídas sustituyen a las guardadas y las que no aparecen
-- se conservan (la lista de Blizzard puede venir filtrada por el buscador de la ventana).
function RecipeDB:SaveProfession(professionName, recipes)
  local byID = {}
  local previous = self.store[professionName]
  for _, recipe in ipairs(previous and previous.recipes or {}) do
    byID[recipe.recipeID] = recipe
  end
  for _, recipe in ipairs(recipes) do
    recipe.profession = professionName
    byID[recipe.recipeID] = recipe
  end

  local merged = {}
  for _, recipe in pairs(byID) do
    merged[#merged + 1] = recipe
  end
  table.sort(merged, byRecipeID)
  self.store[professionName] = { recipes = merged, t = self.clock() }
end

function RecipeDB:Clear()
  for professionName in pairs(self.store) do
    self.store[professionName] = nil
  end
end

function RecipeDB:AllRecipes()
  local professionNames = {}
  for professionName in pairs(self.store) do
    professionNames[#professionNames + 1] = professionName
  end
  table.sort(professionNames)

  local all = {}
  for _, professionName in ipairs(professionNames) do
    for _, recipe in ipairs(self.store[professionName].recipes) do
      all[#all + 1] = recipe
    end
  end
  return all
end

function RecipeDB:HasRecipes()
  return #self:AllRecipes() > 0
end

function RecipeDB:GetRecipe(recipeID)
  for _, recipe in ipairs(self:AllRecipes()) do
    if recipe.recipeID == recipeID then
      return recipe
    end
  end
  return nil
end

function RecipeDB:ItemIDsToScan()
  local seen = {}
  local itemIDs = {}
  local function add(itemID)
    if not seen[itemID] then
      seen[itemID] = true
      itemIDs[#itemIDs + 1] = itemID
    end
  end
  for _, recipe in ipairs(self:AllRecipes()) do
    add(recipe.outputItemID)
    for _, reagent in ipairs(recipe.reagents) do
      add(reagent.itemID)
    end
  end
  table.sort(itemIDs)
  return itemIDs
end
