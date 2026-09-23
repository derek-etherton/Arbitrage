---@class Arbitrage
local Arbitrage = select(2, ...)

local TAB_ID = "Arbitrage-Disenchanting"
local ROW_HEIGHT = 20
local MAX_DISPLAYED_ROWS = 200 -- sane cap; a full scan filtered to disenchantable items shouldn't exceed this by much

---@type table[] pooled row frames, reused and rebound as the list updates
local rowPool = {}
local scrollChild
local emptyMessage

-- Browse-scan results (see ScanData.lua) have no itemLink, only an itemId; fall back to
-- C_Item.GetItemInfo, which accepts a bare itemId and works even without a link.
local function GetItemDisplayName(itemId, itemLink)
    if itemLink then
        local name = itemLink:match("%[(.-)%]")
        if name then
            return name
        end
    end
    return C_Item.GetItemInfo(itemId) or ("Item #" .. itemId)
end

-- Mirrors Auctionator's own Shopping-list click behavior: switch to Blizzard's native Buy tab
-- and run a live, exact-item search so the actual current listings for this item are shown.
local function ShowUnderlyingAuction(entry)
    if AuctionHouseFrame.Tabs and AuctionHouseFrame.Tabs[1] then
        AuctionHouseFrame.Tabs[1]:Click()
    end

    local itemKey = C_AuctionHouse.MakeItemKey(entry.itemId)
    local sorts = {{sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false}}
    if Auctionator.AH and Auctionator.AH.SendSearchQueryByItemKey then
        Auctionator.AH.SendSearchQueryByItemKey(itemKey, sorts, true)
    else
        C_AuctionHouse.SendSearchQuery(itemKey, sorts, true)
    end
end

local function ShowRowTooltip(row)
    local entry = row.entry
    if not entry then
        return
    end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if entry.itemLink then
        GameTooltip:SetHyperlink(entry.itemLink)
    else
        GameTooltip:SetItemByID(entry.itemId)
    end
    GameTooltip:Show()
end

local function UpdateRowValueText(row, entry)
    row.buyout:SetText(Arbitrage.FormatCoin(entry.buyout, 12))
    row.profit:SetText((entry.profit >= 0 and "|cff1eff00" or "|cffff0000") .. Arbitrage.FormatCoin(entry.profit, 12) .. "|r")
end

-- The list's sort order and membership come from the last Auctionator scan, which can go stale
-- (listings sell, get cancelled, etc.). Rather than re-scan or re-sort, we correct just the
-- hovered row's numbers to the item's actual current cheapest listing - the AH only supports one
-- active browse search at a time, so only one of these is ever in flight.
local pendingRow, pendingEntry, pendingItemKey

local function RequestLiveBuyout(row)
    local entry = row.entry
    if not entry then
        return
    end

    pendingRow, pendingEntry = row, entry
    pendingItemKey = C_AuctionHouse.MakeItemKey(entry.itemId)
    local sorts = {{sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false}}
    if Auctionator.AH and Auctionator.AH.SendSearchQueryByItemKey then
        Auctionator.AH.SendSearchQueryByItemKey(pendingItemKey, sorts, true)
    else
        C_AuctionHouse.SendSearchQuery(pendingItemKey, sorts, true)
    end
end

local liveQueryFrame = CreateFrame("Frame")
liveQueryFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
liveQueryFrame:SetScript("OnEvent", function()
    if not pendingItemKey or not C_AuctionHouse.HasFullBrowseResults() then
        return
    end

    local row, entry = pendingRow, pendingEntry
    pendingRow, pendingEntry, pendingItemKey = nil, nil, nil

    if row.entry ~= entry then
        -- Row was rebound to a different item (list refreshed) while the query was in flight.
        return
    end

    local results = C_AuctionHouse.GetBrowseResults()
    if not results or not results[1] or not results[1].minPrice then
        -- Nothing currently listed; keep showing the last-known (stale) scan value.
        return
    end

    entry.buyout = results[1].minPrice
    entry.profit = entry.disenchantValue - entry.buyout
    UpdateRowValueText(row, entry)
end)

local function GetOrCreateRow(index)
    local row = rowPool[index]
    if row then
        return row
    end

    row = CreateFrame("Button", nil, scrollChild)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("LEFT", scrollChild, "LEFT", 0, 0)
    row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
    row:SetPoint("TOP", scrollChild, "TOP", 0, -(index - 1) * ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:SetScript("OnEnter", function(self)
        ShowRowTooltip(self)
        RequestLiveBuyout(self)
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(self)
        ShowUnderlyingAuction(self.entry)
    end)

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
    row.entry = entry
    row.icon:SetTexture(C_Item.GetItemIconByID(entry.itemId))
    row.itemName:SetText(GetItemDisplayName(entry.itemId, entry.itemLink))
    row.disenchantValue:SetText(Arbitrage.FormatCoin(entry.disenchantValue, 12))
    UpdateRowValueText(row, entry)
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
    emptyMessage:SetText("Run a scan in Auctionator to populate this list.")

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
