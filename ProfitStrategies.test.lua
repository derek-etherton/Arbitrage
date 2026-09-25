describe("ProfitStrategies persistence", function()
    ---@type Arbitrage
    local Arbitrage

    local function load()
        Arbitrage = {}
        loadfile("Arbitrage.lua")("Arbitrage", Arbitrage)
        loadfile("ProfitList.lua")("Arbitrage", Arbitrage)
        loadfile("ProfitStrategies.lua")("Arbitrage", Arbitrage)
    end

    before_each(function()
        _G.Arbitrage_Profile = nil
        load()
    end)

    it("should round-trip a full entry through Encode/Decode", function()
        local original = {
            {
                itemId = 111,
                itemLink = "|cffffffff|Hitem:111:0:0:0:0:0:0:0:80:0:0:0:0|h[Test Item]|h|r",
                quantity = 2, buyout = 500, itemLevel = 40, itemSuffix = 0, battlePetSpeciesID = 0,
                value = 800, profit = 300, sortingIndex = 1,
            },
        }

        local decoded = Arbitrage.DecodeProfitList(Arbitrage.EncodeProfitList(original))

        assert.are_same(original, decoded)
    end)

    it("should round-trip an entry with no itemLink", function()
        local original = {
            {
                itemId = 222, quantity = 1, buyout = 100, itemLevel = 0, itemSuffix = 605,
                battlePetSpeciesID = 0, value = 500, profit = 400, sortingIndex = 1,
            },
        }

        local decoded = Arbitrage.DecodeProfitList(Arbitrage.EncodeProfitList(original))

        assert.are_same(original, decoded)
    end)

    it("should round-trip multiple entries in order", function()
        local original = {
            {itemId = 1, quantity = 1, buyout = 10, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0, value = 20, profit = 10, sortingIndex = 1},
            {itemId = 2, quantity = 1, buyout = 20, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0, value = 40, profit = 20, sortingIndex = 2},
        }

        local decoded = Arbitrage.DecodeProfitList(Arbitrage.EncodeProfitList(original))

        assert.are_same(original, decoded)
    end)

    it("should round-trip an empty list", function()
        assert.are_same({}, Arbitrage.DecodeProfitList(Arbitrage.EncodeProfitList({})))
    end)

    it("should decode nil or an empty string as an empty list", function()
        assert.are_same({}, Arbitrage.DecodeProfitList(nil))
        assert.are_same({}, Arbitrage.DecodeProfitList(""))
    end)

    it("should seed Arbitrage.ProfitLists from Arbitrage_Profile.ProfitListsEncoded on load", function()
        _G.Arbitrage_Profile = {
            ProfitListsEncoded = {
                Disenchanting = "111" .. "\7" .. "1" .. "\7" .. "100" .. "\7" .. "0" .. "\7" .. "0"
                    .. "\7" .. "0" .. "\7" .. "500" .. "\7" .. "400" .. "\7" .. "1" .. "\7" .. "",
            },
        }
        load()

        assert.are_same(1, #Arbitrage.ProfitLists.Disenchanting)
        assert.are_same(111, Arbitrage.ProfitLists.Disenchanting[1].itemId)
    end)

    it("should persist the encoded form whenever RefreshAllProfitLists rebuilds a list", function()
        Arbitrage.RegisterProfitStrategy("Disenchanting", function(listing) return listing.buyout + 100 end)

        Arbitrage.RefreshAllProfitLists({
            {itemId = 111, itemLink = "linkA", quantity = 1, buyout = 100, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0},
        })

        assert.is_not_nil(Arbitrage_Profile.ProfitListsEncoded.Disenchanting)
        local decoded = Arbitrage.DecodeProfitList(Arbitrage_Profile.ProfitListsEncoded.Disenchanting)
        assert.are_same(111, decoded[1].itemId)
    end)
end)
