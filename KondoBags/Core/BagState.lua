-- KondoBags Core/BagState.lua -- pure Lua. The CONTROLLER: owns the section store, the current slot
-- list and the held item, and decides what a gesture means for the store (SPECS/00 D15): every
-- gesture is one map edit plus at most ONE server operation. The view (UI/Window.lua) calls these
-- methods and redraws from BagState:Layout().
--
-- No WoW API. MOCK: the ref table is the bag and gestures swap it directly. LIVE: the one op goes
-- through self.moveQueue (a single PickupContainerItem) and the held item is the real cursor.
--
--   KondoBags_BagState = {
--     store      = KondoBags_SectionStore,     -- per-character, persisted by the owner
--     slots      = { KondoBags_SlotRef... },   -- index i = slot i-1; ref.slotIndex = i-1 (combined order)
--     columns    = number,
--     held       = KondoBags_SlotRef | nil,    -- the slot whose item is on the (mock) cursor
--     hoverCell  = KondoBags_LayoutCell | nil,
--     insertMode = bool,                       -- Shift held while carrying
--     listeners  = { fn(event: KondoBags_BagStateEvent, self)... },
--   }
--   KondoBags_BagStateEvent = "changed" | "cursor"

local _, ns = ...
ns = ns or {}
local Sections, Layout = ns.Sections, ns.Layout
local BagState = {}
BagState.__index = BagState
ns.BagState = BagState

-- Give every ref its 0-based combined slot index. Idempotent.
local function IndexSlots(slots)
  for i, ref in ipairs(slots) do ref.slotIndex = i - 1 end
  return slots
end

