---@class Arbitrage
local Arbitrage = select(2, ...)

Arbitrage.Disenchanting = Arbitrage.Disenchanting or {}
local Disenchanting = Arbitrage.Disenchanting

Disenchanting.ROW_HEIGHT = 20
Disenchanting.PAGE_SIZE = 20
Disenchanting.BUY_LISTINGS_PAGE_SIZE = 20
Disenchanting.PANE_GAP = 10

Disenchanting.ITEM_NAME_WIDTH = 140
Disenchanting.VALUE_COL_WIDTH = 90
Disenchanting.COLUMN_GAP = 6

-- scrollChild needs this exact width, or rows anchored LEFT+RIGHT to it collapse to ~0px wide
-- and silently stop receiving mouse events, even though their text/icon still render fine.
Disenchanting.LIST_CONTENT_WIDTH = 2 + (Disenchanting.ROW_HEIGHT - 4) + 4 + Disenchanting.ITEM_NAME_WIDTH
    + Disenchanting.COLUMN_GAP + Disenchanting.VALUE_COL_WIDTH + Disenchanting.COLUMN_GAP
    + Disenchanting.VALUE_COL_WIDTH + Disenchanting.COLUMN_GAP + Disenchanting.VALUE_COL_WIDTH
Disenchanting.LIST_PANE_WIDTH = Disenchanting.LIST_CONTENT_WIDTH + 34

Disenchanting.BUY_CONTENT_WIDTH = 150 + 8 + 100 + 8 + 80
