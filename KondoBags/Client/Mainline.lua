-- KondoBags Client/Mainline.lua -- provider for the Mainline UI family: Forever, Retail, Cata, Mists.
-- Also the fallback when the Era split cannot be detected. Everything is C_Container / C_Item.

local _, ns = ...
local Client = ns.Client

local P = { name = "Mainline" }

-- Every bag we draw, general first (flat-index order), then typed. Enum.BagIndex is the one
-- numbering that is right on every client; Era's keyring is handled in Era.lua.
function P.BagIDs()
  local ids = {}
  local last = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4)
  for bag = 0, last do
    if P.NumSlots(bag) > 0 then ids[#ids + 1] = bag end
  end
  return ids
end

function P.NumSlots(bag) return C_Container.GetContainerNumSlots(bag) or 0 end

function P.FreeSlots(bag)
  local free, family = C_Container.GetContainerNumFreeSlots(bag)
  return free or 0, family or 0
end

function P.BagKind(bag)
  if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag and bag == Enum.BagIndex.ReagentBag then return "reagent" end
  local _, family = P.FreeSlots(bag)
  return Client.KindFromFamily(family)
end

-- nil for an empty slot. `name` can be nil the first time an item is seen; the scanner fills it later.
function P.SlotInfo(bag, slot)
  local info = C_Container.GetContainerItemInfo(bag, slot)
  if not info then return nil end
  return {
    itemID  = info.itemID,
    link    = info.hyperlink,
    icon    = info.iconFileID,
    count   = info.stackCount or 1,
    quality = info.quality or 1,
    locked  = info.isLocked or false,
    name    = info.itemName,
  }
end

-- KondoBags_QuestFlags for the quest highlight; nil when the client has no quest info API.
function P.QuestInfo(bag, slot)
  if not C_Container.GetContainerItemQuestInfo then return nil end
  local q = C_Container.GetContainerItemQuestInfo(bag, slot)
  if not q or not (q.isQuestItem or q.questID) then return nil end
  return { isQuestItem = q.isQuestItem or false, questID = q.questID, isActive = q.isActive or false }
end

function P.Pickup(bag, slot) C_Container.PickupContainerItem(bag, slot) end
function P.InCombat() return InCombatLockdown() end

Client.Register(P)