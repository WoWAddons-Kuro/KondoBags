-- KondoBags -- bootstrap, saved variables, events, slash commands.
--
-- Two bag SOURCES share one window: LIVE (Client provider -> Core/Scan -> BagState, rescanned on
-- BAG_UPDATE_DELAYED) and MOCK (Mock/MockSnapshot, for the mockup). Each has its own section store
-- in KondoBagsCharDB so play data is never polluted by the mockup. /kondo = live, /kondo mock = mock.
-- Phase L step 2: live is READ-ONLY (gestures still run on the mock's table swaps; step 4 wires the
-- real cursor), so Drop is disabled on the live bag.

local ADDON_NAME, ns = ...
_G.KondoBags = ns

local DB_VERSION = 1

local function Print(fmt, ...) print("|cffb0b0b0KondoBags|r: " .. string.format(fmt, ...)) end
ns.Print = Print

local function InitDB()
  if type(KondoBagsDB) ~= "table" then KondoBagsDB = {} end
  if type(KondoBagsCharDB) ~= "table" then KondoBagsCharDB = {} end
  KondoBagsDB.version = KondoBagsDB.version or DB_VERSION
  KondoBagsDB.theme = KondoBagsDB.theme or "classic"
  if KondoBagsDB.kindTint == nil then KondoBagsDB.kindTint = true end   -- border tint on restricted-bag cells
  KondoBagsDB.ammoGlyph = KondoBagsDB.ammoGlyph or "pouch"               -- "pouch" (Blizzard slot art) | "ammo" (projectile icons)
  KondoBagsCharDB.version = KondoBagsCharDB.version or DB_VERSION
  KondoBagsCharDB.window = KondoBagsCharDB.window or { point = "CENTER", x = 0, y = 0, columns = 10 }
  -- Mock store: a fresh one keeps just the mock's hearthstone slot in the default Keep group (D15).
  local store = KondoBagsCharDB.mockSections
  if type(store) ~= "table" or type(store.list) ~= "table" or type(store.kept) ~= "table" or type(store.map) ~= "table" then
    store = ns.Sections.NewStore()
    store.kept[ns.Mock.HEARTHSTONE_SLOT] = store.list[1].id
    store.list[1].order = { ns.Mock.HEARTHSTONE_SLOT }
    KondoBagsCharDB.mockSections = store
  end
  -- Live store (KondoBagsCharDB.sections, SPECS/00 "Saved variables"): Reconcile validates it against
  -- the real bag on every scan; nil here means a fresh empty Keep at the top on first scan.
end

-- ---------------------------------------------------------------------------
-- bag sources
-- ---------------------------------------------------------------------------
local bag            -- the KondoBags_BagState currently attached to the window
local source         -- "live" | "mock"
local liveBag, mockBag

local function Attach(b, money)
  bag = b
  ns.Window.Attach({ bag = b, money = money, themeID = KondoBagsDB.theme })
end

local function EnsureMock()
  if mockBag then return mockBag end
  mockBag = ns.BagState.New({
    store = KondoBagsCharDB.mockSections,
    slots = ns.Mock.Slots(),
    columns = KondoBagsCharDB.window.columns or 10,
  })
  mockBag:AddListener(function(event, b) if event == "changed" then KondoBagsCharDB.window.columns = b.columns end end)
  return mockBag
end

local function LiveScan()
  return (ns.Scan.Refs(ns.Client.Active()))
end

-- "New item" glow. The client flags every slot new at login and only clears them when a stock bag
-- frame HIDES (ContainerFrame_OnHide -> UpdateNewItemList -> C_NewItems.RemoveNewItem). Our window
-- never shows those frames, so we do the same clear ourselves: on first scan (login state is not
-- "new") and whenever our window closes (anything looted while it was open has been seen).
local function ClearNewItems()
  if not (C_NewItems and C_NewItems.RemoveNewItem) then return end
  -- Straight from the provider, not liveBag: this must also run at login before any window exists.
  local P = ns.Client.Active()
  for _, bag in ipairs(P.BagIDs()) do
    for slot = 1, P.NumSlots(bag) do C_NewItems.RemoveNewItem(bag, slot) end
  end
end
ns.ClearNewItems = ClearNewItems

