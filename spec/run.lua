-- KondoBags off-client tests. Run from the repo root:   lua5.1 spec/run.lua
-- Only Core/ is under test; Core files take (addonName, ns) via ... like the game does.

local ns = {}
local function LoadCore(file)
  local chunk = assert(loadfile("KondoBags/Core/" .. file))
  chunk("KondoBags", ns)
end
LoadCore("Sections.lua"); LoadCore("Layout.lua"); LoadCore("BagState.lua")
local S, L, B = ns.Sections, ns.Layout, ns.BagState

local tests, failures = {}, 0
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end
local function eq(a, b, msg)
  if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function ok(v, msg) if not v then error(msg or "expected true", 2) end end

-- A flat combined bag: Bag(n, filled) -> n refs, slot i filled with itemID = 100+i when filled[i].
local function Item(id) return { itemID = id, name = "i" .. id } end
local function Bag(n, filledSlots)
  local set = {}
  for _, s in ipairs(filledSlots or {}) do set[s] = true end
  local slots = {}
  for i = 0, n - 1 do slots[#slots + 1] = { bagID = 0, slot = i + 1, item = set[i] and Item(100 + i) or nil } end
  return slots
end
-- Store with one Keep section owning the top `k` slots of an n-slot bag (visual order = ascending).
local function KeepStore(n, k)
  local st = S.NewStore(n)
  st.list[1].boundary = n - k
  for s = n - k, n - 1 do st.list[1].order[#st.list[1].order + 1] = s end
  return st
end
-- Readable pictures of the layout: incoming itemIDs in reading order / keep itemIDs in reading order.
local function Picture(bag)
  local inc, keep = {}, {}
  for _, r in ipairs(bag:Layout().rows) do for _, c in ipairs(r.cells) do
    if c.kind == L.CELL_SLOT then
      local v = c.ref.item and (c.ref.item.itemID - 100) or "_"
      if c.sectionID then keep[#keep + 1] = v else inc[#inc + 1] = v end
    end
  end end
  return table.concat(inc, " ") .. " | " .. table.concat(keep, " ")
end
local function Cell(bag, slotIndex)
  for _, r in ipairs(bag:Layout().rows) do for _, c in ipairs(r.cells) do
    if c.kind == L.CELL_SLOT and c.ref.slotIndex == slotIndex then return c end
  end end
end
local function LockCell(bag)
  for _, r in ipairs(bag:Layout().rows) do for _, c in ipairs(r.cells) do if c.kind == L.CELL_DROP then return c end end end
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------
test("layout: runs are bottom-anchored, partial row on top right-aligned", function()
  local refs = {}
  for i = 1, 7 do refs[i] = { slotIndex = i - 1, item = Item(i) } end
  local r = L.Build({ columns = 4, loose = refs, sections = {} })
  eq(#r.rows, 2)
  eq(#r.rows[1].cells, 3, "top partial"); eq(r.rows[1].cells[1].col, 2, "right-aligned")
  eq(#r.rows[2].cells, 4, "bottom full")
end)

test("layout: a section is one lock cell then its items, below incoming", function()
  local hs = { slotIndex = 9, item = Item(6948) }
  local r = L.Build({ columns = 4, loose = { { slotIndex = 0 } }, sections = { { id = "s1", slots = { hs } } } })
  eq(#r.rows, 2); eq(r.rows[2].sectionID, "s1")
  eq(r.rows[2].cells[1].kind, L.CELL_DROP); eq(r.rows[2].cells[1].col, 3)
  eq(r.rows[2].cells[2].kind, L.CELL_SLOT); eq(r.rows[2].cells[2].col, 4)
end)

test("layout: empty section still shows its lock cell; Shift insert cell appears at insertAt", function()
  local r = L.Build({ columns = 4, loose = {}, sections = { { id = "s1", slots = {} } } })
  eq(#r.rows[1].cells, 1); eq(r.rows[1].cells[1].kind, L.CELL_DROP)
  local a, b = { slotIndex = 8, item = Item(1) }, { slotIndex = 9, item = Item(2) }
  r = L.Build({ columns = 6, loose = {}, sections = { { id = "s1", slots = { a, b } } }, insertAt = { sectionID = "s1", beforeRef = b } })
  local kinds = {}
  for _, c in ipairs(r.rows[1].cells) do kinds[#kinds + 1] = c.kind end
  eq(table.concat(kinds, ","), "drop,slot,insert,slot")
end)

-- ---------------------------------------------------------------------------
-- Sections (model, D11)
-- ---------------------------------------------------------------------------
test("partition: incoming is highest slot first (slot 0 bottom-right); keep follows order", function()
  local bag = B.New({ store = KeepStore(9, 3), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 6 })
  eq(Picture(bag), "5 4 3 2 1 0 | 6 7 8")
  S.MoveBefore(bag.store.list[1], 8, 6)
  eq(Picture(bag), "5 4 3 2 1 0 | 8 6 7", "visual reorder, no physical move")
end)

test("reconcile: legacy itemID store becomes an empty Keep at the top; bad boundary repaired", function()
  local legacy = { nextID = 2, list = { { id = "s1", name = "Keep", items = { [6948] = true } } } }
  local st = S.Reconcile(legacy, 10)
  eq(st.list[1].boundary, 10); eq(#st.list[1].order, 0)
  local st2 = S.Reconcile({ nextID = 2, list = { { id = "s1", boundary = 7, order = { 7 } } } }, 10)
  eq(#st2.list[1].order, 3, "order rebuilt to match range 7..9")
end)

-- ---------------------------------------------------------------------------
-- BagState (controller) -- the owner's worked examples
-- ---------------------------------------------------------------------------
test("drop kept (slot 7) onto EMPTY incoming slot 2: 7->2, lowest keep slot 6 slides into the hole and is released", function()
  -- Pictures show ITEM ids (item n started in slot n). Owner's example in SLOT terms:
  --   before 5 4 3 _ 1 0 | 6 7 8   drag slot7 -> slot2   after  6 5 4 3 2 1 0 | 7 8  (slot 6 now incoming)
  local bag = B.New({ store = KeepStore(9, 3), slots = Bag(9, { 0, 1, 3, 4, 5, 6, 7, 8 }), columns = 7 })
  eq(Picture(bag), "5 4 3 _ 1 0 | 6 7 8")
  ok(bag:Pickup(bag.slots[8]))                  -- slot 7
  ok(bag:Drop(Cell(bag, 2)))
  eq(Picture(bag), "_ 5 4 3 7 1 0 | 6 8", "slot 6 released EMPTY at top-left; item 6 slid up into slot 7; nothing else moved")
  eq(bag.store.list[1].boundary, 7)
  eq(bag.slots[3].item.itemID, 107, "item 7 physically in slot 2")
  eq(bag.slots[8].item.itemID, 106, "item 6 physically in slot 7"); ok(bag.slots[7].item == nil, "slot 6 empty")
end)

test("drop kept onto OCCUPIED incoming: plain swap, the displaced item is now kept in that visual spot", function()
  local bag = B.New({ store = KeepStore(9, 3), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 7 })
  ok(bag:Pickup(bag.slots[8]))                  -- item 7 at slot 7
  ok(bag:Drop(Cell(bag, 2)))
  eq(Picture(bag), "5 4 3 7 1 0 | 6 2 8")
  eq(bag.store.list[1].boundary, 6, "boundary unchanged")
end)

test("pin loose onto lock: swap into boundary-1 then grow; new item sits right of the lock", function()
  local bag = B.New({ store = KeepStore(9, 3), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 7 })
  ok(bag:Pickup(bag.slots[3]))                  -- item 2 at slot 2
  ok(bag:Drop(LockCell(bag)))
  -- 2<->5 swap, boundary 6->5: incoming (slots 4..0) reads 4 3 5 1 0 ; keep = new(5) first
  eq(Picture(bag), "4 3 5 1 0 | 2 6 7 8")
  eq(bag.store.list[1].boundary, 5)
end)

test("pin the item already at boundary-1: zero moves", function()
  local bag = B.New({ store = KeepStore(9, 3), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 7 })
  ok(bag:Pickup(bag.slots[6]))                  -- item 5 at slot 5
  ok(bag:Drop(LockCell(bag)))
  eq(Picture(bag), "4 3 2 1 0 | 5 6 7 8")
end)

test("unpin the LOWEST keep slot onto empty incoming: one move, no second swap", function()
  local bag = B.New({ store = KeepStore(9, 3), slots = Bag(9, { 0, 1, 3, 4, 5, 6, 7, 8 }), columns = 7 })
  ok(bag:Pickup(bag.slots[7]))                  -- item 6 at slot 6 == boundary
  ok(bag:Drop(Cell(bag, 2)))
  eq(Picture(bag), "_ 5 4 3 6 1 0 | 7 8", "slot 6 released (empty) at top-left")
end)

test("loose onto kept (no Shift): stock swap; membership is by slot", function()
  local bag = B.New({ store = KeepStore(9, 3), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 7 })
  ok(bag:Pickup(bag.slots[3]))                  -- item 2
  ok(bag:Drop(Cell(bag, 7)))                    -- onto item 7 (kept)
  eq(Picture(bag), "5 4 3 7 1 0 | 6 2 8")
end)

test("kept onto kept: visual reorder only", function()
  local bag = B.New({ store = KeepStore(9, 3), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 7 })
  ok(bag:Pickup(bag.slots[9])); ok(bag:Drop(Cell(bag, 6)))
  eq(Picture(bag), "5 4 3 2 1 0 | 8 6 7")
  eq(bag.slots[9].item.itemID, 108, "no physical move")
end)

test("Shift-drag: phantom opens at hover; dropping a LOOSE item there pins it at that index", function()
  local bag = B.New({ store = KeepStore(9, 3), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 7 })
  ok(bag:Pickup(bag.slots[3]))                  -- item 2
  bag:SetInsertMode(true); bag:SetHover(Cell(bag, 8))
  local ins
  for _, r in ipairs(bag:Layout().rows) do for _, c in ipairs(r.cells) do if c.kind == L.CELL_INSERT then ins = c end end end
  ok(ins and ins.beforeRef.slotIndex == 8, "phantom before item 8")
  ok(bag:Drop(ins))
  eq(Picture(bag), "4 3 5 1 0 | 6 7 2 8")
  bag:SetInsertMode(false)
end)

test("Shift-drag over the RIGHTMOST kept item is stable: phantom stays while the shifted item re-hovers", function()
  -- Opening the phantom before the last item pushes that item one cell right, under the still mouse.
  -- The view then reports hover on that same item again; the phantom must not jump.
  local bag = B.New({ store = KeepStore(9, 3), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 7 })
  ok(bag:Pickup(bag.slots[3]))
  bag:SetInsertMode(true)
  bag:SetHover(Cell(bag, 8))
  local function phantomBefore()
    for _, r in ipairs(bag:Layout().rows) do for _, c in ipairs(r.cells) do
      if c.kind == L.CELL_INSERT then return c.beforeRef and c.beforeRef.slotIndex end
    end end
  end
  eq(phantomBefore(), 8)
  bag:SetHover(nil); bag:SetHover(Cell(bag, 8))     -- the re-hover the view produces after the re-flow
  eq(phantomBefore(), 8, "no oscillation")
  ok(bag:Drop(Cell(bag, 8)))                         -- dropping on the item (Shift still down) lands at the phantom
  eq(Picture(bag), "4 3 5 1 0 | 6 7 2 8")
end)

test("loose onto loose / empty: stock swap and place", function()
  local bag = B.New({ store = KeepStore(6, 1), slots = Bag(6, { 0, 2, 5 }), columns = 6 })
  eq(Picture(bag), "_ _ 2 _ 0 | 5")
  ok(bag:Pickup(bag.slots[1])); ok(bag:Drop(Cell(bag, 3)))
  eq(Picture(bag), "_ 0 2 _ _ | 5")
end)

-- ---------------------------------------------------------------------------
for _, t in ipairs(tests) do
  local okRun, err = pcall(t.fn)
  if okRun then
    io.write("  ok   ", t.name, "\n")
  else
    failures = failures + 1; io.write("  FAIL ", t.name, "\n       ", tostring(err), "\n")
  end
end
io.write(string.format("%d tests, %d failed\n", #tests, failures))
os.exit(failures == 0 and 0 or 1)