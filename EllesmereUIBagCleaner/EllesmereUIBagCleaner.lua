if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIBagCleaner.lua
--  Bag Cleaner profile database + shared helpers. First in the TOC so the DB
--  exists from login. Settings live in the EllesmereUI profile store
--  (EllesmereUIDB.profiles[<profile>].addons.EllesmereUIBagCleaner) through
--  EllesmereUI.Lite.NewDB, like every suite module: they follow the active
--  EllesmereUI profile and travel with it.
--
--  Files:
--    EllesmereUIBagCleaner.lua          this file: DB, defaults, helpers
--    EllesmereUIBagCleaner_Prices.lua   auction prices (own scan, Auctionator, TSM)
--    EllesmereUIBagCleaner_Bar.lua      scan, sort, the bar, clicks, Unlock Mode
--    EllesmereUIBagCleaner_Ignore.lua   the Ignore List window
--    EllesmereUIBagCleaner_Options.lua  the Dworak > Bag Cleaner options page
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

ns.FOLDER = ADDON_NAME                 -- "EllesmereUIBagCleaner"
-- The "Dworak" sidebar section (label, position) is set in EllesmereUIDworak.lua.
ns.UNLOCK_GROUP = "Dworak"             -- group in EllesmereUI Unlock Mode

local BAGCLEANER_DEFAULTS = {
    profile = {
        enabled          = true,
        -- Offered
        count            = 4,           -- items shown
        maxQuality       = 2,           -- highest quality offered (2 = Uncommon)
        junkFirst        = false,       -- grey items before everything else
        oldFirst         = false,       -- outlevelled food / drink / potions first
        auction          = true,        -- value at the auction price when higher
        protect          = true,        -- never offer reagents, ammo, quest items, keys, set items
        -- Showing
        visibility       = "always",    -- shared EllesmereUI visibility checklist
        freeBelow        = 0,           -- only with fewer free slots than this (0 = always)
        onFull           = true,        -- "Inventory is full" brings the bar up for 20s
        showFree         = true,        -- free slots header
        countReagentBag  = false,       -- the reagent bag's empty slots count as free
        stack            = true,        -- Stack button when stacks can be combined
        prices           = true,        -- price under each icon
        -- Tooltips
        tipVendor        = true,
        tipAuction       = true,
        tipDelete        = true,
        tipIgnore        = true,
        -- Layout
        iconSize         = 36,
        highlightFirst   = true,        -- the cheapest (first) icon is drawn larger
        firstScale       = 125,         -- its size, % of Icon Size
        glowFirst        = true,        -- accent glow around the cheapest icon
        glowStyle        = 1,           -- EllesmereUI.Glows.STYLES index (1 = Pixel Glow)
        flashFull        = true,        -- red flash when the bags fill up
        spacing          = 6,
        grow             = "RIGHT",     -- RIGHT | LEFT | UP | DOWN
        textSize         = 12,
        -- Display
        bgR = 0.05, bgG = 0.05, bgB = 0.05, bgA = 0.75,
        borderSize       = 1,
        borderR = 0, borderG = 0, borderB = 0,
        qualityBorder    = true,        -- icon borders in item quality colour (Uncommon and up)
        -- Auction prices
        ahButton         = true,        -- Scan Prices button on the auction house
        -- position (point, relPoint, x, y): set by Unlock Mode, nil until moved
        -- ignore (itemID -> time ignored): the Ignore List
    },
}
ns.DEFAULTS = BAGCLEANER_DEFAULTS.profile

local SV_NAME = "EllesmereUIBagCleanerDB"

-------------------------------------------------------------------------------
--  One-time import from the module's old name, "EllesmereUI Bag Slots"
--  (folder EllesmereUIBagSlots). Runs before NewDB, so every profile that
--  had Bag Slots settings starts Bag Cleaner with them: settings, Ignore List,
--  position. Also the scanned auction prices and the Unlock Mode anchors /
--  size matches. The old data is left in place (a backup); a profile that
--  already has Bag Cleaner settings is never touched.
-------------------------------------------------------------------------------
local OLD_FOLDER, OLD_UNLOCK_KEY, NEW_UNLOCK_KEY = "EllesmereUIBagSlots", "EUI_BagSlots", "EUI_BagCleaner"

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = DeepCopy(x) end
    return t
