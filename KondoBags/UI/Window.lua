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
    if frame.SetTitle then frame:SetTitle("Kondo Backpack") elseif frame.Title then frame.Title:SetText("Kondo Backpack") end
    frame.Close = frame.CloseButton
    if frame.Close then frame.Close:SetScript("OnClick", function() Window.Hide() end) end
  else
    -- Flat frame: title bar metrics come from theme.titleBar = { height, titleY, closeSize, closeInset,
    -- closeColor, closeHoverColor }. The close button is a flat glyph, not the stock round button.
    local tb = theme.titleBar or {}
    frame.Portrait = frame:CreateTexture(nil, "ARTWORK")
    frame.Portrait:SetSize(tb.portraitSize or 40, tb.portraitSize or 40)
    frame.Portrait:SetPoint("TOPLEFT", 4, -4)
    frame.Portrait:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
    if frame.Portrait.SetMask then frame.Portrait:SetMask("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask") end
    frame.Title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.Title:SetPoint("TOP", 0, -(tb.titleY or 14))
    frame.Title:SetText("Kondo Backpack")
    local cs = tb.closeSize or 16
    frame.Close = CreateFrame("Button", nil, frame)
    frame.Close:SetSize(cs, cs)
    frame.Close:SetPoint("TOPRIGHT", -(tb.closeInset or 6), -(tb.closeInset or 6))
    frame.Close:SetFrameLevel(frame:GetFrameLevel() + 10)
    frame.Close.glyph = frame.Close:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.Close.glyph:SetPoint("CENTER", 0, 0)
    frame.Close.glyph:SetText("x")
    local cc = tb.closeColor or { 0.7, 0.7, 0.7 }
    local hc = tb.closeHoverColor or { 1, 0.3, 0.3 }
    frame.Close.glyph:SetTextColor(unpack(cc))
    frame.Close:SetScript("OnEnter", function(self) self.glyph:SetTextColor(unpack(hc)) end)
    frame.Close:SetScript("OnLeave", function(self) self.glyph:SetTextColor(unpack(cc)) end)
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
  -- Flat search (theme.searchFlat = { r, g, b, a }): hide SearchBoxTemplate's textured border and
  -- lay a plain colour behind the text. The box reads as a slightly lighter rectangle, no outline.
  if theme.searchFlat then
    for _, key in ipairs({ "Left", "Right", "Middle", "LeftTex", "RightTex", "MiddleTex" }) do
      local tex = frame.Search[key]
      if tex and tex.SetAlpha then tex:SetAlpha(0) end
    end
    for _, region in ipairs({ frame.Search:GetRegions() }) do
      if region:IsObjectType("Texture") and region ~= frame.Search.searchIcon then
        local file = region.GetTextureFileID and region:GetTextureFileID()
        if file and file ~= 0 then region:SetAlpha(0) end
      end
    end
    frame.Search.flatBg = frame.Search:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame.Search.flatBg:SetAllPoints()
    frame.Search.flatBg:SetColorTexture(unpack(theme.searchFlat))
  end

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

  -- Plain drag to move outside Edit Mode, only when "Lock position" (Edit Mode dialog) is off.
  -- Inside Edit Mode the placeholder owns the position.
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    local em = ns.EditMode
    if em and (em.IsActive() or em.IsPositionLocked()) then return end
    self:StartMoving()
  end)
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
-- ---------------------------------------------------------------------------
-- cells
-- ---------------------------------------------------------------------------
local Cell_OnClick, Cell_OnEnter, Cell_OnLeave, Cell_OnDragStart, Cell_OnReceiveDrag

-- Two cell pools (D14):
--   plain  -- our Buttons: lock cells, cursor-gap cells, and every slot of the MOCK bag
--   secure -- ContainerFrameItemButtonTemplate: slots of the LIVE bag. Blizzard's own OnClick /
--             OnDrag / OnEnter run (pickup, swap, split, use, sell, tooltip); the button reads its bag
--             from parent:GetID() and its slot from self:GetID(), so each live cell is parented to a
--             hidden per-bag holder frame. Re-parenting is not allowed in combat (see Render).
local secureCells = {}          -- pool of secure item buttons
local bagHolders = {}           -- bagID -> hidden Frame with SetID(bagID), child of frame.Grid

