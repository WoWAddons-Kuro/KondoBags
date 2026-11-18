-- KondoBags UI/Themes/Modern.lua -- flat dark panel, square cells, no ornament.

local _, ns = ...

ns.Theme.Register({
  id = "modern",
  cell = { size = 36, pitchX = 40, pitchY = 40, iconInset = 2 },
  sectionGapRows = 3,    -- gap between runs (incoming/groups) = 3x the normal inter-row gap
  frame = { padLeft = 10, padRight = 10, padTop = 8, padBottom = 8 },
  titleHeight = 40,
  -- Flat title bar: title text higher, small flat "x" close glyph instead of the stock round button.
  titleBar = { titleY = 6, closeSize = 18, closeInset = 6, portraitSize = 28,
               closeColor = { 0.65, 0.65, 0.65 }, closeHoverColor = { 1, 0.35, 0.35 } },
  searchHeight = 20,
  searchTopGap = 16,     -- below the title line
  searchWidthScale = 0.6,-- modern panel is denser; a 60%-width search box reads better than full
  searchFlat = { 1, 1, 1, 0.07 },   -- no textured border: a slightly lighter flat rectangle
  footerHeight = 20,
  backdrop = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    tile = false, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  },
  backdropColor = { 0.05, 0.05, 0.05, 0.9 },
  backdropBorderColor = { 0.12, 0.12, 0.12, 1 },   -- one step above the 0.05 panel; 0.25 read as a bright outline
  portrait = false,
  titleFont = "GameFontNormal",
  slotNormal = nil,
  slotFlat = { 0, 0, 0, 0.25 },          -- near-transparent interior; the border carries the cell
  slotBorder = { 0.32, 0.32, 0.32, 0.9 }, -- 1px ring, a step above the panel; not bright
  dropGlyph = { file = "Interface\\Icons\\INV_Misc_Key_03", desaturate = true, alpha = 0.35, inset = 7 },
  slimLockScale = 0.5,
  slimDropGlyph = { file = "Interface\\Icons\\INV_Misc_Key_03", desaturate = true, alpha = 0.4, inset = 2 },
  gapGlyph = { file = "Interface\\Icons\\INV_Misc_Key_03", desaturate = false, alpha = 0.8, inset = 7 },
  kindGlyph = {
    quiver     = { file = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Ammo",       desaturate = true, alpha = 0.3, inset = 3 },
    ammo       = { file = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Ammo",      desaturate = true, alpha = 0.3, inset = 3 },


    soul       = { file = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02", desaturate = true, alpha = 0.3, inset = 3 },
    herb       = { file = "Interface\\Icons\\INV_Misc_Herb_01",        desaturate = true, alpha = 0.3, inset = 3 },
    enchanting = { file = "Interface\\Icons\\INV_Enchant_DustIllusion", desaturate = true, alpha = 0.3, inset = 3 },
    mining     = { file = "Interface\\Icons\\INV_Pick_02",             desaturate = true, alpha = 0.3, inset = 3 },
    keyring    = { file = "Interface\\Icons\\INV_Misc_Key_14",         desaturate = true, alpha = 0.3, inset = 3 },
    reagent    = { file = "Interface\\Icons\\INV_Misc_Dust_02",        desaturate = true, alpha = 0.3, inset = 3 },
  },
  kindTint = ns.Theme.DEFAULT_KIND_TINT,
  divider = nil,
  junkTint = { 0.5, 0.5, 0.5 },
})