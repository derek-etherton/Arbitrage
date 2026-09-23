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

---@param listings table[] {itemId, itemLink, quantity, buyout}[] (buyout is per-unit)
---@return table[] profitList {itemId, itemLink, quantity, buyout, disenchantValue, profit}[], sorted by profit descending
function Arbitrage.BuildProfitList(listings)
    local profitList = {}
    if (not DisenchantBuddy) then
        return profitList
    end

    for i = 1, #listings do
        local listing = listings[i]
        local disenchantValue = DisenchantBuddy.API.v1.GetAverageDisenchantValueByItemID("Arbitrage", listing.itemId)
        if disenchantValue then
            table.insert(profitList, {
                itemId = listing.itemId,
                itemLink = listing.itemLink,
                quantity = listing.quantity,
                buyout = listing.buyout,
                disenchantValue = disenchantValue,
                profit = disenchantValue - listing.buyout,
                sortingIndex = #profitList + 1,
            })
        end
    end

    table.sort(profitList, ProfitDescendingComparator)
    return profitList
end
