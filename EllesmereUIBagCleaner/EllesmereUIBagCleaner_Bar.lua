if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIBagCleaner_Bar.lua
--  The cheapest things in your bags as a row of icons on a small bar, to
--  delete, sell or ignore (a port of Naowh Forever's "Bag Space").
--
--    Left-click   delete (Poor and Common at once; Uncommon and up go on the
--                 cursor, where dropping them brings up the game's prompt)
--    Click        sell, while a vendor is open
--    Right-click  ignore the item (never offered again; middle-click too)
--    Shift-click  link it in chat
--
--  Never offered: reagents, ammo, quivers, quest items, keys, items in an
--  equipment set (and BiS items while Naowh Forever is loaded), anything on
--  the Ignore List. Anything an unfinished quest still asks for goes last.
--
--  Drawn like the suite's own HUD elements (Loot Feed): a background with an
--  inline colour, a pixel-perfect border, module font from EllesmereUI's font
--  settings, the shared visibility checklist, placed in Unlock Mode.
-------------------------------------------------------------------------------
local _, ns = ...

local GetContainerItemInfo = C_Container.GetContainerItemInfo
local GetContainerNumSlots = C_Container.GetContainerNumSlots
local GetContainerNumFreeSlots = C_Container.GetContainerNumFreeSlots
local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant

local Get, Set = ns.Get, ns.Set
local PP = EllesmereUI.PP
local DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = 0, y = 180 }

local BS = {}
ns.BagCleaner = BS

-- Rules (same numbers as Naowh's Bag Space)
local R = {
    SCAN_DELAY = 0.2, FULL_SHOW = 20, FULL_SLACK = 0.1, OUTLEVEL = 10, MERGE_STEPS = 60,
    QUEST_CONFIRM = 5, FOLLOW_UP = 0.6, EDGE_COLORED = 2, DIRECT_DELETE = 1, PLAIN_BAG = 0, LOW_SHARE = 0.1,
}
-- The reagent bag (its own equipped slot) only takes reagents: its empty
-- slots are no room for loot, so it is left out of the free count, the scan
-- and stacking, like quivers and profession bags.
-- Enum.BagIndex.ReagentBag where the client has it, else the equipped slot
-- past the four normal bags (NUM_TOTAL_EQUIPPED_BAG_SLOTS > NUM_BAG_SLOTS).
local REAGENT_BAG = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag)
    or (NUM_TOTAL_EQUIPPED_BAG_SLOTS and NUM_BAG_SLOTS and NUM_TOTAL_EQUIPPED_BAG_SLOTS > NUM_BAG_SLOTS
        and NUM_TOTAL_EQUIPPED_BAG_SLOTS) or nil

-- A bag that holds ordinary loot: a plain bag that is not the reagent bag.
local function IsPlainBag(bag, family)
    if family ~= R.PLAIN_BAG then return false end
    if REAGENT_BAG and bag == REAGENT_BAG then return false end
    return true
end

-- The reagent bag's free slots join the free count only with Count Reagent
-- Bag on. Its items are never offered or stacked either way.
local function CountsReagentBag(bag, family)
    return REAGENT_BAG ~= nil and bag == REAGENT_BAG and family == R.PLAIN_BAG and Get("countReagentBag") == true
end

-- Item classes never offered while Protect Needed Items is on
local ITEM_CLASS = { CONSUMABLE = 0, REAGENT = 5, PROJECTILE = 6, QUIVER = 11, QUEST = 12, KEY = 13 }
local PROTECTED_CLASS = {
    [ITEM_CLASS.REAGENT] = true, [ITEM_CLASS.PROJECTILE] = true, [ITEM_CLASS.QUIVER] = true,
    [ITEM_CLASS.QUEST] = true, [ITEM_CLASS.KEY] = true,
}
local NEED_PATTERNS = { "^(.-):%s*%d+%s*/%s*%d+", "^%d+%s*/%s*%d+%s+(.+)$" }

-- Look (sizes drawn for Font Size 12; everything scales with it)
local L = {
    PAD = 6, GAP = 6, HEAD_H = 16, HEAD_GAP = 5, HEAD_SPACE = 12, HEAD_SIZE = 12, HEAD_ICON = 14,
    TEXT_GAP = 4, STACK_PAD = 8, PRICE_SIZE = 10, PRICE_H = 12, PRICE_GAP = 3, PRICE_W = 32,
    ICON_CROP = 0.08, BADGE = 14, BADGE_ART = 12,
    BAG_ICON = "Interface\\AddOns\\EllesmereUI\\media\\micromenu\\menu-bags.png",
    CLOCK_ATLAS = "auctionhouse-icon-clock", QUEST_ATLAS = "smallquestbang",
    SAMPLE_ICON = "Interface\\Icons\\INV_Misc_QuestionMark", SAMPLE_PRICE = 12,
    SAMPLE_FREE = 28, SAMPLE_SLOTS = 96,
}
local RED = { r = 0.97, g = 0.44, b = 0.44 }
local WARN = { r = 0xfb / 255, g = 0x92 / 255, b = 0x3c / 255 }
local QUEST_RGB = { r = 1, g = 0.82, b = 0 }
local DIM = { r = 0.6, g = 0.6, b = 0.6 }

local TEXT = {
    HOLDING = "put down what you are holding first.",
    MOVED = "that item moved in your bags; the row has been refreshed.",
    A_QUEST = "a quest",
    QUEST = "%s (%d/%d)",
    CAREFUL = "careful: %s is needed for %s.",
    ON_CURSOR = "%s (%s) is on your cursor: click the ground to delete it, or a bag slot to put it back.",
    QUEST_DELETE = "%s is needed for %s. Click it again within %d seconds to delete it anyway.",
    DELETED = "deleted %s (%s).",
    IGNORED = "%s is ignored and will not be offered again. Manage it under Dworak > Bag Cleaner > Ignore List.",
    STACK_STOPPED = "stacking stopped: put down what you are holding, and wait for combat to end.",
    STACKED = "stacked your bags: %d slot%s freed.",
    OLD_TIP = ("Outlevelled: %d or more levels below you"):format(10),
}

local frame -- the live bar (built on first use)
local hasContent -- the last scan left something to show
local lastFree   -- free slots at the previous render (full-bag flash)
local unlocked, atMerchant, inCombat, pendingScan, missingInfo, junkFirst, oldFirst
local pool, picks = {}, {}
local free, total, fullUntil = 0, 0, 0
local setItems, setsDirty = {}, true
local partial, stackSaves = {}, 0
local merging, mergeSteps, mergeStartFree

local function Enabled()
    return Get("enabled") == true
end
BS.Enabled = Enabled

local function Ignored()
    local p = ns.DB()
    if type(p.ignore) ~= "table" then p.ignore = {} end
    return p.ignore
end
BS.Ignored = Ignored

-------------------------------------------------------------------------------
--  Scan
-------------------------------------------------------------------------------
local function RebuildSets()
    setsDirty = false
    wipe(setItems)
    if not (C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs) then return end
    for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs()) do
        local ids = C_EquipmentSet.GetItemIDs(setID)
        if ids then
            for _, itemID in pairs(ids) do
                if type(itemID) == "number" and itemID > 0 then setItems[itemID] = true end
            end
        end
    end
