-- KondoBags off-client tests. Run from the repo root:   lua5.1 spec/run.lua
-- Only Core/ is under test; Core files take (addonName, ns) via ... like the game does.

local ns = {}
local function LoadCore(file)
  local chunk = assert(loadfile("KondoBags/Core/" .. file))
  chunk("KondoBags", ns)
end
LoadCore("Sections.lua"); LoadCore("Layout.lua"); LoadCore("BagState.lua")
LoadCore("Scan.lua"); LoadCore("MoveQueue.lua"); LoadCore("../Client/Client.lua"); LoadCore("../Client/Mock.lua")
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
-- Store with one Keep group holding the given physical slots (visual order = given order).
local function KeepStore(slotsKept)
  local st = S.NewStore()
  for _, s in ipairs(slotsKept or {}) do st.kept[s] = st.list[1].id; st.list[1].order[#st.list[1].order + 1] = s end
  return st
end
-- Readable pictures of the layout: incoming itemIDs in reading order / keep itemIDs in reading order.
local function Picture(bag)
  local inc, keep = {}, {}
  for _, r in ipairs(bag:Layout().rows) do for _, c in ipairs(r.cells) do
    if c.kind == L.CELL_SLOT and not r.typed then
      local v = c.ref.item and (c.ref.item.itemID - 100) or "_"
      if c.sectionID then keep[#keep + 1] = v else inc[#inc + 1] = v end
    end
  end end
  return table.concat(inc, " ") .. " | " .. table.concat(keep, " ")
end
-- Physical slot indices of incoming in visual reading order (free cells show as "_N").
local function IncomingSlots(bag)
  local t = {}
  for _, r in ipairs(bag:Layout().rows) do for _, c in ipairs(r.cells) do
    if c.kind == L.CELL_SLOT and not r.typed and not c.sectionID then
      t[#t + 1] = (c.ref.item and "" or "_") .. c.ref.slotIndex
    end
  end end
  return table.concat(t, " ")
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
  local secs = { { id = "s1", slots = { a, b } } }
  r = L.Build({ columns = 6, loose = {}, sections = secs, cursorGap = { sectionID = "s1", anchorRef = a } })
  local kinds = {}
  for _, c in ipairs(r.rows[1].cells) do kinds[#kinds + 1] = c.kind .. "@" .. c.col end
  eq(table.concat(kinds, ","), "drop@3,slot@4,gap@5,slot@6")
  r = L.Build({ columns = 6, loose = {}, sections = secs, cursorGap = { sectionID = "s1", anchorRef = nil } })
  eq(r.rows[1].cells[2].kind, L.CELL_GAP, "nil anchor = right after the lock")
end)

test("layout: slim lock -- a group whose items fill whole rows keeps its lock in the gutter (col 0), no extra row", function()
  local slots = {}
  for i = 1, 4 do slots[i] = { slotIndex = 10 + i, item = Item(i) } end
  local r = L.Build({ columns = 4, loose = { { slotIndex = 0 } }, sections = { { id = "s1", slots = slots } } })
  eq(#r.rows, 2, "incoming row + ONE group row (the lock did not spill)")
  ok(r.slimGutter, "result asks the view for the gutter")
  local row = r.rows[2]
  ok(row.slimLock); eq(#row.cells, 5)
  eq(row.cells[1].kind, L.CELL_DROP); eq(row.cells[1].col, 0); ok(row.cells[1].slim)
  eq(row.cells[2].col, 1); eq(row.cells[5].col, 4, "items keep the full row")
  -- 5 items in 4 columns: normal lock (partial top row), no gutter
  slots[5] = { slotIndex = 15, item = Item(5) }
  r = L.Build({ columns = 4, loose = {}, sections = { { id = "s1", slots = slots } } })
  ok(not r.slimGutter); eq(#r.rows, 2); eq(r.rows[1].cells[1].kind, L.CELL_DROP); eq(r.rows[1].cells[1].col, 3)
end)

-- ---------------------------------------------------------------------------
-- Sections (model, D15): positional map with nullable backing; ReorderHoles
-- ---------------------------------------------------------------------------
-- Reading-order picture of incoming by PHYSICAL index: "_N" = hole backed by N. Position 1 is the
-- bottom-right (last in the string); the top-left (first) is the highest position.
test("fresh store: map is identity (physical N-1 top-left ... 0 bottom-right); holes ascend from the bottom-right", function()
  -- physical 0..8: items in 0,1,3,5 ; kept 6,8 ; free 2,4,7
  local bag = B.New({ store = KeepStore({ 6, 8 }), slots = Bag(9, { 0, 1, 3, 5, 6, 8 }), columns = 7 })
  -- map starts as 0..8 minus kept = {0,1,2,3,4,5,7}; holes at positions of 2,4,7 already ascend from the right
  eq(IncomingSlots(bag), "_7 5 _4 3 _2 1 0")
  eq(Picture(bag), "_ 5 _ 3 _ 1 0 | 6 8")
  S.MoveToPositionOf(bag.store, 8, 6)
  eq(Picture(bag), "_ 5 _ 3 _ 1 0 | 8 6", "visual reorder, no physical move")
end)

test("an item in the MIDDLE of incoming is used up: its position becomes a hole RIGHT THERE; hole backing re-sorts", function()
  local bag = B.New({ store = KeepStore({ 8 }), slots = Bag(9, { 0, 1, 3, 5, 6, 8 }), columns = 7 })
  eq(IncomingSlots(bag), "_7 6 5 _4 3 _2 1 0")
  bag.slots[6].item = nil                                   -- eat the item in physical 5 (position 6)
  S.ReorderHoles(bag.store, bag:IsFreeFn())                 -- what a scan does
  -- holes are now at positions {8,6,5,3} (phys 7,5,4,2 before); re-sorted so reading from the RIGHT they
  -- ascend: position 3 -> 2, 5 -> 4, 6 -> 5, 8 -> 7. Same set, same cells, occupied 6 3 1 0 untouched.
  eq(IncomingSlots(bag), "_7 6 _5 _4 3 _2 1 0")
  bag.slots[9].item = nil                                   -- the KEPT item in 8 is eaten
  bag:SetSlots(bag.slots)                                   -- scan -> Reconcile: Release -> new top-left position
  ok(not S.IsKept(bag.store, 8), "an emptied kept slot leaves Keep (D13.1)")
  eq(IncomingSlots(bag), "_8 _7 6 _5 _4 3 _2 1 0", "8 appeared top-left; backing ascends from the right")
end)

test("reconcile: pre-D15 stores are replaced; emptied / unknown kept slots dropped; missing slots appended top-left", function()
  ok(S.Reconcile({ nextID = 2, boundary = 7, list = { { id = "s1", order = { 7 } } } }, 10).map ~= nil, "boundary store -> fresh")
  local st = { nextID = 3, map = { 0, 1, 2, 3, 4, 5, 6 }, kept = { [7] = "s1", [8] = "s1", [9] = "zz", [12] = "s1" },
               list = { { id = "s1", name = "Keep", order = { 8 } } } }
  local slots = Bag(10, { 0, 1, 2, 3, 4, 5, 6, 7, 9 })     -- 8 is EMPTY, 12 out of range, 9's group does not exist
  S.Reconcile(st, 10, slots)
  ok(st.kept[7] and not st.kept[8] and not st.kept[9] and not st.kept[12])
  eq(table.concat(st.list[1].order, ","), "7", "order holds exactly the kept slots")
  eq(table.concat(st.map, ","), "0,1,2,3,4,5,6,8,9", "8 and 9 appended at the top-left (end of map); 8 is a hole")
end)

test("AddGroup: the new empty group is drawn FIRST, directly under incoming; Keep moves down", function()
  local bag = B.New({ store = KeepStore({ 7, 8 }), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 6 })
  local g = bag:AddGroup("")
  eq(bag.store.list[1], g); eq(bag.store.list[2].name, "Keep")
  local rows = bag:Layout().rows
  eq(rows[#rows - 1].sectionID, g.id, "new group's lock row comes before Keep"); eq(#rows[#rows - 1].cells, 1)
  eq(rows[#rows].sectionID, bag.store.list[2].id)
end)

test("RemoveGroup: its slots get NEW top-left positions, zero moves; last group cannot go", function()
  local bag = B.New({ store = KeepStore({ 6, 7, 8 }), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 6 })
  local g2 = bag:AddGroup("Second")
  S.MoveToGap(bag.store, g2, 8, nil)
  eq(Picture(bag), "5 4 3 2 1 0 | 8 6 7")
  ok(bag:RemoveGroup(g2.id))
  eq(bag.slots[9].item.itemID, 108, "nothing moved")
  eq(Picture(bag), "8 5 4 3 2 1 0 | 6 7", "8 appeared at the top-left of incoming")
  eq(#bag.store.list, 1)
  ok(not bag:RemoveGroup(bag.store.list[1].id), "cannot remove the last group")
end)

test("first run seeds the Hearthstone into Keep by itemID, once; unpinning it later is respected", function()
  local slots = Bag(6, { 0, 1, 2 })
  slots[3].item = { itemID = S.HEARTHSTONE_ID, name = "Hearthstone" }       -- physical 2
  local bag = B.New({ store = nil, slots = slots, columns = 6 })             -- nil store = fresh character
  ok(bag.store.seeded, "seeded flag set")
  ok(S.IsKept(bag.store, 2), "hearthstone slot is kept")
  eq(Picture(bag), "_ _ _ 1 0 | 6848", "kept row shows the hearthstone (Picture prints itemID - 100)")
  -- player unpins it (stock drag out = Release on scan); a later Reconcile must NOT re-pin it
  S.Release(bag.store, 2, bag:IsFreeFn())
  bag:SetSlots(slots)
  ok(not S.IsKept(bag.store, 2), "stays unpinned after the player's choice")
  -- a fresh character with no hearthstone at all: still a valid empty Keep
  local bag2 = B.New({ store = nil, slots = Bag(4, { 0 }), columns = 4 })
  ok(bag2.store.seeded); eq(#bag2.store.list[1].order, 0)
end)

-- ---------------------------------------------------------------------------
-- BagState (controller), MOCK path -- the table is the bag
-- ---------------------------------------------------------------------------
test("pin loose onto lock: ZERO moves; its position is deleted and the run top-left of it closes by one", function()
  local bag = B.New({ store = KeepStore({ 6, 7, 8 }), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 7 })
  ok(bag:Pickup(bag.slots[3]))                  -- item 2 at physical 2
  ok(bag:Drop(LockCell(bag)))
  eq(Picture(bag), "5 4 3 1 0 | 2 6 7 8")
  eq(bag.slots[3].item.itemID, 102, "item 2 is still physically in slot 2")
  ok(S.IsKept(bag.store, 2))
end)

test("pin with holes around: the holes stay where they are; only the pinned position goes", function()
  local bag = B.New({ store = KeepStore({ 8 }), slots = Bag(9, { 0, 1, 3, 5, 8 }), columns = 7 })
  eq(IncomingSlots(bag), "_7 _6 5 _4 3 _2 1 0")
  ok(bag:Pickup(bag.slots[4])); ok(bag:Drop(LockCell(bag)))   -- pin physical 3
  eq(IncomingSlots(bag), "_7 _6 5 _4 _2 1 0", "3's cell is gone; everything left of it stepped right; holes re-sorted")
  eq(Picture(bag), "_ _ 5 _ _ 1 0 | 3 8")
end)

test("drop kept onto EMPTY incoming: stock place; the emptied kept slot is Released to a NEW top-left position", function()
  local bag = B.New({ store = KeepStore({ 6, 7, 8 }), slots = Bag(9, { 0, 1, 3, 4, 5, 6, 7, 8 }), columns = 7 })
  eq(Picture(bag), "5 4 3 _ 1 0 | 6 7 8")
  ok(bag:Pickup(bag.slots[8]))                  -- item 7 (kept)
  ok(bag:Drop(Cell(bag, 2)))                    -- onto empty physical 2
  eq(bag.slots[3].item.itemID, 107); ok(bag.slots[8].item == nil)
  ok(not S.IsKept(bag.store, 7), "7 emptied -> left Keep")
  eq(IncomingSlots(bag), "_7 5 4 3 2 1 0", "7 appeared top-left as a hole; 7's item now in position of 2")
end)

test("drop kept onto OCCUPIED incoming: stock swap; kept-ness follows the SLOT", function()
  local bag = B.New({ store = KeepStore({ 6, 7, 8 }), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 7 })
  ok(bag:Pickup(bag.slots[8])); ok(bag:Drop(Cell(bag, 2)))
  eq(Picture(bag), "5 4 3 7 1 0 | 6 2 8")
  ok(S.IsKept(bag.store, 7) and not S.IsKept(bag.store, 2))
end)

test("loose onto kept (no Shift): stock swap; membership is by slot", function()
  local bag = B.New({ store = KeepStore({ 6, 7, 8 }), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 7 })
  ok(bag:Pickup(bag.slots[3])); ok(bag:Drop(Cell(bag, 7)))
  eq(Picture(bag), "5 4 3 7 1 0 | 6 2 8")
end)

test("kept onto kept: visual reorder only", function()
  local bag = B.New({ store = KeepStore({ 6, 7, 8 }), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 7 })
  ok(bag:Pickup(bag.slots[9])); ok(bag:Drop(Cell(bag, 6)))
  eq(Picture(bag), "5 4 3 2 1 0 | 8 6 7")
  eq(bag.slots[9].item.itemID, 108, "no physical move")
end)

test("Shift-drag: the cursor gap opens in the hovered item's column; dropping a LOOSE item lands there", function()
  local bag = B.New({ store = KeepStore({ 6, 7, 8 }), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 7 })
  ok(bag:Pickup(bag.slots[3]))                  -- item 2
  bag:SetInsertMode(true); bag:SetHover(Cell(bag, 7))
  local gap
  for _, r in ipairs(bag:Layout().rows) do for _, c in ipairs(r.cells) do if c.kind == L.CELL_GAP then gap = c end end end
  ok(gap and gap.anchorRef and gap.anchorRef.slotIndex == 7, "gap anchored to item 7")
  ok(bag:Drop(gap))
  eq(Picture(bag), "5 4 3 1 0 | 6 7 2 8", "item 2 landed right after 7; zero moves")
  bag:SetInsertMode(false)
end)

test("Shift-drag over the RIGHTMOST kept item: gap opens at the right wall, item slides left, and holds", function()
  local slots = Bag(22, { 0, 1, 2, 3, 4, 5, 18, 19, 20, 21 })
  local st = KeepStore({ 18, 19, 20, 21 })
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
  local gap; for _, r in ipairs(bag:Layout().rows) do for _, c in ipairs(r.cells) do if c.kind == L.CELL_GAP then gap = c end end end
  bag:SetHover(nil); bag:SetHover(gap)
  eq(keepRow(), "lock@5 18@6 19@7 20@8 21@9 GAP@10", "stable over the gap")
  bag:SetHover(nil); bag:SetHover(Cell(bag, 21))
  eq(keepRow(), "lock@5 18@6 19@7 20@8 21@9 GAP@10", "same anchor: holds")
  ok(bag:Drop(gap))
  eq(st.list[1].order[#st.list[1].order], 2, "pinned item (physical 2) is LAST, i.e. right of 21")
end)

test("loose onto loose / empty: stock place; the vacated cell is a hole where it was; backing re-sorts", function()
  local bag = B.New({ store = KeepStore({ 5 }), slots = Bag(6, { 0, 2, 5 }), columns = 6 })
  eq(IncomingSlots(bag), "_4 _3 2 _1 0")
  ok(bag:Pickup(bag.slots[1])); ok(bag:Drop(Cell(bag, 3)))          -- item 0 -> empty physical 3
  -- cells: position of 0 is now a hole, position of 3 is occupied. Holes {4,1,0} re-sorted from the right.
  eq(IncomingSlots(bag), "_4 3 2 _1 _0")
end)

-- ---------------------------------------------------------------------------
-- Typed (restricted-bag) slots: ONE display-only run ABOVE incoming (D13.3)
-- ---------------------------------------------------------------------------
test("typed slots: one run above incoming, mixed kinds, do not shift the general index or Keep", function()
  local all = Bag(6, { 0, 1, 5 })                                   -- general: slots 0..5, keep = {5}
  all[#all + 1] = { bagID = 2, slot = 1, kind = "herb",   item = Item(900) }
  all[#all + 1] = { bagID = 2, slot = 2, kind = "herb" }
  all[#all + 1] = { bagID = 3, slot = 1, kind = "quiver", item = Item(901) }
  local bag = B.New({ store = KeepStore({ 5 }), slots = all, columns = 6 })
  eq(#bag.slots, 6, "typed slots are not in the flat general list")
  eq(#bag.typedSlots, 3)
  eq(Picture(bag), "_ _ _ 1 0 | 5")
  local rows = bag:Layout().rows
  ok(rows[1].typed, "first row is the typed run")
  eq(#rows[1].cells, 3)
  eq(rows[1].cells[1].slotKind, "quiver"); eq(rows[1].cells[3].slotKind, "herb")
  eq(rows[1].cells[3].ref.item.itemID, 900)
  ok(not rows[2].typed, "incoming follows")
  -- MOCK: a typed item on the lock = pin from outside: steals the TOP-LEFT hole (physical 4), one place
  ok(bag:Pickup(bag.typedSlots[1]))
  ok(bag:Drop(LockCell(bag)), "typed item pins via the top-left hole")
  eq(bag.slots[5].item.itemID, 900, "landed in physical 4 (the top-left hole)"); ok(S.IsKept(bag.store, 4))
  ok(bag.typedSlots[1].item == nil)
  eq(Picture(bag), "_ _ 1 0 | 800 5", "incoming lost one cell")
  -- a general item on a typed cell is refused and released
  ok(bag:Pickup(bag.slots[1]))
  ok(not bag:Drop(rows[1].cells[2]), "general item cannot be dropped on a typed cell"); ok(bag.held == nil)
  -- same-kind typed <-> typed is a stock swap/place; cross-kind is refused
  ok(bag:Pickup(bag.typedSlots[3]))                                     -- quiver item
  ok(not bag:Drop(rows[1].cells[3]), "quiver -> herb slot refused")
end)

-- ---------------------------------------------------------------------------
-- Client provider + Scan (Phase L step 1/2)
-- ---------------------------------------------------------------------------
test("Client.KindFromFamily: lowest set bit wins; 0/nil = general; unknown bits = general", function()
  local K = ns.Client.KindFromFamily
  eq(K(nil), "general"); eq(K(0), "general")
  eq(K(1), "quiver"); eq(K(2), "ammo"); eq(K(4), "soul"); eq(K(32), "herb"); eq(K(64), "enchanting")
  eq(K(256), "keyring"); eq(K(1024), "mining")
  eq(K(32 + 1024), "herb", "multi-bit mask: lowest bit")
  eq(K(2048), "general", "item-only flag on a bag is not a kind")
end)

test("Client.ItemFitsKind: general takes all; a typed slot takes only items carrying its family bit", function()
  local F = ns.Client.ItemFitsKind
  ok(F(0, "general")); ok(F(nil, "general")); ok(F(1, nil))
  ok(F(1, "quiver"), "arrows -> quiver"); ok(not F(1, "ammo"), "arrows -> pouch refused")
  ok(F(2, "ammo"), "bullets -> pouch"); ok(F(32, "herb")); ok(F(4, "soul"))
  ok(not F(0, "herb"), "ordinary item refused by herb bag"); ok(not F(nil, "herb"))
  ok(F(32 + 1024, "mining"), "multi-family item fits either")
  -- BagState view: nothing carried = everything fits
  local bag = B.New({ store = S.NewStore(3), slots = Bag(3, {}), columns = 3 })
  ok(bag:HeldFits("herb")); bag:SetCursor("external", 0); ok(not bag:HeldFits("herb")); ok(bag:HeldFits("general"))
end)

test("Scan.Refs over the Mock provider: general first (flat index = bag order), typed after, free counts", function()
  local refs = {
    { bagID = 0, slot = 1, kind = "general", item = Item(1) }, { bagID = 0, slot = 2, kind = "general" },
    { bagID = 1, slot = 1, kind = "general" },
    { bagID = 2, slot = 1, kind = "herb", item = Item(7) }, { bagID = 2, slot = 2, kind = "herb" },
  }
  local P = ns.Client.NewMock(refs)
  eq(P.BagKind(2), "herb"); eq(P.NumSlots(0), 2); eq((P.FreeSlots(0)), 1)
  local out, sum = ns.Scan.Refs(P)
  eq(#out, 5); eq(sum.general, 3); eq(sum.typed, 2)
  eq(out[1].bagID, 0); eq(out[1].slot, 1); eq(out[1].item.itemID, 1)
  eq(out[3].bagID, 1); eq(out[4].kind, "herb"); eq(out[4].item.itemID, 7)
  eq(sum.free.general, 2); eq(sum.free.herb, 1)
  -- the same list feeds BagState unchanged
  local bag = B.New({ store = S.NewStore(3), slots = out, columns = 4 })
  eq(#bag.slots, 3); eq(#bag.typedSlots, 2)
  -- Mock Pickup emulates the cursor: pick up then place
  P.Pickup(0, 1); ok(refs[1].item == nil); P.Pickup(0, 2); eq(refs[2].item.itemID, 1)
end)

test("MoveQueue: one op in flight at a time; a place completes on ONE unlock; onDone fires once", function()
  local calls = {}
  local P = { Pickup = function(b, s) calls[#calls + 1] = b .. ":" .. s end }
  local q = ns.MoveQueue.New(P, function(i) return 0, i + 1 end)
  local doneCount = 0
  q:Push({ { place = true, bagID = 1, slot = 7 }, { place = true, bagID = 1, slot = 8 } }, function() doneCount = doneCount + 1 end)
  eq(#calls, 1); eq(calls[1], "1:7"); ok(q:IsBusy())
  q:OnLockChanged(false)                       -- one unlock completes a place
  eq(#calls, 2); eq(calls[2], "1:8")
  q:OnBagUpdateDelayed()                       -- alternative completion signal
  ok(not q:IsBusy()); eq(doneCount, 1)
  q:Push({ { from = 2, to = 3 } })             -- a swap: two Pickups, two unlocks
  eq(#calls, 4); q:OnLockChanged(false); ok(q:IsBusy()); q:OnLockChanged(false); ok(not q:IsBusy())
  q:Abort(); ok(not q:IsBusy())
end)

test("live pin from incoming: ONE Pickup (put the cursor item back); store commits when it lands", function()
  local bag = B.New({ store = KeepStore({ 6, 7, 8 }), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 7 })
  bag.live = true
  local issued = {}
  bag.moveQueue = ns.MoveQueue.New({ Pickup = function(b, s) issued[#issued + 1] = s end },
    function(i) return bag.slots[i + 1].bagID, bag.slots[i + 1].slot end)
  bag:SetCursor(bag.slots[3])                   -- item 2 (physical 2) on the real cursor
  ok(bag:Drop(LockCell(bag)))
  eq(#issued, 1); eq(issued[1], 3, "the one op: Pickup on its OWN slot (index 2 = slot 3) drops it back")
  ok(not S.IsKept(bag.store, 2), "store not committed until the op lands")
  bag.moveQueue:OnLockChanged(false)
  ok(S.IsKept(bag.store, 2), "committed"); eq(bag.store.list[1].order[1], 2)
end)

test("live kept -> other group's lock: map edit plus ONE Pickup on its own slot so the real cursor drops", function()
  local bag = B.New({ store = KeepStore({ 6, 7, 8 }), slots = Bag(9, { 0, 1, 2, 3, 4, 5, 6, 7, 8 }), columns = 7 })
  bag.live = true
  local g2 = bag:AddGroup("Second")
  local issued = {}
  bag.moveQueue = ns.MoveQueue.New({ Pickup = function(b, s) issued[#issued + 1] = s end },
    function(i) return bag.slots[i + 1].bagID, bag.slots[i + 1].slot end)
  bag:SetCursor(bag.slots[8])                   -- kept item 7 on the real cursor
  local lock
  for _, r in ipairs(bag:Layout().rows) do for _, c in ipairs(r.cells) do if c.kind == L.CELL_DROP and c.sectionID == g2.id then lock = c end end end
  ok(bag:Drop(lock))
  eq(#issued, 1); eq(issued[1], 8, "one Pickup on slot 8 (item 7's own slot) puts the cursor item back")
  bag.moveQueue:OnLockChanged(false)
  eq(S.SectionOfSlot(bag.store, 7).id, g2.id, "moved to the second group")
end)

test("hideLocks: external cursor with no free general slot emits no lock / gap cells", function()
  local bag = B.New({ store = KeepStore({ 5 }), slots = Bag(6, { 0, 1, 2, 3, 4, 5 }), columns = 6 })
  bag.live = true
  bag:SetCursor("external")
  ok(LockCell(bag) == nil, "full bag: lock hidden")
  local rows = bag:Layout().rows
  eq(#rows[#rows].cells, 1, "the kept item still draws")
  bag:SetCursor(nil)
  ok(LockCell(bag) ~= nil, "cursor empty: lock back")
  local bag2 = B.New({ store = KeepStore({ 5 }), slots = Bag(6, { 0, 1, 3, 4, 5 }), columns = 6 })
  bag2.live = true; bag2:SetCursor("external")
  ok(LockCell(bag2) ~= nil, "one free slot: lock shown")
end)

test("live pin from OUTSIDE (typed / external): ONE Pickup into the lowest free general slot", function()
  local all = Bag(6, { 0, 1, 3, 4, 5 })                               -- physical 2 free
  all[#all + 1] = { bagID = 2, slot = 1, kind = "herb", item = Item(900) }
  local bag = B.New({ store = KeepStore({ 5 }), slots = all, columns = 6 })
  bag.live = true
  local issued = {}
  bag.moveQueue = ns.MoveQueue.New({ Pickup = function(b, s) issued[#issued + 1] = b .. ":" .. s end },
    function(i) return bag.slots[i + 1].bagID, bag.slots[i + 1].slot end)
  bag:SetCursor(bag.typedSlots[1])
  ok(bag:Drop(LockCell(bag)))
  eq(#issued, 1); eq(issued[1], "0:3", "placed into physical 2 (slot 3), the lowest free")
  bag.moveQueue:OnLockChanged(false)
  ok(S.IsKept(bag.store, 2)); eq(bag.store.list[1].order[1], 2)
  -- external cursor, same path
  local bag3 = B.New({ store = KeepStore({ 5 }), slots = Bag(6, { 0, 1, 3, 4, 5 }), columns = 6 })
  bag3.live = true; local iss3 = {}
  bag3.moveQueue = ns.MoveQueue.New({ Pickup = function(b, s) iss3[#iss3 + 1] = s end }, function(i) return 0, i + 1 end)
  bag3:SetCursor("external"); ok(bag3:Drop(LockCell(bag3))); eq(iss3[1], 3)
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
