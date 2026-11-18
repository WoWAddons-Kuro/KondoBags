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
  KondoBagsCharDB.version = KondoBagsCharDB.version or DB_VERSION
  KondoBagsCharDB.window = KondoBagsCharDB.window or { point = "CENTER", x = 0, y = 0, columns = 10 }
  -- Mock store: a fresh one keeps just the top slot (the mock's hearthstone) in the default Keep group.
  local store = KondoBagsCharDB.mockSections
  local slotCount = 22   -- the mock's general slots (16 + 6); typed bags are not in the flat index
  if type(store) ~= "table" or type(store.list) ~= "table" or type(store.boundary) ~= "number" then
    store = ns.Sections.NewStore(slotCount)
    store.boundary = slotCount - 1
    store.list[1].order = { slotCount - 1 }
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

local function EnsureLive()
  if liveBag then return liveBag end
  liveBag = ns.BagState.New({
    store = KondoBagsCharDB.sections,
    slots = LiveScan(),
    columns = KondoBagsCharDB.window.columns or 10,
  })
  KondoBagsCharDB.sections = liveBag.store        -- Reconcile may have replaced it
  liveBag:AddListener(function(event, b) if event == "changed" then KondoBagsCharDB.window.columns = b.columns end end)
  liveBag.readOnly = true                          -- step 2: no gestures until the real cursor is wired (step 4)
  return liveBag
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
  dirty = false
  liveBag:SetSlots(LiveScan())
  KondoBagsCharDB.sections = liveBag.store
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
    Print("version %s | source %s | provider %s | %d general + %d typed slots | free %s | %d group(s), boundary %d | theme %s | %d cols | edit mode: %s",
      tostring(version), source or "-", ns.Client.Active().name, summary.general, summary.typed, table.concat(free, " "),
      #b.store.list, b.store.boundary, KondoBagsDB.theme, KondoBagsCharDB.window.columns or 10, ns.EditMode.Status())
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
f:SetScript("OnEvent", function(_, event, arg1)
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
    Print("loaded (%s). /kondo to open your bags, /kondo mock for the mockup, /kondo status", ns.Client.Active().name)
  elseif event == "BAG_UPDATE" then
    dirty = true
  elseif event == "BAG_UPDATE_DELAYED" then
    OnBagsChanged()
  elseif event == "PLAYER_MONEY" then
    if source == "live" then ns.Window.SetMoney(GetMoney and GetMoney() or 0) end
  end
end)