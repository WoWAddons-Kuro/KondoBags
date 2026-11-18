-- KondoBags UI/Options.lua -- the Settings panel. Layout modelled on GotJunk's options page:
-- a scrolling canvas holding bordered Section boxes, each widget hanging off the previous one at a
-- fixed left column; every widget has an :Update() that re-reads the saved variables, and the whole
-- tree is refreshed on show. The complete list of settings is in SPECS/00 "Settings" and is meant to
-- stay that short.

local _, ns = ...
local Options = {}
ns.Options = Options

local optionsCategory, optionsFrame

local function CreateOptions()
  if optionsFrame then return optionsFrame end
  optionsFrame = CreateFrame("Frame", "KondoBagsOptions")
  optionsFrame.name = "Kondo Bags"

  local scroll = CreateFrame("ScrollFrame", "KondoBagsOptionsScroll", optionsFrame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, -4)
  scroll:SetPoint("BOTTOMRIGHT", -28, 4)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(620, 600)   -- height is corrected in Update once widgets exist
  scroll:SetScrollChild(content)
  scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(math.max(620, w)) end)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local max = self:GetVerticalScrollRange()
    self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 40)))
  end)

  local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16); title:SetText("Kondo Bags")
  local sub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6); sub:SetWidth(560); sub:SetJustifyH("LEFT")
  sub:SetText("The stock bag plus Keep rows. Drop an item on a lock cell to keep it there. Position, scale and column count are set in Edit Mode; pins are managed in the window itself.")

  -- Layout grid: every widget hangs off `last` at a fixed left column; sections are bordered
  -- boxes with a header.
  local BOX_W, PAD = 580, 10
  local last, lastDy = sub, -14
  local function Place(w, dy, dx) w:SetPoint("TOPLEFT", last, "BOTTOMLEFT", dx or 0, dy or lastDy); last = w; lastDy = -6 end

  -- Checkbox bound to KondoBagsDB[key]; onChange runs after the write.
  local function Check(parent, key, label, tip, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    cb.Text:SetText(label)
    cb.tooltipText = tip
    cb:SetScript("OnClick", function(self)
      KondoBagsDB[key] = self:GetChecked() and true or false
      if onChange then onChange() end
    end)
    cb.Update = function(self) self:SetChecked(KondoBagsDB[key] and true or false) end
    return cb
  end

  -- Bordered section. Children are laid out inside with their own `last` chain; the box is
  -- sized from the running height after the children are added.
  local function Section(header)
    local box = CreateFrame("Frame", nil, content, BackdropTemplateMixin and "BackdropTemplate" or nil)
    box:SetWidth(BOX_W)
    if box.SetBackdrop then
      box:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      box:SetBackdropColor(0, 0, 0, 0.25); box:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.6)
    end
    local h = box:CreateFontString(nil, "ARTWORK", "GameFontNormal"); h:SetPoint("TOPLEFT", PAD, -PAD); h:SetText(header)
    box.inner_last, box.inner_h = h, PAD + 14
    function box:Add(w, height, dy, dx)
      dy = dy or -6
      w:SetPoint("TOPLEFT", self.inner_last, "BOTTOMLEFT", dx or 0, dy)
      self.inner_last, self.inner_h = w, self.inner_h - dy + height
      return w
    end
    function box:Finish() self:SetHeight(self.inner_h + PAD) end
    Place(box, -14)
    return box
  end

  -- Section: Edit Mode (informational + reset)
  local em = Section("Window")
  -- Lock position lives in KondoBagsCharDB.window.locked (per character; the same flag the Edit Mode
  -- dialog's checkbox edits), so it needs its own binding instead of Check()'s KondoBagsDB one.
  local lock = CreateFrame("CheckButton", nil, em, "InterfaceOptionsCheckButtonTemplate")
  lock.Text:SetText("Lock position (move the window only in Edit Mode)")
  lock.tooltipText = "Untick to drag the bag window by its frame at any time. Also available in the Edit Mode dialog for KondoBags."
  lock:SetScript("OnClick", function(self)
    KondoBagsCharDB.window = KondoBagsCharDB.window or {}
    KondoBagsCharDB.window.locked = self:GetChecked() and true or false
  end)
  lock.Update = function(self) self:SetChecked(KondoBagsCharDB.window ~= nil and KondoBagsCharDB.window.locked == true) end
  em:Add(lock, 26)
  local note = em:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  note:SetWidth(BOX_W - 2 * PAD); note:SetJustifyH("LEFT")
  note:SetText("Position, scale and column count live in Edit Mode (Game Menu > Edit Mode): drag the KondoBags frame, or drag its corner grip to change the number of columns.")
  em:Add(note, 30, -6, 4)
  local reset = CreateFrame("Button", nil, em, "UIPanelButtonTemplate")
  reset:SetSize(160, 22); reset:SetText("Reset to 10 columns")
  reset:SetScript("OnClick", function() if ns.EnsureBag then ns.EnsureBag():SetColumns(10) end end)
  em:Add(reset, 22, -8, 4)
  em:Finish()


  -- Section: Theme (radio group over KondoBagsDB.theme)
  local th = Section("Theme")
  local themeRadios = {}
  local function ThemeRadio(id, label, tip)
    local r = CreateFrame("CheckButton", nil, th, "UIRadioButtonTemplate"); r:SetSize(16, 16)
    r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); r.text:SetPoint("LEFT", r, "RIGHT", 4, 0); r.text:SetText(label)
    r.tooltipText = tip
    r:SetScript("OnClick", function()
      KondoBagsDB.theme = id
      for _, o in ipairs(themeRadios) do o:SetChecked(o.themeID == id) end
      ns.Window.SetTheme(id)
    end)
    r.themeID = id
    r.Update = function(self) self:SetChecked((KondoBagsDB.theme or "classic") == id) end
    themeRadios[#themeRadios + 1] = r
    return th:Add(r, 16, -6, 0)
  end
  ThemeRadio("classic", "Classic - the stock bag look of this client")
  ThemeRadio("modern", "Modern - flat dark panel, square cells")
  th:Finish()

  -- Section: Bag types
  local bt = Section("Bag types")
  bt:Add(Check(bt, "kindTint", "Tint the border of quiver, herb, soul (and other special bag) slots",
    "Special bags are drawn as one row above your normal items. The tint says which kind each slot is: orange ammo, green herb, purple soul, blue enchanting, bronze mining, gold keyring, teal reagent.",
    function() ns.Window.Render() end), 26)
  -- Empty typed-slot backdrops: radio pair over KondoBagsDB.typedGlyph ("bag" | "kind")
  local glyphRadios = {}
  local function GlyphRadio(value, label)
    local r = CreateFrame("CheckButton", nil, bt, "UIRadioButtonTemplate"); r:SetSize(16, 16)
    r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); r.text:SetPoint("LEFT", r, "RIGHT", 4, 0); r.text:SetText(label)
    r:SetScript("OnClick", function()
      KondoBagsDB.typedGlyph = value
      for _, o in ipairs(glyphRadios) do o:SetChecked(o.value == value) end
      ns.Window.Render()
    end)
    r.value = value
    r.Update = function(self) self:SetChecked((KondoBagsDB.typedGlyph or "bag") == value) end
    glyphRadios[#glyphRadios + 1] = r
    -- Section:Add hangs each widget off the previous one's BOTTOMLEFT, so a dx is cumulative: only the
    -- first radio is indented (to sit under the checkbox text), the second gets dx 0 to line up with it.
    return bt:Add(r, 16, -6, #glyphRadios == 1 and 4 or 0)
  end
  GlyphRadio("bag", "Empty special-bag slots show the equipped bag's own icon (Blizzard style)")
  GlyphRadio("kind", "Empty special-bag slots show item-type art (herb, arrow, soul shard, ...)")
  -- Keyring (only on clients that have one): MIRROR the held keys as a typed run, occupied slots only.
  -- Off by default. The keyring itself is never ours: its button and keybind always open Blizzard's.
  local P = ns.Client.Active()
  if P.HasKeyring and P.HasKeyring() then
    bt:Add(Check(bt, "showKeys", "Show keys in Kondo Backpack",
      "Mirrors the keys on your keyring as a row above your items (only slots that hold a key). The keyring button and keybind still open Blizzard's keyring as normal.",
      function() if ns.Rescan then ns.Rescan() end end), 26, -8)
  end
  bt:Finish()

  -- Section: Reset
  local rs = Section("Reset")
  local resetAll = CreateFrame("Button", nil, rs, "UIPanelButtonTemplate")
  resetAll:SetSize(200, 22); resetAll:SetText("Reset all settings...")
  resetAll:SetScript("OnClick", function() StaticPopup_Show("KONDOBAGS_RESET_ALL") end)   -- same confirm as /kondo reset
  rs:Add(resetAll, 22, -8, 4)
  rs:Finish()
  local lastSection = rs


  local function LayoutContentHeight()
    local top, bottom = content:GetTop(), lastSection:GetBottom()
    if top and bottom then content:SetHeight(top - bottom + 24) end
  end

  -- Walk nested children so widgets inside section boxes get refreshed too.
  local function UpdateTree(frame)
    for _, child in ipairs({ frame:GetChildren() }) do
      if child.Update then child:Update() end
      UpdateTree(child)
    end
  end
  optionsFrame.Update = function()
    UpdateTree(content)
    LayoutContentHeight()
  end
  optionsFrame:SetScript("OnShow", optionsFrame.Update)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    optionsCategory = Settings.RegisterCanvasLayoutCategory(optionsFrame, "Kondo Bags")
    Settings.RegisterAddOnCategory(optionsCategory)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(optionsFrame)
  end
  return optionsFrame
end

function Options.Setup() CreateOptions() end

-- Re-read every widget from the saved variables (after /kondo reset while the panel is open).
function Options.Refresh() if optionsFrame and optionsFrame.Update then optionsFrame.Update() end end

function Options.Open()
  CreateOptions()
  if Settings and Settings.OpenToCategory and optionsCategory then Settings.OpenToCategory(optionsCategory:GetID())
  elseif InterfaceOptionsFrame_OpenToCategory then InterfaceOptionsFrame_OpenToCategory(optionsFrame); InterfaceOptionsFrame_OpenToCategory(optionsFrame) end
end
