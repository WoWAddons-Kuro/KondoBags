-- KondoBags Core/Sections.lua -- pure Lua. The section MODEL (SPECS/00 D11 + D12).
--
-- No WoW API. Runs under stock Lua 5.1 (spec/run.lua) and in game alike.
--
-- PHYSICALLY there are exactly two ranges in the flat combined bag (slots 0..N-1, Blizzard order):
--   incoming = slots 0 .. boundary-1      Blizzard's loot order; never reordered by us
--   keep     = slots boundary .. N-1      always fully OCCUPIED, so loot never lands here
-- One boundary. Pin = grow keep by taking slot boundary-1 (items above it SHIFT down one; loot order kept). Unpin = the
-- item leaves to an incoming slot; the hole is filled from keep's LOWEST slot, which is released.
--
-- VISUALLY the keep range is drawn as one or more GROUPS, each with its own lock cell. A group is a
-- named list of keep slots in display order; the groups together partition boundary..N-1.
--
--   KondoBags_SectionStore = { nextID = number, boundary = KondoBags_SlotIndex,
--                              list = { KondoBags_Group... } }        -- display order, incoming first
--   KondoBags_Group        = { id = KondoBags_SectionID, name = string,
--                              order = { KondoBags_SlotIndex... } }  -- visual order, left to right from the lock
--   KondoBags_SectionID    = string, "s<n>", never reused
--   KondoBags_SlotIndex    = number, 0-based position in the flat combined bag
--   KondoBags_SlotMove     = { from = KondoBags_SlotIndex, to = KondoBags_SlotIndex }   -- a swap

local _, ns = ...
ns = ns or {}
local Sections = {}
ns.Sections = Sections

Sections.HEARTHSTONE_ID = 6948
Sections.DEFAULT_KEEP_NAME = "Keep"

-- ---------------------------------------------------------------------------
-- store
-- ---------------------------------------------------------------------------

-- A fresh store: empty keep range at the very top, one empty "Keep" group.
function Sections.NewStore(slotCount)
  local store = { nextID = 1, boundary = slotCount, list = {} }
  Sections.Create(store, Sections.DEFAULT_KEEP_NAME)
  return store
end

-- Add an EMPTY group (drawn FIRST, directly under incoming). The + button.
function Sections.Create(store, name)
  local id = "s" .. store.nextID
  store.nextID = store.nextID + 1
  local group = { id = id, name = name or "", order = {} }
  -- New groups are drawn FIRST, directly under incoming; existing groups shift down (owner).
  table.insert(store.list, 1, group)
  return group
end

function Sections.Find(store, sectionID)
  for i, g in ipairs(store.list) do
    if g.id == sectionID then return g, i end
  end
  return nil
end

function Sections.IsKept(store, slot) return slot >= store.boundary end

-- The group whose order names `slot`, or nil (incoming, or a kept slot no group claims yet).
function Sections.GroupOfSlot(store, slot)
  for _, g in ipairs(store.list) do
    for _, s in ipairs(g.order) do if s == slot then return g end end
  end
  return nil
end
-- Back-compat name used by the controller/view.
Sections.SectionOfSlot = function(store, slot)
  if not Sections.IsKept(store, slot) then return nil end
  return Sections.GroupOfSlot(store, slot) or store.list[1]
end

function Sections.IncomingEnd(store) return store.boundary end
function Sections.ItemCount(group) return #group.order end

local function IndexInOrder(group, slot)
  for i, s in ipairs(group.order) do if s == slot then return i end end
  return nil
end

-- After a swap of two slots, any order entry naming one of them must name the other.
local function RenameSlotInOrders(store, a, b)
  for _, g in ipairs(store.list) do
    for i, slot in ipairs(g.order) do
      if slot == a then g.order[i] = b elseif slot == b then g.order[i] = a end
    end
  end
end

local function RemoveSlotFromOrders(store, slot)
  for _, g in ipairs(store.list) do
    local i = IndexInOrder(g, slot)
    if i then table.remove(g.order, i) end
  end
end

-- ---------------------------------------------------------------------------
-- gestures -> moves  (each returns { KondoBags_SlotMove... }; bookkeeping already updated;
-- the caller applies the same moves to the slot contents)
-- ---------------------------------------------------------------------------



-- Where a slot goes in `group.order` to land in the cursor gap anchored to `anchorSlot`:
--   the gap is drawn in the anchor's column and the anchor slides left, so in reading order the new
--   entry sits immediately AFTER the anchor; anchorSlot nil = the gap is right after the lock = first.
local function GapIndex(group, anchorSlot)
  local i = anchorSlot and IndexInOrder(group, anchorSlot)
  return i and (i + 1) or 1
end

