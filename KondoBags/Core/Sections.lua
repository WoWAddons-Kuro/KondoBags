-- KondoBags Core/Sections.lua -- pure Lua. The section MODEL (SPECS/00 D12 + D15).
--
-- No WoW API. Runs under stock Lua 5.1 (spec/run.lua) and in game alike.
--
-- A POSITIONAL map with nullable backing. The general bag is a flat list of PHYSICAL slots 0..N-1
-- (Blizzard order). Incoming is a list of VISUAL positions; store.map[v] is the physical slot drawn
-- at position v (v = 1 is the bottom-right anchor; higher v walks left/up), or Sections.ABSENT while
-- a position's slot has just been taken. Keep is a SET of physical slots (store.kept[phys] = groupID).
--
-- Every gesture is ONE primitive followed by ReorderHoles():
--   a slot in incoming empties          -> ReorderHoles()                      (the position is a hole where it was)
--   a slot leaves Keep                  -> append a NEW position at the top-left, ReorderHoles()
--   something goes into Keep from incoming -> map[v] = nil-backing? NO: the slot is REMOVED from map, kept[phys] = g,
--                                          the position becomes a hole backed by ... see Pin; ReorderHoles()
--   something goes into Keep from outside  -> take the TOP-LEFT-most hole's slot, kept[slot] = g, map[v] = ABSENT,
--                                          ReorderHoles()                      (one server op: Pickup into that slot)
-- ReorderHoles(): (a) delete ABSENT positions, shifting everything top-left of them one step toward
-- the bottom-right (backing untouched: no leapfrog); (b) re-assign the physical slots behind the HOLES
-- so that reading from the bottom-right they ASCEND -> the lowest free physical slot is the
-- bottom-right-most hole, where Blizzard loots next.
--
--   KondoBags_SectionStore = { nextID = number,
--                              map  = { [KondoBags_Position] = KondoBags_SlotIndex | ABSENT },
--                              kept = { [KondoBags_SlotIndex] = KondoBags_SectionID },
--                              list = { KondoBags_Group... } }        -- display order, incoming first
--   KondoBags_Position     = number, 1-based visual index into incoming (1 = bottom-right)
--   KondoBags_SlotIndex    = number, 0-based PHYSICAL index into the flat general bag
--   KondoBags_Group        = { id = KondoBags_SectionID, name = string, order = { KondoBags_SlotIndex... } }
--   KondoBags_SectionID    = string, "s<n>", never reused
--   KondoBags_PinOp        = { place = true, slotIndex = KondoBags_SlotIndex }  -- one PickupContainerItem

local _, ns = ...
ns = ns or {}
local Sections = {}
ns.Sections = Sections

Sections.HEARTHSTONE_ID = 6948
Sections.DEFAULT_KEEP_NAME = "Keep"
Sections.ABSENT = -1          -- a position whose physical slot was just taken; ReorderHoles deletes it

-- ---------------------------------------------------------------------------
-- store
-- ---------------------------------------------------------------------------

function Sections.NewStore()
  local store = { nextID = 1, map = {}, kept = {}, list = {} }
  Sections.Create(store, Sections.DEFAULT_KEEP_NAME)
  return store
end

function Sections.Create(store, name)
  local id = "s" .. store.nextID
  store.nextID = store.nextID + 1
  local group = { id = id, name = name or "", order = {} }
  table.insert(store.list, 1, group)          -- new groups draw FIRST, directly under incoming
  return group
end

function Sections.Find(store, sectionID)
  for i, g in ipairs(store.list) do if g.id == sectionID then return g, i end end
  return nil
end

function Sections.IsKept(store, slot) return store.kept[slot] ~= nil end
function Sections.GroupOfSlot(store, slot) local id = store.kept[slot]; return id and Sections.Find(store, id) or nil end
Sections.SectionOfSlot = Sections.GroupOfSlot
function Sections.ItemCount(group) return #group.order end

local function IndexInOrder(group, slot)
  for i, s in ipairs(group.order) do if s == slot then return i end end
  return nil
end
local function RemoveSlotFromOrders(store, slot)
  for _, g in ipairs(store.list) do local i = IndexInOrder(g, slot); if i then table.remove(g.order, i) end end
end
local function GapIndex(group, anchorSlot)
  local i = anchorSlot and IndexInOrder(group, anchorSlot)
  return i and (i + 1) or 1
end
local function PositionOf(store, slot)
  for v, s in ipairs(store.map) do if s == slot then return v end end
  return nil
end

