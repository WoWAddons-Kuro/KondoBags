-- KondoBags Core/Sections.lua -- pure Lua. The section MODEL: which items the player has pinned where.
--
-- No WoW API. Runs under stock Lua 5.1 (spec/run.lua) and in game alike.
--
--   KondoBags_SectionStore = {            -- persisted per character (KondoBagsCharDB.sections)
--     nextID = number,
--     list   = { KondoBags_Section... },  -- display order
--   }
--   KondoBags_Section   = { id = KondoBags_SectionID, name = string, items = { [itemID] = true } }
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
  local keep = Sections.Create(store, nil, Sections.DEFAULT_KEEP_NAME)
  keep.items[Sections.HEARTHSTONE_ID] = true
  return store
end

function Sections.Create(store, itemID, name)
  local id = "s" .. store.nextID
  store.nextID = store.nextID + 1
  local section = { id = id, name = name or "", items = {} }
  if itemID then section.items[itemID] = true end
  store.list[#store.list + 1] = section
  return section
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
    if s ~= target then s.items[itemID] = nil end
  end
  if target.items[itemID] then return false end
  target.items[itemID] = true
  return true
end

function Sections.Unpin(store, itemID)
  local changed = false
  for _, s in ipairs(store.list) do
    if s.items[itemID] then s.items[itemID] = nil; changed = true end
  end
  return changed
end

function Sections.SectionOf(store, itemID)
  for _, s in ipairs(store.list) do
    if s.items[itemID] then return s end
  end
  return nil
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
function Sections.Partition(store, slots, columns)
  local byID, sections = {}, {}
  for _, s in ipairs(store.list) do
    local sec = { id = s.id, name = s.name, slots = {} }
    sections[#sections + 1] = sec
    byID[s.id] = sec
  end
  local loose = {}
  for _, ref in ipairs(slots) do
    local owner = ref.item and Sections.SectionOf(store, ref.item.itemID)
    if owner then
      local sec = byID[owner.id]
      sec.slots[#sec.slots + 1] = ref
    else
      loose[#loose + 1] = ref
    end
  end
  return { columns = columns, loose = loose, sections = sections }
end

return Sections