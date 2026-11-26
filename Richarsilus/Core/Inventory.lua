-- Consulta de bolsas: cuántas unidades tienes y dónde está un ítem (para publicarlo).
local _, ns = ...

local Inventory = {}
Inventory.__index = Inventory
ns.Inventory = Inventory

-- deps = { bagIDs, getItemCount(itemID), getNumSlots(bagID), getItemID(bagID, slot), makeLocation(bagID, slot) }
function Inventory.New(deps)
  local self = setmetatable({}, Inventory)
  self.deps = deps
  return self
end

function Inventory:Count(itemID)
  return self.deps.getItemCount(itemID) or 0
end

function Inventory:FindItemLocation(itemID)
  for _, bagID in ipairs(self.deps.bagIDs) do
    for slotIndex = 1, self.deps.getNumSlots(bagID) or 0 do
      if self.deps.getItemID(bagID, slotIndex) == itemID then
        return self.deps.makeLocation(bagID, slotIndex)
      end
    end
  end
  return nil
end
