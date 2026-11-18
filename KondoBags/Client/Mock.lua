-- KondoBags Client/Mock.lua -- provider over a plain table, for spec/run.lua (off-client tests).
-- No WoW API. The table shape is Scan.Refs' output: a ref list in bag
-- order, each { bagID, slot, kind, item = { itemID, name, icon, count, quality } | nil }.
--
--   Client.NewMock(refs) -> KondoBags_ClientProvider named "Mock" that reads/writes that table.
--   Pickup(bag, slot) emulates the real cursor: first call picks up, second call swaps/places.

local _, ns = ...
local Client = ns.Client

function Client.NewMock(refs)
  local byBag = {}     -- bagID -> { kind, slots = { [slot] = ref } }
  local order = {}     -- bagIDs in first-seen order
  for _, ref in ipairs(refs) do
    local b = byBag[ref.bagID]
    if not b then b = { kind = ref.kind or "general", slots = {}, n = 0 }; byBag[ref.bagID] = b; order[#order + 1] = ref.bagID end
    b.slots[ref.slot] = ref
    if ref.slot > b.n then b.n = ref.slot end
  end

  local P = { name = "Mock", cursor = nil, inCombat = false }
  function P.BagIDs() local t = {}; for i, id in ipairs(order) do t[i] = id end; return t end
  function P.NumSlots(bag) return byBag[bag] and byBag[bag].n or 0 end
  function P.FreeSlots(bag)
    local b = byBag[bag]; if not b then return 0, 0 end
    local free = 0
    for s = 1, b.n do if not (b.slots[s] and b.slots[s].item) then free = free + 1 end end
    return free, 0
  end
  function P.BagKind(bag) return byBag[bag] and byBag[bag].kind or "general" end
  function P.SlotInfo(bag, slot)
    local ref = byBag[bag] and byBag[bag].slots[slot]
    local it = ref and ref.item
    if not it then return nil end
    return { itemID = it.itemID, link = nil, icon = it.icon, count = it.count or 1, quality = it.quality or 1, locked = false, name = it.name }
  end
  function P.QuestInfo(bag, slot)
    local ref = byBag[bag] and byBag[bag].slots[slot]
    return ref and ref.item and ref.item.quest or nil
  end
  function P.Pickup(bag, slot)
    local ref = byBag[bag] and byBag[bag].slots[slot]
    if not ref then return end
    if P.cursor then
      P.cursor.item, ref.item = ref.item, P.cursor.item   -- swap or place
      P.cursor = nil
    elseif ref.item then
      P.cursor = { item = ref.item }; ref.item = nil
    end
  end
  function P.InCombat() return P.inCombat end
  return P
end