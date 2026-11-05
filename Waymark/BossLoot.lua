local _, ns = ...
local GetItemInfo = GetItemInfo or ns.GetItemInfo
local GetItemIcon = GetItemIcon or ns.GetItemIcon
local GetItemQualityColor = GetItemQualityColor or ns.GetItemQualityColor

-- "What they carry": a dungeon's boss loot in a window beside the map (mock-up
-- mockups\boss-loot.html, A). Opened from the quill menu of a boss on the dungeon
-- map or of a dungeon's entrance pin (Dungeon.lua). Data\WorldQuests.lua's
-- bossloot: each boss's own drops with their chances, best first, quest items
-- last. A tab per boss in kill order (Data\DungeonEncounters.lua); each item its
-- icon, name in quality colour, slot and type, chance. Hover: the game's item
-- tooltip; Shift-click links it, Ctrl-click tries it on. "Only what I can wear"
-- (wilds.lootWear) hides armour and weapons your class can't use.
-- Setting ns.db.wilds: bossLoot (the menu entries), lootWear, lootPos.

local W = 330
local ROW = 34
local QUEST = 12  -- (item class)

-- what each class can wear: weapon subclasses, best armour (1 cloth .. 4 plate),
-- shield, relic subclass
local WEAR = {
    WARRIOR = { w = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }, a = 4, shield = true },
    PALADIN = { w = { 0, 1, 4, 5, 6, 7, 8 }, a = 4, shield = true, relic = 7 },
    HUNTER  = { w = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }, a = 3 },
    SHAMAN  = { w = { 0, 1, 4, 5, 10, 13, 15 }, a = 3, shield = true, relic = 9 },
    ROGUE   = { w = { 2, 3, 4, 7, 13, 15, 16, 18 }, a = 2 },
    DRUID   = { w = { 4, 5, 10, 13, 15 }, a = 2, relic = 8 },
    PRIEST  = { w = { 4, 10, 15, 19 }, a = 1 },
    MAGE    = { w = { 7, 10, 15, 19 }, a = 1 },
    WARLOCK = { w = { 7, 10, 15, 19 }, a = 1 },
}
for _, c in pairs(WEAR) do
    local set = {}
    for _, s in ipairs(c.w) do set[s] = true end
    c.w = set
end

local function Cfg() return ns.db.wilds end

-- true unless it's armour or a weapon your class can't use
local function CanWear(classID, sub)
    local c = WEAR[select(2, UnitClass("player"))]
    if not (c and sub) then return true end
    if classID == 2 then return c.w[sub] or sub == 14 or sub == 20 end
    if classID == 4 then
        if sub == 6 then return c.shield end
        if sub >= 7 then return c.relic == sub end
        return sub <= c.a
    end
    return true
end

