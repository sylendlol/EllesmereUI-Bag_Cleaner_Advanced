if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIBagCleaner_Options.lua
--  Builds the "Bag Cleaner" page: a live preview of the bar in the content
--  header, then its settings, with EllesmereUI's own widget factory and page
--  conventions (section headers, DualRows, slider + inline colour swatch,
--  shared visibility checklist, keybind button, disabled-state tooltips).
--
--  The page is the "Bag Cleaner" row of the "Dworak" sidebar section, which
--  EllesmereUIDworak registers through EllesmereUI's Plugin API
--  (EllesmereUI\PLUGINS_API.md), so an EllesmereUI update never overwrites
--  or breaks it.
-------------------------------------------------------------------------------
local _, ns = ...
local BS = ns.BagCleaner
local Get, Set = ns.Get, ns.Set

local PAGE_BAGCLEANER = "Bag Cleaner"

-------------------------------------------------------------------------------
--  Search Module Settings
--  EllesmereUI shows its inline search box (tab bar, top right) only on its
--  own modules. This is the same box, drawn the same way, at the top of the
--  page header: it drives EllesmereUI's own inline search
--  (EllesmereUI:ApplyInlineSearch), so matching rows are kept and highlighted
--  and the rest folds away exactly as on every suite page.
-------------------------------------------------------------------------------
local SEARCH_W, SEARCH_H, SEARCH_STRIP = 210, 28, 40
local searchFrame, searchBox

