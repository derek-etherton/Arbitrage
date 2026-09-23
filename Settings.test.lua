describe("Settings", function()
    ---@type Arbitrage
    local Arbitrage

    local function load()
        Arbitrage = {}
        loadfile("Arbitrage.lua")("Arbitrage", Arbitrage)
        loadfile("Settings.lua")("Arbitrage", Arbitrage)
    end

    before_each(function()
        _G.Arbitrage_Profile = nil
        load()
    end)

    it("should default ShowDisenchanting and ShowVendoring to true", function()
        assert.is_true(Arbitrage.Settings.ShowDisenchanting)
        assert.is_true(Arbitrage.Settings.ShowVendoring)
    end)

    it("should preserve an existing saved value instead of overwriting it with the default", function()
        _G.Arbitrage_Profile = {Settings = {ShowDisenchanting = false}}
        load()

        assert.is_false(Arbitrage.Settings.ShowDisenchanting)
        assert.is_true(Arbitrage.Settings.ShowVendoring)
    end)

    it("should call the registered refresher when a tab's visibility is set", function()
        local refresh = spy.new(function() end)
        Arbitrage.RegisterTabVisibility("ShowDisenchanting", refresh)

        Arbitrage.SetTabShown("ShowDisenchanting", false)

        assert.is_false(Arbitrage.Settings.ShowDisenchanting)
        assert.spy(refresh).was.called()
    end)

    it("should not error when setting visibility for a key with no registered refresher", function()
        local ok = pcall(Arbitrage.SetTabShown, "ShowVendoring", false)

        assert.is_true(ok)
    end)
end)
