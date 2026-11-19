-- KondoBags Client/Client.lua -- the provider interface and selection (SPECS/00 D5).
--
-- Everything the addon knows about the game's bags comes through ONE table of functions,
-- KondoBags_ClientProvider. Exactly one provider is active: Era, Mainline (Forever/Retail/Cata/Mists
-- all run the Mainline UI code) or Mock (spec/run.lua, no WoW API). Providers are feature-detected,
-- never version-checked. Core/ never calls C_* directly.
--
--   KondoBags_ClientProvider = {
--     name     = "Era" | "Mainline" | "Mock",
--     BagIDs   = function() -> { KondoBags_BagID... }     -- every bag we draw, general first, in flat-index order
--     NumSlots = function(bagID) -> number
--     FreeSlots= function(bagID) -> numFree, KondoBags_FamilyMask
--     BagKind  = function(bagID) -> KondoBags_SlotKind     -- "general" | KondoBags_BagFamily (see below)
--     SlotInfo = function(bagID, slot) -> KondoBags_RawSlotInfo | nil   -- nil = empty slot
--     Pickup   = function(bagID, slot)                     -- C_Container.PickupContainerItem
--     InCombat = function() -> bool
--   }
--   KondoBags_RawSlotInfo = { itemID, link, icon, count, quality, locked, name }
--   KondoBags_BagID       = number (Enum.BagIndex value; Era keyring is negative)

local _, ns = ...
local Client = {}
ns.Client = Client

-- ---------------------------------------------------------------------------
-- Bag families: wire bitmask  <->  KondoBags_BagFamily enum (what the code reasons about)
-- ---------------------------------------------------------------------------
-- The game speaks ONE bitmask (ItemBagFamily, _EXTERNAL_APIS/wow_bag_family_bitmask.md) in two places:
--   C_Container.GetContainerNumFreeSlots(bag) -> numFree, KondoBags_FamilyMask   (what the BAG accepts)
--   C_Item.GetItemFamily(item)                -> KondoBags_FamilyMask            (which bags may hold the ITEM)
-- An item fits a bag when the two masks share a set bit. Nothing else in the addon touches raw bits:
-- the mask is DECODED here into a KondoBags_BagFamilySet, and KondoBags_SlotKind (the one name a slot
-- is drawn as: tint, glyph, cursor refusal) is derived from that set.
--
--   KondoBags_FamilyMask   = number (raw ItemBagFamily bits; 0 = general bag / ordinary item)
--   KondoBags_BagFamily    = "quiver" | "ammo" | "soul" | "leatherworking" | "inscription" | "herb" |
--                            "enchanting" | "engineering" | "keyring" | "gem" | "mining" | "fishing" | "cooking"
--   KondoBags_BagFamilySet = { [KondoBags_BagFamily] = true }   -- decoded mask; empty = general
--   KondoBags_SlotKind     = "general" | KondoBags_BagFamily    -- the family a slot is drawn as
--
-- Forever defines families ABOVE the classic table: 2^25 is its leatherworking bag (Apprentice's
-- Skinning Satchel, GetContainerNumFreeSlots, owner 2026-11-19). The classic bit 2^3 (TBC leatherworking)
-- is kept too, so ONE family can own SEVERAL bits -- which is why the decode is set-based.
-- A mask bit not listed here decodes to the pseudo-family "unknown:<bit>" so it is never silently
-- "general" (the slot still goes to the typed strip) and `/kondo bags` shows what to add.
Client.FAMILY_BY_BIT = {
  [2 ^ 0]  = "quiver",          -- Arrows
  [2 ^ 1]  = "ammo",            -- Bullets
  [2 ^ 2]  = "soul",            -- Soul Shards
  [2 ^ 3]  = "leatherworking",  -- Leatherworking Supplies (TBC+)
  [2 ^ 4]  = "inscription",     -- Inscription Supplies (Wrath+)
  [2 ^ 5]  = "herb",
  [2 ^ 6]  = "enchanting",
  [2 ^ 7]  = "engineering",
  [2 ^ 8]  = "keyring",
  [2 ^ 9]  = "gem",
  [2 ^ 10] = "mining",
  -- 2^11..2^14 are item-only flags (soulbound equipment, pets, currency, quest); no bag has them
  [2 ^ 15] = "fishing",         -- Tackle Box
  [2 ^ 16] = "cooking",
  [2 ^ 25] = "leatherworking",  -- Forever
}
Client.ITEM_ONLY_BITS = { [2 ^ 11] = true, [2 ^ 12] = true, [2 ^ 13] = true, [2 ^ 14] = true }
local MAX_FAMILY_BIT = 2 ^ 31

