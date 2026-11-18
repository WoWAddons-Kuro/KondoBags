-- KondoBags UI/Themes/Modern.lua -- flat dark panel, square cells, no ornament.

local _, ns = ...

ns.Theme.Register({
  id = "modern",
  cell = { size = 36, pitchX = 40, pitchY = 40, iconInset = 2 },
  sectionGapRows = 3,    -- gap between runs (incoming/groups) = 3x the normal inter-row gap
  frame = { padLeft = 10, padRight = 10, padTop = 8, padBottom = 8 },
  titleHeight = 44,
  footerHeight = 20,
  backdrop = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    tile = false, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  },
  backdropColor = { 0.05, 0.05, 0.05, 0.9 },
  backdropBorderColor = { 0.25, 0.25, 0.25, 1 },
  portrait = false,
  titleFont = "GameFontNormal",
  slotNormal = nil,
  slotFlat = { 0, 0, 0, 0.25 },          -- near-transparent interior; the border carries the cell
  slotBorder = { 0.55, 0.55, 0.55, 0.9 }, -- 1px ring, brighter than the panel
  dropGlyph = { file = "Interface\\Icons\\INV_Misc_Key_03", desaturate = true, alpha = 0.35, inset = 7 },
  insertGlyph = { file = "Interface\\Icons\\INV_Misc_Key_03", desaturate = false, alpha = 0.8, inset = 7 },
  divider = nil,
  junkTint = { 0.5, 0.5, 0.5 },
})