# Arbitrage

A World of Warcraft addon that adds a **Disenchanting** tab to the Auction House, surfacing listings worth buying purely to disenchant — items where `expected disenchant value − buyout price` is highest.

Currently targets **"WoW: Forever"** only (`_classic_beta_`, `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`, TOC interface `16001`). Compatibility with other Classic-progression flavors (Cata/Mists Classic, which also use the modern `AuctionHouseFrame`) is a nice-to-have, not a current goal — see [Compatibility](#compatibility).

## Status

**Milestone 1 (done):** a blank "Disenchanting" tab appears in the Auction House, positioned after Auctionator's own tabs.

**Milestone 2 (not started):** populate that tab with a paginated, sorted list of auction listings by disenchant profit. See [Roadmap](#roadmap).

## Dependencies

- **Auctionator** (`## RequiredDeps`) — the whole feature is meaningless without it. Provides the embedded `LibAHTab-1-0` pattern this addon also embeds, and (for Milestone 2) the only available source of per-listing auction data.
- **DisenchantBuddy** (`## OptionalDeps`, will become required once Milestone 2 lands) — provides the actual disenchant-value math via `DisenchantBuddy.API.v1.GetAverageDisenchantValueByItemID/ByItemLink`. Auctionator has its own internal `GetDisenchantPriceByItemID`, but it's gated to `LE_EXPANSION_WARLORDS_OF_DRAENOR`-and-later gear (see `Auctionator/Source_Mainline/Enchant/Main.lua`) and returns `nil` for all Classic-Era/Forever-style gear — it's not usable here.

## How it works

Blizzard's modern `AuctionHouseFrame` doesn't have a public "add your own tab" API. Auctionator solves this with a small shared library, `LibAHTab-1-0` (embedded, LibStub-based — safe for multiple addons to embed independently, newest version wins at runtime). It creates a real Blizzard tab button (`AuctionHouseFrameDisplayModeTabTemplate`) anchored after the existing tab row, with zero taint risk since it never touches `AuctionHouseFrame.Tabs` directly.

`Tabs/DisenchantingTab.lua` waits for `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` (with `Enum.PlayerInteractionType.Auctioneer`) — the same event Auctionator itself uses to know the AH is open — then calls `LibAHTab:CreateTab(...)` once. The `if AuctionHouseFrame then` guard makes this a safe no-op on Vanilla-engine clients (Classic Era, Anniversary, and the Cata-onward `_classic_` client all use a different, older AH frame that doesn't have `AuctionHouseFrame` at all).

## Roadmap (Milestone 2)

Not yet implemented. Design, verified against Auctionator's actual source:

1. **Data source**: Auctionator has no public bulk-listing API — its persisted price DB is daily min/max aggregates only. The only way to get real per-listing data (buyout + itemID) is by listening to an **internal, undocumented** event Auctionator fires after the user runs a "Get All" full scan:
   ```lua
   local listener = {}
   function listener:ReceiveEvent(eventName, scanData) ... end
   Auctionator.EventBus:Register(listener, { Auctionator.FullScan.Events.ScanComplete })
   ```
   Confirmed event name for the ModernAH tree (what this client uses): `"replicate_scan_complete"` (`Auctionator/Source_ModernAH/FullScan/Events.lua`) — this differs from the Legacy-AH tree's `"get_all_scan_complete"`, so don't copy that string from older references.

   **This means the tab only ever shows a snapshot from the last full scan, refreshed when the user re-scans — never continuously live.** This isn't a shortcut we chose; Blizzard throttles the one full-AH API (`C_AuctionHouse.ReplicateItems`) to once per 15 minutes account-wide, and every comparable addon (TSM, Auctioneer) works the same way. Also: since this hook is undocumented/internal to Auctionator, it could change or break on any Auctionator update without notice — worth a quick sanity check after Auctionator updates.

2. **Payload → profit**: for each scan entry, resolve `itemLink → itemID` via `C_Item.GetItemInfoInstant`, call `DisenchantBuddy.API.v1.GetAverageDisenchantValueByItemID("Arbitrage", itemID)`, compute `profit = averageDisenchantValue - buyout`.

3. **Sorting**: a local `NumberComparator(order, fieldName)` mirroring `Auctionator/Source/Utilities/Sorting.lua`'s stable-tie-via-index pattern (don't reach into Auctionator's own comparator — it depends on Auctionator's internal `Constants.SORT` enum). Sort the cached `{itemID, itemLink, buyout, disenchantValue, profit}` list by `profit` descending.

4. **UI**: a `ScrollFrame` + row-pool inside `DisenchantingTab.lua`'s (currently blank) content frame, same shape as Blizzard's standard AH result lists. Paginate.

5. **Caching**: rebuild the list entirely in the `ReceiveEvent` handler each time `ScanComplete` fires — no incremental updates needed given the snapshot model above.

## Compatibility

`AuctionHouseFrame`/LibAHTab only exists on clients using Blizzard's modern AH UI: Cataclysm Classic, Mists Classic, and Mainline/Forever. Vanilla-engine clients (Classic Era, Anniversary, and the Cata-onward `_classic_` progression client, which still uses the old `AuctionFrame`) don't have it at all — the tab will simply never appear there, harmlessly, via the `AuctionHouseFrame` existence guard.

Currently the `.toc` only declares `## Interface: 16001` (Forever's specific range). To extend to Cata/Mists Classic later, follow Auctionator's own precedent: one `.toc`, multiple comma-separated interface numbers (e.g. `## Interface: 50504, 40402, 16001`) rather than per-expansion-suffixed `.toc` files.

## Development

No test suite yet (the addon is still just a static tab registration — nothing meaningfully unit-testable until Milestone 2's pure functions, e.g. the profit calculation and sort comparator, land). When those arrive, follow DisenchantBuddy's established conventions (`busted`, `.test.lua` naming, TDD) for consistency — see `DisenchantBuddy/AGENTS.md`.

To test changes: copy this folder into `<WoW install>\_classic_beta_\Interface\AddOns\Arbitrage`, `/reload`, open the Auction House.
