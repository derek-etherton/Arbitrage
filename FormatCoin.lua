---@class Arbitrage
local Arbitrage = select(2, ...)

Arbitrage.FormatCoin = GetCoinTextureString or (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString)