local function BagHolder(bagID)
  local h = bagHolders[bagID]
  if not h then
    h = CreateFrame("Frame", nil, frame.Grid)
    h:SetID(bagID)
    h:SetAllPoints(frame.Grid)
    bagHolders[bagID] = h
  elseif h:GetParent() ~= frame.Grid then
    h:SetParent(frame.Grid); h:SetAllPoints(frame.Grid)
  end
  return h
end

-- Our overlay regions on a secure button: the theme's flat bg / 1px ring and the kind glyph. The
-- template already owns icon, Count, IconBorder, NormalTexture, searchOverlay.
local function DecorateSecure(b)
  b.bg = b:CreateTexture(nil, "BACKGROUND", nil, -2); b.bg:SetAllPoints()
  b.edges = {}
  for e = 1, 4 do b.edges[e] = b:CreateTexture(nil, "BORDER") end
  b.edges[1]:SetPoint("TOPLEFT", -1, 1);     b.edges[1]:SetPoint("TOPRIGHT", 1, 1);      b.edges[1]:SetHeight(1)
  b.edges[2]:SetPoint("BOTTOMLEFT", -1, -1); b.edges[2]:SetPoint("BOTTOMRIGHT", 1, -1);  b.edges[2]:SetHeight(1)
  b.edges[3]:SetPoint("TOPLEFT", -1, 1);     b.edges[3]:SetPoint("BOTTOMLEFT", -1, -1);  b.edges[3]:SetWidth(1)
  b.edges[4]:SetPoint("TOPRIGHT", 1, 1);     b.edges[4]:SetPoint("BOTTOMRIGHT", 1, -1);  b.edges[4]:SetWidth(1)
  -- The kind glyph (herb, ammo pouch, ...) for EMPTY typed cells. The template's own icon region and
  -- NormalTexture live at BORDER/ARTWORK and were covering an ARTWORK(-1) glyph (regression after the
  -- new-item glow change). OVERLAY(-1) draws above them and below Count / IconBorder / IconQuestTexture.
  b.emptyIcon = b:CreateTexture(nil, "OVERLAY", nil, -1)
  b.emptyIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93); b.emptyIcon:Hide()
  b.dim = b.searchOverlay                              -- stock black overlay = our search dim
  b.normal = b:GetNormalTexture()                      -- stock Quickslot2 = our slotNormal target
  -- Kind tint guard. Blizzard's ItemButton code whitens its NormalTexture from several paths that run
  -- OUTSIDE DressCell (intrinsic OnShow, SetItemButtonQuality, ItemButtonMixin:UpdateItemContext...),
  -- so an occupied typed cell lost its tint while an empty one kept it. Hook the texture's own
  -- SetVertexColor: whenever anyone resets it to white while a kind tint is wanted, put the tint back.
  if b.normal and not b.normal.kbTintHooked then
    b.normal.kbTintHooked = true
    local guard = false
    hooksecurefunc(b.normal, "SetVertexColor", function(tex, r, g, bl)
      if guard or not b.kindTint then return end
      if r == 1 and g == 1 and bl == 1 then
        guard = true; tex:SetVertexColor(unpack(b.kindTint)); guard = false
      end
    end)
  end
  b.qborder = b.IconBorder
  b.count = b.Count
  b.secure = true
end

local function NewSecureCell(i, bagID)
  local b = CreateFrame("ItemButton" , "KondoBagsItem" .. i, BagHolder(bagID), "ContainerFrameItemButtonTemplate")
  DecorateSecure(b)
  -- Our hover tracking for the cursor gap rides alongside Blizzard's tooltip handlers.
  b:HookScript("OnEnter", function(self)
    if self.cell and view.bag then view.hoverButton = self; view.bag:SetHover(self.cell) end
  end)
  b:HookScript("OnLeave", function(self)
    if view.hoverButton == self then view.hoverButton = nil; if view.bag then view.bag:SetHover(nil) end end
  end)
  return b
