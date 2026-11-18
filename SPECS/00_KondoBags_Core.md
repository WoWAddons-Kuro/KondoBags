# SPEC 00 — KondoBags core: sectioned bag addon

- **Status:** Draft 3 (2026-11-17) — revised from the original BagAddon draft with the decisions in "Decisions log".
- **Name:** `KondoBags` (after Marie Kondo). Collision check done: none. Folder, TOC, SavedVariables and slash all use it.
- **Not related to `GotJunk/`.** That is an earlier, separate addon in this workspace. KondoBags shares no code, data or dependency with it. Any junk-deletion widget is **out of scope** until the window is done (owner, 2026-11-17).
- **Targets:** all current clients, with **Classic Era / Hardcore (interface 11509)** and **WoW: Forever (interface 16001)** as the clients we test on first. Cata/Mists/Retail get TOC lines and a clean provider seam, untested until later.
- **Repo shape:** packager-style, addon one level down (`KondoBags/KondoBags/KondoBags.toc`), like `DragonToast_upstream`. `cmd\publish.cmd` discovers it via rule 2 (`D\X\X.toc`).

Milestones:

- [ ] **M0 — UI mockup**: static in-game window from a fake snapshot, Edit Mode movable/scalable. No bag API, no data model. *Nothing in M1+ starts until the look is agreed.*
- [ ] M1 — Dev loop, bag model and classifier core (tested off-client with `lua5.1`)
- [ ] M2 — *(reserved; was a junk widget, deferred)*
- [ ] M3 — Current-quest section (marked quest items plus items a logged quest requires)
- [ ] M4 — Bag window live: five sections, secure buttons, restricted-slot strips, search, pins
- [ ] M5 — Two themes: flat and classic
- [ ] M6 — Keep special cases: gear identity, fishing swap, upgrade hold
- [ ] M7 — Late stage: upcoming-quest section, bank, restricted-slot assists

## Overview

A bag replacement whose organizing idea is five fixed sections that the addon fills on its own: items for current quests, items for upcoming quests, junk, a Keep section the player fills by hand, and everything else. The player never writes a rule. The only manual acts are pinning an item to Keep or to Junk.

The mental model is **a person who organizes their own backpack**, not a bag automator. Everything the addon remembers about how *this character* sorts things is stored **per character**. There is no account-wide pin state.

The design goal is the smallest possible configuration surface and the least adornment. The complete settings list is in "Settings" and is meant to stay that short.

## Decisions log

| # | Decision | Rationale |
|---|---|---|
| D1 | KondoBags is a fresh repo with no relation to `GotJunk/` | Owner statement. GotJunk is prior, unrelated work. |
| D2 | **All stored sorting state is per character** (`KondoBagsCharDB`). No account-wide pins. | The addon models one person's backpack. A new hardcore character starts with an empty Keep. |
| D3 | Window position and scale live in **Edit Mode** via vendored **LibEditMode** (p3lim), not in our settings | Blizzard gives addons no Edit Mode API; hand-rolling it taints Edit Mode. Era has Edit Mode since the July 2026 update, so one path serves every client. Pattern proven in `MoveMyBags.Kuro/EditMode.lua`. Removes "Window scale" from Settings. |
| D4 | **UI mockup before any data model** (M0) | Owner priority. The window is the product; argue about pixels first. |
| D5 | Client access goes through a **provider interface** (`Client/`) with one provider per API family plus a **mock provider** for off-client runs | More than one behaviour source per concern (Era quest log vs `C_QuestLog`), and the core must run under stock Lua 5.1. Use the better API where a client has it. |
| D6 | All flavours supported in TOC and seam; Era + Forever tested first | Owner priority. |
| D7 | Tests run with `lua5.1` (installed: `C:\ProgramData\chocolatey\bin\lua5.1.exe`, `luacheck` also present) | Confirmed on this machine 2026-11-17. |
| D8 | Libraries are **vendored** (unmodified, with `VENDORED.txt`), not git submodules | `publish.cmd` treats an empty submodule folder as missing and LibEditMode has no CurseForge zip to fall back on. |
| D9 | **MVC split in code**: `Core/Sections.lua` (model), `Core/Layout.lua` (pure layout), `Core/BagState.lua` (controller: owns store + slots + held item, `Pickup/Drop` decide pin-vs-swap, emits `changed`/`cursor`), `UI/Window.lua` (view only: draws `BagState:Layout()`, forwards gestures). | Audit 2026-11-17 found the view mutating the model. Drop semantics are now unit-tested and survive the M4 switch to secure buttons untouched; the mock item source is swapped for the Client provider inside the controller. |
| D10 | **Section UI = drop cells, not headers/handles/dividers.** A section is one run of cells: a single drop cell (faded lock glyph) immediately left of its first item, then its items. The unsectioned remainder ("incoming") is drawn above, exactly like the stock bag. A new character starts with one section, **Keep**, holding Hearthstone. More sections can be made later (UI not in M0). | Owner, 2026-11-17, after seeing headers, `+` cell and handle cell in game: too gaudy. |

