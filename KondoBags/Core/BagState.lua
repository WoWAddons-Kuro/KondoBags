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

function BagState.New(opts)
  local self = setmetatable({}, BagState)
  self.slots = IndexSlots(opts.slots or {})
  self.store = Sections.Reconcile(opts.store, #self.slots)
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
  for _, m in ipairs(moves) do
    local a, b = self.slots[m.from + 1], self.slots[m.to + 1]
    a.item, b.item = b.item, a.item
  end
end

-- ---------------------------------------------------------------------------
-- queries
-- ---------------------------------------------------------------------------
function BagState:SectionOfRef(ref) return ref and Sections.SectionOfSlot(self.store, ref.slotIndex) or nil end
function BagState:Section(sectionID) return Sections.Find(self.store, sectionID) end
function BagState:IsHeld(ref) return self.held ~= nil and self.held == ref end
function BagState:HeldItem() return self.held and self.held.item or nil end

-- Where the Shift-drag phantom goes: before the hovered kept item, or at the end when over the lock.
-- STICKY: opening the phantom shifts the hovered item one cell right, straight under the still mouse;
-- the view then reports a hover on that same item. That must not move the phantom again (it would
-- oscillate), so a hover on the item immediately right of the current phantom keeps the current point.
function BagState:InsertPoint()
  if not self.held or not self.insertMode then return nil end
  local c = self.hoverCell
  if not c or not c.sectionID then return nil end
  local cur = self.insertPoint
  local point
  if c.kind == Layout.CELL_SLOT and c.ref then
    if cur and cur.sectionID == c.sectionID and cur.beforeRef == c.ref then
      point = cur                                              -- same item we already insert before
    else
      point = { sectionID = c.sectionID, beforeRef = c.ref }
    end
  elseif c.kind == Layout.CELL_INSERT then
    point = cur or { sectionID = c.sectionID, beforeRef = c.beforeRef }   -- hovering the phantom itself
  elseif c.kind == Layout.CELL_DROP then
    point = { sectionID = c.sectionID, beforeRef = nil }     -- lock cell: at the end
  end
  self.insertPoint = point
  return point
end

local function ResetInsertPoint(self)
  self.insertPoint = nil
end

function BagState:Layout(columns)
  local input = Sections.Partition(self.store, self.slots, columns or self.columns)
  input.insertAt = self:InsertPoint()
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
  self.slots = IndexSlots(slots or {})
  self.store = Sections.Reconcile(self.store, #self.slots)
  self.held = nil
  self:Emit("changed")
end

function BagState:Pickup(ref)
  if not ref or not ref.item then return false end
  self.held = ref
  ResetInsertPoint(self)
  self:Emit("cursor")
  return true
end

function BagState:ClearCursor()
  if not self.held then return false end
  self.held = nil
  ResetInsertPoint(self)
  self:Emit("cursor")
  return true
end

function BagState:SetHover(cell)
  if self.hoverCell == cell then return end
  self.hoverCell = cell
  if self.held and self.insertMode then self:Emit("cursor") end
end

function BagState:SetInsertMode(on)
  on = on and true or false
  if self.insertMode == on then return end
  self.insertMode = on
  if not on then ResetInsertPoint(self) end
  if self.held then self:Emit("cursor") end
end

-- Pin a LOOSE held item into `section` (visually before `beforeRef`, or first). Physical: section
-- grows by taking slot boundary-1; the item is swapped there if it is not there already (D11).
local function PinHeld(self, held, section, beforeRef)
  local beforeSlot = beforeRef and beforeRef.slotIndex or nil
  local moves = Sections.PinFromIncoming(self.store, section, held.slotIndex, beforeSlot)
  self:ApplyMoves(moves)
end

-- Drop the held item on a layout cell. Returns true if the drop was consumed.
function BagState:Drop(cell)
  local held = self.held
  if not held or not cell then return false end
  local heldSec = self:SectionOfRef(held)
  local function done() self.held = nil; ResetInsertPoint(self); self:Emit("changed"); return true end

  -- Section targets: lock cell, Shift phantom, or any section cell while Shift is down.
  local targetSec = cell.sectionID and Sections.Find(self.store, cell.sectionID) or nil
  local insertCell = cell.kind == Layout.CELL_INSERT
  if targetSec and (cell.kind == Layout.CELL_DROP or insertCell or self.insertMode) then
    local point = insertCell and { beforeRef = cell.beforeRef }
      or (self.insertMode and self:InsertPoint()) or { beforeRef = nil }
    if cell.kind == Layout.CELL_SLOT and not self.insertMode then point = { beforeRef = cell.ref } end
    if heldSec == targetSec then
      -- reorder within the section (no physical move)
      if point.beforeRef then Sections.MoveBefore(targetSec, held.slotIndex, point.beforeRef.slotIndex)
      else Sections.MoveToEnd(targetSec, held.slotIndex) end
      return done()
    elseif heldSec == nil then
      -- M0: only the lowest section can grow (it borders incoming)
      if targetSec ~= self.store.list[1] then return false end
      PinHeld(self, held, targetSec, point.beforeRef)
      return done()
    end
    return false   -- section-to-section moves: not in M0
  end

  if cell.kind ~= Layout.CELL_SLOT or not cell.ref then return false end
  local target = cell.ref
  if target == held then return done() end

  if targetSec and heldSec == targetSec then
    -- kept onto kept, same section, no Shift: take its visual position
    Sections.MoveBefore(targetSec, held.slotIndex, target.slotIndex)
    return done()
  end

  if heldSec and not targetSec then
    -- kept -> incoming: leaves the section (D11 UnpinToIncoming; <= 2 moves)
    if heldSec ~= self.store.list[1] then return false end   -- M0: only the lowest section borders incoming
    local moves = Sections.UnpinToIncoming(heldSec, held.slotIndex, target.slotIndex, target.item ~= nil)
    self:ApplyMoves(moves)
    return done()
  end

  if not heldSec and targetSec then
    -- loose -> onto a kept item (no Shift): stock swap. Membership is by slot, so the loose item is
    -- now kept in that visual position and the kept one is loose where the held one was.
    self:ApplyMoves({ { from = held.slotIndex, to = target.slotIndex } })
    return done()
  end

  -- loose <-> loose: stock swap / place
  self:ApplyMoves({ { from = held.slotIndex, to = target.slotIndex } })
  return done()
end

return BagState