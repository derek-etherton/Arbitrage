---@class Arbitrage
local Arbitrage = select(2, ...)

local TAB_ID = "Arbitrage-Disenchanting"

local function CreateContentFrame()
    local frame = CreateFrame("Frame", "ArbitrageDisenchantingTabFrame", AuctionHouseFrame)
    -- Same anchor offsets Auctionator's own AuctionatorTabFrameTemplate uses
    -- (Source\Tabs\Frames\TabFrame.xml), without inheriting that private template.
    frame:SetPoint("LEFT", AuctionHouseFrame, "LEFT", 4, 0)
    frame:SetPoint("RIGHT", AuctionHouseFrame, "RIGHT", -4, 0)
    frame:SetPoint("BOTTOM", AuctionHouseFrame, "BOTTOM", 0, 27)
    frame:SetPoint("TOP", AuctionHouseFrame, "TOP", 0, -103)

    local placeholder = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    placeholder:SetPoint("CENTER")
    placeholder:SetText("Disenchanting (coming soon)")

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