-- ---------------------------------------------------------------------------
-- ReorderHoles
-- ---------------------------------------------------------------------------
-- `isFree(slot) -> bool` reports physical occupancy. Two passes, see the file header.
function Sections.ReorderHoles(store, isFree)
  -- (a) delete ABSENT positions; everything top-left of them (higher v) steps one toward the bottom-right
  local compact = {}
  for _, s in ipairs(store.map) do if s ~= Sections.ABSENT then compact[#compact + 1] = s end end
  store.map = compact
  -- (b) holes: collect their physical slots, sort ascending, hand them back from the bottom-right up
  local holePositions, holeSlots = {}, {}
  for v, s in ipairs(store.map) do
    if isFree(s) then holePositions[#holePositions + 1] = v; holeSlots[#holeSlots + 1] = s end
  end
  table.sort(holeSlots)
  for i, v in ipairs(holePositions) do store.map[v] = holeSlots[i] end
end

-- The top-left-most hole (highest v with a free slot), or nil when incoming has no hole.
function Sections.TopLeftHole(store, isFree)
  for v = #store.map, 1, -1 do if isFree(store.map[v]) then return v end end
  return nil
end

-- ---------------------------------------------------------------------------
-- gestures  (each returns the ONE server op it needs, or {} for none; nil = cannot)
-- ---------------------------------------------------------------------------

-- Pin the item in general slot `slot` (currently incoming) into `group`. ZERO server ops: the slot
-- moves from the map into kept; its position becomes a hole backed by... nothing yet -- we mark it
-- ABSENT so ReorderHoles (a) closes the run. (Owner, 2026-11-18: 'when we steal a free slot to put it
-- in keep, compact the positions left of it'. The same rule applies to a pinned ITEM's position.)
function Sections.Pin(store, group, slot, anchorSlot, isFree)
  if store.kept[slot] then return nil end
  local v = PositionOf(store, slot)
  if v then store.map[v] = Sections.ABSENT end
  store.kept[slot] = group.id
  table.insert(group.order, GapIndex(group, anchorSlot), slot)
  Sections.ReorderHoles(store, isFree)
  return {}
end

-- Pin an item that is NOT in the general list (external cursor, typed bag): steal the top-left-most
-- hole. Returns { KondoBags_PinOp } (one Pickup into its slot), the slot; or nil when there is no hole.
function Sections.PinFromOutside(store, group, anchorSlot, isFree)
  local v = Sections.TopLeftHole(store, isFree)
  if not v then return nil end
  local h = store.map[v]
  store.map[v] = Sections.ABSENT
  store.kept[h] = group.id
  table.insert(group.order, GapIndex(group, anchorSlot), h)
  Sections.ReorderHoles(store, isFree)
  return { { place = true, slotIndex = h } }, h
end

-- A slot leaves Keep (unpin, consume, dissolve): it needs a position -> a NEW one at the far top-left.
function Sections.Release(store, slot, isFree)
  if not store.kept[slot] then return false end
  store.kept[slot] = nil
  RemoveSlotFromOrders(store, slot)
  store.map[#store.map + 1] = slot
  Sections.ReorderHoles(store, isFree)
  return true
end
Sections.Unpin = Sections.Release

function Sections.MoveToGap(store, group, slot, anchorSlot)
  if slot == anchorSlot or not store.kept[slot] then return false end
  RemoveSlotFromOrders(store, slot)
  store.kept[slot] = group.id
  table.insert(group.order, GapIndex(group, anchorSlot), slot)
  return true
end

function Sections.MoveToPositionOf(store, slot, otherSlot)
  if slot == otherSlot then return false end
  local target = Sections.GroupOfSlot(store, otherSlot)
  if not target or not store.kept[slot] then return false end
  RemoveSlotFromOrders(store, slot)
  store.kept[slot] = target.id
  table.insert(target.order, IndexInOrder(target, otherSlot), slot)
  return true
end

-- Shift-insert into INCOMING (SPECS/00 "Shift-insert", Step 2). Incoming is the positional map;
-- holes are interchangeable (D15), so "insert a free slot at this boundary" is: remove the lowest
-- free slot's position and re-insert it between the two named neighbours. Pure map edit; the caller
-- then Pickup()s into that slot. `afterSlot` / `beforeSlot` are the PHYSICAL slots either side of
-- the boundary in reading order (after = the cell to the LEFT, i.e. the HIGHER position; before =
-- the cell to the RIGHT, LOWER position); either may be nil at the run's ends. Returns the slot
-- moved, or nil when incoming has no hole.
function Sections.MoveFreeToBoundary(store, afterSlot, beforeSlot, isFree)
  -- Spend the hole with the LOWEST physical index (where Blizzard would loot next). A hole sitting
  -- right next to the marker is a position like any other: the inserted cell lands BETWEEN the two
  -- neighbours and the holes keep their positions (D15: holes re-sort backing, never positions).
  local hole, holeV
  for v, s in ipairs(store.map) do
    if isFree(s) and (hole == nil or s < hole) then hole, holeV = s, v end
  end
  if not hole then return nil end
  -- Resolve the boundary BEFORE removing the hole so neighbour positions are read from the intact map.
  local afterV = afterSlot ~= nil and PositionOf(store, afterSlot) or nil
  local beforeV = beforeSlot ~= nil and PositionOf(store, beforeSlot) or nil
  if (afterSlot ~= nil and not afterV) and (beforeSlot ~= nil and not beforeV) then return nil end
  table.remove(store.map, holeV)
  -- Reading order is position DESCENDING, so the boundary "after X / before Y" sits at the position
  -- just below X (= just above Y). Resolve from whichever neighbour exists.
  local target
  if afterV then
    target = afterV > holeV and afterV or afterV             -- X's position after the removal shift
    if afterV > holeV then target = afterV - 1 end           -- removing a lower position shifts X down by one
  elseif beforeV then
    target = (beforeV > holeV and beforeV - 1 or beforeV) + 1 -- just above Y (same shift rule)
  else
    target = #store.map + 1                                  -- empty run: only position
  end
  table.insert(store.map, target, hole)
  return hole
end

-- Stack adoption (KondoBagsDB.stackAdjacent): a slot that was EMPTY on the previous scan and now
-- holds an item whose itemID is also held by a KEPT slot is pinned into that group right in front
-- of the sibling. Pure map edit, zero server ops: the loot stays in the physical slot Blizzard
-- chose; we only change where it is drawn. Loot whose siblings are all in incoming is left alone
-- (incoming is physical order, there is nothing to remap to).
--
-- Only LOOT is adopted -- NEVER something the player just moved. The addon's whole promise is
-- "nothing moves unless you move it": when the player drags a stack OUT of Keep onto an empty
-- incoming cell they did it on purpose (to use it up, sell it, give it away, or simply because they
-- want it loose), and the bag must let it go. But to this function that gesture looks exactly like
-- loot: a previously-empty slot now holds an itemID that a kept sibling also holds. Without
-- `exclude` the unpin was silently re-pinned and the item snapped back into Keep (17 + 20 bandages,
-- 2026-11-20) -- the one thing this addon must never do. So the caller passes the itemIDs that LEFT
-- a kept slot this scan, and those are never adopted; the player's move stands.
--   prevItemIDs: { [KondoBags_SlotIndex] = itemID }  of the previous scan (nil = first scan; no-op)
--   slots:       { KondoBags_SlotRef... }            current scan, index i = slot i-1
--   exclude:     { [itemID] = true } or nil           itemIDs that left Keep this scan (player unpin)
-- Returns the number of slots adopted.
function Sections.AdoptNewStacks(store, prevItemIDs, slots, isFree, exclude)
  if not prevItemIDs then return 0 end
  -- itemID -> first KEPT slot holding it, in display order (store.list, then group.order)
  local keptByItem = {}
  for _, g in ipairs(store.list) do
    for _, s in ipairs(g.order) do
      local ref = slots[s + 1]
      local id = ref and ref.item and ref.item.itemID
      if id and keptByItem[id] == nil then keptByItem[id] = s end
    end
  end
  if next(keptByItem) == nil then return 0 end
  local adopted = 0
  for i, ref in ipairs(slots) do
    local slot = i - 1
    local id = ref.item and ref.item.itemID
    if id and prevItemIDs[slot] == nil and not store.kept[slot] and not (exclude and exclude[id]) then  -- newly filled, still incoming, not an unpin
      local sibling = keptByItem[id]
      if sibling and sibling ~= slot then
        local group = Sections.GroupOfSlot(store, sibling)
        -- Anchor = the slot BEFORE the sibling so the new stack lands directly in front of it
        -- (water, 2/20 linen, 20/20 linen, food). Sibling first in group -> anchor nil = index 1.
        local idx = IndexInOrder(group, sibling)
        local anchorSlot = idx and idx > 1 and group.order[idx - 1] or nil
        if Sections.Pin(store, group, slot, anchorSlot, isFree) then adopted = adopted + 1 end
      end
    end
  end
  return adopted
end

-- Remove a group: every slot is Released. ZERO server ops. false if unknown or the last group.
function Sections.Dissolve(store, sectionID, isFree)
  local g, i = Sections.Find(store, sectionID)
  if not g or #store.list < 2 then return false end
  local slots = {}
  for k, s in ipairs(g.order) do slots[k] = s end
  table.remove(store.list, i)
  for _, s in ipairs(slots) do store.kept[s] = nil; store.map[#store.map + 1] = s end
  Sections.ReorderHoles(store, isFree)
  return true
end

-- ---------------------------------------------------------------------------
-- partition for the layout
-- ---------------------------------------------------------------------------

-- `slots` is { KondoBags_SlotRef... } indexed 1..N (physical = i-1). Incoming comes out in READING
-- order: position #map (top-left) first down to position 1 (bottom-right). Then every group.
function Sections.Partition(store, slots, columns, typedSlots)
  local loose = {}
  for v = #store.map, 1, -1 do
    local ref = slots[store.map[v] + 1]
    if ref then loose[#loose + 1] = ref end
  end
  local typed = {}
  for i = #(typedSlots or {}), 1, -1 do typed[#typed + 1] = typedSlots[i] end
  local sections = {}
  for _, g in ipairs(store.list) do
    local sec = { id = g.id, name = g.name, slots = {} }
    for _, slot in ipairs(g.order) do
      local ref = slots[slot + 1]
      if ref then sec.slots[#sec.slots + 1] = ref end
    end
    sections[#sections + 1] = sec
  end
  return { columns = columns, typed = typed, loose = loose, sections = sections }
end

-- Validate/repair a saved store against the current bag:
--   * pre-D15 stores (boundary / per-item sets / no map) -> fresh;
--   * kept entries that are out of range, EMPTY (D13.1) or name an unknown group are Released;
--   * every physical slot appears exactly once in map+kept: duplicates/out-of-range dropped from the map,
--     missing ones appended at the top-left (a bag grew, a slot was never seen);
--   * every group's order = its kept slots, once each; >= 1 group; then ReorderHoles.
function Sections.Reconcile(store, slotCount, slots)
  local fresh = false
  if type(store) ~= "table" or type(store.list) ~= "table" or type(store.kept) ~= "table" or type(store.map) ~= "table" then
    store = Sections.NewStore()
    fresh = true
  end
  local function occupied(slot) return not slots or (slots[slot + 1] ~= nil and slots[slot + 1].item ~= nil) end
  local function isFree(slot) return not occupied(slot) end
  if #store.list == 0 then Sections.Create(store, Sections.DEFAULT_KEEP_NAME) end
  -- First run on this character (store.seeded unset): the Hearthstone starts in Keep (SPECS/00 D10,
  -- README). Seed by itemID once; store.seeded then stays true forever, so a player who later unpins
  -- it is never fought. Zero server ops: the slot is simply marked kept before the map is built.
  if (fresh or not store.seeded) and slots then
    store.seeded = true
    local keep = store.list[#store.list]            -- the default "Keep" group (created first, drawn last)
    for i, ref in ipairs(slots) do
      if ref.item and ref.item.itemID == Sections.HEARTHSTONE_ID and (ref.kind == nil or ref.kind == "general") then
        local slot = i - 1
        if not store.kept[slot] then store.kept[slot] = keep.id; keep.order[#keep.order + 1] = slot end
        break
      end
    end
  end
  -- kept: drop bad entries (they will be re-added to the map below as ordinary slots)
  for slot, gid in pairs(store.kept) do
    if type(slot) ~= "number" or slot < 0 or slot >= slotCount or not occupied(slot) or not Sections.Find(store, gid) then
      store.kept[slot] = nil
    end
  end
  -- map: keep only valid, non-kept, first-seen slots
  local seen, map = {}, {}
  for _, s in ipairs(store.map) do
    if type(s) == "number" and s >= 0 and s < slotCount and not store.kept[s] and not seen[s] then
      map[#map + 1] = s; seen[s] = true
    end
  end
  for s = 0, slotCount - 1 do
    if not seen[s] and not store.kept[s] then map[#map + 1] = s; seen[s] = true end   -- new / released: top-left
  end
  store.map = map
  -- orders
  local inOrder = {}
  for _, g in ipairs(store.list) do
    local order = {}
    for _, slot in ipairs(g.order or {}) do
      if store.kept[slot] == g.id and not inOrder[slot] then order[#order + 1] = slot; inOrder[slot] = true end
    end
    g.order = order
  end
  for slot, gid in pairs(store.kept) do
    if not inOrder[slot] then local g = Sections.Find(store, gid); g.order[#g.order + 1] = slot end
  end
  Sections.ReorderHoles(store, isFree)
  return store
end

return Sections