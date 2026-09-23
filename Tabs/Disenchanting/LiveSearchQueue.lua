---@class Arbitrage
local Arbitrage = select(2, ...)

local Disenchanting = Arbitrage.Disenchanting

-- GetBrowseResults()'s minPrice can be a bid-only auction's current bid, not a real buyout;
-- per-listing results (below) separate buyoutAmount from bidAmount and let us skip own listings.
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

-- The AH only supports one active item search at a time, so requests queue up rather than
-- overwrite each other (an overwrite could strand an in-flight request with no callback ever
-- firing, since it never gets a "cancelled" signal from Blizzard either).
local searchQueue = {}
local activeSearch -- {itemKey, onReady, onTimeout}
local currentPollTicker
local StartNextSearch

-- HasFullItemSearchResults can take a while for a popular item; accept the first non-empty
-- batch instead (like Auctionator does) since we sort ascending by price anyway.
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

    -- Poll as a fallback: Blizzard doesn't always re-fire the event for already-cached results.
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

-- BuyView.lua hooks this to refresh its listings after a purchase lands.
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
