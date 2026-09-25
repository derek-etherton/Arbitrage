---@class Arbitrage
local Arbitrage = select(2, ...)

-- Kept as a live table during play - like Auctionator keeps its own price database - and only
-- serialized at PLAYER_LOGOUT, matching Auctionator's own Source/Variables/Main.lua pattern.
--
-- The value is Base64-encoded (via C_EncodingUtil.EncodeBase64) before it ever reaches the
-- SavedVariable: a raw CBOR string contains unescaped control bytes that this client's
-- SavedVariables writer doesn't Lua-escape correctly, corrupting the whole Arbitrage_Profile
-- table's syntax on the next load (Auctionator's own SavedVariables file has the identical
-- problem, storing its price database the same way). Base64 keeps it to plain printable text.
--
-- The decode itself is deferred to PLAYER_LOGIN rather than done at file-load time, mirroring
-- Auctionator's own addon-load sequence (Source/Initialize/Main.lua), which defers its own large
-- price-database decode the same way instead of doing it inline at ADDON_LOADED.
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

local function LoadProfitLists()
    if not Arbitrage_Profile.ProfitListsEncoded then
        return
    end

    local ok, decoded = pcall(function()
        return C_EncodingUtil.DeserializeCBOR(C_EncodingUtil.DecodeBase64(Arbitrage_Profile.ProfitListsEncoded))
    end)
    if ok and type(decoded) == "table" then
        Arbitrage.ProfitLists = decoded
        hasValidData = true
    end
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
end
