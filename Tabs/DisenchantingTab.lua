---@class Arbitrage
local Arbitrage = select(2, ...)

local TAB_ID = "Arbitrage-Disenchanting"
local ROW_HEIGHT = 20
local MAX_DISPLAYED_ROWS = 200 -- sane cap; a full scan filtered to disenchantable items shouldn't exceed this by much

-- The list pane sits fixed-width on the left so the buy sub-view can open beside it (rather than
-- over it) on the right; its columns are narrower than a full-width list to make room.
local ITEM_NAME_WIDTH = 140
local VALUE_COL_WIDTH = 90
local COLUMN_GAP = 6
-- icon pad(2) + icon(ROW_HEIGHT-4) + gap(4) + name + gap + buyout + gap + DE value + gap + profit.
-- scrollChild needs an explicit width matching this, or rows anchored LEFT+RIGHT to it collapse
-- to ~0px wide and silently stop receiving mouse events (OnEnter/OnClick), even though their
-- text/icon still render fine (children draw at their own offsets regardless of parent size).
local LIST_CONTENT_WIDTH = 2 + (ROW_HEIGHT - 4) + 4 + ITEM_NAME_WIDTH + COLUMN_GAP
    + VALUE_COL_WIDTH + COLUMN_GAP + VALUE_COL_WIDTH + COLUMN_GAP + VALUE_COL_WIDTH
local LIST_PANE_WIDTH = LIST_CONTENT_WIDTH + 34 -- + scrollbar width and a little breathing room
local PANE_GAP = 10 -- gap between the list pane and the buy sub-view

local BUY_CONTENT_WIDTH = 150 + 8 + 100 + 8 + 80 -- buyout + gap + quantity + gap + Buy button

---@type table[] pooled row frames, reused and rebound as the list updates
local rowPool = {}
local scrollChild
local emptyMessage
local listView

---@type table[] pooled rows for the per-item listings shown in the buy sub-view
local buyRowPool = {}
local buyScrollChild
local buyEmptyMessage
local buyView
local buyViewIcon
local buyViewName
local currentBuyEntry

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

-- C_AuctionHouse.GetBrowseResults()'s minPrice is an aggregate "cheapest price" that can reflect
-- a bid-only auction's current bid when nothing has a buyout - not safe to treat as a buyout. The
-- per-listing item search results (below) separate buyoutAmount from bidAmount explicitly, and
-- also let us exclude the player's own listings (can't buy your own auction).
local function CollectBuyoutListings(itemKey)
    local listings = {}
    for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
        local resultInfo = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        if resultInfo and resultInfo.buyoutAmount and resultInfo.buyoutAmount > 0
            and not resultInfo.containsOwnerItem and not resultInfo.containsAccountItem then
            table.insert(listings, {
                auctionID = resultInfo.auctionID,
                buyout = resultInfo.buyoutAmount,
                quantity = resultInfo.quantity or 1,
            })
        end
    end
    table.sort(listings, function(a, b) return a.buyout < b.buyout end)
    return listings
end

-- The AH only supports one active item search at a time, so both the hover-triggered price
-- refresh and the buy sub-view share this single in-flight request; a newer request simply
-- supersedes whatever was previously pending.
local pendingItemKey, pendingOnReady

local function RequestLiveSearch(itemId, onReady)
    local itemKey = C_AuctionHouse.MakeItemKey(itemId)
    pendingItemKey, pendingOnReady = itemKey, onReady
    local sorts = {{sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false}}
    if Auctionator.AH and Auctionator.AH.SendSearchQueryByItemKey then
        Auctionator.AH.SendSearchQueryByItemKey(itemKey, sorts, true)
    else
        C_AuctionHouse.SendSearchQuery(itemKey, sorts, true)
    end
end

local function RequestLiveBuyout(row)
    local entry = row.entry
    if not entry then
        return
    end

    RequestLiveSearch(entry.itemId, function(itemKey)
        if row.entry ~= entry then
            -- Row was rebound to a different item (list refreshed) while the query was in flight.
            return
        end

        local listings = CollectBuyoutListings(itemKey)
        -- No buyout listing found - either sold out or everything left is bid-only/owned by us;
        -- either way it's not something we can point at a fixed buyout price for right now.
        entry.confirmedGone = listings[1] == nil
        if listings[1] then
            entry.buyout = listings[1].buyout
            entry.profit = entry.disenchantValue - entry.buyout
        end
        ApplyRowAppearance(row, entry)
    end)
end