end

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

-- Glyph for an EMPTY cell. General slots: theme.slotEmptyIcon. Typed slots: theme.kindGlyph[kind].
-- Typed slots follow KondoBagsDB.typedGlyph (keyring has no equipped bag, bagIcon nil: always its kind glyph):
--   "bag"  (default) -- the icon of the bag actually equipped (ref.bagIcon, from the provider),
--                         so an empty cell reads "this is my quiver / herb bag"; falls back to the kind glyph
--   "kind"           -- the theme's item-type art for the kind (herb, ammo-slot art, soul shard, ...)
local function EmptyGlyph(cell, theme)
  local kind = cell.slotKind
  if not kind then return theme.slotEmptyIcon end
  local g = theme.kindGlyph and theme.kindGlyph[kind]
  if KondoBagsDB == nil or KondoBagsDB.typedGlyph ~= "kind" then
    local icon = cell.ref and cell.ref.bagIcon
    if icon then
      local base = theme.bagIconGlyph or g or {}
      return { file = icon, desaturate = base.desaturate, alpha = base.alpha or 0.4, inset = base.inset or 2, tint = base.tint }
    end
  end
  return g or theme.slotEmptyIcon
end

-- "Won't take the carried item" mark on a typed cell (owner, 2026-11-18): while an item is on the
-- cursor, every typed slot whose bag family refuses it gets a circle-X (the loot-roll Pass glyph)
-- over the cell. An OCCUPIED cell is also dimmed, since a swap onto it is refused just the same; an
-- empty cell keeps its backdrop undimmed so the row does not turn to mud. The glyph is tinted a
-- little red so it reads against the monochrome backdrop art. General slots take anything and are
-- never marked.
local NO_DROP_TEXTURE = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local function SetNoDrop(b, on, occupied, theme)
  if on and not b.noDrop then
    b.noDrop = b:CreateTexture(nil, "OVERLAY", nil, 6)         -- above icon / border / quest; below nothing of ours
    b.noDrop:SetTexture(NO_DROP_TEXTURE)
    b.noDrop:SetPoint("CENTER")
  end
  if not b.noDrop then return end
  if on then
    local nd = theme.noDrop or {}
    local size = nd.size or 22
    b.noDrop:SetSize(size, size)
    b.noDrop:SetDesaturated(true)
    b.noDrop:SetVertexColor(unpack(nd.color or { 1, 0.55, 0.55 }))
    b.noDrop:SetAlpha(nd.alpha or 0.9)
    b.noDrop:Show()
    if occupied and b.dim then b.dim:Show() end
  else
    b.noDrop:Hide()
  end
end

-- Quest item highlight on a secure cell (SPECS/01 "Quest item highlight"). Stock's rule verbatim:
-- "!" when the item STARTS a quest not yet accepted (questID and not isActive), the yellow border
-- when it is a quest item or belongs to an active quest, nothing otherwise. Era's stock bags hide
-- this texture; we draw it on every client. A slow alpha pulse makes it read without shouting.
local function QuestPulse(b, theme)
  if b.questPulse then return b.questPulse end
  local tex = b.IconQuestTexture
  local ag = tex:CreateAnimationGroup()
  ag:SetLooping("REPEAT")
  local half = (theme.questPulsePeriodSec or Theme.QUEST_PULSE_PERIOD_SEC) / 2
  local lo = theme.questPulseMinAlpha or Theme.QUEST_PULSE_MIN_ALPHA
  local function Leg(order, from, to)
    local a = ag:CreateAnimation("Alpha")
    a:SetOrder(order); a:SetDuration(half); a:SetFromAlpha(from); a:SetToAlpha(to); a:SetSmoothing("IN_OUT")
  end
  Leg(1, 1, lo); Leg(2, lo, 1)
  b.questPulse = ag
  return ag
end