-- Forever's bosses the game's encounter table (the dungeon map's names) calls something else: the
-- loot is under the name players meet them by
local KNOWN_AS = { ["Mana Elemental"] = "Arcanic Enigma", ["Infurnus"] = "Magmatus", ["The Butcher"] = "The Baron" }

local function Rows(instanceID)
    local data = ns.OwnQuestDB and ns.OwnQuestDB()
    local rows = data and data.Wilds and data.Wilds.bossLoot[instanceID]
    return rows, data
end

-- the bosses with loot, in kill order
local function Bosses(instanceID)
    local rows = Rows(instanceID)
    if not rows then return {} end
    local byName, out, seen = {}, {}, {}
    for _, row in ipairs(rows) do byName[row[1]] = row end
    for _, b in ipairs(ns.DungeonEncounters and ns.DungeonEncounters[instanceID] or {}) do
        local n = KNOWN_AS[b[1]] or b[1]
        if byName[n] and not seen[n] then
            seen[n] = true
            out[#out + 1] = byName[n]
        end
    end
    for _, row in ipairs(rows) do
        if not seen[row[1]] then out[#out + 1] = row end
    end
    return out
end

function ns.HasBossLoot(instanceID, name)
    if Cfg().bossLoot == false then return false end
    name = KNOWN_AS[name] or name
    for _, row in ipairs(Bosses(instanceID)) do
        if not name or row[1] == name then return true end
    end
    return false
end

-- Window ---------------------------------------------------------------------------

local f, tabs, rows, labels = nil, {}, {}, {}
local shown = { inst = nil, boss = nil }

local function Text(parent, font, r, g, b)
    local t = parent:CreateFontString(nil, "OVERLAY", font)
    t:SetTextColor(r, g, b)
    t:SetJustifyH("LEFT")
    t:SetWordWrap(false)
    return t
end

local function SavePos()
    local p, _, rp, x, y = f:GetPoint(1)
    Cfg().lootPos = { p, rp, x, y }
end

local function Place()
    f:ClearAllPoints()
    local pos = Cfg().lootPos
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    elseif BattlefieldMapFrame and BattlefieldMapFrame:IsShown() then
        f:SetPoint("TOPLEFT", BattlefieldMapFrame, "TOPRIGHT", 8, 0)
    else
        f:SetPoint("CENTER")
    end
end

local function Tab(i)
    local t = tabs[i]
    if t then return t end
    t = CreateFrame("Button", nil, f, "BackdropTemplate")
    t:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    t.text = Text(t, "GameFontNormalSmall", 0.79, 0.73, 0.56)
    t.text:SetPoint("CENTER")
    t:SetScript("OnClick", function(self) ns.OpenBossLoot(shown.inst, self.boss) end)
    tabs[i] = t
    return t
end

local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, f)
    r:SetSize(W - 12, ROW)
    -- (under the icon and text: the HIGHLIGHT layer would draw over them)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(0.16, 0.14, 0.10, 1)
    r.hl:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(28, 28)
    r.icon:SetPoint("LEFT", 4, 0)
    r.edge = r:CreateTexture(nil, "OVERLAY")
    r.edge:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    r.edge:SetBlendMode("ADD")
    r.edge:SetSize(52, 52)
    r.edge:SetPoint("CENTER", r.icon)
    r.chance = Text(r, "GameFontHighlight", 1, 1, 1)
    r.chance:SetJustifyH("RIGHT")
    r.chance:SetPoint("RIGHT", -6, 0)
    r.name = Text(r, "GameFontHighlight", 1, 1, 1)
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -1)
    r.name:SetPoint("RIGHT", r.chance, "LEFT", -8, 0)
    r.sub = Text(r, "GameFontDisableSmall", 0.55, 0.55, 0.55)
    r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 1)
    r.sub:SetPoint("RIGHT", r.chance, "LEFT", -8, 0)
    r:RegisterForClicks("LeftButtonUp")
    r:SetScript("OnEnter", function(self)
        self.hl:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        ns.ItemTip(self.item, self.name:GetText())
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self)
        self.hl:Hide()
        GameTooltip:Hide()
    end)
    r:SetScript("OnClick", function(self)
        local _, link = GetItemInfo(self.item)
        if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
    end)
    rows[i] = r
    return r
end

local function Label(i, text)
    local l = labels[i]
    if not l then
        l = Text(f, "GameFontDisableSmall", 0.55, 0.55, 0.55)
        labels[i] = l
    end
    l:SetText(text)
    l:Show()
    return l
end

local function Make()
    f = CreateFrame("Frame", "BFIBossLootFrame", UIParent, "BackdropTemplate")
    ns.AddonWindow(f, function() if Cfg().lootPos then SavePos() end end)
    f:SetWidth(W)
    f:SetFrameStrata("HIGH")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.08, 0.067, 0.05, 0.96)
    f:SetBackdropBorderColor(0.48, 0.42, 0.30)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function() f:StopMovingOrSizing() SavePos() end)
    tinsert(UISpecialFrames, "BFIBossLootFrame")  -- (Escape closes it)

    f.title = Text(f, "GameFontNormal", 1, 0.82, 0)
    f.title:SetPoint("TOPLEFT", 10, -10)
    f.title:SetText("What they carry")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -2, -3)
    f.where = Text(f, "GameFontDisableSmall", 0.55, 0.55, 0.55)
    f.where:SetJustifyH("RIGHT")
    f.where:SetPoint("RIGHT", close, "LEFT", -2, 0)
    f.boss = Text(f, "GameFontHighlight", 1, 1, 1)
    f.bossSub = Text(f, "GameFontDisableSmall", 0.55, 0.55, 0.55)

    f.wear = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    f.wear:SetSize(20, 20)
    f.wear:SetScript("OnClick", function(self)
        Cfg().lootWear = self:GetChecked() and true or nil
        ns.OpenBossLoot(shown.inst, shown.boss)
    end)
    f.wearText = Text(f, "GameFontNormalSmall", 0.79, 0.73, 0.56)
    f.wearText:SetText("only what I can wear")
    f.wearText:SetPoint("LEFT", f.wear, "RIGHT", 1, 0)
    f.hint = Text(f, "GameFontDisableSmall", 0.55, 0.55, 0.55)
    f.hint:SetText("Shift-click: link")
    f.hint:SetJustifyH("RIGHT")

    f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    local pending
    f:SetScript("OnEvent", function()
        if pending or not f:IsShown() then return end
        pending = true
        C_Timer.After(0.2, function()
            pending = nil
            if f:IsShown() then ns.OpenBossLoot(shown.inst, shown.boss) end
        end)
    end)
    Place()
end

