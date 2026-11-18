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
  KondoBagsCharDB.mockSections = KondoBagsCharDB.mockSections or ns.Sections.NewStore()
  KondoBagsCharDB.window = KondoBagsCharDB.window or { point = "CENTER", x = 0, y = 0, columns = 10 }
end

local mockSlots

local function OpenMock()
  mockSlots = mockSlots or ns.Mock.Slots()
  ns.Window.Setup({
    store = KondoBagsCharDB.mockSections,
    slots = mockSlots,
    money = ns.Mock.Money(),
    columns = KondoBagsCharDB.window.columns or 10,
    themeID = KondoBagsDB.theme,
    onChanged = function() end,   -- store is a live SavedVariables table; nothing to flush
  })
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
    if n then KondoBagsCharDB.window.columns = n; ns.Window.SetColumns(n) end
    Print("%d columns", ns.Window.GetColumns())
  elseif cmd == "reset" then
    KondoBagsCharDB.mockSections = ns.Sections.NewStore()
    mockSlots = nil
    if ns.Window.IsShown() then ns.Window.Hide(); OpenMock() end
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