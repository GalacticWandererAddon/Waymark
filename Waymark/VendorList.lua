local _, ns = ...

-- "What they sell" (vendors) and "what they teach" (weapon masters, profession trainers): a window
-- beside the map, in the look of "What they carry" (BossLoot.lua; mock-up mockups\vendor-lists.html).
-- Opened from the quill menu of a townsfolk pin (Townsfolk.lua); someone who does both gets both rows.
-- Lists from Data\VendorStock.lua (tools\vendor_stock.py); names, icons and tooltips from the game.
-- Opening a vendor's own window keeps what they really had (WaymarkQuestDB.stock, with
-- townsfolk.record), and that list wins over the reference: Forever's vendors can differ.
-- Setting ns.db.townsfolk: stockPos (where the window was put), stockOther (false: hide the weapon
-- skills your class can't learn), stockKnown (false: hide the recipes you know).

local W = 310
local ROW = 34
local MAX_ROWS = 12  -- (more: the mouse wheel scrolls)
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DIGIT = {}
for i = 1, 64 do DIGIT[B64:byte(i)] = i - 1 end

-- item classes in the order you shop, each its heading
local GROUPS = {
    [0] = { 4, "Consumables" }, [6] = { 5, "Ammo" }, [11] = { 5, "Ammo" }, [5] = { 6, "Reagents" },
    [7] = { 7, "Trade goods" }, [1] = { 9, "Bags" }, [2] = { 10, "Weapons" }, [4] = { 11, "Armour" },
    [9] = { 12, "Recipes" },
}
local OTHER = { 13, "Odds and ends" }
-- gathering and trade tools are weapons to the game (a pick, a knife, a fishing pole): their own heading
local TOOLS = { 8, "Tools" }
local TOOL_ITEMS = { [2901] = true, [7005] = true, [5956] = true, [6219] = true, [6256] = true, [5060] = true,
    [4471] = true }  -- (Flint and Tinder: the cook's campfire, a reagent to the game)
-- the game's "consumables" as a player sorts them (Data\VendorStock.lua kinds; one we don't know: Consumables)
local KINDS = { { 1, "Food & drink" }, { 2, "Potions, scrolls & bandages" }, { 3, "Poisons" }, TOOLS, OTHER }
local function Group(item, classID, sub)
    if TOOL_ITEMS[item] or (classID == 2 and (sub == 14 or sub == 20)) then return TOOLS end
    local k = classID == 0 and ns.VendorStock and ns.VendorStock.kinds[item]
    if k then return KINDS[k] end
    return GROUPS[classID] or OTHER
end

local function Cfg() return ns.db.townsfolk end
local ItemInstant = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
local function SpellInfo(id)  -- name, icon
    if GetSpellInfo then
        local name, _, icon = GetSpellInfo(id)
        return name, icon
    end
    local t = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
    if t then return t.name, t.iconID end
end
local function Data() return ns.VendorStock or {} end
local function Learned()
    local db = WaymarkQuestDB
    return db and db.stock
end

-- a vendor's rows: { { item, price (nil: unknown), count, limited } }, and when you saw them yourself
local function SellRows(npc)
    local seen = Learned() and Learned()[npc]
    local out = {}
    if seen then
        for _, r in ipairs(seen.items) do out[#out + 1] = { r[1], r[2], r[3] or 1, r[4] } end
        return out, seen.day
    end
    local s, d = Data().sells and Data().sells[npc], Data()
    if not s then return nil end
    local i, limited = 1, false
    while i <= #s do
        if s:byte(i) == 33 then  -- "!"
            limited, i = true, i + 1
        else
            local a, b, c = s:byte(i, i + 2)
            local item = DIGIT[a] * 4096 + DIGIT[b] * 64 + DIGIT[c]
            local n = d.count[item] or 1
            out[#out + 1] = { item, d.price[item], n, limited }
            limited, i = false, i + 3
        end
    end
    return out
end

-- a trainer's list: { profession skill (0: weapon skills), { spell, cost, level, skill value, item made }... }
local function TeachRows(npc)
    local n = Data().teach and Data().teach[npc]
    return n and Data().lists[n]
end

-- what the quill menu offers for an NPC: { "sell", "teach" }, either, or none
function ns.StockKinds(npc)
    local out = {}
    if not npc then return out end
    if (Learned() and Learned()[npc]) or (Data().sells and Data().sells[npc]) then out[#out + 1] = "sell" end
    if TeachRows(npc) then out[#out + 1] = "teach" end
    return out
end

-- your rank in a profession by its name (nil: you don't have it)
local function SkillRank(name)
    if not (name and GetNumSkillLines and GetSkillLineInfo) then return end
    for i = 1, GetNumSkillLines() do
        local n, header, _, rank = GetSkillLineInfo(i)
        if n == name and not header then return rank end
    end
end

-- Window ---------------------------------------------------------------------------

local f, rows, labels = nil, {}, {}
local shown = {}  -- npc, name, sub, where, offset

local function Text(parent, font, r, g, b)
    local t = parent:CreateFontString(nil, "OVERLAY", font)
    t:SetTextColor(r, g, b)
    t:SetJustifyH("LEFT")
    t:SetWordWrap(false)
    return t
end

local function SavePos()
    local p, _, rp, x, y = f:GetPoint(1)
    Cfg().stockPos = { p, rp, x, y }
end

local function Place()
    f:ClearAllPoints()
    local pos = Cfg().stockPos
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    elseif BattlefieldMapFrame and BattlefieldMapFrame:IsShown() then
        f:SetPoint("TOPLEFT", BattlefieldMapFrame, "TOPRIGHT", 8, 0)
    else
        f:SetPoint("CENTER")
    end
end

local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, f)
    r:SetSize(W - 12, ROW)
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
    r.price = Text(r, "GameFontHighlight", 1, 1, 1)
    r.price:SetJustifyH("RIGHT")
    r.price:SetPoint("RIGHT", -6, 0)
    r.name = Text(r, "GameFontHighlight", 1, 1, 1)
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -1)
    r.name:SetPoint("RIGHT", r.price, "LEFT", -8, 0)
    r.sub = Text(r, "GameFontDisableSmall", 0.55, 0.55, 0.55)
    r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 1)
    r.sub:SetPoint("RIGHT", r.price, "LEFT", -8, 0)
    r:RegisterForClicks("LeftButtonUp")
    r:SetScript("OnEnter", function(self)
        self.hl:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.item then GameTooltip:SetItemByID(self.item) else GameTooltip:SetSpellByID(self.spell) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self)
        self.hl:Hide()
        GameTooltip:Hide()
    end)
    r:SetScript("OnClick", function(self)
        if not self.item then
            local link = GetSpellLink and GetSpellLink(self.spell)
            if link and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
            return
        end
        local _, link = GetItemInfo(self.item)
        if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
    end)
    r:EnableMouseWheel(true)
    r:SetScript("OnMouseWheel", function(_, d) f:GetScript("OnMouseWheel")(f, d) end)
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

local Show

local function Make()
    f = CreateFrame("Frame", "BFIVendorListFrame", UIParent, "BackdropTemplate")
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
    tinsert(UISpecialFrames, "BFIVendorListFrame")  -- (Escape closes it)

    f.title = Text(f, "GameFontNormal", 1, 0.82, 0)
    f.title:SetPoint("TOPLEFT", 10, -10)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -2, -3)
    f.where = Text(f, "GameFontDisableSmall", 0.55, 0.55, 0.55)
    f.where:SetJustifyH("RIGHT")
    f.where:SetPoint("RIGHT", close, "LEFT", -2, 0)
    f.who = Text(f, "GameFontHighlight", 1, 1, 1)
    f.who:SetPoint("TOPLEFT", 10, -32)
    f.whoSub = Text(f, "GameFontDisableSmall", 0.55, 0.55, 0.55)
    f.whoSub:SetJustifyH("RIGHT")
    f.whoSub:SetPoint("TOPRIGHT", -10, -34)

    f.other = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    f.other:SetSize(20, 20)
    f.other:SetScript("OnClick", function(self)
        local t = shown.toggle == "known" and "stockKnown" or "stockOther"
        Cfg()[t] = (not self:GetChecked()) and false or nil
        Show()
    end)
    f.otherText = Text(f, "GameFontNormalSmall", 0.79, 0.73, 0.56)
    f.otherText:SetText("show what I can't learn")
    f.otherText:SetPoint("LEFT", f.other, "RIGHT", 1, 0)
    f.foot = Text(f, "GameFontDisableSmall", 0.55, 0.55, 0.55)
    f.hint = Text(f, "GameFontDisableSmall", 0.55, 0.55, 0.55)
    f.hint:SetJustifyH("RIGHT")

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, d)
        local o = (shown.offset or 0) - d * 3
        shown.offset = math.max(0, math.min(o, (shown.total or 0) - MAX_ROWS))
        Show()
    end)
    f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    local pending
    f:SetScript("OnEvent", function()
        if pending or not f:IsShown() then return end
        pending = true
        C_Timer.After(0.2, function()
            pending = nil
            if f:IsShown() then Show() end
        end)
    end)
    Place()
