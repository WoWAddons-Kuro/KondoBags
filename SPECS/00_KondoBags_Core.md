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
- Every gesture costs **at most one server operation** and moves **no occupied cell**. Positions are virtual (D15): pinning marks a slot kept, unpinning unmarks it, and the only thing that ever re-sorts is the pool of EMPTY incoming cells, kept in ascending physical order so Blizzard's next loot lands top-left. Empties are indistinguishable, so that re-sort is invisible. Every rule in "Invariants (D13)" and the gesture table is a consequence of this principle; when a new case comes up, the answer is a map change, not a move.

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
| D12 | **One Keep set, many visual groups.** Keep is a set of physical slots; the UI "sections" below incoming are **groups**: named lists of kept slots (`{ id, name, order }`) that together partition the set. A `+` button (right of the search box) adds a new empty group. Dropping on group G's lock pins the slot into `kept` and records it in `G.order`. Incoming is always drawn first. | Owner, 2026-11-18. `+` is a pure UI feature. |
| D13 | **Slot-model invariants, stated once** (see "Invariants" under Bag window): Keep never has a free slot; at most ONE server operation per gesture; restricted bag types are one extra run, no Keep for them; bag swaps move nothing because everything is an indirection map. | Owner, 2026-11-18. |
| D15 | **Virtual positions over a sorted free pool.** The window draws VISUAL positions through one indirection map; Keep is a scattered SET of physical slots, never a range. Occupied incoming cells never move. All FREE general slots are drawn at incoming's top-left end in ascending physical order, so the lowest free physical slot -- where Blizzard loots next -- is always the top-left cell; this pool is re-sorted on every change (invisible: empties are identical). Pin from incoming = zero moves (mark kept); pin from outside = one `PickupContainerItem` into the lowest free slot; unpin = Blizzard's own swap; dissolve = zero moves. **No chain-shift exists.** | Owner, 2026-11-18. The physical-range model needed `boundary-1-e` chained server moves per pin, each gated by the client on a lock round-trip -- the player had to click once per shifted item. One server operation per gesture is the only thing the client will give us, and this is the only model that achieves it with the UI unchanged. |
| D14 | **Live cursor model.** Item cells are `ContainerFrameItemButtonTemplate`; **Blizzard owns every slot-to-slot gesture** (pickup, swap, split, use, sell) and we observe the result on `BAG_UPDATE_DELAYED`. We own only the gestures that have no stock meaning: drop on a **lock** / **cursor gap** (pin or reorder) and `+` / remove group. `BagState.held` is a VIEW of `GetCursorInfo()`, not our own state. An **external** cursor item (bank, mail, trade, guild bank: not in our general flat list) dropping on a lock is `PinFromIncoming(fromSlot = nil)`: it needs a free general slot; **when there is none the lock and gap cells are hidden** while that cursor is held. | Owner + assistant, 2026-11-18. Keeps every stock behaviour exactly stock, in and out of combat, and keeps the pin math (D11–D13) untouched. |

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
3. **Positions are virtual (D15).** Incoming is the low slots in Blizzard's loot order; Keep is the fully occupied high slots. Pin, unpin and dissolve are the only things that move items, exactly as described in the gesture table.

### Repository layout

