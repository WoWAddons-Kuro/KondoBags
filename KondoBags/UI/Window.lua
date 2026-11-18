-- KondoBags UI/Window.lua -- the bag window VIEW (M0: mock cells, no secure buttons yet).
--
-- Draws KondoBags_BagState:Layout() with a KondoBags_Theme. Holds a pool of plain Button cells;
-- each is re-dressed per render as a slot or a section drop cell. The view never touches the
-- section store or the slot list: every gesture is forwarded to the controller (Core/BagState.lua),
-- which emits "changed" / "cursor" and the view redraws. In M4 the cells become secure
-- ContainerFrameItemButtons and the controller routes to the Client provider; this file's
-- layout/theme code stays.

local _, ns = ...
local Layout, Theme = ns.Layout, ns.Theme
local Window = {}
ns.Window = Window

local frame                    -- the window
local cells = {}               -- pool of cell buttons
local view = {
  bag = nil,                   -- KondoBags_BagState (controller)
  themeID = "classic",
  money = 0,
}
Window.view = view

local function Theme_() return Theme.Get(view.themeID) end

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
    frame.Portrait = frame.PortraitContainer and frame.PortraitContainer.portrait
    if frame.SetPortraitToAsset then frame:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Bag_08")
    elseif frame.Portrait then frame.Portrait:SetTexture("Interface\\Icons\\INV_Misc_Bag_08") end
    -- The gold ring is part of the nine-slice TopLeftCorner atlas, so only the portrait itself can be
    -- resized. Shrink it inside the ring (which stays stock size) and keep the circle mask on it.
    if frame.Portrait and theme.portraitScale and theme.portraitScale < 1 then
      local base, s = 62, theme.portraitScale
      local size = base * s
      local shift = (base - size) / 2          -- keep the same centre as the stock portrait
      frame.Portrait:SetSize(size, size)
      frame.Portrait:ClearAllPoints()
      frame.Portrait:SetPoint("TOPLEFT", frame.PortraitContainer, "TOPLEFT", -5 + shift, 7 - shift)
      local mask = frame.PortraitContainer.CircleMask
      if mask then
        mask:ClearAllPoints()
        mask:SetPoint("TOPLEFT", frame.Portrait, "TOPLEFT", 2 * s, 0)
        mask:SetPoint("BOTTOMRIGHT", frame.Portrait, "BOTTOMRIGHT", -2 * s, 4 * s)
      end
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

  -- "+" right of the search box: adds a new empty keep group below the last (D12).
  frame.AddGroup = CreateFrame("Button", "KondoBagsAddGroupButton", frame)
  frame.AddGroup:SetSize(22, 22)
  frame.AddGroup:SetFrameLevel(frame:GetFrameLevel() + 10)
  frame.AddGroup:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
  frame.AddGroup:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
  frame.AddGroup:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
  frame.AddGroup:SetScript("OnClick", function()
    if view.bag then view.bag:AddGroup("") end
  end)
  frame.AddGroup:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("New keep row", 1, 1, 1)
    GameTooltip:AddLine("Adds another row with its own lock. Drop items on the lock to keep them there.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  frame.AddGroup:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Footer bar and money sit on their own frame that ignores the window's alpha, so a translucent
  -- panel background never fades the money text or the bar's border.
  frame.Footer = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame.Footer:SetIgnoreParentAlpha(true)
  frame.Footer:SetFrameLevel(frame:GetFrameLevel() + 6)
  frame.Footer:Hide()

  frame.Money = frame.Footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.Money:SetJustifyH("RIGHT")

  frame.Grid = CreateFrame("Frame", nil, frame)
  frame.Grid:SetFrameLevel(frame:GetFrameLevel() + 5)

  for _, b in ipairs(cells) do b:SetParent(frame.Grid) end
  if old then old:Hide(); old:SetParent(nil) end

  -- Plain drag to move (outside Edit Mode); Edit Mode owns position when the lib is present.
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) if not ns.EditMode or not ns.EditMode.IsActive() then self:StartMoving() end end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); if ns.EditMode then ns.EditMode.OnWindowMoved() end end)
  return frame
end

-- ---------------------------------------------------------------------------
-- helpers
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

