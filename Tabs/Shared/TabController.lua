---@class Arbitrage
local Arbitrage = select(2, ...)

local AH = Arbitrage.AH

---@param config table {tabId: string, title: string, settingsKey: string, createContentFrame: fun(): Frame}
function AH.RegisterTab(config)
    local function ApplyVisibility()
        local LibAHTab = LibStub("LibAHTab-1-0")
        if LibAHTab:DoesIDExist(config.tabId) then
            LibAHTab:GetButton(config.tabId):SetShown(Arbitrage.Settings[config.settingsKey])
        end
    end
    Arbitrage.RegisterTabVisibility(config.settingsKey, ApplyVisibility)

    local function EnsureTab()
        local LibAHTab = LibStub("LibAHTab-1-0")
        if not LibAHTab:DoesIDExist(config.tabId) then
            LibAHTab:CreateTab(config.tabId, config.createContentFrame(), config.title)
        end
        ApplyVisibility()
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
end