local function SetQuestHighlight(b, quest, theme)
  local tex = b.IconQuestTexture
  if not tex then return end
  local file
  if quest and quest.questID and not quest.isActive then file = TEXTURE_ITEM_QUEST_BANG
  elseif quest and (quest.questID or quest.isQuestItem) then file = TEXTURE_ITEM_QUEST_BORDER end
  if file then
    tex:SetTexture(file); tex:Show()
    local ag = QuestPulse(b, theme)
    if not ag:IsPlaying() then ag:Play() end
  else
    if b.questPulse and b.questPulse:IsPlaying() then b.questPulse:Stop() end
    tex:SetAlpha(1); tex:Hide()
  end
end

local function DressCell(b, cell, theme)
  b.cell = cell
  b:SetSize(theme.cell.size, theme.cell.size)
  -- Item icon sits inside the slot border like the stock bags, not edge to edge.
  local ii = theme.cell.iconInset or 0
  if not b.secure then
    b.icon:ClearAllPoints()
    b.icon:SetPoint("TOPLEFT", ii, -ii); b.icon:SetPoint("BOTTOMRIGHT", -ii, ii)
  end
  if b.normal then
    if theme.slotNormal then
      b.normal:SetTexture(theme.slotNormal.file)
      b.normal:SetSize(theme.slotNormal.size, theme.slotNormal.size)
      b.normal:ClearAllPoints(); b.normal:SetPoint("CENTER", 0, theme.slotNormal.offsetY or 0)
      b.normal:SetVertexColor(1, 1, 1)
      b.normal:Show()
    else
      b.normal:Hide()
    end
  end
  if theme.slotFlat then b.bg:SetColorTexture(unpack(theme.slotFlat)); b.bg:Show() else b.bg:Hide() end
  -- Restricted-bag cell: subtle tint per slot kind (KondoBagsDB.kindTint toggles it). With stock slot
  -- art the tint colours the rounded Quickslot border itself; the flat theme tints its 1px ring.
  -- On secure cells the Quickslot tint is applied AFTER the stock helpers below: SetItemButtonQuality
  -- resets the NormalTexture vertex colour to white, which wiped the tint on every cell but the first.
  local tint = cell.slotKind and theme.kindTint and theme.kindTint[cell.slotKind]
  if tint and KondoBagsDB and KondoBagsDB.kindTint == false then tint = nil end
  local normalTint
  if tint and theme.slotNormal and b.normal then
    local r, g, bl, a = unpack(tint)
    a = a or 1
    normalTint = { 1 - (1 - r) * a, 1 - (1 - g) * a, 1 - (1 - bl) * a }         -- blend toward the kind colour
    tint = nil                                                                   -- no square edges on classic
  end
  local function ApplyNormalTint()
    -- Remember the wanted tint on the button: the ItemButton intrinsic whitens its NormalTexture from
    -- its own OnShow / item-update paths (which run AFTER DressCell, when Render shows the button), so
    -- the colour is re-applied from Window.ReapplyKindTint after Show and from a hook on the whitener.
    b.kindTint = normalTint
    if not normalTint then return end
    if b.normal then b.normal:SetVertexColor(unpack(normalTint)) end
  end
  for _, e in ipairs(b.edges) do
    if tint then e:SetColorTexture(unpack(tint)); e:Show()
    elseif theme.slotBorder then e:SetColorTexture(unpack(theme.slotBorder)); e:Show()
    else e:Hide() end
  end

  b:SetAlpha(1)
  b.emptyIcon:Hide()
  if b.secure then
    -- LIVE slot on a secure button: bag/slot IDs drive Blizzard's handlers; the stock helpers draw it.
    local ref = cell.ref
    b:SetID(ref.slot)
    local holder = BagHolder(ref.bagID)
    if b:GetParent() ~= holder then b:SetParent(holder) end
    local item = ref.item
    SetItemButtonTexture(b, item and item.icon or nil)
    SetItemButtonCount(b, item and item.count or 0)
    SetItemButtonQuality(b, item and item.quality or nil, item and item.itemID or nil)
    SetItemButtonDesaturated(b, item and item.locked or false)
    ApplyNormalTint()
    -- Occupied typed cell: the item icon covers the Quickslot ring, so the kind tint has to sit on the
    -- OVERLAY IconBorder (the quality frame). Quality colour wins when the item has one (uncommon+).
    if item and normalTint and b.qborder then
      if not (item.quality and item.quality >= 2) then
        b.qborder:SetTexture("Interface\\Common\\WhiteIconFrame")
        b.qborder:SetVertexColor(unpack(normalTint)); b.qborder:Show()
      end
    end
    -- The template owns a "new item" glow (NewItemTexture + newitemglowAnim/flashAnim) that only
    -- stock's UpdateItems drives; left alone it can show on every cell. We draw it ourselves:
    -- glow only when the client flags the slot new (looted this session), exactly like stock.
    local isNew = item ~= nil and C_NewItems and C_NewItems.IsNewItem and C_NewItems.IsNewItem(ref.bagID, ref.slot)
    if b.NewItemTexture then b.NewItemTexture:SetShown(isNew and true or false) end
    if b.BattlepayItemTexture then b.BattlepayItemTexture:Hide() end
    if b.newitemglowAnim then
      if isNew then if not b.newitemglowAnim:IsPlaying() then b.newitemglowAnim:Play() end
      else b.newitemglowAnim:Stop() end
    end
    if b.flashAnim and not isNew then b.flashAnim:Stop() end
    -- Quest item highlight: stock's border / "!" on the template's IconQuestTexture, pulsing slowly.
    SetQuestHighlight(b, item and item.quest or nil, theme)
    -- Empty slot: the template leaves its icon region shown with no file; hide it so the glyph reads.
    if b.icon then b.icon:SetShown(item ~= nil) end
    if not item then
      SetGlyph(b, EmptyGlyph(cell, theme))
    end
    -- Typed slot that would refuse the carried item: circle-X (and dim when occupied).
    local refuses = cell.slotKind ~= nil and not view.bag:HeldFits(cell.slotKind)
    SetNoDrop(b, refuses, item ~= nil, theme)
    return
  end
  ApplyNormalTint()
  b.icon:Hide(); b.qborder:Hide(); b.count:Hide(); b.dim:Hide()
  if cell.kind == Layout.CELL_SLOT then
    local item = cell.ref and cell.ref.item
    if item then
      b.icon:SetTexture(item.icon); b.icon:Show()
      if item.quality and item.quality >= 2 then b.qborder:SetVertexColor(QualityColor(item.quality)); b.qborder:Show() end
      if (item.count or 1) > 1 then b.count:SetText(item.count); b.count:Show() end
      if view.bag:IsHeld(cell.ref) then b:SetAlpha(0.4) end   -- "picked up"
    else
      SetGlyph(b, EmptyGlyph(cell, theme))
    end
    local refuses = cell.slotKind ~= nil and not view.bag:HeldFits(cell.slotKind)
    SetNoDrop(b, refuses, item ~= nil, theme)
  elseif cell.kind == Layout.CELL_DROP and theme.dropGlyph then
    if cell.slim then
      -- Slim lock (gutter cell, half width). Owner: slim the BORDER, not the key. The stock Quickslot
      -- ring is drawn squeezed to the slim cell (the art stretches cleanly enough at 2:1), the flat
      -- theme's 1px ring already follows the cell; the key glyph keeps its full cell size, centred,
      -- overhanging the narrow border on both sides -- no clipping.
      if b.normal and theme.slotNormal then
        local sn = theme.slotNormal
        local ratio = sn.size / theme.cell.size                      -- ring art : cell (64 : 37 on classic)
        b.normal:SetSize(slimW * ratio, sn.size)
        b.normal:Show()
      end
      local g = theme.slimDropGlyph or theme.dropGlyph
      SetGlyph(b, g)
      local full = theme.cell.size - 2 * (g.inset or 0)
      b.emptyIcon:ClearAllPoints()
      b.emptyIcon:SetPoint("CENTER"); b.emptyIcon:SetSize(full, full)
      b:SetClipsChildren(false)
    else
      b:SetClipsChildren(false)
      if b.normal and theme.slotNormal then b.normal:SetSize(theme.slotNormal.size, theme.slotNormal.size) end
      SetGlyph(b, theme.dropGlyph)
    end
  elseif cell.kind == Layout.CELL_GAP then
    -- Shift-drag cursor gap: the cell under the mouse where the carried item will land; brighter lock glyph
    SetGlyph(b, theme.gapGlyph or theme.dropGlyph)
  end