end

do
    local root = EllesmereUIDB
    if type(root) == "table" then
        if type(root.profiles) == "table" then
            for _, prof in pairs(root.profiles) do
                local addons = type(prof) == "table" and prof.addons
                if type(addons) == "table" and type(addons[OLD_FOLDER]) == "table" and addons[ADDON_NAME] == nil then
                    local copy = DeepCopy(addons[OLD_FOLDER])
                    copy.animate = nil          -- removed option
                    addons[ADDON_NAME] = copy
                end
            end
        end
        if root.bagSlotsAuctionPrices and not root.bagCleanerAuctionPrices then
            root.bagCleanerAuctionPrices = DeepCopy(root.bagSlotsAuctionPrices)
        end
        -- Unlock Mode keeps anchors and size matches per element key.
        for _, store in ipairs({ "unlockAnchors", "unlockWidthMatch", "unlockHeightMatch",
                                 "unlockWidthMatchExtra", "unlockHeightMatchExtra" }) do
            local t = root[store]
            if type(t) == "table" then
                if t[OLD_UNLOCK_KEY] ~= nil and t[NEW_UNLOCK_KEY] == nil then
                    t[NEW_UNLOCK_KEY] = DeepCopy(t[OLD_UNLOCK_KEY])
                end
                -- Other elements anchored to / matched with the old key follow it.
                for _, v in pairs(t) do
                    if v == OLD_UNLOCK_KEY then
                        -- plain string values are handled by the key loop below
                    elseif type(v) == "table" then
                        for k2, v2 in pairs(v) do
                            if v2 == OLD_UNLOCK_KEY then v[k2] = NEW_UNLOCK_KEY end
                        end
                    end
                end
                for k, v in pairs(t) do
                    if v == OLD_UNLOCK_KEY then t[k] = NEW_UNLOCK_KEY end
                end
            end
        end
    end
end

local db = EllesmereUI.Lite.NewDB(SV_NAME, BAGCLEANER_DEFAULTS)

-- The live profile table. Re-opened when the active EllesmereUI profile
-- changed since the db was made (a live profile swap re-points only the
-- suite's own modules), so Bag Cleaner always reads the profile in use.
function ns.DB()
    local active = (EllesmereUIDB and EllesmereUIDB.activeProfile) or "Default"
    if db._profileName ~= active then
        db = EllesmereUI.Lite.NewDB(SV_NAME, BAGCLEANER_DEFAULTS)
    end
    local p = db.profile
    p.animate = nil   -- "Animate Changes" was removed
    -- Undo a short-lived change that switched Count Auction Prices off once.
    if p.vendorPriceMigrated then
        p.vendorPriceMigrated = nil
        p.auction = true
    end
    return p
end

function ns.Get(key)
    local v = ns.DB()[key]
    if v == nil then return ns.DEFAULTS[key] end
    return v
end

function ns.Set(key, value)
    ns.DB()[key] = value
end

-- Back to defaults; the Ignore List survives a reset.
function ns.ResetProfile()
    local p = ns.DB()
    local ignore = p.ignore
    db:ResetProfile()
    db.profile.ignore = ignore
end

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
function ns.Accent()
    local c = EllesmereUI.ELLESMERE_GREEN
    if c and c.r then return c.r, c.g, c.b end
    return 0.05, 0.82, 0.62
end

function ns.AccentHex()
    local r, g, b = ns.Accent()
    if EllesmereUI.HexColor then return EllesmereUI.HexColor(r, g, b) end
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

-- Chat line in the suite's style: brand-coloured module name, then the text.
function ns.Print(msg)
    local brand = (EllesmereUI.COLOR_CODES and EllesmereUI.COLOR_CODES.BRAND) or "|cff0cd29d"
    EllesmereUI.Print(brand .. "Bag Cleaner:|r " .. msg)
end

-- Coins with their icons; short keeps only the largest coin (12g 34s 5c -> 12g).
function ns.Coins(copper, short, size)
    copper = math.floor(copper or 0)
    if short then
        local unit = copper >= 10000 and 10000 or copper >= 100 and 100 or 1
        copper = copper - copper % unit
    end
    return C_CurrencyInfo.GetCoinTextureString(copper, size)
end
