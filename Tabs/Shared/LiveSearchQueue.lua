---@class Arbitrage
local Arbitrage = select(2, ...)

local AH = Arbitrage.AH

-- Stackable/fungible items (ore, herbs, cloth, gems, etc.) are "commodities" on the modern AH,
-- queried and purchased via a completely separate API from regular items (GetNumItemSearchResults
-- etc. silently return nothing for them). Same detection Auctionator's own Shopping results row
-- uses: C_AuctionHouse.GetItemKeyInfo(itemKey).isCommodity.
function AH.IsCommodityItemKey(itemKey)
    local info = C_AuctionHouse.GetItemKeyInfo(itemKey)
    return info ~= nil and info.isCommodity
end

-- GetBrowseResults()'s minPrice can be a bid-only auction's current bid, not a real buyout;
-- per-listing results (below) separate buyoutAmount from bidAmount and let us skip own listings.
-- Commodity results have no such "buyout vs bid" distinction (no bidding on commodities) and no
-- per-auction ID - a listing here is a price tier, bought via itemID + quantity, not an auctionID.
function AH.CollectBuyoutListings(itemKey)
    local listings = {}

    if AH.IsCommodityItemKey(itemKey) then
        for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemKey.itemID) do
            local resultInfo = C_AuctionHouse.GetCommoditySearchResultInfo(itemKey.itemID, i)
            if resultInfo and resultInfo.unitPrice and resultInfo.unitPrice > 0 then
                table.insert(listings, {
                    itemId = itemKey.itemID,
                    isCommodity = true,
                    buyout = resultInfo.unitPrice,
                    quantity = resultInfo.quantity or 1,
                })
            end
        end
    else
        for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
            local resultInfo = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
            if resultInfo and resultInfo.buyoutAmount and resultInfo.buyoutAmount > 0
                and not resultInfo.containsOwnerItem and not resultInfo.containsAccountItem then
                table.insert(listings, {
                    isCommodity = false,
                    auctionID = resultInfo.auctionID,
                    buyout = resultInfo.buyoutAmount,
                    quantity = resultInfo.quantity or 1,
                })
            end
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

-- HasFull*SearchResults can take a while for a popular item; accept the first non-empty batch
-- instead (like Auctionator does) since we sort ascending by price anyway.
local function IsSearchReady(itemKey)
    if AH.IsCommodityItemKey(itemKey) then
        return C_AuctionHouse.HasFullCommoditySearchResults(itemKey.itemID)
            or C_AuctionHouse.GetCommoditySearchResultsQuantity(itemKey.itemID) > 0
    end
    if not C_AuctionHouse.HasSearchResults(itemKey) then
        return false
    end
    return C_AuctionHouse.HasFullItemSearchResults(itemKey)
        or C_AuctionHouse.GetItemSearchResultsQuantity(itemKey) > 0
end

local function TryResolveActive()
    if not activeSearch or not IsSearchReady(activeSearch.itemKey) then
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
function AH.RequestLiveSearch(entry, onReady, onTimeout)
    local itemKey = AH.MakeItemKeyForEntry(entry)
    table.insert(searchQueue, {itemKey = itemKey, onReady = onReady, onTimeout = onTimeout})
    StartNextSearch()
end

-- Each buy pane instance appends its own refresh function here to know when a purchase lands.
AH.BidReceivedListeners = {}

local liveQueryFrame = CreateFrame("Frame")
liveQueryFrame:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
liveQueryFrame:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
liveQueryFrame:RegisterEvent("AUCTION_HOUSE_NEW_BID_RECEIVED")
liveQueryFrame:SetScript("OnEvent", function(_, eventName)
    if eventName == "AUCTION_HOUSE_NEW_BID_RECEIVED" then
        for _, listener in ipairs(AH.BidReceivedListeners) do
            listener()
        end
    else
        TryResolveActive()
    end
end)
