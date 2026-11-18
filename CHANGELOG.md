# Changelog

## Unreleased

- **Stock bags replaced.** `B`, the bag-bar buttons, `/kondo`, Escape, and vendor / bank / mail / auction / trade all
  open and close the KondoBags window; the Blizzard bag frames never show. Hook-only (no stock function is replaced), so
  nothing is tainted; bag-bar buttons highlight while the window is open; stock open/close sounds. Bank bags still open
  as stock windows at the bank until bank support lands.
- Quest items get the stock quest border / `!` marker, slowly pulsing (on Era too, where stock hides it).
- The M0 mockup (`/kondo mock`) is gone; the window is always the real bags.
- M0 UI mockup: stock-look bag window drawn from fake data; incoming grid plus Keep rows, each led by a
  lock cell; drop on a lock to pin, Shift-drag to place, `+` adds a row, right-click a lock removes it;
  classic and modern themes; Edit Mode move and cell-snapped resize. `/kondo`.