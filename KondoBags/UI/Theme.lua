-- KondoBags UI/Theme.lua -- theme registry. A theme is a data table; UI/Window.lua is the only consumer.
--
-- KondoBags_Theme = {
--   id            = KondoBags_ThemeID ("classic" | "modern"),
--   cell          = { size, pitchX, pitchY },                       -- item cell square and grid pitch
--   frame         = { padLeft, padRight, padTop, padBottom },       -- grid inset from the window edge
--   titleHeight   = number,                                         -- room above the grid for title / search
--   footerHeight  = number,                                         -- room below the grid for money
--   backdrop      = BackdropTemplate table | nil,                   -- window background/border
--   backdropColor = { r, g, b, a }, backdropBorderColor = { r, g, b, a },
--   portrait      = bool,                                           -- draw the round bag portrait
--   titleFont     = font object name,
--   slotNormal    = { file, size, offsetY }  | nil,                 -- empty-slot art under each cell (nil = flat)
--   slotFlat      = { r, g, b, a } | nil,                           -- flat cell background (modern)
--   slotBorder    = { r, g, b, a } | nil,                           -- 1px border (modern)
--   plusGlyph     = { text, font, color },                          -- the + cell
--   handleGlyph   = { text, font, color },                          -- the section handle cell
--   divider       = { height, color, insetX },                      -- line between sections
--   junkTint      = { r, g, b }                                     -- later: dim junk cells
-- }

local _, ns = ...
local Theme = {}
ns.Theme = Theme

local registry = {}   -- KondoBags_ThemeID -> KondoBags_Theme

function Theme.Register(theme)
  registry[theme.id] = theme
end

function Theme.Get(id)
  return registry[id] or registry.classic
end

function Theme.IDs()
  local ids = {}
  for id in pairs(registry) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

-- Width/height of a window that shows `columns` x `rows` cells under `theme`.
function Theme.WindowSize(theme, columns, rows)
  local w = theme.frame.padLeft + columns * theme.cell.pitchX - (theme.cell.pitchX - theme.cell.size) + theme.frame.padRight
  local h = theme.frame.padTop + theme.titleHeight + rows * theme.cell.pitchY - (theme.cell.pitchY - theme.cell.size)
    + theme.footerHeight + theme.frame.padBottom
  return w, h
end

-- Inverse: how many whole columns fit in a window `width` wide.
function Theme.ColumnsForWidth(theme, width)
  local inner = width - theme.frame.padLeft - theme.frame.padRight + (theme.cell.pitchX - theme.cell.size)
  return math.max(1, math.floor(inner / theme.cell.pitchX + 0.0001))
end