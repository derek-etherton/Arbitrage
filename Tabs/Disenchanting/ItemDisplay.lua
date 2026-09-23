---@class Arbitrage
local Arbitrage = select(2, ...)

local Disenchanting = Arbitrage.Disenchanting

-- Randomly-enchanted items (e.g. "War Knife of the Monkey") share one itemId across a dozen
-- distinct suffix variants; C_AuctionHouse.MakeItemKey needs the exact itemLevel/itemSuffix/
-- battlePetSpeciesID to find real listings for one specific variant (see ScanData.lua).
function Disenchanting.MakeItemKeyForEntry(entry)
    return C_AuctionHouse.MakeItemKey(entry.itemId, entry.itemLevel, entry.itemSuffix, entry.battlePetSpeciesID)
end

-- Browse-scan results (see ScanData.lua) have no itemLink, only itemKey components. The plain
-- item name is misleading for a random-suffix item (every "War Knife of the X" variant would
-- otherwise show as just "War Knife"), so ask the AH for the suffix-aware display text when the
-- item's key info happens to already be cached; otherwise fall back to the plain name.
function Disenchanting.GetItemDisplayName(entry)
    if entry.itemLink then
        local name = entry.itemLink:match("%[(.-)%]")
        if name then
            return name
        end
    end

    if entry.itemSuffix and entry.itemSuffix ~= 0 then
        local itemKey = Disenchanting.MakeItemKeyForEntry(entry)
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

-- The bare GetItemQualityColor global is deprecated/absent on this client (it errors with
-- "attempt to call a nil value"); C_Item.GetItemQualityColor is the modern replacement, same
-- (r, g, b, hex) return shape.
local GetItemQualityColor = C_Item.GetItemQualityColor or GetItemQualityColor

-- None of GetItemDisplayName's paths embed quality coloring, so every name rendered in
-- GameFontNormal's default (pale yellow) regardless of actual rarity - apply it uniformly here.
function Disenchanting.GetItemQualityColorCode(itemId)
    local _, _, quality = C_Item.GetItemInfo(itemId)
    if not quality then
        return ""
    end
    -- hex is a bare 8-digit AARRGGBB string (no "|c" lead-in) - without prepending it ourselves,
    -- it renders as literal text ("ff1eff00Item Name") instead of being parsed as a color code,
    -- which also overflows the column width and wraps into the row below.
    local _, _, _, hex = GetItemQualityColor(quality)
    return hex and ("|c" .. hex) or ""
end
