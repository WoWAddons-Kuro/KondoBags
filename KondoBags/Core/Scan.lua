-- KondoBags Core/Scan.lua -- pure Lua. Turns a KondoBags_ClientProvider into the ref list BagState
-- consumes. No WoW API: it only calls the provider, so it runs under lua5.1 over Client.NewMock.
--
--   Scan.Refs(provider) -> { KondoBags_SlotRef... }, KondoBags_ScanSummary
--     KondoBags_SlotRef     = { bagID, slot, kind, item = KondoBags_ItemView | nil }
--     KondoBags_ItemView    = { itemID, link, name, icon, count, quality, locked }
--     KondoBags_ScanSummary = { general = n, typed = n, free = { [kind] = n } }
--
-- Order: GENERAL bags first in provider BagIDs() order, slot 1..N each -- that sequence IS the
-- flat combined index (slot 0 = backpack slot 1), the loot order Blizzard fills. Typed bags follow
-- in the same order; BagState splits them off by ref.kind. The shape matches Mock.Slots() so the
-- mockup and the live window are the same code path from here on.

local _, ns = ...
ns = ns or {}
local Scan = {}
ns.Scan = Scan

local function ItemView(raw)
  if not raw then return nil end
  return {
    itemID = raw.itemID, link = raw.link, name = raw.name, icon = raw.icon,
    count = raw.count or 1, quality = raw.quality or 1, locked = raw.locked or false,
  }
end

function Scan.Refs(provider)
  local general, typed = {}, {}
  local summary = { general = 0, typed = 0, free = {} }
  for _, bag in ipairs(provider.BagIDs()) do
    local kind = provider.BagKind(bag) or "general"
    local into = (kind == "general") and general or typed
    local n = provider.NumSlots(bag)
    for slot = 1, n do
      local ref = { bagID = bag, slot = slot, kind = kind, item = ItemView(provider.SlotInfo(bag, slot)) }
      into[#into + 1] = ref
      if not ref.item then summary.free[kind] = (summary.free[kind] or 0) + 1 end
    end
  end
  summary.general, summary.typed = #general, #typed
  local refs = {}
  for _, r in ipairs(general) do refs[#refs + 1] = r end
  for _, r in ipairs(typed) do refs[#refs + 1] = r end
  return refs, summary
end

return Scan