---@class Arbitrage
local Arbitrage = select(2, ...)

-- Entry point for the Disenchanting tab; the actual UI lives in Tabs/Disenchanting/.
local Disenchanting = Arbitrage.Disenchanting

local TAB_ID = "Arbitrage-Disenchanting"

local function CreateContentFrame()
    local frame = CreateFrame("Frame", "ArbitrageDisenchantingTabFrame", AuctionHouseFrame)
    -- Hand-tuned against this client's AH window (tabs sit at the bottom, not a top tab-strip).
    frame:SetPoint("LEFT", AuctionHouseFrame, "LEFT", 4, 0)
    frame:SetPoint("RIGHT", AuctionHouseFrame, "RIGHT", -4, 0)
    frame:SetPoint("BOTTOM", AuctionHouseFrame, "BOTTOM", 0, 27)
    frame:SetPoint("TOP", AuctionHouseFrame, "TOP", 0, -32)

    Disenchanting.CreateListView(frame)
    Disenchanting.CreateBuyView(frame)

    return frame
end

local function EnsureDisenchantingTab()
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
        EnsureDisenchantingTab()
    end
end)
