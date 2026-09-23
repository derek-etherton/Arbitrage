describe("BuildProfitList", function()
    ---@type Arbitrage
    local Arbitrage

    before_each(function()
        Arbitrage = {}
        loadfile("ProfitList.lua")("Arbitrage", Arbitrage)
    end)

    it("should return an empty list for empty listings", function()
        local result = Arbitrage.BuildProfitList({}, function() return nil end)

        assert.are_same({}, result)
    end)

    it("should skip listings the value function can't value", function()
        local result = Arbitrage.BuildProfitList({
            {itemId = 111, itemLink = "linkA", quantity = 1, buyout = 100},
        }, function() return nil end)

        assert.are_same({}, result)
    end)

    it("should exclude listings with zero or negative profit", function()
        local result = Arbitrage.BuildProfitList({
            {itemId = 111, itemLink = "linkA", quantity = 1, buyout = 500}, -- profit 0
            {itemId = 222, itemLink = "linkB", quantity = 1, buyout = 600}, -- profit -100
        }, function() return 500 end)

        assert.are_same({}, result)
    end)

    it("should compute profit as value minus buyout", function()
        local result = Arbitrage.BuildProfitList({
            {itemId = 111, itemLink = "linkA", quantity = 1, buyout = 200},
        }, function(listing)
            if listing.itemId == 111 then return 500 end
            return nil
        end)

        assert.are_same(1, #result)
        assert.are_same(111, result[1].itemId)
        assert.are_same(500, result[1].value)
        assert.are_same(300, result[1].profit)
    end)

    it("should sort by profit descending", function()
        local values = {[111] = 500, [222] = 900, [333] = 600}
        local result = Arbitrage.BuildProfitList({
            {itemId = 111, itemLink = "linkA", quantity = 1, buyout = 400}, -- profit 100
            {itemId = 222, itemLink = "linkB", quantity = 1, buyout = 400}, -- profit 500
            {itemId = 333, itemLink = "linkC", quantity = 1, buyout = 400}, -- profit 200
        }, function(listing) return values[listing.itemId] end)

        assert.are_same({222, 333, 111}, {result[1].itemId, result[2].itemId, result[3].itemId})
    end)

    it("should keep original order stable for equal profit", function()
        local result = Arbitrage.BuildProfitList({
            {itemId = 111, itemLink = "linkA", quantity = 1, buyout = 100},
            {itemId = 222, itemLink = "linkB", quantity = 1, buyout = 100},
        }, function() return 500 end)

        assert.are_same({111, 222}, {result[1].itemId, result[2].itemId})
    end)

    it("should thread itemLevel/itemSuffix/battlePetSpeciesID through from the listing", function()
        local result = Arbitrage.BuildProfitList({
            {itemId = 12967, itemLink = nil, quantity = 1, buyout = 100, itemLevel = 0, itemSuffix = 605, battlePetSpeciesID = 0},
        }, function() return 500 end)

        assert.are_same(0, result[1].itemLevel)
        assert.are_same(605, result[1].itemSuffix)
        assert.are_same(0, result[1].battlePetSpeciesID)
    end)

    it("should default itemLevel/itemSuffix/battlePetSpeciesID to 0 when the listing omits them", function()
        local result = Arbitrage.BuildProfitList({
            {itemId = 111, itemLink = "linkA", quantity = 1, buyout = 100},
        }, function() return 500 end)

        assert.are_same(0, result[1].itemLevel)
        assert.are_same(0, result[1].itemSuffix)
        assert.are_same(0, result[1].battlePetSpeciesID)
    end)
end)
