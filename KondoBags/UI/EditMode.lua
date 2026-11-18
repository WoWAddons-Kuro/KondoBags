-- KondoBags UI/EditMode.lua -- the bag window in Edit Mode, through LibEditMode.
--
-- Pattern follows MoveMyBags.Kuro/EditMode.lua: a UIParent-parented placeholder frame is what
-- the library moves; the live window follows it. The placeholder also carries a resize grip that
-- snaps to whole cells, so the player sets a columns count by dragging. If the library is absent
-- this file does nothing and /kondo status says so.
--
-- Library calls used (vendored LibEditMode minor 18):
--   lib:AddFrame(frame, callback(frame, layoutName, point, x, y), default{point,x,y}, name)
--   lib:AddFrameSettings(frame, { { kind = lib.SettingType.Slider, ... } })
--   lib:AddFrameSettingsButtons(frame, { { text, click } })
--   lib:RegisterCallback('enter'|'exit'|'layout', fn);  lib:IsInEditMode()

local _, ns = ...
local Window, Theme, Sections = ns.Window, ns.Theme, ns.Sections
local EditMode = {}
ns.EditMode = EditMode

local lib
local placeholder
local editing = false
local defaultPos = { point = "CENTER", x = 0, y = 0 }

-- KondoBags_WindowPlacement = { point, x, y, columns }  (saved in KondoBagsCharDB.window)
local function Placement()
  KondoBagsCharDB.window = KondoBagsCharDB.window or { point = "CENTER", x = 0, y = 0, columns = 10 }
  return KondoBagsCharDB.window
end

function EditMode.IsActive() return editing end

-- Apply saved placement to the live window.
function EditMode.ApplyToWindow()
  local f = Window.Frame()
  if not f then return end
  local p = Placement()
  f:ClearAllPoints()
  f:SetPoint(p.point, UIParent, p.point, p.x, p.y)
end

-- Live window was dragged outside Edit Mode: record where it went.
function EditMode.OnWindowMoved()
  local f = Window.Frame()
  if not f then return end
  local point, _, _, x, y = f:GetPoint(1)
  local p = Placement()
  p.point, p.x, p.y = point, x, y
end

-- Window re-rendered at a new size: keep the placeholder the same size.
function EditMode.OnWindowResized(w, h)
  if placeholder then placeholder:SetSize(w, h) end
end

local function SnapColumnsFromWidth(width)
  local theme = Theme.Get(Window.state.themeID)
  local cols = Theme.ColumnsForWidth(theme, width)
  return math.max(Sections.MinColumns(), math.min(24, cols))
end

local function OnPlaceholderMoved(frame)
  local point, _, _, x, y = frame:GetPoint(1)
  local p = Placement()
  p.point, p.x, p.y = point or "CENTER", x or 0, y or 0
  EditMode.ApplyToWindow()
end

local function CreatePlaceholder()
  if placeholder then return placeholder end
  placeholder = CreateFrame("Frame", "KondoBagsEditModePlaceholder", UIParent)
  placeholder:SetFrameStrata("MEDIUM")
  placeholder:SetClampedToScreen(true)
  placeholder:SetMovable(true)
  placeholder:SetResizable(true)
  placeholder:SetSize(200, 150)
  placeholder:Hide()

  local bg = placeholder:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.5)
  local label = placeholder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("CENTER"); label:SetText("KondoBags")
  placeholder.label = label

  -- resize grip, bottom-right; snaps to whole columns on release and live while dragging
  local grip = CreateFrame("Button", nil, placeholder)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function()
    placeholder.resizing = true
    placeholder:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript("OnMouseUp", function()
    placeholder.resizing = false
    placeholder:StopMovingOrSizing()
    local cols = SnapColumnsFromWidth(placeholder:GetWidth())
    Placement().columns = cols
    Window.SetColumns(cols)          -- re-renders; OnWindowResized snaps the placeholder
    placeholder.label:SetText("KondoBags  " .. cols .. " columns")
  end)
  placeholder:SetScript("OnSizeChanged", function(self, w)
    if self.resizing then self.label:SetText("KondoBags  " .. SnapColumnsFromWidth(w) .. " columns") end
  end)

  lib:AddFrame(placeholder, OnPlaceholderMoved, defaultPos, "KondoBags")
  lib:AddFrameSettingsButtons(placeholder, {
    { text = "Reset size", click = function() Placement().columns = 10; Window.SetColumns(10) end },
  })
  return placeholder
end

local function OnEnter()
  editing = true
  CreatePlaceholder()
  local p = Placement()
  defaultPos.point, defaultPos.x, defaultPos.y = "CENTER", 0, 0
  local w, h = Window.SizeForColumns(p.columns or 10)
  placeholder:SetSize(w, h)
  placeholder:ClearAllPoints()
  placeholder:SetPoint(p.point, UIParent, p.point, p.x, p.y)
  placeholder.label:SetText("KondoBags  " .. (p.columns or 10) .. " columns")
  placeholder:Show()
end

local function OnExit()
  editing = false
  if placeholder then placeholder:Hide() end
  EditMode.ApplyToWindow()
end

function EditMode.Setup()
  if lib then return true end
  local found = LibStub and LibStub("LibEditMode", true)
  if not found or type(found.AddFrame) ~= "function" or type(found.RegisterCallback) ~= "function" then
    return false
  end
  lib = found
  lib:RegisterCallback("enter", OnEnter)
  lib:RegisterCallback("exit", OnExit)
  return true
end

function EditMode.Status()
  if not lib then return "LibEditMode not found; window is moved by plain drag" end
  return "LibEditMode minor " .. tostring(lib.hookVersion or "?") .. (editing and " (editing now)" or "")
end