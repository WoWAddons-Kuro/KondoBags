-- KondoBags Core/Sections.lua -- pure Lua. The section MODEL (SPECS/00 D12 + D15).
--
-- No WoW API. Runs under stock Lua 5.1 (spec/run.lua) and in game alike.
--
-- POSITIONS ARE VIRTUAL. The general bag is a flat list of PHYSICAL slots 0..N-1 (Blizzard order).
-- Keep is a SET of physical slots, scattered anywhere (store.kept). What the window draws is a list
-- of VISUAL positions:
--   incoming  = FREE general slots first, ascending physical (so the lowest free slot -- where
--               Blizzard loots next -- is the visually top-left cell), then OCCUPIED non-kept slots
--               in physical order. Occupied cells never move; only the free pool re-sorts.
--   groups    = kept slots in each group's `order` (visual order, left to right from the lock).
-- Every gesture is a MAP edit plus at most ONE server operation (D13.2 / D15).
--
--   KondoBags_SectionStore = { nextID = number,
--                              kept = { [KondoBags_SlotIndex] = KondoBags_SectionID },
--                              list = { KondoBags_Group... } }        -- display order, incoming first
--   KondoBags_Group        = { id = KondoBags_SectionID, name = string,
--                              order = { KondoBags_SlotIndex... } }  -- visual order, left to right from the lock
--   KondoBags_SectionID    = string, "s<n>", never reused
--   KondoBags_SlotIndex    = number, 0-based position in the flat general bag (PHYSICAL)
--   KondoBags_PinOp        = { place = true, slotIndex = KondoBags_SlotIndex }  -- one PickupContainerItem

local _, ns = ...
ns = ns or {}
local Sections = {}
ns.Sections = Sections

Sections.HEARTHSTONE_ID = 6948
Sections.DEFAULT_KEEP_NAME = "Keep"

-- ---------------------------------------------------------------------------
-- store
-- ---------------------------------------------------------------------------

-- A fresh store: nothing kept, one empty "Keep" group.
function Sections.NewStore()
  local store = { nextID = 1, kept = {}, list = {} }
  Sections.Create(store, Sections.DEFAULT_KEEP_NAME)
  return store
end

-- Add an EMPTY group (drawn FIRST, directly under incoming). The + button.
function Sections.Create(store, name)
  local id = "s" .. store.nextID
  store.nextID = store.nextID + 1
  local group = { id = id, name = name or "", order = {} }
  table.insert(store.list, 1, group)
  return group
end

function Sections.Find(store, sectionID)
  for i, g in ipairs(store.list) do
    if g.id == sectionID then return g, i end
  end
  return nil
end

function Sections.IsKept(store, slot) return store.kept[slot] ~= nil end

-- The group that owns `slot`, or nil for incoming.
function Sections.GroupOfSlot(store, slot)
  local id = store.kept[slot]
  return id and Sections.Find(store, id) or nil
end
Sections.SectionOfSlot = Sections.GroupOfSlot

function Sections.ItemCount(group) return #group.order end

local function IndexInOrder(group, slot)
  for i, s in ipairs(group.order) do if s == slot then return i end end
  return nil
end

local function RemoveSlotFromOrders(store, slot)
  for _, g in ipairs(store.list) do
    local i = IndexInOrder(g, slot)
    if i then table.remove(g.order, i) end
  end
end

-- Where a slot goes in `group.order` to land in the cursor gap anchored to `anchorSlot`: the gap is
-- drawn in the anchor's column and the anchor slides left, so the new entry sits immediately AFTER
-- the anchor; anchorSlot nil = right after the lock = first.
local function GapIndex(group, anchorSlot)
  local i = anchorSlot and IndexInOrder(group, anchorSlot)
  return i and (i + 1) or 1
end

-- Lowest free general slot (the visually top-left free cell), or nil when the bag is full.
-- `isFree(slot) -> bool` reports occupancy.
function Sections.LowestFree(store, slotCount, isFree)
  for s = 0, slotCount - 1 do
    if not store.kept[s] and isFree(s) then return s end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- gestures  (each edits the store and returns the ONE server op it needs, or {} for none)
-- ---------------------------------------------------------------------------

-- Pin the item sitting in general slot `slot` (incoming) into `group` at the gap anchored to
-- `anchorSlot` (nil = right after the lock). ZERO moves: the slot is marked kept; incoming's run
-- closes top-left-down by the map (Partition does that). Returns {} -- the caller may still need ONE
-- Pickup to put a cursor-held item back into `slot`, which is the caller's business, not the model's.
function Sections.Pin(store, group, slot, anchorSlot)
  if store.kept[slot] then return nil end
  store.kept[slot] = group.id
  table.insert(group.order, GapIndex(group, anchorSlot), slot)
  return {}
end

