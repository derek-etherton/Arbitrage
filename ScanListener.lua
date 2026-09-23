---@class Arbitrage
local Arbitrage = select(2, ...)

---@param listings table[] {itemId, itemLink, quantity, buyout}[]
---@param source string which scan produced this, for the diagnostic print below
local function UpdateProfitList(listings, source)
    Arbitrage.RefreshAllProfitLists(listings)

    -- Temporary diagnostic while we confirm scan freshness.
    local summary = {}
    for key, profitList in pairs(Arbitrage.ProfitLists) do
        local top = profitList[1]
        table.insert(summary, string.format("%s: %d profitable%s", key, #profitList,
            top and (", top buyout " .. Arbitrage.FormatCoin(top.buyout, 12)) or ""))
    end
    print(string.format("Arbitrage: %s scan complete - %d listings. %s", source, #listings, table.concat(summary, " | ")))
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
