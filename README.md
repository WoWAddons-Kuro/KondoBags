# KondoBags

A bag addon for World of Warcraft that organizes your backpack the way a tidy person would, without you writing a single rule.

The window is the stock bag grid plus **Keep**:

- **Incoming** — everything you loot, drawn exactly where the stock bag would draw it. New loot opens a new cell; nothing already there moves.
- **Keep** — one or more named rows at the bottom, each led by a lock cell. Drop an item on a lock to keep it; drag it back up to let it go; Shift-drag to choose its spot. Hearthstone starts there.

The `+` button adds another Keep row. Everything the addon remembers about how you sort is **per character**.

Position, scale and column count of the window are handled through **Edit Mode**.

KondoBags **replaces** the stock bag windows: `B`, the bag-bar buttons, vendors, mail and the bank all open it. There is no option to keep the stock bags alongside it; disable the addon to get them back.

## Clients

Classic Era / Hardcore and WoW: Forever are the tested targets. Other flavours are listed in the TOC and share the same code through a per-client provider layer; they are untested until noted in the changelog.

## Status

Alpha. See [`SPECS/00_KondoBags_Core.md`](SPECS/00_KondoBags_Core.md) for the design and milestone plan and [`SPECS/01_Stock_Bag_Replacement.md`](SPECS/01_Stock_Bag_Replacement.md) for how the stock bags are replaced. Current phase: **Phase L — live bags, step 5 (stock replacement)**.

## Repository layout

```
KondoBags/            the addon (what gets installed)
SPECS/                design specs
docs/                 notes and screenshots
spec/                 off-client tests, run with  lua5.1 spec/run.lua
```

## License

MIT. Bundled libraries keep their own licences in `KondoBags/Libs/*`.