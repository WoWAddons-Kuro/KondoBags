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
  st.boundary = n - k                       -- D12: one keep-wide boundary
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

test("layout: empty group still shows its lock; the cursor gap opens in the ANCHOR's column (anchor slides left)", function()
  local r = L.Build({ columns = 4, loose = {}, sections = { { id = "s1", slots = {} } } })
  eq(#r.rows[1].cells, 1); eq(r.rows[1].cells[1].kind, L.CELL_DROP)
  local a, b = { slotIndex = 8, item = Item(1) }, { slotIndex = 9, item = Item(2) }
  -- no gap: lock@4 a@5 b@6.  Gap anchored to `a` (mouse was over a at col 5): lock@3 a@4 GAP@5 b@6
  local secs = { { id = "s1", slots = { a, b } } }
  r = L.Build({ columns = 6, loose = {}, sections = secs, cursorGap = { sectionID = "s1", anchorRef = a } })
  local kinds = {}
  for _, c in ipairs(r.rows[1].cells) do kinds[#kinds + 1] = c.kind .. "@" .. c.col end
  eq(table.concat(kinds, ","), "drop@3,slot@4,gap@5,slot@6")
  r = L.Build({ columns = 6, loose = {}, sections = secs, cursorGap = { sectionID = "s1", anchorRef = nil } })
  eq(r.rows[1].cells[2].kind, L.CELL_GAP, "nil anchor = right after the lock")
end)

-- ---------------------------------------------------------------------------
-- Sections (model, D11)
-- ---------------------------------------------------------------------------
test("partition: incoming is highest slot first (slot 0 bottom-right); keep follows order", function()
  local bag = B.New({ store = KeepStore(9, 3), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 6 })
  eq(Picture(bag), "5 4 3 2 1 0 | 6 7 8")
  S.MoveToPositionOf(bag.store, 8, 6)
  eq(Picture(bag), "5 4 3 2 1 0 | 8 6 7", "visual reorder, no physical move")
end)

test("reconcile: legacy stores become an empty Keep at the top; unclaimed keep slots join group 1", function()
  local legacy = { nextID = 2, list = { { id = "s1", name = "Keep", items = { [6948] = true } } } }
  local st = S.Reconcile(legacy, 10)
  eq(st.boundary, 10); eq(#st.list[1].order, 0)
  local perSection = { nextID = 2, list = { { id = "s1", boundary = 7, order = { 7 } } } }   -- D11-era shape
  eq(S.Reconcile(perSection, 10).boundary, 10, "no store-level boundary -> fresh")
  local st2 = S.Reconcile({ nextID = 2, boundary = 7, list = { { id = "s1", order = { 7 } } } }, 10)
  eq(#st2.list[1].order, 3, "slots 8,9 unclaimed -> appended to group 1")
end)

test("AddGroup: the new empty group is drawn FIRST, directly under incoming; Keep moves down", function()
  local bag = B.New({ store = KeepStore(9, 2), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 6 })
  local g = bag:AddGroup("")
  eq(bag.store.list[1], g); eq(bag.store.list[2].name, "Keep")
  local rows = bag:Layout().rows
  eq(rows[#rows - 1].sectionID, g.id, "new group's lock row comes before Keep"); eq(#rows[#rows - 1].cells, 1)
  eq(rows[#rows].sectionID, bag.store.list[2].id)
end)

test("RemoveGroup: items drop into incoming via the lowest keep slot; loot order preserved; last group cannot go", function()
  -- keep = slots 6,7,8 in ONE group; add a second group and move item 8 into it, then remove that group
  local bag = B.New({ store = KeepStore(9, 3), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 6 })
  local g2 = bag:AddGroup("Second")                       -- drawn first
  S.MoveToGap(bag.store, g2, 8, nil)                      -- item 8 now shows in g2 (gap after its lock)
  eq(Picture(bag), "5 4 3 2 1 0 | 8 6 7")                 -- groups print in order: g2 (8) then Keep (6 7)
  ok(bag:RemoveGroup(g2.id))
  -- slot 8 swapped down into slot 6 (the lowest keep slot), slot 6 released to incoming
  eq(bag.store.boundary, 7)
  eq(bag.slots[7].item.itemID, 108, "item 8 now physically in slot 6 = top of incoming")
  eq(bag.slots[9].item.itemID, 106, "item 6 moved up to slot 8, still kept")
  eq(Picture(bag), "8 5 4 3 2 1 0 | 6 7")
  eq(#bag.store.list, 1)
  ok(not bag:RemoveGroup(bag.store.list[1].id), "cannot remove the last group")
  -- removing an EMPTY group is a no-op physically
  local g3 = bag:AddGroup("")
  ok(bag:RemoveGroup(g3.id)); eq(bag.store.boundary, 7); eq(Picture(bag), "8 5 4 3 2 1 0 | 6 7")
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
  eq(bag.store.boundary, 7)
  eq(bag.slots[3].item.itemID, 107, "item 7 physically in slot 2")
  eq(bag.slots[8].item.itemID, 106, "item 6 physically in slot 7"); ok(bag.slots[7].item == nil, "slot 6 empty")
end)

test("drop kept onto OCCUPIED incoming: plain swap, the displaced item is now kept in that visual spot", function()
  local bag = B.New({ store = KeepStore(9, 3), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 7 })
  ok(bag:Pickup(bag.slots[8]))                  -- item 7 at slot 7
  ok(bag:Drop(Cell(bag, 2)))
  eq(Picture(bag), "5 4 3 7 1 0 | 6 2 8")
  eq(bag.store.boundary, 6, "boundary unchanged")
end)

test("pin loose onto lock: items above it SHIFT down (no swap), keep grows; new item sits right of the lock", function()
  local bag = B.New({ store = KeepStore(9, 3), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 7 })
  ok(bag:Pickup(bag.slots[3]))                  -- item 2 at slot 2
  ok(bag:Drop(LockCell(bag)))
  -- Shift: 3->2, 4->3, 5->4, item 2 -> slot 5; boundary 6->5. Incoming (slots 4..0) keeps its order
  -- with the gap at slot 2 closed: 5 4 3 1 0. Keep = new first.
  eq(Picture(bag), "5 4 3 1 0 | 2 6 7 8")
  eq(bag.store.boundary, 5)
  eq(bag.slots[3].item.itemID, 103, "item 3 shifted down into slot 2")
  eq(bag.slots[6].item.itemID, 102, "item 2 now at slot 5 (the new lowest keep slot)")
end)

test("pin the item already at boundary-1: zero moves", function()
  local bag = B.New({ store = KeepStore(9, 3), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 7 })
  ok(bag:Pickup(bag.slots[6]))                  -- item 5 at slot 5
  ok(bag:Drop(LockCell(bag)))
  eq(Picture(bag), "4 3 2 1 0 | 5 6 7 8")
end)

test("pin: the hole is the HIGHEST free slot below the top; only items above it shift (minimal movement)", function()
  -- slots 0..5 incoming, 2 and 4 free; pin item 0. Hole e = 4 (nearest to the blocking item 5):
  -- 0 -> 4, then 4<->5. Items 1 and 3 do not move; slot 2 stays free; slot 0 becomes the hole.
  local bag = B.New({ store = KeepStore(9, 3), slots = Bag(9, { 0, 1, 3, 5, 6, 7, 8 }), columns = 7 })
  eq(Picture(bag), "5 _ 3 _ 1 0 | 6 7 8")
  ok(bag:Pickup(bag.slots[1]))                  -- item 0
  ok(bag:Drop(LockCell(bag)))
  eq(Picture(bag), "5 3 _ 1 _ | 0 6 7 8")
  eq(bag.store.boundary, 5)
  eq(bag.slots[4].item.itemID, 103, "item 3 untouched at slot 3")
  eq(bag.slots[2].item.itemID, 101, "item 1 untouched at slot 1")
  eq(bag.slots[5].item.itemID, 105, "item 5 stepped down into slot 4")
  ok(bag.slots[1].item == nil, "slot 0 (where item 0 was) is now the hole")
end)

test("pin when the top incoming slot itself is free: one move, nothing shifts", function()
  local bag = B.New({ store = KeepStore(9, 3), slots = Bag(9, { 0, 1, 2, 3, 4, 6, 7, 8 }), columns = 7 })
  ok(bag:Pickup(bag.slots[2]))                  -- item 1
  ok(bag:Drop(LockCell(bag)))
  eq(Picture(bag), "4 3 2 _ 0 | 1 6 7 8")
end)

test("pin with no free slot above the item: full shift from the item (the only option)", function()
  local bag = B.New({ store = KeepStore(9, 3), slots = Bag(9, { 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 7 })
  ok(bag:Pickup(bag.slots[3]))                  -- item 2; slot 0 free but BELOW it, irrelevant
  ok(bag:Drop(LockCell(bag)))
  eq(Picture(bag), "5 4 3 1 _ | 2 6 7 8")
end)

test("PinFromIncoming with fromSlot nil (external item): lands in the highest free slot, shifts from there", function()
  local st = KeepStore(9, 3)
  local slots = Bag(9, { 0, 1, 3, 5, 6, 7, 8 })         -- slots 2 and 4 free
  local isFree = function(s) return slots[s + 1].item == nil end
  local moves, e = S.PinFromIncoming(st, st.list[1], nil, nil, isFree)
  eq(e, 4); eq(#moves, 1)                                -- 4<->5 only
  eq(moves[1].from, 4); eq(moves[1].to, 5)
  eq(st.boundary, 5); eq(st.list[1].order[1], 5)
  local full = Bag(3, { 0, 1 }); local st2 = KeepStore(3, 1)
  ok(S.PinFromIncoming(st2, st2.list[1], nil, nil, function(s) return full[s + 1].item == nil end) == nil, "no free slot -> nil")
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

test("Shift-drag: the cursor gap opens in the hovered item's column; dropping a LOOSE item lands there", function()
  local bag = B.New({ store = KeepStore(9, 3), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 7 })
  ok(bag:Pickup(bag.slots[3]))                  -- item 2
  bag:SetInsertMode(true); bag:SetHover(Cell(bag, 7))        -- hover item 7 (keep row: lock 6 7 8)
  local gap
  for _, r in ipairs(bag:Layout().rows) do for _, c in ipairs(r.cells) do if c.kind == L.CELL_GAP then gap = c end end end
  ok(gap and gap.anchorRef and gap.anchorRef.slotIndex == 7, "gap anchored to item 7")
  ok(bag:Drop(gap))
  eq(Picture(bag), "5 4 3 1 0 | 6 7 2 8", "item 2 landed right after 7; incoming shifted, order kept")
  bag:SetInsertMode(false)
end)

test("Shift-drag over the RIGHTMOST kept item: gap opens at the right wall, item slides left, and holds", function()
  -- before:        lock@6 18@7 19@8 20@9 21@10         (10 columns)
  -- hover 21:      lock@5 18@6 19@7 20@8 21@9 GAP@10   <- gap exactly where the mouse is
  local slots = Bag(22, { 0, 1, 2, 3, 4, 5, 18, 19, 20, 21 })
  local st = S.NewStore(22); st.boundary = 18; st.list[1].order = { 18, 19, 20, 21 }
  local bag = B.New({ store = st, slots = slots, columns = 10 })
  local function keepRow()
    for _, r in ipairs(bag:Layout().rows) do if r.sectionID then
      local t = {}
      for _, c in ipairs(r.cells) do
        local label = c.kind == L.CELL_GAP and "GAP" or c.kind == L.CELL_DROP and "lock" or tostring(c.ref.slotIndex)
        t[#t + 1] = label .. "@" .. c.col
      end
      return table.concat(t, " ")
    end end
  end
  eq(keepRow(), "lock@6 18@7 19@8 20@9 21@10")
  ok(bag:Pickup(bag.slots[3]))
  bag:SetHover(Cell(bag, 21)); bag:SetInsertMode(true)
  eq(keepRow(), "lock@5 18@6 19@7 20@8 21@9 GAP@10")
  -- the still mouse is now over the gap; hovering it must not move it
  local gap; for _, r in ipairs(bag:Layout().rows) do for _, c in ipairs(r.cells) do if c.kind == L.CELL_GAP then gap = c end end end
  bag:SetHover(nil); bag:SetHover(gap)
  eq(keepRow(), "lock@5 18@6 19@7 20@8 21@9 GAP@10", "stable over the gap")
  -- re-hovering 21 (same anchor) must not move it either
  bag:SetHover(nil); bag:SetHover(Cell(bag, 21))
  eq(keepRow(), "lock@5 18@6 19@7 20@8 21@9 GAP@10", "same anchor: holds")
  ok(bag:Drop(gap))
  eq(st.list[1].order[#st.list[1].order], 17, "pinned item is LAST (slot 17 = new boundary-1), i.e. right of 21")
  eq(st.boundary, 17)
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