-- KondoBags_FamilyMask -> KondoBags_BagFamilySet. Pure Lua (no bit library on 5.1): peel bits lowest-first.
function Client.DecodeFamilyMask(mask)
  local set = {}
  local rest = mask or 0
  local bit = 1
  while rest > 0 and bit <= MAX_FAMILY_BIT do
    if rest % (bit * 2) >= bit then
      rest = rest - bit
      if not Client.ITEM_ONLY_BITS[bit] then
        set[Client.FAMILY_BY_BIT[bit] or ("unknown:" .. bit)] = true
      end
    end
    bit = bit * 2
  end
  return set
end

-- Stable order (lowest classic bit first): picks THE kind a slot is drawn as if a bag ever reports
-- more than one family (none do today; defensive).
local FAMILY_ORDER = { "quiver", "ammo", "soul", "leatherworking", "inscription", "herb", "enchanting",
                       "engineering", "keyring", "gem", "mining", "fishing", "cooking" }

-- KondoBags_BagFamilySet -> KondoBags_SlotKind. Empty set = "general". An "unknown:<bit>" family is
-- returned as-is so the slot still lands in the typed strip (no glyph/tint, but never in incoming).
function Client.KindFromFamilySet(set)
  for _, fam in ipairs(FAMILY_ORDER) do if set[fam] then return fam end end
  for fam in pairs(set) do return fam end
  return "general"
end

-- Convenience: KondoBags_FamilyMask -> KondoBags_SlotKind.
function Client.KindFromFamily(mask)
  return Client.KindFromFamilySet(Client.DecodeFamilyMask(mask))
end

-- Fallback: bag ITEM class/subclass -> KondoBags_BagFamily, for a client that reports mask 0 for a
-- bag that is not general. Enum.ItemClass.Container (1) and Enum.ItemClass.Quiver (11) subclasses per
-- the ItemSubClass DBC. nil = plain bag / not a bag.
Client.ITEM_CLASS_CONTAINER = 1
Client.ITEM_CLASS_QUIVER    = 11
Client.FAMILY_BY_CONTAINER_SUBCLASS = {
  [1] = "soul", [2] = "herb", [3] = "enchanting", [4] = "engineering", [5] = "gem",
  [6] = "mining", [7] = "leatherworking", [8] = "inscription", [9] = "fishing", [10] = "cooking",
}
Client.FAMILY_BY_QUIVER_SUBCLASS = { [2] = "quiver", [3] = "ammo" }
function Client.FamilyFromBagItemClass(classID, subClassID)
  if classID == Client.ITEM_CLASS_CONTAINER then return Client.FAMILY_BY_CONTAINER_SUBCLASS[subClassID or 0] end
  if classID == Client.ITEM_CLASS_QUIVER    then return Client.FAMILY_BY_QUIVER_SUBCLASS[subClassID or 0] end
  return nil
end

-- The KondoBags_BagFamilySet of an equipped bag: the API mask when it says anything, else the bag
-- item's class/subclass.
function Client.ResolveBagFamilySet(apiMask, classID, subClassID)
  local set = Client.DecodeFamilyMask(apiMask)
  if next(set) then return set end
  local fam = Client.FamilyFromBagItemClass(classID, subClassID)
  if fam then set[fam] = true end
  return set
end

