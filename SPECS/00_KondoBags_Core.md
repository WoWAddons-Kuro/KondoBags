# SPEC 00 — KondoBags core: sectioned bag addon

- **Status:** Living spec (2026-11-18). Describes the addon as it is and as it will be; decisions in "Decisions log". History is not kept here — see git.
- **Name:** `KondoBags` (after Marie Kondo). Collision check done: none. Folder, TOC, SavedVariables and slash all use it.
- **Not related to `GotJunk/`.** KondoBags shares no code, data or dependency with it. Any junk-deletion widget is **out of scope** until the window is done.
- **Targets:** all current clients, with **Classic Era / Hardcore (interface 11509)** and **WoW: Forever (interface 16001)** as the clients we test on first. Cata/Mists/Retail get TOC lines and a clean provider seam, untested until later.
- **Repo shape:** packager-style, addon one level down (`KondoBags/KondoBags/KondoBags.toc`), like `DragonToast_upstream`. `cmd\publish.cmd` discovers it via rule 2 (`D\X\X.toc`).

Milestones:

- [ ] **M0 — UI mockup**: static in-game window from a fake snapshot, Edit Mode movable/scalable. No bag API, no data model. *Nothing in M1+ starts until the look is agreed.*
- [ ] M1 — Dev loop and bag model: Client providers, scanner, fixtures (tested off-client with `lua5.1`)
- [ ] M2 — *(reserved)*
- [ ] M3 — *(reserved)*
- [ ] M4 — Bag window live: incoming + Keep groups over real bags, secure buttons, restricted-slot runs, search, pins
- [ ] M5 — Two themes: classic and modern
- [ ] M6 — Keep special cases: gear identity, fishing swap, upgrade hold
- [ ] M7 — Late stage: bank, restricted-slot assists

## Overview

A bag replacement whose organizing idea is the stock bag grid plus **Keep**: items the player pins stay where they put them, in one or more named groups at the bottom of the window, while everything else ("incoming") fills the grid above in Blizzard's loot order exactly as the stock bag does. The player never writes a rule. The only manual acts are pinning, unpinning and reordering by drag and drop.

The mental model is **a person who organizes their own backpack**, not a bag automator. Everything the addon remembers about how *this character* sorts things is stored **per character**. There is no account-wide pin state.

## Philosophy: visual stability — minimise item movement

**Everything in KondoBags is designed around moving as few items as possible without ever changing their order, so the picture stays stable.** A cell the player has learnt the position of should still be there next time they open the bag. The one-line rule: **we never leapfrog items visually; when we need to move slots, we compress holes.** An item only ever steps into an adjacent hole, so the reading order of incoming is preserved and no item ever jumps past another. Concretely:

