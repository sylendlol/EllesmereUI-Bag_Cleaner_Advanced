if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIBagCleaner_Ignore.lua
--  The Ignore List window: items Bag Cleaner never offers. Search, drop an item
--  on the zone to add it, hover a row and click X to remove it. Newest first.
--  Drawn in EllesmereUI's popup look (flat dark panel, thin border, accent).
-------------------------------------------------------------------------------
local _, ns = ...
local BS = ns.BagCleaner

local W, H, ROW, ICON = 440, 500, 30, 24
local SIDE, SEARCH_Y, SEARCH_H, LIST_TOP, LIST_BOTTOM = 20, 48, 26, 84, 104
local DROP_H, DROP_Y, BTN_W, BTN_H, BTN_Y, BTN_X = 34, 56, 125, 27, 13, 8

local window, rows, FillList = nil, {}, nil

-- The panel's own font (EllesmereUI.MakeFont: Expressway, locale fallback).
local function Font(parent, size, r, g, b, a)
    return EllesmereUI.MakeFont(parent, size, nil, r or 1, g or 1, b or 1, a or 1)
end

local function Border(frame, a)
    EllesmereUI.PP.CreateBorder(frame, 1, 1, 1, a or 0.15, 1, "OVERLAY", 1)
end

local function NewestFirst(a, b)
    if a.when ~= b.when then return a.when > b.when end
    return a.id < b.id
end

local function IgnoredByDate()
    local out = {}
    for itemID, when in pairs(BS.Ignored()) do
        out[#out + 1] = { id = itemID, when = type(when) == "number" and when or 0 }
    end
    table.sort(out, NewestFirst)
    return out
end

local function Refill()
    if window and window:IsShown() then FillList() end
end

local function IgnoreFromCursor()
    local kind, id = GetCursorInfo()
    if kind ~= "item" or not id then return end
    ClearCursor()
    BS.IgnoreItem(id)
    Refill()
end

-- EllesmereUI's popup buttons: dim white (Clear All) and accent (Done),
-- exactly as its confirm dialogs draw Cancel and Confirm.
local function Button(parent, text, accent, onClick, point, x, y)
    local b
    if accent then
        local r, g, bl = ns.Accent()
        b = EllesmereUI.MakePopupButton(parent, point, parent, "BOTTOM", x, y,
            r, g, bl, 0.9,  r, g, bl, 1,  r, g, bl, 0.9,  r, g, bl, 1)
    else
        b = EllesmereUI.MakePopupButton(parent, point, parent, "BOTTOM", x, y,
            1, 1, 1, 0.7,  1, 1, 1, 0.9,  1, 1, 1, 0.5,  1, 1, 1, 0.6)
    end
    b._lbl:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function RowLeave(row)
    if row:IsMouseOver() then return end
    row.hover:Hide()
    row.remove:Hide()
    GameTooltip:Hide()
end

local function NewRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW)
    row:EnableMouse(true)
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.remove = CreateFrame("Button", nil, row)
    row.remove:SetSize(22, 22)
    row.remove:SetPoint("RIGHT", -2, 0)
    row.remove.tex = row.remove:CreateTexture(nil, "ARTWORK")
    row.remove.tex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
    row.remove.tex:SetAllPoints()
    row.remove.tex:SetAlpha(0.6)
    row.remove:SetScript("OnEnter", function(self) self.tex:SetAlpha(1) end)
    row.remove:SetScript("OnLeave", function(self)
        self.tex:SetAlpha(0.6)
        RowLeave(row)
    end)
    row.remove:SetScript("OnClick", function()
        BS.Unignore(row.id)
        Refill()
    end)
    row.remove:Hide()
    row.when = Font(row, 11, 0.6, 0.6, 0.6)
    row.when:SetPoint("RIGHT", -32, 0)
    row.count = Font(row, 11, 0.6, 0.6, 0.6)
    row.count:SetPoint("RIGHT", row.when, "LEFT", -12, 0)
    row.text = Font(row, 12)
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.text:SetPoint("RIGHT", row.count, "LEFT", -8, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
        local r, g, b = ns.Accent()
        self.hover:SetColorTexture(r, g, b, 0.12)
        self.hover:Show()
        self.remove:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.id)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", RowLeave)
    return row
end

