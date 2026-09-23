# Arbitrage

A World of Warcraft addon that adds a **Disenchanting** tab to the Auction House, surfacing listings worth buying purely to disenchant — items where `expected disenchant value − buyout price` is highest.

Targets **"WoW: Forever"** only for now (`_classic_beta_`, `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`, TOC interface `16001`) — that's the only client the maintainer currently tests on. Broader Classic-progression compatibility (Cata/Mists Classic, which also use the modern `AuctionHouseFrame`) is possible later — see [Compatibility](#compatibility) — but isn't a goal right now.

## Status

Working end-to-end and verified in-game. The Disenchanting tab shows a profit-sorted, paginated list of listings from the last Auctionator full scan on the left, and clicking a row opens a side pane on the right listing that item's actual current buyout listings, with a "Buy" action per listing (confirmation popup, then `C_AuctionHouse.PlaceBid`).

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

The tab's UI lives under `Tabs/Disenchanting/`, split by concern rather than one large file:

- **`Layout.lua`** — shared sizing constants (row height, column widths, pane widths) both panes read from.
- **`ItemDisplay.lua`** — item name/quality-color lookups. Randomly-enchanted items (e.g. "War Knife of the Monkey") share one `itemId` across many distinct suffix variants, each a separate AH listing; this is also where `itemLevel`/`itemSuffix`/`battlePetSpeciesID` get turned into the exact `itemKey` needed to find one.
- **`LiveSearchQueue.lua`** — the AH only supports one active item search at a time, so every live price lookup (hover refresh, the buy pane) goes through a small FIFO queue here rather than each caller firing its own search and stomping on the others.
- **`ListView.lua`** — the left pane: the paginated (20/page), profit-sorted list, hover-triggered live buyout correction, and the manual "Reload" button.
- **`BuyView.lua`** — the right pane: opened by clicking a list row, shows that item's real current buyout listings (cheapest 20, with a "+N more" note), and handles the purchase confirm/`PlaceBid` flow.

`Tabs/DisenchantingTab.lua` is just the entry point — it builds the AH-open hook and wires the two panes into one content frame; it doesn't contain any of the actual list/buy logic.

Item icon/name come from the item link (`%[(.-)%]` pattern match) when one's available (replicate scans), falling back to `C_Item.GetItemInfo`/the AH's suffix-aware display text otherwise (browse scans have no link — see `ItemDisplay.lua`).

## Known gaps

- **The "Reload" button and hover refresh only correct what's already on screen** — they don't re-run Auctionator's own scan, so a genuinely new listing that undercuts everything won't appear until the next full "Get All" scan.
- **No support for clients using the Legacy AH** (TBC/Wrath/Vanilla-engine, including TBC Anniversary) — see [Compatibility](#compatibility). Loading there currently risks a load-time error rather than a clean no-op; worth guarding if this addon is ever used somewhere Forever isn't guaranteed.

## Compatibility

`AuctionHouseFrame`/LibAHTab only exists on clients using Blizzard's modern AH UI: Cataclysm Classic, Mists Classic, and Mainline/Forever. Vanilla-engine clients (Classic Era, Anniversary, and the Cata-onward `_classic_` progression client, which still uses the old `AuctionFrame`) don't have it at all — the tab will simply never appear there, harmlessly, via the `AuctionHouseFrame` existence guard.

Currently the `.toc` only declares `## Interface: 16001` (Forever's specific range). To extend to Cata/Mists Classic later, follow Auctionator's own precedent: one `.toc`, multiple comma-separated interface numbers (e.g. `## Interface: 50504, 40402, 16001`) rather than per-expansion-suffixed `.toc` files.

## Development

Follows DisenchantBuddy's established conventions (`busted`, `.test.lua` naming, TDD, `luacheck`) for consistency — see `DisenchantBuddy/AGENTS.md`. Pure logic (`ScanData.lua`, `ProfitList.lua`) is tested; UI code (`Tabs/DisenchantingTab.lua`, `Tabs/Disenchanting/*.lua`) isn't, matching how DisenchantBuddy itself only tests logic, not frame/rendering code.

```powershell
$env:PATH += ";$env:APPDATA\luarocks\bin"   # one-time per shell if not already permanent
busted -p ".test.lua" .
luacheck -q .
```

To test changes in-game: copy this folder into `<WoW install>\_classic_beta_\Interface\AddOns\Arbitrage`, `/reload`, open the Auction House.