-- Pin the item at incoming `fromSlot` into `group`, landing in the cursor gap anchored to
-- `anchorSlot` (nil = right after the lock). Keep grows by taking slot boundary-1; one swap brings
-- the item there unless it is there already.
function Sections.PinFromIncoming(store, group, fromSlot, anchorSlot)
  -- Pin the item at incoming `fromSlot` into `group`, landing in the cursor gap anchored to
  -- `anchorSlot` (nil = right after the lock). Keep grows by taking slot boundary-1. The item is
  -- carried there by a SHIFT, not a swap: every incoming item above it steps down one slot
  -- (fromSlot+1 -> fromSlot, ..., boundary-1 -> boundary-2), so incoming stays contiguous and in
  -- Blizzard's loot order (owner, 2026-11-18; a swap would drop the displaced item mid-incoming).
  -- Expressed as a chain of adjacent swaps, each carrying the pinned item one slot up.
  local moves = {}
  local target = store.boundary - 1
  for s = fromSlot, target - 1 do
    moves[#moves + 1] = { from = s, to = s + 1 }
  end
  -- No order entries name incoming slots, so nothing to rename for the shift itself.
  store.boundary = target
  table.insert(group.order, GapIndex(group, anchorSlot), target)
  return moves
end

-- Unpin: the kept item at `slot` leaves to incoming slot `toSlot`.
--   toSlot occupied -> plain swap; the displaced item is now kept in `slot`, same visual spot.
--   toSlot empty    -> move; the hole at `slot` is filled from keep's LOWEST slot (boundary), which
--                      is then released to incoming. The slid item keeps its group (rename).
function Sections.UnpinToIncoming(store, slot, toSlot, toSlotOccupied)
  local moves = { { from = slot, to = toSlot } }
  if toSlotOccupied then return moves end
  RemoveSlotFromOrders(store, slot)
  local low = store.boundary
  if slot ~= low then
    moves[#moves + 1] = { from = low, to = slot }
    RenameSlotInOrders(store, low, slot)     -- whichever group held `low` now holds `slot`
  end
  store.boundary = low + 1
  return moves
end


-- Move a kept `slot` into the cursor gap of `group` anchored to `anchorSlot` (nil = right after the
-- lock). Works across groups. Visual only.
function Sections.MoveToGap(store, group, slot, anchorSlot)
  if slot == anchorSlot then return false end
  RemoveSlotFromOrders(store, slot)
  table.insert(group.order, GapIndex(group, anchorSlot), slot)
  return true
end

-- Move a kept `slot` to the visual position `otherSlot` occupies (no-Shift drop onto a kept item):
-- `slot` takes that cell; `otherSlot` and everything after it shift right. Works across groups.
function Sections.MoveToPositionOf(store, slot, otherSlot)
  if slot == otherSlot then return false end
  local target = Sections.GroupOfSlot(store, otherSlot)
  if not target then return false end
  RemoveSlotFromOrders(store, slot)
  table.insert(target.order, IndexInOrder(target, otherSlot), slot)
  return true
end

-- (MoveToEnd removed 2026-11-18: superseded by MoveToGap with a nil anchor / last-item anchor.)

function Sections.NoteSwapWithin(store, a, b) RenameSlotInOrders(store, a, b) end


-- Remove a group. Its items drop into INCOMING: each of its slots is swapped down into keep's lowest
-- slot (boundary) and that slot is released, so the released slots are always the lowest ones and
-- Blizzard's loot order is preserved (D11). Returns the moves, or nil if the group is unknown or it
-- is the last group (there must always be at least one).
function Sections.Dissolve(store, sectionID)
  local g, i = Sections.Find(store, sectionID)
  if not g or #store.list < 2 then return nil end
  local moves = {}
  -- copy: RenameSlotInOrders rewrites g.order while we iterate
  local slots = {}
  for k, s in ipairs(g.order) do slots[k] = s end
  for _, slot in ipairs(slots) do
    local low = store.boundary
    if slot ~= low then
      moves[#moves + 1] = { from = slot, to = low }
      RenameSlotInOrders(store, slot, low)      -- the item that was at `low` now lives at `slot`
    end
    store.boundary = low + 1
  end
  table.remove(store.list, i)
  return moves
end

-- ---------------------------------------------------------------------------
-- partition for the layout
-- ---------------------------------------------------------------------------

-- `slots` is { KondoBags_SlotRef... } indexed 1..N (slot index = i-1). Incoming comes out HIGHEST slot
-- first (slot 0 is the bottom-right anchor, new loot opens a cell top-left). Then every group.
function Sections.Partition(store, slots, columns)
  local loose = {}
  for i = store.boundary, 1, -1 do loose[#loose + 1] = slots[i] end
  local sections = {}
  for _, g in ipairs(store.list) do
    local sec = { id = g.id, name = g.name, slots = {} }
    for _, slot in ipairs(g.order) do
      local ref = slots[slot + 1]
      if ref then sec.slots[#sec.slots + 1] = ref end
    end
    sections[#sections + 1] = sec
  end
  return { columns = columns, loose = loose, sections = sections }
end

-- Validate/repair a saved store against the current bag. Enforces: boundary in range; every keep
-- slot OCCUPIED (a range reaching into empty slots is cut back); every keep slot named by exactly one
-- group (stray/duplicate entries dropped, unclaimed slots appended to the first group); >= 1 group.
-- Stores from before D12 (per-section boundary / per-item sets) collapse to an empty keep.
function Sections.Reconcile(store, slotCount, slots)
  if type(store) ~= "table" or type(store.list) ~= "table" or type(store.boundary) ~= "number" then
    return Sections.NewStore(slotCount)
  end
  local function occupied(slot) return not slots or (slots[slot + 1] ~= nil and slots[slot + 1].item ~= nil) end
  local b = math.max(0, math.min(slotCount, store.boundary))
  local low = slotCount
  while low > b and occupied(low - 1) do low = low - 1 end
  store.boundary = low
  if #store.list == 0 then Sections.Create(store, Sections.DEFAULT_KEEP_NAME) end
  local claimed = {}
  for _, g in ipairs(store.list) do
    local order = {}
    for _, slot in ipairs(g.order or {}) do
      if type(slot) == "number" and slot >= store.boundary and slot < slotCount and not claimed[slot] then
        order[#order + 1] = slot; claimed[slot] = true
      end
    end
    g.order = order
  end
  for slot = store.boundary, slotCount - 1 do
    if not claimed[slot] then local g = store.list[1]; g.order[#g.order + 1] = slot end
  end
  return store
end

return Sections