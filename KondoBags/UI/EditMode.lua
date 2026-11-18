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
local Window, Theme, Layout = ns.Window, ns.Theme, ns.Layout
local EditMode = {}
ns.EditMode = EditMode

local lib
local placeholder
local editing = false
local defaultPos = { point = "CENTER", x = 0, y = 0 }

-- KondoBags_WindowPlacement = { point, x, y, columns }  (saved in KondoBagsCharDB.window)
local function Placement()
  local p = KondoBagsCharDB.window
  if not p then p = { columns = 10 }; KondoBagsCharDB.window = p end
  -- Fresh install (no anchor chosen yet): open where the STOCK bags open, so the first look is familiar.
  -- Stock anchors the first bag's BOTTOMRIGHT to UIParent's BOTTOMRIGHT at
  --   x = -(right action bar width + 10)   (Forever; Era uses CONTAINER_OFFSET_X = -4 in place of +10)
  --   y = CONTAINER_OFFSET_Y               (Forever 85, Era 70)
  -- (_ref/blizzard/forever/ContainerFrame.lua:1320-1395, classic_era/ContainerFrame_Shared.lua:994-1041).
  -- Read once; after that the saved anchor rules. `placed` marks that an anchor exists.
  -- A store saved before `placed` existed already carries point/x/y the player chose: honour it and
  -- just stamp the flag -- otherwise every /reload snapped a moved window back to the stock spot.
  if p.point then p.placed = true end
  if not p.placed then
    local barW = 0
    if EditModeUtil and EditModeUtil.GetRightActionBarWidth then
      local okW, w = pcall(EditModeUtil.GetRightActionBarWidth, EditModeUtil)
      if okW and type(w) == "number" then barW = w end
    end
    local pad = (CONTAINER_OFFSET_X and CONTAINER_OFFSET_X < 0) and -CONTAINER_OFFSET_X or 10
    p.point, p.x, p.y = "BOTTOMRIGHT", -(barW + pad), CONTAINER_OFFSET_Y or 85
    p.placed = true
  end
  return p
end

function EditMode.IsActive() return editing end

-- True when the window may be dragged by its frame OUTSIDE Edit Mode (the "Lock position"
-- checkbox in the Edit Mode dialog is off). Default movable.
function EditMode.IsPositionLocked() return Placement().locked == true end

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
  -- Not while Blizzard is sizing it: a SetSize mid-drag fights StartSizing and collapses the frame.
  if placeholder and not placeholder.resizing then placeholder:SetSize(w, h) end
end

local function SnapColumnsFromWidth(width)
  local theme = Theme.Get(Window.ThemeID())
  local cols = Theme.ColumnsForWidth(theme, width)
  return math.max(Layout.MIN_COLUMNS, math.min(24, cols))
end

local function SetColumns(cols)
  Placement().columns = cols
  if ns.EnsureBag then ns.EnsureBag():SetColumns(cols) end   -- controller re-renders via its listener
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
  -- Above the live window (MEDIUM, toplevel): clicking the window raises it, and a MEDIUM placeholder
  -- would then drag underneath it.
  placeholder:SetFrameStrata("HIGH")
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

  -- Resize grip, bottom-right. Blizzard sizes the placeholder (StartSizing); we only READ its width,
  -- snap it to a column count and resize the live window to match. The window's height is ours.
  -- The placeholder is never resized by us while the drag is in progress, so nothing fights.
  local grip = CreateFrame("Button", nil, placeholder)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function()
    placeholder.resizing = true
    placeholder:StartSizing("BOTTOMRIGHT")
    if placeholder.FollowStart then placeholder.FollowStart() end
  end)
  grip:SetScript("OnMouseUp", function()
    placeholder.resizing = false
    placeholder:StopMovingOrSizing()
    if placeholder.FollowStop then placeholder.FollowStop() end
    local cols = SnapColumnsFromWidth(placeholder:GetWidth())
    SetColumns(cols)                               -- no-op if the live follow already applied this count
    -- Snap the placeholder back to the window's real size. SetColumns only re-renders when the count
    -- changes, and during the drag it usually already has, so do it explicitly from the window.
    local f = Window.Frame()
    if f and f:GetWidth() > 0 then placeholder:SetSize(f:GetSize())
    else placeholder:SetSize(Window.SizeForColumns(cols)) end
    OnPlaceholderMoved(placeholder)                -- save the (possibly re-normalised) anchor
    placeholder.label:SetText("KondoBags  " .. cols .. " columns")
  end)

  lib:AddFrame(placeholder, OnPlaceholderMoved, defaultPos, "KondoBags")
  -- The library parents a full-size selection overlay on the placeholder AFTER our grip exists, so
  -- the grip would sit underneath it and never receive the mouse. Lift it above the overlay.
  local selection = lib.frameSelections and lib.frameSelections[placeholder]
  local above = (selection and selection:GetFrameLevel() or placeholder:GetFrameLevel()) + 5
  grip:SetFrameLevel(above)
  grip:SetFrameStrata(placeholder:GetFrameStrata())
  placeholder.grip = grip

  -- LIVE FOLLOW. The library only reports a position when the drag ENDS; the window would sit
  -- still until the drop. While the placeholder is being moved (library drag) or sized (our grip),
  -- mirror its position to the live window every frame, and during sizing snap the column count
  -- as the width crosses each cell boundary so the window reflows under the mouse.
  local function FollowStart() placeholder:SetScript("OnUpdate", function(self)
    local point, _, _, x, y = self:GetPoint(1)
    if not point then return end
    local f = Window.Frame()
    if f then f:ClearAllPoints(); f:SetPoint(point, UIParent, point, x, y) end
    if self.resizing then
      local cols = SnapColumnsFromWidth(self:GetWidth())
      if cols ~= Placement().columns then
        SetColumns(cols)                           -- window reflows; placeholder is left to Blizzard
        self.label:SetText("KondoBags  " .. cols .. " columns")
      end
    end
  end) end
  local function FollowStop() placeholder:SetScript("OnUpdate", nil) end
  placeholder.FollowStart, placeholder.FollowStop = FollowStart, FollowStop
  if selection then
    selection:HookScript("OnDragStart", FollowStart)
    selection:HookScript("OnDragStop", FollowStop)
  end
  lib:AddFrameSettingsButtons(placeholder, {
    { text = "Reset size", click = function() SetColumns(10) end },
  })
  -- "Lock position": unchecked (default) = the window can be dragged by its frame at any time, as
  -- most addons do. Checked = it moves only in Edit Mode. Saved per character.
  lib:AddFrameSettings(placeholder, {
    {
      kind = lib.SettingType.Checkbox,
      name = "Lock position",
      default = false,
      get = function() return Placement().locked == true end,
      set = function(_, value) Placement().locked = value and true or false end,
    },
  })
  return placeholder
end

local function OnEnter()
  editing = true
  CreatePlaceholder()
  local p = Placement()
  defaultPos.point, defaultPos.x, defaultPos.y = "CENTER", 0, 0
  -- Size from the live window when it exists (it includes the 3x section gaps the renderer adds);
  -- fall back to the theme estimate when the window has never been built.
  local live = Window.Frame()
  local w, h
  if live and live:GetWidth() > 0 then w, h = live:GetSize() else w, h = Window.SizeForColumns(p.columns or 10) end
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