## Architecture

```
            WoW events (bags, quest log, equipment, item-loaded)
                              |
                       +------v------+
                       |   Client    |   providers: Era, Mainline, Mock
                       +------+------+
                              |
   +----------+        +------v------+        +-------------+
   |  Pins    +------->|  Bag model  |<-------+ Quest needs |
   | (char)   |        |  (snapshot) |        |  (derived)  |
   +----------+        +------+------+        +-------------+
                              |
                       +------v------+
                       | Classifier  |   pure Lua, no WoW API
                       +------+------+
                              |
              +---------------+----------------+
              |                                |
       +------v------+                  +------v------+
       |  BagState   |----------------->| Bag window  |
       | (controller)|   Layout() +     | (view,      |
       +-------------+   changed/cursor |  themes)    |
                                        +-------------+
```

Three rules hold across the whole design:

1. **Core is pure Lua.** The bag model, classifier, sort order and layout solver take plain tables in and return plain tables out, with no WoW API calls. They run under stock Lua 5.1 against a dumped or mocked snapshot.
2. **Everything is event-driven.** No OnUpdate scanning and no repeating timers. A bag or quest event marks state dirty; one coalesced flush recomputes.
3. **Views are logical, slots are physical.** Sections are a way of drawing items. Nothing is physically moved between bags to make a section (the optional late-stage auto-move in M7 is the only exception).

### Repository layout

```
KondoBags/                              git repo  (github WoWAddons-Kuro/KondoBags)
  README.md  CHANGELOG.md  LICENSE(MIT)  .pkgmeta  .gitignore  .luacheckrc
  SPECS/
    00_KondoBags_Core.md                this file
    01_...                              later specs (themes, bank, quests) as they split out
  docs/                                 design notes, mockup screenshots
  spec/                                 off-client tests:  lua5.1 spec/run.lua
    run.lua  fixtures/*.lua (dumped snapshots, quest logs; M1)
  KondoBags/                            the addon; folder name == TOC name
    KondoBags.toc
    KondoBags.lua                       bootstrap, slash, events
    Core/                               pure Lua (D9): Sections.lua (model) Layout.lua BagState.lua (controller);
                                        M1+: Model.lua Classifier.lua Sort.lua QuestNeeds.lua
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
  SlotQuestInfo   = function(bagID, slot) -> isQuestItem, questID, isActive | nil   -- nil provider = not available
  ItemInfo        = function(itemIDOrLink) -> KondoBags_RawItemInfo | nil         -- nil until cached
  ItemInfoInstant = function(itemIDOrLink) -> KondoBags_RawItemInfoInstant
  OnItemLoaded    = function(bagID, slot, fn)                                       -- Item:CreateFromBagAndSlot:ContinueOnItemLoad or GET_ITEM_INFO_RECEIVED
  QuestLogEntries = function() -> { KondoBags_QuestLogEntry... }                   -- { questID, title, isHeader }
  QuestObjectives = function(questID) -> { KondoBags_QuestObjective... }           -- { text, type, finished, numFulfilled, numRequired }
  PickupSlot      = function(bagID, slot)
  DeleteCursor    = function()
  EquippedLink    = function(invSlot) -> link | nil
  InCombat        = function() -> bool
}
```

Known provider differences (ground truth from `_EXTERNAL_APIS/wow_classic_era_quest_ui_api.md` and `_ref/blizzard/classic_era/*Documentation.lua`, fetched from the Era UI source):

