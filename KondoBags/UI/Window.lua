-- KondoBags UI/Window.lua -- the bag window renderer (M0: mock cells, no secure buttons yet).
--
-- Draws a KondoBags_LayoutResult from Core/Sections.lua using a KondoBags_Theme. Holds a pool of
-- plain Button cells; each is re-dressed per render as a slot / plus / handle cell. All item
-- interaction here is MOCK: clicking a filled slot picks up a fake cursor item, clicking an empty
-- slot puts it down, dropping on + or a handle pins. Replaced by secure ContainerFrameItemButton
-- cells in M4; the layout, theme and section code underneath stay.

local _, ns = ...
local Sections, Theme = ns.Sections, ns.Theme
local Window = {}
ns.Window = Window

local frame                    -- the window
local cells = {}               -- pool of cell buttons
local dividers = {}            -- pool of divider textures
local state = {
  columns = 10,
  themeID = "classic",
  store = nil,                 -- KondoBags_SectionStore (set by KondoBags.lua)
  slots = nil,                 -- { KondoBags_SlotRef... } current data
  money = 0,
  cursor = nil,                -- mock cursor: { ref = KondoBags_SlotRef } while "holding" an item
  dragSection = nil,           -- section id being reordered by handle drag
  onChanged = nil,             -- callback() after any pin/reorder, so the owner can persist
}
Window.state = state

local function Theme_()
  return Theme.Get(state.themeID)
end

-- ---------------------------------------------------------------------------
-- frame
-- ---------------------------------------------------------------------------
local function ApplyBackdrop(f, theme)
  if not f.SetBackdrop or not theme.backdrop then return end
  f:SetBackdrop(theme.backdrop)
  if theme.backdropColor then f:SetBackdropColor(unpack(theme.backdropColor)) end
  if theme.backdropBorderColor then f:SetBackdropBorderColor(unpack(theme.backdropBorderColor)) end
end

-- The window is created once per theme *family*: Blizzard's PortraitFrameTemplate (stock look)
-- cannot be turned into a flat backdrop frame after the fact, so switching between a template
-- theme and a backdrop theme rebuilds the frame. Cells are re-parented onto the new Grid.
local function FrameTemplateFor(theme)
  if theme.frameTemplate then return theme.frameTemplate end
  return BackdropTemplateMixin and "BackdropTemplate" or nil
end

