---@class Arbitrage
local Arbitrage = select(2, ...)

-- Backed by the SavedVariable (not a plain table) so the last scan's results are still there
-- immediately on login/reload instead of sitting empty until a new scan completes - previously
-- this was a throwaway table, invisible only because Auctionator's own display was equally
-- blank post-reload until Blizzard fixed SavedVariables persistence.
Arbitrage_Profile.ProfitLists = Arbitrage_Profile.ProfitLists or {}

---@type table<string, table[]> profit list per registered strategy key
Arbitrage.ProfitLists = Arbitrage_Profile.ProfitLists

-- Temporary diagnostics while we track down why persisted results aren't surviving reload:
-- one at load (what came back from disk) and one right before save (what's about to be written).
local function SummarizeProfitLists()
    local summary = {}
    for key, profitList in pairs(Arbitrage.ProfitLists) do
        table.insert(summary, string.format("%s: %d", key, #profitList))
    end
    return next(summary) and table.concat(summary, ", ") or "empty"
end

print("Arbitrage: loaded ProfitLists from SavedVariables - " .. SummarizeProfitLists())

local logoutWatcher = CreateFrame("Frame")
logoutWatcher:RegisterEvent("PLAYER_LOGOUT")
logoutWatcher:SetScript("OnEvent", function()
    print("Arbitrage: saving ProfitLists on logout/reload - " .. SummarizeProfitLists())
end)

---@type table<string, function> each strategy's ListPane refresh callback, set by ListPane.lua
Arbitrage.ProfitListRefreshers = {}

local valueFunctions = {}

---@param key string unique strategy id, e.g. "Disenchanting"
---@param getValue fun(listing: table): number|nil
function Arbitrage.RegisterProfitStrategy(key, getValue)
    valueFunctions[key] = getValue
end

function Arbitrage.RefreshAllProfitLists(listings)
    for key, getValue in pairs(valueFunctions) do
        Arbitrage.ProfitLists[key] = Arbitrage.BuildProfitList(listings, getValue)
        local refresh = Arbitrage.ProfitListRefreshers[key]
        if refresh then
            refresh()
        end
    end
end
