---@class Arbitrage
local Arbitrage = select(2, ...)

-- "WoW: Forever" reports as MAINLINE but with a build number in the 16000-19999 range
-- (matches Auctionator's own IsForever detection).
local build = select(4, GetBuildInfo())
Arbitrage.IsForever = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and build >= 16000 and build < 20000
