---@class Arbitrage
local Arbitrage = select(2, ...)

-- Kept as a live table during play - like Auctionator keeps its own price database - and only
-- serialized at PLAYER_LOGOUT, matching Auctionator's own Source/Variables/Main.lua pattern.
--
-- Two client-specific problems fixed here, both confirmed directly rather than guessed at:
--
-- 1. This client's SavedVariables writer doesn't escape raw binary correctly. Running the actual
--    saved WTF/.../SavedVariables/Arbitrage.lua through luac5.1 -p reproducibly failed with
--    "unfinished string near '<eof>'" - a raw C_EncodingUtil.SerializeCBOR string contains
--    unescaped control bytes that break Lua's string-literal syntax, so the whole
--    Arbitrage_Profile table silently failed to parse on the next load (masked because Settings'
--    own defaults happened to match what was already there). Auctionator's own SavedVariables
--    file has the identical parse failure for the identical reason - not Arbitrage-specific.
--    Fixed by Base64-encoding the CBOR bytes before they ever reach a SavedVariable, so the file
--    only ever contains plain printable text.
--
-- 2. Even with a confirmed-valid, Base64-safe file on disk, reading Arbitrage_Profile.ProfitListsEncoded
--    at plain file-load time kept coming back nil. Auctionator's own addon-load sequence
--    (Source/Initialize/Main.lua) explains why it avoids exactly this: it defers its own (also
--    large) price database decode to PLAYER_LOGIN specifically, rather than doing it inline at
--    ADDON_LOADED/file-load time, implying large SavedVariables values aren't reliably available
--    that early on this client. Fixed by deferring our decode to PLAYER_LOGIN too.
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
local function LoadProfitLists()
    local loadDiagnostic
    if not Arbitrage_Profile.ProfitListsEncoded then
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
end

if C_EncodingUtil then
    local loginWatcher = CreateFrame("Frame")
    loginWatcher:RegisterEvent("PLAYER_LOGIN")
    loginWatcher:SetScript("OnEvent", LoadProfitLists)

    local logoutWatcher = CreateFrame("Frame")
    logoutWatcher:RegisterEvent("PLAYER_LOGOUT")
    logoutWatcher:SetScript("OnEvent", function()
        if hasValidData then
            Arbitrage_Profile.ProfitListsEncoded = C_EncodingUtil.EncodeBase64(C_EncodingUtil.SerializeCBOR(Arbitrage.ProfitLists))
        end
    end)
else
    print("Arbitrage: ProfitLists load - C_EncodingUtil missing")
end