-- Pin an item that is NOT in the general list (external cursor, typed bag): claim the lowest free
-- general slot. Returns { KondoBags_PinOp } (one Pickup into that slot) or nil when the bag is full.
function Sections.PinFromOutside(store, group, anchorSlot, slotCount, isFree)
  local h = Sections.LowestFree(store, slotCount, isFree)
  if h == nil then return nil end
  store.kept[h] = group.id
  table.insert(group.order, GapIndex(group, anchorSlot), h)
  return { { place = true, slotIndex = h } }, h
end

-- Unpin: the kept `slot` leaves Keep. ZERO moves. (The player's drag onto an incoming cell is
-- Blizzard's own swap/place; this is the bookkeeping that follows, or a direct unpin gesture.)
function Sections.Unpin(store, slot)
  if not store.kept[slot] then return false end
  store.kept[slot] = nil
  RemoveSlotFromOrders(store, slot)
  return true
end

-- Move a kept `slot` into the cursor gap of `group` anchored to `anchorSlot`. Visual only; across groups.
function Sections.MoveToGap(store, group, slot, anchorSlot)
  if slot == anchorSlot or not store.kept[slot] then return false end
  RemoveSlotFromOrders(store, slot)
  store.kept[slot] = group.id
  table.insert(group.order, GapIndex(group, anchorSlot), slot)
  return true
end

-- Move a kept `slot` to the visual position `otherSlot` occupies (no-Shift drop onto a kept item).
function Sections.MoveToPositionOf(store, slot, otherSlot)
  if slot == otherSlot then return false end
  local target = Sections.GroupOfSlot(store, otherSlot)
  if not target or not store.kept[slot] then return false end
  RemoveSlotFromOrders(store, slot)
  store.kept[slot] = target.id
  table.insert(target.order, IndexInOrder(target, otherSlot), slot)
  return true
end

-- Remove a group: its slots go back to incoming. ZERO moves. Returns true, or false when the group
-- is unknown or is the last one (there must always be at least one).
function Sections.Dissolve(store, sectionID)
  local g, i = Sections.Find(store, sectionID)
  if not g or #store.list < 2 then return false end
  for _, slot in ipairs(g.order) do store.kept[slot] = nil end
  table.remove(store.list, i)
  return true
end

-- ---------------------------------------------------------------------------
-- partition for the layout
-- ---------------------------------------------------------------------------

-- `slots` is { KondoBags_SlotRef... } indexed 1..N (slot index = i-1). Incoming comes out in VISUAL
-- reading order: free slots ascending physical (lowest free = first = top-left), then occupied
-- non-kept slots DESCENDING physical (slot 0 is the bottom-right anchor, like stock). Then every group.
-- `typedSlots` (optional) form ONE run drawn above incoming.
function Sections.Partition(store, slots, columns, typedSlots)
  local free, occupied = {}, {}
  for i = 1, #slots do
    local ref = slots[i]
    local s = i - 1
    if not store.kept[s] then
      if ref.item == nil then free[#free + 1] = ref else occupied[#occupied + 1] = ref end
    end
  end
  local loose = {}
  for _, ref in ipairs(free) do loose[#loose + 1] = ref end                -- ascending physical
  for i = #occupied, 1, -1 do loose[#loose + 1] = occupied[i] end          -- descending physical
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

-- Validate/repair a saved store against the current bag. Enforces: every kept slot in range and
-- OCCUPIED (an emptied kept slot leaves Keep -- D13.1); every kept slot named by exactly one group,
-- in `order` exactly once; >= 1 group. Stores from before D15 (a `boundary`, per-item sets) are replaced.
function Sections.Reconcile(store, slotCount, slots)
  if type(store) ~= "table" or type(store.list) ~= "table" or type(store.kept) ~= "table" then
    return Sections.NewStore()
  end
  local function occupied(slot) return not slots or (slots[slot + 1] ~= nil and slots[slot + 1].item ~= nil) end
  if #store.list == 0 then Sections.Create(store, Sections.DEFAULT_KEEP_NAME) end
  -- drop kept entries that are out of range, empty, or name a group that no longer exists
  for slot, gid in pairs(store.kept) do
    if type(slot) ~= "number" or slot < 0 or slot >= slotCount or not occupied(slot) or not Sections.Find(store, gid) then
      store.kept[slot] = nil
    end
  end
  -- every group's order = its kept slots, each exactly once, in the existing order where possible
  local seen = {}
  for _, g in ipairs(store.list) do
    local order = {}
    for _, slot in ipairs(g.order or {}) do
      if store.kept[slot] == g.id and not seen[slot] then order[#order + 1] = slot; seen[slot] = true end
    end
    g.order = order
  end
  for slot, gid in pairs(store.kept) do
    if not seen[slot] then local g = Sections.Find(store, gid); g.order[#g.order + 1] = slot; seen[slot] = true end
  end
  return store
end

return Sections