local function GetOrCreateBuyRow(index)
    local row = buyRowPool[index]
    if row then
        return row
    end

    row = CreateFrame("Frame", nil, buyScrollChild)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("LEFT", buyScrollChild, "LEFT", 0, 0)
    row:SetPoint("RIGHT", buyScrollChild, "RIGHT", 0, 0)
    row:SetPoint("TOP", buyScrollChild, "TOP", 0, -(index - 1) * ROW_HEIGHT)

    row.buyout = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.buyout:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.buyout:SetWidth(150)
    row.buyout:SetJustifyH("LEFT")

    row.quantity = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.quantity:SetPoint("LEFT", row.buyout, "RIGHT", 8, 0)
    row.quantity:SetWidth(100)
    row.quantity:SetJustifyH("LEFT")

    row.buyButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.buyButton:SetSize(80, ROW_HEIGHT - 2)
    row.buyButton:SetPoint("LEFT", row.quantity, "RIGHT", 8, 0)
    row.buyButton:SetText("Buy")
    row.buyButton:SetScript("OnClick", function(self)
        local listing = self:GetParent().listing
        if not listing then
            return
        end
        StaticPopup_Show("ARBITRAGE_CONFIRM_BUYOUT", Arbitrage.FormatCoin(listing.buyout, 12), nil, listing)
    end)

    buyRowPool[index] = row
    return row
end

