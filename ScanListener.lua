---@class Arbitrage
local Arbitrage = select(2, ...)

---@type table[] the current profit-sorted listings from the last completed Auctionator scan
Arbitrage.ProfitList = Arbitrage.ProfitList or {}

---@param listings table[] {itemId, itemLink, quantity, buyout}[]
local function UpdateProfitList(listings)
    Arbitrage.ProfitList = Arbitrage.BuildProfitList(listings)
    if Arbitrage.OnProfitListUpdated then
        Arbitrage.OnProfitListUpdated()
    end
end

-- Auctionator has two distinct full-scan mechanisms (see ScanData.lua for why); the default
-- in-game scan button uses the "incremental"/summary-mode one, so both are listened for.
local replicateListener = {}
function replicateListener.ReceiveEvent(_, _, scanData)
    UpdateProfitList(Arbitrage.ParseReplicateScanData(scanData))
end

local browseListener = {}
function browseListener.ReceiveEvent(_, _, rawScan)
    UpdateProfitList(Arbitrage.ParseBrowseScanData(rawScan))
end

if Auctionator and Auctionator.EventBus then
    if Auctionator.FullScan then
        Auctionator.EventBus:Register(replicateListener, {Auctionator.FullScan.Events.ScanComplete})
    end
    if Auctionator.IncrementalScan then
        Auctionator.EventBus:Register(browseListener, {Auctionator.IncrementalScan.Events.ScanComplete})
    end
end
