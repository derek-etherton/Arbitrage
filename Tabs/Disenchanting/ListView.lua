---@class Arbitrage
local Arbitrage = select(2, ...)

local Disenchanting = Arbitrage.Disenchanting
local ROW_HEIGHT = Disenchanting.ROW_HEIGHT
local ITEM_NAME_WIDTH = Disenchanting.ITEM_NAME_WIDTH
local VALUE_COL_WIDTH = Disenchanting.VALUE_COL_WIDTH
local COLUMN_GAP = Disenchanting.COLUMN_GAP
local LIST_CONTENT_WIDTH = Disenchanting.LIST_CONTENT_WIDTH
local LIST_PANE_WIDTH = Disenchanting.LIST_PANE_WIDTH
local PAGE_SIZE = Disenchanting.PAGE_SIZE

local currentPage = 1

---@type table[] pooled row frames, reused and rebound as the list updates
local rowPool = {}
local scrollChild
local emptyMessage
local listView
local pageLabel
local prevPageButton
local nextPageButton
local reloadButton

local bulkRefreshInProgress = false

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

local function ApplyRowAppearance(row, entry)
    UpdateRowValueText(row, entry)
    row:SetAlpha(entry.confirmedGone and 0.4 or 1)
end

---@param onDone function|nil called once, whether the refresh succeeded, was skipped, or timed out
local function RequestLiveBuyout(row, onDone)
    local entry = row.entry
    if not entry then
        if onDone then onDone() end
        return
    end

    local function Finish()
        if onDone then onDone() end
    end

    Disenchanting.RequestLiveSearch(entry, function(itemKey)
        if row.entry == entry then
            local listings = Disenchanting.CollectBuyoutListings(itemKey)
            entry.confirmedGone = listings[1] == nil
            if listings[1] then
                entry.buyout = listings[1].buyout
                entry.profit = entry.disenchantValue - entry.buyout
            end
            ApplyRowAppearance(row, entry)
        end
        Finish()
    end, Finish)
end

local function RefreshDisplayedBuyouts()
    if bulkRefreshInProgress then
        return
    end

    local rows = {}
    for i = 1, #rowPool do
        if rowPool[i]:IsShown() and rowPool[i].entry then
            table.insert(rows, rowPool[i])
        end
    end
    if #rows == 0 then
        return
    end

    bulkRefreshInProgress = true
    reloadButton:SetText("Reloading...")
    reloadButton:Disable()

    local index = 0
    local function Next()
        index = index + 1
        local row = rows[index]
        if row then
            RequestLiveBuyout(row, Next)
        else
            bulkRefreshInProgress = false
            reloadButton:SetText("Reload")
            reloadButton:Enable()
        end
    end
    Next()
end

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
        if not bulkRefreshInProgress then
            RequestLiveBuyout(self)
        end
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(self)
        if self.entry then
            Disenchanting.ShowBuyView(self.entry)
        end
    end)

    -- Top-anchored (not vertically centered) so a wrapped 2-line item name doesn't push its
    -- first line above the icon and overlap the row below.
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
    row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 2, 0)

    row.itemName = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.itemName:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 4, 0)
    row.itemName:SetWidth(ITEM_NAME_WIDTH)
    row.itemName:SetJustifyH("LEFT")
    row.itemName:SetJustifyV("TOP")

    row.buyout = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.buyout:SetPoint("TOPLEFT", row.itemName, "TOPRIGHT", COLUMN_GAP, 0)
    row.buyout:SetWidth(VALUE_COL_WIDTH)
    row.buyout:SetJustifyH("LEFT")
    row.buyout:SetJustifyV("TOP")

    row.disenchantValue = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.disenchantValue:SetPoint("TOPLEFT", row.buyout, "TOPRIGHT", COLUMN_GAP, 0)
    row.disenchantValue:SetWidth(VALUE_COL_WIDTH)
    row.disenchantValue:SetJustifyH("LEFT")
    row.disenchantValue:SetJustifyV("TOP")

    row.profit = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.profit:SetPoint("TOPLEFT", row.disenchantValue, "TOPRIGHT", COLUMN_GAP, 0)
    row.profit:SetWidth(VALUE_COL_WIDTH)
    row.profit:SetJustifyH("LEFT")
    row.profit:SetJustifyV("TOP")

    rowPool[index] = row
    return row
end

local function SetRowData(row, entry)
    row.entry = entry
    row.icon:SetTexture(C_Item.GetItemIconByID(entry.itemId))
    row.itemName:SetText(Disenchanting.GetItemQualityColorCode(entry.itemId) .. Disenchanting.GetItemDisplayName(entry) .. "|r")
    row.disenchantValue:SetText(Arbitrage.FormatCoin(entry.disenchantValue, 12))
    UpdateRowValueText(row, entry)
    row:Show()
end

