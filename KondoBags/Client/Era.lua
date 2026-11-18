-- KondoBags Client/Era.lua -- provider for Classic Era / Hardcore (1.15.x).
-- C_Container is identical to Mainline (confirmed: _EXTERNAL_APIS/wow_classic_era_container_ui_api.md);
-- the differences are the negative-ID keyring and no reagent bag. Everything else delegates.

local _, ns = ...
local Client = ns.Client

local P = { name = "Era" }

function P.NumSlots(bag) return C_Container.GetContainerNumSlots(bag) or 0 end

function P.FreeSlots(bag)
  local free, family = C_Container.GetContainerNumFreeSlots(bag)
  return free or 0, family or 0
end

-- Backpack + 4 bags, then the keyring (KEYRING_CONTAINER, negative) if it has slots.
function P.BagIDs()
  local ids = {}
  for bag = 0, NUM_BAG_SLOTS or 4 do
    if P.NumSlots(bag) > 0 then ids[#ids + 1] = bag end
  end
  if KEYRING_CONTAINER and P.NumSlots(KEYRING_CONTAINER) > 0 then ids[#ids + 1] = KEYRING_CONTAINER end
  return ids
end

function P.BagKind(bag)
  if KEYRING_CONTAINER and bag == KEYRING_CONTAINER then return "keyring" end
  local _, family = P.FreeSlots(bag)
  return Client.KindFromFamily(family)
end

-- Icon of the equipped bag itself (for empty-cell backdrops of typed bags); nil for the backpack / keyring.
function P.BagIcon(bag)
  if bag <= 0 or not C_Container.ContainerIDToInventoryID then return nil end
  local inv = C_Container.ContainerIDToInventoryID(bag)
  return inv and GetInventoryItemTexture("player", inv) or nil
end

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

-- KondoBags_QuestFlags; GetContainerItemQuestInfo returns the same table on Era (confirmed in _EXTERNAL_APIS).
function P.QuestInfo(bag, slot)
  if not C_Container.GetContainerItemQuestInfo then return nil end
  local q = C_Container.GetContainerItemQuestInfo(bag, slot)
  if not q or not (q.isQuestItem or q.questID) then return nil end
  return { isQuestItem = q.isQuestItem or false, questID = q.questID, isActive = q.isActive or false }
end

function P.Pickup(bag, slot) C_Container.PickupContainerItem(bag, slot) end
function P.InCombat() return InCombatLockdown() end

Client.Register(P)