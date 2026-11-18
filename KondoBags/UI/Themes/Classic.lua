-- KondoBags UI/Themes/Classic.lua -- the stock bag look.
--
-- The frame is Blizzard's own PortraitFrameTemplate (Blizzard_SharedXML/SharedUIPanelTemplates.xml):
-- rock background, nine-slice border, 62px circular portrait outset at TOPLEFT (-5, 7), title bar
-- with TitleContainer.TitleText (GameFontNormal) and UIPanelCloseButtonDefaultAnchors. Grid metrics
-- from ContainerFrame (see _EXTERNAL_APIS/wow_classic_era_container_ui_api.md): 37px cells,
-- 42x41 pitch, UI-Quickslot2 art. Everything here is data; UI/Window.lua draws it.

local _, ns = ...

ns.Theme.Register({
  id = "classic",
  frameTemplate = "PortraitFrameTemplate",   -- Blizzard frame; backdrop fields below are ignored when set
  portraitScale = 0.82,                         -- stock 62px circle is too big for a bag; ~30% smaller
  bgTint = { 0.72, 0.72, 0.72, 0.8 },          -- PortraitFrame Bg: ~30% darker, 20% more transparent than stock
  cell = { size = 37, pitchX = 42, pitchY = 41, iconInset = 2 },
  sectionGapRows = 3,    -- gap between runs (incoming/groups) = 3x the normal inter-row gap
  -- PortraitFrameTemplate: Bg starts at y=-21 (below the title bar), border ~6px each side.
  frame = { padLeft = 12, padRight = 12, padTop = 22, padBottom = 8 },
  titleHeight = 38,      -- search row under the title bar (search box + gaps)
  searchHeight = 20,
  searchTopGap = 10,     -- air between the title bar and the search box
  searchWidthScale = 0.7,-- 30% narrower than the grid, left-aligned
  footerHeight = 24,     -- money bar
  moneyFont = "GameFontNormal",                -- ~10% larger than Small, full brightness (white via SetTextColor)
  moneyColor = { 1, 1, 1 },
  backdrop = nil,
  -- Stock backpack draws the money inside a thin bordered strip across the whole bottom row.
  footerBar = {
    backdrop = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
                 insets = { left = 2, right = 2, top = 2, bottom = 2 } },
    bgColor = { 0, 0, 0, 0.35 }, borderColor = { 0.62, 0.45, 0.2, 0.9 },
    height = 20, insetX = 2,
  },
  portrait = true,
  titleFont = "GameFontNormal",
  slotNormal = { file = "Interface\\Buttons\\UI-Quickslot2", size = 64, offsetY = -1 },
  -- Stock bags show a desaturated bag icon inside each empty slot; for now the same icon as the portrait.
  slotEmptyIcon = { file = "Interface\\Icons\\INV_Misc_Bag_08", desaturate = true, alpha = 0.45, inset = 2, tint = 0.9 },
  slotFlat = nil,
  slotBorder = nil,
  -- Section drop cell: a faded lock icon over the empty-slot art. Drop an item on it to pin it there.
  dropGlyph = { file = "Interface\\Icons\\INV_Misc_Key_03", desaturate = true, alpha = 0.4, inset = 7 },
  -- Slim lock: the half-width gutter lock drawn when a group's items fill whole rows (Layout.slimGutter).
  slimLockScale = 0.5,
  slimDropGlyph = { file = "Interface\\Icons\\INV_Misc_Key_03", desaturate = true, alpha = 0.45, inset = 2 },
  slimLockBg = { 0, 0, 0, 0.35 },
  gapGlyph = { file = "Interface\\Icons\\INV_Misc_Key_03", desaturate = false, alpha = 0.85, inset = 7 },  -- Shift-drag cursor gap
  -- Restricted-bag slots (KondoBags_SlotKind): faded glyph behind EMPTY cells and a subtle border tint
  -- on every cell of that kind (tint is toggled by KondoBagsDB.kindTint).
  kindGlyph = {
    quiver     = { file = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Ammo",       desaturate = true, alpha = 0.4, inset = 2, tint = 0.9 },
    ammo       = { file = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Ammo",      desaturate = true, alpha = 0.4, inset = 2, tint = 0.9 },



    soul       = { file = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02", desaturate = true, alpha = 0.4, inset = 2, tint = 0.9 },
    herb       = { file = "Interface\\Icons\\INV_Misc_Herb_01",        desaturate = true, alpha = 0.4, inset = 2, tint = 0.9 },
    enchanting = { file = "Interface\\Icons\\INV_Enchant_DustIllusion", desaturate = true, alpha = 0.4, inset = 2, tint = 0.9 },
    mining     = { file = "Interface\\Icons\\INV_Pick_02",             desaturate = true, alpha = 0.4, inset = 2, tint = 0.9 },
    keyring    = { file = "Interface\\Icons\\INV_Misc_Key_14",         desaturate = true, alpha = 0.4, inset = 2, tint = 0.9 },
    reagent    = { file = "Interface\\Icons\\INV_Misc_Dust_02",        desaturate = true, alpha = 0.4, inset = 2, tint = 0.9 },
  },
  kindTint = ns.Theme.DEFAULT_KIND_TINT,
  divider = nil,
  junkTint = { 0.55, 0.55, 0.55 },
})