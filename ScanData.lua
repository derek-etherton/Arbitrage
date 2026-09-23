---@class Arbitrage
local Arbitrage = select(2, ...)

-- Field indices into C_AuctionHouse.GetReplicateItemInfo()'s return tuple, verified against
-- Auctionator's own Source_ModernAH/FullScan/Mixins/Frame.lua (GetInfo/ProcessBatch).
local REPLICATE_INFO = {
    QUANTITY = 3,
    BUYOUT = 10,
    ITEM_ID = 17,
}

---@param replicateInfo table raw C_AuctionHouse.GetReplicateItemInfo() tuple
---@return number|nil itemId
---@return number|nil quantity
---@return number|nil buyoutPerUnit
local function ParseReplicateInfo(replicateInfo)
    local quantity = replicateInfo[REPLICATE_INFO.QUANTITY]
    local totalBuyout = replicateInfo[REPLICATE_INFO.BUYOUT]
    local itemId = replicateInfo[REPLICATE_INFO.ITEM_ID]

    if (not itemId) or (not quantity) or quantity <= 0 or (not totalBuyout) or totalBuyout <= 0 then
        return nil
    end

    return itemId, quantity, totalBuyout / quantity
end

---@param scanData table[] raw payload from Auctionator.FullScan.Events.ScanComplete:
---    {replicateInfo: table, itemLink: string, timeLeft: number}[]
---@return table[] listings {itemId, itemLink, quantity, buyout}[] (buyout is per-unit)
function Arbitrage.ParseScanData(scanData)
    local listings = {}
    for i = 1, #scanData do
        local entry = scanData[i]
        local itemId, quantity, buyout = ParseReplicateInfo(entry.replicateInfo)
        if itemId then
            table.insert(listings, {
                itemId = itemId,
                itemLink = entry.itemLink,
                quantity = quantity,
                buyout = buyout,
            })
        end
    end
    return listings
end
