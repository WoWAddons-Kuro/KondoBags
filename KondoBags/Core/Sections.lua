-- KondoBags Core/Sections.lua -- pure Lua. The section MODEL: sections as PHYSICAL slot ranges (SPECS/00 D11).
--
-- No WoW API. Runs under stock Lua 5.1 (spec/run.lua) and in game alike.
--
-- The bag is a flat list of KondoBags_SlotIndex 0..N-1 in Blizzard's combined order. Sections cut it
-- into contiguous ranges, bottom-up from the TOP slot:
--
--   incoming  = slots 0 .. list[1].boundary-1          (Blizzard's loot order; never reordered by us)
--   list[1]   = slots list[1].boundary .. list[2].boundary-1
--   list[k]   = slots list[k].boundary .. N-1            (last section runs to the end)
--
-- Every section slot is always OCCUPIED (a section is exactly as big as its item count), so loot
-- never lands in one and a section's physical slot order is free. Its VISUAL order is `order`, a
-- list of its slot indices. Membership is BY SLOT, not by item: moving an item into the range pins it.
--
--   KondoBags_SectionStore = { nextID = number, list = { KondoBags_Section... } }   -- persisted per character
--   KondoBags_Section      = { id = KondoBags_SectionID, name = string,
--                              boundary = KondoBags_SlotIndex,        -- lowest slot this section owns
--                              order = { KondoBags_SlotIndex... } }  -- visual order, left to right from the lock
--   KondoBags_SectionID    = string, "s<n>", never reused
--   KondoBags_SlotIndex    = number, 0-based position in the flat combined bag
--
-- Edits are expressed as KondoBags_SlotMove = { from = KondoBags_SlotIndex, to = KondoBags_SlotIndex }
-- (a swap of the two slots' contents). The controller applies them to the mock or, in M4, issues
-- C_Container.PickupContainerItem pairs.

local _, ns = ...
ns = ns or {}
local Sections = {}
ns.Sections = Sections

Sections.HEARTHSTONE_ID = 6948
Sections.DEFAULT_KEEP_NAME = "Keep"

-- ---------------------------------------------------------------------------
-- store
-- ---------------------------------------------------------------------------

-- A fresh store with one empty "Keep" section at the very top of a bag of `slotCount` slots.
-- The owner pins Hearthstone into it on first run (needs the slot list, so not done here).
function Sections.NewStore(slotCount)
  local store = { nextID = 1, list = {} }
  Sections.Create(store, slotCount, Sections.DEFAULT_KEEP_NAME)
  return store
end

-- Create an EMPTY section whose range starts at `boundary` (= slotCount for a section at the end).
function Sections.Create(store, boundary, name)
  local id = "s" .. store.nextID
  store.nextID = store.nextID + 1
  local section = { id = id, name = name or "", boundary = boundary, order = {} }
  store.list[#store.list + 1] = section
  return section
end

function Sections.Find(store, sectionID)
  for i, s in ipairs(store.list) do
    if s.id == sectionID then return s, i end
  end
  return nil
end

-- The section owning `slot`, or nil if it is incoming.
function Sections.SectionOfSlot(store, slot)
  local owner
  for _, s in ipairs(store.list) do
    if slot >= s.boundary then owner = s end   -- list is bottom-up, so the last match wins
  end
  return owner
end

-- Incoming is everything below the first section (or all of it when there are no sections).
function Sections.IncomingEnd(store, slotCount)
  local first = store.list[1]
  return first and first.boundary or slotCount
end

function Sections.ItemCount(section) return #section.order end

local function IndexInOrder(section, slot)
  for i, s in ipairs(section.order) do if s == slot then return i end end
  return nil
end

-- After a swap of two slots, any `order` entry naming one of them must name the other.
local function RenameSlotInOrders(store, a, b)
  for _, s in ipairs(store.list) do
    for i, slot in ipairs(s.order) do
      if slot == a then s.order[i] = b elseif slot == b then s.order[i] = a end
    end
  end
end

-- ---------------------------------------------------------------------------
-- gestures -> moves  (each returns { KondoBags_SlotMove... } already applied to the store's
-- bookkeeping; the caller applies the same moves to the slot contents)
-- ---------------------------------------------------------------------------

-- Grow `section` by one slot at its bottom and put the item from `fromSlot` (incoming) there.
-- Visual: the new item goes FIRST in `order` (right of the lock), or before `beforeSlot` if given.
-- The section takes slot boundary-1; if the item is not already there, one swap brings it.
-- (Any section BELOW this one would have to shrink -- only the lowest section can grow in M0.)
function Sections.PinFromIncoming(store, section, fromSlot, beforeSlot)
  local moves = {}
  local target = section.boundary - 1
  if fromSlot ~= target then
    moves[#moves + 1] = { from = fromSlot, to = target }
    RenameSlotInOrders(store, fromSlot, target)   -- no section names either slot today, but keep it honest
  end
  section.boundary = target
  local at = beforeSlot and IndexInOrder(section, beforeSlot) or 1
  table.insert(section.order, at, target)
  return moves
end

-- Shrink `section` by one: the item at `slot` (inside the section) leaves to incoming slot `toSlot`.
--   toSlot occupied -> plain swap; the displaced item is now in the section, takes `slot`'s place in order.
--   toSlot empty    -> move; the hole left at `slot` is filled from the section's LOWEST slot
--                      (boundary), which is then released to incoming. At most two moves, no cascade.
function Sections.UnpinToIncoming(section, slot, toSlot, toSlotOccupied)
  local moves = { { from = slot, to = toSlot } }
  if toSlotOccupied then
    -- membership is by slot: whatever came back into `slot` is now kept, same visual position
    return moves
  end
  local idx = IndexInOrder(section, slot)
  if idx then table.remove(section.order, idx) end
  local low = section.boundary
  if slot ~= low then
    moves[#moves + 1] = { from = low, to = slot }   -- the lowest-slot item slides into the hole
    local lowIdx = IndexInOrder(section, low)
    if lowIdx then section.order[lowIdx] = slot end
  end
  section.boundary = low + 1                        -- slot `low` is incoming again (and empty)
  return moves
end

-- Reorder inside a section: `slot` takes the visual position of `otherSlot`. No physical move.
function Sections.MoveBefore(section, slot, otherSlot)
  if slot == otherSlot then return false end
  local i, j = IndexInOrder(section, slot), IndexInOrder(section, otherSlot)
  if not i or not j then return false end
  table.remove(section.order, i)
  j = IndexInOrder(section, otherSlot)
  table.insert(section.order, j, slot)
  return true
end

function Sections.MoveToEnd(section, slot)
  local i = IndexInOrder(section, slot)
  if not i or i == #section.order then return false end
  table.remove(section.order, i)
  section.order[#section.order + 1] = slot
  return true
end

-- Two slots in the same section swapped physically (e.g. a stock drag): keep `order` pointing at the items.
function Sections.NoteSwapWithin(store, a, b)
  RenameSlotInOrders(store, a, b)
end

-- ---------------------------------------------------------------------------
-- partition for the layout
-- ---------------------------------------------------------------------------

-- `slots` is { KondoBags_SlotRef... } indexed 1..N in combined order (slot index = i-1).
-- Incoming comes out HIGHEST slot first so that slot 0 is the bottom-right anchor and new loot
-- (lowest free slot) opens a new cell at the top-left without moving anything else.
function Sections.Partition(store, slots, columns)
  local n = #slots
  local incomingEnd = Sections.IncomingEnd(store, n)
  local loose = {}
  for i = incomingEnd, 1, -1 do loose[#loose + 1] = slots[i] end   -- slot incomingEnd-1 .. 0
  local sections = {}
  for _, s in ipairs(store.list) do
    local sec = { id = s.id, name = s.name, slots = {} }
    for _, slot in ipairs(s.order) do
      local ref = slots[slot + 1]
      if ref then sec.slots[#sec.slots + 1] = ref end
    end
    sections[#sections + 1] = sec
  end
  return { columns = columns, loose = loose, sections = sections }
end

-- Validate/repair a saved store against the current slot count (bag resized, old format, etc.).
-- Returns the store (possibly replaced). A section whose order does not match its range is rebuilt.
function Sections.Reconcile(store, slotCount, slots)
  if type(store) ~= "table" or type(store.list) ~= "table" then return Sections.NewStore(slotCount) end
  -- D11 invariant: every section slot is OCCUPIED. With `slots` we enforce it: a saved range that
  -- reaches down into empty slots is cut back to its occupied top, so stale stores never draw empty
  -- cells inside a section. Without `slots` (tests of pure bookkeeping) ranges are trusted.
  local function occupied(slot) return not slots or (slots[slot + 1] ~= nil and slots[slot + 1].item ~= nil) end
  local top = slotCount
  for i = #store.list, 1, -1 do
    local s = store.list[i]
    if type(s.boundary) ~= "number" or s.boundary > top or s.boundary < 0 then
      -- legacy (itemID-based) or out-of-range: collapse to empty at the top
      s.boundary, s.order = top, {}
    end
    local low = top
    while low > s.boundary and occupied(low - 1) do low = low - 1 end
    s.boundary = low
    local want = top - s.boundary
    -- keep the saved visual order where it still names slots in range; append any missing
    local seen, order = {}, {}
    for _, slot in ipairs(s.order or {}) do
      if slot >= s.boundary and slot < top and not seen[slot] then order[#order + 1] = slot; seen[slot] = true end
    end
    for slot = s.boundary, top - 1 do if not seen[slot] then order[#order + 1] = slot end end
    s.order = order
    assert(#s.order == want)
    top = s.boundary
  end
  return store
end

return Sections