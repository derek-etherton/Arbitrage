---@class Arbitrage
local Arbitrage = select(2, ...)

Arbitrage_Profile.Settings = Arbitrage_Profile.Settings or {}
Arbitrage.Settings = Arbitrage_Profile.Settings

local defaults = {
    ShowDisenchanting = true,
    ShowVendoring = true,
}
for key, value in pairs(defaults) do
    if Arbitrage.Settings[key] == nil then
        Arbitrage.Settings[key] = value
    end
end

local visibilityRefreshers = {}

---@param key string settings key, e.g. "ShowDisenchanting"
---@param refresh fun() re-applies Arbitrage.Settings[key] to the tab if it currently exists
function Arbitrage.RegisterTabVisibility(key, refresh)
    visibilityRefreshers[key] = refresh
end

---@param key string
---@param shown boolean
function Arbitrage.SetTabShown(key, shown)
    Arbitrage.Settings[key] = shown
    local refresh = visibilityRefreshers[key]
    if refresh then
        refresh()
    end
end