-- Mock-only: an icon that rides the mouse while the controller holds an item, standing in for the
-- client's real cursor item (which only C_Container.PickupContainerItem can produce). Removed in M4.
local carry
local function Carry_Update()
  if not carry then return end
  local x, y = GetCursorPosition()
  local s = UIParent:GetEffectiveScale()
  carry:ClearAllPoints()
  carry:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s + 14, y / s - 14)
end
local function Carry_Sync()
  local item = view.bag and view.bag:HeldItem()
  if not item then
    if carry then carry:Hide() end
    ResetCursor()
    return
  end
  if not carry then
    carry = CreateFrame("Frame", "KondoBagsMockCarry", UIParent)
    carry:SetSize(30, 30)
    carry:SetFrameStrata("TOOLTIP")
    carry.icon = carry:CreateTexture(nil, "OVERLAY")
    carry.icon:SetAllPoints()
    carry.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    carry:SetScript("OnUpdate", Carry_Update)
  end
  carry.icon:SetTexture(item.icon)
  carry:SetAlpha(0.85)
  Carry_Update()
  carry:Show()
end

-- ---------------------------------------------------------------------------
-- cells
-- ---------------------------------------------------------------------------
local Cell_OnClick, Cell_OnEnter, Cell_OnLeave, Cell_OnDragStart, Cell_OnReceiveDrag

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
  b.emptyIcon = b:CreateTexture(nil, "BACKGROUND", nil, 1) -- faint glyph in empty / drop cells
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
  b.dim = b:CreateTexture(nil, "OVERLAY", nil, 4)
  b.dim:SetAllPoints(); b.dim:SetColorTexture(0, 0, 0, 0.75); b.dim:Hide()
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints(); b.hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square"); b.hl:SetBlendMode("ADD")
  b:SetScript("OnClick", Cell_OnClick)
  b:SetScript("OnEnter", Cell_OnEnter)
  b:SetScript("OnLeave", Cell_OnLeave)
  b:SetScript("OnDragStart", Cell_OnDragStart)
  b:SetScript("OnReceiveDrag", Cell_OnReceiveDrag)
  return b
end

local function SetGlyph(b, g)
  b.emptyIcon:SetTexture(g.file)
  b.emptyIcon:SetDesaturated(g.desaturate and true or false)
  b.emptyIcon:SetAlpha(g.alpha or 0.5)
  local t = g.tint or 1; b.emptyIcon:SetVertexColor(t, t, t)
  local inset = g.inset or 0
  b.emptyIcon:SetPoint("TOPLEFT", inset, -inset); b.emptyIcon:SetPoint("BOTTOMRIGHT", -inset, inset)
  b.emptyIcon:Show()
end

