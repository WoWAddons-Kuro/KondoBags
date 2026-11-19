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
  -- Family bits first: a bag with a family IS that kind wherever it sits. Enum.BagIndex.ReagentBag (5)
  -- is the reagent-bag SLOT, but Forever lets a profession bag be equipped there; a herb bag in that
  -- slot is a herb bag, not a reagent bag. Only a family-less bag in slot 5 is the actual reagent bag.
  local _, family = P.FreeSlots(bag)
  local kind = Client.KindFromFamily(family)
  if kind ~= "general" then return kind end
  if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag and bag == Enum.BagIndex.ReagentBag then return "reagent" end
  return "general"
end

-- Icon of the equipped bag itself (for empty-cell backdrops of typed bags); nil for the backpack / keyring.
function P.BagIcon(bag)
  if bag <= 0 or not C_Container.ContainerIDToInventoryID then return nil end
  local inv = C_Container.ContainerIDToInventoryID(bag)
  return inv and GetInventoryItemTexture("player", inv) or nil
end

-- Bag-family bits of an item (which typed bags may hold it); 0 for ordinary items.
function P.ItemFamily(itemIDOrLink)
  if not itemIDOrLink then return 0 end
  local fn = (C_Item and C_Item.GetItemFamily) or GetItemFamily
  return fn and fn(itemIDOrLink) or 0
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

-- Charges on a charge-based item: the shared tooltip scan in Client.lua (identical on every client).
P.Charges = Client.TooltipCharges
P.InvalidateCharges = Client.InvalidateTooltipCharges

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
