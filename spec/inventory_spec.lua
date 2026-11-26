local loader = require("loader")

describe("Inventory", function()
  local Inventory
  local bags
  local inventory

  before_each(function()
    Inventory = loader.load({ "Core/Init.lua", "Core/Inventory.lua" }).Inventory
    bags = {
      [0] = { [1] = 10, [2] = nil, [3] = 20 },
      [1] = { [1] = 30, [2] = 20 },
    }
    inventory = Inventory.New({
      bagIDs = { 0, 1 },
      getItemCount = function(itemID)
        local count = 0
        for _, slots in pairs(bags) do
          for _, slotItemID in pairs(slots) do
            if slotItemID == itemID then
              count = count + 1
            end
          end
        end
        return count
      end,
      getNumSlots = function(bagID)
        return bagID == 0 and 3 or 2
      end,
      getItemID = function(bagID, slotIndex)
        return bags[bagID][slotIndex]
      end,
      makeLocation = function(bagID, slotIndex)
        return { bag = bagID, slot = slotIndex }
      end,
    })
  end)

  it("counts items", function()
    assert.are.equal(2, inventory:Count(20))
    assert.are.equal(0, inventory:Count(99))
  end)

  it("finds the first bag slot holding an item", function()
    assert.are.same({ bag = 0, slot = 3 }, inventory:FindItemLocation(20))
    assert.are.same({ bag = 1, slot = 1 }, inventory:FindItemLocation(30))
  end)

  it("returns nil when the item is not in the bags", function()
    assert.is_nil(inventory:FindItemLocation(99))
  end)
end)