-- the slot and type under an item's name
local function SubText(classID, subType, equipLoc)
    if classID == QUEST then return "Quest item" end
    local slot = equipLoc and equipLoc ~= "" and _G[equipLoc]
    if subType then subType = subType:gsub("^One%-Handed ", ""):gsub("^Two%-Handed ", "") end  -- (the slot says it)
    if slot and subType and subType ~= "" and subType ~= "Miscellaneous" then return slot .. " · " .. subType end
    return slot or subType or ""
end

function ns.OpenBossLoot(instanceID, name)
    name = KNOWN_AS[name] or name
    local bosses = Bosses(instanceID)
    if #bosses == 0 then return end
    if not f then Make() end
    local row = bosses[1]
    for _, b in ipairs(bosses) do if b[1] == name then row = b end end
    shown.inst, shown.boss = instanceID, row[1]
    local _, data = Rows(instanceID)
    local entrance = ns.DungeonEntrances and ns.DungeonEntrances[instanceID]
    f.where:SetText(entrance and entrance[1] or "")

    -- tabs, wrapping
    local x, y = 8, -32
    for i, b in ipairs(bosses) do
        local t = Tab(i)
        t.boss = b[1]
        t.text:SetText(b[1])
        local w = math.min(W - 16, t.text:GetStringWidth() + 12)
        if x + w > W - 8 then x, y = 8, y - 20 end
        t:SetSize(w, 17)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", x, y)
        local on = b[1] == row[1]
        t:SetBackdropColor(on and 0.18 or 0.11, on and 0.145 or 0.094, on and 0.086 or 0.07, 1)
        t:SetBackdropBorderColor(on and 0.63 or 0.24, on and 0.52 or 0.2, on and 0.27 or 0.14)
        t.text:SetTextColor(on and 1 or 0.79, on and 0.82 or 0.73, on and 0 or 0.56)
        t:Show()
        x = x + w + 3
    end
    for i = #bosses + 1, #tabs do tabs[i]:Hide() end
    y = y - 26

    f.boss:ClearAllPoints()
    f.boss:SetPoint("TOPLEFT", 10, y)
    f.boss:SetText(row[1])
    y = y - 18

    -- items: gear (filtered), then quest items
    local wear = Cfg().lootWear
    f.wear:SetChecked(wear and true or false)
    local gear, quest = {}, {}
    for i, item in ipairs(row[2]) do
        local _, _, q, _, _, _, subType, _, equipLoc, _, _, classID, sub = GetItemInfo(item)
        if not q and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, item) end
        local e = { item = item, q = q, classID = classID, subType = subType, equipLoc = equipLoc, chance = row[3][i] }
        if classID == QUEST then
            quest[#quest + 1] = e
        elseif not (wear and classID and not CanWear(classID, sub)) then
            gear[#gear + 1] = e
        end
    end
    local n, nl = 0, 0
    local function Put(e)
        n = n + 1
        local r = Row(n)
        r.item = e.item
        r.icon:SetTexture(GetItemIcon and GetItemIcon(e.item) or 134400)
        local cr, cg, cb = 1, 1, 1
        if e.q and GetItemQualityColor then cr, cg, cb = GetItemQualityColor(e.q) end
        r.name:SetText(GetItemInfo(e.item) or data.Item.name(e.item) or ("Item " .. e.item))  -- (the game's name: Forever's, ours while it loads)
        r.name:SetTextColor(cr, cg, cb)
        r.edge:SetVertexColor(cr, cg, cb)
        r.edge:SetShown(e.q and e.q >= 2)
        r.sub:SetText(e.classID and SubText(e.classID, e.subType, e.equipLoc) or ns.GAP_SHORT)
        local c = ns.ChanceText and ns.ChanceText(e.chance) or ""
        r.chance:SetText(c)
        if c == "always" then r.chance:SetTextColor(0.55, 0.55, 0.55) else r.chance:SetTextColor(1, 1, 1) end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 6, y)
        r:Show()
        y = y - ROW - 2
    end
    for _, e in ipairs(gear) do Put(e) end
    if #gear == 0 then
        nl = nl + 1
        Label(nl, "Nothing here you can wear"):SetPoint("TOPLEFT", 12, y - 2)
        y = y - 18
    end
    if #quest > 0 then
        nl = nl + 1
        y = y - 4
        Label(nl, "QUEST ITEMS"):SetPoint("TOPLEFT", 12, y)
        y = y - 14
        for _, e in ipairs(quest) do Put(e) end
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    for i = nl + 1, #labels do labels[i]:Hide() end

    y = y - 6
    f.wear:ClearAllPoints()
    f.wear:SetPoint("TOPLEFT", 8, y)
    f.hint:ClearAllPoints()
    f.hint:SetPoint("TOPRIGHT", -10, y - 4)
    f:SetHeight(-y + 28)
    f:Show()
end
