---@class Arbitrage
local Arbitrage = select(2, ...)

-- Mirrors Auctionator's own Source/Utilities/Sorting.lua NumberComparator (stable descending
-- sort via an insertion-order tiebreak) without depending on its internal Constants.SORT enum.
local function ProfitDescendingComparator(left, right)
    if left.profit ~= right.profit then
        return left.profit > right.profit
    end
    return left.sortingIndex < right.sortingIndex
end

---@param listings table[] {itemId, itemLink, quantity, buyout, itemLevel, itemSuffix, battlePetSpeciesID}[] (buyout is per-unit)
---@param getValue fun(listing: table): number|nil the profit strategy (disenchant value, vendor price, ...)
---@return table[] profitList {itemId, itemLink, quantity, buyout, itemLevel, itemSuffix, battlePetSpeciesID, value, profit}[], sorted by profit descending
function Arbitrage.BuildProfitList(listings, getValue)
    local profitList = {}

    for i = 1, #listings do
        local listing = listings[i]
        local value = getValue(listing)
        if value then
            table.insert(profitList, {
                itemId = listing.itemId,
                itemLink = listing.itemLink,
                quantity = listing.quantity,
                buyout = listing.buyout,
                itemLevel = listing.itemLevel or 0,
                itemSuffix = listing.itemSuffix or 0,
                battlePetSpeciesID = listing.battlePetSpeciesID or 0,
                value = value,
                profit = value - listing.buyout,
                sortingIndex = #profitList + 1,
            })
        end
    end

    table.sort(profitList, ProfitDescendingComparator)
    return profitList
end
