-- KondoBags off-client tests. Run from the repo root:   lua5.1 spec/run.lua
-- Only Core/ is under test; Core files take (addonName, ns) via ... like the game does.

local function LoadCore(file)
  local ns = {}
  local chunk = assert(loadfile("KondoBags/Core/" .. file))
  chunk("KondoBags", ns)
  return ns
end

local tests, failures = {}, 0
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end
local function eq(a, b, msg)
  if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function ok(v, msg) if not v then error(msg or "expected true", 2) end end

local S = LoadCore("Sections.lua").Sections

local function Ref(bag, slot, itemID)
  return { bagID = bag, slot = slot, item = itemID and { itemID = itemID, name = "i" .. itemID } or nil }
end

-- ---------------------------------------------------------------------------
test("layout: fresh character = one plus cell then loose slots", function()
  local loose = { Ref(0, 1, 10), Ref(0, 2), Ref(0, 3) }
  local r = S.Layout({ columns = 4, sections = {}, loose = loose })
  eq(#r.rows, 1, "rows")
  eq(r.rows[1].cells[1].kind, S.CELL_PLUS, "first cell is +")
  eq(#r.rows[1].cells, 4, "plus + 3 slots")
  eq(r.rows[1].dividerAbove, false, "no divider on first run")
  eq(r.cellCount, 4)
end)

test("layout: section = items then handle, divider only after first run", function()
  local sec = { id = "s1", name = "A", slots = { Ref(0, 1, 10), Ref(0, 2, 11) } }
  local r = S.Layout({ columns = 4, sections = { sec }, loose = { Ref(0, 3) } })
  eq(#r.rows, 2)
  eq(r.rows[1].cells[3].kind, S.CELL_HANDLE, "handle after items")
  eq(r.rows[1].cells[3].sectionID, "s1")
  eq(r.rows[1].dividerAbove, false, "first run has no divider")
  eq(r.rows[2].dividerAbove, true, "loose run gets a divider")
  eq(r.rows[2].cells[1].kind, S.CELL_PLUS)
end)

test("layout: handle alone on a new row when items fill the width exactly", function()
  local sec = { id = "s1", slots = { Ref(0, 1, 1), Ref(0, 2, 2), Ref(0, 3, 3), Ref(0, 4, 4) } }
  local r = S.Layout({ columns = 4, sections = { sec }, loose = {} })
  eq(#r.rows, 3, "4 items, lone handle row, plus row")
  eq(#r.rows[2].cells, 1)
  eq(r.rows[2].cells[1].kind, S.CELL_HANDLE)
  eq(r.rows[2].dividerAbove, false, "same section, no divider mid-run")
end)

test("layout: runs never share a row", function()
  local a = { id = "a", slots = { Ref(0, 1, 1) } }
  local b = { id = "b", slots = { Ref(0, 2, 2) } }
  local r = S.Layout({ columns = 10, sections = { a, b }, loose = {} })
  eq(#r.rows, 3)
  eq(r.rows[1].sectionID, "a"); eq(r.rows[2].sectionID, "b"); eq(r.rows[3].sectionID, nil)
  eq(r.rows[2].dividerAbove, true); eq(r.rows[3].dividerAbove, true)
end)

-- ---------------------------------------------------------------------------
test("store: create / pin / unpin / sectionOf", function()
  local st = S.NewStore()
  local s1 = S.Create(st, 100)
  eq(s1.id, "s1"); ok(s1.items[100])
  ok(S.SectionOf(st, 100) == s1)
  local s2 = S.Create(st, 200)
  eq(s2.id, "s2")
  ok(S.Pin(st, "s2", 100), "pin moves item")
  ok(not s1.items[100] and s2.items[100], "removed from s1, in s2")
  ok(not S.Pin(st, "s2", 100), "re-pin is a no-op")
  ok(S.Unpin(st, 100)); ok(not S.SectionOf(st, 100))
  ok(not S.Pin(st, "nope", 1), "unknown section")
end)

test("store: ids are never reused after dissolve", function()
  local st = S.NewStore()
  S.Create(st, 1); S.Create(st, 2)
  ok(S.Dissolve(st, "s1"))
  local s3 = S.Create(st, 3)
  eq(s3.id, "s3")
  eq(#st.list, 2)
end)

test("store: reorder clamps and reports change", function()
  local st = S.NewStore()
  S.Create(st, 1); S.Create(st, 2); S.Create(st, 3)
  ok(S.Reorder(st, "s3", 1)); eq(st.list[1].id, "s3"); eq(st.list[2].id, "s1")
  ok(not S.Reorder(st, "s3", 1), "already there")
  ok(S.Reorder(st, "s1", 99)); eq(st.list[3].id, "s1", "clamped to end")
  ok(not S.Reorder(st, "zz", 1))
end)

test("partition: pinned items leave loose, same itemID twice both go", function()
  local st = S.NewStore()
  S.Create(st, 6948)
  local slots = { Ref(0, 1, 6948), Ref(0, 2, 5), Ref(0, 3), Ref(1, 1, 6948) }
  local input = S.Partition(st, slots, 4)
  eq(#input.sections, 1); eq(#input.sections[1].slots, 2, "both hearthstones")
  eq(#input.loose, 2, "one item + one empty")
  eq(input.columns, 4)
  eq(S.RowCount(input, 4), 2)
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