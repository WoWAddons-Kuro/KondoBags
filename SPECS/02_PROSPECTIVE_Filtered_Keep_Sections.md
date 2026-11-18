# SPEC 02 (PROSPECTIVE) — Filtered Keep sections ("smart" groups)

> ## ⚠ NOT COMMITTED. This is a CONSIDERATION, not a plan.
>
> Written 2026-11-18 at the owner's request to think the idea through on paper. **Nothing here is scheduled.**
> The owner's own assessment: *auto sections open substantial complexity that might not be worth it.*
> The core promise of KondoBags (SPECS/00 "Philosophy") is that the player never writes a rule and the
> addon never moves an item on its own. Every feature in this document breaks the second half of that
> promise. It should be built only if, after living with the manual Keep for a while, the owner still wants it.

- **Parent:** `00_KondoBags_Core.md` (D10 sections, D13 invariants, D15 virtual positions), `01_Stock_Bag_Replacement.md` (no-drop mark, `Client.ItemFitsKind`).
- **Status:** prospective. No bringup checklist; see "If we ever build it" at the end.

## The idea, as requested

On a group's lock cell, the right-click menu gains a **filter** radio:

```
 ( ) any items          <- today's behaviour; the default
 ( ) quest items
 ( ) crafting reagents
 ( ) ammo
 ( ) herbs / soul shards / enchanting / mining / engineering / ...   <- one entry per bag kind the client knows
```

A group with a filter is a **magnet**: a matching item that lands **anywhere** in the general bags is physically
moved into that group. Concretely, per the owner:

- **quest items**: any item flagged `isQuestItem` lands here. (*Later, not now:* any item NEEDED by a quest in the log.)
- **crafting reagents**: any item flagged **Crafting Reagent** lands here.
- **ammo** (and each other bag kind): any item that fits that bag family lands here.

### Naming collision, resolved

Forever has a **reagent BAG slot** (`Enum.BagIndex.ReagentBag`, bag 5, a container kind) and items have a **Crafting
Reagent** flag (an item property). This spec means the **item flag**, never the bag slot. In code the two must never share
a word: the bag kind stays `KondoBags_SlotKind = "reagent"` (existing), the item predicate is `KondoBags_ItemFilter = "craftingReagent"`.

## Ground truth available today

| Predicate | API | Client | Cost | Note |
|---|---|---|---|---|
| quest item | `C_Container.GetContainerItemQuestInfo(bag, slot).isQuestItem` | Era + Forever | per slot, cheap | already scanned into `item.quest` (SPECS/01) |
| crafting reagent | `GetItemInfo(link)` return 17 `isCraftingReagent` | Era (`_ref/blizzard/classic_era/ItemDocumentation.lua:420`) + Forever (`ItemDocumentation.lua:632`) | **async**: nil until the item is cached; needs `Item:ContinueOnItemLoad` | the ONLY general signal; classID 7 "Trade Goods" is NOT the same set |
| fits bag kind K | `C_Item.GetItemFamily(link)` bit for K (`Client.ItemFitsKind`) | both | instant | already used for the no-drop mark |
| needed by a current quest | none that is cheap/reliable; would need quest-objective item scraping | — | — | **deferred** by the owner |

## Why this is bigger than it looks

Each point below is a place where the current design has a hard rule that a magnet group would violate or complicate.

1. **KondoBags does not move items on its own. Ever.** (D13.2, D15, Philosophy.) Today the ONLY server op the addon issues
   is the single put-back `Pickup` on a player's drop. A magnet means **unattended moves after loot**, possibly several per
   `BAG_UPDATE_DELAYED`. That is a different kind of addon (an auto-sorter), with the failure modes auto-sorters have:
   moves racing the player's own drag, moves in combat (impossible: `PickupContainerItem` is fine but our render is
   deferred, so the window lies for a while), moves fighting Blizzard's own `SortBags`, moves while a vendor/mail window
   has the cursor.
2. **Positions are virtual; Keep is a SET of physical slots.** (D15.) A magnet move is a *physical* move into a general slot
   that is then marked kept. The receiving slot must be a **free** general slot (steal the top-left hole, exactly like
   `PinFromOutside`). If there is no hole, the item simply stays where it is — a magnet can never evict anything.
3. **Typed bags are a display-only run with no Keep.** (D13.3.) "All ammo type slots should get auto moved here" cannot mean
   moving arrows OUT of the quiver into general slots — that is backwards and wastes the quiver. The only sane reading:
   a magnet pulls matching items **from general slots only**; items already in a typed bag stay there. An *ammo* magnet
   therefore only matters when the quiver is full and arrows spill into general slots.
4. **Precedence.** A Mageroyal is a herb (bag kind), a crafting reagent (flag) and might be a quest item. With several
   magnet groups, one rule must win. Proposal: **quest > specific bag kind > crafting reagent > any**; first matching group
   in display order; at most one group per filter value (the menu greys out a filter already taken).
5. **Async item data.** `isCraftingReagent` is nil until `GET_ITEM_INFO_RECEIVED`; a freshly looted stack may be
   unclassifiable for a frame or two, so the magnet must re-evaluate on item-loaded, not only on scan.