end

-- gestures -> controller
Cell_OnClick = function(b, button)
  local cell, bag = b.cell, view.bag
  if not cell or not bag then return end
  -- D14: only lock / gap cells are ours. Left with an item on the cursor = pin or reorder; right-click
  -- on a lock with an empty cursor = the group menu. Slot gestures are Blizzard's (secure buttons).
  if button == "RightButton" then
    if cell.kind == Layout.CELL_DROP and not CursorHasItem() then Window.ShowGroupMenu(b, cell.sectionID) end
    return
  end
  if CursorHasItem() and bag.held then bag:Drop(cell) end
end

-- Clicking the 3D world while carrying: right = cancel, left = the stock "destroy item?" dialog.
-- Mock-only (M4 uses the real cursor and Blizzard's own dialog). One WorldFrame hook, installed once.
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
  if not b.cell or not view.bag then return end
  if CursorHasItem() and view.bag.held then view.bag:Drop(b.cell) end
end

-- Slots are secure buttons (Blizzard drags them); our plain cells are locks and gaps, which do not drag.
Cell_OnDragStart = function() end

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
  -- Slim-lock gutter (Layout.slimGutter): a group whose items fill whole rows puts its lock half-width
  -- in a gutter LEFT of the grid instead of on a row of its own. The window grows by the gutter; the
  -- grid origin shifts right by it; the grid itself is unchanged.
  local slimW = math.floor(theme.cell.size * (theme.slimLockScale or 0.5) + 0.5)
  local gutter = layout.slimGutter and (slimW + (theme.cell.pitchX - theme.cell.size)) or 0
  w = w + gutter
  frame:SetSize(w, h)

  local f = theme.frame
  -- Vertical stack under the title bar: [padTop] search row [gap] grid ... footer [padBottom].
  local searchH = theme.searchHeight or 20
  local searchTop = f.padTop + (theme.searchTopGap or (theme.titleHeight - searchH) / 2)
  frame.Grid:ClearAllPoints()
  frame.Grid:SetPoint("TOPLEFT", f.padLeft + gutter, -(f.padTop + theme.titleHeight))
  frame.Grid:SetSize(w - f.padLeft - f.padRight - gutter, rows * theme.cell.pitchY + extraH)

  local gridW = w - f.padLeft - f.padRight - gutter
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

  -- Cell assignment. Live slots (view.bag.live) take SECURE buttons from their own pool; everything
  -- else (lock, gap, mock slots) takes plain buttons. Secure buttons cannot be re-parented or shown/
  -- hidden in combat: if a layout change arrives mid-combat, remember it and replay on PLAYER_REGEN_ENABLED.
  local useSecure = view.bag.live == true
  if useSecure and InCombatLockdown() then
    view.renderDeferred = true
    Window.ApplySearch(frame.Search:GetText())
    return
  end
  local ci, si = 0, 0
  for r, row in ipairs(layout.rows) do
    local cellY = rowY[r]
    for _, cell in ipairs(row.cells) do
      local b
      if useSecure and cell.kind == Layout.CELL_SLOT and cell.ref then
        si = si + 1
        b = secureCells[si]
        if not b then b = NewSecureCell(si, cell.ref.bagID); secureCells[si] = b end
      else
        ci = ci + 1
        b = cells[ci]
        if not b then b = NewCell(ci); cells[ci] = b end
      end
      DressCell(b, cell, theme)
      b:ClearAllPoints()
      if cell.slim then
        -- Slim lock: half-width cell in the gutter immediately left of the grid, top row of its group.
        b:SetSize(slimW, theme.cell.size)
        b:SetPoint("TOPRIGHT", frame.Grid, "TOPLEFT", -(theme.cell.pitchX - theme.cell.size), cellY)
      else
        b:SetPoint("TOPLEFT", frame.Grid, "TOPLEFT", (cell.col - 1) * theme.cell.pitchX, cellY)
      end
      b:Show()
    end
  end
  for i = ci + 1, #cells do cells[i]:Hide(); cells[i].cell = nil end
  for i = si + 1, #secureCells do secureCells[i]:Hide(); secureCells[i].cell = nil end
  view.renderDeferred = false

  Window.ApplySearch(frame.Search:GetText())
  if ns.EditMode then ns.EditMode.OnWindowResized(w, h) end
end

function Window.ApplySearch(text)
  text = (text or ""):lower()
  local function apply(pool)
    for _, b in ipairs(pool) do
      if b:IsShown() and b.cell and b.cell.kind == Layout.CELL_SLOT and b.cell.ref and b.cell.ref.item then
        local name = b.cell.ref.item.name
        local miss = text ~= "" and (not name or not name:lower():find(text, 1, true))
        -- The dim also serves the "won't take the carried item" mark on occupied typed cells
        -- (SetNoDrop); the search must not undo it. ApplySearch runs after every DressCell.
        local refuses = b.noDrop ~= nil and b.noDrop:IsShown()
        if b.dim then b.dim:SetShown(miss or refuses) end
        if b.secure then SetItemButtonDesaturated(b, miss or b.cell.ref.item.locked) else b.icon:SetDesaturated(miss) end
      end
    end
  end
  apply(cells); apply(secureCells)
end

-- In-place update of the one secure cell showing `ref` (lock state during a Blizzard drag). No
-- re-parent, no re-anchor, no re-dress: only the desaturation. Anything heavier mid-gesture cancels
-- the client's own pickup.
function Window.RefreshRef(ref)
  if not frame or not frame:IsShown() then return end
  for _, b in ipairs(secureCells) do
    if b.cell and b.cell.ref == ref then
      local item = ref.item
      SetItemButtonDesaturated(b, item ~= nil and item.locked or false)
      return
    end
  end
end

-- Debug (/kondo cursor): which shown typed cells carry the no-drop mark, as "kind:slot".
function Window.DebugNoDrop()
  local out = {}
  for _, pool in ipairs({ secureCells, cells }) do
    for _, b in ipairs(pool) do
      if b:IsShown() and b.cell and b.cell.slotKind then
        out[#out + 1] = b.cell.slotKind .. ":" .. tostring(b.cell.ref and b.cell.ref.slot) .. (b.noDrop and b.noDrop:IsShown() and "=X" or "=ok")
      end
    end
  end
  return #out > 0 and table.concat(out, " ") or "(none)"
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
  -- Combat: a layout change requested mid-combat is deferred by Render; replay it when combat ends.
  if not view.regenFrame then
    view.regenFrame = CreateFrame("Frame")
    view.regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    view.regenFrame:SetScript("OnEvent", function()
      if view.renderDeferred and frame and frame:IsShown() then Window.Render() end
    end)
  end
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
function Window.SetMoney(copper)
  view.money = copper or 0
  if frame and frame.Money then frame.Money:SetText(FormatMoney(view.money)) end
end
function Window.Frame() return frame end
function Window.Show()
  CreateWindow(); Window.Render()
  if frame:IsShown() then return end
  frame:Show()
  if ns.StockBags then ns.StockBags.OnWindowShown(true) end     -- bag-bar highlight + open sound (SPECS/01 R7)
end
function Window.Hide()
  if not (frame and frame:IsShown()) then return end
  frame:Hide()
  if ns.ClearNewItems then ns.ClearNewItems() end                -- stock clears "new" flags on bag hide; so do we
  if ns.StockBags then ns.StockBags.OnWindowShown(false) end
end
function Window.Toggle() if frame and frame:IsShown() then Window.Hide() else Window.Show() end end
function Window.IsShown() return frame ~= nil and frame:IsShown() end

-- Size the window would have at `columns` for the current data (for Edit Mode snapping).
function Window.SizeForColumns(columns)
  if not view.bag then return 200, 150 end
  local rows = math.max(1, view.bag:RowCount(columns))
  return Theme.WindowSize(Theme_(), columns, rows)
end