local function EnsureLive()
  if liveBag then return liveBag end
  liveBag = ns.BagState.New({
    store = KondoBagsCharDB.sections,
    slots = LiveScan(),
    columns = KondoBagsCharDB.window.columns or 10,
  })
  KondoBagsCharDB.sections = liveBag.store        -- Reconcile may have replaced it
  liveBag:AddListener(function(event, b) if event == "changed" then KondoBagsCharDB.window.columns = b.columns end end)
  liveBag.live = true                              -- secure cells; Blizzard owns slot gestures (D14)
  -- Physical moves (pin / unpin / dissolve) go through the MoveQueue one swap at a time. The flat
  -- index resolves to a bag/slot through the CURRENT ref list.
  liveBag.moveQueue = ns.MoveQueue.New(ns.Client.Active(), function(slotIndex)
    local ref = liveBag.slots[slotIndex + 1]
    return ref.bagID, ref.slot
  end)
  ClearNewItems()                                  -- login state is not "new"
  return liveBag
end

-- LIVE cursor -> BagState.held (D14). GetCursorInfo() tells us an item is held but not where it came
-- from; ITEM_LOCK_CHANGED(bag, slot) does: the slot that just LOCKED while the cursor filled is the
-- source. A locked slot we know is one of ours -> that ref; an item on the cursor with no locked slot
-- of ours -> "external" (bank, mail, trade, guild bank).
local lastLocked   -- { bagID, slot } of the most recent lock event
local function RefForBagSlot(bagID, slot)
  if not liveBag then return nil end
  for _, r in ipairs(liveBag.slots) do if r.bagID == bagID and r.slot == slot then return r end end
  for _, r in ipairs(liveBag.typedSlots) do if r.bagID == bagID and r.slot == slot then return r end end
  return nil
end
local function SyncCursor()
  if not liveBag then return end
  local kind = GetCursorInfo()
  if kind ~= "item" then liveBag:SetCursor(nil); return end
  local ref = lastLocked and RefForBagSlot(lastLocked.bagID, lastLocked.slot)
  if ref and ref.item and ref.item.locked then liveBag:SetCursor(ref) else liveBag:SetCursor("external") end
end
local function OnItemLockChanged(bagID, slot)
  if not liveBag or not slot then return end
  local ref = RefForBagSlot(bagID, slot)
  if ref and ref.item then
    local info = ns.Client.Active().SlotInfo(bagID, slot)
    ref.item.locked = info and info.locked or false
    if ref.item.locked then lastLocked = { bagID = bagID, slot = slot } end
  end
  liveBag.moveQueue:OnLockChanged(ref and ref.item and ref.item.locked)
  SyncCursor()
  -- NO full render here: a lock fires in the middle of Blizzard's own pickup/drop on the secure
  -- button under the mouse; re-dressing / re-parenting it mid-gesture cancels the drag. Only the one
  -- cell's "locked" look changes, in place.
  if source == "live" and ref then ns.Window.RefreshRef(ref) end
end

-- The bag the UI (Edit Mode, Options) should act on: whichever is attached, else live.
local function EnsureBag()
  if bag then return bag end
  source = "live"
  Attach(EnsureLive(), GetMoney and GetMoney() or 0)
  return bag
end
ns.EnsureBag = EnsureBag

local function Open(which)
  if which ~= source then
    source = which
    if which == "mock" then Attach(EnsureMock(), ns.Mock.Money())
    else Attach(EnsureLive(), GetMoney and GetMoney() or 0) end
  end
  EnsureBag()
  ns.EditMode.ApplyToWindow()
  ns.Window.Toggle()
end

-- Event-driven rescan: BAG_UPDATE marks dirty, BAG_UPDATE_DELAYED (coalesced by the client) rescans.
-- Everything else (money) is cheap enough to refresh on the same tick.
local dirty = false
local function OnBagsChanged()
  if not dirty or not liveBag then return end
  -- While our own MoveQueue is mid-chain the bag is half-moved; a Reconcile now would "repair" the
  -- store against it. Feed the event to the queue (it completes the in-flight swap) and rescan the
  -- moment the queue drains -- the LAST BAG_UPDATE_DELAYED of a chain arrives while the queue is
  -- still marked busy, so without this the window never repainted after a pin.
  if liveBag.moveQueue:IsBusy() then
    liveBag.moveQueue.onDone = function() dirty = true; OnBagsChanged() end
    liveBag.moveQueue:OnBagUpdateDelayed()
    return
  end
  dirty = false
  liveBag:SetSlots(LiveScan())
  KondoBagsCharDB.sections = liveBag.store
  lastLocked = nil
  SyncCursor()
  if source == "live" then ns.Window.SetMoney(GetMoney and GetMoney() or 0) end
