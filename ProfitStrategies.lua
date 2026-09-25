---@class Arbitrage
local Arbitrage = select(2, ...)

-- Kept as a live table during play - like Auctionator keeps its own price database - and only
-- serialized at PLAYER_LOGOUT, matching Auctionator's own Source/Variables/Main.lua pattern.
--
-- Root cause, confirmed directly: this client's SavedVariables writer doesn't escape raw binary
-- correctly. C_EncodingUtil.SerializeCBOR output contains arbitrary bytes (including literal
-- newlines), and running the actual saved WTF/.../SavedVariables/Arbitrage.lua file through
-- luac5.1 -p reproducibly failed with "unfinished string near '<eof>'" - the CBOR string breaks
-- Lua's string-literal syntax, so the WHOLE Arbitrage_Profile table silently fails to parse on
-- the next load (masked because Settings' own defaults happen to match what was already there).
-- Auctionator's SavedVariables file has the exact same parse failure for the exact same reason -
-- this isn't an Arbitrage-specific bug, it's a client-wide one around binary strings.
-- Fix: Base64-encode the CBOR bytes before they ever reach a SavedVariable, so the file only ever
-- contains plain printable text. C_EncodingUtil.EncodeBase64/DecodeBase64 are documented as
-- available on this exact client type (warcraft.wiki.gg lists "forever +1.60.1").
---@type table<string, table[]> profit list per registered strategy key
Arbitrage.ProfitLists = {}

---@type table<string, function> each strategy's ListPane refresh callback, set by ListPane.lua
Arbitrage.ProfitListRefreshers = {}

local valueFunctions = {}

-- Only true once this session actually has trustworthy data - either decoded successfully from
-- the SavedVariable, or freshly rebuilt from a scan. Guards the PLAYER_LOGOUT save below: without
-- this, a session that fails to decode existing good data (leaving ProfitLists at its {} default)
-- would happily overwrite that good data with the empty table on its own next logout.
local hasValidData = false

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
    hasValidData = true
end

-- Temporary diagnostic while confirming this survives a reload.
local loadDiagnostic
if not C_EncodingUtil then
    loadDiagnostic = "C_EncodingUtil missing"
elseif not Arbitrage_Profile.ProfitListsEncoded then
    loadDiagnostic = "no ProfitListsEncoded saved"
else
    local encodedLength = #Arbitrage_Profile.ProfitListsEncoded
    local ok, decodedOrError = pcall(function()
        return C_EncodingUtil.DeserializeCBOR(C_EncodingUtil.DecodeBase64(Arbitrage_Profile.ProfitListsEncoded))
    end)
    if not ok then
        loadDiagnostic = string.format("decode FAILED (%d bytes saved) - %s", encodedLength, tostring(decodedOrError))
    elseif type(decodedOrError) ~= "table" then
        loadDiagnostic = string.format("decode returned a %s, not a table (%d bytes saved)", type(decodedOrError), encodedLength)
    else
        Arbitrage.ProfitLists = decodedOrError
        hasValidData = true
        local summary = {}
        for key, profitList in pairs(Arbitrage.ProfitLists) do
            table.insert(summary, string.format("%s: %d", key, #profitList))
        end
        loadDiagnostic = string.format("decoded OK (%d bytes) - %s", encodedLength,
            next(summary) and table.concat(summary, ", ") or "empty")
    end
end
print("Arbitrage: ProfitLists load - " .. loadDiagnostic)

if C_EncodingUtil then
    local logoutWatcher = CreateFrame("Frame")
    logoutWatcher:RegisterEvent("PLAYER_LOGOUT")
    logoutWatcher:SetScript("OnEvent", function()
        if hasValidData then
            Arbitrage_Profile.ProfitListsEncoded = C_EncodingUtil.EncodeBase64(C_EncodingUtil.SerializeCBOR(Arbitrage.ProfitLists))
        end
    end)
end
