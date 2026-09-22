---@class Arbitrage
local Arbitrage = select(2, ...)

--- Addon is running on "WoW: Forever". Project ID matches retail (MAINLINE), but the TOC
--- interface version falls in the 16000-19999 range Blizzard appears to have reserved for it
--- (confirmed independently via Auctionator's own IsForever/IsRetail detection, which uses this
--- same range and a build 120000+ retail cutoff).
---@type boolean
local build = select(4, GetBuildInfo())
Arbitrage.IsForever = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and build >= 16000 and build < 20000
