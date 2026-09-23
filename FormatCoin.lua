---@class Arbitrage
local Arbitrage = select(2, ...)

-- Classic-flavored clients expose the plain global; WOW_PROJECT_MAINLINE-flavored clients
-- (e.g. "WoW: Forever") only expose the C_CurrencyInfo-namespaced version. Same fix as
-- DisenchantBuddy's GetTooltipLineData.lua.
Arbitrage.FormatCoin = GetCoinTextureString or (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString)
