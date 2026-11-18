-- KondoBags Core/Sections.lua -- pure Lua. The section MODEL: which items the player has pinned where.
--
-- No WoW API. Runs under stock Lua 5.1 (spec/run.lua) and in game alike.
--
--   KondoBags_SectionStore = {            -- persisted per character (KondoBagsCharDB.sections)
--     nextID = number,
--     list   = { KondoBags_Section... },  -- display order
--   }
--   KondoBags_Section   = { id = KondoBags_SectionID, name = string,
--                           items = { [itemID] = true }, order = { itemID... } }   -- order = display order from the lock, newest FIRST
--   KondoBags_SectionID = string, "s<n>", never reused
--
-- A new character starts with one section, "Keep", holding Hearthstone (SPECS/00). Users can add
-- more; the UI for that is not in M0.

local _, ns = ...
ns = ns or {}
local Sections = {}
ns.Sections = Sections

Sections.HEARTHSTONE_ID = 6948
Sections.DEFAULT_KEEP_NAME = "Keep"

function Sections.NewStore()
  local store = { nextID = 1, list = {} }
  Sections.Create(store, Sections.HEARTHSTONE_ID, Sections.DEFAULT_KEEP_NAME)
  return store
end

function Sections.Create(store, itemID, name)
  local id = "s" .. store.nextID
  store.nextID = store.nextID + 1
  local section = { id = id, name = name or "", items = {}, order = {} }
  if itemID then section.items[itemID] = true; section.order[1] = itemID end
  store.list[#store.list + 1] = section
  return section
end

local function RemoveFromOrder(section, itemID)
  for i, id in ipairs(section.order) do
    if id == itemID then table.remove(section.order, i); return end
  end
end

-- Saved stores from before `order` existed: rebuild it from membership (arbitrary but stable).
local function EnsureOrder(section)
  if section.order then return end
  section.order = {}
  for id in pairs(section.items) do section.order[#section.order + 1] = id end
  table.sort(section.order)
end

function Sections.Find(store, sectionID)
  for i, s in ipairs(store.list) do
    if s.id == sectionID then return s, i end
  end
  return nil
end

-- Pin itemID into sectionID, removing it from any other section first. Returns true if changed.
function Sections.Pin(store, sectionID, itemID)
  local target = Sections.Find(store, sectionID)
  if not target or not itemID then return false end
  for _, s in ipairs(store.list) do
    EnsureOrder(s)
    if s ~= target and s.items[itemID] then s.items[itemID] = nil; RemoveFromOrder(s, itemID) end
  end
  if target.items[itemID] then return false end
  target.items[itemID] = true
  -- Newest FIRST: the run reads left-to-right from the lock cell, so the item you just dropped
  -- appears right where you dropped it, next to the lock; older pins shift right.
  table.insert(target.order, 1, itemID)
  return true
end

function Sections.Unpin(store, itemID)
  local changed = false
  for _, s in ipairs(store.list) do
    EnsureOrder(s)
    if s.items[itemID] then s.items[itemID] = nil; RemoveFromOrder(s, itemID); changed = true end
  end
  return changed
end

function Sections.SectionOf(store, itemID)
  for _, s in ipairs(store.list) do
    if s.items[itemID] then return s end
  end
  return nil
end

-- Move `itemID` to the display position of `otherItemID` inside their shared section (the other
-- item and everything after shift right). Returns true if changed; no-op across sections.
function Sections.MoveBefore(store, itemID, otherItemID)
  local s = Sections.SectionOf(store, itemID)
  if not s or itemID == otherItemID or not s.items[otherItemID] then return false end
  EnsureOrder(s)
  RemoveFromOrder(s, itemID)
  for i, id in ipairs(s.order) do
    if id == otherItemID then table.insert(s.order, i, itemID); return true end
  end
  s.order[#s.order + 1] = itemID   -- unreachable when membership and order agree; keep them consistent
  return true
end

-- Move `itemID` to the end of its section's display order. Returns true if changed.
function Sections.MoveToEnd(store, itemID)
  local s = Sections.SectionOf(store, itemID)
  if not s then return false end
  EnsureOrder(s)
  if s.order[#s.order] == itemID then return false end
  RemoveFromOrder(s, itemID)
  s.order[#s.order + 1] = itemID
  return true
end

function Sections.ItemCount(section)
  local n = 0
  for _ in pairs(section.items) do n = n + 1 end
  return n
end

function Sections.Reorder(store, sectionID, newIndex)
  local s, i = Sections.Find(store, sectionID)
  if not s then return false end
  newIndex = math.max(1, math.min(#store.list, newIndex))
  if newIndex == i then return false end
  table.remove(store.list, i)
  table.insert(store.list, newIndex, s)
  return true
end

function Sections.Dissolve(store, sectionID)
  local _, i = Sections.Find(store, sectionID)
  if not i then return false end
  table.remove(store.list, i)
  return true
end

-- Split a flat slot list (bag order) into a KondoBags_LayoutInput (see Core/Layout.lua).
-- Section slots come out in section.order (newest FIRST), so a just-dropped item sits immediately right of the
-- lock cell; several stacks of the same itemID keep bag order among themselves.
function Sections.Partition(store, slots, columns)
  local byID, sections, pending = {}, {}, {}
  for _, s in ipairs(store.list) do
    EnsureOrder(s)
    local sec = { id = s.id, name = s.name, slots = {} }
    sections[#sections + 1] = sec
    byID[s.id] = sec
    pending[s.id] = {}          -- itemID -> { refs in bag order }
  end
  local loose = {}
  for _, ref in ipairs(slots) do
    local owner = ref.item and Sections.SectionOf(store, ref.item.itemID)
    if owner then
      local bucket = pending[owner.id]
      bucket[ref.item.itemID] = bucket[ref.item.itemID] or {}
      table.insert(bucket[ref.item.itemID], ref)
    else
      loose[#loose + 1] = ref
    end
  end
  for _, s in ipairs(store.list) do
    local sec, bucket = byID[s.id], pending[s.id]
    for _, itemID in ipairs(s.order) do
      for _, ref in ipairs(bucket[itemID] or {}) do sec.slots[#sec.slots + 1] = ref end
    end
  end
  return { columns = columns, loose = loose, sections = sections }
end

return Sections