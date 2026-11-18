-- KondoBags -- bootstrap, saved variables, events, slash commands.
--
-- One bag source: LIVE (Client provider -> Core/Scan -> BagState, rescanned on BAG_UPDATE_DELAYED).
-- The window replaces the stock bags outright (SPECS/01): UI/StockBags.lua hooks the stock entry
-- points and routes to ns.ToggleBags / ns.OpenBags / ns.CloseBags below.

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
  KondoBagsDB.typedGlyph = KondoBagsDB.typedGlyph or "bag"               -- empty typed-slot art: "bag" (equipped bag's icon) | "kind" (item-type art)
  KondoBagsDB.ammoGlyph = nil                                             -- pre-release key, retired
  KondoBagsCharDB.version = KondoBagsCharDB.version or DB_VERSION
  KondoBagsCharDB.window = KondoBagsCharDB.window or { point = "CENTER", x = 0, y = 0, columns = 10 }
  KondoBagsCharDB.mockSections = nil                                      -- M0 mockup store, retired (SPECS/01 R5)
  -- Live store (KondoBagsCharDB.sections, SPECS/00 "Saved variables"): Reconcile validates it against
  -- the real bag on every scan; nil here means a fresh empty Keep at the top on first scan.
end

-- ---------------------------------------------------------------------------
-- the live bag
-- ---------------------------------------------------------------------------
local liveBag        -- the KondoBags_BagState attached to the window

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
  if ref then ns.Window.RefreshRef(ref) end
end

-- The bag the UI (Edit Mode, Options) acts on. Attaching builds the window (hidden) and renders it.
local attached = false
local function EnsureBag()
  local b = EnsureLive()
  if not attached then
    attached = true
    ns.Window.Attach({ bag = b, money = GetMoney and GetMoney() or 0, themeID = KondoBagsDB.theme })
    ns.EditMode.ApplyToWindow()
  end
  return b
end
ns.EnsureBag = EnsureBag

-- ---------------------------------------------------------------------------
-- window actions (called by UI/StockBags.lua hooks and /kondo)
-- ---------------------------------------------------------------------------
function ns.OpenBags()
  if ns.Window.IsShown() then return end
  if not ns.StockBags.AllowedToOpen() then return end
  EnsureBag()
  ns.Window.Show()
end
function ns.CloseBags()
  if ns.Window.IsShown() then ns.Window.Hide() end
end
function ns.ToggleBags()
  if ns.Window.IsShown() then ns.CloseBags() else ns.OpenBags() end
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
  ns.Window.SetMoney(GetMoney and GetMoney() or 0)
end

-- ---------------------------------------------------------------------------
-- slash
-- ---------------------------------------------------------------------------
local function Slash(msg)
  msg = (msg or ""):match("^%s*(.-)%s*$")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  if cmd == "" or cmd == "toggle" then
    ns.ToggleBags()
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
    ns.CloseBags()
    KondoBagsCharDB.sections = nil; liveBag = nil; attached = false
    if wasShown then ns.OpenBags() else EnsureBag() end
    Print("sections reset")
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
    Print("version %s | provider %s | %d general + %d typed slots | free %s"
      .. " | %d group(s), %d kept | theme %s | %d cols | edit mode: %s",
      tostring(version), ns.Client.Active().name, summary.general, summary.typed, table.concat(free, " "),
      #b.store.list, kept, KondoBagsDB.theme, KondoBagsCharDB.window.columns or 10, ns.EditMode.Status())
  else
    Print("/kondo - toggle bags | theme [classic|modern] | columns N | tint | reset | options | status")
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
    ns.StockBags.Setup()
    f:RegisterEvent("BAG_UPDATE")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:RegisterEvent("PLAYER_MONEY")
    f:RegisterEvent("ITEM_LOCK_CHANGED")
    f:RegisterEvent("CURSOR_CHANGED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    Print("loaded (%s). Stock bags replaced; /kondo status", ns.Client.Active().name)
  elseif event == "BAG_UPDATE" then
    dirty = true
  elseif event == "BAG_UPDATE_DELAYED" then
    OnBagsChanged()
  elseif event == "ITEM_LOCK_CHANGED" then
    OnItemLockChanged(arg1, arg2)
  elseif event == "CURSOR_CHANGED" then
    SyncCursor()
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- Pre-build (SPECS/01 R6): secure cells cannot be created in combat, so the window is built and
    -- rendered hidden now; a first open mid-combat still shows cells. Also clears login "new" flags.
    f:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if not InCombatLockdown() then EnsureBag() else ClearNewItems() end
  elseif event == "PLAYER_MONEY" then
    ns.Window.SetMoney(GetMoney and GetMoney() or 0)
  end
end)