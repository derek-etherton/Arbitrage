describe("ProfitStrategies persistence", function()
    ---@type Arbitrage
    local Arbitrage
    local loggedOutHandler

    local function mockCreateFrame()
        local frame = {}
        frame.RegisterEvent = function() end
        frame.SetScript = function(_, _, handler)
            loggedOutHandler = handler
        end
        return frame
    end

    local function load()
        Arbitrage = {}
        loadfile("Arbitrage.lua")("Arbitrage", Arbitrage)
        loadfile("ProfitList.lua")("Arbitrage", Arbitrage)
        loadfile("ProfitStrategies.lua")("Arbitrage", Arbitrage)
    end

    before_each(function()
        _G.Arbitrage_Profile = nil
        _G.CreateFrame = mockCreateFrame
        loggedOutHandler = nil
    end)

    it("should default to an empty ProfitLists when nothing was saved", function()
        _G.C_EncodingUtil = {SerializeCBOR = function() end, DeserializeCBOR = function() end}

        load()

        assert.are_same({}, Arbitrage.ProfitLists)
    end)

    it("should decode Arbitrage_Profile.ProfitListsEncoded via C_EncodingUtil.DeserializeCBOR on load", function()
        local decoded = {Disenchanting = {{itemId = 111}}}
        _G.C_EncodingUtil = {
            SerializeCBOR = function() end,
            DeserializeCBOR = spy.new(function() return decoded end),
        }
        _G.Arbitrage_Profile = {ProfitListsEncoded = "some-encoded-blob"}

        load()

        assert.spy(_G.C_EncodingUtil.DeserializeCBOR).was.called_with("some-encoded-blob")
        assert.are_same(decoded, Arbitrage.ProfitLists)
    end)

    it("should fall back to an empty ProfitLists if decoding fails", function()
        _G.C_EncodingUtil = {
            SerializeCBOR = function() end,
            DeserializeCBOR = function() error("corrupt data") end,
        }
        _G.Arbitrage_Profile = {ProfitListsEncoded = "garbage"}

        load()

        assert.are_same({}, Arbitrage.ProfitLists)
    end)

    it("should not error when C_EncodingUtil is unavailable", function()
        _G.C_EncodingUtil = nil

        local ok = pcall(load)

        assert.is_true(ok)
        assert.are_same({}, Arbitrage.ProfitLists)
    end)

    it("should serialize the current ProfitLists via C_EncodingUtil.SerializeCBOR when PLAYER_LOGOUT fires", function()
        local serialize = spy.new(function() return "encoded-blob" end)
        _G.C_EncodingUtil = {SerializeCBOR = serialize, DeserializeCBOR = function() end}
        load()

        Arbitrage.RegisterProfitStrategy("Disenchanting", function(listing) return listing.buyout + 100 end)
        Arbitrage.RefreshAllProfitLists({
            {itemId = 111, itemLink = "linkA", quantity = 1, buyout = 100, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0},
        })

        loggedOutHandler()

        assert.spy(serialize).was.called_with(Arbitrage.ProfitLists)
        assert.are_same("encoded-blob", Arbitrage_Profile.ProfitListsEncoded)
    end)

    it("should NOT overwrite the saved data on logout if this session never got valid data", function()
        -- Regression test: a session that fails to decode existing good data must not then
        -- blindly save its own empty ProfitLists over that data on its own next logout.
        _G.C_EncodingUtil = {
            SerializeCBOR = spy.new(function() return "should-not-be-called" end),
            DeserializeCBOR = function() error("corrupt data") end,
        }
        _G.Arbitrage_Profile = {ProfitListsEncoded = "original-good-data"}
        load()

        loggedOutHandler()

        assert.spy(_G.C_EncodingUtil.SerializeCBOR).was_not.called()
        assert.are_same("original-good-data", Arbitrage_Profile.ProfitListsEncoded)
    end)

    it("should still save on logout after a successful decode, even without a fresh scan", function()
        _G.C_EncodingUtil = {
            SerializeCBOR = spy.new(function() return "re-encoded" end),
            DeserializeCBOR = function() return {Disenchanting = {}} end,
        }
        _G.Arbitrage_Profile = {ProfitListsEncoded = "original-good-data"}
        load()

        loggedOutHandler()

        assert.spy(_G.C_EncodingUtil.SerializeCBOR).was.called()
        assert.are_same("re-encoded", Arbitrage_Profile.ProfitListsEncoded)
    end)

    it("should call the registered refresher and rebuild ProfitLists when RefreshAllProfitLists runs", function()
        _G.C_EncodingUtil = {SerializeCBOR = function() end, DeserializeCBOR = function() end}
        load()

        local refresh = spy.new(function() end)
        Arbitrage.RegisterProfitStrategy("Disenchanting", function(listing) return listing.buyout + 100 end)
        Arbitrage.ProfitListRefreshers.Disenchanting = refresh

        Arbitrage.RefreshAllProfitLists({
            {itemId = 111, itemLink = "linkA", quantity = 1, buyout = 100, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0},
        })

        assert.are_same(1, #Arbitrage.ProfitLists.Disenchanting)
        assert.are_same(111, Arbitrage.ProfitLists.Disenchanting[1].itemId)
        assert.spy(refresh).was.called()
    end)
end)