local function BuildSearchBox(header)
    local EUI = EllesmereUI
    local bc = EUI.BORDER_COLOR or { r = 1, g = 1, b = 1 }
    local dim = EUI.TEXT_DIM or { r = 1, g = 1, b = 1 }
    local f = CreateFrame("Frame", nil, header)
    f:SetSize(SEARCH_W, SEARCH_H)
    local bg = EUI.SolidTex(f, "BACKGROUND", EUI.SL_INPUT_R or 0.03, EUI.SL_INPUT_G or 0.023,
        EUI.SL_INPUT_B or 0.018, (EUI.SL_INPUT_A or 0.25) + 0.10)
    bg:SetAllPoints()
    local brd = EUI.MakeBorder(f, bc.r, bc.g, bc.b, 0.10, EUI.PanelPP)

    local edit = CreateFrame("EditBox", nil, f)
    edit:SetAllPoints()
    edit:SetAutoFocus(false)
    edit:SetFont(EUI.EXPRESSWAY, 13, "")
    edit:SetTextColor(1, 1, 1, 1)
    edit:SetTextInsets(10, 24, 0, 0)
    edit:SetMaxLetters(40)

    local placeholder = EUI.MakeFont(f, 12, nil, dim.r, dim.g, dim.b, 0.3)
    placeholder:SetPoint("LEFT", f, "LEFT", 10, 0)
    placeholder:SetText(EUI.L("Search Module Settings..."))

    local clear = CreateFrame("Button", nil, f)
    clear:SetSize(20, 20)
    clear:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    clear:SetFrameLevel(edit:GetFrameLevel() + 2)
    clear:Hide()
    local x = EUI.MakeFont(clear, 15, nil, dim.r, dim.g, dim.b, 0.35)
    x:SetPoint("CENTER")
    x:SetText("x")
    clear:SetScript("OnEnter", function() x:SetTextColor(1, 1, 1, 1) end)
    clear:SetScript("OnLeave", function() x:SetTextColor(dim.r, dim.g, dim.b, 0.35) end)
    clear:SetScript("OnClick", function()
        edit:SetText("")
        edit:ClearFocus()
    end)

    f:EnableMouse(true)
    f:SetScript("OnEnter", function() brd:SetColor(bc.r, bc.g, bc.b, 0.15) end)
    f:SetScript("OnLeave", function() brd:SetColor(bc.r, bc.g, bc.b, 0.10) end)
    edit:SetScript("OnEditFocusGained", function() brd:SetColor(bc.r, bc.g, bc.b, 0.15) end)
    edit:SetScript("OnEditFocusLost", function() brd:SetColor(bc.r, bc.g, bc.b, 0.10) end)

    local debounce
    edit:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        placeholder:SetShown(text == "")
        clear:SetShown(text ~= "")
        if debounce then debounce:Cancel(); debounce = nil end
        -- The first letter makes EllesmereUI rebuild the page once (its search
        -- expands collapsed sections), which re-parents this box with the header
        -- and drops its focus: give it back, cursor at the end.
        local hadFocus = self:HasFocus()
        EUI:ApplyInlineSearch(text, true)
        if hadFocus and not self:HasFocus() and self:IsVisible() then
            self:SetFocus()
            self:SetCursorPosition(#text)
        end
        if text ~= "" then
            debounce = C_Timer.NewTimer(0.5, function()
                debounce = nil
                EUI:ApplyInlineSearch(text)
            end)
        end
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    searchFrame, searchBox = f, edit
end

-- Empties the box (and so restores the page) while the page is still active.
local function ClearSearch()
    if searchBox and searchBox:GetText() ~= "" then searchBox:SetText("") end
end

-- The content header: the search box on top, the live preview under it.
-- Exported through getHeaderBuilder so a cached page whose header was
-- dropped rebuilds with it.
local function HeaderBuilder(header, width)
    if not searchFrame then BuildSearchBox(header) end
    searchFrame:SetParent(header)
    searchFrame:SetFrameStrata(header:GetFrameStrata())
    searchFrame:SetFrameLevel(header:GetFrameLevel() + 5)
    searchFrame:ClearAllPoints()
    searchFrame:SetPoint("TOPRIGHT", header, "TOPRIGHT", -10, -((SEARCH_STRIP - SEARCH_H) / 2))
    searchFrame:Show()
    -- The text is kept: the header is also rebuilt in the middle of a search.
    -- The box is emptied when the module is left (onModuleLeave).

    local building = true
    local view = BS.CreateSettingsPreview(header, width, function(height)
        local total = height + SEARCH_STRIP
        if not building and header:IsVisible() and math.abs(header:GetHeight() - total) > 1 then
            EllesmereUI:SetContentHeaderHeightSilent(total)
        end
    end, SEARCH_STRIP)
    building = false
    return view.previewHeight + SEARCH_STRIP
end

local GROW = { RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down" }
local GROW_ORDER = { "RIGHT", "LEFT", "UP", "DOWN" }

-- Pick Up Cheapest Item: a real key binding (Bindings.xml), written out of
-- combat and saved to the current binding set.
local function SetPickupKey(chord)
    if InCombatLockdown() then
        ns.Print("key bindings can only be changed out of combat.")
        return
    end
    local a, b = GetBindingKey(BS.BINDING)
    if a then SetBinding(a) end
    if b then SetBinding(b) end
    if chord then SetBinding(chord, BS.BINDING) end
    SaveBindings(GetCurrentBindingSet())
end

local function BuildBagCleanerPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local BLANK = EllesmereUI.BlankRowCfg
    local prebuilding = EllesmereUI.IsSearchPrebuild()
    local y = yOffset
    local _, h
    parent._showRowDivider = true

    if not prebuilding then EllesmereUI:SetContentHeader(HeaderBuilder) end

    local function off()
        return not BS.Enabled()
    end
    -- A setting changed: re-apply the bar and the preview, refresh the rows.
    local function Reapply()
        BS.Changed()
        EllesmereUI:RefreshPage()
    end
    -- Binds cfg to setting key. Greyed out while Bag Cleaner is off unless
    -- disabled is given.
    local function Bind(cfg, key, disabled, disabledTooltip)
        cfg.disabled, cfg.disabledTooltip = disabled or off, disabledTooltip or "Bag Cleaner"
        cfg.getValue = cfg.getValue or function() return Get(key) end
        cfg.setValue = cfg.setValue or function(v)
            Set(key, v)
            Reapply()
        end
        return cfg
    end
    local function Toggle(key, text, tooltip, disabled, disabledTooltip)
        return Bind({ type = "toggle", text = text, tooltip = tooltip }, key, disabled, disabledTooltip)
    end
    local function Slider(key, text, min, max, tooltip, disabled, disabledTooltip)
        return Bind({ type = "slider", text = text, tooltip = tooltip, min = min, max = max, step = 1 },
            key, disabled, disabledTooltip)
    end
    -- An inline swatch for the prefix .. "R" / "G" / "B" colour.
    local function Swatch(region, prefix, tooltip, disabled, disabledTooltip)
        EllesmereUI.BuildInlineSwatches(region, { {
            tooltip = tooltip, disabled = disabled, disabledTooltip = disabledTooltip,
            getValue = function() return Get(prefix .. "R"), Get(prefix .. "G"), Get(prefix .. "B"), 1 end,
            setValue = function(r, g, b)
                Set(prefix .. "R", r)
                Set(prefix .. "G", g)
                Set(prefix .. "B", b)
                BS.Changed()
            end,
        } }, { disabled = off, disabledTooltip = "Bag Cleaner" })
    end

    ---------------------------------------------------------------------------
    --  BAG CLEANER
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "BAG CLEANER", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Enable Bag Cleaner",
          tooltip = "The cheapest items in your bags as a row of icons, cheapest first.\n"
              .. "Click: delete. At a vendor: click sells, Ctrl-click deletes. Right-click: ignore. Shift-click: link.\n"
              .. "Move it in Unlock Mode.",
          getValue = function() return BS.Enabled() end,
          setValue = function(v)
              Set("enabled", v)
              Reapply()
          end },
        { type = "labeledButton", text = "Ignore List", buttonText = "Open Ignore List",
          tooltip = "Items Bag Cleaner never offers. Search for one, drop one in, or right-click an icon on the bar.",
          onClick = function() BS.ShowIgnoreList() end }
    );  y = y - h

    _, h = EllesmereUI.BuildVisibilityRow(W, parent, y,
        { getStore = ns.DB, legacyKey = "visibility",
          disabledFn = off, disabledTooltip = "Bag Cleaner",
          onChanged = function() BS.Changed() end,
          onOptionChanged = function() BS.Changed() end },
        Toggle("onFull", "Show When Bags Are Full",
            "An \"Inventory is full\" error brings the bar up for 20 seconds, even with more free slots than "
            .. "Only With Free Slots Below.",
            function() return off() or Get("freeBelow") == 0 end,
            function() return off() and "Bag Cleaner" or "Only With Free Slots Below" end)
    );  y = y - h

    local keyRow
    keyRow, h = W:DualRow(parent, y,
        Slider("freeBelow", "Only With Free Slots Below", 0, 30,
            "Shows the bar only once your bags are this full. 0 shows it all the time."),
        { type = "label", text = "Pick Up Cheapest Item",
          tooltip = "A key that puts the cheapest item on your cursor, to drop or sell. Also under "
              .. "Key Bindings > EllesmereUI." }
    );  y = y - h
    if not prebuilding then
        local btn = EllesmereUI.BuildKeybindButton(keyRow._rightRegion, {
            w = 170, h = 30,
            get = function() return (GetBindingKey(BS.BINDING)) end,
            set = SetPickupKey,
            disabled = off, disabledTip = "Bag Cleaner",
        })
        btn:SetPoint("RIGHT", keyRow._rightRegion, "RIGHT", -20, 0)
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  OFFERED
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "OFFERED", y);  y = y - h

    local qualityValues, qualityOrder = {}, {}
    for q = 0, 4 do
        local key, color = tostring(q), ITEM_QUALITY_COLORS[q]
        local label = _G["ITEM_QUALITY" .. q .. "_DESC"] or key
        qualityValues[key] = color and (color.hex .. label .. "|r") or label
        qualityOrder[q + 1] = key
    end

    _, h = W:DualRow(parent, y,
        Slider("count", "Items Shown", 1, 8),
        Bind({ type = "dropdown", text = "Highest Quality Offered", values = qualityValues, order = qualityOrder,
               tooltip = "Items above this quality are never offered.",
               getValue = function() return tostring(Get("maxQuality")) end,
               setValue = function(v)
                   Set("maxQuality", tonumber(v))
                   Reapply()
               end }, "maxQuality")
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("junkFirst", "Grey Items First", "Grey items come before everything else, whatever they sell for."),
        Toggle("oldFirst", "Outlevelled Food & Potions First",
            "Puts food, drink and potions 10 or more levels below you, marked with a clock, first.")
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("auction", "Count Auction Prices",
            "An item worth more at the auction house than at a vendor is valued at its auction price: from "
            .. "your last Scan Prices, else Auctionator, else TradeSkillMaster."),
        Toggle("protect", "Protect Needed Items",
            "Never offers reagents, ammo, quivers, quest items, keys or items in an equipment set (and BiS "
            .. "items while Naowh Forever is loaded).")
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("ahButton", "Scan Prices Button",
            "A Scan Prices button on the auction house. It reads every listing and keeps the lowest buyout for "
            .. "each item, for this realm and faction. Blizzard allows one full scan every 15 minutes."),
        BLANK()
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  LAYOUT
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "LAYOUT", y);  y = y - h

    _, h = W:DualRow(parent, y,
        Slider("iconSize", "Icon Size", 24, 56),
        Slider("spacing", "Icon Spacing", 0, 20)
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("highlightFirst", "Highlight Cheapest",
            "Draws the first icon, the cheapest item, larger than the others."),
        Slider("firstScale", "Cheapest Icon Size", 100, 160,
            "Size of the cheapest item's icon, in percent of Icon Size.",
            function() return off() or not Get("highlightFirst") end,
            function() return off() and "Bag Cleaner" or "Highlight Cheapest" end)
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Bind({ type = "dropdown", text = "Grow Direction", values = GROW, order = GROW_ORDER,
               tooltip = "Which way the row grows from the cheapest item." }, "grow"),
        Slider("textSize", "Text Size", 8, 24,
            "Free slots, prices and the Stack button. The font follows Global Settings > Fonts.")
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  DISPLAY
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("showFree", "Show Free Slots", "Free bag slots out of your total, above the icons. Hover it for each bag."),
        Toggle("stack", "Show Stack Button", "A Stack button on the bar when part-filled stacks of an item can be combined.")
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("countReagentBag", "Count Reagent Bag",
            "Counts the reagent bag's empty slots as free. Off: only bags that take any loot are counted, "
            .. "since the reagent bag only holds reagents. Its items are never offered either way.",
            function() return off() or not Get("showFree") end,
            function() return off() and "Bag Cleaner" or "Show Free Slots" end),
        BLANK()
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("prices", "Show Prices", "What each stack is worth, in its largest coin, under its icon."),
        Toggle("qualityBorder", "Quality Borders", "Colors icon borders by item quality (Uncommon and up).")
    );  y = y - h

    -- Glow styles from EllesmereUI's glow engine (Blackout fills the icon: left out).
    local glowValues, glowOrder = {}, {}
    local styles = EllesmereUI.Glows and EllesmereUI.Glows.STYLES or { { name = "Pixel Glow" } }
    for i, st in ipairs(styles) do
        if not st.solidFill then
            glowValues[tostring(i)] = st.name
            glowOrder[#glowOrder + 1] = tostring(i)
        end
    end
    _, h = W:DualRow(parent, y,
        Toggle("glowFirst", "Glow Cheapest",
            "A glow in the UI Accent Color around the cheapest item's icon."),
        Bind({ type = "dropdown", text = "Glow Style", values = glowValues, order = glowOrder,
               getValue = function() return tostring(Get("glowStyle")) end,
               setValue = function(v)
                   Set("glowStyle", tonumber(v))
                   Reapply()
               end }, "glowStyle",
            function() return off() or not Get("glowFirst") end,
            function() return off() and "Bag Cleaner" or "Glow Cheapest" end)
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("flashFull", "Flash When Full",
            "The bar flashes red when your bags fill up, and on an \"Inventory is full\" error."),
        BLANK()
    );  y = y - h

    local displayRow
    displayRow, h = W:DualRow(parent, y,
        Bind({ type = "slider", text = "Background", min = 0, max = 100, step = 1,
               tooltip = "Opacity of the bar background.",
               getValue = function() return math.floor(Get("bgA") * 100 + 0.5) end,
               setValue = function(v)
                   Set("bgA", v / 100)
                   BS.Changed()
               end }),
        Bind({ type = "slider", text = "Border Size", min = 0, max = 4, step = 1,
               tooltip = "0 hides the border." }, "borderSize")
    );  y = y - h
    if not prebuilding then
        Swatch(displayRow._leftRegion, "bg", "Background Color")
        -- Nothing to colour at size 0 (the slider + inline swatch pattern).
        Swatch(displayRow._rightRegion, "border", "Border Color",
            function() return off() or Get("borderSize") == 0 end,
            function() return off() and "Bag Cleaner" or "Border Size" end)
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    ---------------------------------------------------------------------------
    --  TOOLTIPS
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "TOOLTIPS", y);  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("tipVendor", "Vendor Price", "What the whole stack sells for at a vendor, and each item's price."),
        Toggle("tipAuction", "Auction Price", "What the stack fetches at the auction house.")
    );  y = y - h

    _, h = W:DualRow(parent, y,
        Toggle("tipDelete", "Delete Hint", "The Click to delete line (Ctrl-click at a vendor, where Click sells)."),
        Toggle("tipIgnore", "Ignore Hint", "The Right-click line.")
    );  y = y - h

    return math.abs(y)
