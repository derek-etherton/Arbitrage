---@class Arbitrage
local Arbitrage = select(2, ...)

local AH = Arbitrage.AH
local ROW_HEIGHT = AH.ROW_HEIGHT
local ITEM_NAME_WIDTH = AH.ITEM_NAME_WIDTH
local VALUE_COL_WIDTH = AH.VALUE_COL_WIDTH
local PERCENT_COL_WIDTH = AH.PERCENT_COL_WIDTH
local COLUMN_GAP = AH.COLUMN_GAP
local LIST_CONTENT_WIDTH = AH.LIST_CONTENT_WIDTH
local LIST_PANE_WIDTH = AH.LIST_PANE_WIDTH

---@param config table {profitListKey: string, valueLabel: string, emptyText: string, onRowClick: fun(entry: table)}
---@return table pane with .Create(frame) and .frame (set once Create runs)
function AH.NewListPane(config)
    local pane = {}

    local currentPage = 1
    local rowPool = {}
    local scrollChild, scrollFrame, emptyMessage, pageLabel, prevPageButton, nextPageButton, reloadButton
    local headerProfit, headerPercent
    local bulkRefreshInProgress = false
    local sortKey = "profit" -- "profit" | "percent"
    local RefreshRows
    -- Set once Create() has anchored scrollFrame, from its actual measured height - fills
    -- whatever vertical space the AH window gives us instead of guessing a fixed row count.
    local pageSize = AH.PAGE_SIZE

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
        -- FormatCoin (GetCoinTextureString) errors on a negative amount, so a loss needs its
        -- own "-" prefix with the absolute value passed through instead.
        local isLoss = entry.profit < 0
        local color = isLoss and "|cffff0000" or "|cff1eff00"
        local profitText = (isLoss and "-" or "") .. Arbitrage.FormatCoin(math.abs(entry.profit), 12)
        row.profit:SetText(color .. profitText .. "|r")

        local percent = entry.buyout > 0 and (entry.profit / entry.buyout * 100) or 0
        row.profitPercent:SetText(color .. string.format("%.0f%%", percent) .. "|r")
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

        AH.RequestLiveSearch(entry, function(itemKey)
            if row.entry == entry then
                local listings = AH.CollectBuyoutListings(itemKey)
                entry.confirmedGone = listings[1] == nil
                if listings[1] then
                    entry.buyout = listings[1].buyout
                    entry.profit = entry.value - entry.buyout
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
                config.onRowClick(self.entry)
            end
        end)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
        row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)

        row.itemName = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.itemName:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.itemName:SetWidth(ITEM_NAME_WIDTH)
        row.itemName:SetJustifyH("LEFT")
        row.itemName:SetJustifyV("MIDDLE")

        row.buyout = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.buyout:SetPoint("LEFT", row.itemName, "RIGHT", COLUMN_GAP, 0)
        row.buyout:SetWidth(VALUE_COL_WIDTH)
        row.buyout:SetJustifyH("LEFT")
        row.buyout:SetJustifyV("MIDDLE")

        row.value = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.value:SetPoint("LEFT", row.buyout, "RIGHT", COLUMN_GAP, 0)
        row.value:SetWidth(VALUE_COL_WIDTH)
        row.value:SetJustifyH("LEFT")
        row.value:SetJustifyV("MIDDLE")

        row.profit = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.profit:SetPoint("LEFT", row.value, "RIGHT", COLUMN_GAP, 0)
        row.profit:SetWidth(VALUE_COL_WIDTH)
        row.profit:SetJustifyH("LEFT")
        row.profit:SetJustifyV("MIDDLE")

        row.profitPercent = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.profitPercent:SetPoint("LEFT", row.profit, "RIGHT", COLUMN_GAP, 0)
        row.profitPercent:SetWidth(PERCENT_COL_WIDTH)
        row.profitPercent:SetJustifyH("LEFT")
        row.profitPercent:SetJustifyV("MIDDLE")

        rowPool[index] = row
        return row
    end

    local function SetRowData(row, entry)
        row.entry = entry
        row.icon:SetTexture(C_Item.GetItemIconByID(entry.itemId))
        row.itemName:SetText(AH.GetItemQualityColorCode(entry.itemId) .. AH.GetItemDisplayName(entry) .. "|r")
        row.value:SetText(Arbitrage.FormatCoin(entry.value, 12))
        UpdateRowValueText(row, entry)
        row:Show()
    end

    local function PercentDescComparator(a, b)
        local ratioA = a.buyout > 0 and (a.profit / a.buyout) or 0
        local ratioB = b.buyout > 0 and (b.profit / b.buyout) or 0
        if ratioA ~= ratioB then
            return ratioA > ratioB
        end
        return a.sortingIndex < b.sortingIndex
    end

    -- Arbitrage.ProfitLists[key] is already sorted by profit descending (BuildProfitList), so
    -- only the "%" sort needs its own copy; entries themselves are shared, not duplicated.
    local function GetSortedProfitList()
        local source = Arbitrage.ProfitLists[config.profitListKey] or {}
        if sortKey ~= "percent" then
            return source
        end

        local sorted = {}
        for i = 1, #source do
            sorted[i] = source[i]
        end
        table.sort(sorted, PercentDescComparator)
        return sorted
    end

    -- Color the active sort column gold instead of using an arrow glyph, since WoW's default
    -- fonts don't reliably render arrow/caret unicode characters across all locales.
    local function UpdateSortHeaders()
        headerProfit:SetText(sortKey == "profit" and "|cffffd200Profit|r" or "Profit")
        headerPercent:SetText(sortKey == "percent" and "|cffffd200%|r" or "%")
    end

    local function SetSortKey(key)
        if sortKey == key then
            return
        end
        sortKey = key
        currentPage = 1
        UpdateSortHeaders()
        RefreshRows()
    end

    RefreshRows = function()
        local profitList = GetSortedProfitList()
        local totalItems = #profitList
        local totalPages = math.max(1, math.ceil(totalItems / pageSize))
        currentPage = math.min(math.max(currentPage, 1), totalPages)

        local startIndex = (currentPage - 1) * pageSize
        local displayCount = math.min(pageSize, totalItems - startIndex)

        for i = 1, displayCount do
            SetRowData(GetOrCreateRow(i), profitList[startIndex + i])
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

    Arbitrage.ProfitListRefreshers[config.profitListKey] = RefreshRows

    function pane.Create(frame)
        local listView = CreateFrame("Frame", nil, frame)
        listView:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        listView:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        listView:SetWidth(LIST_PANE_WIDTH)
        pane.frame = listView

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

        local headerValue = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        headerValue:SetPoint("LEFT", headerBuyout, "RIGHT", COLUMN_GAP, 0)
        headerValue:SetWidth(VALUE_COL_WIDTH)
        headerValue:SetJustifyH("LEFT")
        headerValue:SetText(config.valueLabel)

        local headerProfitButton = CreateFrame("Button", nil, header)
        headerProfitButton:SetPoint("LEFT", headerValue, "RIGHT", COLUMN_GAP, 0)
        headerProfitButton:SetSize(VALUE_COL_WIDTH, ROW_HEIGHT)
        headerProfitButton:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        headerProfitButton:SetScript("OnClick", function() SetSortKey("profit") end)

        headerProfit = headerProfitButton:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        headerProfit:SetAllPoints(headerProfitButton)
        headerProfit:SetJustifyH("LEFT")
        headerProfit:SetJustifyV("MIDDLE")

        local headerPercentButton = CreateFrame("Button", nil, header)
        headerPercentButton:SetPoint("LEFT", headerProfitButton, "RIGHT", COLUMN_GAP, 0)
        headerPercentButton:SetSize(PERCENT_COL_WIDTH, ROW_HEIGHT)
        headerPercentButton:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        headerPercentButton:SetScript("OnClick", function() SetSortKey("percent") end)

        headerPercent = headerPercentButton:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        headerPercent:SetAllPoints(headerPercentButton)
        headerPercent:SetJustifyH("LEFT")
        headerPercent:SetJustifyV("MIDDLE")

        UpdateSortHeaders()

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

        scrollFrame = CreateFrame("ScrollFrame", nil, listView, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
        scrollFrame:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -26, 4)

        scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetWidth(LIST_CONTENT_WIDTH)
        scrollChild:SetHeight(1)
        scrollFrame:SetScrollChild(scrollChild)

        emptyMessage = listView:CreateFontString(nil, "ARTWORK", "GameFontDisableLarge")
        emptyMessage:SetPoint("CENTER", scrollFrame, "CENTER", 0, 0)
        emptyMessage:SetText(config.emptyText)

        local availableHeight = scrollFrame:GetHeight()
        if availableHeight and availableHeight > 0 then
            pageSize = math.max(1, math.floor(availableHeight / ROW_HEIGHT))
        end

        RefreshRows()
    end

    return pane
end