local function FillRow(row, entry, name, quality)
    local id = entry.id
    row.id = id
    row.hover:Hide()
    row.remove:Hide()
    row.icon:SetTexture(C_Item.GetItemIconByID(id))
    if name then
        local c = ITEM_QUALITY_COLORS[quality]
        row.text:SetText((c and c.hex or "|cffffffff") .. name .. "|r")
    else
        row.text:SetText("Item " .. id)
        Item:CreateFromItemID(id):ContinueOnItemLoad(Refill)
    end
    local carried = C_Item.GetItemCount(id)
    row.count:SetText(carried > 0 and ("x" .. carried) or "")
    row.when:SetText(entry.when > 0 and date("%d %b", entry.when) or "")
end

function FillList()
    local content = window.content
    local items = IgnoredByDate()
    local filter = strtrim(window.search:GetText() or ""):lower()
    window.title:SetText(("Bag Cleaner: Ignored Items (%d)"):format(#items))
    local y, shown = 0, 0
    for _, entry in ipairs(items) do
        local name, _, quality = C_Item.GetItemInfo(entry.id)
        if filter == "" or (name and name:lower():find(filter, 1, true)) then
            shown = shown + 1
            local row = rows[shown] or NewRow(content)
            rows[shown] = row
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
            row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
            FillRow(row, entry, name, quality)
            row:Show()
            y = y - ROW
        end
    end
    for i = shown + 1, #rows do rows[i]:Hide() end
    if #items == 0 then
        window.note:SetText("Nothing ignored yet. Right-click an icon on the Bag Cleaner bar, or drop an item below.")
    elseif shown == 0 then
        window.note:SetText("No ignored item matches your search.")
    end
    window.note:SetShown(shown == 0)
    if shown == 0 then y = y - ROW end
    content:SetHeight(math.max(1, -y))
    window.UpdateThumb()
end

local function NewSearch(parent)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetAutoFocus(false)
    box:SetFont(EllesmereUI.EXPRESSWAY or STANDARD_TEXT_FONT, 11, "")
    box:SetTextColor(1, 1, 1, 0.9)
    box:SetTextInsets(10, 10, 0, 0)
    box.bg = box:CreateTexture(nil, "BACKGROUND")
    box.bg:SetAllPoints()
    box.bg:SetColorTexture(0, 0, 0, 0.5)
    Border(box, 0.2)
    box.ph = Font(box, 12, 0.7, 0.7, 0.7, 0.45)
    box.ph:SetPoint("LEFT", 10, 0)
    box.ph:SetText("Search")
    box:SetScript("OnTextChanged", function(self)
        self.ph:SetShown((self:GetText() or "") == "")
        if window and window:IsShown() then FillList() end
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

local function NewDropZone(parent)
    local zone = CreateFrame("Button", nil, parent)
    zone:SetHeight(DROP_H)
    zone.bg = zone:CreateTexture(nil, "BACKGROUND")
    zone.bg:SetAllPoints()
    zone.bg:SetColorTexture(0, 0, 0, 0.35)
    Border(zone, 0.2)
    zone.text = Font(zone, 12, 0.7, 0.7, 0.7)
    zone.text:SetPoint("CENTER")
    zone.text:SetText("Drop an item here to ignore it")
    zone:SetScript("OnReceiveDrag", IgnoreFromCursor)
    zone:SetScript("OnClick", IgnoreFromCursor)
    zone:SetScript("OnEnter", function(self)
        if GetCursorInfo() == "item" then
            local r, g, b = ns.Accent()
            EllesmereUI.PP.SetBorderColor(self, r, g, b, 1)
        end
    end)
    zone:SetScript("OnLeave", function(self) EllesmereUI.PP.SetBorderColor(self, 1, 1, 1, 0.2) end)
    return zone
end

local function NewScroll(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:SetPoint("TOPLEFT", SIDE, -LIST_TOP)
    sf:SetPoint("BOTTOMRIGHT", -SIDE - 8, LIST_BOTTOM)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(W - SIDE * 2 - 8, 1)
    sf:SetScrollChild(content)
    -- Slim accent thumb on the right, like EllesmereUI's panel scrollbar.
    local track = CreateFrame("Frame", nil, parent)
    track:SetPoint("TOPLEFT", sf, "TOPRIGHT", 4, 0)
    track:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 4, 0)
    track:SetWidth(3)
    track.bg = track:CreateTexture(nil, "BACKGROUND")
    track.bg:SetAllPoints()
    track.bg:SetColorTexture(1, 1, 1, 0.05)
    local thumb = track:CreateTexture(nil, "ARTWORK")
    thumb:SetWidth(3)
    local function UpdateThumb()
        local range = math.max(0, content:GetHeight() - sf:GetHeight())
        if range <= 0 then
            thumb:Hide()
            sf:SetVerticalScroll(0)
            return
        end
        local r, g, b = ns.Accent()
        thumb:SetColorTexture(r, g, b, 0.8)
        local th = math.max(20, track:GetHeight() * sf:GetHeight() / content:GetHeight())
        local pos = sf:GetVerticalScroll() / range
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(track:GetHeight() - th) * pos)
        thumb:Show()
    end
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local range = math.max(0, content:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(range, math.max(0, self:GetVerticalScroll() - delta * ROW * 2)))
        UpdateThumb()
    end)
    return sf, content, UpdateThumb
end

local function Build()
    local f = CreateFrame("Frame", "EllesmereUIBagCleanerIgnoreWindow", UIParent)
    f:SetSize(W, H)
    f:SetPoint("CENTER", 0, 40)
    -- Above the EllesmereUI panel (DIALOG, level 100), below its confirm popup (level 100+).
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(20)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    -- Same flat panel and border as EllesmereUI's confirm popup.
    f.bg = EllesmereUI.SolidTex(f, "BACKGROUND", 0.077, 0.068, 0.058, 1)
    f.bg:SetAllPoints()
    local bc = EllesmereUI.BORDER_COLOR or { r = 1, g = 1, b = 1 }
    EllesmereUI.PP.CreateBorder(f, bc.r, bc.g, bc.b, 0.15, 1, "OVERLAY", 1)
    tinsert(UISpecialFrames, "EllesmereUIBagCleanerIgnoreWindow") -- Escape closes it

    f.title = Font(f, 16)
    f.title:SetPoint("TOP", 0, -18)

    f.close = CreateFrame("Button", nil, f)
    f.close:SetSize(18, 18)
    f.close:SetPoint("TOPRIGHT", -12, -12)
    f.close.tex = f.close:CreateTexture(nil, "ARTWORK")
    f.close.tex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
    f.close.tex:SetAllPoints()
    f.close.tex:SetAlpha(0.6)
    f.close:SetScript("OnEnter", function(self) self.tex:SetAlpha(1) end)
    f.close:SetScript("OnLeave", function(self) self.tex:SetAlpha(0.6) end)
    f.close:SetScript("OnClick", function() f:Hide() end)

    f.search = NewSearch(f)
    f.search:SetPoint("TOPLEFT", SIDE, -SEARCH_Y)
    f.search:SetPoint("TOPRIGHT", -SIDE, -SEARCH_Y)
    f.search:SetHeight(SEARCH_H)

    f.scroll, f.content, f.UpdateThumb = NewScroll(f)
    f.note = Font(f.content, 12, 0.7, 0.7, 0.7)
    f.note:SetPoint("TOPLEFT", 0, -6)
    f.note:SetWidth(W - SIDE * 2 - 8)
    f.note:SetJustifyH("LEFT")

    f.drop = NewDropZone(f)
    f.drop:SetPoint("BOTTOMLEFT", SIDE, DROP_Y)
    f.drop:SetPoint("BOTTOMRIGHT", -SIDE, DROP_Y)

    f.clear = Button(f, "Clear All", false, function()
        local function DoClear()
            BS.ClearIgnored()
            Refill()
        end
        if EllesmereUI.ShowConfirmPopup then
            EllesmereUI:ShowConfirmPopup({
                title = "Clear Ignore List",
                message = "Offer every item you ignored again?",
                confirmText = "Clear All",
                onConfirm = DoClear,
            })
        else
            DoClear()
        end
    end, "BOTTOMRIGHT", -8, BTN_Y)
    f.done = Button(f, "Done", true, function() f:Hide() end, "BOTTOMLEFT", 8, BTN_Y)

    f:SetScript("OnShow", function(self)
        if self.done._resetAnim then self.done._resetAnim() end
        if self.clear._resetAnim then self.clear._resetAnim() end
        FillList()
    end)
    f:Hide()
    return f
end

function BS.ShowIgnoreList()
    window = window or Build()
    window.search:SetText("")
    window.scroll:SetVerticalScroll(0)
    if window:IsShown() then
        FillList()
    else
        window:Show()
    end
end