6. **Un-matching.** A quest item whose quest is abandoned stops matching. Does it leave the group? If yes, it needs a new
   incoming position (`Release`), zero moves (D13.1 style). If no, the group slowly fills with junk. Proposal: it stays;
   the filter is a magnet on arrival, not a bouncer.
7. **Manual drops onto a filtered lock.** Should a non-matching item be refused (no-drop X on the lock, SPECS/01 style)?
   Consistent, but it means a "quest" group can never hold the one non-quest thing you want next to your quest items.
8. **Combat.** Moves are allowed in combat by the API, but our secure-cell render is deferred to `PLAYER_REGEN_ENABLED`.
   A magnet should simply not run in combat (`InCombatLockdown()`), and run once when combat ends.
9. **Reload / login.** On first scan the whole bag is "new". Should the magnet sweep everything at login (potentially
   dozens of moves) or only act on arrivals after login? Proposal: **arrivals only**, plus an explicit "Sweep now" menu
   item for the player to trigger the bulk pass deliberately.

## Shape it would take (sketch only)

```lua
-- pseudocode: illustrative only
KondoBags_ItemFilter = "any" | "quest" | "craftingReagent" | KondoBags_SlotKind   -- "ammo", "quiver", "herb", ...
KondoBags_Group = { id, name, order = { phys... }, filter = KondoBags_ItemFilter }  -- filter nil == "any"

-- pure Lua, Core/Filters.lua
Filters.Matches(filter, itemView) -> bool
  "any"              -> true
  "quest"            -> itemView.quest ~= nil and itemView.quest.isQuestItem
  "craftingReagent"  -> itemView.craftingReagent == true          -- new ItemView field, async-filled
  kind               -> Client.ItemFitsKind(itemView.family, kind) -- new ItemView field: GetItemFamily bits
Filters.GroupFor(store, itemView) -> KondoBags_Group | nil        -- precedence quest > kind > craftingReagent; "any" never magnets

-- controller, after every scan / item-loaded, out of combat, queue idle, cursor empty:
BagState:RunMagnets()
  for each INCOMING occupied slot s (never typed, never kept):
    g = Filters.GroupFor(store, slots[s].item); if not g then continue end
    h = Sections.TopLeftHole(store, isFree); if not h then break end        -- no hole: stop, never evict
    LiveGesture: Sections.PinFromOutside(copy, g, nil, isFree) with source s  -- ONE Pickup(s) + ONE Pickup(h)? NO:
      -- a move general->general is a SWAP into an EMPTY slot: Pickup(s); Pickup(h) = two ops, one gesture.
      -- D13.2 says one op per gesture; this is the first two-op gesture. MoveQueue already supports {from, to}.
  one magnet per flush; the next BAG_UPDATE_DELAYED (from our own move) runs the next -- self-paced, never a burst
```

- Menu: `Window.ShowGroupMenu` gains a radio submenu over `g.filter`; a value already used by another group is disabled.
- Scan: `KondoBags_ItemView` gains `family` (instant) and `craftingReagent` (async, via `Item:CreateFromBagAndSlot():ContinueOnItemLoad`).
- Saved: `KondoBagsCharDB.sections.list[i].filter`. Reconcile leaves it alone.
- Lock tooltip: shows the filter ("Keep: quest items").

## What it would cost

- ~1 new core file (`Core/Filters.lua`), changes in `Sections`, `BagState`, `Scan`, both providers, `Window.ShowGroupMenu`, tooltip.
- The first **two-op** gesture in the addon and the first **unattended** gesture: `MoveQueue` is ready for the mechanics, but
  D13.2 ("one server operation per gesture") and the Philosophy section of SPECS/00 would need a written amendment, not a quiet exception.
- A test matrix roughly the size of the existing one again: precedence, no-hole, combat deferral, async reagent flag, un-matching, login sweep.

## Alternatives that stay inside the current philosophy

These get most of the value without the addon ever moving an item by itself:

- **Highlight, don't move.** A filtered group's lock pulses softly when a matching item is sitting in incoming; the player
  drags it over (or clicks the lock to pull it — one deliberate gesture, one op). Zero unattended moves.
- **"Pull matching" on the lock menu.** Explicit, player-triggered bulk pass: same `RunMagnets` loop, but only when clicked.
  Keeps D13.2 in spirit (the gesture is the click; the ops are the player's intent).
- **Filter as a drop guard only.** The filter refuses non-matching manual drops (no-drop X) and nothing more. Cheapest; the
  group's meaning is enforced, the player still does the sorting.

## If we ever build it

Decisions needed first (owner):

- [ ] Confirm the alternatives above are NOT enough (the "pull matching" button in particular).
- [ ] Q1 — magnets pull from general slots only; typed-bag contents never move (proposed yes).
- [ ] Q2 — precedence quest > bag kind > crafting reagent > any; one group per filter (proposed yes).
- [ ] Q3 — arrival-only, never a login sweep without a click (proposed yes).
- [ ] Q4 — un-matching items stay put (proposed yes).
- [ ] Q5 — filtered lock refuses non-matching manual drops (proposed yes, with the no-drop X).
- [ ] Amend SPECS/00 D13.2 and Philosophy to admit the magnet gesture explicitly.

Then, and only then, a real bringup checklist replaces this section.