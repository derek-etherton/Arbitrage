---@class Arbitrage
local Arbitrage = select(2, ...)

Arbitrage.AH = Arbitrage.AH or {}
local AH = Arbitrage.AH

AH.ROW_HEIGHT = 30
AH.PAGE_SIZE = 15
AH.BUY_LISTINGS_PAGE_SIZE = 20
AH.PANE_GAP = 10

AH.ITEM_NAME_WIDTH = 140
AH.VALUE_COL_WIDTH = 90
AH.PERCENT_COL_WIDTH = 50
AH.COLUMN_GAP = 6

-- scrollChild needs this exact width, or rows anchored LEFT+RIGHT to it collapse to ~0px wide
-- and silently stop receiving mouse events, even though their text/icon still render fine.
AH.LIST_CONTENT_WIDTH = 2 + (AH.ROW_HEIGHT - 4) + 4 + AH.ITEM_NAME_WIDTH
    + AH.COLUMN_GAP + AH.VALUE_COL_WIDTH + AH.COLUMN_GAP
    + AH.VALUE_COL_WIDTH + AH.COLUMN_GAP + AH.VALUE_COL_WIDTH
    + AH.COLUMN_GAP + AH.PERCENT_COL_WIDTH
AH.LIST_PANE_WIDTH = AH.LIST_CONTENT_WIDTH + 34

AH.BUY_CONTENT_WIDTH = 150 + 8 + 70 + 8 + 100 + 8 + 80
