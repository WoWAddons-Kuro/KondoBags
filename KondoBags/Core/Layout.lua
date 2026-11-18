-- KondoBags Core/Layout.lua -- pure Lua. Turns a partitioned bag (loose + sections) into grid cells.
--
-- No WoW API. Runs under stock Lua 5.1 (spec/run.lua) and in game alike. The VIEW (UI/Window.lua)
-- consumes KondoBags_LayoutResult and nothing else from the model.
--
-- Input  (from Sections.Partition):
--   KondoBags_LayoutInput = {
--     columns  = number,
--     loose    = { KondoBags_SlotRef... },                                            -- incoming, bag order
--     sections = { { id = KondoBags_SectionID, name, slots = { KondoBags_SlotRef... } }... },  -- display order
--     insertAt = KondoBags_InsertPoint | nil,   -- Shift-drag: where a phantom insert cell opens (see Build)
--   }
--   KondoBags_InsertPoint = { sectionID = KondoBags_SectionID, beforeRef = KondoBags_SlotRef | nil }  -- nil = at end
--   KondoBags_SlotRef = { bagID, slot, item = KondoBags_ItemView | nil }   -- item nil = empty slot
--
-- Output:
--   KondoBags_LayoutResult = { rows = { KondoBags_LayoutRow... }, cellCount = number }
--   KondoBags_LayoutRow    = { cells = { KondoBags_LayoutCell... }, sectionID = KondoBags_SectionID | nil }
--   KondoBags_LayoutCell   = { kind = KondoBags_CellKind, col = number, ref = KondoBags_SlotRef | nil, sectionID }
--   KondoBags_CellKind     = "slot" | "drop"
--
-- Rules (SPECS/00 "Bag window"):
--   * the unsectioned remainder ("incoming") is drawn first, exactly like the stock bag;
--   * below it, every section in display order: ONE drop cell (lock glyph) immediately LEFT of its
--     first item, then its items; no headers, dividers or handles;
--   * every run is bottom-anchored like the stock bags: last row full, partial row on TOP and
--     right-aligned, so free space appears top-left. Cells carry `col` (1-based).

local _, ns = ...
ns = ns or {}
local Layout = {}
ns.Layout = Layout

Layout.CELL_SLOT, Layout.CELL_DROP, Layout.CELL_INSERT = "slot", "drop", "insert"   -- insert: Shift-drag phantom target
Layout.MIN_COLUMNS = 2

local function LayoutRun(cells, columns, sectionID)
  local rows = {}
  local n = #cells
  if n == 0 then return rows end
  local firstRowCount = n % columns
  if firstRowCount == 0 then firstRowCount = columns end
  local startCol = columns - firstRowCount + 1
  local row, col
  for _, cell in ipairs(cells) do
    if not row or col > columns then
      row = { cells = {}, sectionID = sectionID }
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
function Layout.Build(input)
  local columns = math.max(Layout.MIN_COLUMNS, input.columns or 10)
  local out = { rows = {}, cellCount = 0 }
  local function Append(rows)
    for _, r in ipairs(rows) do
      out.rows[#out.rows + 1] = r
      out.cellCount = out.cellCount + #r.cells
    end
  end

  local incoming = {}
  for _, ref in ipairs(input.loose or {}) do
    incoming[#incoming + 1] = { kind = Layout.CELL_SLOT, ref = ref }
  end
  Append(LayoutRun(incoming, columns, nil))

  for _, section in ipairs(input.sections or {}) do
    local cells = { { kind = Layout.CELL_DROP, sectionID = section.id } }
    -- Shift-drag insert mode: open a phantom "insert" cell at input.insertAt so the player can see
    -- exactly where the held item will land. beforeRef nil = at the end of the section.
    local ins = input.insertAt
    local insHere = ins and ins.sectionID == section.id
    local placed = false
    for _, ref in ipairs(section.slots or {}) do
      if insHere and not placed and ins.beforeRef == ref then
        cells[#cells + 1] = { kind = Layout.CELL_INSERT, sectionID = section.id, beforeRef = ref }
        placed = true
      end
      cells[#cells + 1] = { kind = Layout.CELL_SLOT, ref = ref, sectionID = section.id }
    end
    if insHere and not placed then
      cells[#cells + 1] = { kind = Layout.CELL_INSERT, sectionID = section.id, beforeRef = nil }
    end
    Append(LayoutRun(cells, columns, section.id))
  end

  return out
end

function Layout.RowCount(input, columns)
  return #Layout.Build({ columns = columns, loose = input.loose, sections = input.sections, insertAt = input.insertAt }).rows
end

return Layout