end

-- ---------------------------------------------------------------------------
-- slash
-- ---------------------------------------------------------------------------
local function Slash(msg)
  msg = (msg or ""):match("^%s*(.-)%s*$")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  if cmd == "" or cmd == "live" then
    Open("live")
  elseif cmd == "mock" then
    Open("mock")
  elseif cmd == "theme" then
    if rest == "" then
      Print("theme is %s (available: %s)", KondoBagsDB.theme, table.concat(ns.Theme.IDs(), ", "))
    else
      KondoBagsDB.theme = rest:lower()
      ns.Window.SetTheme(KondoBagsDB.theme)
      Print("theme %s", KondoBagsDB.theme)
    end
  elseif cmd == "columns" or cmd == "cols" then
    local n = tonumber(rest)
    if n then EnsureBag():SetColumns(n) end
    Print("%d columns", EnsureBag().columns)
  elseif cmd == "tint" then
    KondoBagsDB.kindTint = not KondoBagsDB.kindTint
    ns.Window.Render()
    Print("bag-type border tint %s", KondoBagsDB.kindTint and "on" or "off")
  elseif cmd == "reset" then
    local wasShown = ns.Window.IsShown()
    ns.Window.Hide()
    if source == "mock" then KondoBagsCharDB.mockSections = nil; InitDB(); mockBag = nil
    else KondoBagsCharDB.sections = nil; liveBag = nil end
    bag = nil; local was = source; source = nil
    if wasShown then Open(was or "live") end
    Print("%s sections reset", was or "live")
  elseif cmd == "options" or cmd == "config" or cmd == "settings" then
    ns.Options.Open()
  elseif cmd == "status" then
    local version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON_NAME, "Version")
    local b = EnsureBag()
    local _, summary = ns.Scan.Refs(ns.Client.Active())
    local free = {}
    for k, n in pairs(summary.free) do free[#free + 1] = k .. "=" .. n end
    table.sort(free)
    local kept = 0
    for _ in pairs(b.store.kept) do kept = kept + 1 end
    Print("version %s | source %s | provider %s | %d general + %d typed slots | free %s"
      .. " | %d group(s), %d kept | theme %s | %d cols | edit mode: %s",
      tostring(version), source or "-", ns.Client.Active().name, summary.general, summary.typed, table.concat(free, " "),
      #b.store.list, kept, KondoBagsDB.theme, KondoBagsCharDB.window.columns or 10, ns.EditMode.Status())
  else
    Print("/kondo - toggle live window | mock | theme [classic|modern] | columns N | tint | reset | options | status")
  end
end

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, arg1, arg2)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    InitDB()
    SLASH_KONDOBAGS1 = "/kondo"
    SLASH_KONDOBAGS2 = "/kondobags"
    SlashCmdList.KONDOBAGS = Slash
  elseif event == "PLAYER_LOGIN" then
    ns.Client.Select()
    ns.EditMode.Setup()
    ns.Options.Setup()
    f:RegisterEvent("BAG_UPDATE")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:RegisterEvent("PLAYER_MONEY")
    f:RegisterEvent("ITEM_LOCK_CHANGED")
    f:RegisterEvent("CURSOR_CHANGED")
    -- Login state is not "new": clear the client's new-item flags once bag data is available.
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    Print("loaded (%s). /kondo to open your bags, /kondo mock for the mockup, /kondo status", ns.Client.Active().name)
  elseif event == "BAG_UPDATE" then
    dirty = true
  elseif event == "BAG_UPDATE_DELAYED" then
    OnBagsChanged()
  elseif event == "ITEM_LOCK_CHANGED" then
    OnItemLockChanged(arg1, arg2)
  elseif event == "CURSOR_CHANGED" then
    SyncCursor()
  elseif event == "PLAYER_ENTERING_WORLD" then
    ClearNewItems()
    f:UnregisterEvent("PLAYER_ENTERING_WORLD")
  elseif event == "PLAYER_MONEY" then
    if source == "live" then ns.Window.SetMoney(GetMoney and GetMoney() or 0) end
  end
end)