```
KondoBags/                              git repo  (github WoWAddons-Kuro/KondoBags)
  README.md  CHANGELOG.md  LICENSE(MIT)  .pkgmeta  .gitignore  .luacheckrc
  SPECS/
    00_KondoBags_Core.md                this file
    01_Stock_Bag_Replacement.md         Phase L step 5: hooks, sink, parity, typed-slot polish
    02_PROSPECTIVE_Filtered_Keep_Sections.md   NOT committed: "smart" groups considered on paper only
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
  sections = KondoBags_SectionStore,      -- D15: { nextID, kept = { [phys] = groupID }, list = { KondoBags_Group... } }; see "Bag window"
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

**The slot model: a POSITIONAL map with nullable backing (D15, 2026-11-18).** The bag's general slots `0..N-1` (Blizzard's combined order) are PHYSICAL. Incoming is a list of VISUAL positions, `store.map[v] = phys | nil` -- each position is backed by one physical slot, or by nothing (an **absent** position, transient). Keep is a SET of physical slots (`store.kept[phys] = groupID`), scattered anywhere in the bag; nothing about Keep is positional. Five facts drive everything:

1. **Blizzard loots into the lowest free PHYSICAL slot.** That is the only thing the client decides for us, so it is the only thing the map has to respect.
2. **Keep never has a free slot.** Keep is a set of pinned ITEMS; an empty cell is not one. The instant a kept slot empties it leaves `kept` and becomes an incoming position. Zero moves.
3. **Occupied positions never move.** `map[v]` for an occupied slot is never rewritten while the slot is occupied. Pins, unpins, loot, consumes, sells: none of them move an occupied incoming cell.
4. **Holes stay where they are.** When the item at position `v` is consumed, `v` is now a HOLE (empty cell) right there: `item item hole item item hole item` becomes `item item hole item item hole hole`. Only the PHYSICAL slots behind the holes are re-assigned (see `ReorderHoles`).
5. **`ReorderHoles()` runs after every change** and does exactly two things: (a) if any position is **absent** (its physical slot was taken: pinned from outside, or the slot count shrank), delete that position and shift every position top-left of it one step toward the bottom-right -- their physical backing is untouched, so no item leapfrogs, the run just closes by one; (b) collect the physical slots behind all holes and re-assign them so that, reading the holes from the bottom-right (position 0) toward the top-left, their physical indices ASCEND. The lowest free physical slot is therefore always the **bottom-right-most hole**, which is where Blizzard loots next: new loot appears in the bottom-right-most empty cell and nothing else moves. Empties are indistinguishable, so (b) is invisible (Philosophy).

```
 positions (reading order, 0 = bottom-right):   v6  v5  v4  v3  v2  v1  v0
 backing physical / contents:                   [8] [_] [5] [3] [_] [1] [0]      holes at v5 (phys 7) and v2 (phys 2)
 after ReorderHoles (b): holes ascend from the bottom-right -> v2 gets phys 2, v5 gets phys 7  (already so)
 item at v4 (phys 5) is eaten:                  [8] [_] [_] [3] [_] [1] [0]      v4 is a hole now; backing {7,5,2} re-sorted
                                                  v5->7  v4->5  v2->2  : ascending from the bottom-right. Nothing moved.
 loot lands in phys 2 = v2, the bottom-right-most hole.
```

**Invariants (D13, restated under D15).**

1. **Keep never has a free slot** (fact 2). `Reconcile` drops any `kept` entry whose physical slot is empty or out of range; that slot becomes an incoming position.
2. **One server operation per gesture, at most.** Every gesture is one primitive followed by `ReorderHoles()`:
   - **a slot in incoming empties** (consumed, sold, swapped out): nothing to do but `ReorderHoles()`; the position is a hole where it was.
   - **a slot leaves Keep** (unpin by stock drag, consume, dissolve): it needs a position: append a NEW position at the far top-left of incoming (the grid grows by one cell, like the mockup), then `ReorderHoles()`.
   - **something goes INTO Keep** -- from incoming: its physical slot moves from `map` to `kept`; its position is a hole now; `ReorderHoles()`. ZERO server ops. From OUTSIDE (bank, mail, trade, our typed bags): take the **top-left-most hole** of incoming, ONE `PickupContainerItem` into its physical slot, move that slot to `kept`, mark the position ABSENT, `ReorderHoles()` (which deletes the absent position and closes the run by one). ONE server op; no hole -> the lock cells are hidden (D14).
   **There is no chain-shift anywhere.**
3. **Restricted bag types are ONE display-only run ABOVE incoming.** Quiver, ammo, soul, herb, enchanting, mining, keyring, reagent slots are concatenated in bag order into a single run (never one run per kind), drawn above incoming with the same bottom-anchored rule. Each cell carries its `KondoBags_SlotKind`: empty cells show a faded glyph for the kind, every cell a subtle border tint per kind (`KondoBagsDB.kindTint`, default on). They are not in the general flat index and never in `kept`; their items pin like an external cursor (one move into the lowest free general slot). **No Keep for alternate bag types.**
4. **Bag swaps move nothing.** `kept` and `group.order` are physical indices into the flat list; equipping or rearranging bags re-indexes the list and `Reconcile` re-validates. No item moves.

```
 pin item at physical 3 (visual: second occupied cell):         kept item at physical 6 is EATEN:
   before   free[2 4 7] occ[5 3 1 0] | lock 6 8                    before   free[2 4 7] occ[5 1 0] | lock 6 8
   kept += {3} ; free pool += {}  (3 was occupied, no new hole)    kept -= {6} ; free pool += {6} -> re-sort
   after    free[2 4 7] occ[5 1 0] | lock 3 6 8   ZERO moves       after    free[2 4 6 7] occ[5 1 0] | lock 8   ZERO moves
   (cells for 5, 1, 0 did not move; 3's cell is gone from         (the new free cell slots in between 4 and 7; empties
    incoming and reappears right of the lock)                       are indistinguishable so nothing visibly jumped)
