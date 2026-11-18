-- KondoBags Core/MoveQueue.lua -- pure Lua. Issues a list of KondoBags_SlotMove swaps to the
-- client ONE AT A TIME. No WoW API: the caller supplies the provider and feeds events in.
--
-- Why a queue: a pin chain-shift is several swaps and the client locks both slots of a swap until
-- the server answers (ITEM_LOCK_CHANGED). Issuing the next swap while a slot is still locked
-- silently fails. So: issue one swap (two PickupContainerItem calls), wait until every slot we
-- touched is unlocked again, issue the next. The swaps were computed against the bag as it was
-- when the gesture happened; BAG_UPDATE_DELAYED from our own moves must NOT trigger a Reconcile
-- mid-chain or the store would be repaired against a half-moved bag. The owner checks IsBusy().
--
--   KondoBags_MoveQueue = {
--     provider = KondoBags_ClientProvider,
--     resolve  = function(slotIndex) -> bagID, slot     -- flat index -> physical address
--     pending  = { KondoBags_SlotMove... },
--     inFlight = KondoBags_SlotMove | nil,
--     onDone   = function() | nil,
--   }

local _, ns = ...
ns = ns or {}
local MoveQueue = {}
MoveQueue.__index = MoveQueue
ns.MoveQueue = MoveQueue

function MoveQueue.New(provider, resolve)
  return setmetatable({ provider = provider, resolve = resolve, pending = {}, inFlight = nil }, MoveQueue)
end

function MoveQueue:IsBusy() return self.inFlight ~= nil or #self.pending > 0 end

-- Queue moves and start if idle. onDone fires once the whole list has been applied (or aborted).
function MoveQueue:Push(moves, onDone)
  for _, m in ipairs(moves or {}) do self.pending[#self.pending + 1] = m end
  self.onDone = onDone or self.onDone
  self:Step()
end

-- Issue the next swap if nothing is in flight. A swap of slot a with slot b is Pickup(a); Pickup(b):
-- the first puts a's item on the cursor, the second drops it into b and puts b's item (if any) on
-- the cursor... which the client then places into a (that is what PickupContainerItem does when
-- the cursor holds an item and the target is occupied). Two calls, one swap.
function MoveQueue:Step()
  if self.inFlight or #self.pending == 0 then
    if not self.inFlight and self.onDone then local f = self.onDone; self.onDone = nil; f() end
    return
  end
  local m = table.remove(self.pending, 1)
  self.inFlight = m
  self.unlocks = 0
  if m.place then
    -- Cursor already holds an item: ONE Pickup on the target drops it there (empty target) or
    -- swaps it with the target's item (which then sits on the cursor; the next op consumes it).
    -- ONE slot is touched, so ONE unlock completes it.
    self.needUnlocks = 1
    self.provider.Pickup(m.bagID, m.slot)
    return
  end
  self.needUnlocks = 2
  local ab, as = self.resolve(m.from)
  local bb, bs = self.resolve(m.to)
  self.provider.Pickup(ab, as)
  self.provider.Pickup(bb, bs)
end

-- Feed ITEM_LOCK_CHANGED here with the slot's NEW lock state. The in-flight op completes when every
-- slot it touched has reported an UNLOCK: one for a place, two for a swap. Requiring two for a place
-- stalled the chain until the player's next click produced another lock event (owner, 2026-11-18).
function MoveQueue:OnLockChanged(isLocked)
  if not self.inFlight then return end
  if isLocked == nil or isLocked == false then
    self.unlocks = (self.unlocks or 0) + 1
    if self.unlocks >= (self.needUnlocks or 2) then self:Complete() end
  end
end

function MoveQueue:OnBagUpdateDelayed() if self.inFlight then self:Complete() end end

function MoveQueue:Complete()
  self.inFlight = nil
  self.unlocks = 0
  self:Step()
end

-- Something went wrong (cursor lost, combat): drop what is left; the next Reconcile repairs the store.
function MoveQueue:Abort()
  self.pending = {}
  self.inFlight = nil
  self.unlocks = 0
  if self.onDone then local f = self.onDone; self.onDone = nil; f() end
end

return MoveQueue
