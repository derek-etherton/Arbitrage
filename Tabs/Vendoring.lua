---@class Arbitrage
local Arbitrage = select(2, ...)

local AH = Arbitrage.AH
local TAB_ID = "Arbitrage-Vendoring"
local PROFIT_KEY = "Vendoring"

Arbitrage.RegisterProfitStrategy(PROFIT_KEY, function(listing)
    local sellPrice = select(11, C_Item.GetItemInfo(listing.itemId))
    if not sellPrice or sellPrice <= 0 then
        return nil
    end
    return sellPrice
end)

local buyPane = AH.NewBuyPane()
local listPane = AH.NewListPane({
    profitListKey = PROFIT_KEY,
    valueLabel = "Vendor Value",
    emptyText = "Run a scan in Auctionator to populate this list.",
    onRowClick = function(entry) buyPane.Show(entry) end,
})

local function CreateContentFrame()
    local frame = CreateFrame("Frame", "ArbitrageVendoringTabFrame", AuctionHouseFrame)
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
    LibAHTab:CreateTab(TAB_ID, CreateContentFrame(), "Vendoring")
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
