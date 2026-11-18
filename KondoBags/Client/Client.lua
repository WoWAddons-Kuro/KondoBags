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