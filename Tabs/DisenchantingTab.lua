---@class Arbitrage
local Arbitrage = select(2, ...)

-- Entry point for the Disenchanting tab. The actual UI lives in Tabs/Disenchanting/:
--   Layout.lua          - shared sizing constants for both panes
--   ItemDisplay.lua      - item name/quality-color helpers
--   LiveSearchQueue.lua  - the single-search-at-a-time AH query queue both panes share
--   ListView.lua         - the sorted, paginated list on the left
--   BuyView.lua          - the per-item listings/purchase sub-pane on the right
-- This file just wires the two panes into one content frame and hooks the AH opening.
local Disenchanting = Arbitrage.Disenchanting

local TAB_ID = "Arbitrage-Disenchanting"

local function CreateContentFrame()
    local frame = CreateFrame("Frame", "ArbitrageDisenchantingTabFrame", AuctionHouseFrame)
    -- These 4 offsets are the whole content area, hand-tuned against this client's AH window
    -- (tabs sit at the BOTTOM here, not a top tab-strip, so there's no need for much top
    -- clearance beyond the title bar). Adjust these numbers directly if the fit is off.
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