-- Split the bag-order ref list into the GENERAL flat list (indexed, participates in incoming/Keep)
-- and the typed list (restricted-bag slots, display only). ref.kind nil counts as "general".
local function SplitSlots(all)
  local general, typed = {}, {}
  for _, ref in ipairs(all) do
    if ref.kind and ref.kind ~= "general" then typed[#typed + 1] = ref else general[#general + 1] = ref end
  end
  return IndexSlots(general), typed
end

function BagState.New(opts)
  local self = setmetatable({}, BagState)
  self.slots, self.typedSlots = SplitSlots(opts.slots or {})
  self.store = Sections.Reconcile(opts.store, #self.slots, self.slots)
  self.columns = opts.columns or 10
  self.held = nil
  self.hoverCell = nil
  self.insertMode = false
  self.listeners = {}
  return self
end

function BagState:AddListener(fn) self.listeners[#self.listeners + 1] = fn end
function BagState:Emit(event) for _, fn in ipairs(self.listeners) do fn(event, self) end end

-- ---------------------------------------------------------------------------
-- cursor
-- LIVE: the real cursor. The view calls this on CURSOR_CHANGED with the ref the cursor item came
-- from (nil = empty cursor), or the string "external" for an item from outside the bag (bank, mail).
-- `heldFamily` = KondoBags_ItemFamilyBits of the carried item (C_Item.GetItemFamily; 0 = ordinary),
-- so the view can mark typed slots that would refuse it (Client.ItemFitsKind).
function BagState:SetCursor(refOrExternal, heldFamily)
  if self.held == refOrExternal and self.heldFamily == heldFamily then return end
  self.held = refOrExternal
  self.heldFamily = refOrExternal and (heldFamily or 0) or nil
  if not self.held then self.cursorGap = nil end
  self:Emit("cursor")
end

-- Would the carried item fit a slot of `kind`? Always true with nothing carried.
function BagState:HeldFits(kind)
  if not self.held then return true end
  return ns.Client.ItemFitsKind(self.heldFamily, kind)
end

-- ---------------------------------------------------------------------------
-- queries
-- ---------------------------------------------------------------------------
function BagState:SectionOfRef(ref) return ref and Sections.SectionOfSlot(self.store, ref.slotIndex) or nil end
function BagState:Section(sectionID) return Sections.Find(self.store, sectionID) end
function BagState:IsHeld(ref) return self.held ~= nil and self.held == ref end
function BagState:HeldItem() return self.held and self.held.item or nil end

-- The Shift-drag CURSOR GAP (KondoBags_CursorGap): the phantom cell drawn UNDER THE MOUSE while an
-- item is carried with Shift down. Anchored to the kept item that was hovered (anchorRef) or to the
-- lock (anchorRef nil); Layout draws the gap in the anchor's column and slides the anchor one cell left.
-- THE RULE (owner, 2026-11-18): the gap opens where the mouse is and does NOT move again until the
-- mouse enters a cell naming a DIFFERENT anchor. Re-renders, the anchor sliding under the still
-- cursor, hovering the gap itself, OnLeave noise: none of that moves it.
function BagState:CursorGap()
  if not self.held or not self.insertMode then return nil end
  -- A stored fact (set by UpdateCursorGap), never derived from the current hover on read.
  -- the mouse enters a cell that names a DIFFERENT target. It is a stored fact (set by
  -- UpdateCursorGap), never derived from the current hover on read.
  return self.cursorGap
end

-- What a hovered cell targets: the slot it shows (insert before it), or "end" over the lock.
-- nil for cells outside a section and for the phantom itself.
local function AnchorForCell(c)
  if not c or not c.sectionID then return nil end
  if c.kind == Layout.CELL_SLOT and c.ref then return c.ref, c.ref.slotIndex end
  if c.kind == Layout.CELL_DROP then return nil, "lock" end
  return nil
end

-- Move the phantom only if the hovered cell names a different target than the current point.
local function UpdateCursorGap(self)
  local c = self.hoverCell
  local anchorRef, key = AnchorForCell(c)
  if key == nil then return false end                               -- phantom / off-section: hold
  local cur = self.cursorGap
  if cur and cur.sectionID == c.sectionID and cur.key == key then return false end
  self.cursorGap = { sectionID = c.sectionID, anchorRef = anchorRef, key = key }
  return true
end

local function CloseCursorGap(self)
  self.cursorGap = nil
end

function BagState:Layout(columns)
  local input = Sections.Partition(self.store, self.slots, columns or self.columns, self.typedSlots)
  input.cursorGap = self:CursorGap()
  -- D14: an external cursor item with no free general slot cannot be pinned; hide the targets.
  if self.held == "external" then
    input.hideLocks = Sections.TopLeftHole(self.store, self:IsFreeFn()) == nil
  end
  return Layout.Build(input)
end

function BagState:RowCount(columns) return #self:Layout(columns).rows end

-- ---------------------------------------------------------------------------
-- commands
-- ---------------------------------------------------------------------------
function BagState:SetColumns(n)
  n = math.max(Layout.MIN_COLUMNS, math.min(24, n))
  if n == self.columns then return false end
  self.columns = n
  self:Emit("changed")
  return true
end

function BagState:SetSlots(slots)
  self.slots, self.typedSlots = SplitSlots(slots or {})
  self.store = Sections.Reconcile(self.store, #self.slots, self.slots)
  self.held = nil
  self:Emit("changed")
end

function BagState:Pickup(ref)
  if not ref or not ref.item then return false end
  if self.readOnly then return false end          -- live bag before the real cursor is wired (Phase L step 4)
  self.held = ref
  CloseCursorGap(self)
  self:Emit("cursor")
  return true
end

function BagState:ClearCursor()
  if not self.held then return false end
  self.held = nil
  CloseCursorGap(self)
  self:Emit("cursor")
  return true
end

function BagState:SetHover(cell)
  if self.hoverCell == cell then return end
  self.hoverCell = cell
  if self.held and self.insertMode and UpdateCursorGap(self) then self:Emit("cursor") end
end

-- Same as SetHover but never emits: for the view's post-render re-sync, which must not trigger

function BagState:SetInsertMode(on)
  on = on and true or false
  if self.insertMode == on then return end
  self.insertMode = on
  if on then UpdateCursorGap(self) else CloseCursorGap(self) end   -- open where the mouse already is
  if self.held then self:Emit("cursor") end
end

-- LIVE: a store change must land WITH the one server op, not before -- otherwise the view draws the
-- new store against the old bag for a frame or two and a mid-flight Reconcile trusts that. Live
-- gestures run on a COPY; the copy is committed from the queue's onDone (zero ops = commit now).
local function CopyStore(store)
  local c = { nextID = store.nextID, map = {}, kept = {}, list = {} }
  for v, s in ipairs(store.map) do c.map[v] = s end
  for s, gid in pairs(store.kept) do c.kept[s] = gid end
  for i, g in ipairs(store.list) do
    local o = {}
    for k, s in ipairs(g.order) do o[k] = s end
    c.list[i] = { id = g.id, name = g.name, order = o }
  end
  return c
end

local function LiveGesture(self, fn)
  local copy = CopyStore(self.store)
  local ops = fn(copy)
  if ops == nil then return false end
  -- A drop made in combat cannot be drawn until combat ends (secure cells are locked). Flag it so
  -- the view can say so; the view clears movePending when it finally renders.
  local P = ns.Client and ns.Client.Active and ns.Client.Active()
  if P and P.InCombat and P.InCombat() then self.movePending = true end
  local function commit() self.store = copy end
  if #ops == 0 then commit(); self.cursorGap = nil; self:Emit("changed"); return true end
  self.moveQueue:Push(ops, commit)
  self.cursorGap = nil; self:Emit("changed"); return true
end

function BagState:IsFreeFn()
  return function(slot) local r = self.slots[slot + 1]; return r ~= nil and r.item == nil end
end

-- Drop the held item on a layout cell. Returns true if the drop was consumed.
function BagState:Drop(cell)
  local held = self.held
  if not held or not cell then return false end
  local isFree = self:IsFreeFn()
  local function opsFor(ops)   -- KondoBags_PinOp { slotIndex } -> queue op { place, bagID, slot }
    local out = {}
    for i, o in ipairs(ops) do local r = self.slots[o.slotIndex + 1]; out[i] = { place = true, bagID = r.bagID, slot = r.slot } end
    return out
  end

  -- LIVE (D14 + D15): only lock / gap cells reach us; slot cells are Blizzard's.
  if self.live then
    local targetGroupID = cell.sectionID
    if not targetGroupID or (cell.kind ~= Layout.CELL_DROP and cell.kind ~= Layout.CELL_GAP) then return false end
    local anchorRef = cell.kind == Layout.CELL_GAP and cell.anchorRef or nil
    local anchorSlot = anchorRef and anchorRef.slotIndex or nil
    return LiveGesture(self, function(store)
      local group = Sections.Find(store, targetGroupID)
      if not group then return nil end
      local fromOutside = held == "external" or (held.kind ~= nil and held.kind ~= "general")
      if fromOutside then
        local ops = Sections.PinFromOutside(store, group, anchorSlot, isFree)   -- steals the top-left hole; one Pickup
        if not ops then return nil end
        return opsFor(ops)
      end
      if Sections.IsKept(store, held.slotIndex) then
        -- Kept item re-ordered (same or another group): a map edit only, but the item is on the REAL
        -- cursor (D14), so ONE Pickup on its own slot drops it back -- otherwise the player had to
        -- click once more to finish the drop.
        Sections.MoveToGap(store, group, held.slotIndex, anchorSlot)
        return { { place = true, bagID = held.bagID, slot = held.slot } }
      end
      -- Loose item from incoming on the cursor: mark its slot kept; ONE Pickup on its own slot puts it back.
      if not Sections.Pin(store, group, held.slotIndex, anchorSlot, isFree) then return nil end
      return { { place = true, bagID = held.bagID, slot = held.slot } }
    end)
  end

  -- MOCK: the table IS the bag; gestures apply synchronously, then ReorderHoles like a scan would.
  local function done()
    Sections.ReorderHoles(self.store, isFree)
    self.held = nil; CloseCursorGap(self); self:Emit("changed"); return true
  end
  local function refuse() self.held = nil; CloseCursorGap(self); self:Emit("cursor"); return false end
  local heldTyped = held.kind ~= nil and held.kind ~= "general"
  local targetGroup = cell.sectionID and Sections.Find(self.store, cell.sectionID) or nil
  local onGap = cell.kind == Layout.CELL_GAP
  local anchorRef
  if onGap then anchorRef = cell.anchorRef
  elseif self.insertMode then local gap = self:CursorGap(); anchorRef = gap and gap.anchorRef or nil end
  local anchorSlot = anchorRef and anchorRef.slotIndex or nil

  if heldTyped then
    if targetGroup and (cell.kind == Layout.CELL_DROP or onGap) then
      local ops, h = Sections.PinFromOutside(self.store, targetGroup, anchorSlot, isFree)
      if not ops then return refuse() end
      self.slots[h + 1].item, held.item = held.item, nil
      return done()
    end
    local target = cell.kind == Layout.CELL_SLOT and cell.ref or nil
    if not target or target == held or not cell.typed or target.kind ~= held.kind then return refuse() end
    held.item, target.item = target.item, held.item
    return done()
  end
  if cell.typed then return refuse() end

  local heldKept = Sections.IsKept(self.store, held.slotIndex)
  if targetGroup and (cell.kind == Layout.CELL_DROP or onGap or self.insertMode) then
    if heldKept then Sections.MoveToGap(self.store, targetGroup, held.slotIndex, anchorSlot)
    else Sections.Pin(self.store, targetGroup, held.slotIndex, anchorSlot, isFree) end
    return done()
  end

  if cell.kind ~= Layout.CELL_SLOT or not cell.ref then return false end
  local target = cell.ref
  if target == held then return done() end
  local targetKept = Sections.IsKept(self.store, target.slotIndex)
  if heldKept and targetKept then
    Sections.MoveToPositionOf(self.store, held.slotIndex, target.slotIndex)
    return done()
  end
  -- Stock swap / place. Kept-ness follows the SLOT: an emptied kept slot leaves Keep (D13.1) and gets a
  -- new top-left position (Release).
  held.item, target.item = target.item, held.item
  if heldKept and held.item == nil then Sections.Release(self.store, held.slotIndex, isFree) end
  return done()
end

-- The + button: a new empty group drawn FIRST, directly under incoming.
function BagState:AddGroup(name)
  local g = Sections.Create(self.store, name)
  self:Emit("changed")
  return g
end

-- Right-click on a group's lock: remove the group; its slots become incoming (D15, zero moves).
function BagState:RemoveGroup(sectionID)
  if not Sections.Dissolve(self.store, sectionID, self:IsFreeFn()) then return false end
  self:Emit("changed")
  return true
end

return BagState
