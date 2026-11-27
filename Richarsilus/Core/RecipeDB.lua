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

-- Quita de las demás profesiones guardadas las recetas indicadas. Si el juego da el nombre de la
-- profesión de otra forma (por ejemplo tras cambiar de idioma), las recetas no quedan guardadas dos veces.
function RecipeDB:RemoveFromOtherProfessions(professionName, recipeIDs)
  for otherName, entry in pairs(self.store) do
    if otherName ~= professionName then
      local kept = {}
      for _, recipe in ipairs(entry.recipes or {}) do
        if not recipeIDs[recipe.recipeID] then
          kept[#kept + 1] = recipe
        end
      end
      if #kept == 0 then
        self.store[otherName] = nil
      else
        entry.recipes = kept
      end
    end
  end
end

-- Fusiona por recipeID: las recetas leídas sustituyen a las guardadas y las que no aparecen
-- se conservan (la lista de Blizzard puede venir filtrada por el buscador de la ventana).
function RecipeDB:SaveProfession(professionName, recipes)
  local byID = {}
  local previous = self.store[professionName]
  for _, recipe in ipairs(previous and previous.recipes or {}) do
    byID[recipe.recipeID] = recipe
  end
  local readIDs = {}
  for _, recipe in ipairs(recipes) do
    recipe.profession = professionName
    byID[recipe.recipeID] = recipe
    readIDs[recipe.recipeID] = true
  end

  local merged = {}
  for _, recipe in pairs(byID) do
    merged[#merged + 1] = recipe
  end
  table.sort(merged, byRecipeID)
  self:RemoveFromOtherProfessions(professionName, readIDs)
  self.store[professionName] = { recipes = merged, t = self.clock() }
end

function RecipeDB:Clear()
  for professionName in pairs(self.store) do
    self.store[professionName] = nil
  end
end

-- Todas las recetas guardadas de todas las profesiones (las más recientes primero si se repiten).
local function storedRecipes(store)
  local professionNames = {}
  for professionName in pairs(store) do
    professionNames[#professionNames + 1] = professionName
  end
  table.sort(professionNames, function(first, second)
    local firstTime, secondTime = store[first].t or 0, store[second].t or 0
    if firstTime ~= secondTime then
      return firstTime > secondTime
    end
    return first < second
  end)

  local all = {}
  for _, professionName in ipairs(professionNames) do
    for _, recipe in ipairs(store[professionName].recipes or {}) do
      all[#all + 1] = recipe
    end
  end
  return all
end

-- Misma salida, misma cantidad producida y mismos materiales: para el cálculo son la misma receta.
local function craftSignature(recipe)
  local reagents = {}
  for index, reagent in ipairs(recipe.reagents) do
    reagents[index] = reagent.itemID .. "x" .. reagent.quantity
  end
  table.sort(reagents)
  return table.concat({
    recipe.outputItemID,
    recipe.quantityMin or 1,
    recipe.quantityMax or 1,
    table.concat(reagents, ","),
  }, ";")
end

-- Recetas para la tabla: cada recipeID una vez, y una sola entre las que craftean lo mismo con lo mismo.
function RecipeDB:AllRecipes()
  local seenIDs = {}
  local seenSignatures = {}
  local unique = {}
  for _, recipe in ipairs(storedRecipes(self.store)) do
    local signature = craftSignature(recipe)
    if not seenIDs[recipe.recipeID] and not seenSignatures[signature] then
      unique[#unique + 1] = recipe
    end
    seenIDs[recipe.recipeID] = true
    seenSignatures[signature] = true
  end
  table.sort(unique, byRecipeID)
  return unique
end

function RecipeDB:HasRecipes()
  return #self:AllRecipes() > 0
end

-- Busca en todo lo guardado, también en recetas que la tabla no muestra por estar repetidas.
function RecipeDB:GetRecipe(recipeID)
  for _, recipe in ipairs(storedRecipes(self.store)) do
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
