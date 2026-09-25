---@class Arbitrage
local Arbitrage = select(2, ...)

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

-- Persisted as flat delimited strings, not as nested Lua tables. Everything flat (booleans, a
-- lone string) has survived a reload on this client so far; a nested table of tables never has -
-- so this avoids nesting rather than presume any table shape round-trips through SavedVariables.
local FIELD_SEP = "\7"
local ENTRY_SEP = "\8"
local ENTRY_FIELDS = {
    "itemId", "quantity", "buyout", "itemLevel", "itemSuffix",
    "battlePetSpeciesID", "value", "profit", "sortingIndex",
}

---@param profitList table[] as returned by Arbitrage.BuildProfitList
---@return string
function Arbitrage.EncodeProfitList(profitList)
    local parts = {}
    for i = 1, #profitList do
        local entry = profitList[i]
        local fields = {}
        for j = 1, #ENTRY_FIELDS do
            fields[j] = entry[ENTRY_FIELDS[j]]
        end
        fields[#ENTRY_FIELDS + 1] = entry.itemLink or ""
        parts[i] = table.concat(fields, FIELD_SEP)
    end
    return table.concat(parts, ENTRY_SEP)
end

---@param encoded string|nil as returned by Arbitrage.EncodeProfitList
---@return table[]
function Arbitrage.DecodeProfitList(encoded)
    local profitList = {}
    if not encoded or encoded == "" then
        return profitList
    end

    for entryStr in (encoded .. ENTRY_SEP):gmatch("(.-)" .. ENTRY_SEP) do
        local fields = {}
        for field in (entryStr .. FIELD_SEP):gmatch("(.-)" .. FIELD_SEP) do
            table.insert(fields, field)
        end

        local entry = {}
        for j = 1, #ENTRY_FIELDS do
            entry[ENTRY_FIELDS[j]] = tonumber(fields[j])
        end
        entry.itemLink = (fields[#ENTRY_FIELDS + 1] ~= "" and fields[#ENTRY_FIELDS + 1]) or nil
        table.insert(profitList, entry)
    end

    return profitList
end

Arbitrage_Profile.ProfitListsEncoded = Arbitrage_Profile.ProfitListsEncoded or {}
for key, encoded in pairs(Arbitrage_Profile.ProfitListsEncoded) do
    Arbitrage.ProfitLists[key] = Arbitrage.DecodeProfitList(encoded)
end

function Arbitrage.RefreshAllProfitLists(listings)
    for key, getValue in pairs(valueFunctions) do
        local profitList = Arbitrage.BuildProfitList(listings, getValue)
        Arbitrage.ProfitLists[key] = profitList
        Arbitrage_Profile.ProfitListsEncoded[key] = Arbitrage.EncodeProfitList(profitList)

        local refresh = Arbitrage.ProfitListRefreshers[key]
        if refresh then
            refresh()
        end
    end
end

-- Temporary diagnostic while confirming this survives a reload.
do
    local summary = {}
    for key, profitList in pairs(Arbitrage.ProfitLists) do
        table.insert(summary, string.format("%s: %d", key, #profitList))
    end
    print("Arbitrage: loaded ProfitLists from SavedVariables - " .. (next(summary) and table.concat(summary, ", ") or "empty"))
end
