---@class Arbitrage
local Arbitrage = select(2, ...)

SLASH_Arbitrage1 = "/arbitrage"

local TAB_SETTINGS = {
    disenchanting = "ShowDisenchanting",
    vendoring = "ShowVendoring",
}

local function PrintStatus()
    print("Arbitrage: /arbitrage disenchanting|vendoring [on|off]")
    for name, key in pairs(TAB_SETTINGS) do
        print(string.format("  %s: %s", name, Arbitrage.Settings[key] and "shown" or "hidden"))
    end
end

SlashCmdList["Arbitrage"] = function(msg)
    local cmd, arg = string.match(msg, "^%s*(%S*)%s*(%S*)")
    local key = cmd and TAB_SETTINGS[cmd:lower()]

    if not key then
        PrintStatus()
        return
    end

    arg = arg and arg:lower()
    local shown
    if arg == "on" then
        shown = true
    elseif arg == "off" then
        shown = false
    else
        shown = not Arbitrage.Settings[key]
    end

    Arbitrage.SetTabShown(key, shown)
    print(string.format("Arbitrage: %s tab %s", cmd, shown and "shown" or "hidden"))
end
