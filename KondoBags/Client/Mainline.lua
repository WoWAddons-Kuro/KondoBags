-- KondoBags Client/Mainline.lua -- provider for the Mainline UI family: Forever, Retail, Cata, Mists.
-- Also the fallback when the Era split cannot be detected. Everything is C_Container / C_Item.

local _, ns = ...
local Client = ns.Client

local P = { name = "Mainline" }

-- Every bag we draw, general first (flat-index order), then typed. Enum.BagIndex is the one
-- numbering that is right on every client; Era's keyring is handled in Era.lua.
-- Enum.BagIndex.ReagentBag (5) is the PROFESSION-BAG SLOT: on Forever it accepts ONLY profession /
-- typed bags, never a general bag. Blizzard's name for it has nothing to do with a "reagent bag" kind.
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

-- Bag-family mask of the bag in container `bag`. The container API is the first word, but on Forever
-- it reports 0 for some profession bags (Apprentice's Skinning Satchel; a mining bag reported 1024
-- correctly, owner 2026-11-19), so the equipped bag ITEM's class/subclass is the fallback.
-- KondoBags_BagFamilySet of the bag in container `bag`: the container API's mask decoded, with the
-- equipped bag ITEM's class/subclass as the fallback when the mask is 0 for a non-general bag.
function P.BagFamilySet(bag)
  local _, mask = P.FreeSlots(bag)
  local classID, subClassID
  if bag > 0 and C_Container.ContainerIDToInventoryID then
    local inv = C_Container.ContainerIDToInventoryID(bag)
    local itemID = inv and GetInventoryItemID("player", inv)
    local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if itemID and getInstant then local _, _, _, _, _, c, s = getInstant(itemID); classID, subClassID = c, s end
  end
  return Client.ResolveBagFamilySet(mask, classID, subClassID)
end

function P.BagKind(bag)
  -- A bag IS its family, wherever it sits (slot 1-4 or the profession-bag slot). There is no slot-index
  -- rule: the profession-bag slot only ever holds a typed bag, so its family set always answers.
  return Client.KindFromFamilySet(P.BagFamilySet(bag))
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

-- Is the item a crafting reagent (what the Retail-style reagent bag accepts)? The tooltip flag
-- "Crafting Reagent": C_Item.IsItemCraftingReagent where it exists, else GetItemInfo return 17.
function P.IsCraftingReagent(itemIDOrLink)
  if not itemIDOrLink then return false end
  if C_Item and C_Item.IsItemCraftingReagent then return C_Item.IsItemCraftingReagent(itemIDOrLink) and true or false end
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not getInfo then return false end
  return select(17, getInfo(itemIDOrLink)) and true or false
end

-- KondoBags_HeldItemFacts for the fit test (Client.ItemFitsKind): everything it needs about one item.
function P.ItemFacts(itemIDOrLink)
  return { familyMask = P.ItemFamily(itemIDOrLink), isReagent = P.IsCraftingReagent(itemIDOrLink) }
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
