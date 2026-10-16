if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIBagCleaner_Prices.lua
--  Auction prices for Bag Cleaner' "Count Auction Prices" and its tooltip.
--  Sources, first one that knows the item wins:
--    1. Bag Cleaner' own scan: a "Scan Prices" button on the auction house reads
--       every listing (one full scan per 15 minutes, Blizzard's limit) and
--       keeps the lowest buyout per item, per realm and faction.
--    2. Auctionator, when installed.
--    3. TradeSkillMaster (dbminbuyout), when installed.
-------------------------------------------------------------------------------
local _, ns = ...

local SCAN_COOLDOWN = 900
local CHUNK = 1000
local TIMEOUT = 60
local AGE_TICK = 60
local BUTTON_W, BUTTON_H = 125, 27

local P = {}
ns.Prices = P

local houseKey
local button, scanning, scanGen, ageTicker = nil, nil, 0, nil
local priced, pricedAt

-- Whether the Scan Prices button shows (a profile setting).
local function ButtonOn()
    return ns.Get("enabled") and ns.Get("ahButton")
end

-- Scanned prices are account-wide data, not a setting: they live in
-- EllesmereUIDB.bagCleanerAuctionPrices[<realm>-<faction>], outside the profiles.
local function House(create)
    if not EllesmereUIDB then
        if not create then return nil end
        EllesmereUIDB = {}
    end
    local store = EllesmereUIDB.bagCleanerAuctionPrices
    if not store then
        if not create then return nil end
        store = {}
        EllesmereUIDB.bagCleanerAuctionPrices = store
    end
    houseKey = houseKey or (GetRealmName() .. "-" .. (UnitFactionGroup("player") or ""))
    if create and not store[houseKey] then store[houseKey] = { prices = {} } end
    return store[houseKey]
end

local function Age(seconds)
    if seconds < 3600 then return math.max(1, math.floor(seconds / 60)) .. "m" end
    if seconds < 86400 then return math.floor(seconds / 3600) .. "h" end
    return math.floor(seconds / 86400) .. "d"
end
P.Age = Age

local function OwnPrice(itemID)
    local house = House()
    return house and house.prices and house.prices[itemID]
end

local function AuctionatorPrice(itemID)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.GetAuctionPriceByItemID) then return end
    local ok, value = pcall(api.GetAuctionPriceByItemID, "EllesmereUIBagCleaner", itemID)
    if ok and type(value) == "number" and value > 0 then return value end
end

local function TSMPrice(link)
    if not (TSM_API and TSM_API.GetCustomPriceValue and TSM_API.ToItemString and link) then return end
    local ok, value = pcall(TSM_API.GetCustomPriceValue, "dbminbuyout", TSM_API.ToItemString(link))
    if ok and type(value) == "number" and value > 0 then return value end
end

-- Price of one item at the auction house, or nil when no source knows it.
function P.Each(itemID, link)
    if not itemID then return end
    return OwnPrice(itemID) or AuctionatorPrice(itemID) or TSMPrice(link)
end

local function Priced(house)
    if pricedAt ~= house.time then
        priced = 0
        for _ in pairs(house.prices) do priced = priced + 1 end
        pricedAt = house.time
    end
    return priced
end

-- "Last scan 3h ago: 12,345 items priced" / "No scan yet ...".
function P.Summary()
    local house = House()
    if not (house and house.time) then
        return "No Bag Cleaner scan yet for this realm and faction."
    end
    return ("Last scan %s ago: %s items priced."):format(Age(time() - house.time), BreakUpLargeNumbers(Priced(house)))
end

-------------------------------------------------------------------------------
--  Scan Prices button on the auction house
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")

local function Label(text)
    if button then button.label:SetText(text) end
end

local function ShowAge()
    if not (button and button.age) then return end
    local house = House()
    if not (house and house.time) then return button.age:SetText("No scan yet") end
    local since = time() - house.time
    local wait = SCAN_COOLDOWN - since
    button.age:SetText(("Last scan %s ago%s"):format(Age(since),
        wait > 0 and (", next in %dm"):format(math.ceil(wait / 60)) or ""))
end

