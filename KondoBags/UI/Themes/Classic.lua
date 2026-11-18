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
  cell = { size = 37, pitchX = 42, pitchY = 41 },
  -- PortraitFrameTemplate: Bg starts at y=-21 (below the title bar), border ~6px each side.
  frame = { padLeft = 12, padRight = 12, padTop = 22, padBottom = 8 },
  titleHeight = 30,      -- search row under the title bar
  footerHeight = 20,     -- money
  backdrop = nil,
  portrait = true,
  titleFont = "GameFontNormal",
  slotNormal = { file = "Interface\\Buttons\\UI-Quickslot2", size = 64, offsetY = -1 },
  slotFlat = nil,
  slotBorder = nil,
  plusGlyph = { text = "+", font = "GameFontNormalLarge", color = { 1, 0.82, 0, 0.55 } },
  handleGlyph = { text = "\226\137\161", font = "GameFontNormalLarge", color = { 1, 0.82, 0, 0.55 } },  -- U+2261
  divider = { height = 1, color = { 1, 0.82, 0, 0.35 }, insetX = 4 },
  junkTint = { 0.55, 0.55, 0.55 },
})