local function CreateWindow(theme)
  theme = theme or Theme_()
  local template = FrameTemplateFor(theme)
  if frame and frame.kbTemplate == template then return frame end
  local old = frame
  frame = CreateFrame("Frame", "KondoBagsWindow" .. (old and "2" or ""), UIParent, template)
  frame.kbTemplate = template
  frame:SetFrameStrata("MEDIUM")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:SetPoint("CENTER")
  frame:Hide()

  if theme.frameTemplate then
    -- Blizzard portrait frame: it already has NineSlice, Bg, TitleContainer.TitleText, PortraitContainer.portrait,
    -- CloseButton. Use its own pieces so the look is exactly the client's.
    if theme.portraitScale and theme.portraitScale < 1 and NineSliceUtil and NineSliceLayouts then
      -- The template's TopLeftCorner atlas carries the ring for a 62px portrait and cannot be scaled on
      -- its own. Use the no-portrait border layout and draw a smaller portrait + ring ourselves.
      local layout = NineSliceLayouts.ButtonFrameTemplateNoPortrait or NineSliceLayouts.PortraitFrameTemplateNoPortrait
      if layout and frame.NineSlice then NineSliceUtil.ApplyLayout(frame.NineSlice, layout) end
      if frame.PortraitContainer then frame.PortraitContainer:Hide() end
      local size = 62 * theme.portraitScale
      local holder = CreateFrame("Frame", nil, frame)
      holder:SetFrameLevel(frame:GetFrameLevel() + 20)
      holder:SetSize(size, size)
      holder:SetPoint("TOPLEFT", frame, "TOPLEFT", -6, 6)
      frame.Portrait = holder:CreateTexture(nil, "ARTWORK")
      frame.Portrait:SetAllPoints()
      frame.Portrait:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
      frame.Portrait:SetTexCoord(0.1, 0.9, 0.1, 0.9)
      if frame.Portrait.SetMask then frame.Portrait:SetMask("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask") end
      local ring = holder:CreateTexture(nil, "OVERLAY")
      ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")   -- round gold ring, stock art
      ring:SetTexCoord(0, 0.6, 0, 0.6)
      ring:SetPoint("CENTER", holder, "CENTER", 10 * theme.portraitScale, -10 * theme.portraitScale)
      ring:SetSize(size * 1.55, size * 1.55)
      frame.PortraitRing = ring
    else
      frame.Portrait = frame.PortraitContainer and frame.PortraitContainer.portrait
      if frame.SetPortraitToAsset then frame:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Bag_08")
      elseif frame.Portrait then frame.Portrait:SetTexture("Interface\\Icons\\INV_Misc_Bag_08") end
    end
    if frame.Bg and theme.bgTint then frame.Bg:SetVertexColor(unpack(theme.bgTint)) end
    frame.Title = frame.TitleContainer and frame.TitleContainer.TitleText or frame.TitleText
    if frame.SetTitle then frame:SetTitle("KondoBags") elseif frame.Title then frame.Title:SetText("KondoBags") end
    frame.Close = frame.CloseButton
    if frame.Close then frame.Close:SetScript("OnClick", function() Window.Hide() end) end
  else
    frame.Portrait = frame:CreateTexture(nil, "ARTWORK")
    frame.Portrait:SetSize(40, 40)
    frame.Portrait:SetPoint("TOPLEFT", 4, -4)
    frame.Portrait:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
    if frame.Portrait.SetMask then frame.Portrait:SetMask("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask") end
    frame.Title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.Title:SetPoint("TOP", 0, -14)
    frame.Title:SetText("KondoBags")
    frame.Close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.Close:SetPoint("TOPRIGHT", 2, 2)
    frame.Close:SetScript("OnClick", function() Window.Hide() end)
  end

  frame.Search = CreateFrame("EditBox", "KondoBagsSearchBox", frame, "SearchBoxTemplate")
  frame.Search:SetHeight(20)
  frame.Search:SetAutoFocus(false)
  frame.Search:SetFrameLevel(frame:GetFrameLevel() + 10)   -- above the grid and any template children
  frame.Search:SetScript("OnTextChanged", function(self)
    if self.Instructions then self.Instructions:SetShown(self:GetText() == "") end
    Window.ApplySearch(self:GetText())
  end)
  frame.Search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)

  frame.Money = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  frame.Money:SetJustifyH("RIGHT")

  frame.Footer = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame.Footer:Hide()

  frame.Grid = CreateFrame("Frame", nil, frame)
  frame.Grid:SetFrameLevel(frame:GetFrameLevel() + 5)

  -- Carry the cell pool and dividers over from a previous frame.
  for _, b in ipairs(cells) do b:SetParent(frame.Grid) end
  for _, d in ipairs(dividers) do d:SetParent(frame.Grid) end
  if old then old:Hide(); old:SetParent(nil) end

  -- Plain drag to move (outside Edit Mode); Edit Mode owns position when the lib is present.
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) if not ns.EditMode or not ns.EditMode.IsActive() then self:StartMoving() end end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); if ns.EditMode then ns.EditMode.OnWindowMoved() end end)
  return frame
end