local function DressCell(b, cell, theme)
  b.cell = cell
  b:SetSize(theme.cell.size, theme.cell.size)
  -- Item icon sits inside the slot border like the stock bags, not edge to edge.
  local ii = theme.cell.iconInset or 0
  b.icon:ClearAllPoints()
  b.icon:SetPoint("TOPLEFT", ii, -ii); b.icon:SetPoint("BOTTOMRIGHT", -ii, ii)
  if theme.slotNormal then
    b.normal:SetTexture(theme.slotNormal.file)
    b.normal:SetSize(theme.slotNormal.size, theme.slotNormal.size)
    b.normal:SetPoint("CENTER", 0, theme.slotNormal.offsetY or 0)
    b.normal:SetVertexColor(1, 1, 1)
    b.normal:Show()
  else
    b.normal:Hide()
  end
  if theme.slotFlat then b.bg:SetColorTexture(unpack(theme.slotFlat)); b.bg:Show() else b.bg:Hide() end
  -- Restricted-bag cell: subtle tint per slot kind (KondoBagsDB.kindTint toggles it). With stock slot
  -- art the tint colours the rounded Quickslot border itself; the flat theme tints its 1px ring.
  local tint = cell.slotKind and theme.kindTint and theme.kindTint[cell.slotKind]
  if tint and KondoBagsDB and KondoBagsDB.kindTint == false then tint = nil end
  if tint and theme.slotNormal then
    local r, g, bl, a = unpack(tint)
    a = a or 1
    b.normal:SetVertexColor(1 - (1 - r) * a, 1 - (1 - g) * a, 1 - (1 - bl) * a)   -- blend toward the kind colour
    tint = nil                                                                   -- no square edges on classic
  end
  for _, e in ipairs(b.edges) do
    if tint then e:SetColorTexture(unpack(tint)); e:Show()
    elseif theme.slotBorder then e:SetColorTexture(unpack(theme.slotBorder)); e:Show()
    else e:Hide() end
  end

  b.icon:Hide(); b.qborder:Hide(); b.count:Hide(); b.dim:Hide(); b.emptyIcon:Hide()
  b:SetAlpha(1)
  if cell.kind == Layout.CELL_SLOT then
    local item = cell.ref and cell.ref.item
    if item then
      b.icon:SetTexture(item.icon); b.icon:Show()
      if item.quality and item.quality >= 2 then b.qborder:SetVertexColor(QualityColor(item.quality)); b.qborder:Show() end
      if (item.count or 1) > 1 then b.count:SetText(item.count); b.count:Show() end
      if view.bag:IsHeld(cell.ref) then b:SetAlpha(0.4) end   -- "picked up"
    elseif cell.slotKind and theme.kindGlyph and theme.kindGlyph[cell.slotKind] then
      SetGlyph(b, theme.kindGlyph[cell.slotKind])
    elseif theme.slotEmptyIcon then
      SetGlyph(b, theme.slotEmptyIcon)
    end
  elseif cell.kind == Layout.CELL_DROP and theme.dropGlyph then
    SetGlyph(b, theme.dropGlyph)
  elseif cell.kind == Layout.CELL_GAP then
    -- Shift-drag cursor gap: the cell under the mouse where the carried item will land; brighter lock glyph
    SetGlyph(b, theme.gapGlyph or theme.dropGlyph)
  end
end

-- gestures -> controller
Cell_OnClick = function(b, button)
  local cell, bag = b.cell, view.bag
  if not cell or not bag then return end
  if button == "RightButton" then
    -- Right-click while carrying always cancels the carry (stock behaviour), nothing else.
    if bag:HeldItem() then bag:ClearCursor(); return end
    if cell.kind == Layout.CELL_DROP then Window.ShowGroupMenu(b, cell.sectionID) end
    return
  end
  if bag:HeldItem() then bag:Drop(cell); return end
  if cell.kind == Layout.CELL_SLOT and cell.ref then bag:Pickup(cell.ref) end
end

