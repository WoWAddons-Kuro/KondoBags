-- KondoBags Core/BagState.lua -- pure Lua. The CONTROLLER: owns the section store, the current slot
-- list and the held item, and decides what a gesture means. The view (UI/Window.lua) calls these
-- methods and redraws from BagState.Layout(); it never touches the store or slots itself.
--
-- No WoW API. In M0 the item source is the mock snapshot and "pickup"/"drop" swap table fields; in
-- M4 the same calls route to the Client provider (C_Container.PickupContainerItem etc.) and the
-- held-item state comes from the real cursor. The view does not change.
--
--   KondoBags_BagState = {
--     store    = KondoBags_SectionStore,       -- per-character, persisted by the owner
--     slots    = { KondoBags_SlotRef... },     -- current contents, bag order
--     columns  = number,
--     held     = KondoBags_SlotRef | nil,      -- the slot whose item is on the (mock) cursor
--     listeners = { fn(event: KondoBags_BagStateEvent)... },
--   }
--   KondoBags_BagStateEvent = "changed" | "cursor"
--
--   Drop targets (KondoBags_LayoutCell.kind):
--     drop  -> pin held item into cell.sectionID  (logical; the item does not move)
--     slot  -> physical swap/place with that slot (stock behaviour)

local _, ns = ...
ns = ns or {}
local Sections, Layout = ns.Sections, ns.Layout
local BagState = {}
BagState.__index = BagState
ns.BagState = BagState

function BagState.New(opts)
  local self = setmetatable({}, BagState)
  self.store = opts.store
  self.slots = opts.slots or {}
  self.columns = opts.columns or 10
  self.held = nil
  self.hoverCell = nil        -- KondoBags_LayoutCell under the mouse (view reports it)
  self.insertMode = false     -- Shift held while carrying: show a phantom insert cell at the hover
  self.listeners = {}
  return self
end

function BagState:AddListener(fn) self.listeners[#self.listeners + 1] = fn end

function BagState:Emit(event)
  for _, fn in ipairs(self.listeners) do fn(event, self) end
end

-- ---------------------------------------------------------------------------
-- queries (what the view reads)
-- ---------------------------------------------------------------------------
-- Where the phantom insert cell goes right now, or nil. Only while carrying, Shift down, and the
-- mouse is over a section (any cell of one). Hovering an item = insert before it; hovering the
-- lock or the section's insert cell itself = keep the current spot; hovering nothing in a section = nil.
function BagState:InsertPoint()
  if not self.held or not self.insertMode then return nil end
  local c = self.hoverCell
  if not c or not c.sectionID then return nil end
  if c.kind == Layout.CELL_SLOT and c.ref then
    return { sectionID = c.sectionID, beforeRef = c.ref }
  elseif c.kind == Layout.CELL_INSERT then
    return { sectionID = c.sectionID, beforeRef = c.beforeRef }
  elseif c.kind == Layout.CELL_DROP then
    return { sectionID = c.sectionID, beforeRef = nil }   -- lock cell: insert goes to the end
  end
  return nil
end

function BagState:Layout(columns)
  columns = columns or self.columns
  local input = Sections.Partition(self.store, self.slots, columns)
  input.insertAt = self:InsertPoint()
  return Layout.Build(input)
end

function BagState:RowCount(columns)
  return #self:Layout(columns).rows
end

function BagState:IsHeld(ref) return self.held ~= nil and self.held == ref end
function BagState:HeldItem() return self.held and self.held.item or nil end
function BagState:SectionOf(itemID) return Sections.SectionOf(self.store, itemID) end
function BagState:Section(sectionID) return Sections.Find(self.store, sectionID) end

-- ---------------------------------------------------------------------------
-- commands (what the view calls)
-- ---------------------------------------------------------------------------
function BagState:SetColumns(n)
  n = math.max(Layout.MIN_COLUMNS, math.min(24, n))
  if n == self.columns then return false end
  self.columns = n
  self:Emit("changed")
  return true
end

function BagState:SetSlots(slots)
  self.slots = slots or {}
  self.held = nil
  self:Emit("changed")
end

-- Pick up the item in `ref`. Returns true if something is now held.
function BagState:Pickup(ref)
  if not ref or not ref.item then return false end
  self.held = ref
  self:Emit("cursor")
  return true
end

function BagState:ClearCursor()
  if not self.held then return false end
  self.held = nil
  self:Emit("cursor")
  return true
end

-- View reports the cell under the mouse (nil when leaving). Only matters in insert mode.
function BagState:SetHover(cell)
  if self.hoverCell == cell then return end
  self.hoverCell = cell
  if self.held and self.insertMode then self:Emit("cursor") end
end

-- View reports Shift state (MODIFIER_STATE_CHANGED). Toggling re-flows the layout while carrying.
function BagState:SetInsertMode(on)
  on = on and true or false
  if self.insertMode == on then return end
  self.insertMode = on
  if self.held then self:Emit("cursor") end
end

-- Put the held item at an insert point: into that section, before beforeRef (nil = end).
local function InsertHeldAt(self, held, point)
  local itemID = held.item.itemID
  Sections.Pin(self.store, point.sectionID, itemID)          -- membership (no-op if already there)
  if point.beforeRef and point.beforeRef.item and point.beforeRef.item.itemID ~= itemID then
    Sections.MoveBefore(self.store, itemID, point.beforeRef.item.itemID)
  else
    Sections.MoveToEnd(self.store, itemID)
  end
end

-- Drop the held item on a layout cell. Returns true if the drop was consumed.
function BagState:Drop(cell)
  local held = self.held
  if not held or not cell then return false end
  if cell.kind == Layout.CELL_INSERT then
    InsertHeldAt(self, held, { sectionID = cell.sectionID, beforeRef = cell.beforeRef })
    self.held = nil
    self:Emit("changed")
    return true
  elseif self.insertMode and cell.sectionID then
    -- Shift held: whatever section cell we are over, land at the phantom spot shown there
    local point = self:InsertPoint() or { sectionID = cell.sectionID, beforeRef = cell.ref }
    InsertHeldAt(self, held, point)
    self.held = nil
    self:Emit("changed")
    return true
  elseif cell.kind == Layout.CELL_DROP then
    Sections.Pin(self.store, cell.sectionID, held.item.itemID)
    self.held = nil
    self:Emit("changed")
    return true
  elseif cell.kind == Layout.CELL_SLOT and cell.ref then
    local target = cell.ref
    if target ~= held then
      local heldSec = Sections.SectionOf(self.store, held.item.itemID)
      local targetSec = target.item and Sections.SectionOf(self.store, target.item.itemID)
      if heldSec and heldSec == targetSec then
        -- both kept in the same section: reorder the row (logical); the held item lands where the
        -- target was and nothing moves physically
        Sections.MoveBefore(self.store, held.item.itemID, target.item.itemID)
      else
        target.item, held.item = held.item, target.item    -- mock physical swap/place
      end
    end
    self.held = nil
    self:Emit("changed")
    return true
  end
  return false
end

function BagState:Unpin(itemID)
  if Sections.Unpin(self.store, itemID) then self:Emit("changed"); return true end
  return false
end

return BagState