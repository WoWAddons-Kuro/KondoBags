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
--     FreeSlots= function(bagID) -> numFree, bagFamilyBits
--     BagKind  = function(bagID) -> KondoBags_SlotKind     -- "general" | "quiver" | ... (see Client.KIND_BY_BIT)
--     SlotInfo = function(bagID, slot) -> KondoBags_RawSlotInfo | nil   -- nil = empty slot
--     Pickup   = function(bagID, slot)                     -- C_Container.PickupContainerItem
--     InCombat = function() -> bool
--   }
--   KondoBags_RawSlotInfo = { itemID, link, icon, count, quality, locked, name }
--   KondoBags_BagID       = number (Enum.BagIndex value; Era keyring is negative)

local _, ns = ...
local Client = {}
ns.Client = Client

-- Bag-family bit -> KondoBags_SlotKind (ground truth: _EXTERNAL_APIS/wow_bag_family_bitmask.md).
Client.KIND_BY_BIT = {
  [1] = "quiver", [2] = "ammo", [4] = "soul", [8] = "leatherworking", [16] = "inscription",
  [32] = "herb", [64] = "enchanting", [128] = "engineering", [256] = "keyring", [512] = "gem",
  [1024] = "mining", [32768] = "fishing", [65536] = "cooking",
}

-- Lowest set bit of a bag-family mask -> kind; 0/nil -> "general". Pure Lua (shared by providers + tests).
function Client.KindFromFamily(family)
  if not family or family == 0 then return "general" end
  local bit = 1
  while bit <= 65536 do
    if family % (bit * 2) >= bit then return Client.KIND_BY_BIT[bit] or "general" end
    bit = bit * 2
  end
  return "general"
end

-- Does an item with bag-family bits `itemFamily` (C_Item.GetItemFamily) fit a slot of `kind`?
-- General slots take anything. A typed slot takes the item only if the item's family has that kind's
-- bit set (a Quiver takes arrows, never thrown weapons or herbs). Unknown itemFamily (nil) = refused
-- by typed slots, which is what a non-family item reports (0). Pure Lua (tests).
function Client.ItemFitsKind(itemFamily, kind)
  if not kind or kind == "general" then return true end
  -- The Mainline reagent bag has no family bit, so family bits cannot answer for it. Until the client
  -- gives a reagent predicate, ANY family-bagged item (arrows, herbs) is refused and ordinary items
  -- are allowed: wrong only for non-reagent ordinary items, never for typed ones.
  if kind == "reagent" then return (itemFamily or 0) == 0 end
  local f = itemFamily or 0
  for bit, k in pairs(Client.KIND_BY_BIT) do
    if k == kind then return f % (bit * 2) >= bit end
  end
  return false
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