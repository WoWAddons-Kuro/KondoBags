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

local function Ref(bag, slot, itemID)
  return { bagID = bag, slot = slot, item = itemID and { itemID = itemID, name = "i" .. itemID } or nil }
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------
test("layout: incoming run is bottom-anchored, partial row on top right-aligned", function()
  local loose = { Ref(0, 1, 1), Ref(0, 2, 2), Ref(0, 3, 3), Ref(0, 4), Ref(0, 5), Ref(0, 6), Ref(0, 7) }
  local r = L.Build({ columns = 4, loose = loose, sections = {} })
  eq(#r.rows, 2)
  eq(#r.rows[1].cells, 3, "top partial"); eq(r.rows[1].cells[1].col, 2, "right-aligned")
  eq(#r.rows[2].cells, 4, "bottom full"); eq(r.rows[2].cells[4].ref.slot, 7)
  eq(r.rows[1].sectionID, nil)
end)

test("layout: a section is one drop cell then its items, below incoming", function()
  local sec = { id = "s1", name = "Keep", slots = { Ref(0, 9, 6948) } }
  local r = L.Build({ columns = 4, loose = { Ref(0, 1) }, sections = { sec } })
  eq(#r.rows, 2)
  eq(r.rows[2].sectionID, "s1")
  eq(#r.rows[2].cells, 2, "drop + hearthstone")
  eq(r.rows[2].cells[1].kind, L.CELL_DROP); eq(r.rows[2].cells[1].col, 3, "drop sits left of item")
  eq(r.rows[2].cells[2].kind, L.CELL_SLOT); eq(r.rows[2].cells[2].col, 4, "item bottom-right")
  eq(r.rows[2].cells[1].sectionID, "s1")
end)

test("layout: empty section still shows its drop cell", function()
  local r = L.Build({ columns = 4, loose = {}, sections = { { id = "s1", slots = {} } } })
  eq(#r.rows, 1); eq(#r.rows[1].cells, 1); eq(r.rows[1].cells[1].kind, L.CELL_DROP); eq(r.rows[1].cells[1].col, 4)
end)

test("layout: runs never share a row; sections keep display order", function()
  local a = { id = "a", slots = { Ref(0, 1, 1) } }
  local b = { id = "b", slots = { Ref(0, 2, 2) } }
  local r = L.Build({ columns = 10, loose = { Ref(0, 3) }, sections = { a, b } })
  eq(#r.rows, 3)
  eq(r.rows[1].sectionID, nil); eq(r.rows[2].sectionID, "a"); eq(r.rows[3].sectionID, "b")
  eq(L.RowCount({ loose = { Ref(0, 3) }, sections = { a, b } }, 10), 3)
end)

-- ---------------------------------------------------------------------------
-- Sections (model)
-- ---------------------------------------------------------------------------
test("store: new store has one Keep section holding Hearthstone", function()
  local st = S.NewStore()
  eq(#st.list, 1); eq(st.list[1].name, "Keep"); ok(st.list[1].items[S.HEARTHSTONE_ID])
  eq(S.ItemCount(st.list[1]), 1)
end)

test("store: create / pin / unpin / sectionOf", function()
  local st = S.NewStore()
  local s1 = st.list[1]
  local s2 = S.Create(st, 200)
  eq(s2.id, "s2")
  ok(S.Pin(st, "s2", S.HEARTHSTONE_ID), "pin moves item")
  ok(not s1.items[S.HEARTHSTONE_ID] and s2.items[S.HEARTHSTONE_ID])
  ok(not S.Pin(st, "s2", S.HEARTHSTONE_ID), "re-pin is a no-op")
  ok(S.Unpin(st, 200)); ok(not S.SectionOf(st, 200))
  ok(not S.Pin(st, "nope", 1), "unknown section")
end)

test("store: ids never reused; reorder clamps", function()
  local st = S.NewStore()
  S.Create(st, 2); S.Create(st, 3)
  ok(S.Dissolve(st, "s2")); eq(S.Create(st, 4).id, "s4")
  ok(S.Reorder(st, "s4", 1)); eq(st.list[1].id, "s4")
  ok(not S.Reorder(st, "s4", 1)); ok(not S.Reorder(st, "zz", 1))
end)

test("partition: pinned items leave loose, same itemID twice both go", function()
  local st = S.NewStore()
  local slots = { Ref(0, 1, 6948), Ref(0, 2, 5), Ref(0, 3), Ref(1, 1, 6948) }
  local input = S.Partition(st, slots, 4)
  eq(#input.sections, 1); eq(#input.sections[1].slots, 2, "both hearthstones")
  eq(#input.loose, 2, "one item + one empty")
end)

-- ---------------------------------------------------------------------------
-- BagState (controller)
-- ---------------------------------------------------------------------------
local function NewState(slots)
  local st = B.New({ store = S.NewStore(), slots = slots, columns = 4 })
  local events = {}
  st:AddListener(function(e) events[#events + 1] = e end)
  return st, events
end

test("bagstate: pickup then drop on drop-cell pins; item stays in its slot", function()
  local cloth = Ref(0, 1, 2589)
  local st, events = NewState({ cloth, Ref(0, 2), Ref(0, 3, 6948) })
  ok(st:Pickup(cloth)); ok(st:IsHeld(cloth)); eq(events[#events], "cursor")
  local lay = st:Layout()
  local dropCell
  for _, row in ipairs(lay.rows) do for _, c in ipairs(row.cells) do if c.kind == L.CELL_DROP then dropCell = c end end end
  ok(dropCell, "keep section has a drop cell")
  ok(st:Drop(dropCell))
  ok(not st.held); eq(events[#events], "changed")
  eq(st:SectionOf(2589).name, "Keep")
  eq(cloth.bagID, 0); eq(cloth.slot, 1, "physical slot unchanged")
  eq(#st:Layout().rows, 2, "incoming row + keep row")
end)

test("bagstate: drop on a slot swaps (mock physical move)", function()
  local a, empty = Ref(0, 1, 10), Ref(0, 2)
  local st = NewState({ a, empty })
  st:Pickup(a); ok(st:Drop({ kind = L.CELL_SLOT, ref = empty }))
  ok(a.item == nil and empty.item and empty.item.itemID == 10)
end)

test("bagstate: drop with nothing held is ignored; drop on own slot just clears", function()
  local a = Ref(0, 1, 10)
  local st = NewState({ a })
  ok(not st:Drop({ kind = L.CELL_SLOT, ref = a }))
  st:Pickup(a); ok(st:Drop({ kind = L.CELL_SLOT, ref = a })); ok(a.item.itemID == 10); ok(not st.held)
end)

test("bagstate: pickup of an empty slot fails; SetColumns clamps", function()
  local st = NewState({ Ref(0, 1) })
  ok(not st:Pickup(st.slots[1]))
  ok(st:SetColumns(1)); eq(st.columns, L.MIN_COLUMNS)
  ok(st:SetColumns(99)); eq(st.columns, 24)
  ok(not st:SetColumns(24))
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