```

Terminology: while an item is carried with Shift down the window is in **insert mode** (see "Shift-insert" below). Nothing in the grid moves; a vertical **insert marker** shows where the item will land. The earlier "cursor gap" phantom (a cell that opened under the mouse and slid its neighbours) is retired -- it swapped when it should have inserted and its placement rules were a source of glitches (owner, 2026-11-19).

| Gesture | Server operations (`PickupContainerItem`; the mock swaps its table) | Visual result |
|---|---|---|
| Drop kept `k` on **occupied** incoming slot `t` | Blizzard swaps `k ↔ t` (D14). On scan: `k`'s physical slot now holds `t`'s item and is still in `kept`; `t`'s slot holds `k` and is incoming | the kept cell shows the item that was at `t`; `k` sits where `t` was. Stock swap, nothing of ours moved |
| Drop kept `k` on **empty** incoming slot `t` | Blizzard places `k` into `t`. On scan: `k`'s old slot is empty → leaves `kept` (fact 2), joins the free pool | `k` appears at `t`; its old cell becomes a free cell and re-sorts into the pool. Zero moves of ours |
| Drop loose `l` (physical `s_l`, on the cursor) on a **lock** or **gap** | ONE `Pickup(s_l)`: puts the item back in its own slot (the cursor must be empty for the map to be truth). `kept[s_l] = group`; `order` gains `s_l` at the gap | `l` appears right of the lock (or at the gap); its incoming cell vanishes and the occupied cells close ranks? **No** -- occupied cells never move: the cell `l` left is now a FREE cell and joins the pool at the top-left end. |
| Drop **EXTERNAL** or **TYPED** item (not in the general list) on a lock or gap | needs a free general slot: `h` = lowest free physical slot; ONE `Pickup(h)` places the cursor item; `kept[h] = group` | item lands in the group. **No free slot → the lock and gap cells are hidden** while that cursor is held (`Layout` input `hideLocks`). (D14) |
| Drop kept `k` on kept `j` | none | reorder: `k` takes `j`'s position in `order` (any group) |
| **Shift** while carrying (insert mode) | drop = pin / reorder as above at the **insert index** under the marker; a Shift-drop on an **item cell** is intercepted by us and is NEVER a stock swap | vertical insert marker between the two cells nearest the mouse; grid does not move |
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

### Shift-insert (replaces the cursor gap)

**One rule, everywhere.** While an item is on the cursor and Shift is held the window is in **insert mode**: the grid does not move, and a vertical **insert marker** (`KondoBags_InsertMarker`) shows the one boundary where the item will land. Dropping there **migrates a free slot to that boundary and fills it** -- never a stock swap. Release Shift (or empty the cursor) → marker gone, stock behaviour back. Works identically over a section row, the incoming grid and the typed strip; the only thing that differs per run is **where the free slot comes from** (table below).

**When there is no free slot to migrate**, Shift does nothing: no marker, no catcher, the drop is a stock swap/place exactly as without Shift. (Owner, 2026-11-19: 'pretend shift is not held'.)

**Why.** The cursor-gap phantom (a) slid cells under the mouse so the target moved while aiming, and (b) a Shift-drop landing on an *item* cell never reached us -- Blizzard's secure `OnClick` swapped. Both vanish when nothing moves and we own the click.

**Owning the click.** Secure buttons cannot be re-scripted, so insert mode raises one **transparent catch frame** (`KondoBags_InsertCatcher`: a plain Button sized to `frame.Grid`, frame level above every cell) that takes the click. It is shown only while `IsShiftKeyDown() and CursorHasItem()` **and a free slot exists for the run under the cursor** (recomputed on mouse move). **Combat does not disable it**: the catcher is a plain Button and the marker a texture, neither is protected, and `PickupContainerItem` plus the store edit are already allowed in combat (`LiveGesture`). What combat blocks is only the REDRAW of the secure cells, so a Shift-drop in combat lands, sets `BagState.movePending`, and the footer's `Move pending, will apply out of combat...` notice shows until `PLAYER_REGEN_ENABLED` replays the render. The catcher frame itself is created with the window (pre-build, SPECS/01 R6), never on demand. `OnUpdate` tracks the cursor → `InsertPointAt` → marker; `OnClick`/`OnReceiveDrag` performs the insert; `OnLeave` hides the marker.

**Insert point (`KondoBags_InsertPoint`).** Pure Lua in `Core/Layout.lua`, computed on every mouse move from cursor position against the current layout:

```lua
-- Layout.InsertPointAt(layout, metrics, gridX, gridY) -> KondoBags_InsertPoint | nil
--   metrics = { pitchX, pitchY, cellSize, rowY = { [row] = topY }, gridW }   -- passed in, keeps Layout pure
--   KondoBags_InsertPoint = {
--     run        = "section" | "incoming" | "typed",
--     sectionID  = KondoBags_SectionID | nil,          -- section runs only
--     slotKind   = KondoBags_SlotKind | nil,           -- typed runs only (the kind of the hovered strip)
--     beforeRef  = KondoBags_SlotRef | nil,            -- the cell RIGHT of the boundary; nil = after the last cell
--     afterRef   = KondoBags_SlotRef | nil,            -- the cell LEFT of the boundary; nil = before the first cell
--     markerRow, markerX                               -- grid coords for the marker
--   }
```

1. **Row** under the cursor by `rowY` bands (outside every row → nearest row). The row names the run and, for sections, the `sectionID`; for typed rows the `slotKind` of the strip.
2. **Nearest boundary** in that row: each slot cell has a centre `cx`; candidate boundaries are the midpoints between consecutive cells plus the left edge of the first cell (after the lock on a section row) and the right edge of the last. Pick the boundary whose x is closest to the cursor. `afterRef` / `beforeRef` are the cells either side (nil at the ends).
3. Multi-row runs: "after the last cell of row r" and "before the first cell of row r+1" are the same index; the marker is drawn on the row the cursor is on.
4. The marker moves only when the nearest boundary **changes** (no distance threshold; the nearest is always defined).

**Where the free slot comes from, and what the drop does** (`BagState:InsertAt(point)`; one server op maximum, as D13/D15 require):

| Run under cursor | Free slot needed | Store edit | Server op | No free slot → |
|---|---|---|---|---|
| **section** | one general slot the item can land in: the held item's OWN slot if it is general (nothing moves), else the lowest free general slot (`TopLeftHole`) | `Sections.Pin` / `MoveToGap` / `PinFromOutside` with `anchor = afterRef.slotIndex` (nil = first) — the existing `GapIndex` convention | ONE `Pickup` (held item's own slot, or the hole) | Shift inert |
| **incoming** | a free general slot. Incoming is the FREE POOL drawn in physical order, so the marker boundary names a physical neighbour: `afterRef` (or `beforeRef`). The lowest free general slot is **re-ordered in the map** to sit at that boundary (`Sections.MoveFreeToBoundary(store, afterSlot, beforeSlot, isFree)`: a map edit — holes are interchangeable, D15), then the item is placed into it | map edit + ONE `Pickup(hole)` | Shift inert |
| **typed** (quiver/herb/...) | -- | **Shift is inert on the typed strip**: no marker, no catcher, stock behaviour. (Owner, 2026-11-19: revisit only if it feels odd in play.) | -- | -- |

Dropping the held item on its **own** current position is a no-op (one `Pickup` releases the cursor).

**Marker.** One texture on `frame.Grid` (OVERLAY), themed: `theme.insertMarker = { width = 2, color = {1, 0.82, 0.3, 0.9}, overhang = 2 }`: full cell height + overhang, centred on the boundary (half the inter-cell gap). No animation.

**Removed.** `BagState.insertMode / cursorGap / SetInsertMode / CursorGap / UpdateCursorGap / CloseCursorGap`, `Layout.CELL_GAP` and the `cursorGap` input, `theme.gapGlyph`, the `MODIFIER_STATE_CHANGED → SetInsertMode` path (the catcher is toggled there instead), the two Shift-drag tests (replaced by `InsertPointAt` / `MoveFreeToBoundary` tests).

**Plan** (incremental; each step leaves the suite green)

- [ ] **Step 1 — sections only.** `Layout.InsertPointAt` for section rows; `BagState:InsertAt` section branch; catcher + marker in `Window.lua`; remove the cursor-gap machinery; `theme.insertMarker`, drop `gapGlyph`. Incoming rows: catcher not shown yet (Step 2). Typed strip: inert, by design. Tests: nearest boundary before-first / between / after-last; multi-row boundary. In-game: Shift-drop onto a kept item inserts before it; marker tracks; Shift release restores stock swap; a Shift-drop in combat lands and shows the footer notice.
- [ ] **Step 2 — incoming.** `Sections.MoveFreeToBoundary`; `InsertAt` incoming branch; catcher shown over incoming when a general hole exists. Tests: hole re-ordered to the named boundary; no hole → nil.
- [ ] SPECS: D14 row -> "we own lock drops **and every Shift drop on a general run**"; "Pinning by direct manipulation" loses its gap wording.

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
| Always compare items | on / off | off | Settings panel, "Item utilities". Not ours either: reads/writes Blizzard's `alwaysCompareItems` CVar directly (no `KondoBagsDB` key), so the box tracks the stock setting. |
| Create new stacks next to existing stacks | on / off | on | Settings panel, "Item utilities" (`KondoBagsDB.stackAdjacent`). **Stack adoption**: a general slot that was empty on the previous scan and now holds an itemID that a KEPT slot also holds is `Pin`ned into that group directly in front of the sibling (`water, 2/20 linen, 20/20 linen, food`). Map edit only, zero server ops; the loot stays in the physical slot Blizzard filled. Siblings only in incoming: nothing happens (incoming is physical order). First kept sibling in display order wins when there are several. `Sections.AdoptNewStacks`, driven from `OnBagsChanged` with a slotIndex→itemID snapshot of the previous scan. |

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

### Phase L — Live bags (replaces M1 + M4; one phase, five shippable steps)

M1's fixtures and `/kondo dump` existed to test a classifier that no longer exists; what is left of M1
(provider + scanner) only has value once the window draws it. Each step below ends with something you
can use in play. The keystone is D14: Blizzard owns slot-to-slot gestures, we own lock/gap drops.

**Step 1 — Client provider** (`Client/Client.lua`, `Era.lua`, `Mainline.lua`, `Mock.lua`)

- [ ] `KondoBags_ClientProvider = { name, BagIDs, NumSlots, FreeSlots, SlotInfo, BagKind, Pickup, InCombat }`
      (`SlotInfo(bag, slot) -> KondoBags_RawSlotInfo { itemID, link, icon, count, quality, locked, name }`)
- [ ] `BagKind(bag) -> KondoBags_SlotKind` from the `GetContainerNumFreeSlots` bag-family bitmask + `Enum.BagIndex.ReagentBag`
- [ ] selection at load from `WOW_PROJECT_ID` with capability checks; Mock provider over a ref table for `spec/run.lua`
- Research first: bag-family bit values on Era vs Forever (`_ref/blizzard/classic_era/ContainerDocumentation.lua`, wiki) → `_EXTERNAL_APIS/`

**Step 2 — Scanner, read-only live window** (`Core/Scan.lua`)

- [ ] `Scan.Refs(provider) -> { KondoBags_SlotRef... }`: general bags in `Enum.BagIndex` order (= the flat index), typed bags with `ref.kind`; same shape `Mock.Slots()` emits today, so `BagState`/`Layout`/`Window` change nothing
- [ ] `KondoBags.lua`: `BAG_UPDATE(bag)` marks dirty → `BAG_UPDATE_DELAYED` scans → `BagState:SetSlots`; `ITEM_LOCK_CHANGED` → per-cell redraw
- [ ] async names: `Item:CreateFromBagAndSlot():ContinueOnItemLoad` fills `name` for search (verify on Era)
- Milestone: `/kondo` shows the real bags, read-only (the `/kondo mock` mockup was retired in step 5)

**Step 3 — Secure cells**

- [ ] `CELL_SLOT` buttons become `ContainerFrameItemButtonTemplate`, one hidden per-bag parent frame (`SetID(bag)`), cell `SetID(slot)`, re-parented at render; lock / gap cells stay plain Buttons
- [ ] combat: `InCombatLockdown()` → defer render to `PLAYER_REGEN_ENABLED`; icon/count/dim updates still run
- [ ] dress through the stock helpers (`SetItemButtonTexture/Count/Quality/Desaturated`, `searchOverlay`); our ring/tint/glyph regions layer on top
- Milestone: right-click use, drag, split, vendor sell, trade all work from our window

**Step 4 — Pins live**

- [ ] `BagState.held` becomes a view of `GetCursorInfo()`: `SetCursor(ref | "external" | nil)` on `CURSOR_CHANGED` / `ITEM_LOCK_CHANGED`; `Pickup`/`ClearCursor` and the mock carry icon go
- [ ] **D15 store**: `Sections` holds `kept = { [phys] = groupID }` (no `boundary`); `Partition` emits incoming as the FREE POOL (free general slots ascending physical) followed by occupied slots in physical order, then the groups; `Reconcile` drops `kept` entries whose slot is empty / out of range and claims none
- [ ] **D15 gestures**: pin from incoming = `kept[s] = group` + ONE `Pickup(s)` to put the cursor item back (zero net moves); pin from outside = ONE `Pickup(lowestFree)` + `kept[lowestFree] = group`; unpin / dissolve = bookkeeping only. `Core/MoveQueue.lua` shrinks to a single-op issuer (kept for the one-Pickup case and its lock wait)
- [ ] store changes are committed only when the (single) op has landed, so the view never shows the pre-move bag against the post-move store
- [ ] external cursor (D14): `Layout` input `hideLocks` when no general slot is free
- [ ] Shift-insert: `PreClick` on the secure button + `ClearCursor()` to pre-empt the template when `IsShiftKeyDown()` and an item is held — **verify in game**; if it cannot pre-empt, M4 ships with "drop on lock = front, kept-on-kept = reorder" and Shift-insert waits
- Milestone: pin, unpin, reorder, `+` / remove group on real items; Keep survives `/reload`

**Step 5 — Replace the default bags**

- [x] **Spec: `SPECS/01_Stock_Bag_Replacement.md`.** Bagnon/BagBrother pattern: `hooksecurefunc` on `ToggleBackpack` / `ToggleBag` /
      `ToggleAllBags` / `CloseAllBags` (never replace the globals: taint), stock held-bag `ContainerFrameN` re-parented into a hidden sink
      on `SetID`, Forever `combinedBags` cvar forced off, auto open/close from `PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE`; bag-bar
      highlight, sounds, Escape; window pre-built at login; bank bags pass through as stock until M7
- [x] no setting: installed = stock bags replaced (owner decision 2026-11-18)
- [x] `Mock/MockSnapshot.lua` out of the TOC and deleted; `/kondo mock` removed (`Client/Mock.lua` stays for `spec/run.lua`)
- Milestone: default bags not needed in normal play -- **reached on Forever 2026-11-18** (owner playing live); Era run still pending

Exit criteria (whole phase): right-click use, drag, split-stack, vendor sell and trade all work from the window, in and out of combat; pins survive reload; an external item pins when a slot is free and has nowhere to land when none is.

Tests added in `spec/run.lua`: Mock provider → `Scan.Refs` (typed/general split, flat index = bag order); free-pool ordering (lowest free physical = top-left) after a release, a consume and a pin; pin from incoming = zero moves and the vacated cell joins the pool; pin from outside = one op into the lowest free slot; `Reconcile` drops an emptied kept slot; `hideLocks` emits no `CELL_DROP`/`CELL_GAP`.

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
