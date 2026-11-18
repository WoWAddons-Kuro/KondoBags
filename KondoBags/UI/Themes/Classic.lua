-- KondoBags UI/Themes/Classic.lua -- the stock bag look. Metrics from Blizzard's ContainerFrame
-- (see _EXTERNAL_APIS/wow_classic_era_container_ui_api.md): 37px cells, 42x41 pitch, Quickslot2 art.

local _, ns = ...

ns.Theme.Register({
  id = "classic",
  cell = { size = 37, pitchX = 42, pitchY = 41 },
  frame = { padLeft = 12, padRight = 12, padTop = 8, padBottom = 10 },
  titleHeight = 52,      -- portrait row + search row
  footerHeight = 22,     -- money
  backdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  },
  backdropColor = { 1, 1, 1, 1 },
  backdropBorderColor = { 1, 1, 1, 1 },
  portrait = true,
  titleFont = "GameFontHighlight",
  slotNormal = { file = "Interface\\Buttons\\UI-Quickslot2", size = 64, offsetY = -1 },
  slotFlat = nil,
  slotBorder = nil,
  plusGlyph = { text = "+", font = "GameFontNormalLarge", color = { 1, 0.82, 0, 0.55 } },
  handleGlyph = { text = "\226\137\161", font = "GameFontNormalLarge", color = { 1, 0.82, 0, 0.55 } },  -- U+2261 ≡
  divider = { height = 1, color = { 1, 0.82, 0, 0.35 }, insetX = 4 },
  junkTint = { 0.55, 0.55, 0.55 },
})