-- Does an item whose C_Item.GetItemFamily mask is `itemMask` fit a slot drawn as `kind`?
-- General slots take anything. A typed slot takes the item only if the item's decoded family set
-- contains that kind (a Quiver takes arrows, never thrown weapons or herbs). nil/0 = ordinary item =
-- refused by every typed slot. Pure Lua (tests).
function Client.ItemFitsKind(itemMask, kind)
  if not kind or kind == "general" then return true end
  return Client.DecodeFamilyMask(itemMask)[kind] == true
end

-- Charges left on a charge-based item (Bag of Marbles "10 Charges"); nil when the item has none.
-- ContainerItemInfo has no field for it (stackCount is the STACK), so the tooltip is read:
-- C_TooltipInfo.GetBagItem where it exists (Forever), else a hidden GameTooltip (Era). Cached per
-- bag:slot:link. A used charge keeps the same link, so the owner calls InvalidateTooltipCharges(bag)
-- on BAG_UPDATE(bag) and the next scan re-reads that bag's slots. Same code on every client.
local chargePattern   -- built lazily: ITEM_SPELL_CHARGES is a global set by the client at load
local function ChargePattern()
  if not chargePattern then
    -- The global is "%d Charges" (Era) or "%d |4Charge:Charges;" (plural token, Forever). Keep the
    -- LITERAL words: "|4Charge:Charges;" -> "Charges?", "%d" -> "(%d+)", anchored to the whole line.
    -- An earlier "%a+" version matched ANY "number word" line and read "Durability 40" / "8 - 13
    -- Damage" as charges (owner screenshot, 2026-11-19).
    local src = ITEM_SPELL_CHARGES or "%d Charges"
    src = src:gsub("|4([^:;]*):([^;]*);", function(singular, plural)
      return plural:sub(1, #singular) == singular and (singular .. plural:sub(#singular + 1) .. "?") or ("(" .. singular .. "|" .. plural .. ")")
    end)
    chargePattern = "^" .. src:gsub("%%d", "(%%d+)") .. "$"
  end
  return chargePattern
end
local chargeCache = {}        -- "bag:slot:link" -> charges | false (scanned, item has none)
local scanTip
function Client.TooltipCharges(bag, slot, link)
  if not link then return nil end
  local key = bag .. ":" .. slot .. ":" .. link
  local cached = chargeCache[key]
  if cached ~= nil then return cached or nil end
  local pattern, n = ChargePattern(), nil
  if C_TooltipInfo and C_TooltipInfo.GetBagItem then
    local data = C_TooltipInfo.GetBagItem(bag, slot)
    for _, line in ipairs(data and data.lines or {}) do
      local m = line.leftText and line.leftText:match(pattern)
      if m then n = tonumber(m); break end
    end
  elseif CreateFrame then
    scanTip = scanTip or CreateFrame("GameTooltip", "KondoBagsScanTooltip", nil, "GameTooltipTemplate")
    scanTip:SetOwner(UIParent, "ANCHOR_NONE"); scanTip:ClearLines(); scanTip:SetBagItem(bag, slot)
    for i = 1, scanTip:NumLines() do
      local fs = _G["KondoBagsScanTooltipTextLeft" .. i]
      local m = fs and fs:GetText() and fs:GetText():match(pattern)
      if m then n = tonumber(m); break end
    end
  end
  chargeCache[key] = n or false
  return n
end
function Client.InvalidateTooltipCharges(bag)
  local prefix = bag .. ":"
  for k in pairs(chargeCache) do if k:sub(1, #prefix) == prefix then chargeCache[k] = nil end end
end

local providers = {}   -- name -> KondoBags_ClientProvider
function Client.Register(p) providers[p.name] = p end

local active
-- Pick the provider for this client. Era if the Era quest-log globals exist and C_QuestLog.GetInfo
-- does not (the one API-family split we know of); Mainline otherwise. A provider may be forced
-- (spec/run.lua forces Mock).
function Client.Select(forceName)
  if forceName then active = providers[forceName] end
  if not active then
    local isEra = type(GetQuestLogTitle) == "function" and not (C_QuestLog and C_QuestLog.GetInfo)
    active = providers[isEra and "Era" or "Mainline"] or providers.Mainline or providers.Era
  end
  return active
end
function Client.Active() return active or Client.Select() end

return Client