end

-------------------------------------------------------------------------------
--  Registration: the "Bag Cleaner" row of the "Dworak" sidebar section. The
--  section itself belongs to EllesmereUIDworak, which registers it at login
--  with every Dworak addon's row.
-------------------------------------------------------------------------------
local DW = EllesmereUIDworak
if not DW then
    ns.Print("EllesmereUI Dworak is not enabled, so the Bag Cleaner settings cannot be shown.")
    return
end

DW.AddModule({
    key         = "BagCleaner",
    title       = "Bag Cleaner",
    order       = 10,
    description = "The cheapest items in your bags on a small bar: delete, sell or ignore them in one click.",
    pages       = { PAGE_BAGCLEANER },
    buildPage   = BuildBagCleanerPage,
    -- The preview lives in the content header; declaring the builder makes a
    -- cached page whose header was dropped rebuild with it.
    getHeaderBuilder = function(pageName)
        if pageName == PAGE_BAGCLEANER then return HeaderBuilder end
    end,
    onPageCacheRestore = function() BS.RefreshPreview() end,
    onModuleLeave = function() ClearSearch() end,
    onReset = function()
        BS.Reset()
        local pos = EllesmereUIDB and EllesmereUIDB.unlockAnchors
        if pos then pos.EUI_BagCleaner = nil end
        BS.ApplyPosition()
        EllesmereUI:InvalidatePageCache()
    end,
})

-- /bagcleaner (or the old /bagslots) opens this page.
SLASH_EUIBAGCLEANER1 = "/bagcleaner"
SLASH_EUIBAGCLEANER2 = "/bagslots"   -- the old name keeps working
SlashCmdList.EUIBAGCLEANER = function() DW.Open("BagCleaner") end
