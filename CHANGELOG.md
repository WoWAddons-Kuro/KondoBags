# Changelog

## Unreleased

- **Shift-insert.** Holding Shift while carrying an item shows a thin amber insert marker on the boundary
  nearest the mouse inside a section; dropping there inserts the item at that spot. Nothing in the grid moves
  and a Shift-drop never swaps. Works in combat (the redraw waits for combat to end). The old sliding
  "cursor gap" phantom is gone. Incoming rows and the special-bag strip are not insert targets yet.
- **Stack adoption** (Settings > Item utilities, "Create new stacks next to existing stacks", default on): loot that
  starts a new stack of an item you already keep in a section is drawn in that section right in front of the existing
  stack. The item is not moved; only where it is drawn changes.
- New-item glow is white instead of green (green read as uncommon gear).
- Settings: "Item utilities" section with an "Always compare items in tooltips" checkbox (Blizzard's `alwaysCompareItems` CVar, default off).
- Mousing over a "new" item clears its green glow at once (stock mainline does this too; stock Era does not).
  The glow's 1-second pulse is Blizzard's template animation, unchanged.
- App icon on the Settings panel (`Media\KondoBags_Icon.tga`).
- **Stock bags replaced.** `B`, the bag-bar buttons, `/kondo`, Escape, and vendor / bank / mail / auction / trade all
  open and close the KondoBags window; the Blizzard bag frames never show. Hook-only (no stock function is replaced), so
  nothing is tainted; bag-bar buttons highlight while the window is open; stock open/close sounds. Bank bags still open
  as stock windows at the bank until bank support lands.
- Quest items get the stock quest border / `!` marker, slowly pulsing (on Era too, where stock hides it).
- The M0 mockup (`/kondo mock`) is gone; the window is always the real bags.
- M0 UI mockup: stock-look bag window drawn from fake data; incoming grid plus Keep rows, each led by a
  lock cell; drop on a lock to pin, Shift-drag to place, `+` adds a row, right-click a lock removes it;
  classic and modern themes; Edit Mode move and cell-snapped resize. `/kondo`.