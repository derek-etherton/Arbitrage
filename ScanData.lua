---@class Arbitrage
local Arbitrage = select(2, ...)

-- Auctionator has two full-scan mechanisms with different payloads: "Replicate"
-- (Auctionator.FullScan.Events.ScanComplete) gives real per-listing data with an itemLink;
-- "Incremental"/summary mode (Auctionator.IncrementalScan.Events.ScanComplete, what the default
-- scan button triggers) gives per-itemKey aggregates with no itemLink. Both get parsed into the
-- same {itemId, itemLink, quantity, buyout, ...}[] shape so the rest of the pipeline doesn't care.

-- Field indices into C_AuctionHouse.GetReplicateItemInfo()'s tuple.
local REPLICATE_INFO = {
    QUANTITY = 3,
    BUYOUT = 10,
    ITEM_ID = 17,
}

-- Randomly-enchanted items (e.g. "War Knife of the Monkey") share one itemId across many suffix
-- variants, each a separate AH listing; MakeItemKey needs the exact suffix to find one. Extracted
-- the same way as Auctionator's own DBKeyFromLink.lua: the 7th colon-delimited field of the link.
local function GetItemSuffixFromLink(itemLink)
    if not itemLink then
        return nil
    end
    return tonumber(itemLink:match("item:.-:.-:.-:.-:.-:.-:(.-):"))
end

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
---@return table[] listings {itemId, itemLink, quantity, buyout, itemSuffix}[] (buyout is per-unit)
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
                itemLevel = 0,
                itemSuffix = GetItemSuffixFromLink(entry.itemLink) or 0,
                battlePetSpeciesID = 0,
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
---@return number itemLevel
---@return number itemSuffix
---@return number battlePetSpeciesID
local function ParseBrowseResult(resultInfo)
    local itemKey = resultInfo.itemKey
    local itemId = itemKey and itemKey.itemID
    local quantity = resultInfo.totalQuantity
    local minUnitPrice = resultInfo.minPrice

    if (not itemId) or (not quantity) or quantity <= 0 or (not minUnitPrice) or minUnitPrice <= 0 then
        return nil
    end

    return itemId, quantity, minUnitPrice, itemKey.itemLevel or 0, itemKey.itemSuffix or 0, itemKey.battlePetSpeciesID or 0
end

---@param rawScan table[] raw payload from Auctionator.IncrementalScan.Events.ScanComplete
---@return table[] listings {itemId, itemLink, quantity, buyout, itemSuffix}[] (itemLink is always
---    nil here; browse results aggregate by exact itemKey, not by individual listing)
function Arbitrage.ParseBrowseScanData(rawScan)
    local listings = {}
    for i = 1, #rawScan do
        local itemId, quantity, buyout, itemLevel, itemSuffix, battlePetSpeciesID = ParseBrowseResult(rawScan[i])
        if itemId then
            table.insert(listings, {
                itemId = itemId,
                itemLink = nil,
                quantity = quantity,
                buyout = buyout,
                itemLevel = itemLevel,
                itemSuffix = itemSuffix,
                battlePetSpeciesID = battlePetSpeciesID,
            })
        end
    end
    return listings
end
