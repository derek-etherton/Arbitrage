---@class Arbitrage
local Arbitrage = select(2, ...)

---@type table[] the current profit-sorted listings from the last completed Auctionator full scan
Arbitrage.ProfitList = Arbitrage.ProfitList or {}

local listener = {}
function listener.ReceiveEvent(_, _, scanData)
    local listings = Arbitrage.ParseScanData(scanData)
    Arbitrage.ProfitList = Arbitrage.BuildProfitList(listings)

    if Arbitrage.OnProfitListUpdated then
        Arbitrage.OnProfitListUpdated()
    end
end

if Auctionator and Auctionator.EventBus and Auctionator.FullScan then
    Auctionator.EventBus:Register(listener, {Auctionator.FullScan.Events.ScanComplete})
end