end

local scanIgnored, scanProtect, scanAuction, scanMaxQuality, scanLevel, anyLocked

local function IsBis(itemID)
    local naowh = _G.NaowhForever
    return naowh and naowh.IsBisItem and naowh.IsBisItem(itemID) and true or false
end

local function Protected(itemID, classID)
    if scanIgnored[itemID] then return true end
    if not scanProtect then return false end
    if PROTECTED_CLASS[classID] or setItems[itemID] then return true end
    return IsBis(itemID)
end

local function AuctionEach(itemID, link)
    return ns.Prices and ns.Prices.Each(itemID, link)
end

local function StackValue(itemID, link, vendor, count)
    local each = vendor
    if scanAuction then
        local ah = AuctionEach(itemID, link)
        if ah and ah > each then each = ah end
    end
    return each * count
end

local questNeeds, questDirty = {}, true
local needPool, needsUsed = {}, 0

local function NoteNeed(name, title, have, need)
    needsUsed = needsUsed + 1
    local n = needPool[needsUsed] or {}
    needPool[needsUsed] = n
    n.title, n.have, n.need = title, have, need
    questNeeds[name] = n
end

local function NoteObjectives(info)
    local objectives = C_QuestLog.GetQuestObjectives(info.questID)
    if not objectives then return end
    for _, o in ipairs(objectives) do
        if o.type == "item" and not o.finished and o.text then
            local name = o.text:match(NEED_PATTERNS[1]) or o.text:match(NEED_PATTERNS[2])
            if name then NoteNeed(name, info.title, o.numFulfilled or 0, o.numRequired or 0) end
        end
    end
end

local function RebuildQuestNeeds()
    questDirty = false
    wipe(questNeeds)
    needsUsed = 0
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetQuestObjectives
        and C_QuestLog.GetInfo) then return end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then NoteObjectives(info) end
    end
end

-- Sort order: quest items last, then (optional) greys first, (optional)
-- outlevelled food first, then cheapest first.
local function Cheaper(a, b)
    if (a.quest ~= nil) ~= (b.quest ~= nil) then return b.quest ~= nil end
    if junkFirst and (a.quality == 0) ~= (b.quality == 0) then return a.quality == 0 end
    if oldFirst and (a.old == true) ~= (b.old == true) then return a.old == true end
    if a.value ~= b.value then return a.value < b.value end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end

local listPool, listsUsed = {}, 0
local slotPool, slotsUsed = {}, 0

local function NotePartial(bag, slot, itemID, count, maxStack)
    if not maxStack or maxStack <= 1 or count >= maxStack then return end
    local list = partial[itemID]
    if not list then
        listsUsed = listsUsed + 1
        list = listPool[listsUsed] or {}
        listPool[listsUsed] = list
        wipe(list)
        list.total, list.max = 0, maxStack
        partial[itemID] = list
    end
    slotsUsed = slotsUsed + 1
    local rec = slotPool[slotsUsed] or {}
    slotPool[slotsUsed] = rec
    rec.bag, rec.slot, rec.count = bag, slot, count
    list[#list + 1] = rec
    list.total = list.total + count
end

local function CountStackSaves()
    stackSaves = 0
    for _, list in pairs(partial) do
        if #list > 1 then
            stackSaves = stackSaves + #list - math.ceil(list.total / list.max)
        end
    end
end

local function Offer(n, bag, slot, info, quality, classID, name, minLevel, vendor, icon)
    n = n + 1
    local e = pool[n] or {}
    pool[n] = e
    e.bag, e.slot, e.itemID, e.link = bag, slot, info.itemID, info.hyperlink
    e.icon, e.count, e.quality, e.name = info.iconFileID or icon
        or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(info.itemID)) or L.SAMPLE_ICON, info.stackCount or 1, quality, name
    e.vendor = vendor
    e.value = StackValue(info.itemID, info.hyperlink, vendor, e.count)
    e.old = classID == ITEM_CLASS.CONSUMABLE and (minLevel or 0) > 0 and scanLevel - minLevel >= R.OUTLEVEL
    e.quest = questNeeds[name]
    picks[n] = e
    return n
end

local function ScanSlot(n, bag, slot)
    local info = GetContainerItemInfo(bag, slot)
    if info and info.isLocked then anyLocked = true end
    if not (info and info.itemID and not info.isLocked) then return n end
    local _, _, _, _, instantIcon, classID = GetItemInfoInstant(info.itemID)
    local quality = info.quality or 1
    local name, _, _, _, minLevel, _, _, maxStack, _, _, vendor = GetItemInfo(info.itemID)
    if vendor == nil then
        missingInfo = true
        return n
    end
    NotePartial(bag, slot, info.itemID, info.stackCount or 1, maxStack)
    if vendor > 0 and quality <= scanMaxQuality and not Protected(info.itemID, classID) then
        n = Offer(n, bag, slot, info, quality, classID, name, minLevel, vendor, instantIcon)
    end
    return n
end

local function StartScan()
    for i = #picks, 1, -1 do picks[i] = nil end
    wipe(partial)
    listsUsed, slotsUsed = 0, 0
    free, total, missingInfo, anyLocked = 0, 0, false, false
    if setsDirty then RebuildSets() end
    if questDirty then RebuildQuestNeeds() end
    scanIgnored, scanProtect = Ignored(), Get("protect")
    scanAuction, scanMaxQuality = Get("auction"), Get("maxQuality")
    scanLevel = UnitLevel("player")
end

local function Scan()
    StartScan()
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS
    local n = 0
    for bag = BACKPACK_CONTAINER, lastBag do
        local freeSlots, family = GetContainerNumFreeSlots(bag)
        if IsPlainBag(bag, family) then
            local slots = GetContainerNumSlots(bag)
            free, total = free + (freeSlots or 0), total + slots
            for slot = 1, slots do n = ScanSlot(n, bag, slot) end
        elseif CountsReagentBag(bag, family) then
            free, total = free + (freeSlots or 0), total + GetContainerNumSlots(bag)
        end
    end
    CountStackSaves()
    junkFirst, oldFirst = Get("junkFirst"), Get("oldFirst")
    table.sort(picks, Cheaper)
end

-------------------------------------------------------------------------------
--  Actions
-------------------------------------------------------------------------------
local RequestScan, Update

local function StillThere(p)
    local info = GetContainerItemInfo(p.bag, p.slot)
    return info and info.itemID == p.itemID and (info.stackCount or 1) == p.count and not info.isLocked
end

local function Snapshot(e)
    return { bag = e.bag, slot = e.slot, itemID = e.itemID, link = e.link, count = e.count, value = e.value,
        quest = e.quest, quality = e.quality }
end

local function Label(p)
    return p.link .. (p.count > 1 and (" x" .. p.count) or "")
end

local function PickUp(p)
    if GetCursorInfo() then
        ns.Print(TEXT.HOLDING)
        return
    end
    if not StillThere(p) then
        ns.Print(TEXT.MOVED)
        RequestScan()
        return
    end
    C_Container.PickupContainerItem(p.bag, p.slot)
    local kind, id = GetCursorInfo()
    if kind ~= "item" or id ~= p.itemID then
        ClearCursor()
        return
    end
    return true
