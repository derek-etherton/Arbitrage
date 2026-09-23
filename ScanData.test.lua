describe("ParseReplicateScanData", function()
    ---@type Arbitrage
    local Arbitrage

    before_each(function()
        Arbitrage = {}
        loadfile("ScanData.lua")("Arbitrage", Arbitrage)
    end)

    local function replicateInfo(quantity, totalBuyout, itemId)
        -- Real tuples have 18 elements; only indices 3/10/17 matter to us.
        local info = {}
        info[3] = quantity
        info[10] = totalBuyout
        info[17] = itemId
        return info
    end

    it("should return an empty list for empty scan data", function()
        local listings = Arbitrage.ParseReplicateScanData({})

        assert.are_same({}, listings)
    end)

    it("should extract itemId, itemLink, quantity, and per-unit buyout", function()
        local scanData = {
            {replicateInfo = replicateInfo(2, 200, 10940), itemLink = "itemLinkA"},
        }

        local listings = Arbitrage.ParseReplicateScanData(scanData)

        assert.are_same({
            {itemId = 10940, itemLink = "itemLinkA", quantity = 2, buyout = 100},
        }, listings)
    end)

    it("should skip listings with zero quantity", function()
        local scanData = {
            {replicateInfo = replicateInfo(0, 200, 10940), itemLink = "itemLinkA"},
        }

        local listings = Arbitrage.ParseReplicateScanData(scanData)

        assert.are_same({}, listings)
    end)

    it("should skip listings with zero buyout (bid-only auctions)", function()
        local scanData = {
            {replicateInfo = replicateInfo(1, 0, 10940), itemLink = "itemLinkA"},
        }

        local listings = Arbitrage.ParseReplicateScanData(scanData)

        assert.are_same({}, listings)
    end)

    it("should skip listings with no itemId", function()
        local scanData = {
            {replicateInfo = replicateInfo(1, 100, nil), itemLink = "itemLinkA"},
        }

        local listings = Arbitrage.ParseReplicateScanData(scanData)

        assert.are_same({}, listings)
    end)

    it("should handle multiple listings, skipping invalid ones", function()
        local scanData = {
            {replicateInfo = replicateInfo(1, 100, 111), itemLink = "linkA"},
            {replicateInfo = replicateInfo(0, 100, 222), itemLink = "linkB"},
            {replicateInfo = replicateInfo(3, 300, 333), itemLink = "linkC"},
        }

        local listings = Arbitrage.ParseReplicateScanData(scanData)

        assert.are_same({
            {itemId = 111, itemLink = "linkA", quantity = 1, buyout = 100},
            {itemId = 333, itemLink = "linkC", quantity = 3, buyout = 100},
        }, listings)
    end)
end)

describe("ParseBrowseScanData", function()
    ---@type Arbitrage
    local Arbitrage

    before_each(function()
        Arbitrage = {}
        loadfile("ScanData.lua")("Arbitrage", Arbitrage)
    end)

    local function browseResult(itemId, minPrice, totalQuantity)
        return {
            itemKey = {itemID = itemId},
            minPrice = minPrice,
            totalQuantity = totalQuantity,
        }
    end

    it("should return an empty list for an empty scan", function()
        local listings = Arbitrage.ParseBrowseScanData({})

        assert.are_same({}, listings)
    end)

    it("should extract itemId, quantity, and min price, with a nil itemLink", function()
        local rawScan = {browseResult(10940, 100, 5)}

        local listings = Arbitrage.ParseBrowseScanData(rawScan)

        assert.are_same({
            {itemId = 10940, itemLink = nil, quantity = 5, buyout = 100},
        }, listings)
    end)

    it("should skip results with zero quantity", function()
        local rawScan = {browseResult(10940, 100, 0)}

        local listings = Arbitrage.ParseBrowseScanData(rawScan)

        assert.are_same({}, listings)
    end)

    it("should skip results with zero or nil min price", function()
        local rawScan = {browseResult(10940, 0, 5), browseResult(10941, nil, 5)}

        local listings = Arbitrage.ParseBrowseScanData(rawScan)

        assert.are_same({}, listings)
    end)

    it("should skip results with no itemKey", function()
        local rawScan = {{minPrice = 100, totalQuantity = 5}}

        local listings = Arbitrage.ParseBrowseScanData(rawScan)

        assert.are_same({}, listings)
    end)
end)
