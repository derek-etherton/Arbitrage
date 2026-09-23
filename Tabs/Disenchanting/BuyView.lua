---@class Arbitrage
local Arbitrage = select(2, ...)

local Disenchanting = Arbitrage.Disenchanting
local ROW_HEIGHT = Disenchanting.ROW_HEIGHT
local PANE_GAP = Disenchanting.PANE_GAP
local BUY_CONTENT_WIDTH = Disenchanting.BUY_CONTENT_WIDTH
local BUY_LISTINGS_PAGE_SIZE = Disenchanting.BUY_LISTINGS_PAGE_SIZE

---@type table[] pooled rows for the per-item listings shown in the buy sub-view
local buyRowPool = {}
local buyScrollChild
local buyEmptyMessage
local buyMoreLabel
local buyView
local buyViewIcon
local buyViewName
local currentBuyEntry

local function ConfirmBuyListing(listing)
    if not listing then
        return
    end
    StaticPopup_Show("ARBITRAGE_CONFIRM_BUYOUT", Arbitrage.FormatCoin(listing.buyout, 12), nil, listing)
end

local function ApplyBuyRowAppearance(row)
    local purchased = row.listing and row.listing.purchased
    row:SetAlpha(purchased and 0.4 or 1)
    if purchased then
        row:Disable()
        row.buyButton:Disable()
    else
        row:Enable()
        row.buyButton:Enable()
    end
end

-- The AUCTION_HOUSE_NEW_BID_RECEIVED refresh (which drops sold-out listings entirely) can take a
-- moment to arrive from the server; grey the row out immediately on confirm so it's clear the
-- purchase went through and the row can't be bought again while that refresh is in flight.
local function MarkListingPurchased(listing)
    listing.purchased = true
    for i = 1, #buyRowPool do
        local row = buyRowPool[i]
        if row.listing == listing then
            ApplyBuyRowAppearance(row)
            break
        end
    end
end

local function GetOrCreateBuyRow(index)
    local row = buyRowPool[index]
    if row then
        return row
    end

    row = CreateFrame("Button", nil, buyScrollChild)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("LEFT", buyScrollChild, "LEFT", 0, 0)
    row:SetPoint("RIGHT", buyScrollChild, "RIGHT", 0, 0)
    row:SetPoint("TOP", buyScrollChild, "TOP", 0, -(index - 1) * ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:SetScript("OnClick", function(self)
        ConfirmBuyListing(self.listing)
    end)

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
        ConfirmBuyListing(self:GetParent().listing)
    end)

    buyRowPool[index] = row
    return row
end

---@param listings table[] already capped to at most BUY_LISTINGS_PAGE_SIZE entries
---@param totalCount number|nil how many real listings exist in total, before capping
local function RenderBuyListings(listings, totalCount)
    for i = 1, #listings do
        local listing = listings[i]
        local row = GetOrCreateBuyRow(i)
        row.listing = listing
        row.buyout:SetText(Arbitrage.FormatCoin(listing.buyout, 12))
        row.quantity:SetText(tostring(listing.quantity))
        ApplyBuyRowAppearance(row)
        row:Show()
    end

    for i = #listings + 1, #buyRowPool do
        buyRowPool[i]:Hide()
    end

    buyScrollChild:SetHeight(math.max(#listings * ROW_HEIGHT, 1))
    buyEmptyMessage:SetShown(#listings == 0)

    local remaining = (totalCount or #listings) - #listings
    buyMoreLabel:SetShown(remaining > 0)
    if remaining > 0 then
        buyMoreLabel:SetText(string.format("+ %d more listing(s) not shown (showing the %d cheapest)", remaining, #listings))
    end
end

local function RefreshBuyView()
    if not currentBuyEntry then
        return
    end

    local entry = currentBuyEntry
    Disenchanting.RequestLiveSearch(entry, function(itemKey)
        if currentBuyEntry ~= entry then
            -- User navigated back (or to a different item) before results arrived.
            return
        end
        local listings = Disenchanting.CollectBuyoutListings(itemKey)
        local totalCount = #listings
        if #listings == 0 then
            buyEmptyMessage:SetText("No active listings for this item right now.")
        end
        for i = #listings, BUY_LISTINGS_PAGE_SIZE + 1, -1 do
            listings[i] = nil
        end
        RenderBuyListings(listings, totalCount)
    end, function()
        if currentBuyEntry ~= entry then
            return
        end
        buyEmptyMessage:SetText("Couldn't load current listings - try closing and reopening this item.")
        RenderBuyListings({})
    end)
end

-- Wire ourselves into the search queue's generic "a purchase landed" hook.
Disenchanting.OnBidReceived = RefreshBuyView

function Disenchanting.ShowBuyView(entry)
    currentBuyEntry = entry
    buyViewIcon:SetTexture(C_Item.GetItemIconByID(entry.itemId))
    buyViewName:SetText(Disenchanting.GetItemQualityColorCode(entry.itemId) .. Disenchanting.GetItemDisplayName(entry) .. "|r")
    buyEmptyMessage:SetText("Loading current listings...")
    RenderBuyListings({})

    buyView:Show()

    RefreshBuyView()
end

function Disenchanting.HideBuyView()
    currentBuyEntry = nil
    buyView:Hide()
end

StaticPopupDialogs["ARBITRAGE_CONFIRM_BUYOUT"] = {
    text = "Buy this item for %s?",
    button1 = "Buy",
    button2 = "Cancel",
    OnAccept = function(_, data)
        C_AuctionHouse.PlaceBid(data.auctionID, data.buyout)
        MarkListingPurchased(data)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function Disenchanting.CreateBuyView(frame)
    local listView = Disenchanting.ListView

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
    closeButton:SetScript("OnClick", Disenchanting.HideBuyView)

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

    buyMoreLabel = buyView:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    buyMoreLabel:SetPoint("BOTTOMLEFT", buyView, "BOTTOMLEFT", 4, 4)
    buyMoreLabel:SetPoint("BOTTOMRIGHT", buyView, "BOTTOMRIGHT", -4, 4)
    buyMoreLabel:SetJustifyH("LEFT")
    buyMoreLabel:Hide()

    local scrollFrame = CreateFrame("ScrollFrame", "ArbitrageBuyItemScrollFrame", buyView, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", buyMoreLabel, "TOPRIGHT", -26, 4)

    buyScrollChild = CreateFrame("Frame", nil, scrollFrame)
    buyScrollChild:SetWidth(BUY_CONTENT_WIDTH)
    buyScrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(buyScrollChild)

    buyEmptyMessage = buyView:CreateFontString(nil, "ARTWORK", "GameFontDisableLarge")
    buyEmptyMessage:SetPoint("CENTER", buyView, "CENTER", 0, 0)
    buyEmptyMessage:SetText("No active listings for this item right now.")
end