end

local function QuestText(q)
    return TEXT.QUEST:format(q.title or TEXT.A_QUEST, q.have, q.need)
end

local function GroundHint(p)
    if p.quest then ns.Print(TEXT.CAREFUL:format(p.link, QuestText(p.quest))) end
    ns.Print(TEXT.ON_CURSOR:format(Label(p), ns.Coins(p.value)))
end

local armedItem, armedUntil = nil, 0

-- A quest item takes a second click within 5 seconds (a warning, not a
-- popup: the delete must come straight from the click).
local function ConfirmQuestDelete(p)
    if not p.quest or (armedItem == p.itemID and GetTime() < armedUntil) then
        armedItem = nil
        return true
    end
    armedItem, armedUntil = p.itemID, GetTime() + R.QUEST_CONFIRM
    ns.Print(TEXT.QUEST_DELETE:format(p.link, QuestText(p.quest), R.QUEST_CONFIRM))
    return false
end

-- DeleteCursorItem skips the game's own confirmation, so only Poor and Common
-- are deleted straight away; better items go on the cursor and the game asks.
local function Delete(p)
    if not PickUp(p) then return end
    if p.quality > R.DIRECT_DELETE then
        GroundHint(p)
        return
    end
    DeleteCursorItem()
    if GetCursorInfo() then
        GroundHint(p)
        return
    end
    ns.Print(TEXT.DELETED:format(Label(p), ns.Coins(p.value)))
end

local function Sell(p)
    if InCombatLockdown() or not StillThere(p) then return end
    C_Container.UseContainerItem(p.bag, p.slot)
end

local function Ignore(p)
    Ignored()[p.itemID] = time()
    ns.Print(TEXT.IGNORED:format(p.link))
    RequestScan()
end

local function StopMerge(message)
    merging = false
    if message then ns.Print(message) end
    RequestScan()
end

local function Smaller(a, b)
    return a.count < b.count
end

local function NextMove()
    for _, list in pairs(partial) do
        if #list > 1 then
            table.sort(list, Smaller)
            local src = list[1]
            for i = #list, 2, -1 do
                local dst = list[i]
                local room = list.max - dst.count
                if room > 0 then return src, dst, math.min(room, src.count) end
            end
        end
    end
end

-- One move per bag update: the server locks both slots until a move lands.
local function MergeStep()
    if not merging then return end
    if InCombatLockdown() or GetCursorInfo() then
        return StopMerge(TEXT.STACK_STOPPED)
    end
    mergeSteps = mergeSteps + 1
    if mergeSteps == 1 then mergeStartFree = free end
    local src, dst, amount = NextMove()
    if not src and anyLocked and mergeSteps <= R.MERGE_STEPS then return end
    if not src or mergeSteps > R.MERGE_STEPS then
        local freed = free - mergeStartFree
        if freed <= 0 then return StopMerge() end
        return StopMerge(TEXT.STACKED:format(freed, freed == 1 and "" or "s"))
    end
    if amount < src.count then
        C_Container.SplitContainerItem(src.bag, src.slot, amount)
    else
        C_Container.PickupContainerItem(src.bag, src.slot)
    end
    C_Container.PickupContainerItem(dst.bag, dst.slot)
    if GetCursorInfo() then C_Container.PickupContainerItem(src.bag, src.slot) end
end

local function StartMerge()
    if merging or InCombatLockdown() then return end
    if GetCursorInfo() then
        ns.Print(TEXT.HOLDING)
        return
    end
    merging, mergeSteps = true, 0
    Update()
end

-- Key binding: puts the cheapest item on the cursor (to drop or sell).
-- The old Bag Slots binding (EUI_BAGSLOTS_PICKUP) calls this name.
function EUI_BagSlots_PickUp() return EUI_BagCleaner_PickUp() end

function EUI_BagCleaner_PickUp()
    if not Enabled() then return end
    Update()
    if not picks[1] then return end
    local p = Snapshot(picks[1])
    if PickUp(p) then GroundHint(p) end
end
BINDING_HEADER_EUI_BAGCLEANER = "Bag Cleaner"
BINDING_NAME_EUI_BAGCLEANER_PICKUP = "Pick Up Cheapest Item"
BS.BINDING = "EUI_BAGCLEANER_PICKUP"

-- A second pass a moment after a click (delete, sell, ignore): the scan
-- right after the bag update can draw the reshuffled row before the client
-- has settled; this redraws it the way moving an item in the bags does.
local function FollowUp()
    C_Timer.After(R.FOLLOW_UP, function() BS.RequestScan() end)
end

local function OnClick(self, button)
    local e = self.pick
    if not e or unlocked then return end
    FollowUp()
    local p = Snapshot(e)
    if IsModifiedClick("CHATLINK") then
        if ChatFrameUtil and ChatFrameUtil.InsertLink then
            ChatFrameUtil.InsertLink(p.link)
        elseif ChatEdit_InsertLink then
            ChatEdit_InsertLink(p.link)
        end
    elseif button == "RightButton" or button == "MiddleButton" then
        Ignore(p)
    elseif atMerchant and not IsControlKeyDown() then
        -- At a vendor a left click sells (it pays); Ctrl-click still deletes.
        Sell(p)
    elseif ConfirmQuestDelete(p) then
        Delete(p)
    end
end

-------------------------------------------------------------------------------
--  Tooltips
-------------------------------------------------------------------------------
local function Worth(each, count)
    if count <= 1 then return ns.Coins(each) end
    return ns.Coins(each * count) .. ("  |cff999999(%s each x%d)|r"):format(ns.Coins(each), count)
end

local function Key(text)
    return ns.AccentHex() .. text .. "|r"
end

local function AddHints(e, deleteHint, ignoreHint)
    if deleteHint then
        -- At a vendor a click sells, so deleting moves to Ctrl-click there.
        local del = atMerchant and "Ctrl-click" or "Click"
        if atMerchant then GameTooltip:AddLine(Key("Click") .. "  sell", 1, 1, 1) end
        if e.quest then
            GameTooltip:AddLine(Key(del) .. "  twice to delete", 1, 1, 1)
        elseif e.quality > R.DIRECT_DELETE then
            GameTooltip:AddLine(Key(del) .. "  pick up to delete", 1, 1, 1)
        else
            GameTooltip:AddLine(Key(del) .. "  delete now", 1, 1, 1)
        end
    end
    if ignoreHint then GameTooltip:AddLine(Key("Right-click") .. "  ignore this item", 1, 1, 1) end
end

local function AddTipLines(e, ah)
    local vendor, auction = Get("tipVendor"), Get("tipAuction")
    local deleteHint, ignoreHint = Get("tipDelete"), Get("tipIgnore")
    if vendor or auction or deleteHint or ignoreHint or e.quest or e.old then GameTooltip:AddLine(" ") end
    if vendor then GameTooltip:AddDoubleLine("Vendor", Worth(e.vendor, e.count), 1, 1, 1, 1, 1, 1) end
    if auction then
        GameTooltip:AddDoubleLine("Auction", ah and Worth(ah, e.count) or "|cff999999unknown|r", 1, 1, 1, 1, 1, 1)
    end
    if e.old then
        GameTooltip:AddLine("|A:" .. L.CLOCK_ATLAS .. ":0:0|a " .. TEXT.OLD_TIP, WARN.r, WARN.g, WARN.b)
    end
    if e.quest then
        GameTooltip:AddLine("|A:" .. L.QUEST_ATLAS .. ":0:0|a Needed for " .. QuestText(e.quest),
            QUEST_RGB.r, QUEST_RGB.g, QUEST_RGB.b)
    end
    AddHints(e, deleteHint, ignoreHint)
