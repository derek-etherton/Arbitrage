---@class Arbitrage
local Arbitrage = select(2, ...)

---@type table<string, table[]> profit list per registered strategy key (in-memory, live/unlimited
-- - see Arbitrage_Profile.ProfitListsSnapshot for the small persisted copy)
Arbitrage.ProfitLists = {}

---@type table<string, function> each strategy's ListPane refresh callback, set by ListPane.lua
Arbitrage.ProfitListRefreshers = {}

local valueFunctions = {}

---@param key string unique strategy id, e.g. "Disenchanting"
---@param getValue fun(listing: table): number|nil
function Arbitrage.RegisterProfitStrategy(key, getValue)
    valueFunctions[key] = getValue
end

-- Diagnostic while narrowing down why nothing new persists: a tiny field written immediately
-- (not at logout) isolates timing from size - if THIS survives but a big ProfitLists table
-- didn't, the SavedVariables write is choking on size, not on when it's written.
local function SaveDebugSnapshot()
    Arbitrage_Profile.DebugImmediateWrite = "wrote at " .. date("%X")

    Arbitrage_Profile.ProfitListsSnapshot = Arbitrage_Profile.ProfitListsSnapshot or {}
    local SNAPSHOT_CAP = 5
    for key, profitList in pairs(Arbitrage.ProfitLists) do
        local snapshot = {}
        for i = 1, math.min(SNAPSHOT_CAP, #profitList) do
            snapshot[i] = profitList[i]
        end
        Arbitrage_Profile.ProfitListsSnapshot[key] = snapshot
    end
end

function Arbitrage.RefreshAllProfitLists(listings)
    for key, getValue in pairs(valueFunctions) do
        Arbitrage.ProfitLists[key] = Arbitrage.BuildProfitList(listings, getValue)
        local refresh = Arbitrage.ProfitListRefreshers[key]
        if refresh then
            refresh()
        end
    end
    SaveDebugSnapshot()
end

print("Arbitrage: previous session's immediate-write field was - " .. tostring(Arbitrage_Profile.DebugImmediateWrite))
do
    local counts = {}
    if Arbitrage_Profile.ProfitListsSnapshot then
        for key, list in pairs(Arbitrage_Profile.ProfitListsSnapshot) do
            table.insert(counts, string.format("%s: %d", key, #list))
        end
    end
    print("Arbitrage: previous session's capped snapshot was - " .. (next(counts) and table.concat(counts, ", ") or "empty/missing"))
end
