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
  -- Does this client actually show a keyring? GetContainerNumSlots(KEYRING_CONTAINER) answers for the
  -- container ID on EVERY client (32 on Era 1.15, which has no keyring UI at all), so slot count is not
  -- the signal. Stock gates on C_ActionBar.ShouldShowKeyring() (Forever), GetKeyRingSize() and the
  -- showKeyring cvar (_ref/blizzard/forever/ContainerFrame.lua:10,80,238; classic_era/
  -- ContainerFrame_Shared.lua:118-124). Same three, in that order of trust.
  local function HasKeyring()
    if not KEYRING_CONTAINER then return false end
    if C_ActionBar and C_ActionBar.ShouldShowKeyring then return C_ActionBar.ShouldShowKeyring() and true or false end
    if GetKeyRingSize then return (GetKeyRingSize() or 0) > 0 end
    if C_CVar and C_CVar.GetCVarBool then
      local ok, shown = pcall(C_CVar.GetCVarBool, "showKeyring")
      if ok and shown ~= nil then return shown end
    end
    return false
  end
  P.HasKeyring = HasKeyring
  for bag = 0, NUM_BAG_SLOTS or 4 do
    if P.NumSlots(bag) > 0 then ids[#ids + 1] = bag end
  end
  if HasKeyring() and KondoBagsDB and KondoBagsDB.showKeys and P.NumSlots(KEYRING_CONTAINER) > 0 then ids[#ids + 1] = KEYRING_CONTAINER end
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

-- Bag-family bits of an item (which typed bags may hold it); 0 for ordinary items.
function P.ItemFamily(itemIDOrLink)
  if not itemIDOrLink then return 0 end
  local fn = (C_Item and C_Item.GetItemFamily) or GetItemFamily
  return fn and fn(itemIDOrLink) or 0
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
  -- Era 1.15 DECLARES the same ItemQuestInfo struct (ContainerDocumentation.lua:659) but the live
  -- client returned isQuestItem = false for a Scavenger Paw whose tooltip said "Quest Item" (owner,
  -- 2026-11-18, screenshot). The tooltip line comes from the item CLASS, so that is the fallback:
  -- GetItemInfoInstant classID 12 (Enum.ItemClass.Questitem) marks the item a quest item when the
  -- quest API will not. questID / isActive (the "!" for quest starters) come only from the quest API.
  local q = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot) or nil
  local isQuest = (q and q.isQuestItem) or false
  if not isQuest then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local link = info and (info.hyperlink or info.itemID)
    local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if link and getInstant then
      local _, _, _, _, _, classID = getInstant(link)
      local questClass = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12
      isQuest = classID == questClass
    end
  end
  local questID = q and q.questID or nil
  if not isQuest and not questID then return nil end
  return { isQuestItem = isQuest, questID = questID, isActive = (q and q.isActive) or false }
end

function P.Pickup(bag, slot) C_Container.PickupContainerItem(bag, slot) end
function P.InCombat() return InCombatLockdown() end

Client.Register(P)