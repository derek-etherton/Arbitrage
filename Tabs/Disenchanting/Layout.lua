---@class Arbitrage
local Arbitrage = select(2, ...)

Arbitrage.Disenchanting = Arbitrage.Disenchanting or {}
local Disenchanting = Arbitrage.Disenchanting

-- Shared sizing/layout constants for the Disenchanting tab's two panes (ListView.lua, BuyView.lua).
Disenchanting.ROW_HEIGHT = 20
Disenchanting.PAGE_SIZE = 20
Disenchanting.BUY_LISTINGS_PAGE_SIZE = 20 -- only render the cheapest N; a popular item can have hundreds
Disenchanting.PANE_GAP = 10 -- gap between the list pane and the buy sub-view

-- The list pane sits fixed-width on the left so the buy sub-view can open beside it (rather than
-- over it) on the right; its columns are narrower than a full-width list to make room.
Disenchanting.ITEM_NAME_WIDTH = 140
Disenchanting.VALUE_COL_WIDTH = 90
Disenchanting.COLUMN_GAP = 6

-- icon pad(2) + icon(ROW_HEIGHT-4) + gap(4) + name + gap + buyout + gap + DE value + gap + profit.
-- scrollChild needs an explicit width matching this, or rows anchored LEFT+RIGHT to it collapse
-- to ~0px wide and silently stop receiving mouse events (OnEnter/OnClick), even though their
-- text/icon still render fine (children draw at their own offsets regardless of parent size).
Disenchanting.LIST_CONTENT_WIDTH = 2 + (Disenchanting.ROW_HEIGHT - 4) + 4 + Disenchanting.ITEM_NAME_WIDTH
    + Disenchanting.COLUMN_GAP + Disenchanting.VALUE_COL_WIDTH + Disenchanting.COLUMN_GAP
    + Disenchanting.VALUE_COL_WIDTH + Disenchanting.COLUMN_GAP + Disenchanting.VALUE_COL_WIDTH
Disenchanting.LIST_PANE_WIDTH = Disenchanting.LIST_CONTENT_WIDTH + 34 -- + scrollbar width and a little breathing room

Disenchanting.BUY_CONTENT_WIDTH = 150 + 8 + 100 + 8 + 80 -- buyout + gap + quantity + gap + Buy button
