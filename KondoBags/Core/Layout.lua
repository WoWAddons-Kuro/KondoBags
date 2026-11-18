-- KondoBags Core/Layout.lua -- pure Lua. Turns a partitioned bag (loose + sections) into grid cells.
--
-- No WoW API. Runs under stock Lua 5.1 (spec/run.lua) and in game alike. The VIEW (UI/Window.lua)
-- consumes KondoBags_LayoutResult and nothing else from the model.
--
-- Input  (from Sections.Partition):
--   KondoBags_LayoutInput = {
--     columns  = number,
--     typed    = { KondoBags_SlotRef... },                                            -- restricted-bag slots, ONE run above incoming
--     loose    = { KondoBags_SlotRef... },                                            -- incoming, bag order
--     sections = { { id = KondoBags_SectionID, name, slots = { KondoBags_SlotRef... } }... },  -- display order
--     cursorGap = KondoBags_CursorGap | nil,   -- Shift-drag: the phantom cell that opens under the mouse
--   }
--   KondoBags_SlotKind = "general" | "quiver" | "ammo" | "soul" | "herb" | "enchanting" | "mining" | "keyring" | "reagent"
--   KondoBags_CursorGap = { sectionID = KondoBags_SectionID, anchorRef = KondoBags_SlotRef | nil }
--     anchorRef = the kept item the gap is attached to; nil = attached to the lock cell.
--     RENDER RULE: the gap is drawn in the column the ANCHOR occupied and the anchor slides one cell
--     LEFT (toward the lock). Rows are right-aligned, so this is the only placement that puts the gap
--     exactly under a mouse that was hovering the anchor: the lock and everything up to and including
--     the anchor shift left; everything right of the anchor stays put. anchorRef nil = the gap is the
--     first cell after the lock.
--   KondoBags_SlotRef = { bagID, slot, item = KondoBags_ItemView | nil }   -- item nil = empty slot
--
-- Output:
--   KondoBags_LayoutResult = { rows = { KondoBags_LayoutRow... }, cellCount = number }
--   KondoBags_LayoutRow    = { cells = { KondoBags_LayoutCell... }, sectionID = KondoBags_SectionID | nil }
--   KondoBags_LayoutCell   = { kind = KondoBags_CellKind, col = number, ref = KondoBags_SlotRef | nil, sectionID,
--                              anchorRef = KondoBags_SlotRef | nil }     -- gap cells only
--   KondoBags_CellKind     = "slot" | "drop" | "gap"
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

Layout.CELL_SLOT, Layout.CELL_DROP, Layout.CELL_GAP = "slot", "drop", "gap"   -- gap: the Shift-drag phantom under the mouse
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

  -- Restricted-bag slots: ONE run above incoming, every cell carrying its slot kind for the glyph/tint.
  local typed = {}
  for _, ref in ipairs(input.typed or {}) do
    typed[#typed + 1] = { kind = Layout.CELL_SLOT, ref = ref, slotKind = ref.kind, typed = true }
  end
  local typedRows = LayoutRun(typed, columns, nil)
  for _, r in ipairs(typedRows) do r.typed = true end
  Append(typedRows)

  local incoming = {}
  for _, ref in ipairs(input.loose or {}) do
    incoming[#incoming + 1] = { kind = Layout.CELL_SLOT, ref = ref }
  end
  Append(LayoutRun(incoming, columns, nil))

  for _, section in ipairs(input.sections or {}) do
    -- hideLocks (D14): an EXTERNAL cursor item with no free general slot has nowhere to land, so the
    -- lock (and gap) cells are not emitted at all; the group's items still draw.
    local cells = {}
    -- SLIM LOCK (owner, 2026-11-18): when a group's items fill whole rows exactly, the lock alone would
    -- spill onto a row of its own. Instead the lock is emitted `slim` at col 0 -- a half-width cell in
    -- a gutter LEFT of the grid, on the group's TOP row -- so the grid itself never changes. The view
    -- widens the window by that gutter only while some row carries a slim lock (KondoBags_LayoutResult.slimGutter).
    local lock
    if not input.hideLocks then lock = { kind = Layout.CELL_DROP, sectionID = section.id }; cells[1] = lock end
    -- Shift-drag: the cursor gap. See KondoBags_CursorGap RENDER RULE above: the gap takes the
    -- anchor's column and the anchor slides left, which in reading order means the gap cell is
    -- emitted immediately AFTER the anchor (or right after the lock when anchorRef is nil).
    local gap = input.cursorGap
    local gapHere = gap and gap.sectionID == section.id and not input.hideLocks
    if gapHere and gap.anchorRef == nil then
      cells[#cells + 1] = { kind = Layout.CELL_GAP, sectionID = section.id, anchorRef = nil }
    end
    for _, ref in ipairs(section.slots or {}) do
      cells[#cells + 1] = { kind = Layout.CELL_SLOT, ref = ref, sectionID = section.id }
      if gapHere and gap.anchorRef == ref then
        cells[#cells + 1] = { kind = Layout.CELL_GAP, sectionID = section.id, anchorRef = ref }
      end
    end
    local rest = #cells - (lock and 1 or 0)
    if lock and rest > 0 and rest % columns == 0 then
      table.remove(cells, 1)                               -- lay out items (+ gap) alone: they fill whole rows
      local rows = LayoutRun(cells, columns, section.id)
      lock.col, lock.slim = 0, true
      table.insert(rows[1].cells, 1, lock)                 -- gutter cell on the group's top row
      rows[1].slimLock = true
      out.slimGutter = true
      Append(rows)
    else
      Append(LayoutRun(cells, columns, section.id))
    end
  end

  return out
end

function Layout.RowCount(input, columns)
  return #Layout.Build({ columns = columns, loose = input.loose, sections = input.sections, cursorGap = input.cursorGap }).rows
end

return Layout