- Incoming is drawn in Blizzard's own slot order and is never re-sorted by us; new loot opens a *new* cell at the top-left frontier and nothing already visible moves.
- Keep positions are an indirection map (`order` lists), so reordering inside Keep is visual only — zero physical moves.
- When a physical move is unavoidable (a pin needs the top incoming slot; an unpin frees a Keep slot), the algorithm compresses the hole **nearest the blocking items**: the items between that hole and the top each step down one cell, in order, and the shift chain is as short as the free space allows. A freed Keep slot is filled with ONE swap (Keep's own order is visual, so a swap there leapfrogs nothing). Every rule in "Invariants (D13)" and the gesture table is a consequence of this principle; when a new case comes up, choose the move set that disturbs the fewest cells **without changing item order** (a single swap would be fewer cells, but it leapfrogs; it is never the answer).

The design goal is the smallest possible configuration surface and the least adornment. The complete settings list is in "Settings" and is meant to stay that short.

## Decisions log

| # | Decision | Rationale |
|---|---|---|
| D1 | KondoBags is a fresh repo with no relation to `GotJunk/` | Owner statement. |
| D2 | **All stored sorting state is per character** (`KondoBagsCharDB`). No account-wide pins. | The addon models one person's backpack. A new hardcore character starts with an empty Keep. |
| D3 | Window position and scale live in **Edit Mode** via vendored **LibEditMode** (p3lim), not in our settings | Blizzard gives addons no Edit Mode API; hand-rolling it taints Edit Mode. Era has Edit Mode since the July 2026 update, so one path serves every client. Pattern proven in `MoveMyBags.Kuro/EditMode.lua`. Removes "Window scale" from Settings. |
| D4 | **UI mockup before any data model** (M0) | Owner priority. The window is the product; argue about pixels first. |
| D5 | Client access goes through a **provider interface** (`Client/`) with one provider per API family plus a **mock provider** for off-client runs | More than one behaviour source per concern (Era quest log vs `C_QuestLog`), and the core must run under stock Lua 5.1. Use the better API where a client has it. |
| D6 | All flavours supported in TOC and seam; Era + Forever tested first | Owner priority. |
| D7 | Tests run with `lua5.1` (installed: `C:\ProgramData\chocolatey\bin\lua5.1.exe`, `luacheck` also present) | Confirmed on this machine 2026-11-17. |
| D8 | Libraries are **vendored** (unmodified, with `VENDORED.txt`), not git submodules | `publish.cmd` treats an empty submodule folder as missing and LibEditMode has no CurseForge zip to fall back on. |
| D9 | **MVC split in code**: `Core/Sections.lua` (model), `Core/Layout.lua` (pure layout), `Core/BagState.lua` (controller: owns store + slots + held item, `Pickup/Drop` decide pin-vs-swap, emits `changed`/`cursor`), `UI/Window.lua` (view only: draws `BagState:Layout()`, forwards gestures). | The view must never mutate the model. Drop semantics are now unit-tested and survive the M4 switch to secure buttons untouched; the mock item source is swapped for the Client provider inside the controller. |
| D10 | **Section UI = drop cells, not headers/handles/dividers.** A section is one run of cells: a single drop cell (faded lock glyph) immediately left of its first item, then its items. The unsectioned remainder ("incoming") is drawn above, exactly like the stock bag. A new character starts with one section, **Keep**, holding Hearthstone. More sections can be made later (UI not in M0). | Owner. Headers, dividers and handles read as gaudy next to the stock bag. |
| D11 | **Sections are physical slot ranges**, bottom-up from the highest slots; incoming = the low slots in Blizzard's loot order, drawn slot 0 bottom-right. Pin/unpin = physical move(s); on shrink the section returns its **lowest** slot. See "Sections are PHYSICAL slot ranges". | Owner, 2026-11-18. Incoming cells must never shift when cells are added/removed at its start; and the mock must behave exactly as M4's real `PickupContainerItem` moves will. |
| D12 | **One physical Keep range, many visual groups.** Physically there are exactly two ranges: incoming (`0 .. boundary-1`) and Keep (`boundary .. N-1`), with ONE boundary and the D11 grow/shrink rule. The UI "sections" below incoming are **groups**: named lists of Keep slots (`{ id, name, order }`) that together partition the Keep range. A `+` button (right of the search box) adds a new empty group. Dropping on group G's lock pins via D11 and records the new slot in `G.order`. When a shrink slides the lowest-slot item into a hole, the slot is renamed in whichever group's `order` held it, so visual membership follows the item. Incoming is always drawn first. | Owner, 2026-11-18. Keeps the loot invariant trivially (one boundary) and makes `+` a pure UI feature. |
| D13 | **Slot-model invariants, stated once** (see "Invariants" under Bag window): Keep never has a free slot; pinning SHIFTS incoming down (the one unavoidable incoming reshuffle); restricted bag types are extra incoming runs, no Keep for them; bag swaps move nothing because Keep positions are an indirection map. | Owner, 2026-11-18. |

## Architecture

```
            WoW events (bags, equipment, item-loaded)
                              |
                       +------v------+
                       |   Client    |   providers: Era, Mainline, Mock
                       +------+------+
                              |
   +----------+        +------v------+
   | Sections +------->|  Bag model  |   pure Lua, no WoW API
   | (char)   |        |  (snapshot) |
   +----------+        +------+------+
                              |
                       +------v------+                  +-------------+
                       |  BagState   |----------------->| Bag window  |
                       | (controller)|   Layout() +     | (view,      |
                       +-------------+   changed/cursor |  themes)    |
                                                        +-------------+
```

Three rules hold across the whole design:

1. **Core is pure Lua.** The bag model, section model, controller and layout take plain tables in and return plain tables out, with no WoW API calls. They run under stock Lua 5.1 against a dumped or mocked snapshot.
2. **Everything is event-driven.** No OnUpdate scanning and no repeating timers. A bag event marks state dirty; one coalesced flush recomputes.
3. **Sections are physical slot ranges (D11).** Incoming is the low slots in Blizzard's loot order; Keep is the fully occupied high slots. Pin, unpin and dissolve are the only things that move items, exactly as described in the gesture table.

### Repository layout

```
KondoBags/                              git repo  (github WoWAddons-Kuro/KondoBags)
  README.md  CHANGELOG.md  LICENSE(MIT)  .pkgmeta  .gitignore  .luacheckrc
  SPECS/
    00_KondoBags_Core.md                this file
    01_...                              later specs (themes, bank) as they split out
  docs/                                 design notes, mockup screenshots
  spec/                                 off-client tests:  lua5.1 spec/run.lua
    run.lua  fixtures/*.lua (dumped snapshots; M1)
  KondoBags/                            the addon; folder name == TOC name
    KondoBags.toc
    KondoBags.lua                       bootstrap, slash, events
    Core/                               pure Lua (D9): Sections.lua (model) Layout.lua BagState.lua (controller);
                                        M1+: Model.lua (snapshot / scanner output)
    Client/                             M1+: providers Client.lua (interface + selection), Era.lua, Mainline.lua, Mock.lua
    UI/                                 Window.lua (view) EditMode.lua Theme.lua Themes/Classic.lua Themes/Modern.lua
    Mock/                               MockSnapshot.lua (M0 fake data; shipped only while M0..M3 are in progress)
    Libs/                               LibStub, LibEditMode (vendored)
```

`.pkgmeta`: `package-as: KondoBags`, `move-folders: KondoBags/KondoBags: KondoBags`, `ignore: SPECS/, docs/, spec/, *.md`.

### Client provider interface

One table of functions the core and UI call; exactly one provider is selected at load from `WOW_PROJECT_ID` (with capability checks, not version checks, where a function may or may not exist). The Mock provider implements the same table from fixture data so the whole addon except frame creation runs under `lua5.1`.

```lua
-- pseudocode: illustrative only
KondoBags_ClientProvider = {
  name            = "Era" | "Mainline" | "Mock",
  BagIDs          = function() -> { KondoBags_BagID... }           -- backpack, equipped bags, reagent, keyring as the client has them
  NumSlots        = function(bagID) -> count
  FreeSlots       = function(bagID) -> numFree, bagFamilyBits
  SlotInfo        = function(bagID, slot) -> KondoBags_RawSlotInfo | nil
  ItemInfo        = function(itemIDOrLink) -> KondoBags_RawItemInfo | nil         -- nil until cached
  ItemInfoInstant = function(itemIDOrLink) -> KondoBags_RawItemInfoInstant
  OnItemLoaded    = function(bagID, slot, fn)                                       -- Item:CreateFromBagAndSlot:ContinueOnItemLoad or GET_ITEM_INFO_RECEIVED
  PickupSlot      = function(bagID, slot)
  EquippedLink    = function(invSlot) -> link | nil
  InCombat        = function() -> bool
}
```

Known provider differences (ground truth from `_EXTERNAL_APIS/wow_classic_era_quest_ui_api.md` and `_ref/blizzard/classic_era/*Documentation.lua`, fetched from the Era UI source):

| Concern | Era (1.15.x) | Mainline / Forever | Note |
|---|---|---|---|
| Item info | `C_Item.GetItemInfo` (18 returns, sellPrice #11), `C_Item.GetItemInfoInstant` present on Era | same | Legacy globals as fallback behind a capability check. |
| Containers | `C_Container.*` present (GotJunk relies on it on both clients) | same | |
| Reagent bag | none | bag index 5 | |
| Keyring, quiver, ammo, soul, herb, enchanting bags | present | to confirm on Forever | |
| Bank bag numbering | differs | differs | use `Enum.BagIndex` |
| Protected bank actions | not observed | some blocked for addons | M7 |
| `BAG_UPDATE_DELAYED` | believed present; **confirm with `/etrace`** | present | one-shot next-frame coalescing fallback either way |
| Settings panel | `Settings.RegisterAddOnCategory` present on Era 1.15 | same | |
| Edit Mode | present since July 2026 | present | via LibEditMode |

### Bag model

A snapshot is a flat list of slot records plus per-kind free counts.

```lua
-- pseudocode: illustrative only
KondoBags_SlotRecord = {
  bagID, slot,                -- physical address
  slotKind,                   -- KondoBags_SlotKind: "general" | "reagent" | "quiver" | "ammo" | "soul" | "herb" | "enchanting" | "keyring"
  itemID, link, count,
  quality, classID, subclassID, equipLoc, reqLevel, maxStack,
  sellPrice,                  -- per unit, 0 if none
  isQuestMarked,              -- item itself is a quest item
  isLocked,
  loaded,                     -- false until item data has arrived
}
KondoBags_Snapshot = { slots = { KondoBags_SlotRecord... }, free = { general = 5, reagent = 12, ... } }
```

**Slot kind.** Every bag has a kind. Backpack and ordinary bags are `general`. Restricted bags each get their own kind. Slots of different kinds are not interchangeable, so free space is always reported per kind and never as one total. Kind derives from the bag family bitmask (`1` quiver, `2` ammo, `4` soul, `32` herb, `64` enchanting, `256` keyring; reagent via `Enum.BagIndex.ReagentBag`).

**Async item data.** Item info can be missing when a slot is first scanned. Such records are stored with `loaded = false` (icon/count still drawn from the container API) and completed when the item-loaded callback arrives.

**Update flow.**

```lua
-- pseudocode: illustrative only
on BAG_UPDATE(bag)        -> dirtyBags[bag] = true
on BAG_UPDATE_DELAYED     -> flush()          -- rescan dirty bags, Reconcile the section store, notify views
on item loaded            -> complete that slot record, notify views
```

If a client does not fire `BAG_UPDATE_DELAYED`, the fallback is a single one-shot next-frame callback armed by the first `BAG_UPDATE` in a burst. That is coalescing, not polling.

### Saved variables

```lua
-- pseudocode: illustrative only
KondoBagsCharDB = {                       -- ## SavedVariablesPerCharacter
  version  = 1,
  sections = KondoBags_SectionStore,      -- D12: { nextID, boundary, list = { KondoBags_Group... } }; see "Bag window"
  window   = { point, x, y, columns },    -- KondoBags_WindowPlacement (+ locked = bool)
  swapOut  = { [gearKey] = true },        -- transient fishing swap-outs (M6)
}
KondoBagsDB = {                           -- ## SavedVariables (account): display-only, nothing about sorting
  theme = "classic" | "modern",
  kindTint = true,                        -- border tint on restricted-bag cells
}
```

Membership in Keep is by slot (D11), so no item IDs are stored. Gear identity (M6) only matters for `swapOut`, where two drops with the same item ID can differ by random suffix or enchant.

### Bag window

One window replaces the default bag frames. It hooks the standard open/close/toggle entry points and the bag keybinds.

**Starting point: the stock Combined Backpack, unchanged.** Same frame art, title bar, portrait, close button, search box, sort button, slot grid, money bar. The only thing classic bags lack is differentiation: the grid is one undifferentiated run of boxes. KondoBags adds *sections* on top of that grid and nothing else. **No labelled header rows, dividers or handles**: they stop it looking like the stock bag.

**Grid.** Column count comes from the window width; the window is **drag-resizable in Edit Mode, snapping to whole cells** (`KondoBagsCharDB.window.columns`; rows follow from content). Every run of cells is **bottom-anchored like the stock bags**: its last row is full and any partial row is the top row, right-aligned, so free space appears top-left. Empty slots stay as empty slot art (a faded bag icon), exactly like stock. Restricted bags (quiver, herb, soul, …) are one extra run above incoming (D13.3).

**Sections (D10).** The unsectioned remainder ("incoming") is drawn first. Below it, each section in display order is one run of cells: a single **drop cell** — stock empty-slot art with a faded lock glyph — immediately to the LEFT of the section's first item, then its items. Dropping a held item on the drop cell pins it into that section. No header, no divider, no handle. A new character starts with one section, **Keep**, holding Hearthstone, so the window reads as "the stock bag plus one more row with the hearthstone at the bottom-right".

```
 fresh character (10 columns)                   after dropping Linen Cloth on the lock cell
+------------------------------------------+   +------------------------------------------+
| (o) KondoBags                       [x]  |   | (o) KondoBags                       [x]  |
|           [ search          ]            |   |           [ search          ]            |
|                          [ ][ ][cloth]   |   |                             [ ][ ][ ]    |
|  [ ][ ][ ][ ][ ][ ][ ][ ][ ][ ]          |   |  [ ][ ][ ][ ][ ][ ][ ][ ][ ][ ]          |
|  [ ][ ][ ][ ][ ][ ][ ][ ][ ][ ]          |   |  [ ][ ][ ][ ][ ][ ][ ][ ][ ][ ]          |
|                          [lock][hearth]  |   |                   [lock][cloth][hearth]  |
|                             8s 62c       |   |                             8s 62c       |
+------------------------------------------+   +------------------------------------------+
```

**Sections are PHYSICAL slot ranges (D11, 2026-11-18).** The bag's slots `0..N` (in Blizzard's combined order) are cut into contiguous ranges, one per section, bottom-up: incoming owns `0 .. boundary-1`, the first section owns `boundary .. boundary2-1`, and so on. Three facts drive everything:

1. **Blizzard loots into the lowest free slot.** Incoming's slot order *is* Blizzard's loot order and is never reordered by us.
2. **Every section slot is always occupied** (a section is exactly as big as its item count), so loot never lands in a section. That means a section's *physical* slot order is irrelevant; its **visual order** is our own `order` list.
3. **Incoming is drawn with slot `0` bottom-right and higher slots walking left/up** (`N-1 … 1 0` in reading order), bottom-anchored with the partial row on top. New loot therefore appears at the top-left frontier in a *new* cell and **no existing incoming cell moves**. Cells being added or removed at the start of incoming (padding, reclaimed section slots) never shift the others.

```
 incoming (6 wide):   [5][4][3][2][1][0]        0 = anchor, bottom-right
 keep:                [lock][6][7][8]           physical slots 6..8, visual order = order list
```

**Invariant on shrink.** When a section loses an item, the slot it gives back to incoming **must be its lowest-numbered slot** (`boundary`), because that is where Blizzard loots next and it must become the top of incoming's sequence. Since section slot order is free, this costs at most ONE extra physical swap, never a cascade.

**Invariants (D13).** The slot model in four sentences; everything in the gesture table below follows from these.

1. **Keep never has a free slot.** A section is exactly as large as its item count. Whenever a Keep slot would become free, the item from Keep's **lowest** slot slides into it and that lowest slot is released to incoming (D11 shrink). Loot can therefore never land inside Keep.
2. **Pinning SHIFTS incoming down from the hole nearest the top; it never swaps.** To land an item from incoming slot `f` in Keep, Keep claims slot `boundary-1`. Let `e` be the **highest** FREE incoming slot above `f` — the free slot closest to the blocking items at the top (or `f` itself if there is none). The item is placed at `e`, then only the items in `e+1 .. boundary-1` step down one slot and the pinned item arrives at `boundary-1`. Everything below `e` never moves; incoming stays in Blizzard's loot order. This is the minimal-movement choice (see Philosophy): the chain is as short as the free space allows. Cost is `boundary-1-e` adjacent moves plus one place (one `PickupContainerItem` pair each in M4); zero if `f == boundary-1`, one if `boundary-1` is free. An item from OUTSIDE the bag (`f` = nil: bank, mail, trade cursor) uses the same rule with `e` = the highest free incoming slot; no free slot means the pin cannot happen, exactly like stock.
3. **Restricted bag types are ONE display-only run ABOVE incoming.** Quiver, ammo, soul, herb, enchanting, mining, keyring, reagent slots are concatenated in bag order into a single run (never one run per kind: that would stack rows and eat the screen), drawn above incoming with the same bottom-anchored, slot-0-bottom-right rule. Each cell carries its `KondoBags_SlotKind`: empty cells show a faded glyph for the kind, and every cell gets a subtle border tint per kind (`KondoBagsDB.kindTint`, default on). They are **not** in the general flat index, so `boundary`, Keep and every pin rule ignore them; a drop from a typed cell onto a lock, or of anything onto a typed cell, is refused — stock handles those bags. **No Keep for alternate bag types.**
4. **Bag swaps move nothing.** Keep positions are an **indirection map** (`group.order` lists slot indices; the view resolves them at render). There is no stored mapping from a visual Keep position to a bag/slot pair, so equipping, unequipping or rearranging bags re-indexes the flat slot list and `Reconcile` re-validates the ranges; no items are moved and no visual position changes unless the slot count itself shrank below the Keep range.

```
 pin item at slot 0, slots 2 and 4 free         unpin kept item at slot 7 onto EMPTY incoming slot 2:
 (boundary 6):
   before   5 _ 3 _ 1 0 | 6 7 8                  before   5 4 3 _ 1 0 | 6 7 8
   place    0→4 (e = 4, nearest the top) ; 5→4   move     7→2 ; hole at 7 ; 6→7 ; slot 6 released
   after    5 3 _ 1 _ | 0 6 7 8   (boundary 5)   after    _ 5 4 3 2 1 0 | 7 8   (boundary 7)
   (only item 5 moved; items 1 and 3 untouched;   (incoming order preserved; the freed slot is the
    slot 2 still free, slot 0 now free)            top-left one, where Blizzard loots next)
```

Terminology: the Shift-drag phantom is the **cursor gap** (`KondoBags_CursorGap`): the cell drawn under the mouse while an item is carried with Shift down, anchored to the kept item that was hovered (`anchorRef`; nil = the lock). The gap takes the anchor's column and the anchor slides one cell left, which on a right-aligned row is exactly what puts the gap under a mouse that was over the anchor. It opens where the mouse is and does not move until the mouse enters a cell naming a different anchor.

| Gesture | Physical moves (`PickupContainerItem` pairs in M4; table swaps in the mock) | Visual result |
|---|---|---|
| Drop kept `k` (slot `s_k`) on **occupied** incoming slot `t` | swap `s_k ↔ t` | `k` now loose at `t`'s cell; old `t` is kept, takes `k`'s place in `order`. Boundary unchanged |
| Drop kept `k` on **empty** incoming slot `t` | move `k → t`; if `s_k ≠ boundary` then swap `boundary ↔ s_k`; `boundary += 1` | `k` appears at `t`; the section is one shorter; incoming gains slot `boundary-1` at its top-left; nothing else in incoming moves. Example: `5 4 3 2 1 0 \| 6 7 8`, drag 7 → empty 2 ⇒ `6 5 4 3 2 1 0 \| 7 8` |
| Drop loose `l` (slot `s_l`) on a section's **lock cell** | `e` = highest free incoming slot above `s_l`, else `s_l`; move `s_l → e` if different; then for `s = e .. boundary-2` swap `s ↔ s+1` (each carries `l` one up and the displaced item one down); `boundary -= 1`; `order` gains `l` at the front | `l` appears right of the lock. Incoming stays in loot order; the hole moves from `e` to `s_l` (D13.2). Zero moves if `s_l == boundary-1`; one move if `boundary-1` is free. |
| Drop kept `k` on kept `j` (same section) | none (or one swap; slot order is free) | reorder: `k` takes `j`'s position in `order` |
| **Shift** while carrying over a section | none until drop; drop = pin/reorder as above, at the phantom's index | phantom insert cell opens under the mouse; gap closes when Shift is released |
| Loose on loose / empty | stock swap/place | stock |
| Hover the lock cell | — | tooltip: section name, count, "drop an item here to keep it" |
| *(later)* right-click the lock cell | — | rename, dissolve, new section |

```lua
-- pseudocode: illustrative only
KondoBagsCharDB.sections = {                 -- KondoBags_SectionStore; list order = display order, bottom-up in slots
  nextID = 2,
  list = {
    { id = "s1", name = "Keep", boundary = 6, order = { 7, 8, 6 } },   -- owns slots 6..N; order = visual, by slot index
  },
}
-- Membership is BY SLOT (slot >= boundary), not by itemID. `order` lists the section's slots in visual order.
-- Moving an item physically into or out of the range is what pins/unpins it.
```

Consequences: (a) a drop **may need a free slot only when the gesture is itself a physical place into an empty slot**, exactly like stock; pinning never does, it swaps; (b) `BagState:Drop` returns the list of moves, which the mock applies to the slot table and M4 applies through the Client provider; (c) `Partition` is now trivial — slots below `boundary` descending are incoming, slots at/above are the section in `order`.

**M0 mockup scope:** stock-looking window from a fake snapshot; default Keep group with lock cell; mock pick-up (carry icon follows the mouse) and drop-to-pin; `+` adds a group, right-click a lock removes it; Edit Mode move + cell-snapped resize.

**Secure item buttons.** Right-click-to-use must work in combat, so every item cell is the client's own container item button template (`ContainerFrameItemButtonTemplate`), with the bag ID on its parent frame (`SetID(bag)`) and the slot ID on the button (`SetID(slot)`). These cannot be created or re-parented during combat. The window keeps a pool sized to total slot count, built out of combat, and any layout change requested in combat is deferred to `PLAYER_REGEN_ENABLED`. Content updates that do not re-parent (icon, count, dimming) may still run in combat.

**Pinning by direct manipulation.** Drop on a group's lock cell (or on the Shift-drag cursor gap) pins; drop on an incoming cell unpins. Later: modifier-click shortcut.

**Search.** A small edit box in the upper right. On each text change, every visible item whose name does not contain the query (case-insensitive, plain substring) is desaturated and dimmed; matches stay normal. Empty box restores everything. Escape clears and unfocuses. Appearance-only, so safe in combat.

**Edit Mode.** The window is registered with LibEditMode (`lib:AddFrame`, `lib:AddFrameSettings` for scale, `lib:AddFrameSettingsButtons` for reset). Position/scale are owned by the library's layout storage. In Edit Mode the window also gets a **resize grip**; dragging it snaps the size to whole cells and stores `KondoBags_GridColumns`/`KondoBags_GridRows`. Minimum is the number of columns needed so every slot fits. The window being a toggled panel, Edit Mode shows a placeholder the window's last size when it is closed (pattern: `MoveMyBags.Kuro/EditMode.lua`).

### Themes

A theme is a data table (textures, borders, background, fonts, cell art, lock/gap glyphs, section gap, metrics) consumed by one renderer. No theme-specific code paths. **`classic` is the default**: the window must look like the stock Combined Backpack of the client it runs on. A **modern** theme is the second option and must exist from M0 so the renderer is proven theme-agnostic.

| Theme (`KondoBags_ThemeID`) | Intent |
|---|---|
| `classic` | Stock bag art for the running client: `ButtonFrameTemplate`/portrait frame, stock slot textures, stock fonts, stock search box and money frame. **Default.** |
| `modern` | Flat dark panel, thin 1px borders, square cells, no portrait, modern font sizing. |
| `skinned` | Not our art at all: when a UI theming addon is present, defer to it so KondoBags looks like the rest of the user's UI. |

**Skinning / theme addons.** Where a theme library or UI suite exists, expose the frames so it can skin them rather than painting our own look over theirs:

- **ElvUI**: register the window with `E:GetModule("Skins")` style hooks (`S:HandleFrame`, `S:HandleEditBox`, `S:HandleItemButton`) when `ElvUI` is loaded; the stock `ContainerFrameItemButtonTemplate` cells are what ElvUI's bag skin already knows how to handle.
- **Masque** (`LibStub("Masque")`): register the item cells as a Masque group `"KondoBags"` so button-skin packs apply. This is the one library that is *specifically* for item buttons and is widely installed on Classic.
- **LibSharedMedia-3.0**: fonts and the divider/background textures are looked up by name so a user's SharedMedia choices apply.

Order of precedence at load: a loaded skinning addon wins (`skinned`), else the saved `KondoBagsDB.theme`, else `classic`. The theme can be switched live without reload (re-run the renderer over the same pool).

### Settings

The intended complete list:

| Setting | Values | Default | Where |
|---|---|---|---|
| Theme | classic / modern | classic | Settings panel |
| Bag-type border tint | on / off | on | Settings panel (`/kondo tint` for now) |
| Lock position | locked / movable | movable | Settings panel **and** the Edit Mode dialog for the window (`KondoBagsCharDB.window.locked`). Movable = the window drags by its frame at any time, as most addons do; locked = only in Edit Mode. |
| Window position, scale and column count | — | — | **Edit Mode**: drag the frame; drag its corner grip to set columns (width snaps to whole cells, height follows). Not a setting of ours. |

Pins are managed in the window itself. Anything proposed beyond this list needs a reason it cannot be a fixed behaviour.

### Keep special cases (M6)

**Fishing swap.** When `PLAYER_EQUIPMENT_CHANGED` fires for main-hand (16) or off-hand (17) and the newly equipped main-hand item is a fishing pole (class Weapon `2`, subclass `20`), the items that just left those two slots are recorded in `swapOut` (keyed by the full item link: item ID plus suffix and enchant fields, or a per-instance GUID where the client exposes one) and pinned into Keep. The record clears when they are equipped again. Per character, survives reload.

**Upgrade hold.** An equippable item the class can use whose required level is above the player's level is flagged as a possible future upgrade and surfaced as a one-click suggestion to pin, not placed automatically. A held upgrade shows its required level on the cell.

### Late stage (M7)

- **Bank**: same window and section model over bank bags, plus a saved snapshot for viewing away from the bank. Forever's protected bank actions may stay with the stock UI.
- **Restricted-slot assists**: colour ring on `general` items that fit a restricted bag with free space; optional auto-move on a player action, never on a timer.

## Bringup phases

Each phase ends with something usable in play, and nothing is built before the loop that tests it.

### Phase 0 — UI mockup (M0)

- [x] Repo skeleton: `.pkgmeta`, `.gitignore`, `.luacheckrc`, LICENSE, README, CHANGELOG, `PROJECT_STRUCTURE.md` entry
- [x] `KondoBags/KondoBags.toc` loading on Era (seen 2026-11-17); vendored LibStub + LibEditMode. Forever: to confirm
- [x] `Mock/MockSnapshot.lua`: 16-slot backpack + 6-slot bag with real icon paths and counts (no restricted strips in this iteration)
- [x] `UI/Theme.lua` + `Themes/Classic.lua` + `Themes/Modern.lua`: metrics and colours as data
- [x] `UI/Window.lua`: view only (D9); stock-look frame, bottom-anchored grid, lock drop cell per section (D10), mock pickup with carry icon, drop-to-pin, search
- [x] `Core/Sections.lua` + `Core/Layout.lua` + `Core/BagState.lua` (D9); 17 off-client tests
- [x] `UI/EditMode.lua`: placeholder registered with LibEditMode; drag + cell-snapped resize grip. In-game verification pending
- [x] `/kondo` toggles the mock window; `/kondo status`, `theme`, `columns`, `reset`
- [ ] Visual sign-off on classic theme: lock drop cell look pending; portrait/search/bg/money/footer accepted 2026-11-17
- [x] Spec hygiene: no history, only current design

Exit criteria: owner looks at it on both clients and signs off on frame art, spacing, cell art, lock cell. Screenshots saved to `docs/`.

### Phase 1 — Dev loop and bag model (M1)

- [ ] `Client/` provider interface, Era and Mainline providers, Mock provider over fixtures
- [ ] Scanner producing a `KondoBags_Snapshot`; slot-kind detection; async item completion
- [ ] `/kondo dump` writes the current snapshot to SavedVariables; a script copies it into `spec/fixtures/`
- [ ] `spec/run.lua` harness under `lua5.1`: loads fixtures through the Mock provider, runs Reconcile + Partition + Layout, asserts the picture

Exit criteria: tests run in about a second with no game running; addon loads on Era and Forever with no errors; dumped snapshot matches the bags by hand count, including per-kind free slots.

### Phase 4 — Bag window live (M4)

- [ ] Layout solver in `Core/Layout.lua` (sections and strips in, cell rectangles out), with tests
- [ ] Secure button pool; combat-deferred layout
- [ ] Mock renderer replaced by live snapshot; `Mock/` removed from the TOC
- [ ] Replace default bags: toggle hooks and keybinds
- [ ] Drop-to-pin and modifier-click pin through `C_Container.PickupContainerItem`; "kept in <group>" tooltip line

Exit criteria: right-click use, drag, split-stack, vendor sell and trade all work from the window, in and out of combat; default bags not needed in normal play.

### Phase 5 — Themes (M5) · Phase 6 — Keep special cases (M6) · Phase 7 — Late stage (M7)

As in the sections above; each gets its own `SPECS/0N_*.md` when work starts.

## API surface (to verify per client as each phase reaches it)

**Bags:** `C_Container.GetContainerNumSlots`, `.GetContainerItemInfo` (table: `iconFileID, stackCount, isLocked, quality, hyperlink, hasNoValue, itemID, isBound`), `.GetContainerNumFreeSlots` → `numFree, bagFamily`, `.GetContainerItemQuestInfo` (Era: confirm), `.PickupContainerItem` + `DeleteCursorItem()`, `GetItemFamily(item)` bitmask. Bag IDs via `Enum.BagIndex`.

**Items:** `C_Item.GetItemInfo` (nil until cached), `C_Item.GetItemInfoInstant`, `Item:CreateFromBagAndSlot(bag, slot):ContinueOnItemLoad(fn)`, `GET_ITEM_INFO_RECEIVED`. Constants: quality Poor `0`, Common `1`; class Quest `12`; bind type quest `4`; class Weapon `2` subclass Fishing Poles `20`; Hearthstone `6948`.

**Equipment and combat:** `PLAYER_EQUIPMENT_CHANGED(slot, hasCurrent)`, `GetInventoryItemLink("player", slot)`, `InCombatLockdown()`, `PLAYER_REGEN_ENABLED`.

**LibEditMode (vendored, minor 18):** `lib:AddFrame(frame, cb(frame, layoutName, point, x, y), defaultTable, name)`; frame must be parented to `UIParent` and movable. `lib:AddFrameSettings(frame, settings)`, `lib:AddFrameSettingsButtons(frame, buttons)`, `lib:RegisterCallback('enter'|'exit'|'layout', fn)`, `lib:IsInEditMode()`.

### References

- Workspace ground truth: `_EXTERNAL_APIS/wow_classic_era_quest_ui_api.md`, `_ref/blizzard/classic_era/ItemDocumentation.lua`, `QuestLogDocumentation.lua`, `QuestLogFrame.lua`
- Edit Mode pattern: `MoveMyBags.Kuro/EditMode.lua`, `MoveMyBags.Kuro/Libs/LibEditMode/`
- Repo shape: `DragonToast_upstream/` (`.pkgmeta` move-folders, `.luacheckrc`, `spec/wow_mock.lua`)
- Workspace rules: `PROJECT_STRUCTURE.md` (publishing/releasing by the owner only; folder == TOC name; version tag `vYYYY.MM.DD.HHMM`)
- [World of Warcraft API index](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API) · [C_Container.GetContainerItemInfo](https://warcraft.wiki.gg/wiki/API_C_Container.GetContainerItemInfo) · [GetContainerNumFreeSlots](https://warcraft.wiki.gg/wiki/API_C_Container.GetContainerNumFreeSlots) · [ItemMixin](https://warcraft.wiki.gg/wiki/ItemMixin) · [BagID](https://warcraft.wiki.gg/wiki/BagID) · [BAG_UPDATE_DELAYED](https://warcraft.wiki.gg/wiki/BAG_UPDATE_DELAYED) · [DeleteCursorItem](https://warcraft.wiki.gg/wiki/API_DeleteCursorItem) · [TOC format](https://warcraft.wiki.gg/wiki/TOC_format) · [LibDataBroker-1.1](https://github.com/tekkub/libdatabroker-1-1) · [LibEditMode](https://github.com/p3lim-wow/LibEditMode)

## Open questions

- **`BAG_UPDATE_DELAYED` on Era** — confirm with `/etrace`; fallback exists either way.
- **Per-instance item identity on Era** — whether a bag-item GUID call exists. If not, gear key = link suffix + enchant fields.
- **Forever specifics** — whether Era's typed bags exist; which bank actions are protected; whether any bag or quest data is restricted in combat.
- **Stock art for `classic`** — which textures/atlases exist on each client now that Era runs the newer UI framework.
- **Edit Mode and a toggled window** — whether to register the live window itself (hidden frames cannot be dragged) or a placeholder that the window follows, as MoveMyBags.Kuro does. Decide during M0.
- **Pin on drop vs. the client's own drag.** `OnReceiveDrag` on a plain frame fires when the mouse is released over it with an item on the cursor; confirm it also fires on Era for frames that are not item buttons, else fall back to `OnMouseUp` + `CursorHasItem()`.
