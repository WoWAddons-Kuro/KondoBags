-- KondoBags Core/Sections.lua -- pure Lua. Turns sections + loose slots into a grid of cells.
--
-- No WoW API here. Runs under stock Lua 5.1 (spec/run.lua) and in game alike.
--
-- Input:
--   KondoBags_LayoutInput = {
--     columns  = number,                         -- cells per row
--     sections = { KondoBags_Section... },       -- display order; each { id, name, slots = { KondoBags_SlotRef... } }
--     loose    = { KondoBags_SlotRef... },       -- everything not in a section, in bag order
--   }
--   KondoBags_SlotRef = { bagID, slot, item = KondoBags_ItemView | nil }   -- item nil = empty slot
--
-- Output:
--   KondoBags_LayoutResult = { rows = { KondoBags_LayoutRow... }, cellCount = number }
--   KondoBags_LayoutRow    = { cells = { KondoBags_LayoutCell... }, dividerAbove = bool, sectionID = KondoBags_SectionID | nil }
--   KondoBags_LayoutCell   = { kind = KondoBags_CellKind, ref = KondoBags_SlotRef | nil, sectionID = KondoBags_SectionID | nil }
--   KondoBags_CellKind     = "slot" | "handle" | "plus"
--
-- Rules (SPECS/00 "Bag window"):
--   * every section is its own run of cells, items first, then ONE handle cell; a divider line sits
--     above the first row of each section after the first;
--   * the unsectioned remainder starts with ONE plus cell, then its slots; no handle, no name;
--   * cells fill left-to-right; a run never shares a row with another run;
--   * a run is bottom-anchored like the stock bags: its last row is full, the partial row is on TOP,
--     right-aligned (so free space appears at the top-left of each run). Cells carry `col`.
--   * the handle is the last cell of its run, so it always sits bottom-right of the section.
--   * cells fill left-to-right, top-to-bottom; a run never shares a row with another run;
--   * a handle that lands alone on a new row stays there (that is where the next item would go).

local _, ns = ...
ns = ns or {}
local Sections = {}
ns.Sections = Sections

local CELL_SLOT, CELL_HANDLE, CELL_PLUS = "slot", "handle", "plus"
Sections.CELL_SLOT, Sections.CELL_HANDLE, Sections.CELL_PLUS = CELL_SLOT, CELL_HANDLE, CELL_PLUS

-- Lay one run of cells into rows of `columns`. Returns the rows (array) it produced.
local function LayoutRun(cells, columns, sectionID, dividerAbove)
  -- Bottom-anchored like the stock bags: the last row is always full and the partial row (if any)
  -- is the TOP row, right-aligned. Each cell gets `col` (1-based); a row holds only real cells.
  --   7 cells, 4 columns  ->  [ ][c1][c2][c3]
  --                           [c4][c5][c6][c7]
  local rows = {}
  local n = #cells
  if n == 0 then return rows end
  local firstRowCount = n % columns
  if firstRowCount == 0 then firstRowCount = columns end
  local startCol = columns - firstRowCount + 1
  local row
  local col = startCol
  for _, cell in ipairs(cells) do
    if not row or col > columns then
      row = { cells = {}, sectionID = sectionID, dividerAbove = (#rows == 0) and dividerAbove or false }
      rows[#rows + 1] = row
      col = (#rows == 1) and startCol or 1
    end
    cell.col = col
    row.cells[#row.cells + 1] = cell
    col = col + 1
  end
  return rows
end

-- KondoBags_LayoutInput -> KondoBags_LayoutResult
function Sections.Layout(input)
  local columns = math.max(1, input.columns or 10)
  local out = { rows = {}, cellCount = 0 }
  local function Append(rows)
    for _, r in ipairs(rows) do
      out.rows[#out.rows + 1] = r
      out.cellCount = out.cellCount + #r.cells
    end
  end

  local first = true
  for _, section in ipairs(input.sections or {}) do
    local cells = {}
    for _, ref in ipairs(section.slots or {}) do
      cells[#cells + 1] = { kind = CELL_SLOT, ref = ref, sectionID = section.id }
    end
    cells[#cells + 1] = { kind = CELL_HANDLE, sectionID = section.id }
    Append(LayoutRun(cells, columns, section.id, not first))
    first = false
  end

  local loose = { { kind = CELL_PLUS } }
  for _, ref in ipairs(input.loose or {}) do
    loose[#loose + 1] = { kind = CELL_SLOT, ref = ref }
  end
  Append(LayoutRun(loose, columns, nil, not first))

  return out
end

-- Minimum columns so that the widest single run (any section's items + handle, or plus + loose)
-- is not forced to wrap more than the total slot count would anyway. We simply require >= 2 so
-- a section can show one item and its handle on one row; the caller clamps to its own range.
function Sections.MinColumns()
  return 2
end

-- Rows needed for a given input at `columns` (used by the resize snap to report height).
function Sections.RowCount(input, columns)
  local copy = { columns = columns, sections = input.sections, loose = input.loose }
  return #Sections.Layout(copy).rows
end

-- ---------------------------------------------------------------------------
-- Section bookkeeping over a plain KondoBags_SectionStore (what we persist per character):
--   KondoBags_SectionStore = { nextID = number, list = { { id, name, items = { [itemID] = true } }... } }
-- ---------------------------------------------------------------------------

function Sections.NewStore()
  return { nextID = 1, list = {} }
end

-- Create a section containing itemID. Returns the new section.
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

-- Remove itemID from every section. Returns true if it was in one.
function Sections.Unpin(store, itemID)
  local changed = false
  for _, s in ipairs(store.list) do
    if s.items[itemID] then s.items[itemID] = nil; changed = true end
  end
  return changed
end

-- Which section (if any) holds itemID.
function Sections.SectionOf(store, itemID)
  for _, s in ipairs(store.list) do
    if s.items[itemID] then return s end
  end
  return nil
end

-- Move sectionID to display index newIndex (1-based, clamped). Returns true if order changed.
function Sections.Reorder(store, sectionID, newIndex)
  local s, i = Sections.Find(store, sectionID)
  if not s then return false end
  newIndex = math.max(1, math.min(#store.list, newIndex))
  if newIndex == i then return false end
  table.remove(store.list, i)
  table.insert(store.list, newIndex, s)
  return true
end

-- Dissolve a section; its items become loose.
function Sections.Dissolve(store, sectionID)
  local _, i = Sections.Find(store, sectionID)
  if not i then return false end
  table.remove(store.list, i)
  return true
end

-- Split a flat slot list into KondoBags_LayoutInput.sections / .loose using the store.
-- `slots` is { KondoBags_SlotRef... } in bag order; a ref with no item is loose.
function Sections.Partition(store, slots, columns)
  local byID = {}
  local sections = {}
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
  return { columns = columns, sections = sections, loose = loose }
end

return Sections