-- ---------------------------------------------------------------------------
-- cells
-- ---------------------------------------------------------------------------
local function FormatMoney(copper)
  copper = math.floor(copper or 0)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t" end
  if g > 0 or s > 0 then out[#out + 1] = s .. "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t" end
  out[#out + 1] = c .. "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t"
  return table.concat(out, " ")
end

local function QualityColor(q)
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
  if c then return c.r, c.g, c.b end
  return 1, 1, 1
end

local Cell_OnClick, Cell_OnEnter, Cell_OnLeave, Cell_OnDragStart, Cell_OnDragStop, Cell_OnReceiveDrag

local function NewCell(i)
  local b = CreateFrame("Button", "KondoBagsCell" .. i, frame.Grid)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b.bg = b:CreateTexture(nil, "BACKGROUND")           -- flat theme background
  b.bg:SetAllPoints()
  -- flat theme 1px ring: four edge textures so the interior stays see-through
  b.edges = {}
  for e = 1, 4 do b.edges[e] = b:CreateTexture(nil, "BORDER") end
  b.edges[1]:SetPoint("TOPLEFT", -1, 1);     b.edges[1]:SetPoint("TOPRIGHT", 1, 1);      b.edges[1]:SetHeight(1)
  b.edges[2]:SetPoint("BOTTOMLEFT", -1, -1); b.edges[2]:SetPoint("BOTTOMRIGHT", 1, -1);  b.edges[2]:SetHeight(1)
  b.edges[3]:SetPoint("TOPLEFT", -1, 1);     b.edges[3]:SetPoint("BOTTOMLEFT", -1, -1);  b.edges[3]:SetWidth(1)
  b.edges[4]:SetPoint("TOPRIGHT", 1, 1);     b.edges[4]:SetPoint("BOTTOMRIGHT", 1, -1);  b.edges[4]:SetWidth(1)
  b.normal = b:CreateTexture(nil, "BACKGROUND", nil, -1) -- classic Quickslot2 art
  b.normal:SetPoint("CENTER", 0, -1)
  b.emptyIcon = b:CreateTexture(nil, "BACKGROUND", nil, 1) -- classic: faint bag icon in empty slots
  b.emptyIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.emptyIcon:Hide()
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.qborder = b:CreateTexture(nil, "OVERLAY")
  b.qborder:SetTexture("Interface\\Common\\WhiteIconFrame")
  b.qborder:SetAllPoints()
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.count:SetPoint("BOTTOMRIGHT", -3, 2)
  b.glyph = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  b.glyph:SetPoint("CENTER", 0, 0)
  b.dim = b:CreateTexture(nil, "OVERLAY", nil, 4)
  b.dim:SetAllPoints(); b.dim:SetColorTexture(0, 0, 0, 0.75); b.dim:Hide()
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints(); b.hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square"); b.hl:SetBlendMode("ADD")
  b:SetScript("OnClick", Cell_OnClick)
  b:SetScript("OnEnter", Cell_OnEnter)
  b:SetScript("OnLeave", Cell_OnLeave)
  b:SetScript("OnDragStart", Cell_OnDragStart)
  b:SetScript("OnDragStop", Cell_OnDragStop)
  b:SetScript("OnReceiveDrag", Cell_OnReceiveDrag)
  return b
end

local function DressCell(b, cell, theme)
  b.cell = cell
  b:SetSize(theme.cell.size, theme.cell.size)
  -- art under the cell
  if theme.slotNormal then
    b.normal:SetTexture(theme.slotNormal.file)
    b.normal:SetSize(theme.slotNormal.size, theme.slotNormal.size)
    b.normal:SetPoint("CENTER", 0, theme.slotNormal.offsetY or 0)
    b.normal:Show()
  else
    b.normal:Hide()
  end
  if theme.slotFlat then b.bg:SetColorTexture(unpack(theme.slotFlat)); b.bg:Show() else b.bg:Hide() end
  for _, e in ipairs(b.edges) do
    if theme.slotBorder then e:SetColorTexture(unpack(theme.slotBorder)); e:Show() else e:Hide() end
  end

  b.icon:Hide(); b.qborder:Hide(); b.count:Hide(); b.glyph:Hide(); b.dim:Hide()
  b.emptyIcon:Hide()
  b:SetAlpha(1)
  if cell.kind == Sections.CELL_SLOT then
    local item = cell.ref and cell.ref.item
    if item then
      b.icon:SetTexture(item.icon); b.icon:Show()
      if item.quality and item.quality >= 2 then b.qborder:SetVertexColor(QualityColor(item.quality)); b.qborder:Show() end
      if (item.count or 1) > 1 then b.count:SetText(item.count); b.count:Show() end
      if state.cursor and state.cursor.ref == cell.ref then b:SetAlpha(0.4) end   -- "picked up"
    elseif theme.slotEmptyIcon then
      local e = theme.slotEmptyIcon
      b.emptyIcon:SetTexture(e.file)
      b.emptyIcon:SetDesaturated(e.desaturate and true or false)
      b.emptyIcon:SetAlpha(e.alpha or 0.5)
      local t = e.tint or 1; b.emptyIcon:SetVertexColor(t, t, t)
      b.emptyIcon:SetPoint("TOPLEFT", e.inset or 0, -(e.inset or 0)); b.emptyIcon:SetPoint("BOTTOMRIGHT", -(e.inset or 0), e.inset or 0)
      b.emptyIcon:Show()
    end
  elseif cell.kind == Sections.CELL_PLUS then
    local g = theme.plusGlyph
    b.glyph:SetFontObject(g.font); b.glyph:SetText(g.text); b.glyph:SetTextColor(unpack(g.color)); b.glyph:Show()
  elseif cell.kind == Sections.CELL_HANDLE then
    local g = theme.handleGlyph
    b.glyph:SetFontObject(g.font); b.glyph:SetText(g.text); b.glyph:SetTextColor(unpack(g.color)); b.glyph:Show()
    if theme.slotNormal then b.normal:SetAlpha(0.45) end
  end
  if theme.slotNormal and cell.kind ~= Sections.CELL_HANDLE then b.normal:SetAlpha(1) end
end

-- ---------------------------------------------------------------------------
-- mock interaction
-- ---------------------------------------------------------------------------
local function Changed()
  if state.onChanged then state.onChanged() end
  Window.Render()
end

-- Mock-only: an icon that rides the mouse while a fake item is "held", standing in for the client's
-- real cursor item (which only C_Container.PickupContainerItem can produce). Removed in M4.
local carry
local function Carry_Update()
  if not carry then return end
  local x, y = GetCursorPosition()
  local s = UIParent:GetEffectiveScale()
  carry:ClearAllPoints()
  carry:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s + 14, y / s - 14)
end
local function Carry_Show(icon)
  if not carry then
    carry = CreateFrame("Frame", "KondoBagsMockCarry", UIParent)
    carry:SetSize(30, 30)
    carry:SetFrameStrata("TOOLTIP")
    carry.icon = carry:CreateTexture(nil, "OVERLAY")
    carry.icon:SetAllPoints()
    carry.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    carry:SetScript("OnUpdate", Carry_Update)
  end
  carry.icon:SetTexture(icon)
  carry:SetAlpha(0.85)
  Carry_Update()
  carry:Show()
end
local function Carry_Hide() if carry then carry:Hide() end end

local function MockPickup(ref)
  if ref and ref.item then state.cursor = { ref = ref }; Carry_Show(ref.item.icon) end
end

local function MockClearCursor()
  state.cursor = nil
  Carry_Hide()
  ResetCursor()
end

-- Drop the held mock item onto a cell. Returns true if something happened.
local function MockDrop(cell)
  local held = state.cursor and state.cursor.ref
  if not held then return false end
  if cell.kind == Sections.CELL_PLUS then
    Sections.Create(state.store, held.item.itemID)
    MockClearCursor(); Changed(); return true
  elseif cell.kind == Sections.CELL_HANDLE then
    Sections.Pin(state.store, cell.sectionID, held.item.itemID)
    MockClearCursor(); Changed(); return true
  elseif cell.kind == Sections.CELL_SLOT then
    local target = cell.ref
    if target == held then MockClearCursor(); Window.Render(); return true end
    -- physical swap (mock): exchange the item fields of the two refs
    target.item, held.item = held.item, target.item
    MockClearCursor(); Changed(); return true
  end
  return false
end

Cell_OnClick = function(b, button)
  local cell = b.cell
  if not cell then return end
  if button == "RightButton" then
    if cell.kind == Sections.CELL_HANDLE then Window.ShowHandleMenu(b, cell.sectionID) end
    return
  end
  if state.cursor then MockDrop(cell); return end
  if cell.kind == Sections.CELL_SLOT and cell.ref and cell.ref.item then
    MockPickup(cell.ref); Window.Render()
  end
end

Cell_OnReceiveDrag = function(b)
  if b.cell then MockDrop(b.cell) end
end

Cell_OnDragStart = function(b)
  local cell = b.cell
  if not cell then return end
  if cell.kind == Sections.CELL_HANDLE then
    state.dragSection = cell.sectionID
    SetCursor("UI_MOVE_CURSOR")
  elseif cell.kind == Sections.CELL_SLOT and cell.ref and cell.ref.item and not state.cursor then
    MockPickup(cell.ref); Window.Render()
  end
end

Cell_OnDragStop = function(_)
  if state.dragSection then
    -- find the cell under the mouse; reorder to that cell's section index (or last if loose)
    local target
    for _, c in ipairs(cells) do
      if c:IsShown() and c:IsMouseOver() then target = c.cell; break end
    end
    local newIndex
    if target and target.sectionID then
      local _, idx = Sections.Find(state.store, target.sectionID)
      newIndex = idx
    elseif target then
      newIndex = #state.store.list
    end
    local moving = state.dragSection
    state.dragSection = nil
    ResetCursor()
    if newIndex and Sections.Reorder(state.store, moving, newIndex) then Changed() end
  end
end

Cell_OnEnter = function(b)
  local cell = b.cell
  if not cell then return end
  GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
  if cell.kind == Sections.CELL_PLUS then
    GameTooltip:SetText("New section", 1, 1, 1)
    GameTooltip:AddLine("Drop an item here to start a section with it.", 0.8, 0.8, 0.8, true)
  elseif cell.kind == Sections.CELL_HANDLE then
    local s = Sections.Find(state.store, cell.sectionID)
    local n = 0; if s then for _ in pairs(s.items) do n = n + 1 end end
    GameTooltip:SetText((s and s.name ~= "" and s.name) or "Section", 1, 1, 1)
    GameTooltip:AddLine(n .. " pinned item" .. (n == 1 and "" or "s"), 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Drop an item: pin it here", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Drag: move this section", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Right-click: options", 0.6, 0.6, 0.6)
  elseif cell.ref and cell.ref.item then
    local it = cell.ref.item
    GameTooltip:SetText(it.name, QualityColor(it.quality))
    local s = Sections.SectionOf(state.store, it.itemID)
    if s then GameTooltip:AddLine("KondoBags: pinned to " .. ((s.name ~= "" and s.name) or s.id), 0.6, 0.8, 1) end
    GameTooltip:AddLine(string.format("bag %d slot %d (mock)", cell.ref.bagID, cell.ref.slot), 0.5, 0.5, 0.5)
  else
    GameTooltip:Hide(); return
  end
  GameTooltip:Show()
end

Cell_OnLeave = function() GameTooltip:Hide() end

-- Right-click menu on a handle. Minimal in M0: rename (prompt), dissolve.
function Window.ShowHandleMenu(anchor, sectionID)
  local s = Sections.Find(state.store, sectionID)
  if not s then return end
  if MenuUtil and MenuUtil.CreateContextMenu then
    MenuUtil.CreateContextMenu(anchor, function(_, root)
      root:CreateTitle((s.name ~= "" and s.name) or "Section")
      root:CreateButton("Rename...", function() Window.PromptRename(sectionID) end)
      root:CreateButton("Dissolve section", function() Sections.Dissolve(state.store, sectionID); Changed() end)
    end)
  else
    -- very old clients: just toggle dissolve on shift-right-click, prompt rename otherwise
    if IsShiftKeyDown() then Sections.Dissolve(state.store, sectionID); Changed() else Window.PromptRename(sectionID) end
  end
end

function Window.PromptRename(sectionID)
  StaticPopupDialogs["KONDOBAGS_RENAME_SECTION"] = StaticPopupDialogs["KONDOBAGS_RENAME_SECTION"] or {
    text = "Section name", button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, maxLetters = 32,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnAccept = function(self, data)
      local s = Sections.Find(state.store, data)
      if s then s.name = self.editBox:GetText(); Changed() end
    end,
    EditBoxOnEnterPressed = function(self) local p = self:GetParent(); p.button1:Click() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    OnShow = function(self, data)
      local s = Sections.Find(state.store, data)
      self.editBox:SetText(s and s.name or ""); self.editBox:HighlightText()
    end,
  }
  StaticPopup_Show("KONDOBAGS_RENAME_SECTION", nil, nil, sectionID)
end

-- ---------------------------------------------------------------------------
-- render
-- ---------------------------------------------------------------------------
local function GetDivider(i)
  local d = dividers[i]
  if not d then d = frame.Grid:CreateTexture(nil, "ARTWORK"); dividers[i] = d end
  return d
end

function Window.Render()
  if not frame or not state.store or not state.slots then return end
  local theme = Theme_()
  ApplyBackdrop(frame, theme)
  if frame.Portrait and not theme.frameTemplate then frame.Portrait:SetShown(theme.portrait) end
  if frame.Title and not theme.frameTemplate then frame.Title:SetFontObject(theme.titleFont) end

  local input = Sections.Partition(state.store, state.slots, state.columns)
  local layout = Sections.Layout(input)
  local rows = math.max(1, #layout.rows)
  local w, h = Theme.WindowSize(theme, state.columns, rows)
  frame:SetSize(w, h)

  local f = theme.frame
  -- Vertical stack under the title bar: [padTop] search row [searchGap] grid ... footer [padBottom].
  local searchH = theme.searchHeight or 20
  local searchTop = f.padTop + (theme.searchTopGap or (theme.titleHeight - searchH) / 2)
  frame.Grid:ClearAllPoints()
  frame.Grid:SetPoint("TOPLEFT", f.padLeft, -(f.padTop + theme.titleHeight))
  frame.Grid:SetSize(w - f.padLeft - f.padRight, rows * theme.cell.pitchY)

  local gridW = w - f.padLeft - f.padRight
  local searchW = gridW * (theme.searchWidthScale or 1) - 8
  frame.Search:ClearAllPoints()
  frame.Search:SetHeight(searchH)
  frame.Search:SetWidth(searchW)
  frame.Search:SetPoint("TOPLEFT", frame, "TOPLEFT", f.padLeft + 6, -searchTop)
  frame.Money:ClearAllPoints()
  if theme.moneyFont then frame.Money:SetFontObject(theme.moneyFont) end
  if theme.moneyColor then frame.Money:SetTextColor(unpack(theme.moneyColor)) end
  frame.Money:SetText(FormatMoney(state.money))
  local bar = theme.footerBar
  if bar and frame.Footer.SetBackdrop then
    frame.Footer:SetBackdrop(bar.backdrop)
    if bar.bgColor then frame.Footer:SetBackdropColor(unpack(bar.bgColor)) end
    if bar.borderColor then frame.Footer:SetBackdropBorderColor(unpack(bar.borderColor)) end
    frame.Footer:ClearAllPoints()
    frame.Footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", f.padLeft - bar.insetX, f.padBottom)
    frame.Footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -f.padRight + bar.insetX, f.padBottom)
    frame.Footer:SetHeight(bar.height)
    frame.Footer:Show()
    frame.Money:SetPoint("RIGHT", frame.Footer, "RIGHT", -6, 0)
  else
    frame.Footer:Hide()
    frame.Money:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -f.padRight - 2, f.padBottom + 2)
  end

  local ci, di = 0, 0
  for r, row in ipairs(layout.rows) do
    local y = -((r - 1) * theme.cell.pitchY)
    if row.dividerAbove then
      di = di + 1
      local d = GetDivider(di)
      d:SetColorTexture(unpack(theme.divider.color))
      d:SetHeight(theme.divider.height)
      d:ClearAllPoints()
      d:SetPoint("TOPLEFT", frame.Grid, "TOPLEFT", theme.divider.insetX, y + math.floor((theme.cell.pitchY - theme.cell.size) / 2))
      d:SetPoint("RIGHT", frame.Grid, "RIGHT", -theme.divider.insetX, 0)
      d:Show()
    end
    for c, cell in ipairs(row.cells) do
      ci = ci + 1
      local b = cells[ci]
      if not b then b = NewCell(ci); cells[ci] = b end
      DressCell(b, cell, theme)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", frame.Grid, "TOPLEFT", ((cell.col or c) - 1) * theme.cell.pitchX, y)
      b:Show()
    end
  end
  for i = ci + 1, #cells do cells[i]:Hide(); cells[i].cell = nil end
  for i = di + 1, #dividers do dividers[i]:Hide() end

  Window.ApplySearch(frame.Search:GetText())
  if ns.EditMode then ns.EditMode.OnWindowResized(w, h) end
end

function Window.ApplySearch(text)
  text = (text or ""):lower()
  for _, b in ipairs(cells) do
    if b:IsShown() and b.cell and b.cell.kind == Sections.CELL_SLOT and b.cell.ref and b.cell.ref.item then
      local miss = text ~= "" and not b.cell.ref.item.name:lower():find(text, 1, true)
      b.dim:SetShown(miss)
      b.icon:SetDesaturated(miss)
    end
  end
end

-- ---------------------------------------------------------------------------
-- public
-- ---------------------------------------------------------------------------
function Window.Setup(opts)
  state.store = opts.store
  state.slots = opts.slots
  state.money = opts.money or 0
  state.columns = opts.columns or state.columns
  state.themeID = opts.themeID or state.themeID
  state.onChanged = opts.onChanged
  CreateWindow()
  Window.Render()
end

function Window.SetTheme(id)
  state.themeID = id
  local wasShown = Window.IsShown()
  CreateWindow()                      -- rebuilds only when the frame family changes
  if ns.EditMode then ns.EditMode.ApplyToWindow() end
  Window.Render()
  if wasShown then frame:Show() end
end
function Window.SetColumns(n) state.columns = math.max(Sections.MinColumns(), math.min(24, n)); Window.Render() end
function Window.GetColumns() return state.columns end
function Window.Frame() return frame end
function Window.Show() CreateWindow(); Window.Render(); frame:Show() end
function Window.Hide() if frame then frame:Hide() end; MockClearCursor() end
function Window.Toggle() if frame and frame:IsShown() then Window.Hide() else Window.Show() end end
function Window.IsShown() return frame and frame:IsShown() end

-- Size the window would have at `columns` for the current data (for Edit Mode snapping).
function Window.SizeForColumns(columns)
  local theme = Theme_()
  local input = Sections.Partition(state.store, state.slots, columns)
  local rows = math.max(1, Sections.RowCount(input, columns))
  return Theme.WindowSize(theme, columns, rows)
end