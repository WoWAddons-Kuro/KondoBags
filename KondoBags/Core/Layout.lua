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
--     hideLocks = bool | nil,                  -- D14: external cursor with no free general slot: no lock cells
--   }
--   KondoBags_SlotKind = "general" | "quiver" | "ammo" | "soul" | "herb" | "enchanting" | "mining" | "keyring" | "reagent"
--   KondoBags_SlotRef = { bagID, slot, item = KondoBags_ItemView | nil }   -- item nil = empty slot
--
-- Output:
--   KondoBags_LayoutResult = { rows = { KondoBags_LayoutRow... }, cellCount = number }
--   KondoBags_LayoutRow    = { cells = { KondoBags_LayoutCell... }, sectionID = KondoBags_SectionID | nil }
--   KondoBags_LayoutCell   = { kind = KondoBags_CellKind, col = number, ref = KondoBags_SlotRef | nil, sectionID }
--   KondoBags_CellKind     = "slot" | "drop"
--   Shift-insert never adds cells: see Layout.InsertPointAt at the bottom of this file.
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

Layout.CELL_SLOT, Layout.CELL_DROP = "slot", "drop"
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
    for _, ref in ipairs(section.slots or {}) do
      cells[#cells + 1] = { kind = Layout.CELL_SLOT, ref = ref, sectionID = section.id }
    end
    local rest = #cells - (lock and 1 or 0)
    if lock and rest > 0 and rest % columns == 0 then
      table.remove(cells, 1)                               -- lay out the items alone: they fill whole rows
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
  return #Layout.Build({ columns = columns, loose = input.loose, sections = input.sections }).rows
end

-- ---------------------------------------------------------------------------
-- Shift-insert (SPECS/00 "Shift-insert"): where would a drop at grid point (x, y) go?
-- ---------------------------------------------------------------------------
--   Layout.InsertPointAt(layout, metrics, x, y) -> KondoBags_InsertPoint | nil
--     layout  = KondoBags_LayoutResult (the one currently drawn)
--     metrics = KondoBags_GridMetrics { pitchX, pitchY, cellSize, rowY = { [row] = topY (<= 0, grid coords) } }
--     x, y    = cursor in frame.Grid coordinates: x from the grid's LEFT edge, y from its TOP (y <= 0)
--   KondoBags_InsertPoint = {
--     run       = "section",                      -- Step 1: only section rows answer; others return nil
--     sectionID = KondoBags_SectionID,
--     afterRef  = KondoBags_SlotRef | nil,        -- cell LEFT of the boundary; nil = before the group's first item
--     beforeRef = KondoBags_SlotRef | nil,        -- cell RIGHT of the boundary; nil = after the group's last item
--     markerRow = number, markerX = number,       -- the boundary, for the view's marker (grid coords)
--   }
-- Rule: the ROW under the cursor (nearest row when outside every row band) names the section. Within
-- that row the candidate boundaries are the midpoints between consecutive SLOT cells plus the left
-- edge of the first slot (right after the lock) and the right edge of the last; the one whose x is
-- nearest the cursor wins. Nothing in the grid moves. Pure Lua; the view only draws the marker.
function Layout.InsertPointAt(layout, metrics, x, y)
  if not layout or not metrics or not metrics.rowY then return nil end
  -- 1. the row: y is <= 0 going down; row r spans [rowY[r] - pitchY, rowY[r]]
  local bestRow, bestDist
  for r, top in ipairs(metrics.rowY) do
    local bottom = top - metrics.pitchY
    local d = (y > top) and (y - top) or (y < bottom) and (bottom - y) or 0
    if not bestDist or d < bestDist then bestRow, bestDist = r, d end
  end
  local row = bestRow and layout.rows[bestRow]
  if not row or not row.sectionID then return nil end           -- incoming / typed: Step 2 / inert
  -- 2. slot cells of this row in column order; the lock (col 0 when slim) is not a candidate neighbour
  local slots = {}
  for _, c in ipairs(row.cells) do
    if c.kind == Layout.CELL_SLOT and c.ref then slots[#slots + 1] = c end
  end
  local function cellLeft(c) return (c.col - 1) * metrics.pitchX end
  local function cellRight(c) return cellLeft(c) + metrics.cellSize end
  local half = (metrics.pitchX - metrics.cellSize) / 2
  local candidates = {}
  if #slots == 0 then
    -- an empty group: the only boundary is right after its lock
    local lock
    for _, c in ipairs(row.cells) do if c.kind == Layout.CELL_DROP then lock = c end end
    local bx = lock and (lock.slim and 0 or cellRight(lock) + half) or 0
    candidates[1] = { x = bx, after = nil, before = nil }
  else
    candidates[#candidates + 1] = { x = cellLeft(slots[1]) - half, after = nil, before = slots[1].ref }
    for i = 1, #slots - 1 do
      candidates[#candidates + 1] = { x = cellRight(slots[i]) + half, after = slots[i].ref, before = slots[i + 1].ref }
    end
    candidates[#candidates + 1] = { x = cellRight(slots[#slots]) + half, after = slots[#slots].ref, before = nil }
  end
  -- 3. nearest boundary
  local best
  for _, cand in ipairs(candidates) do
    local d = math.abs(cand.x - x)
    if not best or d < best.d then best = { d = d, c = cand } end
  end
  -- Multi-row groups: the row's own first/last boundary is the same INDEX as the neighbouring row's
  -- last/first, so afterRef/beforeRef taken from this row alone are correct; the marker stays on this row.
  return {
    run = "section", sectionID = row.sectionID,
    afterRef = best.c.after, beforeRef = best.c.before,
    markerRow = bestRow, markerX = best.c.x,
  }
end

return Layout
