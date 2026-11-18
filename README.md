# KondoBags

A bag addon for World of Warcraft that organizes your backpack the way a tidy person would, without you writing a single rule.

Five fixed sections, filled automatically:

| Section | What lands there |
|---|---|
| **Quest** | Items marked as quest items, plus ordinary items a quest in your log is asking for |
| **Upcoming** | Items a quest you are not on yet will ask for *(late stage)* |
| **Keep** | Whatever you pin there. Hearthstone starts there. |
| **Everything else** | The rest |
| **Junk** | Greys, and anything you pin as junk |

The only manual acts are pinning an item to Keep or to Junk. Everything the addon remembers about how you sort is **per character**. Nothing is physically moved between bags; sections are how items are drawn.

Also included: the **Toss line** *(working name)* — an always-visible one-liner showing the least valuable droppable stack in your bags. One click deletes it. Quest items, Keep pins and anything above Common quality are never offered.

Position and scale of the window and the Toss line are handled through **Edit Mode**.

## Clients

Classic Era / Hardcore and WoW: Forever are the tested targets. Other flavours are listed in the TOC and share the same code through a per-client provider layer; they are untested until noted in the changelog.

## Status

Pre-alpha. See [`SPECS/00_KondoBags_Core.md`](SPECS/00_KondoBags_Core.md) for the design and milestone plan. Current milestone: **M0 — UI mockup**.

## Repository layout

```
KondoBags/            the addon (what gets installed)
SPECS/                design specs
docs/                 notes and screenshots
spec/                 off-client tests, run with  lua5.1 spec/run.lua
```

## License

MIT. Bundled libraries keep their own licences in `KondoBags/Libs/*`.