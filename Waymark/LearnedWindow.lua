local _, ns = ...

-- "What you've learned": the quest givers, quests and monster spots learned as you play
-- (Learn.lua, WaymarkQuestDB), in a window like "What they carry" (BossLoot.lua;
-- mock-up mockups\learned-window.html). Two tabs: Quests, by the zone their giver stands
-- in (yours first), level in difficulty colours, who gives and who takes them in; and
-- Monsters, each learned monster, the quest it's for, its spots. Click a row: the map goes
-- there. Share them / Import... at the foot (Setups.lua's strings). Opened from the
-- Quests page and /bfi learned. Its place: ns.db.learned.winPos.

local W, LIST_H = 340, 330
local ROW, ZONE = 34, 20

local f, list, content, rowsUsed
local rows, heads = {}, {}
local tab = "quests"

local function Cfg() return ns.db.learned end
local function DB() return WaymarkQuestDB or {} end

local function Text(parent, font, r, g, b)
    local t = parent:CreateFontString(nil, "OVERLAY", font)
    t:SetTextColor(r, g, b)
    t:SetJustifyH("LEFT")
    t:SetWordWrap(false)
    return t
end

-- Data ---------------------------------------------------------------------------

-- the zone a map is in (its own name for a zone; a town's or cave's: the zone above)
local function Zone(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    local guard = 0
    while info and info.mapType and info.mapType > 3 and info.parentMapID and guard < 5 do
        info, guard = C_Map.GetMapInfo(info.parentMapID), guard + 1
    end
    return info and info.name or "Elsewhere"
end

-- a giver's first spot: its map, x, y
local function FirstSpot(spots)
    for mapID, s in pairs(spots or {}) do
        if type(s[1]) == "number" then return mapID, s[1], s[2] end
        if type(s[1]) == "table" then return mapID, s[1][1], s[1][2] end
    end
end

-- { { zone, { entry, ... } }, ... }: your zone first, then A-Z
local function Grouped(entries)
    local byZone, order = {}, {}
    for _, e in ipairs(entries) do
        if not byZone[e.zone] then
            byZone[e.zone] = {}
            order[#order + 1] = e.zone
        end
        table.insert(byZone[e.zone], e)
    end
    local here = Zone(C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    table.sort(order, function(a, b)
        if (a == here) ~= (b == here) then return a == here end
        return a < b
    end)
    local out = {}
    for _, z in ipairs(order) do
        table.sort(byZone[z], function(a, b)
            if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
            return (a.title or "") < (b.title or "")
        end)
        out[#out + 1] = { z, byZone[z] }
    end
    return out
end

local function Quests()
    local db, out = DB(), {}
    for qid, q in pairs(db.quests or {}) do
        local e = { id = qid, title = q.title or ("Quest " .. qid), level = q.level }
        for _, g in pairs(db.givers or {}) do
            if g.offers and g.offers[qid] and not e.from then
                e.from = g.name
                e.map, e.x, e.y = FirstSpot(g.spots)
            end
            if g.takes and g.takes[qid] and not e.to then
                e.to = g.name
                if not e.map then e.map, e.x, e.y = FirstSpot(g.spots) end
            end
        end
        e.zone = Zone(e.map)
        out[#out + 1] = e
    end
    return Grouped(out)
end

-- the quests that want a monster to be killed (our quest data), cached: it reads them all
local questsFor = {}
local function QuestsFor(npc)
    if questsFor[npc] then return questsFor[npc] end
    local d = ns.WorldQuestData
    local names = {}
    for _, q in pairs(d and d.quests or {}) do
        local o = q[18]
        if type(o) == "string" then
            local fn = loadstring("return " .. o)
            o = fn and select(2, pcall(fn))
        end
        if type(o) == "table" then
            for _, k in ipairs(o[1] or {}) do
                if k[1] == npc then names[#names + 1] = q[1] break end
            end
        end
        if #names >= 2 then break end
    end
    questsFor[npc] = table.concat(names, ", ")
    return questsFor[npc]
end

local function Monsters()
    local out = {}
    for id, m in pairs(DB().mobs or {}) do
        local n, mapID, x, y = 0, nil, nil, nil
        for mid, spots in pairs(m.spots or {}) do
            for _, s in ipairs(spots) do
                n = n + 1
                if not mapID then mapID, x, y = mid, s[1], s[2] end
            end
        end
        if n > 0 then
            out[#out + 1] = { id = id, title = m.name or ("Monster " .. id), map = mapID, x = x, y = y,
                              zone = Zone(mapID), spots = n, quests = QuestsFor(id) }
        end
    end
    return Grouped(out)
end

-- Rows ---------------------------------------------------------------------------

local function LevelColour(level)
    if level and GetQuestDifficultyColor then
        local c = GetQuestDifficultyColor(level)
        if c then return c.r, c.g, c.b end
    end
    return 1, 0.82, 0
end

-- the map there, as "find on map" opens it (docked: the big map first)
local function ShowOnMap(e)
    if not e.map then return end
    local map = BattlefieldMapFrame
    if map and not map:IsShown() and ToggleBattlefieldMap then ToggleBattlefieldMap() end
    local function Go()
        if ns.BrowseTo then ns.BrowseTo(e.map) elseif map then map:SetMapID(e.map) end
    end
    if ns.Docked and ns.Docked() and not (ns.MapIsBig and ns.MapIsBig()) and ns.ToggleBigMap then
        ns.ToggleBigMap()
        C_Timer.After(0.2, Go)
    else
        Go()
    end
end

local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, content)
    r:SetSize(W - 26, ROW)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(0.16, 0.14, 0.10, 1)
    r.hl:Hide()
    r.level = Text(r, "GameFontHighlightSmall", 1, 1, 1)
    r.level:SetJustifyH("RIGHT")
    r.level:SetWidth(22)
    r.level:SetPoint("TOPLEFT", 2, -4)
    r.name = Text(r, "GameFontHighlight", 1, 1, 1)
    r.name:SetPoint("TOPLEFT", 30, -3)
    r.name:SetPoint("RIGHT", -4, 0)
    r.sub = Text(r, "GameFontDisableSmall", 0.55, 0.55, 0.55)
    r.sub:SetPoint("BOTTOMLEFT", 30, 4)
    r.sub:SetPoint("RIGHT", -4, 0)
    r:SetScript("OnEnter", function(self)
        self.hl:Show()
        local e = self.entry
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(e.title, self.name:GetTextColor())
        if e.spots then
            if e.quests ~= "" then GameTooltip:AddLine("For " .. e.quests, 1, 1, 1, true) end
            GameTooltip:AddLine(e.spots .. (e.spots == 1 and " spot" or " spots") .. " in " .. e.zone, 0.8, 0.8, 0.8)
        else
            if e.level then GameTooltip:AddLine("Level " .. e.level, 1, 1, 1) end
            if e.from then GameTooltip:AddLine("From " .. e.from, 0.8, 0.8, 0.8) end
            if e.to then GameTooltip:AddLine("Handed in to " .. e.to, 0.8, 0.8, 0.8) end
        end
        if e.map then GameTooltip:AddLine("Click: show it on the map", 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self)
        self.hl:Hide()
        GameTooltip:Hide()
    end)
    r:SetScript("OnClick", function(self) ShowOnMap(self.entry) end)
    rows[i] = r
    return r
end

local function Head(i)
    local h = heads[i]
    if h then return h end
    h = CreateFrame("Frame", nil, content)
    h:SetSize(W - 26, ZONE)
    h.text = Text(h, "GameFontNormalSmall", 0.79, 0.73, 0.56)
    h.text:SetPoint("LEFT", 6, -2)
    h.rule = h:CreateTexture(nil, "ARTWORK")
    h.rule:SetHeight(1)
    h.rule:SetPoint("LEFT", h.text, "RIGHT", 8, 0)
    h.rule:SetPoint("RIGHT", -4, 0)
    h.rule:SetColorTexture(1, 1, 1, 1)
    if not pcall(h.rule.SetGradient, h.rule, "HORIZONTAL", CreateColor(0.36, 0.30, 0.20, 1), CreateColor(0.36, 0.30, 0.20, 0)) then
        h.rule:SetColorTexture(0.36, 0.30, 0.20, 0.6)
    end
    heads[i] = h
    return h
end

-- Window -------------------------------------------------------------------------

local function SavePos()
    local p, _, rp, x, y = f:GetPoint(1)
    Cfg().winPos = { p, rp, x, y }
end

local function Place()
    f:ClearAllPoints()
    local pos = Cfg().winPos
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    elseif BattlefieldMapFrame and BattlefieldMapFrame:IsShown() then
        f:SetPoint("TOPLEFT", BattlefieldMapFrame, "TOPRIGHT", 8, 0)
    else
        f:SetPoint("CENTER")
    end
end

local tabButtons = {}
local function Fill()
    for _, b in pairs(tabButtons) do
        local on = b.tab == tab
        b:SetBackdropColor(on and 0.17 or 0.11, on and 0.14 or 0.09, on and 0.09 or 0.07, 1)
        b:SetBackdropBorderColor(on and 0.63 or 0.24, on and 0.52 or 0.20, on and 0.27 or 0.14, 1)
        b.text:SetTextColor(on and 1 or 0.79, on and 0.82 or 0.73, on and 0 or 0.56)
    end
    local db = DB()
    local function Count(t)
        local n = 0
        for _ in pairs(t or {}) do n = n + 1 end
        return n
    end
    local nq, ng, nm = Count(db.quests), Count(db.givers), Count(db.mobs)
    f.counts:SetText(string.format("%d quests · %d givers · %d %s", nq, ng, nm, nm == 1 and "monster" or "monsters"))

    for _, r in ipairs(rows) do r:Hide() end
    for _, h in ipairs(heads) do h:Hide() end
    local groups = tab == "quests" and Quests() or Monsters()
    local y, ri, hi = 0, 0, 0
    for _, g in ipairs(groups) do
        hi = hi + 1
        local h = Head(hi)
        h:SetPoint("TOPLEFT", 0, -y)
        h.text:SetText(g[1]:upper())
        h:Show()
        y = y + ZONE
        for _, e in ipairs(g[2]) do
            ri = ri + 1
            local r = Row(ri)
            r.entry = e
            r:SetPoint("TOPLEFT", 0, -y)
            if e.spots then
                r.level:SetText("")
                r.name:SetText(e.title)
                r.name:SetTextColor(1, 0.5, 0.31)
                r.sub:SetText((e.quests ~= "" and ("for |cffb8a77f" .. e.quests .. "|r · ") or "")
                    .. e.spots .. (e.spots == 1 and " spot" or " spots"))
            else
                local cr, cg, cb = LevelColour(e.level)
                r.level:SetText(e.level or "")
                r.level:SetTextColor(cr, cg, cb)
                r.name:SetText(e.title)
                r.name:SetTextColor(cr, cg, cb)
                local parts = {}
                if e.from then parts[#parts + 1] = "from |cffb8a77f" .. e.from .. "|r" end
                if e.to then parts[#parts + 1] = "to |cffb8a77f" .. e.to .. "|r" end
                r.sub:SetText(table.concat(parts, " · "))
            end
            r:Show()
            y = y + ROW
        end
    end
    f.empty:SetShown(ri == 0)
    f.empty:SetText(tab == "quests" and "Nothing learned yet: talk to quest givers as you play, or import what someone shared."
        or "No monsters yet: a quest's monster the map can't place is learned when you loot or kill it.")
    content:SetHeight(math.max(1, y))
    list:SetVerticalScroll(math.min(list:GetVerticalScroll(), math.max(0, y - LIST_H)))
    rowsUsed = y
end

local function Make()
    f = CreateFrame("Frame", "BFILearnedFrame", UIParent, "BackdropTemplate")
    f:SetWidth(W)
    -- (with the settings window it opens from: above the map and bars, raised on a click)
    f:SetFrameStrata("FULLSCREEN")
    f:SetToplevel(true)
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
    tinsert(UISpecialFrames, "BFILearnedFrame")  -- (Escape closes it)

    local title = Text(f, "GameFontNormal", 1, 0.82, 0)
    title:SetPoint("TOPLEFT", 10, -10)
    title:SetText("What you've learned")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -2, -3)
    f.counts = Text(f, "GameFontDisableSmall", 0.55, 0.55, 0.55)
    f.counts:SetJustifyH("RIGHT")
    f.counts:SetPoint("RIGHT", close, "LEFT", -2, 0)

    -- the two tabs
    local prev
    for _, t in ipairs({ { "quests", "Quests" }, { "monsters", "Monsters" } }) do
        local b = CreateFrame("Button", nil, f, "BackdropTemplate")
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        b.text = Text(b, "GameFontNormalSmall", 0.79, 0.73, 0.56)
        b.text:SetPoint("CENTER")
        b.text:SetText(t[2])
        b:SetSize(b.text:GetStringWidth() + 18, 18)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 3, 0) else b:SetPoint("TOPLEFT", 8, -32) end
        b.tab = t[1]
        b:SetScript("OnClick", function(self)
            tab = self.tab
            list:SetVerticalScroll(0)
            Fill()
        end)
        tabButtons[#tabButtons + 1] = b
        prev = b
    end
    local rule = f:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(0.17, 0.15, 0.11, 1)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 4, -56)
    rule:SetPoint("TOPRIGHT", -4, -56)

    -- the list: scrolls with the mouse wheel
    list = CreateFrame("ScrollFrame", nil, f)
    list:SetPoint("TOPLEFT", 8, -60)
    list:SetSize(W - 16, LIST_H)
    content = CreateFrame("Frame", nil, list)
    content:SetSize(W - 26, 1)
    list:SetScrollChild(content)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        local top = math.max(0, (rowsUsed or 0) - LIST_H)
        self:SetVerticalScroll(math.max(0, math.min(top, self:GetVerticalScroll() - delta * ROW * 2)))
    end)
    f.empty = Text(f, "GameFontDisableSmall", 0.55, 0.55, 0.55)
    f.empty:SetWordWrap(true)
    f.empty:SetPoint("TOPLEFT", list, "TOPLEFT", 6, -10)
    f.empty:SetWidth(W - 40)

    -- the foot: share and import, the welcome note, the hint
    local foot = f:CreateTexture(nil, "ARTWORK")
    foot:SetColorTexture(0.17, 0.15, 0.11, 1)
    foot:SetHeight(1)
    foot:SetPoint("TOPLEFT", list, "BOTTOMLEFT", -4, -4)
    foot:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", 4, -4)
    local share = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    share:SetSize(110, 22)
    share:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -10)
    share:SetText("Share them")
    share:SetScript("OnClick", function() if ns.ShowLearnedExport then ns.ShowLearnedExport() end end)
    local import = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    import:SetSize(100, 22)
    import:SetPoint("LEFT", share, "RIGHT", 6, 0)
    import:SetText("Import...")
    import:SetScript("OnClick", function() if ns.ShowImport then ns.ShowImport() end end)
    local note = Text(f, "GameFontDisableSmall", 0.56, 0.52, 0.45)
    note:SetWordWrap(true)
    note:SetWidth(W - 20)
    note:SetPoint("TOPLEFT", share, "BOTTOMLEFT", 2, -7)
    note:SetText("Forever's quests are still being gathered: what you share is very welcome.")
    local hint = Text(f, "GameFontDisableSmall", 0.55, 0.55, 0.55)
    hint:SetJustifyH("RIGHT")
    hint:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", -2, -48)
    hint:SetText("Click: show it on the map")
    f:SetHeight(60 + LIST_H + 76)
    f:SetScript("OnShow", Fill)
    Place()
end

-- the window open, or closed again
function ns.ToggleLearnedWindow()
    if not ns.db then return end
    if not f then Make() end
    if f:IsShown() then f:Hide() return end
    f:Show()
end

-- something was learned or taken in: the open window follows
function ns.RefreshLearnedWindow()
    if f and f:IsShown() then Fill() end
end
