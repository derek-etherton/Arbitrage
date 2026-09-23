---@class Arbitrage
local Arbitrage = select(2, ...)

local TAB_ID = "Arbitrage-Disenchanting"
local ROW_HEIGHT = 20
local MAX_DISPLAYED_ROWS = 200 -- sane cap; a full scan filtered to disenchantable items shouldn't exceed this by much

---@type table[] pooled row frames, reused and rebound as the list updates
local rowPool = {}
local scrollChild
local emptyMessage

local function GetItemDisplayName(itemLink)
    local name = itemLink:match("%[(.-)%]")
    return name or itemLink
end

local function GetOrCreateRow(index)
    local row = rowPool[index]
    if row then
        return row
    end

    row = CreateFrame("Frame", nil, scrollChild)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("LEFT", scrollChild, "LEFT", 0, 0)
    row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
    row:SetPoint("TOP", scrollChild, "TOP", 0, -(index - 1) * ROW_HEIGHT)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)

    row.itemName = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.itemName:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.itemName:SetWidth(220)
    row.itemName:SetJustifyH("LEFT")

    row.buyout = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.buyout:SetPoint("LEFT", row.itemName, "RIGHT", 8, 0)
    row.buyout:SetWidth(130)
    row.buyout:SetJustifyH("LEFT")

    row.disenchantValue = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.disenchantValue:SetPoint("LEFT", row.buyout, "RIGHT", 8, 0)
    row.disenchantValue:SetWidth(130)
    row.disenchantValue:SetJustifyH("LEFT")

    row.profit = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.profit:SetPoint("LEFT", row.disenchantValue, "RIGHT", 8, 0)
    row.profit:SetWidth(130)
    row.profit:SetJustifyH("LEFT")

    rowPool[index] = row
    return row
end

local function SetRowData(row, entry)
    row.icon:SetTexture(C_Item.GetItemIconByID(entry.itemId))
    row.itemName:SetText(GetItemDisplayName(entry.itemLink))
    row.buyout:SetText(Arbitrage.FormatCoin(entry.buyout, 12))
    row.disenchantValue:SetText(Arbitrage.FormatCoin(entry.disenchantValue, 12))
    row.profit:SetText((entry.profit >= 0 and "|cff1eff00" or "|cffff0000") .. Arbitrage.FormatCoin(entry.profit, 12) .. "|r")
    row:Show()
end

local function RefreshRows()
    local profitList = Arbitrage.ProfitList or {}
    local displayCount = math.min(#profitList, MAX_DISPLAYED_ROWS)

    for i = 1, displayCount do
        local row = GetOrCreateRow(i)
        SetRowData(row, profitList[i])
    end

    for i = displayCount + 1, #rowPool do
        rowPool[i]:Hide()
    end

    scrollChild:SetHeight(math.max(displayCount * ROW_HEIGHT, 1))
    emptyMessage:SetShown(#profitList == 0)
end

Arbitrage.OnProfitListUpdated = RefreshRows

local function CreateContentFrame()
    local frame = CreateFrame("Frame", "ArbitrageDisenchantingTabFrame", AuctionHouseFrame)
    -- Same anchor offsets Auctionator's own AuctionatorTabFrameTemplate uses
    -- (Source\Tabs\Frames\TabFrame.xml), without inheriting that private template.
    frame:SetPoint("LEFT", AuctionHouseFrame, "LEFT", 4, 0)
    frame:SetPoint("RIGHT", AuctionHouseFrame, "RIGHT", -4, 0)
    frame:SetPoint("BOTTOM", AuctionHouseFrame, "BOTTOM", 0, 27)
    frame:SetPoint("TOP", AuctionHouseFrame, "TOP", 0, -103)

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    header:SetHeight(ROW_HEIGHT)

    local headerItem = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    headerItem:SetPoint("LEFT", header, "LEFT", 22, 0)
    headerItem:SetWidth(220)
    headerItem:SetJustifyH("LEFT")
    headerItem:SetText("Item")

    local headerBuyout = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    headerBuyout:SetPoint("LEFT", headerItem, "RIGHT", 8, 0)
    headerBuyout:SetWidth(130)
    headerBuyout:SetJustifyH("LEFT")
    headerBuyout:SetText("Buyout")

    local headerDisenchantValue = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    headerDisenchantValue:SetPoint("LEFT", headerBuyout, "RIGHT", 8, 0)
    headerDisenchantValue:SetWidth(130)
    headerDisenchantValue:SetJustifyH("LEFT")
    headerDisenchantValue:SetText("DE Value")

    local headerProfit = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    headerProfit:SetPoint("LEFT", headerDisenchantValue, "RIGHT", 8, 0)
    headerProfit:SetWidth(130)
    headerProfit:SetJustifyH("LEFT")
    headerProfit:SetText("Profit")

    local scrollFrame = CreateFrame("ScrollFrame", "ArbitrageDisenchantingScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 4)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(1)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    emptyMessage = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableLarge")
    emptyMessage:SetPoint("CENTER", frame, "CENTER", 0, 0)
    emptyMessage:SetText("Run a full \"Get All\" scan in Auctionator to populate this list.")

    RefreshRows()

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
