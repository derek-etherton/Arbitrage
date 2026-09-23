---@class Arbitrage
local Arbitrage = select(2, ...)

-- Auctionator has two distinct full-scan mechanisms with different payload shapes, both
-- confirmed by reading Auctionator's own Source_ModernAH source directly:
--   - "Replicate" scan (Auctionator.FullScan.Events.ScanComplete): uses
--     C_AuctionHouse.ReplicateItems(), gives real per-listing data with an exact itemLink.
--   - "Incremental"/"summary mode" scan (Auctionator.IncrementalScan.Events.ScanComplete):
--     uses C_AuctionHouse.SendBrowseQuery(), gives per-itemKey aggregates (min price seen,
--     total quantity across all matching listings) with no itemLink. This is what the
--     default in-game scan button actually triggers ("Starting a full scan (summary mode)").
-- Both are parsed into the same {itemId, itemLink, quantity, buyout}[] shape so the rest of
-- the pipeline (ProfitList.lua, the UI) doesn't need to care which scan produced the data.

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
function Arbitrage.ParseReplicateScanData(scanData)
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

---@param resultInfo table single entry from C_AuctionHouse.GetBrowseResults(), as passed
---    through Auctionator's rawScan array
---@return number|nil itemId
---@return number|nil quantity
---@return number|nil minUnitPrice
local function ParseBrowseResult(resultInfo)
    local itemId = resultInfo.itemKey and resultInfo.itemKey.itemID
    local quantity = resultInfo.totalQuantity
    local minUnitPrice = resultInfo.minPrice

    if (not itemId) or (not quantity) or quantity <= 0 or (not minUnitPrice) or minUnitPrice <= 0 then
        return nil
    end

    return itemId, quantity, minUnitPrice
end

---@param rawScan table[] raw payload from Auctionator.IncrementalScan.Events.ScanComplete
---@return table[] listings {itemId, itemLink, quantity, buyout}[] (itemLink is always nil here;
---    browse results aggregate by item, not by individual listing)
function Arbitrage.ParseBrowseScanData(rawScan)
    local listings = {}
    for i = 1, #rawScan do
        local itemId, quantity, buyout = ParseBrowseResult(rawScan[i])
        if itemId then
            table.insert(listings, {
                itemId = itemId,
                itemLink = nil,
                quantity = quantity,
                buyout = buyout,
            })
        end
    end
    return listings
end