| Concern | Era (1.15.x) | Mainline / Forever | Note |
|---|---|---|---|
| Quest log iteration | `GetNumQuestLogEntries()` + `GetQuestLogTitle(i)` (returns `questID` as the 8th value, `isHeader` 4th) | `C_QuestLog.GetNumQuestLogEntries()` + `C_QuestLog.GetInfo(i)` | Era `C_QuestLog` has **no** `GetNumQuestLogEntries`/`GetInfo`. |
| Quest objectives | `C_QuestLog.GetQuestObjectives(questID)` **exists on Era** → `{ text, type, finished, numFulfilled, numRequired }` | same | Preferred on both. Fallback `GetQuestLogLeaderBoard(obj, i)` on Era only if the former misbehaves. `text` is still name-based (`"Linen Cloth: 3/10"`). |
| Item info | `C_Item.GetItemInfo` (18 returns, sellPrice #11), `C_Item.GetItemInfoInstant` present on Era | same | Legacy globals as fallback behind a capability check. |
| Containers | `C_Container.*` present (GotJunk relies on it on both clients) | same | |
| Per-slot quest info | `C_Container.GetContainerItemQuestInfo` — **to confirm on Era** | present | Provider returns nil when absent; classifier falls back to item class / bind type. |
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

**Async item data.** Item info can be missing when a slot is first scanned. Such records are stored with `loaded = false`, classified as "everything else" for the moment, and reclassified when the item-loaded callback arrives. Classification must be safe to run repeatedly.

**Update flow.**

```lua
-- pseudocode: illustrative only
on BAG_UPDATE(bag)        -> dirtyBags[bag] = true
on BAG_UPDATE_DELAYED     -> flush()          -- rescan dirty bags, reclassify, notify views
on item loaded            -> reclassify that itemID, notify views
on quest log changed      -> rebuild quest needs, reclassify, notify views
```

If a client does not fire `BAG_UPDATE_DELAYED`, the fallback is a single one-shot next-frame callback armed by the first `BAG_UPDATE` in a burst. That is coalescing, not polling.

### Classifier

Each slot record gets exactly one section. First match wins:

| Order | Section (`KondoBags_SectionID`) | Test |
|---|---|---|
| 1 | `keep` | Item is pinned to Keep, or is a transient swap-out (M6) |
| 2 | `quest` | Item is marked as a quest item, OR a quest in the log lists it as an item objective |
| 3 | `upcoming` | Item is required by a quest in the upcoming set (M7) |
| 4 | `junk` | Quality is Poor, or item is pinned to Junk |
| 5 | `other` | Fallthrough ("Everything else") |

Quest ranks above Junk deliberately: a grey or white item that a quest needs must never be offered for deletion. Keep ranks above everything so a manual pin is never overridden.

The quest test is a union of two independent checks. "Marked as a quest item" is a property of the item (per-slot quest info where the provider has it, else item class Quest `12` or bind type quest `4`). "Required by a logged quest" pulls ordinary items such as Linen Cloth into the section only while a quest that needs them is in the log; they fall back to their normal section when the quest is turned in or abandoned. When a quest needs 10 and the player holds 14, the whole stack is treated as quest.

Every placement carries a reason string (`"pinned"`, `"quest: <quest name>"`, `"grey"`), shown as one tooltip line.

**Sort within a section** is fixed and not configurable: Junk by stack value ascending; all others by item class, subclass, quality descending, then name.

### Quest needs

```lua
-- pseudocode: illustrative only
KondoBags_QuestNeeds = { [itemName] = { questID, questName, required, have } }   -- current quests
```

Built from `QuestObjectives(questID)` entries with `type == "item"`, for every non-header `QuestLogEntries()` entry. The objective text carries no item ID, so the match is by item name against bag contents. Both strings come from the same client, so this holds across locales.

### Pins (per character)

```lua
-- pseudocode: illustrative only
KondoBagsCharDB = {                       -- ## SavedVariablesPerCharacter
  version  = 1,
  keep     = { [itemID] = true },         -- Hearthstone (6948) present by default on a new character
  junk     = { [itemID] = true },
  keepGear = { [gearKey] = true },        -- gearKey derived from the full item link (M6)
  swapOut  = { [gearKey] = true },        -- transient fishing swap-outs (M6)
}
KondoBagsDB = {                           -- ## SavedVariables (account): display-only, nothing about sorting
  theme = "flat" | "classic",
  theme = "classic" | "modern",
}
```

Stackables and consumables pin by item ID. Gear pins by an instance key (M6), because two drops with the same item ID can differ by random suffix or enchant.

*(A junk-deletion widget was specified here in Draft 2 and removed in Draft 3; out of scope until the window is done.)*

### Bag window

One window replaces the default bag frames. It hooks the standard open/close/toggle entry points and the bag keybinds.

**Starting point: the stock Combined Backpack, unchanged.** Same frame art, title bar, portrait, close button, search box, sort button, slot grid, money bar. The only thing classic bags lack is differentiation: the grid is one undifferentiated run of boxes. KondoBags adds *sections* on top of that grid and nothing else. **No labelled header rows** (five empty "Quest / Keep / Junk…" headers on a fresh character looked dumb and stopped looking like the stock bag; rejected 2026-11-17).

**Grid.** Column count comes from the window width; the window is **drag-resizable in Edit Mode, snapping to whole cells** (`KondoBagsCharDB.window.columns`; rows follow from content). Every run of cells is **bottom-anchored like the stock bags**: its last row is full and any partial row is the top row, right-aligned, so free space appears top-left. Empty slots stay as empty slot art (a faded bag icon), exactly like stock. Restricted bags (quiver, soul, reagent) keep their stock windows in this iteration.

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

| Gesture | Effect |
|---|---|
| Drop an item on a section's lock cell | Pin that item into the section (logical; needs no free slot; the item does not change physical slot) |
| Drop on an item cell / empty slot | Stock swap / place behaviour, untouched |
| Hover the lock cell | Tooltip: section name, item count, "drop an item here to keep it" |
| *(later)* right-click the lock cell | Section options: rename, dissolve, unpin, new section |

**Rejected along the way (2026-11-17, kept for the record):** labelled header rows with thin rules; a `+` cell that creates a section; a per-section handle cell (`≡`) for drag-reorder / right-click; divider lines between sections. All read as gaudy next to the stock bag.

- Sections are *logical*. `OnReceiveDrag` on a lock cell records a pin in `KondoBagsCharDB.sections` and returns the cursor item to its slot. **A drop never needs a free slot.**
- The classifier's automatic sections (Quest, Junk, …) come later and render as more runs with the same lock cell, so the mockup proves the user-made section first.

```lua
-- pseudocode: illustrative only
KondoBagsCharDB.sections = {                  -- KondoBags_SectionStore; list order is display order
  nextID = 2,
  list = { { id = "s1", name = "Keep", items = { [6948] = true } } },
}
KondoBags_SectionID = string                  -- stable key, e.g. "s1", never reused
```

**M0 mockup scope:** stock-looking window from a fake snapshot; default Keep section with lock cell; mock pick-up (carry icon follows the mouse) and drop-to-pin; Edit Mode move + cell-snapped resize. Creating further sections is not in M0.

**Previous layout (rejected 2026-11-17, kept for the record):**

```
+------------------------------------------------+
| KondoBags                          [ search ]  |
| Quest ─────────────────────────────────────── |
|  [][][]                                        |
| Upcoming ──────────────────────────────────── |
|  [][]                                          |
| Keep ──────────────────────────────────────── |
|  [][][][][]                                    |
| Everything else ───────────────────────────── |
|  [][][][][][][][][][]                          |
|  [][][][][][][]                    [free: 5]   |
| Junk ──────────────────────────────────────── |
|  [][][]            (cells dimmed)              |
| ── restricted ────────────────────────────── |
|  Reagent  [][][][]                 [free: 12]  |
|  Quiver   [][]                     [free: 14]  |
+------------------------------------------------+
```

Rejected because labelled header rows look dumb when most sections are empty, and because it stopped looking like the stock bag.

**Secure item buttons.** Right-click-to-use must work in combat, so every item cell is the client's own container item button template (`ContainerFrameItemButtonTemplate`), with the bag ID on its parent frame (`SetID(bag)`) and the slot ID on the button (`SetID(slot)`). These cannot be created or re-parented during combat. The window keeps a pool sized to total slot count, built out of combat, and any layout change requested in combat is deferred to `PLAYER_REGEN_ENABLED`. Content updates that do not re-parent (icon, count, dimming) may still run in combat.

**Pinning by direct manipulation.** The `+` cell and section handles are the only pin gestures in M0. Later: drop onto the unsectioned area to unpin; modifier-click shortcut.

**Search.** A small edit box in the upper right. On each text change, every visible item whose name does not contain the query (case-insensitive, plain substring) is desaturated and dimmed; matches stay normal. Empty box restores everything. Escape clears and unfocuses. Appearance-only, so safe in combat.

**Edit Mode.** The window is registered with LibEditMode (`lib:AddFrame`, `lib:AddFrameSettings` for scale, `lib:AddFrameSettingsButtons` for reset). Position/scale are owned by the library's layout storage. In Edit Mode the window also gets a **resize grip**; dragging it snaps the size to whole cells and stores `KondoBags_GridColumns`/`KondoBags_GridRows`. Minimum is the number of columns needed so every slot fits. The window being a toggled panel, Edit Mode shows a placeholder the window's last size when it is closed (pattern: `MoveMyBags.Kuro/EditMode.lua`).

### Themes

A theme is a data table (textures, borders, background, fonts, cell art, handle/`+` glyphs, divider, metrics) consumed by one renderer. No theme-specific code paths. **`classic` is the default**: the window must look like the stock Combined Backpack of the client it runs on. A **modern** theme is the second option and must exist from M0 so the renderer is proven theme-agnostic.

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
| Theme | classic / flat | classic | Settings panel |
| Toss line standalone frame | shown / hidden | shown | Settings panel |
| Window / Toss line position and scale | — | — | **Edit Mode** (not a setting of ours) |

Pins are managed in the window itself. Anything proposed beyond this list needs a reason it cannot be a fixed behaviour.

### Keep special cases (M6)

**Gear identity.** Gear pins use a key derived from the full item link (item ID plus suffix and enchant fields), or a per-instance GUID where the client exposes one. A pin on one "of the Monkey" drop must not keep a second drop with the same item ID.

**Fishing swap.** When `PLAYER_EQUIPMENT_CHANGED` fires for main-hand (16) or off-hand (17) and the newly equipped main-hand item is a fishing pole (class Weapon `2`, subclass `20`), the items that just left those two slots are recorded in `swapOut` and classified as Keep. The record clears when they are equipped again. Per character, survives reload.

**Upgrade hold.** An equippable item the class can use whose required level is above the player's level is flagged as a possible future upgrade and surfaced as a one-click suggestion to pin, not placed automatically. A held upgrade shows its required level on the cell.

### Late stage (M7)

- **Upcoming-quest section**: the "required by a quest" test against quests the player is not on yet. Needs outside data; candidate sources in Open Questions.
- **Bank**: same window and classifier over bank bags, plus a saved snapshot for viewing away from the bank. Forever's protected bank actions may stay with the stock UI.
- **Restricted-slot assists**: colour ring on `general` items that fit a restricted bag with free space; optional auto-move on a player action, never on a timer.

## Bringup phases

Each phase ends with something usable in play, and nothing is built before the loop that tests it.

### Phase 0 — UI mockup (M0)

- [x] Repo skeleton: `.pkgmeta`, `.gitignore`, `.luacheckrc`, LICENSE, README, CHANGELOG, `PROJECT_STRUCTURE.md` entry
- [x] `KondoBags/KondoBags.toc` loading on Era (seen 2026-11-17); vendored LibStub + LibEditMode. Forever: to confirm
- [x] `Mock/MockSnapshot.lua`: 16-slot backpack + 6-slot bag with real icon paths and counts (no restricted strips in this iteration)
- [x] `UI/Theme.lua` + `Themes/Classic.lua` + `Themes/Modern.lua`: metrics and colours as data
- [x] `UI/Window.lua`: view only (D9); stock-look frame, bottom-anchored grid, lock drop cell per section (D10), mock pickup with carry icon, drop-to-pin, search
- [x] `Core/Sections.lua` + `Core/Layout.lua` + `Core/BagState.lua` (D9); 12 off-client tests
- [x] `UI/EditMode.lua`: placeholder registered with LibEditMode; drag + cell-snapped resize grip. In-game verification pending
- [x] `/kondo` toggles the mock window; `/kondo status`, `theme`, `columns`, `reset`
- [ ] Visual sign-off on classic theme: lock drop cell look pending; portrait/search/bg/money/footer accepted 2026-11-17
- [x] Spec hygiene: Toss-line remnants purged (Draft 3)

Exit criteria: owner looks at it on both clients and signs off on frame art, spacing, cell art, lock cell. Screenshots saved to `docs/`.

### Phase 1 — Dev loop, bag model, classifier core (M1)

- [ ] `Client/` provider interface, Era and Mainline providers, Mock provider over fixtures
- [ ] Scanner producing a `KondoBags_Snapshot`; slot-kind detection; async item completion
- [ ] `/kondo dump` writes the current snapshot and quest needs to SavedVariables; a script copies it into `spec/fixtures/`
- [ ] `spec/run.lua` harness under `lua5.1`: loads fixtures through the Mock provider, runs classifier and sort, asserts sections
- [ ] Classifier with Keep pins, marked-quest test, Junk and fallthrough

Exit criteria: tests run in about a second with no game running; addon loads on Era and Forever with no errors; dumped snapshot matches the bags by hand count, including per-kind free slots.

### Phase 2 — Toss line (M2)

- [ ] Candidate selection and value model in `Core/Toss.lua`, with tests
- [ ] LDB data object; updates pushed on flush
- [ ] Standalone frame, Edit Mode registered
- [ ] Click-to-delete with the pre-delete slot re-check; right-click to Keep

Exit criteria: always shows the true cheapest candidate after looting, selling and deleting; a marked quest item or Keep pin never appears; a full hardcore session with no wrong deletion.

### Phase 3 — Current-quest section (M3)

- [ ] Quest-needs builder per provider; name matching; rebuild on quest-log events
- [ ] Fixture tests: accept, progress, turn-in, abandon

Exit criteria: an ordinary turn-in item is excluded from the Toss line while its quest is logged and returns after turn-in.

### Phase 4 — Bag window live (M4)

- [ ] Layout solver in `Core/Layout.lua` (sections and strips in, cell rectangles out), with tests
- [ ] Secure button pool; combat-deferred layout
- [ ] Mock renderer replaced by live snapshot; `Mock/` removed from the TOC
- [ ] Replace default bags: toggle hooks and keybinds
- [ ] Drop-to-pin and modifier-click pin; reason line in tooltip

Exit criteria: right-click use, drag, split-stack, vendor sell and trade all work from the window, in and out of combat; default bags not needed in normal play.

### Phase 5 — Themes (M5) · Phase 6 — Keep special cases (M6) · Phase 7 — Late stage (M7)

As in the sections above; each gets its own `SPECS/0N_*.md` when work starts.

## API surface (to verify per client as each phase reaches it)

**Bags:** `C_Container.GetContainerNumSlots`, `.GetContainerItemInfo` (table: `iconFileID, stackCount, isLocked, quality, hyperlink, hasNoValue, itemID, isBound`), `.GetContainerNumFreeSlots` → `numFree, bagFamily`, `.GetContainerItemQuestInfo` (Era: confirm), `.PickupContainerItem` + `DeleteCursorItem()`, `GetItemFamily(item)` bitmask. Bag IDs via `Enum.BagIndex`.

**Items:** `C_Item.GetItemInfo` (nil until cached), `C_Item.GetItemInfoInstant`, `Item:CreateFromBagAndSlot(bag, slot):ContinueOnItemLoad(fn)`, `GET_ITEM_INFO_RECEIVED`. Constants: quality Poor `0`, Common `1`; class Quest `12`; bind type quest `4`; class Weapon `2` subclass Fishing Poles `20`; Hearthstone `6948`.

**Quest log:** see provider table. Events: `QUEST_LOG_UPDATE`, `QUEST_ACCEPTED`, `QUEST_REMOVED`, `QUEST_TURNED_IN`.

**Equipment and combat:** `PLAYER_EQUIPMENT_CHANGED(slot, hasCurrent)`, `GetInventoryItemLink("player", slot)`, `InCombatLockdown()`, `PLAYER_REGEN_ENABLED`.

**LibDataBroker:** `LibStub("LibDataBroker-1.1"):NewDataObject(name, { type = "data source", icon, text, OnClick, OnTooltipShow })`; assigning `.text` notifies displays.

**LibEditMode (vendored, minor 18):** `lib:AddFrame(frame, cb(frame, layoutName, point, x, y), defaultTable, name)`; frame must be parented to `UIParent` and movable. `lib:AddFrameSettings(frame, settings)`, `lib:AddFrameSettingsButtons(frame, buttons)`, `lib:RegisterCallback('enter'|'exit'|'layout', fn)`, `lib:IsInEditMode()`.

### References

- Workspace ground truth: `_EXTERNAL_APIS/wow_classic_era_quest_ui_api.md`, `_ref/blizzard/classic_era/ItemDocumentation.lua`, `QuestLogDocumentation.lua`, `QuestLogFrame.lua`
- Edit Mode pattern: `MoveMyBags.Kuro/EditMode.lua`, `MoveMyBags.Kuro/Libs/LibEditMode/`
- Repo shape: `DragonToast_upstream/` (`.pkgmeta` move-folders, `.luacheckrc`, `spec/wow_mock.lua`)
- Workspace rules: `PROJECT_STRUCTURE.md` (publishing/releasing by the owner only; folder == TOC name; version tag `vYYYY.MM.DD.HHMM`)
- [World of Warcraft API index](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API) · [C_Container.GetContainerItemInfo](https://warcraft.wiki.gg/wiki/API_C_Container.GetContainerItemInfo) · [GetContainerNumFreeSlots](https://warcraft.wiki.gg/wiki/API_C_Container.GetContainerNumFreeSlots) · [ItemMixin](https://warcraft.wiki.gg/wiki/ItemMixin) · [BagID](https://warcraft.wiki.gg/wiki/BagID) · [BAG_UPDATE_DELAYED](https://warcraft.wiki.gg/wiki/BAG_UPDATE_DELAYED) · [DeleteCursorItem](https://warcraft.wiki.gg/wiki/API_DeleteCursorItem) · [TOC format](https://warcraft.wiki.gg/wiki/TOC_format) · [LibDataBroker-1.1](https://github.com/tekkub/libdatabroker-1-1) · [LibEditMode](https://github.com/p3lim-wow/LibEditMode)

## Open questions

- **`C_Container.GetContainerItemQuestInfo` on Era** — check `_ref/blizzard/classic_era/` container documentation or `/api` in game before M1.
- **`BAG_UPDATE_DELAYED` on Era** — confirm with `/etrace`; fallback exists either way.
- **Per-instance item identity on Era** — whether a bag-item GUID call exists. If not, gear key = link suffix + enchant fields.
- **Upcoming-quest data source** — (a) installed quest-database addon as optional dependency; (b) small shipped table of quest → pre-collectable item IDs; (c) the route known to Velocity, so "upcoming" = "on my route".
- **Forever specifics** — whether Era's typed bags exist; which bank actions are protected; whether any bag or quest data is restricted in combat.
- **Stock art for `classic`** — which textures/atlases exist on each client now that Era runs the newer UI framework.
- **Edit Mode and a toggled window** — whether to register the live window itself (hidden frames cannot be dragged) or a placeholder that the window follows, as MoveMyBags.Kuro does. Decide during M0.
- **Pin on drop vs. the client's own drag.** `OnReceiveDrag` on a plain frame fires when the mouse is released over it with an item on the cursor; confirm it also fires on Era for frames that are not item buttons, else fall back to `OnMouseUp` + `CursorHasItem()`.

## Alternatives considered

- **User-authored rules with inference from drags.** More general, possible later layer; five fixed sections cover the stated need with no rule concept in the UI.
- **Items appearing in more than one section.** Rejected: first-match precedence is the entire model and every item has one explainable reason for where it sits.
- **Dropping onto an empty slot to move an item into a section.** Rejected: there may be no empty slot, and sections are not places. A drop on a section is a pin, so it needs no free space and never moves anything.
- **Physically sorting items between bags.** Rejected: slow, visible, blocked in several situations. Logical views avoid all of that.
- **Account-wide pins.** Rejected (D2): the addon models one character's habits.
- **Own window-scale setting.** Rejected (D3): Edit Mode owns position and scale for every other frame on screen; ours should behave the same.