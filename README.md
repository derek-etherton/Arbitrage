# Arbitrage

A World of Warcraft addon that adds a **Disenchanting** tab to the Auction House, surfacing listings worth buying purely to disenchant — items where `expected disenchant value − buyout price` is highest.

Targets **"WoW: Forever"** only for now (`_classic_beta_`, `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`, TOC interface `16001`) — that's the only client the maintainer currently tests on. Broader Classic-progression compatibility (Cata/Mists Classic, which also use the modern `AuctionHouseFrame`) is possible later — see [Compatibility](#compatibility) — but isn't a goal right now.

## Status

**Milestone 1 (done):** a blank "Disenchanting" tab appears in the Auction House, positioned after Auctionator's own tabs.

**Milestone 2 (in progress):** the tab now shows a scrollable, profit-sorted list of listings from the last Auctionator full scan. Working end-to-end, but not yet verified against a real in-game scan (see [Known gaps](#known-gaps)).

## Dependencies

- **Auctionator** (`## RequiredDeps`) — the whole feature is meaningless without it. Provides the embedded `LibAHTab-1-0` pattern this addon also embeds, and the only available source of per-listing auction data (via an internal event — see below).
- **DisenchantBuddy** (`## OptionalDeps`) — provides the actual disenchant-value math via `DisenchantBuddy.API.v1.GetAverageDisenchantValueByItemID`. Auctionator has its own internal `GetDisenchantPriceByItemID`, but it's gated to `LE_EXPANSION_WARLORDS_OF_DRAENOR`-and-later gear (see `Auctionator/Source_Mainline/Enchant/Main.lua`) and returns `nil` for all Classic-Era/Forever-style gear — it's not usable here. Without DisenchantBuddy loaded, the list is simply always empty (`ProfitList.lua` returns `{}`).

## How it works

### Tab injection

Blizzard's modern `AuctionHouseFrame` doesn't have a public "add your own tab" API. Auctionator solves this with a small shared library, `LibAHTab-1-0` (embedded, LibStub-based — safe for multiple addons to embed independently, newest version wins at runtime). It creates a real Blizzard tab button (`AuctionHouseFrameDisplayModeTabTemplate`) anchored after the existing tab row, with zero taint risk since it never touches `AuctionHouseFrame.Tabs` directly.

`Tabs/DisenchantingTab.lua` waits for `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` (with `Enum.PlayerInteractionType.Auctioneer`) — the same event Auctionator itself uses to know the AH is open — then calls `LibAHTab:CreateTab(...)` once. The `if AuctionHouseFrame then` guard makes this a safe no-op on Vanilla-engine clients (Classic Era, Anniversary, and the Cata-onward `_classic_` client all use a different, older AH frame that doesn't have `AuctionHouseFrame` at all).

### Data pipeline

Auctionator has no public bulk-listing API — its persisted price DB is daily min/max aggregates only, not individual listings. The only way to get real per-listing data (buyout + itemID) is by listening to an **internal, undocumented** event Auctionator fires after the user runs a "Get All" full scan (`ScanListener.lua`):
```lua
local listener = {}
function listener.ReceiveEvent(_, eventName, scanData) ... end
Auctionator.EventBus:Register(listener, { Auctionator.FullScan.Events.ScanComplete })
```
Confirmed event name for the ModernAH tree (what this client uses): `"replicate_scan_complete"` (`Auctionator/Source_ModernAH/FullScan/Events.lua`) — this differs from the Legacy-AH tree's `"get_all_scan_complete"`.

**This means the list only ever reflects a snapshot from the last full scan, refreshed when the user re-scans — never continuously live.** This isn't a shortcut chosen for convenience: Blizzard throttles the one full-AH API (`C_AuctionHouse.ReplicateItems`) to once per 15 minutes account-wide, and every comparable addon (TSM, Auctioneer) works the same way. Since this hook is undocumented/internal to Auctionator, it could change or break on any Auctionator update without notice — worth a quick sanity check (`busted`/manual test) after Auctionator updates.

The payload (`scanData`) is an array of `{replicateInfo, itemLink, timeLeft}`. `replicateInfo` is the raw `C_AuctionHouse.GetReplicateItemInfo()` tuple — **verified directly against Auctionator's own `Source_ModernAH/FullScan/Mixins/Frame.lua`** (don't trust field indices from secondhand descriptions; an offset error here silently produces wrong numbers, not an error):
- `replicateInfo[3]` = quantity
- `replicateInfo[10]` = total buyout for the stack (divide by quantity for per-unit price)
- `replicateInfo[17]` = itemID

`ScanData.lua` parses this into `{itemId, itemLink, quantity, buyout}`, skipping zero-quantity, zero-buyout (bid-only), and missing-itemID entries. `ProfitList.lua` then values each via DisenchantBuddy's API, computes `profit = disenchantValue - buyout`, and sorts descending (a local comparator mirroring Auctionator's own `Source/Utilities/Sorting.lua` stable-tiebreak pattern, without depending on Auctionator's internal `Constants.SORT` enum).

### UI

`Tabs/DisenchantingTab.lua` renders `Arbitrage.ProfitList` as a scrollable list (icon, name, buyout, DE value, profit) inside a `UIPanelScrollFrameTemplate`, capped at 200 rows (a scan filtered down to actually-disenchantable Uncommon+ armor/weapons shouldn't exceed this by much; if it does in practice, worth revisiting). A pure scrolling list rather than click-through pagination — matches Blizzard's own AH result-list UX and Auctionator's own Shopping/Buying tabs, and was simpler to implement correctly.

Item icon/name come directly from the item link (`%[(.-)%]` pattern match for the name, `C_Item.GetItemIconByID` for the icon) rather than async `Item:CreateFromItemID():ContinueOnItemLoad()` loading. This is a deliberate simplification for this pass, not a bug — it works for any item with a real link, which every AH listing has. Revisit if truncated/garbled names show up in practice.

## Known gaps

- **Not yet tested against a real in-game "Get All" scan.** The data pipeline (`ScanData.lua`/`ProfitList.lua`) is unit-tested against synthetic data; the actual `Auctionator.FullScan.Events.ScanComplete` payload shape has only been verified by reading Auctionator's source, not by observing a real firing. Test this next: run a full scan in Auctionator, confirm the Disenchanting tab populates with sensible numbers.
- **No visible "click to open Auctionator's Buy tab for this item" action** — the list is informational only; you can't act on a row yet.
- **200-row cap** with no indication when it's hit — a status line ("Showing top 200 of N") would be a small, worthwhile follow-up.

## Compatibility

`AuctionHouseFrame`/LibAHTab only exists on clients using Blizzard's modern AH UI: Cataclysm Classic, Mists Classic, and Mainline/Forever. Vanilla-engine clients (Classic Era, Anniversary, and the Cata-onward `_classic_` progression client, which still uses the old `AuctionFrame`) don't have it at all — the tab will simply never appear there, harmlessly, via the `AuctionHouseFrame` existence guard.

Currently the `.toc` only declares `## Interface: 16001` (Forever's specific range). To extend to Cata/Mists Classic later, follow Auctionator's own precedent: one `.toc`, multiple comma-separated interface numbers (e.g. `## Interface: 50504, 40402, 16001`) rather than per-expansion-suffixed `.toc` files.

## Development

Follows DisenchantBuddy's established conventions (`busted`, `.test.lua` naming, TDD, `luacheck`) for consistency — see `DisenchantBuddy/AGENTS.md`. Pure logic (`ScanData.lua`, `ProfitList.lua`) is tested; UI code (`Tabs/DisenchantingTab.lua`) isn't, matching how DisenchantBuddy itself only tests logic, not frame/rendering code.

```powershell
$env:PATH += ";$env:APPDATA\luarocks\bin"   # one-time per shell if not already permanent
busted -p ".test.lua" .
luacheck -q .
```

To test changes in-game: copy this folder into `<WoW install>\_classic_beta_\Interface\AddOns\Arbitrage`, `/reload`, open the Auction House.