end

-- the slot and type under an item's name, less what its heading already says
local function SubText(subType, equipLoc, heading)
    local slot = equipLoc and equipLoc ~= "" and _G[equipLoc]
    if subType then subType = subType:gsub("^One%-Handed ", ""):gsub("^Two%-Handed ", "") end  -- (the slot says it)
    if subType == "Miscellaneous" or subType == "Consumable" then subType = nil end  -- (the heading says more)
    local out, h = {}, (heading or ""):lower()
    for _, part in ipairs({ slot or "", subType or "" }) do
        if part ~= "" and h:find(part:lower(), 1, true) ~= 1 then out[#out + 1] = part end
    end
    return table.concat(out, " · ")
end

local function Money(c)
    if not c then return "" end
    if GetCoinTextureString then return GetCoinTextureString(c) end
    return tostring(c)
end

local function Known(spell)
    if IsPlayerSpell then return IsPlayerSpell(spell) end
    return IsSpellKnown and IsSpellKnown(spell)
end

-- the entries to list: { label } or { item/spell row }
local function SellEntries()
    local list, day = SellRows(shown.npc)
    local groups = {}
    for _, r in ipairs(list or {}) do
        local item = r[1]
        local _, _, _, _, icon, classID, sub = ItemInstant(item)
        local g = Group(item, classID, sub)
        local e = { item = item, icon = icon, price = r[2], count = r[3], limited = r[4], heading = g[2] }
        groups[g] = groups[g] or {}
        table.insert(groups[g], e)
    end
    local order = {}
    for g in pairs(groups) do order[#order + 1] = g end
    table.sort(order, function(a, b) return a[1] < b[1] end)
    local out = {}
    for _, g in ipairs(order) do
        if #order > 1 then out[#out + 1] = { label = g[2]:upper() } end
        for _, e in ipairs(groups[g]) do out[#out + 1] = e end
    end
    return out, day
end

local function Put(out, label, list)
    if #list == 0 then return end
    out[#out + 1] = { label = label }
    for _, e in ipairs(list) do out[#out + 1] = e end
end

-- weapon skills: what your class can learn, then what it can't (the toggle hides those)
local function WeaponEntries(list)
    local classID = select(3, UnitClass("player"))
    local bit = classID and 2 ^ (classID - 1) or 0
    local can, other = {}, {}
    for k = 2, #list do
        local r = list[k]
        local mask = Data().classes and Data().classes[r[1]] or 0
        local e = { spell = r[1], price = r[2], level = r[3], weapon = true }
        if math.floor(mask / bit) % 2 == 1 then can[#can + 1] = e else e.no = true other[#other + 1] = e end
    end
    local out = {}
    Put(out, "YOU CAN LEARN", can)
    if Cfg().stockOther ~= false then Put(out, ("Not for %ss"):format(UnitClass("player") or "your class"):upper(), other) end
    if #out == 0 then out[1] = { label = "NOTHING HERE YOUR CLASS CAN LEARN" } end
    return out, #other > 0 and "other" or nil
end

-- a profession's recipes and ranks: what you can learn now, later, and what you know (the toggle hides those)
local function RecipeEntries(list)
    local name = Data().skills and Data().skills[list[1]]
    local rank = SkillRank(name)
    local myLevel = UnitLevel("player") or 1
    local now, later, known = {}, {}, {}
    for k = 2, #list do
        local r = list[k]
        local e = { spell = r[1], price = r[2], level = r[3], need = r[4], item = r[5], skill = name, rank = rank }
        if Known(r[1]) then
            e.known = true
            known[#known + 1] = e
        elseif rank and rank >= r[4] and r[3] <= myLevel then
            now[#now + 1] = e
        else
            later[#later + 1] = e
        end
    end
    local out = {}
    Put(out, "YOU CAN LEARN", now)
    Put(out, rank and "LATER" or ("NEEDS " .. (name or "THE PROFESSION"):upper()), later)
    if Cfg().stockKnown ~= false then Put(out, "KNOWN", known) end
    if #out == 0 then out[1] = { label = "NOTHING NEW HERE" } end
    return out, #known > 0 and "known" or nil
end

local TOGGLE = { other = { "stockOther", "show what I can't learn" }, known = { "stockKnown", "show what I know" } }

function Show()
    if not f then Make() end
    local teach = shown.kind == "teach"
    f.title:SetText(teach and "What they teach" or "What they sell")
    f.where:SetText(shown.where or "")
    f.who:SetText(shown.name or "")
    f.whoSub:SetText(shown.sub or "")
    f.who:SetPoint("RIGHT", f.whoSub, "LEFT", -8, 0)

    local list, day, toggle = {}, nil, nil
    if teach then
        local rows = TeachRows(shown.npc) or { 0 }
        if rows[1] == 0 then list, toggle = WeaponEntries(rows) else list, toggle = RecipeEntries(rows) end
    else
        list, day = SellEntries()
    end
    shown.total, shown.toggle = #list, toggle
    local off = math.max(0, math.min(shown.offset or 0, #list - MAX_ROWS))
    shown.offset = off
    local y, n, nl = -52, 0, 0
    local myLevel = UnitLevel("player") or 1
    for k = off + 1, math.min(#list, off + MAX_ROWS) do
        local e = list[k]
        if e.label then
            nl = nl + 1
            Label(nl, e.label):SetPoint("TOPLEFT", 12, y - 2)
            y = y - 16
        else
            n = n + 1
            local r = Row(n)
            r.item, r.spell = e.item, e.spell
            local cr, cg, cb = 1, 1, 1
            local name, q, subType, equipLoc
            if e.item then
                local _
                name, _, q, _, _, _, subType, _, equipLoc = GetItemInfo(e.item)
                if not q and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, e.item) end
                if q and GetItemQualityColor then cr, cg, cb = GetItemQualityColor(q) end
            end
            r.edge:SetVertexColor(cr, cg, cb)
            r.edge:SetShown(q and q >= 2 or false)
            r.sub:SetTextColor(0.55, 0.55, 0.55)
            if e.spell then
                local sname, sicon = SpellInfo(e.spell)
                local icon = e.item and (select(5, ItemInstant(e.item)))
                r.icon:SetTexture(icon or sicon or 134400)
                r.name:SetText(sname or name or ("Spell " .. e.spell))
                local need = e.need and e.need > 0 and ("%s (%d)"):format(e.skill or "?", e.need)
                if e.known or (e.weapon and Known(e.spell)) then
                    r.sub:SetText("Known")
                    r.sub:SetTextColor(0.25, 0.75, 0.25)
                elseif need and not (e.rank and e.rank >= e.need) then
                    r.sub:SetText("Requires " .. need)
                    r.sub:SetTextColor(1, 0.25, 0.25)
                elseif e.level > myLevel then
                    r.sub:SetText(("Requires level %d"):format(e.level))
                    r.sub:SetTextColor(1, 0.25, 0.25)
                else
                    r.sub:SetText(e.weapon and "Weapon skill" or need or e.skill or "")
                end
                r:SetAlpha(e.no and 0.45 or 1)
            else
                r.icon:SetTexture(e.icon or (GetItemIcon and GetItemIcon(e.item)) or 134400)
                r.name:SetText(name or ("Item " .. e.item))
                local sub = SubText(subType, equipLoc, e.heading)
                if e.count and e.count > 1 then sub = ("%s%sin stacks of %d"):format(sub, sub ~= "" and " · " or "", e.count) end
                if e.limited then sub = "Limited" .. (sub ~= "" and " · " .. sub or "") end
                r.sub:SetText(sub)
                r:SetAlpha(1)
            end
            r.name:SetTextColor(cr, cg, cb)
            r.price:SetText(Money(e.price))
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 6, y)
            r:Show()
            y = y - ROW - 2
        end
    end
    if #list == 0 then
        nl = nl + 1
        Label(nl, "Nothing listed"):SetPoint("TOPLEFT", 12, y - 2)
        y = y - 18
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    for i = nl + 1, #labels do labels[i]:Hide() end

    y = y - 6
    local more = #list > MAX_ROWS and ("scroll: %d-%d of %d"):format(off + 1, math.min(#list, off + MAX_ROWS), #list)
    local t = TOGGLE[toggle]
    f.other:SetShown(t and true or false)
    f.otherText:SetShown(t and true or false)
    f.foot:SetShown(not teach)
    f.hint:ClearAllPoints()
    f.hint:SetPoint("TOPRIGHT", -10, y - 4)
    if t then
        f.other:ClearAllPoints()
        f.other:SetPoint("TOPLEFT", 8, y)
        f.other:SetChecked(Cfg()[t[1]] ~= false)
        f.otherText:SetText(t[2])
    end
    if teach then
        f.hint:SetText(more or "")
    else
        f.foot:ClearAllPoints()
        f.foot:SetPoint("TOPLEFT", 10, y - 4)
        if day then
            f.foot:SetText("seen by you, " .. date("%b %d", day))
            f.foot:SetTextColor(0.56, 0.75, 0.42)
        else
            f.foot:SetText(more and "" or "Prices before any discount")
            f.foot:SetTextColor(0.55, 0.55, 0.55)
        end
        f.hint:SetText(more or "Shift-click: link")
    end
    if teach and not t and not more then y = y + 8 end
    f:SetHeight(-y + 28)
    f:Show()
end

-- npc: its ID; name, sub: who they are; where: the map's name; kind: "sell" or "teach" (nil: the first)
function ns.OpenStock(npc, name, sub, where, kind)
    kind = kind or ns.StockKinds(npc)[1]
    if not kind then return end
    if not f then Make() end
    if shown.npc ~= npc or shown.kind ~= kind then shown.offset = 0 end
    shown.npc, shown.kind, shown.name, shown.sub, shown.where = npc, kind, name, sub, where
    Show()
end

-- The real stock, kept as you open a vendor's window ----------------------------------

local function NpcID()
    local guid = UnitGUID("npc")
    if not guid then return end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" then return tonumber(id) end
end

local function Keep()
    if not (Cfg().record and WaymarkQuestDB) then return end
    local id = NpcID()
    if not id then return end
    local items = {}
    for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
        local link = GetMerchantItemLink and GetMerchantItemLink(i)
        local item = link and tonumber(link:match("item:(%d+)"))
        if not item then return end  -- (still loading: MERCHANT_UPDATE looks again)
        local _, _, price, count, available, _, _, extended = GetMerchantItemInfo(i)
        items[#items + 1] = { item, (not extended) and price or nil, count or 1, (available and available >= 0) or nil }
    end
    if #items == 0 then return end
    WaymarkQuestDB.stock = WaymarkQuestDB.stock or {}
    WaymarkQuestDB.stock[id] = { day = time(), items = items }
    if f and f:IsShown() and shown.npc == id then Show() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_UPDATE")
events:SetScript("OnEvent", function() pcall(Keep) end)
