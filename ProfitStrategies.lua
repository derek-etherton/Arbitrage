---@class Arbitrage
local Arbitrage = select(2, ...)

-- Kept as a live table during play - like Auctionator keeps its own price database - and only
-- serialized to a compact string at PLAYER_LOGOUT via C_EncodingUtil.SerializeCBOR, matching
-- Auctionator's own Source/Variables/Main.lua pattern exactly. That file's own comment explains
-- why: saving a large table of tables directly risks "a constant overflow when the client parses
-- the saved variables" - a real Lua limit on how many literal constants one parsed chunk can
-- hold, since a SavedVariables file is loaded back in as executed Lua source. A single flat
-- string has no such limit.
---@type table<string, table[]> profit list per registered strategy key
Arbitrage.ProfitLists = {}

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

if C_EncodingUtil then
    if Arbitrage_Profile.ProfitListsEncoded then
        local ok, decoded = pcall(C_EncodingUtil.DeserializeCBOR, Arbitrage_Profile.ProfitListsEncoded)
        if ok and type(decoded) == "table" then
            Arbitrage.ProfitLists = decoded
        end
    end

    local logoutWatcher = CreateFrame("Frame")
    logoutWatcher:RegisterEvent("PLAYER_LOGOUT")
    logoutWatcher:SetScript("OnEvent", function()
        Arbitrage_Profile.ProfitListsEncoded = C_EncodingUtil.SerializeCBOR(Arbitrage.ProfitLists)
    end)
end

-- Temporary diagnostic while confirming this survives a reload.
do
    local summary = {}
    for key, profitList in pairs(Arbitrage.ProfitLists) do
        table.insert(summary, string.format("%s: %d", key, #profitList))
    end
    print("Arbitrage: loaded ProfitLists from SavedVariables - " .. (next(summary) and table.concat(summary, ", ") or "empty")
        .. " (C_EncodingUtil " .. (C_EncodingUtil and "available" or "MISSING") .. ")")
end
