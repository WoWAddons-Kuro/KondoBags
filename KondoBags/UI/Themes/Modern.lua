-- KondoBags UI/Themes/Modern.lua -- flat dark panel, square cells, no ornament.

local _, ns = ...

ns.Theme.Register({
  id = "modern",
  cell = { size = 36, pitchX = 40, pitchY = 40 },
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
  slotFlat = { 0.12, 0.12, 0.12, 0.9 },
  slotBorder = { 0.3, 0.3, 0.3, 1 },
  plusGlyph = { text = "+", font = "GameFontNormalLarge", color = { 0.8, 0.8, 0.8, 0.5 } },
  handleGlyph = { text = "\226\137\161", font = "GameFontNormalLarge", color = { 0.8, 0.8, 0.8, 0.5 } },
  divider = { height = 1, color = { 0.5, 0.5, 0.5, 0.5 }, insetX = 2 },
  junkTint = { 0.5, 0.5, 0.5 },
})