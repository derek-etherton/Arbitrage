# Arbitrage

A World of Warcraft addon that adds **Disenchanting** and **Vendoring** tabs to the Auction House, each surfacing listings worth buying purely to resell — items where `expected resale value − buyout price` is highest (disenchant value for one tab, vendor sell price for the other).

Targets **"WoW: Forever"** only for now (`_classic_beta_`, `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`, TOC interface `16001`) — that's the only client the maintainer currently tests on. Broader Classic-progression compatibility (Cata/Mists Classic, which also use the modern `AuctionHouseFrame`) is possible later — see [Compatibility](#compatibility) — but isn't a goal right now.

## Status

Working end-to-end and verified in-game. Each tab shows a profit-sorted, paginated list of listings from the last Auctionator full scan on the left, and clicking a row opens a side pane on the right listing that item's actual current buyout listings, with a "Buy" action per listing (confirmation popup, then `C_AuctionHouse.PlaceBid`).

## Dependencies

- **Auctionator** (`## RequiredDeps`) — the whole feature is meaningless without it. Provides the embedded `LibAHTab-1-0` pattern this addon also embeds, and the only available source of per-listing auction data (via an internal event — see below).
- **DisenchantBuddy** (`## OptionalDeps`) — powers the Disenchanting tab's value math via `DisenchantBuddy.API.v1.GetAverageDisenchantValueByItemID`. Auctionator has its own internal `GetDisenchantPriceByItemID`, but it's gated to `LE_EXPANSION_WARLORDS_OF_DRAENOR`-and-later gear (see `Auctionator/Source_Mainline/Enchant/Main.lua`) and returns `nil` for all Classic-Era/Forever-style gear — it's not usable here. Without DisenchantBuddy loaded, the Disenchanting tab is simply always empty; the Vendoring tab doesn't depend on it at all (vendor sell price comes straight from `C_Item.GetItemInfo`).

## How it works

### Tab injection

Blizzard's modern `AuctionHouseFrame` doesn't have a public "add your own tab" API. Auctionator solves this with a small shared library, `LibAHTab-1-0` (embedded, LibStub-based — safe for multiple addons to embed independently, newest version wins at runtime). It creates a real Blizzard tab button (`AuctionHouseFrameDisplayModeTabTemplate`) anchored after the existing tab row, with zero taint risk since it never touches `AuctionHouseFrame.Tabs` directly.

Each tab's orchestrator file (`Tabs/Disenchanting.lua`, `Tabs/Vendoring.lua`) waits for `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` (with `Enum.PlayerInteractionType.Auctioneer`) — the same event Auctionator itself uses to know the AH is open — then calls `LibAHTab:CreateTab(...)` once. The `if AuctionHouseFrame then` guard makes this a safe no-op on Vanilla-engine clients (Classic Era, Anniversary, and the Cata-onward `_classic_` client all use a different, older AH frame that doesn't have `AuctionHouseFrame` at all).

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

`ScanData.lua` parses this into `{itemId, itemLink, quantity, buyout, itemLevel, itemSuffix, battlePetSpeciesID}`, skipping zero-quantity, zero-buyout (bid-only), and missing-itemID entries.

### Profit strategies

`ProfitList.lua`'s `BuildProfitList(listings, getValue)` is generic — it doesn't know or care what "value" means, just that `profit = getValue(listing) - buyout`. Each tab registers its own `getValue` function under a unique key via `Arbitrage.RegisterProfitStrategy` (`ProfitStrategies.lua`):

- **Disenchanting** (`Tabs/Disenchanting.lua`) — `DisenchantBuddy.API.v1.GetAverageDisenchantValueByItemID`.
- **Vendoring** (`Tabs/Vendoring.lua`) — `C_Item.GetItemInfo`'s vendor sell price, no external dependency.

On every scan, `ScanListener.lua` calls `Arbitrage.RefreshAllProfitLists(listings)`, which rebuilds every registered strategy's list in one pass and stores each under `Arbitrage.ProfitLists[key]`.

### UI

The two tabs share almost all of their UI, under `Tabs/Shared/`:

- **`Layout.lua`** — sizing constants (row height, column widths, pane widths) both panes read from.
- **`ItemDisplay.lua`** — item name/quality-color lookups. Randomly-enchanted items (e.g. "War Knife of the Monkey") share one `itemId` across many distinct suffix variants, each a separate AH listing; this is also where `itemLevel`/`itemSuffix`/`battlePetSpeciesID` get turned into the exact `itemKey` needed to find one.
- **`LiveSearchQueue.lua`** — the AH only supports one active item search at a time, so every live price lookup (hover refresh, either buy pane) goes through one shared FIFO queue rather than each caller firing its own search and stomping on the others.
- **`ListPane.lua`** — `AH.NewListPane(config)`, a factory: give it a profit-list key, a "value" column label, and a row-click handler, and it builds a paginated (20/page), profit-sorted list with hover-triggered live buyout correction and a "Reload" button. Each tab creates its own instance.
- **`BuyPane.lua`** — `AH.NewBuyPane()`, a factory for the side pane opened by clicking a list row: shows that item's real current buyout listings (cheapest 20, with a "+N more" note) and handles the purchase confirm/`PlaceBid` flow. Each instance gets its own `StaticPopupDialogs` key since that table is global.

- **`TabController.lua`** — `AH.RegisterTab(config)`: given a tab id, title, settings key, and content-frame factory, handles creating the tab lazily on AH-open and applying its current show/hide setting. This is the only place the `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` hook lives.

`Tabs/Disenchanting.lua` and `Tabs/Vendoring.lua` are each just: register a profit strategy, instantiate a list pane + buy pane with the right labels, and call `AH.RegisterTab`. Neither contains any list/buy rendering logic, or its own AH-open hook.

Item icon/name come from the item link (`%[(.-)%]` pattern match) when one's available (replicate scans), falling back to `C_Item.GetItemInfo`/the AH's suffix-aware display text otherwise (browse scans have no link — see `ItemDisplay.lua`).

## Settings

`Settings.lua` stores per-tab show/hide flags in `Arbitrage_Profile.Settings` (`ShowDisenchanting`, `ShowVendoring`, both default `true`). `/arbitrage disenchanting|vendoring [on|off]` (`SlashCommands.lua`) toggles them live — no `/reload` needed, since `TabController.lua` just hides/shows the existing tab button via `LibAHTab:GetButton(tabId):SetShown(...)` rather than creating/destroying the tab. Running `/arbitrage` with no arguments prints current status. No graphical options panel yet; this was intentionally kept to the simplest thing that works, following DisenchantBuddy's own slash-command-only precedent.

## Known gaps

- **The "Reload" button and hover refresh only correct what's already on screen** — they don't re-run Auctionator's own scan, so a genuinely new listing that undercuts everything won't appear until the next full "Get All" scan.
- **No support for clients using the Legacy AH** (TBC/Wrath/Vanilla-engine, including TBC Anniversary) — see [Compatibility](#compatibility). Loading there currently risks a load-time error rather than a clean no-op; worth guarding if this addon is ever used somewhere Forever isn't guaranteed.

## Compatibility

`AuctionHouseFrame`/LibAHTab only exists on clients using Blizzard's modern AH UI: Cataclysm Classic, Mists Classic, and Mainline/Forever. Vanilla-engine clients (Classic Era, Anniversary, and the Cata-onward `_classic_` progression client, which still uses the old `AuctionFrame`) don't have it at all — the tab will simply never appear there, harmlessly, via the `AuctionHouseFrame` existence guard.

Currently the `.toc` only declares `## Interface: 16001` (Forever's specific range). To extend to Cata/Mists Classic later, follow Auctionator's own precedent: one `.toc`, multiple comma-separated interface numbers (e.g. `## Interface: 50504, 40402, 16001`) rather than per-expansion-suffixed `.toc` files.

## Development

Follows DisenchantBuddy's established conventions (`busted`, `.test.lua` naming, TDD, `luacheck`) for consistency — see `DisenchantBuddy/AGENTS.md`. Pure logic (`ScanData.lua`, `ProfitList.lua`, `Settings.lua`) is tested; UI/command code (`Tabs/*.lua`, `Tabs/Shared/*.lua`, `SlashCommands.lua`) isn't, matching how DisenchantBuddy itself only tests logic, not frame/rendering code.

```powershell
$env:PATH += ";$env:APPDATA\luarocks\bin"   # one-time per shell if not already permanent
busted -p ".test.lua" .
luacheck -q .
```

To test changes in-game: copy this folder into `<WoW install>\_classic_beta_\Interface\AddOns\Arbitrage`, `/reload`, open the Auction House.