local function RenderBuyListings(listings)
    for i = 1, #listings do
        local listing = listings[i]
        local row = GetOrCreateBuyRow(i)
        row.listing = listing
        row.buyout:SetText(Arbitrage.FormatCoin(listing.buyout, 12))
        row.quantity:SetText(tostring(listing.quantity))
        row:Show()
    end

    for i = #listings + 1, #buyRowPool do
        buyRowPool[i]:Hide()
    end

    buyScrollChild:SetHeight(math.max(#listings * ROW_HEIGHT, 1))
    buyEmptyMessage:SetShown(#listings == 0)
end

local function RefreshBuyView()
    if not currentBuyEntry then
        return
    end

    local entry = currentBuyEntry
    RequestLiveSearch(entry.itemId, function(itemKey)
        if currentBuyEntry ~= entry then
            -- User navigated back (or to a different item) before results arrived.
            return
        end
        local listings = CollectBuyoutListings(itemKey)
        if #listings == 0 then
            buyEmptyMessage:SetText("No active listings for this item right now.")
        end
        RenderBuyListings(listings)
    end)
end

local function ShowBuyView(entry)
    currentBuyEntry = entry
    buyViewIcon:SetTexture(C_Item.GetItemIconByID(entry.itemId))
    buyViewName:SetText(GetItemDisplayName(entry.itemId, entry.itemLink))
    buyEmptyMessage:SetText("Loading current listings...")
    RenderBuyListings({})

    buyView:Show()

    RefreshBuyView()
end

local function HideBuyView()
    currentBuyEntry = nil
    buyView:Hide()
end

local liveQueryFrame = CreateFrame("Frame")
liveQueryFrame:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
liveQueryFrame:RegisterEvent("AUCTION_HOUSE_NEW_BID_RECEIVED")
liveQueryFrame:SetScript("OnEvent", function(_, eventName, itemKey)
    if eventName == "AUCTION_HOUSE_NEW_BID_RECEIVED" then
        -- A purchase (ours or otherwise) landed; if the buy sub-view is open, refresh its listings.
        RefreshBuyView()
        return
    end

    if not pendingItemKey or not itemKey or itemKey.itemID ~= pendingItemKey.itemID
        or not C_AuctionHouse.HasFullItemSearchResults(itemKey) then
        return
    end

    local onReady = pendingOnReady
    pendingItemKey, pendingOnReady = nil, nil
    onReady(itemKey)
end)

StaticPopupDialogs["ARBITRAGE_CONFIRM_BUYOUT"] = {
    text = "Buy this item for %s?",
    button1 = "Buy",
    button2 = "Cancel",
    OnAccept = function(_, data)
        C_AuctionHouse.PlaceBid(data.auctionID, data.buyout)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

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
        if self.entry then
            ShowBuyView(self.entry)
        end
    end)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)

    row.itemName = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.itemName:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.itemName:SetWidth(ITEM_NAME_WIDTH)
    row.itemName:SetJustifyH("LEFT")

    row.buyout = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.buyout:SetPoint("LEFT", row.itemName, "RIGHT", COLUMN_GAP, 0)
    row.buyout:SetWidth(VALUE_COL_WIDTH)
    row.buyout:SetJustifyH("LEFT")

    row.disenchantValue = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.disenchantValue:SetPoint("LEFT", row.buyout, "RIGHT", COLUMN_GAP, 0)
    row.disenchantValue:SetWidth(VALUE_COL_WIDTH)
    row.disenchantValue:SetJustifyH("LEFT")

    row.profit = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.profit:SetPoint("LEFT", row.disenchantValue, "RIGHT", COLUMN_GAP, 0)
    row.profit:SetWidth(VALUE_COL_WIDTH)
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

local function CreateListView(frame)
    listView = CreateFrame("Frame", nil, frame)
    listView:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    listView:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    listView:SetWidth(LIST_PANE_WIDTH)

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

    local scrollFrame = CreateFrame("ScrollFrame", "ArbitrageDisenchantingScrollFrame", listView, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", listView, "BOTTOMRIGHT", -26, 4)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(LIST_CONTENT_WIDTH)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    emptyMessage = listView:CreateFontString(nil, "ARTWORK", "GameFontDisableLarge")
    emptyMessage:SetPoint("CENTER", listView, "CENTER", 0, 0)
    emptyMessage:SetText("Run a scan in Auctionator to populate this list.")

    RefreshRows()
end

local function CreateBuyView(frame)
    buyView = CreateFrame("Frame", nil, frame)
    buyView:SetPoint("TOPLEFT", listView, "TOPRIGHT", PANE_GAP, 0)
    buyView:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    buyView:Hide()

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.15)
    divider:SetWidth(1)
    divider:SetPoint("TOP", listView, "TOPRIGHT", math.floor(PANE_GAP / 2), 0)
    divider:SetPoint("BOTTOM", listView, "BOTTOMRIGHT", math.floor(PANE_GAP / 2), 0)

    local closeButton = CreateFrame("Button", nil, buyView, "UIPanelButtonTemplate")
    closeButton:SetSize(60, ROW_HEIGHT + 2)
    closeButton:SetPoint("TOPRIGHT", buyView, "TOPRIGHT", -4, -4)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", HideBuyView)

    buyViewIcon = buyView:CreateTexture(nil, "ARTWORK")
    buyViewIcon:SetSize(ROW_HEIGHT, ROW_HEIGHT)
    buyViewIcon:SetPoint("TOPLEFT", buyView, "TOPLEFT", 4, -4)

    buyViewName = buyView:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    buyViewName:SetPoint("LEFT", buyViewIcon, "RIGHT", 6, 0)
    buyViewName:SetJustifyH("LEFT")

    local header = CreateFrame("Frame", nil, buyView)
    header:SetPoint("TOPLEFT", buyViewIcon, "BOTTOMLEFT", 0, -8)
    header:SetPoint("TOPRIGHT", buyView, "TOPRIGHT", -4, 0)
    header:SetHeight(ROW_HEIGHT)

    local headerBuyout = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    headerBuyout:SetPoint("LEFT", header, "LEFT", 4, 0)
    headerBuyout:SetWidth(150)
    headerBuyout:SetJustifyH("LEFT")
    headerBuyout:SetText("Buyout")

    local headerQuantity = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    headerQuantity:SetPoint("LEFT", headerBuyout, "RIGHT", 8, 0)
    headerQuantity:SetWidth(100)
    headerQuantity:SetJustifyH("LEFT")
    headerQuantity:SetText("Quantity")

    local scrollFrame = CreateFrame("ScrollFrame", "ArbitrageBuyItemScrollFrame", buyView, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", buyView, "BOTTOMRIGHT", -26, 4)

    buyScrollChild = CreateFrame("Frame", nil, scrollFrame)
    buyScrollChild:SetWidth(BUY_CONTENT_WIDTH)
    buyScrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(buyScrollChild)

    buyEmptyMessage = buyView:CreateFontString(nil, "ARTWORK", "GameFontDisableLarge")
    buyEmptyMessage:SetPoint("CENTER", buyView, "CENTER", 0, 0)
    buyEmptyMessage:SetText("No active listings for this item right now.")
end

local function CreateContentFrame()
    local frame = CreateFrame("Frame", "ArbitrageDisenchantingTabFrame", AuctionHouseFrame)
    -- Same anchor offsets Auctionator's own AuctionatorTabFrameTemplate uses
    -- (Source\Tabs\Frames\TabFrame.xml), without inheriting that private template.
    frame:SetPoint("LEFT", AuctionHouseFrame, "LEFT", 4, 0)
    frame:SetPoint("RIGHT", AuctionHouseFrame, "RIGHT", -4, 0)
    frame:SetPoint("BOTTOM", AuctionHouseFrame, "BOTTOM", 0, 27)
    frame:SetPoint("TOP", AuctionHouseFrame, "TOP", 0, -103)

    CreateListView(frame)
    CreateBuyView(frame)

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
