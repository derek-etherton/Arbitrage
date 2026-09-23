---@class Arbitrage
local Arbitrage = select(2, ...)

local Disenchanting = Arbitrage.Disenchanting

-- C_AuctionHouse.GetBrowseResults()'s minPrice is an aggregate "cheapest price" that can reflect
-- a bid-only auction's current bid when nothing has a buyout - not safe to treat as a buyout. The
-- per-listing item search results (below) separate buyoutAmount from bidAmount explicitly, and
-- also let us exclude the player's own listings (can't buy your own auction).
function Disenchanting.CollectBuyoutListings(itemKey)
    local listings = {}
    for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
        local resultInfo = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        if resultInfo and resultInfo.buyoutAmount and resultInfo.buyoutAmount > 0
            and not resultInfo.containsOwnerItem and not resultInfo.containsAccountItem then
            table.insert(listings, {
                auctionID = resultInfo.auctionID,
                buyout = resultInfo.buyoutAmount,
                quantity = resultInfo.quantity or 1,
            })
        end
    end
    table.sort(listings, function(a, b) return a.buyout < b.buyout end)
    return listings
end

-- The AH only supports one active item search at a time. Earlier this shared a single
-- overwrite-on-request slot between the hover-triggered refresh and the buy sub-view - but with
-- both visible side by side, hovering a list row while the buy pane's search was in flight would
-- silently steal that slot, and NOTHING would ever call the buy pane's callback again (not
-- success, not timeout) - a permanent hang, not a performance issue. A real FIFO queue instead:
-- every request eventually gets its turn and is guaranteed to resolve or time out.
local searchQueue = {}
local activeSearch -- {itemKey, onReady, onTimeout}
local currentPollTicker
local StartNextSearch

-- Mirrors Auctionator's own AuctionatorAHSearchScanFrameMixin: for a popular item, results
-- stream in over several batches and HasFullItemSearchResults can take a while (sometimes
-- longer than our poll window) to go true. Accepting the first non-empty batch - like
-- Auctionator does - keeps this fast; since we always sort ascending by price, that first
-- batch already contains the cheapest listings, which is all this pane cares about.
local function IsItemSearchReady(itemKey)
    if not C_AuctionHouse.HasSearchResults(itemKey) then
        return false
    end
    return C_AuctionHouse.HasFullItemSearchResults(itemKey)
        or C_AuctionHouse.GetItemSearchResultsQuantity(itemKey) > 0
end

local function TryResolveActive()
    if not activeSearch or not IsItemSearchReady(activeSearch.itemKey) then
        return false
    end

    local search = activeSearch
    activeSearch = nil
    if currentPollTicker then
        currentPollTicker:Cancel()
        currentPollTicker = nil
    end

    search.onReady(search.itemKey)
    StartNextSearch()
    return true
end

StartNextSearch = function()
    if activeSearch or #searchQueue == 0 then
        return
    end
    activeSearch = table.remove(searchQueue, 1)

    local sorts = {{sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false}}
    if Auctionator.AH and Auctionator.AH.SendSearchQueryByItemKey then
        Auctionator.AH.SendSearchQueryByItemKey(activeSearch.itemKey, sorts, true)
    else
        C_AuctionHouse.SendSearchQuery(activeSearch.itemKey, sorts, true)
    end

    -- Blizzard doesn't always re-fire ITEM_SEARCH_RESULTS_UPDATED when a search's results are
    -- already fully cached (e.g. this exact item was searched moments ago via hover) - without
    -- this poll, that leaves a request waiting forever for an event that never comes.
    local attempts = 0
    currentPollTicker = C_Timer.NewTicker(0.2, function(ticker)
        if TryResolveActive() then
            return
        end

        attempts = attempts + 1
        if attempts >= 15 then
            ticker:Cancel()
            currentPollTicker = nil
            local timedOut = activeSearch
            activeSearch = nil
            if timedOut.onTimeout then
                timedOut.onTimeout()
            end
            StartNextSearch()
        end
    end)
end

---@param entry table needs itemId, itemLevel, itemSuffix, battlePetSpeciesID
---@param onTimeout function|nil called if results never arrive within a few seconds
function Disenchanting.RequestLiveSearch(entry, onReady, onTimeout)
    local itemKey = Disenchanting.MakeItemKeyForEntry(entry)
    table.insert(searchQueue, {itemKey = itemKey, onReady = onReady, onTimeout = onTimeout})
    StartNextSearch()
end

-- BuyView.lua sets this to know when to refresh its listings after a purchase (ours or otherwise)
-- lands. Kept as a settable hook rather than a direct call so this module doesn't need to know
-- anything about the buy pane.
Disenchanting.OnBidReceived = nil

local liveQueryFrame = CreateFrame("Frame")
liveQueryFrame:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
liveQueryFrame:RegisterEvent("AUCTION_HOUSE_NEW_BID_RECEIVED")
liveQueryFrame:SetScript("OnEvent", function(_, eventName)
    if eventName == "AUCTION_HOUSE_NEW_BID_RECEIVED" then
        if Disenchanting.OnBidReceived then
            Disenchanting.OnBidReceived()
        end
    else
        TryResolveActive()
    end
end)