end

local function OnEnter(self)
    local e = self.pick
    if not e or unlocked then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetBagItem(e.bag, e.slot)
    AddTipLines(e, Get("tipAuction") and AuctionEach(e.itemID, e.link) or nil)
    GameTooltip:Show()
end

local function StackTip(self)
    local saves = self.saves or 0
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Stack Your Bags")
    GameTooltip:AddLine(("Combines part-filled stacks of the same item, freeing %d slot%s. Nothing is deleted.")
        :format(saves, saves == 1 and "" or "s"), 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(Key("Click") .. "  stack now", 1, 1, 1)
    GameTooltip:Show()
end

local function FreeTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Bag Cleaner")
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS
    local special = false
    for bag = BACKPACK_CONTAINER, lastBag do
        local slots = GetContainerNumSlots(bag)
        if slots > 0 then
            local freeSlots, family = GetContainerNumFreeSlots(bag)
            if not (IsPlainBag(bag, family) or CountsReagentBag(bag, family)) then
                special = true
            else
                local name = C_Container.GetBagName and C_Container.GetBagName(bag) or ("Bag " .. bag)
                GameTooltip:AddDoubleLine(name, ("%d/%d free"):format(freeSlots or 0, slots), 1, 1, 1, 1, 1, 1)
            end
        end
    end
    if special then
        GameTooltip:AddLine(Get("countReagentBag") and "Quivers and profession bags are not counted."
            or "The reagent bag, quivers and profession bags are not counted.", DIM.r, DIM.g, DIM.b, true)
    end
    GameTooltip:Show()
end

-------------------------------------------------------------------------------
--  Look: one "view" draws the card, live on screen or in the options preview
-------------------------------------------------------------------------------
-- Module text in EllesmereUI's font and outline (Global Settings > Fonts);
-- flags overrides the outline (item counts are always outlined).
local function Scaled(v, scale)
    return math.floor(v * scale + 0.5)
end

local function SetFont(fs, size, flags)
    EllesmereUI.ApplyModuleFont(fs, nil, size, nil, flags)
end

local function OutlineFlag()
    return EllesmereUI.OutlineFlagForMode and EllesmereUI.OutlineFlagForMode("outline") or "OUTLINE"
end

local function Text(parent, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    -- A FontString needs a font before its first SetText; Style() then applies
    -- the real size and outline.
    fs:SetFontObject(GameFontHighlightSmall)
    SetFont(fs, L.HEAD_SIZE)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function NewFreeCounter(parent, live)
    local f = CreateFrame("Frame", nil, parent)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetTexture(L.BAG_ICON)
    f.icon:SetVertexColor(0.85, 0.85, 0.85)
    f.icon:SetPoint("LEFT")
    f.text = Text(f)
    f.word = Text(f)
    f.word:SetPoint("LEFT", f.text, "RIGHT", L.TEXT_GAP, 0)
    f.word:SetText("free")
    if live then
        f:EnableMouse(true)
        f:SetScript("OnEnter", FreeTooltip)
        f:SetScript("OnLeave", GameTooltip_Hide)
    end
    return f
end

-- Stack button in the suite's style: dark fill, thin accent border and text.
local function NewStackButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b.bg = EllesmereUI.SolidTex(b, "BACKGROUND", 0, 0, 0, 0.5)
    b.bg:SetAllPoints()
    PP.CreateBorder(b, 1, 1, 1, 0.6, 1, "OVERLAY", 1)
    b.label = Text(b, "CENTER")
    b.label:SetPoint("CENTER")
    if onClick then b:SetScript("OnClick", onClick) end
    b:SetScript("OnEnter", function(self)
        local r, g, bl = ns.Accent()
        PP.SetBorderColor(self, r, g, bl, 1)
        self.label:SetTextColor(r, g, bl, 1)
        StackTip(self)
    end)
    b:SetScript("OnLeave", function(self)
        local r, g, bl = ns.Accent()
        PP.SetBorderColor(self, r, g, bl, 0.6)
        self.label:SetTextColor(r, g, bl, 0.9)
        GameTooltip:Hide()
    end)
    b:Hide()
    return b
end

local function NewBadge(parent, corner, atlas, color)
    local badge = CreateFrame("Frame", nil, parent)
    badge:SetSize(L.BADGE, L.BADGE)
    badge:SetPoint(corner, corner == "TOPLEFT" and 1 or -1, -1)
    badge.back = badge:CreateTexture(nil, "BACKGROUND")
    badge.back:SetAllPoints()
    badge.back:SetColorTexture(0, 0, 0, 0.65)
    badge.art = badge:CreateTexture(nil, "ARTWORK")
    badge.art:SetAtlas(atlas)
    badge.art:SetSize(L.BADGE_ART, L.BADGE_ART)
    badge.art:SetPoint("CENTER")
    if color then badge.art:SetVertexColor(color.r, color.g, color.b) end
    badge:Hide()
    return badge
end

local function NewView(parent, live, onClick, onEnter, onStack)
    local view = CreateFrame("Frame", nil, parent)
    view.bg = view:CreateTexture(nil, "BACKGROUND")
    view.bg:SetAllPoints()
    PP.CreateBorder(view, 0, 0, 0, 1, 1, "OVERLAY", 1)
    view.free = NewFreeCounter(view, live)
    view.stack = NewStackButton(view, onStack)
    view.measure = Text(view)   -- hidden: measures price widths for the cell width
    view.measure:Hide()
    view.cells, view.onClick, view.onEnter, view.live = {}, onClick, onEnter, live
    return view
end

local function NewCell(view, i)
    local b = CreateFrame("Button", nil, view)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(L.ICON_CROP, 1 - L.ICON_CROP, L.ICON_CROP, 1 - L.ICON_CROP)
    b.back = b:CreateTexture(nil, "BACKGROUND")
    b.back:SetAllPoints()
    b.back:SetColorTexture(0, 0, 0, 1)
    PP.CreateBorder(b, 0, 0, 0, 1, 1, "OVERLAY", 2)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetColorTexture(1, 1, 1, 0.15)
    b.marks = CreateFrame("Frame", nil, b)
    b.marks:SetAllPoints()
    b.marks:SetFrameLevel(b:GetFrameLevel() + 3)
    b.count = Text(b.marks, "RIGHT")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b.old = NewBadge(b.marks, "TOPLEFT", L.CLOCK_ATLAS, WARN)
    b.quest = NewBadge(b.marks, "TOPRIGHT", L.QUEST_ATLAS)
    b.price = Text(b, "CENTER")
    b.price:SetPoint("TOP", b, "BOTTOM", 0, -L.PRICE_GAP)
    if view.onClick then
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
        b:SetScript("OnClick", view.onClick)
    end
    b:SetScript("OnEnter", view.onEnter)
    b:SetScript("OnLeave", GameTooltip_Hide)
    view.cells[i] = b
    return b
end


-- Background (colour + opacity) and border (size + colour) as in the suite's
-- HUD elements; text sizes follow Text Size (12 is what the layout is drawn for).
local function Style(view)
    view.bg:SetColorTexture(Get("bgR"), Get("bgG"), Get("bgB"), Get("bgA"))
    view.bg:SetShown(Get("bgA") > 0)
    local bsz = Get("borderSize")
    if bsz > 0 then
        PP.UpdateBorder(view, bsz, Get("borderR"), Get("borderG"), Get("borderB"), 1)
        PP.ShowBorder(view)
    else
        PP.HideBorder(view)
    end
    local size = Get("textSize")
    local scale = size / L.HEAD_SIZE
    local price = Scaled(L.PRICE_SIZE, scale)
    view.priceSize, view.priceH, view.priceW = price, Scaled(L.PRICE_H, scale), Scaled(L.PRICE_W, scale)
    view.headH, view.headIcon = Scaled(L.HEAD_H, scale), Scaled(L.HEAD_ICON, scale)
    local f = view.free
    f:SetHeight(view.headH)
    f.icon:SetSize(view.headIcon, view.headIcon)
    f.text:ClearAllPoints()
    f.text:SetPoint("LEFT", view.headIcon + L.TEXT_GAP, 0)
    SetFont(f.text, size)
    SetFont(f.word, size)
    local dim = EllesmereUI.TEXT_DIM or DIM
    f.word:SetTextColor(dim.r, dim.g, dim.b, dim.a or 1)
    view.stack:SetHeight(view.headH + 4)
    SetFont(view.stack.label, size - 1)
    local r, g, b = ns.Accent()
    view.stack.label:SetTextColor(r, g, b, 0.9)
    PP.SetBorderColor(view.stack, r, g, b, 0.6)
    -- Cell fonts are set by Layout (view.restyle), which also styles new cells.
    view.size = size
    view.countSize = math.max(9, math.floor(Get("iconSize") * 0.33 + 0.5))
end

local function ShowFree(view, count, slots)
    local f = view.free
    if not Get("showFree") then
        f:Hide()
        return 0
    end
    local c = count == 0 and RED or count < slots * R.LOW_SHARE and WARN or nil
    if c then f.text:SetTextColor(c.r, c.g, c.b, 1) else f.text:SetTextColor(1, 1, 1, 1) end
    f.text:SetText(count)
    local w = math.ceil(view.headIcon + L.TEXT_GAP + f.text:GetStringWidth() + L.TEXT_GAP + f.word:GetStringWidth())
    f:SetWidth(w)
    f:Show()
    return w
end

local function ShowStack(view, saves)
    local b = view.stack
    if saves <= 0 then
        b:Hide()
        return 0
    end
    b.label:SetText(("Stack +%d"):format(saves))
    local w = math.ceil(b.label:GetStringWidth()) + L.STACK_PAD * 2
    b:SetWidth(w)
    b.saves = saves
    b:Show()
    return w
end

-- Lays the card out: header (free slots, Stack) on top, then one cell per
-- item in the chosen direction. Left / Up put the cheapest item at the far
-- end the row grows from (right / bottom).
-- Icon size of cell i: the first (cheapest) one is drawn larger while
-- Highlight Cheapest is on.
local function CellSize(i, size)
    if i == 1 and Get("highlightFirst") then
        return math.floor(size * (Get("firstScale") or 125) / 100 + 0.5)
    end
    return size
end

-- Lays the card out: header (free slots, Stack) on top, then one cell per
-- item in the chosen direction. Left / Up put the cheapest item at the far
-- end the row grows from (right / bottom). In a row the cells line up at
-- the bottom, so a larger first icon stands out above the others.
local function Layout(view, shown, freeW, stackW)
    local size = Get("iconSize")
    local gap = Get("spacing")
    local prices = Get("prices")
    local dir = Get("grow")
    local horizontal = dir ~= "UP" and dir ~= "DOWN"
    local priceH = prices and (L.PRICE_GAP + view.priceH) or 0
    local n = math.max(shown, 0)
    -- Per-cell icon size, cell width and cell height.
    local sz, cw, ch = rawget(view, "cellSizes") or {}, rawget(view, "cellWidths") or {}, rawget(view, "cellHeights") or {}
    view.cellSizes, view.cellWidths, view.cellHeights = sz, cw, ch
    local sumW, sumH, maxW, maxH = 0, 0, 0, 0
    for i = 1, n do
        local s = CellSize(i, size)
        sz[i] = s
        cw[i] = prices and math.max(s, view.priceW) or s
        ch[i] = s + priceH
        sumW, sumH = sumW + cw[i], sumH + ch[i]
        maxW, maxH = math.max(maxW, cw[i]), math.max(maxH, ch[i])
    end
    local contentW, contentH
    if n == 0 then
        contentW, contentH = 0, 0
    elseif horizontal then
        contentW, contentH = sumW + (n - 1) * gap, maxH
    else
        contentW, contentH = maxW, sumH + (n - 1) * gap
    end
    local headW = freeW + stackW + ((freeW > 0 and stackW > 0) and L.HEAD_SPACE or 0)
    local head = headW > 0 and view.headH or 0
    local innerW = math.max(contentW, headW, n == 0 and size or 0)
    local w = innerW + L.PAD * 2
    local h = L.PAD * 2 + head + ((head > 0 and n > 0) and L.HEAD_GAP or 0) + contentH
    if n == 0 and head == 0 then h = L.PAD * 2 + size end
    view:SetSize(w, h)

    view.free:ClearAllPoints()
    view.free:SetPoint("TOPLEFT", L.PAD, -L.PAD)
    view.stack:ClearAllPoints()
    view.stack:SetPoint("TOPRIGHT", -L.PAD, -L.PAD + 1)

    local top = -(L.PAD + head + ((head > 0) and L.HEAD_GAP or 0))
    local cells = view.cells
    -- Running offset along the row / column, in display order.
    local first, last, step = 1, n, 1
    if dir == "LEFT" or dir == "UP" then first, last, step = n, 1, -1 end
    local along = (dir == "LEFT") and (innerW - contentW) or 0
    for i = first, last, step do
        local b = cells[i] or NewCell(view, i)
        if not b.styled or view.restyle then
            SetFont(b.price, view.priceSize)
            b.price:SetTextColor(0.85, 0.85, 0.85)
            SetFont(b.count, view.countSize, OutlineFlag())
            b.styled = true
        end
        local s = sz[i]
        b:SetSize(s, s)
        b:ClearAllPoints()
        local x, y
        if horizontal then
            x = along + (cw[i] - s) / 2
            y = contentH - ch[i]          -- bottoms line up
            along = along + cw[i] + gap
        else
            x = (contentW - s) / 2
            y = along
            along = along + ch[i] + gap
        end
        b:SetPoint("TOPLEFT", view, "TOPLEFT", L.PAD + x, top - y)
        b.price:SetShown(prices)
        b:SetAlpha(1)
        b:Show()
    end
    for i = n + 1, #cells do cells[i]:Hide() end
    view.restyle = nil
end

local function Fill(b, e, icon, price, count, quality, old, quest)
    b.pick = e
    b.icon:SetTexture(icon)
    b.price:SetText(price)
    b.count:SetText(count and count > 1 and count or "")
    b.old:SetShown(old == true)
    b.quest:SetShown(quest ~= nil)
    local c = Get("qualityBorder") and quality and quality >= R.EDGE_COLORED and ITEM_QUALITY_COLORS[quality]
    if c then
        PP.SetBorderColor(b, c.r, c.g, c.b, 1)
    else
        PP.SetBorderColor(b, 0, 0, 0, 1)
    end
end

-- Full price (gold, silver and copper) in the price font.
local function PriceText(view, value)
    return ns.Coins(value, false, view.priceSize)
end

-- Widens the cells to the longest price shown, so full prices never overlap.
local function FitPrices(view, texts, n)
    local w = Scaled(L.PRICE_W, view.size / L.HEAD_SIZE)
    if Get("prices") then
        local m = view.measure
        SetFont(m, view.priceSize)
        for i = 1, n do
            m:SetText(texts[i])
            w = math.max(w, math.ceil(m:GetStringWidth()) + 4)
        end
    end
    view.priceW = w
end

-------------------------------------------------------------------------------
--  Effects: accent glow on the cheapest icon and a red flash when the bags
--  fill up. Both follow the UI Accent Color live (RegAccent, see OnLogin).
-------------------------------------------------------------------------------
local FX = { FLASH_IN = 0.12, FLASH_OUT = 0.3, FLASHES = 3 }
local FLASH_RGB = { r = 0.97, g = 0.25, b = 0.25 }

-- EllesmereUI.Glows on a wrapper over cell 1; restarted only when its look
-- (style, size, colour) changes, stopped on every other cell.
local function UpdateGlow(view, shown)
    local G = EllesmereUI.Glows
    if not G then return end
    local cells = view.cells
    local want = Get("glowFirst") and shown > 0
    for i = 1, #cells do
        local b = cells[i]
        local gw = rawget(b, "glow")
        if gw and gw._dwGlowKey and (i ~= 1 or not want) then
            G.StopGlow(gw)
            gw._dwGlowKey = nil
        end
    end
    if not want then return end
    local b = cells[1]
    if not rawget(b, "glow") then
        b.glow = CreateFrame("Frame", nil, b)
        b.glow:SetAllPoints(b)
        b.glow:SetFrameLevel(b:GetFrameLevel() + 4)
    end
    local style = tonumber(Get("glowStyle")) or 1
    local w = math.floor(b:GetWidth() + 0.5)
    local r, g, bl = ns.Accent()
    local key = ("%d:%d:%.3f:%.3f:%.3f"):format(style, w, r, g, bl)
    if b.glow._dwGlowKey == key and b.glow._euiGlowActive then return end
    b.glow:Show()
    G.StartGlow(b.glow, style, w, r, g, bl, { N = 8, th = 1, period = 5 })
    b.glow._dwGlowKey = key
end

-- Red border flash (three pulses) over the whole bar.
local function Flash(view)
    if not view then return end
    local f = rawget(view, "flash")
    if not f then
        f = CreateFrame("Frame", nil, view)
        f:SetAllPoints(view)
        f:SetFrameLevel(view:GetFrameLevel() + 20)
        f.bg = f:CreateTexture(nil, "BACKGROUND")
        f.bg:SetAllPoints()
        f.bg:SetColorTexture(FLASH_RGB.r, FLASH_RGB.g, FLASH_RGB.b, 0.12)
        PP.CreateBorder(f, FLASH_RGB.r, FLASH_RGB.g, FLASH_RGB.b, 1, 2, "OVERLAY", 7)
        f:SetAlpha(0)
        local g = f:CreateAnimationGroup()
        for i = 1, FX.FLASHES do
            local up = g:CreateAnimation("Alpha")
            up:SetOrder(i * 2 - 1)
            up:SetDuration(FX.FLASH_IN)
            up:SetFromAlpha(0)
            up:SetToAlpha(1)
            local down = g:CreateAnimation("Alpha")
            down:SetOrder(i * 2)
            down:SetDuration(FX.FLASH_OUT)
            down:SetFromAlpha(1)
            down:SetToAlpha(0)
        end
        g:SetScript("OnFinished", function() f:SetAlpha(0) end)
        f.anim = g
        view.flash = f
    end
    f.anim:Stop()
    f.anim:Play()
end

-- Stack button and glow in the current accent (UI Accent Color changed).
local function RepaintAccent(view)
    if not view then return end
    local r, g, b = ns.Accent()
    view.stack.label:SetTextColor(r, g, b, 0.9)
    PP.SetBorderColor(view.stack, r, g, b, 0.6)
    local n = 0
    for i = 1, #view.cells do if view.cells[i]:IsShown() then n = i end end
    UpdateGlow(view, n)
end

local priceTexts = {}

local function Draw(view, list, shown, count, slots, saves)
    Style(view)
    view.restyle = true
    for i = 1, shown do priceTexts[i] = PriceText(view, list[i].value) end
    FitPrices(view, priceTexts, shown)
    local freeW, stackW = ShowFree(view, count, slots), ShowStack(view, saves)
    Layout(view, shown, freeW, stackW)
    local cells = view.cells
    for i = 1, shown do
        local e = list[i]
        Fill(cells[i], e, e.icon, priceTexts[i], e.count, e.quality, e.old, e.quest)
    end
    UpdateGlow(view, shown)
end

-------------------------------------------------------------------------------
--  The live card
-------------------------------------------------------------------------------
local function RenderUnlocked()
    local n = Get("count")
    Style(frame)
    frame.restyle = true
    local freeW
    if total > 0 then
        freeW = ShowFree(frame, free, total)
    else
        freeW = ShowFree(frame, L.SAMPLE_FREE, L.SAMPLE_SLOTS)
    end
    ShowStack(frame, 0)
    for i = 1, n do
        local e = picks[i]
        priceTexts[i] = PriceText(frame, e and e.value or L.SAMPLE_PRICE * i)
    end
    FitPrices(frame, priceTexts, n)
    Layout(frame, n, freeW, 0)
    local cells = frame.cells
    for i = 1, n do
        local e = picks[i]
        if e then
            Fill(cells[i], nil, e.icon, priceTexts[i], e.count, e.quality, e.old, e.quest)
        else
            Fill(cells[i], nil, L.SAMPLE_ICON, priceTexts[i], nil, 1, i == 1)
        end
    end
    UpdateGlow(frame, n)
    frame:Show()
end

-- The shared EllesmereUI visibility checklist (Always / Never / Mouseover /
-- In Combat / Out of Combat / group and instance conditions) on the profile.
-- true = show, false = hide, "mouseover" = the dispatcher shows it on hover.
local function VisibilityVerdict()
    if not EllesmereUI.EvalVisibility then return true end
    return EllesmereUI.EvalVisibility(ns.DB())
end

local function Render()
    if unlocked then return RenderUnlocked() end
    local below = Get("freeBelow")
    local enoughRoom = below > 0 and free >= below and GetTime() >= fullUntil
    local offerStack = Get("stack") and stackSaves > 0 and not merging
    local shown = math.min(#picks, Get("count"))
    local vis = VisibilityVerdict()
    hasContent = not ((shown == 0 and not offerStack) or enoughRoom)
    -- Bags just filled up: flash the bar (only while it is on screen).
    local justFull = total > 0 and free == 0 and lastFree ~= nil and lastFree > 0
    lastFree = total > 0 and free or nil
    if not hasContent or vis == false then
        frame:Hide()
        return
    end
    Draw(frame, picks, shown, free, total, offerStack and stackSaves or 0)
    BS.CheckCells(shown)
    if justFull and Get("flashFull") then Flash(frame) end
    -- Mouseover: the dispatcher's hover scan owns Show/Hide.
    if vis ~= "mouseover" then frame:Show() end
end

-------------------------------------------------------------------------------
--  Self-check: one frame after a render, every shown cell must be on screen
--  (shown, anchored, opaque, sized, with an icon). A cell that is not gets
--  redrawn once; /bagcleaner debug prints what was wrong.
-------------------------------------------------------------------------------
local checkPending, healing, debugCells = false, false, false

local function CellProblem(b)
    if not b then return "missing" end
    if not b:IsShown() then return "hidden" end
    if b:GetNumPoints() == 0 then return "no anchor" end
    if not b:GetLeft() then return "no position" end
    if b:GetAlpha() < 0.99 then return ("alpha %.2f"):format(b:GetAlpha()) end
    if b:GetWidth() < 2 or b:GetHeight() < 2 then return ("size %.1fx%.1f"):format(b:GetWidth(), b:GetHeight()) end
    if not b.icon:GetTexture() then return "no icon" end
    if b.icon:GetAlpha() < 0.99 or not b.icon:IsShown() then return "icon hidden" end
end

local function CheckNow(shown)
    checkPending = false
    if not (frame and frame:IsShown()) or unlocked then return end
    for i = 1, shown do
        local why = CellProblem(frame.cells[i])
        if why then
            if debugCells then
                ns.Print(("debug: cell %d of %d was not drawn (%s)%s."):format(i, shown, why,
                    healing and ", still wrong after a redraw" or ", redrawing"))
            end
            if healing then
                healing = false
                return
            end
            healing = true
            Render()
            return
        end
    end
    if healing and debugCells then ns.Print("debug: redraw fixed it.") end
    healing = false
end

function BS.CheckCells(shown)
    if checkPending then return end
    checkPending = true
    C_Timer.After(0, function() CheckNow(math.min(shown, #frame.cells)) end)
end

function BS.ToggleDebug()
    debugCells = not debugCells
    ns.Print("debug messages " .. (debugCells and "on" or "off") .. ".")
end

local events = CreateFrame("Frame")

function Update()
    pendingScan = false
    if not (frame and Enabled()) then return end
    Scan()
    if missingInfo then
        events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    else
        events:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    end
    if merging then
        events:RegisterEvent("ITEM_LOCK_CHANGED")
        MergeStep()
    else
        events:UnregisterEvent("ITEM_LOCK_CHANGED")
    end
    Render()
end

function RequestScan()
    if pendingScan then return end
    pendingScan = true
    C_Timer.After(R.SCAN_DELAY, Update)
end
BS.RequestScan = function()
    if frame and Enabled() then RequestScan() end
end

events:SetScript("OnEvent", function(_, event, _, message)
    if event == "UI_ERROR_MESSAGE" then
        if message ~= ERR_INV_FULL and message ~= ERR_BAG_FULL then return end
        if Get("flashFull") and frame and frame:IsVisible() then Flash(frame) end
        fullUntil = GetTime() + R.FULL_SHOW
        C_Timer.After(R.FULL_SHOW + R.FULL_SLACK, RequestScan)
    elseif event == "MERCHANT_SHOW" then
        atMerchant = true
    elseif event == "MERCHANT_CLOSED" then
        atMerchant = false
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    elseif event == "EQUIPMENT_SETS_CHANGED" then
        setsDirty = true
    elseif event == "QUEST_LOG_UPDATE" then
        questDirty = true
    end
    RequestScan()
end)

-- Position: where Unlock Mode put the card (DEFAULT_POS until then).
local function SavedPos()
    local pos = Get("position")
    return type(pos) == "table" and pos.point and pos or DEFAULT_POS
end

local function Place()
    if not frame then return end
    local pos = SavedPos()
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
end

local function Build()
    if frame then return frame end
    frame = NewView(UIParent, true, OnClick, OnEnter, function()
        if not unlocked then StartMerge() end
    end)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    -- Hidden: restart the glow when shown again (animated glows stop while
    -- their frame is hidden).
    frame:HookScript("OnHide", function(self)
        local c1 = self.cells[1]
        local gw = c1 and rawget(c1, "glow")
        if gw then gw._dwGlowKey = nil end
    end)
    frame:Hide()
    _G.EllesmereUIBagCleanerBar = frame
    return frame
end

local function Apply()
    events:UnregisterAllEvents()
    if ns.Prices then ns.Prices.ApplyButton() end
    if not Enabled() then
        if frame then frame:Hide() end
        return
    end
    Build()
    Place()
    inCombat = UnitAffectingCombat("player")
    atMerchant = MerchantFrame and MerchantFrame:IsShown()
    events:RegisterEvent("BAG_UPDATE_DELAYED")
    events:RegisterEvent("MERCHANT_SHOW")
    events:RegisterEvent("MERCHANT_CLOSED")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("EQUIPMENT_SETS_CHANGED")
    events:RegisterEvent("QUEST_LOG_UPDATE")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    if (Get("onFull") and Get("freeBelow") > 0) or Get("flashFull") then
        events:RegisterEvent("UI_ERROR_MESSAGE")
    end
    setsDirty, questDirty = true, true
    Update()
end
BS.Apply = Apply
BS.ApplyPosition = Place

-------------------------------------------------------------------------------
--  Unlock Mode (EllesmereUI): the card is one element; its size follows the
--  settings, so it moves but does not resize.
-------------------------------------------------------------------------------
local UNLOCK_KEY = "EUI_BagCleaner"

local function IsUnlockActive()
    return EllesmereUI.IsUnlockModeActive and EllesmereUI:IsUnlockModeActive() or false
end

local function OnLogin()
    Apply()
    -- Old name (Bag Slots): carry its Pick Up Cheapest Item key over once, while
    -- the new action has none. Needs the old binding still known to the
    -- client, so it runs at the first login with Bag Cleaner.
    if not InCombatLockdown() and not GetBindingKey(BS.BINDING) then
        local a, b = GetBindingKey("EUI_BAGSLOTS_PICKUP")
        if a then
            SetBinding(a, BS.BINDING)
            if b then SetBinding(b, BS.BINDING) end
            SaveBindings(GetCurrentBindingSet())
        end
    end
    -- UI Accent Color changes repaint the Stack button and the glow live.
    if EllesmereUI.RegAccent then
        EllesmereUI.RegAccent({ type = "callback", fn = function()
            if frame and frame:IsShown() then RepaintAccent(frame) end
            if BS.RefreshPreview then BS.RefreshPreview() end
        end })
    end
    -- Shared visibility dispatcher: combat, group, zone and target changes.
    if EllesmereUI.RegisterVisibilityUpdater then
        EllesmereUI.RegisterVisibilityUpdater(function()
            if frame and Enabled() and not unlocked then Render() end
        end)
    end
    if EllesmereUI.RegisterMouseoverTarget then
        EllesmereUI.RegisterMouseoverTarget(Build(), function()
            return Enabled() and not unlocked and hasContent and VisibilityVerdict() == "mouseover"
        end)
    end
    if not (EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement) then return end
    EllesmereUI:RegisterUnlockElements({
        EllesmereUI.MakeUnlockElement({
            key      = UNLOCK_KEY,
            label    = "Bag Cleaner",
            group    = ns.UNLOCK_GROUP,
            order    = 900,
            noResize = true,
            isHidden = function() return not Enabled() end,
            getFrame = function()
                if not Enabled() then return nil end
                return Build()
            end,
            getSize = function()
                if not frame then return 100, 60 end
                return frame:GetWidth(), frame:GetHeight()
            end,
            savePos = function(_, point, relPoint, x, y)
                if not point then return end
                Set("position", { point = point, relPoint = relPoint, x = x, y = y })
                if not IsUnlockActive() then Place() end
            end,
            loadPos = SavedPos,
            clearPos = function()
                Set("position", nil)
                Place()
            end,
            applyPos = function()
                if Enabled() then
                    Build()
                    Place()
                end
            end,
        }),
    }, ns.FOLDER)
    if EllesmereUI.RegisterUnlockModeListener then
        EllesmereUI:RegisterUnlockModeListener(UNLOCK_KEY, function(active)
            unlocked = active and Enabled() or false
            if unlocked then
                Build()
                RenderUnlocked()
            elseif frame then
                Apply()
            end
        end)
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    OnLogin()
end)

-------------------------------------------------------------------------------
--  Options preview: the same card, drawn from samples in the options header.
--  No bags are read and no click acts. Hovering a sample shows its tooltip.
-------------------------------------------------------------------------------
local PREVIEW = { SLOTS = 52, FREE = 28, STACK = 1, MARGIN = 14, MIN_H = 110 }

local function Samples()
    local quest = { title = "Linen for Lakeshire", have = 2, need = 6 }
    local list = {
        { name = "Worn Leather Pants", icon = "Interface\\Icons\\INV_Pants_04", quality = 2, count = 1, vendor = 150 },
        { name = "Ruined Pelt", icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", quality = 0, count = 4, vendor = 59 },
        { name = "Tough Jerky", icon = "Interface\\Icons\\INV_Misc_Food_14", quality = 1, count = 20, vendor = 15,
          old = true },
        { name = "Linen Cloth", icon = "Interface\\Icons\\INV_Fabric_Linen_01", quality = 1, count = 7, vendor = 13,
          quest = quest },
        { name = "Jade Ring", icon = "Interface\\Icons\\INV_Jewelry_Ring_03", quality = 3, count = 1, vendor = 920 },
        { name = "Broken Fang", icon = "Interface\\Icons\\INV_Misc_Bone_08", quality = 0, count = 2, vendor = 26 },
        { name = "Light Leather", icon = "Interface\\Icons\\INV_Misc_LeatherScrap_03", quality = 1, count = 3,
          vendor = 15 },
        { name = "Rough Stone", icon = "Interface\\Icons\\INV_Stone_04", quality = 1, count = 9, vendor = 2 },
    }
    for i, e in ipairs(list) do
        e.bag, e.slot, e.value = 0, i, e.vendor * e.count
    end
    return list
end

local function PreviewEnter(self)
    local e = self.pick
    if not e then return end
    local c = ITEM_QUALITY_COLORS[e.quality] or ITEM_QUALITY_COLORS[1]
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(e.name, c.r, c.g, c.b)
    AddTipLines(e, nil)
    GameTooltip:Show()
end

local preview

local function RefreshPreview(force)
    local v = preview
    if not (v and (force or v.holder:IsVisible())) then return end
    local list, maxQuality, n = v.list, Get("maxQuality"), 0
    for i = 1, #v.samples do
        local e = v.samples[i]
        if e.quality <= maxQuality then
            n = n + 1
            list[n] = e
        end
    end
    for i = n + 1, #list do list[i] = nil end
    junkFirst, oldFirst = Get("junkFirst"), Get("oldFirst")
    table.sort(list, Cheaper)
    local view = v.view
    Draw(view, list, math.min(n, Get("count")), PREVIEW.FREE, PREVIEW.SLOTS, Get("stack") and PREVIEW.STACK or 0)
    view:SetAlpha(Enabled() and 1 or 0.4)
    local pw = v.holder:GetWidth()
    local roomW = ((pw and pw > 0) and pw or v.availableWidth or 600) - PREVIEW.MARGIN * 2
    local w, h = view:GetWidth(), view:GetHeight()
    local scale = 1
    if roomW > 0 and w > roomW then scale = roomW / w end
    view:SetScale(scale)
    local height = math.max(PREVIEW.MIN_H, h * scale + PREVIEW.MARGIN * 2)
    v.previewHeight = height
    v.holder:SetHeight(height)
    if v.onHeightChanged then v.onHeightChanged(height) end
end

local hookedParents = {}
-- topOffset: room left free above the preview (the search box strip).
function BS.CreateSettingsPreview(parent, availableWidth, onHeightChanged, topOffset)
    local v = preview
    if not v then
        v = { samples = Samples(), list = {} }
        v.holder = CreateFrame("Frame", nil, parent)
        v.view = NewView(v.holder, false, nil, PreviewEnter, nil)
        v.view:SetPoint("CENTER")
        v.holder:SetScript("OnShow", function() RefreshPreview() end)
        preview = v
    end
    v.availableWidth, v.onHeightChanged = availableWidth, onHeightChanged
    v.holder:SetParent(parent)
    -- Same layer as the options panel: a frame first made elsewhere must not
    -- keep a lower strata and draw underneath it.
    v.holder:SetFrameStrata(parent:GetFrameStrata())
    v.holder:SetFrameLevel(parent:GetFrameLevel() + 2)
    v.holder:ClearAllPoints()
    v.holder:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(topOffset or 0))
    v.holder:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(topOffset or 0))
    if not hookedParents[parent] then
        hookedParents[parent] = true
        local lastWidth
        parent:HookScript("OnSizeChanged", function(_, width)
            if width == lastWidth then return end
            lastWidth = width
            if v.holder:GetParent() == parent then RefreshPreview() end
        end)
    end
    v.holder:Show()
    RefreshPreview(true)
    return v
end

BS.RefreshPreview = function() RefreshPreview() end

-- A setting changed: rebuild the live card and the preview.
function BS.Changed()
    Apply()
    if unlocked and frame then RenderUnlocked() end
    RefreshPreview()
end

-- Ignore list helpers for BagCleaner_Ignore.lua
BS.Unignore = function(itemID)
    Ignored()[itemID] = nil
    BS.RequestScan()
end
BS.IgnoreItem = function(itemID)
    Ignored()[itemID] = time()
    BS.RequestScan()
end
BS.ClearIgnored = function()
    wipe(Ignored())
    BS.RequestScan()
end

function BS.Reset()
    ns.ResetProfile()
    BS.Changed()
end
