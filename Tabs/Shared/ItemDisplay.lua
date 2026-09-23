---@class Arbitrage
local Arbitrage = select(2, ...)

local AH = Arbitrage.AH

-- Random-suffix items (e.g. "War Knife of the Monkey") share one itemId across many variants;
-- MakeItemKey needs the exact suffix/level/petSpecies to find real listings for one.
function AH.MakeItemKeyForEntry(entry)
    return C_AuctionHouse.MakeItemKey(entry.itemId, entry.itemLevel, entry.itemSuffix, entry.battlePetSpeciesID)
end

-- Browse-scan entries have no itemLink, so a random-suffix item falls back to the plain name
-- ("War Knife") unless the AH's suffix-aware display text is already cached.
function AH.GetItemDisplayName(entry)
    if entry.itemLink then
        local name = entry.itemLink:match("%[(.-)%]")
        if name then
            return name
        end
    end

    if entry.itemSuffix and entry.itemSuffix ~= 0 then
        local itemKey = AH.MakeItemKeyForEntry(entry)
        local itemKeyInfo = C_AuctionHouse.GetItemKeyInfo(itemKey)
        if itemKeyInfo then
            local prettyName = AuctionHouseUtil.GetItemDisplayTextFromItemKey(itemKey, itemKeyInfo, false)
            if prettyName and prettyName ~= "" then
                return prettyName
            end
        end
    end

    return C_Item.GetItemInfo(entry.itemId) or ("Item #" .. entry.itemId)
end

-- Bare GetItemQualityColor is deprecated/absent on this client; C_Item.GetItemQualityColor
-- is the modern replacement, same return shape.
local GetItemQualityColor = C_Item.GetItemQualityColor or GetItemQualityColor

function AH.GetItemQualityColorCode(itemId)
    local _, _, quality = C_Item.GetItemInfo(itemId)
    if not quality then
        return ""
    end
    -- hex is a bare 8-digit AARRGGBB string with no "|c" lead-in.
    local _, _, _, hex = GetItemQualityColor(quality)
    return hex and ("|c" .. hex) or ""
end
