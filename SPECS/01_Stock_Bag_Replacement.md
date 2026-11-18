# SPEC 01 — Stock bag replacement (Phase L step 5)

- **Status:** Living spec (2026-11-18). Parent: `00_KondoBags_Core.md` ("Bag window": *one window replaces the default bag frames*).
- **Decision (owner, 2026-11-18): when KondoBags is installed it replaces the stock held-bag windows completely.** No setting, no checkbox.
  To see the stock bags, disable the addon.
- **Ground truth:** `_EXTERNAL_APIS/wow_bag_toggle_api_and_bagnon_pattern.md` (stock entry points per client; BagBrother's pattern).

## Decisions log

| # | Decision | Rationale |
|---|---|---|
| R1 | **Hook, do not replace.** Every stock bag function is left intact and `hooksecurefunc`'d. We never assign `_G.ToggleBackpack` etc. | The `TOGGLEBACKPACK`/`OPENALLBAGS` bindings and `ShowUIPanel -> OpenAllBags(MatchingContext)` are secure paths; replacing the globals taints them (workspace precedent: blocked item clicks, `MoveMyBags.Kuro/Core/Drag.lua:413`). Bagnon has shipped this hook-only pattern for years on every client. |
| R2 | **Stock frames are made invisible, never blocked.** Held-bag `ContainerFrameN` (and Forever's `ContainerFrameCombinedBags`) are re-parented into a hidden frame when they are assigned a bag we draw. | Stock `IsBagOpen(id)` then stays truthful for merchant/mail/bank "open bags on show" logic with no override from us (replaces Q-IsBagOpen from the original plan). |
| R3 | **Bag IDs we do not draw pass through untouched.** Era bank bags (`NUM_BAG_SLOTS+1..`) open as stock frames at the bank until M7. | Owner, Q1. |
| R4 | **Belt and braces on the stock frames**: in addition to the re-parent, `HookScript("OnShow")` on each held-bag stock frame hides it if its bag is ours. | Owner, Q2. Covers any direct `ContainerFrame_GenerateFrame` caller. |
| R5 | **Mockup removed this tag**: `Mock\MockSnapshot.lua` out of the TOC, `/kondo mock`, mock section store, mock carry icon and world-click hook deleted. `Client/Mock.lua` stays for `spec/run.lua`. | Owner, Q3; spec 00 step 5 line item. |
| R6 | **Window is pre-built at login** (`PLAYER_ENTERING_WORLD`): created and rendered once while hidden. | Owner, Q4. Secure cells cannot be made in combat; a first-ever open in combat must still show cells. |
| R7 | **Stock parity**: bag-bar highlight, open/close sounds, Escape closes. | Owner, Q5 (all three). |
| R8 | **Forever `combinedBags` cvar forced off** at load and on `CVAR_UPDATE` (out of combat), as BagBrother does. | With combined mode on, `ContainerFrameN:SetID` never fires for bags 1-4 and `ToggleBag_Combined` asserts; individual mode makes every stock path uniform and our re-parent hook complete. The player never sees stock bags anyway. |
| R9 | **Auto open/close is event-driven** (`PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE`, `TRADE_SKILL_*`, `CharacterFrame` hooks), not inferred from `OpenAllBags`/`CloseAllBags` hooks. | Same as BagBrother; the stock functions are no-ops when a stock bag is already "open" (which, hidden, it still is), so they cannot be relied on for intent. `CloseAllBags` IS hooked, for Escape (`CloseAllWindows`) only. |

## Architecture

New file **`KondoBags/UI/StockBags.lua`** (loaded after `UI/Window.lua`, before `KondoBags.lua`). Everything about the stock bag UI lives here; `KondoBags.lua` only calls `ns.StockBags.Setup()` on `PLAYER_LOGIN`.

```
 stock entry points --hooksecurefunc--> StockBags (dedupe by debugstack) --> ns.OpenBags() / ns.CloseBags() / ns.ToggleBags()
 ContainerFrameN:SetID(bag) -----------> StockBags: bag drawn by us? reparent -> KondoBagsStockBagSink (hidden) : restore
 PLAYER_INTERACTION_MANAGER_FRAME_* ---> StockBags: auto open/close
 Window show/hide -------------------------> StockBags.OnWindowShown(bool): bag-bar highlight + sound
```

### Names (linguistic keying)

| Symbol | Meaning |
|---|---|
| `ns.StockBags` | this module |
| `KondoBagsStockBagSink` | hidden `Frame` (parent `ContainerFrameContainer or UIParent`) that swallows stock held-bag frames |
| `KondoBags_HeldBagID` | a bag ID in the active provider's `BagIDs()` (backpack, bags 1-4, reagent, keyring on Era) — a bag **we draw** |
| `StockBags.IsOurBag(bagID) -> bool` | `bagID` is a `KondoBags_HeldBagID` |
| `ns.ToggleBags()`, `ns.OpenBags()`, `ns.CloseBags()` | the three public window actions in `KondoBags.lua` (live bag; attach, apply Edit Mode placement, show/hide) |
| `KondoBags_AutoDisplayInteraction` | an `Enum.PlayerInteractionType` value that opens the window: `Merchant`, `Banker`, `MailInfo`, `Auctioneer`, `TradePartner`, `GuildBanker`, `VoidStorageBanker`, `ItemUpgrade`, `Scrapping`? — see Open questions |

## Behaviour

### Toggle hooks (R1)

```lua
-- pseudocode
hooksecurefunc("ToggleAllBags", function()
  if not debugstack():find("Manager") then ns.ToggleBags() end
end)
hooksecurefunc("ToggleBackpack", function()
  local s = debugstack()
  if not s:find("ToggleAllBags") and not s:find("Manager") then ns.ToggleBags() end
end)
hooksecurefunc("ToggleBag", function(bag)
  local s = debugstack()
  if StockBags.IsOurBag(bag) and not s:find("OpenBackpack") and not s:find("ToggleBackpack") and not s:find("Manager") then ns.ToggleBags() end
end)
hooksecurefunc("CloseAllBags", function(frame) if frame == nil then ns.CloseBags() end end)   -- Escape / CloseAllWindows; frame-scoped calls are panel logic, handled by R9
if ToggleBackpack_Combined then hooksecurefunc("ToggleBackpack_Combined", function() ContainerFrameCombinedBags:SetParent(KondoBagsStockBagSink) end) end
```

- `ToggleBackpack` on Forever gates on `ContainerFrame_AllowedToOpenBags()` *before* our hook runs (hooks run after the body), so a toggle refused by stock (dead, `BagsUIDisabled` game rule) is also refused by us: the hook still fires. **Mirror the gate**: `ns.ToggleBags()` returns early when `ContainerFrame_AllowedToOpenBags` exists and is false, or on Era when `CanOpenPanels()` is false. Era's `ToggleBackpack` also returns on `IsOptionFrameOpen()`; mirror that too.
- Keybinds `TOGGLEBACKPACK`, `OPENALLBAGS`, `TOGGLEBAG1..4` all route through these three functions; no binding work needed.
- Bag-bar buttons (`MainMenuBarBackpackButton`, `CharacterBagNSlot`, Forever `BagsBar`) call `ToggleBackpack` / `ToggleBag`; covered.
- `/kondo` (no args) = `ns.ToggleBags()`.

### Hiding stock frames (R2, R4, R8)

```lua
-- pseudocode
local sink = CreateFrame("Frame", "KondoBagsStockBagSink", ContainerFrameContainer or UIParent); sink:Hide()
for i = 1, NUM_CONTAINER_FRAMES do
  local f = _G["ContainerFrame" .. i]
  hooksecurefunc(f, "SetID", function(frame, bag)
    if StockBags.IsOurBag(bag) then frame:SetParent(sink)
    elseif frame:GetParent() == sink then frame:SetParent(ContainerFrameContainer or UIParent) end
  end)
  f:HookScript("OnShow", function(frame) if StockBags.IsOurBag(frame:GetID()) then frame:Hide() end end)   -- R4
end
if ContainerFrameCombinedBags then ContainerFrameCombinedBags:SetParent(sink) end
-- R8
if C_CVar.GetCVarBool("combinedBags") then C_CVar.SetCVar("combinedBags", "0") end   -- Forever only; guard on cvar existence
on CVAR_UPDATE("combinedBags"): if not InCombatLockdown() and true -> SetCVar("combinedBags", "0")
```

- Era: `ContainerFrameN:SetID` is called by `ContainerFrame_GenerateFrame`; frames parented to `UIParent`. Same hook works (verified in `_ref/blizzard/classic_era/ContainerFrame_Shared.lua`).
- `Hide()` from `OnShow` in R4 is not protected for these frames (they are not secure); still, skip it if `InCombatLockdown()` — the sink parent already makes them invisible.
- Because stock frames still "open" (hidden), **stock's `UpdateNewItemList` on their hide and our `ClearNewItems` on our hide both run** — harmless duplicates.

### Auto display (R9)

```lua
-- pseudocode
AUTO = { Merchant=1, Banker=1, MailInfo=1, Auctioneer=1, TradePartner=1, GuildBanker=1, VoidStorageBanker=1 }   -- KondoBags_AutoDisplayInteraction
on PLAYER_INTERACTION_MANAGER_FRAME_SHOW(id): name = enum name for id; if AUTO[name] then ns.OpenBags() end
on PLAYER_INTERACTION_MANAGER_FRAME_HIDE(id): if AUTO[name] then ns.CloseBags() end
on TRADE_SKILL_SHOW / TRADE_SKILL_CLOSE: open / close (Era: `TradeSkillFrame` is loaded on demand; the event exists on both)
CharacterFrame:HookScript("OnShow", ns.OpenBags); CharacterFrame:HookScript("OnHide", ns.CloseBags)   -- stock opens bags with the character sheet on Forever? verify; Bagnon has it behind a setting
```

- `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` exists on Era 1.15 and Forever (both use the interaction manager; Bagnon relies on it for all clients ≥ 1.14).
- `ns.OpenBags()` while already shown is a no-op (no re-sound). `ns.CloseBags()` while hidden is a no-op.
- No `OpenAllBags` / `OpenBackpack` hooks: with a stock frame already (invisibly) shown they are no-ops and carry no intent.

### Stock parity (R7)

- **Bag bar**: on window show/hide, for each of `MainMenuBarBackpackButton`, `CharacterBag0Slot..3Slot`, `CharacterReagentBag0Slot`, `KeyRingButton` that exists: `button.SlotHighlightTexture:SetShown(shown)` if the region exists (Forever), else `button:SetChecked(shown)` (Era CheckButtons). Done from `Window.Show/Hide` via `ns.StockBags.OnWindowShown(bool)`.
- **Sounds**: `PlaySound(SOUNDKIT.IG_BACKPACK_OPEN)` on show, `SOUNDKIT.IG_BACKPACK_CLOSE` on hide (in `OnWindowShown`). Not on the hidden pre-build render (R6).
- **Escape**: via the `CloseAllBags(nil)` hook above. **Not** `UISpecialFrames` (would double-close and fight the stock sequence).

### Pre-build (R6) and `KondoBags.lua` changes

- `PLAYER_ENTERING_WORLD` (first only): `EnsureBag()` + `ns.Window.Attach(...)` + `ns.EditMode.ApplyToWindow()`; window stays hidden. Then `ClearNewItems()` as today.
- `Open(which)` / `source` / `mockBag` / `EnsureMock` / `KondoBagsCharDB.mockSections` removed (R5). `bag`, `liveBag` remain; `EnsureBag()` always live.
- `ns.ToggleBags()`, `ns.OpenBags()`, `ns.CloseBags()` added (gate, ensure, `Window.Show/Hide`).
- Slash: `/kondo` toggle; `mock` removed; `reset` resets live only; `status` drops `source`.
- `Window.lua`: delete `carry`, `Carry_*`, `StaticPopupDialogs.KONDOBAGS_MOCK_DESTROY`, `InstallWorldClickHook`, the `bag.live == false` branches in `Cell_OnClick/OnDragStart/OnReceiveDrag`, the "(mock)" tooltip line; `Window.Show/Hide` call `ns.StockBags.OnWindowShown(true/false)` (guarded, `Show` only when the frame was hidden).
- `BagState` keeps `live` flag (tests use the non-live path); only the view's mock branches go.

### Quest item highlight (owner request, 2026-11-18)

Stock draws a yellow border (`TEXTURE_ITEM_QUEST_BORDER`) on quest items and a `!` (`TEXTURE_ITEM_QUEST_BANG`) on items that *start* a
quest not yet accepted (`ContainerFrameItemButtonMixin:UpdateQuestItem` in `_ref/blizzard/forever/ContainerFrame.lua:1866`). Era's
stock bags hide the texture entirely (`ContainerFrame.Vanilla.lua`). We draw it on both clients, **slowly pulsing** so it reads.

- **Data**: provider gains `QuestInfo(bagID, slot) -> KondoBags_QuestFlags { isQuestItem, questID, isActive } | nil`, from
  `C_Container.GetContainerItemQuestInfo` (table on Mainline; Era returns the same table shape, confirmed in
  `_EXTERNAL_APIS/wow_classic_era_container_ui_api.md` -- verify, else fall back to classID 12 from `GetItemInfoInstant`).
  `Scan` copies it onto `KondoBags_ItemView.quest`. Mock provider returns nil.
- **View** (`DressCell`, secure cells): the template's own `IconQuestTexture` is used -- `TEXTURE_ITEM_QUEST_BANG` when
  `questID and not isActive`, `TEXTURE_ITEM_QUEST_BORDER` when `questID or isQuestItem`, hidden otherwise (stock rule, verbatim).
- **Pulse**: one `AnimationGroup` per secure cell, created lazily (`b.questPulse`), looping, two `Alpha` animations on
  `IconQuestTexture`: 1.0 -> 0.45 over 1.2 s, 0.45 -> 1.0 over 1.2 s, smoothing `IN_OUT`. `Play()` when the texture is shown,
  `Stop()` + alpha reset when hidden. Appearance-only: safe in combat, runs inside `DressCell` and `RefreshRef`.
- Constants: `KondoBags_QuestPulsePeriodSec = 2.4`, `KondoBags_QuestPulseMinAlpha = 0.45` in `UI/Theme.lua` (shared by both themes;
  the modern theme may override).
- Not a setting (spec 00 "Settings": anything beyond the list needs a reason it cannot be fixed behaviour).

## Bringup

- [x] Quest highlight: provider `QuestInfo`, `Scan` -> `item.quest`, `DressCell` quest texture + pulse animation group
- [x] `_EXTERNAL_APIS/wow_bag_toggle_api_and_bagnon_pattern.md` written (done 2026-11-18)
- [x] `UI/StockBags.lua`: sink frame, `SetID` + `OnShow` hooks, `combinedBags` cvar, toggle hooks with debugstack dedupe, `CloseAllBags` hook, interaction-manager auto display, `OnWindowShown` (bag bar + sound)
- [x] `KondoBags.lua`: remove mock source; `ns.ToggleBags/OpenBags/CloseBags` with the stock gates; pre-build on `PLAYER_ENTERING_WORLD`; `/kondo` toggle; `ns.StockBags.Setup()` on `PLAYER_LOGIN`
- [x] `UI/Window.lua`: remove carry icon, mock destroy popup, world-click hook, mock gesture branches; call `OnWindowShown`
- [x] TOC: add `UI\StockBags.lua`; drop `Mock\MockSnapshot.lua`. Delete `Mock/MockSnapshot.lua` (`git rm`)
- [x] `spec/run.lua` green (27 tests); `luacheck` 0 errors
- [x] SPECS/00: step 5 checked off with a pointer here; `/kondo mock` removed from step 2 milestone text; README "Status" + CHANGELOG entry
- [x] In-game verification (owner, Forever, 2026-11-18): `B`, bag-bar buttons, `/kondo`, Escape, first `B` after `/reload`, no stock frame visible, kept -> other group drops on mouse-up. **Era and the taint check (`/console taintLog 1` after a vendor session) still to run.**

### Findings while bringing up (2026-11-18)

- **Escape vs. the first-`B` reopen** (`903dec3`). Stock `ToggleBackpack_Individual` calls `CloseAllBags()` itself when the (invisible) stock
  backpack is open, so a `CloseAllBags` hook that closes our window makes the following `ToggleBackpack` hook reopen it. Name-matching the
  stack is NOT viable: `Blizzard_GameMenuEsc` dispatches Esc handlers through `securecallfunction(fn)`, so `CloseAllWindows` never appears
  in `debugstack()`. Resolution: a one-frame flag handoff -- the `CloseAllBags` hook closes and sets `closedByStock`; a `Toggle*` hook on the
  same stock call consumes it instead of toggling; `C_Timer.After(0)` clears it. R9's "CloseAllBags(nil) for Escape only" pseudocode above is
  superseded by this.
- **Profession bag in the reagent-bag slot** (`5dae33e`). Forever allows a herb bag in `Enum.BagIndex.ReagentBag` (5). `BagKind` must decide by
  family bits first; only a family-less bag in slot 5 is the reagent bag. `ItemFitsKind("reagent")` refuses family-bagged items.
- **Typed-cell tint on occupied cells** (`eb63acf`). The `ItemButton` icon is a full-cell BORDER-layer texture that covers the Quickslot ring, so
  tinting `NormalTexture` can only ever show on EMPTY cells. Occupied typed cells carry the kind tint on the OVERLAY `IconBorder` when the item
  has no quality colour.

### Added in the same tag (owner requests, 2026-11-18)

- **`KondoBagsDB.typedGlyph`** = `"bag"` (default) | `"kind"`: empty typed-slot art is the equipped bag's own icon (provider `BagIcon(bag)` ->
  `ref.bagIcon`) or the theme's item-type art. Replaces the ammo-only `ammoGlyph`. Options radios aligned (Section:Add dx is cumulative).
- **No-drop mark** (`cd7fecf`): while an item is carried, typed cells whose family refuses it (`Client.ItemFitsKind(heldFamily, kind)`,
  `BagState:HeldFits`) show the loot-roll Pass circle-X tinted `{1, .55, .55}`; occupied ones are also dimmed; empty ones are not. General
  cells never marked. Provider `ItemFamily(itemIDOrLink)`; `SyncCursor` passes the carried family to `SetCursor(ref, family)`.
- **Slim lock** (`113cff8`..`5995ff2`): a group whose items fill whole rows exactly gets its lock emitted `slim` at `col 0` on its top row
  (`KondoBags_LayoutResult.slimGutter`); the view widens the window by one gutter, draws the Quickslot ring at half width and the key glyph at
  full size, unclipped. Theme: `slimLockScale`, `slimDropGlyph`, `slimLockBg`.
- **Kept -> other group drop** (`cf0d0af`): the live reorder issues ONE `Pickup` on the item's own slot so the real cursor drops on mouse-up.
- `/kondo cursor`: debug readout of the carried item's family, per-kind fit, `BagState.held/heldFamily`, and which typed cells are marked.
- **Release polish** (`1d74619`..`f1e54ba`): fresh install anchors the window where the stock bags open (`window.placed`); display name
  "Kondo Bags" in the AddOns list / Settings (identifiers unchanged, owner decision: no rename); `/kondo reset` = factory reset behind
  `KONDOBAGS_RESET_ALL`, same button on the Settings page; modern theme: nil-glyph fix, dimmer window edge, flat `+`; README rewritten.
  Workspace `Scripts/release.cs` now discovers packager-style repos (`<name>\<name>\<name>.toc`) so `release.cmd` lists KondoBags.

## Open questions

- **Forever bag-bar "pressed" look**: Bagnon uses `button.SlotHighlightTexture:SetShown()`; verify on Forever in game (`/dump MainMenuBarBackpackButton.SlotHighlightTexture`). Fallback is harmless (`SetChecked` if available, else nothing).
- **`PLAYER_REGEN_DISABLED` auto-hide**: Bagnon option; we do nothing (stock bags do not close on combat).
- **`Enum.PlayerInteractionType` coverage on Era**: confirm `Merchant`, `Banker`, `MailInfo`, `Auctioneer`, `TradePartner` names exist (expected: yes, the enum is shared). If an Era vendor does not fire the event, fall back to `MERCHANT_SHOW/CLOSED`, `MAIL_SHOW/CLOSED`, `BANKFRAME_OPENED/CLOSED`, `AUCTION_HOUSE_SHOW/CLOSED`, `TRADE_SHOW/CLOSED`.
- *(resolved 2026-11-18)* No `CharacterFrame` auto-open: stock does not do it; we replace stock, we add nothing. Keyring (Era only, `KEYRING_CONTAINER`): `KeyRingButton` -> `ToggleBag(-2)` toggles our window; the keyring is already a typed run in it.