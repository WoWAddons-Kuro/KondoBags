-- KondoBags Core/BagState.lua -- pure Lua. The CONTROLLER: owns the section store, the current slot
-- list and the held item, and decides what a gesture means in terms of PHYSICAL slot moves
-- (SPECS/00 D11). The view (UI/Window.lua) calls these methods and redraws from BagState:Layout().
--
-- No WoW API. In M0 ApplyMoves swaps table fields; in M4 it issues C_Container.PickupContainerItem
-- pairs through the Client provider and the held item comes from the real cursor. The view is unchanged.
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
-- physical moves
-- ---------------------------------------------------------------------------
-- Apply { KondoBags_SlotMove... } to the slot table: each is a swap of the two slots' contents.
function BagState:ApplyMoves(moves)
  -- LIVE: hand the list to self.moveQueue (Core/MoveQueue), which issues PickupContainerItem pairs
  -- one at a time; the real bag changes arrive via BAG_UPDATE_DELAYED -> SetSlots. We do NOT touch
  -- the ref table ourselves (the scan is the truth). MOCK: swap the table fields now.
  if self.live then
    if self.moveQueue and #moves > 0 then self.moveQueue:Push(moves) end
    return
  end
  for _, m in ipairs(moves) do
    local a, b = self.slots[m.from + 1], self.slots[m.to + 1]
    a.item, b.item = b.item, a.item
  end
end

-- LIVE: the real cursor. The view calls this on CURSOR_CHANGED with the ref the cursor item came
-- from (nil = empty cursor), or the string "external" for an item from outside the bag (bank, mail).
function BagState:SetCursor(refOrExternal)
  if self.held == refOrExternal then return end
  self.held = refOrExternal
  if not self.held then self.cursorGap = nil end
  self:Emit("cursor")
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
    local isFree = function(slot) local r = self.slots[slot + 1]; return r ~= nil and r.item == nil end
    input.hideLocks = Sections.LowestFree(self.store, #self.slots, isFree) == nil
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
  local c = { nextID = store.nextID, kept = {}, list = {} }
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
  local function commit() self.store = copy end
  if #ops == 0 then commit(); self.cursorGap = nil; self:Emit("changed"); return true end
  self.moveQueue:Push(ops, commit)
  self.cursorGap = nil; self:Emit("changed"); return true
end

-- Drop the held item on a layout cell. Returns true if the drop was consumed.
function BagState:Drop(cell)
  local held = self.held
  if not held or not cell then return false end
  local isFree = function(slot) local r = self.slots[slot + 1]; return r ~= nil and r.item == nil end
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
        -- ONE Pickup into the lowest free general slot (= the top-left free cell); mark it kept.
        local ops = Sections.PinFromOutside(store, group, anchorSlot, #self.slots, isFree)
        if not ops then return nil end
        return opsFor(ops)
      end
      if Sections.IsKept(store, held.slotIndex) then
        Sections.MoveToGap(store, group, held.slotIndex, anchorSlot)   -- visual reorder; item stays on the cursor
        return {}
      end
      -- Loose item from incoming, currently on the cursor: mark its slot kept (zero net moves) and put
      -- the item back where it came from with ONE Pickup on its own slot.
      if not Sections.Pin(store, group, held.slotIndex, anchorSlot) then return nil end
      return { { place = true, bagID = held.bagID, slot = held.slot } }
    end)
  end

  -- MOCK: the table IS the bag; gestures apply synchronously.
  local function done() self.held = nil; CloseCursorGap(self); self:Emit("changed"); return true end
  local function refuse() self.held = nil; CloseCursorGap(self); self:Emit("cursor"); return false end
  local heldTyped = held.kind ~= nil and held.kind ~= "general"
  local targetGroup = cell.sectionID and Sections.Find(self.store, cell.sectionID) or nil
  local onGap = cell.kind == Layout.CELL_GAP
  local anchorRef
  if onGap then anchorRef = cell.anchorRef
  elseif self.insertMode then local gap = self:CursorGap(); anchorRef = gap and gap.anchorRef or nil end
  local anchorSlot = anchorRef and anchorRef.slotIndex or nil

  if heldTyped then
    -- typed item: same-kind typed <-> typed is a stock swap; onto a lock = pin from outside (one place)
    if targetGroup and (cell.kind == Layout.CELL_DROP or onGap) then
      local ops, h = Sections.PinFromOutside(self.store, targetGroup, anchorSlot, #self.slots, isFree)
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
    else Sections.Pin(self.store, targetGroup, held.slotIndex, anchorSlot) end
    return done()
  end

  if cell.kind ~= Layout.CELL_SLOT or not cell.ref then return false end
  local target = cell.ref
  if target == held then return done() end
  local targetKept = Sections.IsKept(self.store, target.slotIndex)
  if heldKept and targetKept then
    Sections.MoveToPositionOf(self.store, held.slotIndex, target.slotIndex)   -- visual reorder
    return done()
  end
  -- Stock swap / place between any two general slots. Kept-ness follows the SLOT (D15): a kept item
  -- dropped on incoming leaves Keep; the incoming item that lands in a kept slot is now kept there.
  held.item, target.item = target.item, held.item
  if heldKept and held.item == nil then Sections.Unpin(self.store, held.slotIndex) end     -- D13.1: emptied kept slot leaves Keep
  return done()
end

-- The + button: a new empty group drawn FIRST, directly under incoming.
function BagState:AddGroup(name)
  local g = Sections.Create(self.store, name)
  self:Emit("changed")
  return g
end

-- Right-click on a group's lock: remove the group; its items drop into incoming (D11 moves).
function BagState:RemoveGroup(sectionID)
  -- D15: its slots simply become incoming; zero moves.
  if not Sections.Dissolve(self.store, sectionID) then return false end
  self:Emit("changed")
  return true
end

return BagState
