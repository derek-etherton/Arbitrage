---@class Arbitrage
local Arbitrage = select(2, ...)

---@type table[] the current profit-sorted listings from the last completed Auctionator scan
Arbitrage.ProfitList = Arbitrage.ProfitList or {}

---@param listings table[] {itemId, itemLink, quantity, buyout}[]
---@param source string which scan produced this, for the diagnostic print below
local function UpdateProfitList(listings, source)
    Arbitrage.ProfitList = Arbitrage.BuildProfitList(listings)
    -- Temporary diagnostic while we confirm scan freshness.
    local top = Arbitrage.ProfitList[1]
    print(string.format(
        "Arbitrage: %s scan complete - %d listings, %d profitable%s",
        source, #listings, #Arbitrage.ProfitList,
        top and (", top: item " .. top.itemId .. " buyout " .. Arbitrage.FormatCoin(top.buyout, 12)) or ""
    ))
    if Arbitrage.OnProfitListUpdated then
        Arbitrage.OnProfitListUpdated()
    end
end

local replicateListener = {}
function replicateListener.ReceiveEvent(_, _, scanData)
    UpdateProfitList(Arbitrage.ParseReplicateScanData(scanData), "Replicate")
end

local browseListener = {}
function browseListener.ReceiveEvent(_, _, rawScan)
    UpdateProfitList(Arbitrage.ParseBrowseScanData(rawScan), "Browse")
end

if Auctionator and Auctionator.EventBus then
    if Auctionator.FullScan then
        Auctionator.EventBus:Register(replicateListener, {Auctionator.FullScan.Events.ScanComplete})
    end
    if Auctionator.IncrementalScan then
        Auctionator.EventBus:Register(browseListener, {Auctionator.IncrementalScan.Events.ScanComplete})
    end
end
