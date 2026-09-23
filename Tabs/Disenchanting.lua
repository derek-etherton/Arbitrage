---@class Arbitrage
local Arbitrage = select(2, ...)

local AH = Arbitrage.AH
local TAB_ID = "Arbitrage-Disenchanting"
local PROFIT_KEY = "Disenchanting"

Arbitrage.RegisterProfitStrategy(PROFIT_KEY, function(listing)
    if not DisenchantBuddy then
        return nil
    end
    return DisenchantBuddy.API.v1.GetAverageDisenchantValueByItemID("Arbitrage", listing.itemId)
end)

local buyPane = AH.NewBuyPane()
local listPane = AH.NewListPane({
    profitListKey = PROFIT_KEY,
    valueLabel = "DE Value",
    emptyText = "Run a scan in Auctionator to populate this list.",
    onRowClick = function(entry) buyPane.Show(entry) end,
})

local function CreateContentFrame()
    local frame = CreateFrame("Frame", "ArbitrageDisenchantingTabFrame", AuctionHouseFrame)
    -- Hand-tuned against this client's AH window (tabs sit at the bottom, not a top tab-strip).
    frame:SetPoint("LEFT", AuctionHouseFrame, "LEFT", 4, 0)
    frame:SetPoint("RIGHT", AuctionHouseFrame, "RIGHT", -4, 0)
    frame:SetPoint("BOTTOM", AuctionHouseFrame, "BOTTOM", 0, 27)
    frame:SetPoint("TOP", AuctionHouseFrame, "TOP", 0, -32)

    listPane.Create(frame)
    buyPane.Create(frame, listPane.frame)

    return frame
end

local function EnsureTab()
    local LibAHTab = LibStub("LibAHTab-1-0")
    if LibAHTab:DoesIDExist(TAB_ID) then
        return
    end
    LibAHTab:CreateTab(TAB_ID, CreateContentFrame(), "Disenchanting")
end

local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
hookFrame:SetScript("OnEvent", function(_, eventName, interactionType)
    if eventName == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
        and interactionType == Enum.PlayerInteractionType.Auctioneer
        and AuctionHouseFrame then
        EnsureTab()
    end
end)
