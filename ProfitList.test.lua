describe("BuildProfitList", function()
    ---@type Arbitrage
    local Arbitrage

    before_each(function()
        Arbitrage = {}
        _G.DisenchantBuddy = {
            API = {
                v1 = {
                    GetAverageDisenchantValueByItemID = spy.new(function() return nil end)
                }
            }
        }
        loadfile("ProfitList.lua")("Arbitrage", Arbitrage)
    end)

    it("should return an empty list for empty listings", function()
        local result = Arbitrage.BuildProfitList({})

        assert.are_same({}, result)
    end)

    it("should skip listings DisenchantBuddy can't value", function()
        _G.DisenchantBuddy.API.v1.GetAverageDisenchantValueByItemID = spy.new(function() return nil end)
        loadfile("ProfitList.lua")("Arbitrage", Arbitrage)

        local result = Arbitrage.BuildProfitList({
            {itemId = 111, itemLink = "linkA", quantity = 1, buyout = 100},
        })

        assert.are_same({}, result)
    end)

    it("should return nil-safe when DisenchantBuddy is not loaded", function()
        _G.DisenchantBuddy = nil
        loadfile("ProfitList.lua")("Arbitrage", Arbitrage)

        local result = Arbitrage.BuildProfitList({
            {itemId = 111, itemLink = "linkA", quantity = 1, buyout = 100},
        })

        assert.are_same({}, result)
    end)

    it("should compute profit as disenchant value minus buyout", function()
        _G.DisenchantBuddy.API.v1.GetAverageDisenchantValueByItemID = spy.new(function(_, itemId)
            if itemId == 111 then return 500 end
            return nil
        end)
        loadfile("ProfitList.lua")("Arbitrage", Arbitrage)

        local result = Arbitrage.BuildProfitList({
            {itemId = 111, itemLink = "linkA", quantity = 1, buyout = 200},
        })

        assert.are_same(1, #result)
        assert.are_same(111, result[1].itemId)
        assert.are_same(500, result[1].disenchantValue)
        assert.are_same(300, result[1].profit)
        assert.spy(_G.DisenchantBuddy.API.v1.GetAverageDisenchantValueByItemID)
            .was.called_with("Arbitrage", 111)
    end)

    it("should sort by profit descending", function()
        _G.DisenchantBuddy.API.v1.GetAverageDisenchantValueByItemID = spy.new(function(_, itemId)
            local values = {[111] = 500, [222] = 900, [333] = 600}
            return values[itemId]
        end)
        loadfile("ProfitList.lua")("Arbitrage", Arbitrage)

        local result = Arbitrage.BuildProfitList({
            {itemId = 111, itemLink = "linkA", quantity = 1, buyout = 400}, -- profit 100
            {itemId = 222, itemLink = "linkB", quantity = 1, buyout = 400}, -- profit 500
            {itemId = 333, itemLink = "linkC", quantity = 1, buyout = 400}, -- profit 200
        })

        assert.are_same({222, 333, 111}, {result[1].itemId, result[2].itemId, result[3].itemId})
    end)

    it("should thread itemLevel/itemSuffix/battlePetSpeciesID through from the listing", function()
        _G.DisenchantBuddy.API.v1.GetAverageDisenchantValueByItemID = spy.new(function() return 500 end)
        loadfile("ProfitList.lua")("Arbitrage", Arbitrage)

        local result = Arbitrage.BuildProfitList({
            {itemId = 12967, itemLink = nil, quantity = 1, buyout = 100, itemLevel = 0, itemSuffix = 605, battlePetSpeciesID = 0},
        })

        assert.are_same(0, result[1].itemLevel)
        assert.are_same(605, result[1].itemSuffix)
        assert.are_same(0, result[1].battlePetSpeciesID)
    end)

    it("should default itemLevel/itemSuffix/battlePetSpeciesID to 0 when the listing omits them", function()
        _G.DisenchantBuddy.API.v1.GetAverageDisenchantValueByItemID = spy.new(function() return 500 end)
        loadfile("ProfitList.lua")("Arbitrage", Arbitrage)

        local result = Arbitrage.BuildProfitList({
            {itemId = 111, itemLink = "linkA", quantity = 1, buyout = 100},
        })

        assert.are_same(0, result[1].itemLevel)
        assert.are_same(0, result[1].itemSuffix)
        assert.are_same(0, result[1].battlePetSpeciesID)
    end)

    it("should keep original order stable for equal profit", function()
        _G.DisenchantBuddy.API.v1.GetAverageDisenchantValueByItemID = spy.new(function() return 500 end)
        loadfile("ProfitList.lua")("Arbitrage", Arbitrage)

        local result = Arbitrage.BuildProfitList({
            {itemId = 111, itemLink = "linkA", quantity = 1, buyout = 100},
            {itemId = 222, itemLink = "linkB", quantity = 1, buyout = 100},
        })

        assert.are_same({111, 222}, {result[1].itemId, result[2].itemId})
    end)
end)