local function Stop(message)
    scanning = nil
    scanGen = scanGen + 1
    events:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    Label("Scan Prices")
    if message then ns.Print(message) end
end

local function ReadListing(prices, i)
    local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
    if not (itemID and buyout and buyout > 0 and count and count > 0) then return end
    local each = math.floor(buyout / count)
    if not prices[itemID] or each < prices[itemID] then prices[itemID] = each end
end

local function Finish(prices)
    local house = House(true)
    house.prices, house.time = prices, time()
    Stop()
    ShowAge()
    ns.Print(P.Summary())
    if ns.BagCleaner then ns.BagCleaner.RequestScan() end
end

local function ReadAll()
    events:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    local total = C_AuctionHouse.GetNumReplicateItems()
    if total == 0 then return Stop("the auction house returned no listings. Try again in a moment.") end
    local prices, index, gen = {}, 0, scanGen
    local function Step()
        if gen ~= scanGen then return end
        local last = math.min(index + CHUNK, total) - 1
        for i = index, last do ReadListing(prices, i) end
        index = last + 1
        if index < total then
            Label(("Scanning %d%%"):format(math.floor(index * 100 / total)))
            C_Timer.After(0, Step)
            return
        end
        Finish(prices)
    end
    Step()
end

local function Scan()
    if scanning then return end
    local house = House()
    local wait = house and house.time and SCAN_COOLDOWN - (time() - house.time)
    if wait and wait > 0 then
        ns.Print(("Blizzard allows one full scan every 15 minutes. Next scan in %dm."):format(math.ceil(wait / 60)))
        return
    end
    if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then
        ns.Print("this client has no full auction house scan.")
        return
    end
    scanning = true
    scanGen = scanGen + 1
    local gen = scanGen
    Label("Scanning...")
    events:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    C_AuctionHouse.ReplicateItems()
    C_Timer.After(TIMEOUT, function()
        if gen == scanGen and scanning then
            Stop("no answer from the auction house. A full scan can only run once every 15 minutes.")
        end
    end)
end

-- EllesmereUI's popup button (dim white, accent-free), the same one its
-- confirm dialogs use, with the last-scan age beside it.
local function BuildButton(frame)
    local tab = frame.AuctionsTab
    local b
    if tab then
        b = EllesmereUI.MakePopupButton(frame, "LEFT", tab, "RIGHT", 8, 0,
            1, 1, 1, 0.7,  1, 1, 1, 0.9,  1, 1, 1, 0.5,  1, 1, 1, 0.6)
    else
        b = EllesmereUI.MakePopupButton(frame, "TOPRIGHT", frame, "BOTTOMRIGHT", -8, -4,
            1, 1, 1, 0.7,  1, 1, 1, 0.9,  1, 1, 1, 0.5,  1, 1, 1, 0.6)
    end
    b:SetSize(BUTTON_W, BUTTON_H)
    b.label = b._lbl
    b.label:SetText("Scan Prices")
    b.age = EllesmereUI.MakeFont(b, 11, nil, 0.6, 0.6, 0.6)
    b.age:SetPoint("LEFT", b, "RIGHT", 8, 0)
    b:SetScript("OnClick", Scan)
    b:HookScript("OnEnter", function(self)
        EllesmereUI.ShowWidgetTooltip(self, "Reads every listing on the auction house and keeps the lowest "
            .. "buyout for each item, for Bag Cleaner. Blizzard allows one full scan every 15 minutes.\n\n"
            .. EllesmereUI.COLOR_CODES.DIM .. P.Summary() .. "|r")
    end)
    b:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
    button = b
end

local function ShowButton()
    local frame = _G.AuctionHouseFrame
    if not frame then return end
    if not button then BuildButton(frame) end
    button:SetShown(ButtonOn() and true or false)
    ShowAge()
    if ButtonOn() and not ageTicker then ageTicker = C_Timer.NewTicker(AGE_TICK, ShowAge) end
end

function P.ApplyButton()
    if button then button:SetShown(ButtonOn() and true or false) end
end

events:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_SHOW" then
        ShowButton()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        if scanning then Stop("scan stopped: the auction house closed.") end
        if ageTicker then
            ageTicker:Cancel()
            ageTicker = nil
        end
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        ReadAll()
    end
end)
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")