-- Clicking the 3D world while carrying: right = cancel, left = the stock "destroy item?" dialog.
-- Mock-only (M4 uses the real cursor and Blizzard's own dialog). One WorldFrame hook, installed once.
StaticPopupDialogs["KONDOBAGS_MOCK_DESTROY"] = {
  text = "Do you want to destroy %s?",
  button1 = YES, button2 = NO,
  OnAccept = function()
    local bag = view.bag
    if bag and bag.held then bag.held.item = nil; bag:ClearCursor(); bag:Emit("changed") end
  end,
  OnCancel = function() if view.bag then view.bag:ClearCursor() end end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
local function InstallWorldClickHook()
  if view.worldHooked or not WorldFrame then return end
  view.worldHooked = true
  WorldFrame:HookScript("OnMouseDown", function(_, button)
    local bag = view.bag
    local item = bag and bag:HeldItem()
    if not item then return end
    if button == "RightButton" then bag:ClearCursor()
    elseif button == "LeftButton" then StaticPopup_Show("KONDOBAGS_MOCK_DESTROY", item.name) end
  end)
end

-- Right-click menu on a group's lock cell. One item for now: remove the group (items -> incoming).
function Window.ShowGroupMenu(anchor, sectionID)
  local bag = view.bag
  if not bag then return end
  local g = bag:Section(sectionID)
  if not g then return end
  local canRemove = #bag.store.list > 1
  if MenuUtil and MenuUtil.CreateContextMenu then
    MenuUtil.CreateContextMenu(anchor, function(_, root)
      root:CreateTitle((g.name ~= "" and g.name) or "Keep row")
      local btn = root:CreateButton("Remove section", function() bag:RemoveGroup(sectionID) end)
      if not canRemove and btn.SetEnabled then btn:SetEnabled(false) end
    end)
  elseif canRemove then
    bag:RemoveGroup(sectionID)       -- clients without MenuUtil: right-click removes directly
  end
end

Cell_OnReceiveDrag = function(b)
  if b.cell and view.bag then view.bag:Drop(b.cell) end
end

Cell_OnDragStart = function(b)
  local cell, bag = b.cell, view.bag
  if cell and bag and cell.kind == Layout.CELL_SLOT and cell.ref and not bag:HeldItem() then bag:Pickup(cell.ref) end
end

Cell_OnEnter = function(b)
  local cell, bag = b.cell, view.bag
  if not cell or not bag then return end
  view.hoverButton = b
  bag:SetHover(cell)
  GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
  if cell.kind == Layout.CELL_DROP or cell.kind == Layout.CELL_GAP then
    local s = bag:Section(cell.sectionID)
    local n = s and ns.Sections.ItemCount(s) or 0
    GameTooltip:SetText((s and s.name ~= "" and s.name) or "Section", 1, 1, 1)
    GameTooltip:AddLine(n .. " kept item" .. (n == 1 and "" or "s"), 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Drop an item here to keep it in this section.", 0.6, 0.6, 0.6, true)
  elseif cell.ref and cell.ref.item then
    local it = cell.ref.item
    GameTooltip:SetText(it.name, QualityColor(it.quality))
    local s = bag:SectionOfRef(cell.ref)
    if s then GameTooltip:AddLine("KondoBags: kept in " .. ((s.name ~= "" and s.name) or s.id), 0.6, 0.8, 1) end
    GameTooltip:AddLine(string.format("bag %d slot %d (mock)", cell.ref.bagID, cell.ref.slot), 0.5, 0.5, 0.5)
  else
    GameTooltip:Hide(); return
  end
  GameTooltip:Show()
end

-- When the layout re-flows under a stationary mouse, the button that WAS under it is re-dressed as a
-- different cell and a neighbouring button now sits under the cursor. WoW then fires OnEnter on the
-- new button and OnLeave on the old one, in either order. A trailing OnLeave must not wipe a hover
-- the newer OnEnter just set, or the phantom closes and reopens every frame (the rightmost-item
-- "spaz"). So OnLeave only clears the hover it owns.
Cell_OnLeave = function(b)
  GameTooltip:Hide()
  if view.hoverButton ~= b then return end
  view.hoverButton = nil
  if view.bag then view.bag:SetHover(nil) end
end

-- ---------------------------------------------------------------------------
-- render
-- ---------------------------------------------------------------------------
function Window.Render()
  if not frame or not view.bag then return end
  local theme, bag = Theme_(), view.bag
  ApplyBackdrop(frame, theme)
  if frame.Portrait and not theme.frameTemplate then frame.Portrait:SetShown(theme.portrait) end
  if frame.Title and not theme.frameTemplate then frame.Title:SetFontObject(theme.titleFont) end

  local layout = bag:Layout()
  local rows = math.max(1, #layout.rows)
  -- Vertical placement per row. A run boundary (incoming -> group, group -> group) gets a gap of
  -- theme.sectionGapRows times the normal inter-row gap (owner: 3x), so groups read as groups.
  local rowGap = theme.cell.pitchY - theme.cell.size
  local sectionGap = (theme.sectionGapRows or 3) * rowGap
  local rowY, extraH = {}, 0
  local y = 0
  for r, row in ipairs(layout.rows) do
    -- A run boundary: typed -> incoming, incoming -> group, group -> group.
    local prev = layout.rows[r - 1]
    local runChanged = prev and (row.sectionID ~= prev.sectionID or (row.typed or false) ~= (prev.typed or false))
    if runChanged then
      y = y - (sectionGap - rowGap); extraH = extraH + (sectionGap - rowGap)
    end
    rowY[r] = y
    y = y - theme.cell.pitchY
  end
  local w, h = Theme.WindowSize(theme, bag.columns, rows)
  h = h + extraH
  frame:SetSize(w, h)

  local f = theme.frame
  -- Vertical stack under the title bar: [padTop] search row [gap] grid ... footer [padBottom].
  local searchH = theme.searchHeight or 20
  local searchTop = f.padTop + (theme.searchTopGap or (theme.titleHeight - searchH) / 2)
  frame.Grid:ClearAllPoints()
  frame.Grid:SetPoint("TOPLEFT", f.padLeft, -(f.padTop + theme.titleHeight))
  frame.Grid:SetSize(w - f.padLeft - f.padRight, rows * theme.cell.pitchY + extraH)

  local gridW = w - f.padLeft - f.padRight
  frame.Search:ClearAllPoints()
  frame.Search:SetHeight(searchH)
  frame.Search:SetWidth(gridW * (theme.searchWidthScale or 1) - 8)
  frame.Search:SetPoint("TOP", frame, "TOP", 0, -searchTop)
  frame.AddGroup:ClearAllPoints()
  frame.AddGroup:SetPoint("LEFT", frame.Search, "RIGHT", 6, 0)

  frame.Money:ClearAllPoints()
  if theme.moneyFont then frame.Money:SetFontObject(theme.moneyFont) end
  if theme.moneyColor then frame.Money:SetTextColor(unpack(theme.moneyColor)) end
  frame.Money:SetText(FormatMoney(view.money))
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

  local ci = 0
  for r, row in ipairs(layout.rows) do
    local cellY = rowY[r]
    for _, cell in ipairs(row.cells) do
      ci = ci + 1
      local b = cells[ci]
      if not b then b = NewCell(ci); cells[ci] = b end
      DressCell(b, cell, theme)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", frame.Grid, "TOPLEFT", (cell.col - 1) * theme.cell.pitchX, cellY)
      b:Show()
    end
  end
  for i = ci + 1, #cells do cells[i]:Hide(); cells[i].cell = nil end

  Window.ApplySearch(frame.Search:GetText())
  Carry_Sync()
  if ns.EditMode then ns.EditMode.OnWindowResized(w, h) end
end

function Window.ApplySearch(text)
  text = (text or ""):lower()
  for _, b in ipairs(cells) do
    if b:IsShown() and b.cell and b.cell.kind == Layout.CELL_SLOT and b.cell.ref and b.cell.ref.item then
      local miss = text ~= "" and not b.cell.ref.item.name:lower():find(text, 1, true)
      b.dim:SetShown(miss)
      b.icon:SetDesaturated(miss)
    end
  end
end

-- ---------------------------------------------------------------------------
-- public
-- ---------------------------------------------------------------------------
local function OnBagEvent(event)
  if event == "cursor" then
    -- only alpha + carry icon change; a full render is cheap enough in M0
    Window.Render()
  else
    Window.Render()
  end
end

-- opts = { bag = KondoBags_BagState, money, themeID }
function Window.Attach(opts)
  if view.bag ~= opts.bag then
    view.bag = opts.bag
    view.bag:AddListener(OnBagEvent)
    view.bag:SetInsertMode(IsShiftKeyDown())
  end
  InstallWorldClickHook()
  -- Shift toggles insert mode while carrying (see BagState). One event frame for the window.
  if not view.modFrame then
    view.modFrame = CreateFrame("Frame")
    view.modFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
    view.modFrame:SetScript("OnEvent", function(_, _, key, down)
      if key == "LSHIFT" or key == "RSHIFT" then
        if view.bag then view.bag:SetInsertMode(down == 1 or down == true) end
      end
    end)
  end
  view.money = opts.money or view.money
  view.themeID = opts.themeID or view.themeID
  CreateWindow()
  Window.Render()
end

function Window.SetTheme(id)
  view.themeID = id
  local wasShown = Window.IsShown()
  CreateWindow()                      -- rebuilds only when the frame family changes
  if ns.EditMode then ns.EditMode.ApplyToWindow() end
  Window.Render()
  if wasShown then frame:Show() end
end
function Window.ThemeID() return view.themeID end
function Window.Frame() return frame end
function Window.Show() CreateWindow(); Window.Render(); frame:Show() end
function Window.Hide() if frame then frame:Hide() end; if view.bag then view.bag:ClearCursor() end end
function Window.Toggle() if frame and frame:IsShown() then Window.Hide() else Window.Show() end end
function Window.IsShown() return frame and frame:IsShown() end

-- Size the window would have at `columns` for the current data (for Edit Mode snapping).
function Window.SizeForColumns(columns)
  if not view.bag then return 200, 150 end
  local rows = math.max(1, view.bag:RowCount(columns))
  return Theme.WindowSize(Theme_(), columns, rows)
end