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
function BagState:Layout(columns)
  columns = columns or self.columns
  return Layout.Build(Sections.Partition(self.store, self.slots, columns))
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

-- Drop the held item on a layout cell. Returns true if the drop was consumed.
function BagState:Drop(cell)
  local held = self.held
  if not held or not cell then return false end
  if cell.kind == Layout.CELL_DROP then
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