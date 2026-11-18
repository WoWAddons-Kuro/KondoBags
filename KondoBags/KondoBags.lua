-- KondoBags -- bootstrap, saved variables, slash commands.
-- M0: the window is a mockup over Mock/MockSnapshot.lua. No bag API is read yet.

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
  KondoBagsCharDB.version = KondoBagsCharDB.version or DB_VERSION
  -- Sections live per character (SPECS/00 D2). Mock sections are kept apart so play data is never
  -- polluted by the mockup.
  local store = KondoBagsCharDB.mockSections
  -- D12 store: ONE keep-wide boundary plus visual groups. Stores from earlier builds (per-item sets,
  -- or a per-section boundary) have no store.boundary and are replaced. A fresh store keeps just the
  -- top slot (the mock's hearthstone) in the default Keep group.
  local slotCount = #ns.Mock.Slots()
  if type(store) ~= "table" or type(store.list) ~= "table" or type(store.boundary) ~= "number" then
    store = ns.Sections.NewStore(slotCount)
    store.boundary = slotCount - 1
    store.list[1].order = { slotCount - 1 }
    KondoBagsCharDB.mockSections = store
  end
  KondoBagsCharDB.window = KondoBagsCharDB.window or { point = "CENTER", x = 0, y = 0, columns = 10 }
end

local bag   -- KondoBags_BagState (controller); created on first open

local function EnsureBag()
  if bag then return bag end
  bag = ns.BagState.New({
    store = KondoBagsCharDB.mockSections,
    slots = ns.Mock.Slots(),
    columns = KondoBagsCharDB.window.columns or 10,
  })
  bag:AddListener(function(event, b)
    if event == "changed" then KondoBagsCharDB.window.columns = b.columns end
  end)
  ns.Window.Attach({ bag = bag, money = ns.Mock.Money(), themeID = KondoBagsDB.theme })
  return bag
end
ns.EnsureBag = EnsureBag

local function OpenMock()
  EnsureBag()
  ns.EditMode.ApplyToWindow()
  ns.Window.Toggle()
end

local function Slash(msg)
  msg = (msg or ""):match("^%s*(.-)%s*$")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  if cmd == "" or cmd == "mock" then
    OpenMock()
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
  elseif cmd == "reset" then
    KondoBagsCharDB.mockSections = nil; InitDB()
    local wasShown = ns.Window.IsShown()
    bag = nil
    ns.Window.Hide()
    if wasShown then OpenMock() end
    Print("mock sections and items reset")
  elseif cmd == "status" then
    local version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON_NAME, "Version")
    local n = #KondoBagsCharDB.mockSections.list
    Print("version %s | theme %s | %d columns | %d mock section(s) | edit mode: %s | project %s",
      tostring(version), KondoBagsDB.theme, KondoBagsCharDB.window.columns or 10, n, ns.EditMode.Status(), tostring(WOW_PROJECT_ID))
  else
    Print("/kondo - toggle mock window | theme [classic|modern] | columns N | reset | status")
  end
end

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
    ns.EditMode.Setup()
    Print("M0 mockup loaded. /kondo to open, /kondo theme modern, /kondo status")
  end
end)