local function RefreshRows()
    local profitList = Arbitrage.ProfitList or {}
    local totalItems = #profitList
    local totalPages = math.max(1, math.ceil(totalItems / PAGE_SIZE))
    currentPage = math.min(math.max(currentPage, 1), totalPages)

    local startIndex = (currentPage - 1) * PAGE_SIZE
    local displayCount = math.min(PAGE_SIZE, totalItems - startIndex)

    for i = 1, displayCount do
        local row = GetOrCreateRow(i)
        SetRowData(row, profitList[startIndex + i])
    end

    for i = displayCount + 1, #rowPool do
        rowPool[i]:Hide()
    end

    scrollChild:SetHeight(math.max(displayCount * ROW_HEIGHT, 1))
    emptyMessage:SetShown(totalItems == 0)

    pageLabel:SetText(string.format("Page %d / %d (%d items)", currentPage, totalPages, totalItems))
    if currentPage > 1 then prevPageButton:Enable() else prevPageButton:Disable() end
    if currentPage < totalPages then nextPageButton:Enable() else nextPageButton:Disable() end
end

Arbitrage.OnProfitListUpdated = RefreshRows

function Disenchanting.CreateListView(frame)
    listView = CreateFrame("Frame", nil, frame)
    listView:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    listView:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    listView:SetWidth(LIST_PANE_WIDTH)
    Disenchanting.ListView = listView

    local header = CreateFrame("Frame", nil, listView)
    header:SetPoint("TOPLEFT", listView, "TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", listView, "TOPRIGHT", -4, -4)
    header:SetHeight(ROW_HEIGHT)

    local headerItem = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    headerItem:SetPoint("LEFT", header, "LEFT", 22, 0)
    headerItem:SetWidth(ITEM_NAME_WIDTH)
    headerItem:SetJustifyH("LEFT")
    headerItem:SetText("Item")

    local headerBuyout = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    headerBuyout:SetPoint("LEFT", headerItem, "RIGHT", COLUMN_GAP, 0)
    headerBuyout:SetWidth(VALUE_COL_WIDTH)
    headerBuyout:SetJustifyH("LEFT")
    headerBuyout:SetText("Buyout")

    local headerDisenchantValue = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    headerDisenchantValue:SetPoint("LEFT", headerBuyout, "RIGHT", COLUMN_GAP, 0)
    headerDisenchantValue:SetWidth(VALUE_COL_WIDTH)
    headerDisenchantValue:SetJustifyH("LEFT")
    headerDisenchantValue:SetText("DE Value")

    local headerProfit = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    headerProfit:SetPoint("LEFT", headerDisenchantValue, "RIGHT", COLUMN_GAP, 0)
    headerProfit:SetWidth(VALUE_COL_WIDTH)
    headerProfit:SetJustifyH("LEFT")
    headerProfit:SetText("Profit")

    local footer = CreateFrame("Frame", nil, listView)
    footer:SetPoint("BOTTOMLEFT", listView, "BOTTOMLEFT", 4, 4)
    footer:SetPoint("BOTTOMRIGHT", listView, "BOTTOMRIGHT", -4, 4)
    footer:SetHeight(ROW_HEIGHT + 4)

    reloadButton = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    reloadButton:SetSize(56, ROW_HEIGHT + 2)
    reloadButton:SetPoint("LEFT", footer, "LEFT", 0, 0)
    reloadButton:SetText("Reload")
    reloadButton:SetScript("OnClick", RefreshDisplayedBuyouts)

    prevPageButton = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    prevPageButton:SetSize(50, ROW_HEIGHT + 2)
    prevPageButton:SetPoint("LEFT", reloadButton, "RIGHT", 4, 0)
    prevPageButton:SetText("< Prev")
    prevPageButton:SetScript("OnClick", function()
        currentPage = currentPage - 1
        RefreshRows()
    end)

    nextPageButton = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    nextPageButton:SetSize(60, ROW_HEIGHT + 2)
    nextPageButton:SetPoint("RIGHT", footer, "RIGHT", 0, 0)
    nextPageButton:SetText("Next >")
    nextPageButton:SetScript("OnClick", function()
        currentPage = currentPage + 1
        RefreshRows()
    end)

    pageLabel = footer:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    pageLabel:SetPoint("LEFT", prevPageButton, "RIGHT", 4, 0)
    pageLabel:SetPoint("RIGHT", nextPageButton, "LEFT", -4, 0)
    pageLabel:SetJustifyH("CENTER")

    local scrollFrame = CreateFrame("ScrollFrame", "ArbitrageDisenchantingScrollFrame", listView, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -26, 4)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(LIST_CONTENT_WIDTH)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    emptyMessage = listView:CreateFontString(nil, "ARTWORK", "GameFontDisableLarge")
    emptyMessage:SetPoint("CENTER", scrollFrame, "CENTER", 0, 0)
    emptyMessage:SetText("Run a scan in Auctionator to populate this list.")

    RefreshRows()
end
