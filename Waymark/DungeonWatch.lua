local _, ns = ...

-- "Watch for": mob behaviour as short lines, in the user's own way of writing on the
-- Deadmines map: no full stops ("Odo calls his friends"). Not drawn on the map (the
-- user's call, 2026-11-02): a dev list (/waymark watch) the user writes from into the
-- journal with the quill. ns.DungeonWatchLines(instance) -> { { text, tip, who }, ... }.
-- From Data\DungeonWatch.lua (tools\dungeon_watch.py): who runs when hurt, who calls
-- others in, who fears, who silences. A monster's plain spell list is named by the game
-- here (GetSpellInfo), so fears and silences the scripts don't name are caught too.

local FEAR = { "Fear", "Psychic Scream", "Intimidating Shout", "Howl of Terror", "Terrify", "Terrifying",
               "Bellowing Roar", "Panic", "Scare", "Frightening Shout" }
local SILENCE = { "Silence", "Spell Lock", "Counterspell", "Arcane Torrent" }
local MAX_NAMES, MAX_LINE = 3, 42   -- (names in a line; its letters at most, names dropped to fit)

local function Match(name, list)
    if not name then return false end
    for _, w in ipairs(list) do
        if name == w or name:find("^" .. w .. "%f[%A]") then return true end
    end
    return false
end

-- "Defias Wizard" -> "Wizards" (the shared first word goes, see Short), "Odo the Blindwatcher" -> "Odo"
local function Plural(w)
    if w:find("man$") then return (w:gsub("man$", "men")) end
    if w:find("[^aeiou]y$") then return (w:gsub("y$", "ies")) end
    if w:find("[sxz]$") or w:find("[cs]h$") then return w .. "es" end
    if w:find("lf$") then return (w:gsub("lf$", "lves")) end
    return w .. "s"
end
local function Short(row, shared)
    local name = row[1]
    if row[8] then return name:match("^(.-) the ") or name end   -- (one of a kind: as named)
    if shared and name:find("^" .. shared .. " ") then name = name:sub(#shared + 2) end
    return Plural(name)
end

-- the names in a line: the common monsters first, then the ones of a kind; up to
-- MAX_NAMES, "and others" after; one of a kind alone -> singular verb. Line(names, one):
-- the whole line, kept to MAX_LINE letters by dropping names
local function Names(rows, Line)
    local sorted = {}
    for i, r in ipairs(rows) do sorted[i] = r end
    table.sort(sorted, function(a, b)
        if (a[8] or false) ~= (b[8] or false) then return not a[8] end
        return a[1] < b[1]
    end)
    -- (a first word most share goes: "Defias Wizard" -> "Wizards"; not a "Death's Head ...")
    local first, same = nil, 0
    for _, r in ipairs(sorted) do
        local w = r[1]:match("^(%S+) ")
        if not r[8] and w and not w:find("'s$") then
            if first == nil then first = w end
            if w == first then same = same + 1 end
        end
    end
    local shared = same >= 2 and first or nil
    local function Join(n)
        local out = {}
        for i = 1, n do out[i] = Short(sorted[i], shared) end
        if #sorted > n then return table.concat(out, ", ") .. " and others" end
        if n > 1 then return table.concat(out, ", ", 1, n - 1) .. " and " .. out[n] end
        return out[1]
    end
    local one = #sorted == 1 and sorted[1][8]
    local n = math.min(MAX_NAMES, #sorted)
    local s = Line(Join(n), one)
    while n > 1 and #s > MAX_LINE do
        n = n - 1
        s = Line(Join(n), one)
    end
    return s
end

local HER = { "^Lady ", "^Mistress ", "^Queen ", "^Princess ", "^Priestess ", "^Matron ", "^Sister ", "^Witch " }
local function Their(rows, one)
    if not one then return "their" end
    for _, p in ipairs(HER) do if rows[1][1]:find(p) then return "her" end end
    return "his"
end

-- each kind: its line (one: singular), and its words in the tooltip
local KINDS = {
    { key = "fear", line = function(n, one) return n .. (one and " sends you running" or " send you running") end },
    { key = "silence", line = function(n, one) return n .. (one and " steals your voice" or " steal your voice") end },
    { key = "calls", line = function(n, one, rows) return n .. (one and " calls " or " call ") .. Their(rows, one) .. " friends" end },
    { key = "runs", line = function(n, one) return n .. (one and " runs when hurt" or " run when hurt") end },
}

local function TipFor(rows, key)
    local lines = {}
    for _, r in ipairs(rows) do
        local what
        if key == "runs" then what = "runs at " .. (r[2] or 15) .. "% health"
        elseif key == "calls" then what = "calls for help"
        elseif key == "fear" then what = "fears: " .. (r.fear or "?")
        else what = "silences: " .. (r.silence or "?") end
        local casts = {}
        for _, s in ipairs(r[6] or {}) do
            if s ~= r.fear and s ~= r.silence then casts[#casts + 1] = s end
        end
        lines[#lines + 1] = r[1] .. ": " .. what .. (#casts > 0 and ("; casts " .. table.concat(casts, ", ")) or "")
    end
    return table.concat(lines, "\n")
end

-- an instance's lines, kept (the spell names settle once the game knows them)
local cache = {}
function ns.DungeonWatchLines(inst)
    local c = cache[inst]
    if c and c.done then return c.lines end
    local data = ns.DungeonWatchData and ns.DungeonWatchData[inst]
    if not data then return nil end
    local by, settled = { fear = {}, silence = {}, calls = {}, runs = {} }, true
    for _, r in ipairs(data) do
        r.fear, r.silence = r[4], r[5]
        for _, id in ipairs(r[7] or {}) do
            local name = GetSpellInfo and GetSpellInfo(id)
            if not name then settled = false end
            if not r.fear and Match(name, FEAR) then r.fear = name end
            if not r.silence and Match(name, SILENCE) then r.silence = name end
        end
        if r.fear then table.insert(by.fear, r) end
        if r.silence then table.insert(by.silence, r) end
        if r[3] then table.insert(by.calls, r) end
        if r[2] then table.insert(by.runs, r) end
    end
    local lines = {}
    for _, k in ipairs(KINDS) do
        local rows = by[k.key]
        if #rows > 0 then
            local line = Names(rows, function(n, one) return k.line(n, one, rows) end)
            local who = {}
            for _, r in ipairs(rows) do who[#who + 1] = r[1] end
            table.sort(who)
            lines[#lines + 1] = { line, TipFor(rows, k.key), table.concat(who, ", ") }
        end
    end
    cache[inst] = { lines = lines, done = settled }
    return lines
end

-- one monster's ways, for its dot's tooltip (DungeonMobDots.lua, with Shift): what to watch for
-- first (runs, calls friends, fears, silences), then what else it casts. nil: nothing known.
function ns.DungeonWatchFor(inst, name)
    local data = ns.DungeonWatchData and ns.DungeonWatchData[inst]
    if not data then return nil end
    ns.DungeonWatchLines(inst)                             -- (names its fears and silences)
    for _, r in ipairs(data) do
        if r[1] == name then
            local watch, casts = {}, {}
            if r[2] then watch[#watch + 1] = "Runs when hurt (" .. r[2] .. "% health)" end
            if r[3] then watch[#watch + 1] = "Calls for help" end
            if r.fear then watch[#watch + 1] = "Fears: " .. r.fear end
            if r.silence then watch[#watch + 1] = "Silences: " .. r.silence end
            local had = {}
            local function Cast(s)
                if s and s ~= r.fear and s ~= r.silence and not had[s] then had[s] = true casts[#casts + 1] = s end
            end
            for _, s in ipairs(r[6] or {}) do Cast(s) end
            for _, id in ipairs(r[7] or {}) do Cast(GetSpellInfo and GetSpellInfo(id)) end
            if #watch == 0 and #casts == 0 then return nil end
            return watch, casts
        end
    end
end

-- The dev list (/waymark watch), laid out like "What they carry" (BossLoot.lua), the look of our
-- dev windows: a tab per dungeon in the journal's order (Data\FoundNotes.lua; the rest after, by
-- name), the dungeon on the map (or the one you're in) picked first; a row per line, the monsters
-- in it under it; hovering a row shows each one, what it does and what else it casts. For the
-- user to write into the journal with the quill.
local W, ROW = 420, 34
local f, tabs, rows = nil, {}, {}
local shownInst

local function Text(parent, font, r, g, b)
    local t = parent:CreateFontString(nil, "OVERLAY", font)
    t:SetTextColor(r, g, b)
    t:SetJustifyH("LEFT")
    t:SetWordWrap(false)
    return t
end

local function DungeonName(id)
    local e = ns.DungeonEntrances and ns.DungeonEntrances[id]
    return e and e[1] or (GetRealZoneText and GetRealZoneText(id)) or tostring(id)
end

-- the dungeons with lines: the journal's first, in its order, then the rest by name
local function Ids()
    local out, seen = {}, {}
    local data = ns.DungeonWatchData or {}
    for _, dg in ipairs(ns.FoundNotes or {}) do
        local id = dg.instance
        if id and data[id] and not seen[id] then out[#out + 1], seen[id] = id, true end
    end
    local rest = {}
    for id in pairs(data) do if not seen[id] then rest[#rest + 1] = id end end
    table.sort(rest, function(a, b) return DungeonName(a) < DungeonName(b) end)
    for _, id in ipairs(rest) do out[#out + 1] = id end
    return out
end

local function Here()
    local key = ns.DungeonInkSurface and select(2, ns.DungeonInkSurface())
    local id = key and tonumber(key:match("^d(%d+):"))
    if id then return id end
    if IsInInstance() then return select(8, GetInstanceInfo()) end
end

local Show

local function Tab(i)
    local t = tabs[i]
    if t then return t end
    t = CreateFrame("Button", nil, f, "BackdropTemplate")
    t:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    t.text = Text(t, "GameFontNormalSmall", 0.79, 0.73, 0.56)
    t.text:SetPoint("CENTER")
    t:SetScript("OnClick", function(self) Show(self.inst) end)
    tabs[i] = t
    return t
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
    r.name = Text(r, "GameFontHighlight", 1, 1, 1)
    r.name:SetPoint("TOPLEFT", 6, -2)
    r.name:SetPoint("RIGHT", -6, 0)
    r.sub = Text(r, "GameFontDisableSmall", 0.55, 0.55, 0.55)
    r.sub:SetPoint("BOTTOMLEFT", 6, 3)
    r.sub:SetPoint("RIGHT", -6, 0)
    r:SetScript("OnEnter", function(self)
        self.hl:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.line, 1, 1, 1)
        for t in (self.tip or ""):gmatch("[^\n]+") do GameTooltip:AddLine(t, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self)
        self.hl:Hide()
        GameTooltip:Hide()
    end)
    rows[i] = r
    return r
end

local function Make()
    f = CreateFrame("Frame", "WaymarkDevWatchFor", UIParent, "BackdropTemplate")
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
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local p, _, rp, x, y = f:GetPoint(1)
        WaymarkDB.devWatchPos = { p, rp, x, y }
    end)
    tinsert(UISpecialFrames, "WaymarkDevWatchFor")  -- (Escape closes it)
    local pos = WaymarkDB.devWatchPos
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    elseif BattlefieldMapFrame and BattlefieldMapFrame:IsShown() then
        f:SetPoint("TOPLEFT", BattlefieldMapFrame, "TOPRIGHT", 8, 0)
    else
        f:SetPoint("CENTER")
    end
    f.title = Text(f, "GameFontNormal", 1, 0.82, 0)
    f.title:SetPoint("TOPLEFT", 10, -10)
    f.title:SetText("Watch for")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -2, -3)
    f.where = Text(f, "GameFontDisableSmall", 0.55, 0.55, 0.55)
    f.where:SetJustifyH("RIGHT")
    f.where:SetPoint("RIGHT", close, "LEFT", -2, 0)
    f.where:SetText("dev")
    f.dungeon = Text(f, "GameFontHighlight", 1, 1, 1)
    f.none = Text(f, "GameFontDisableSmall", 0.55, 0.55, 0.55)
    f.none:SetText("Nothing to watch for here")
    f.hint = Text(f, "GameFontDisableSmall", 0.55, 0.55, 0.55)
    f.hint:SetText("Hover: who, and what they cast")
    f.hint:SetJustifyH("RIGHT")
end

Show = function(inst)
    if not f then Make() end
    local ids = Ids()
    local found = false
    for _, id in ipairs(ids) do if id == inst then found = true end end
    if not found then inst = ids[1] end
    shownInst = inst
    -- tabs, wrapping
    local x, y = 8, -32
    for i, id in ipairs(ids) do
        local t = Tab(i)
        t.inst = id
        t.text:SetText(DungeonName(id))
        local w = math.min(W - 16, t.text:GetStringWidth() + 12)
        if x + w > W - 8 then x, y = 8, y - 20 end
        t:SetSize(w, 17)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", x, y)
        local on = id == inst
        t:SetBackdropColor(on and 0.18 or 0.11, on and 0.145 or 0.094, on and 0.086 or 0.07, 1)
        t:SetBackdropBorderColor(on and 0.63 or 0.24, on and 0.52 or 0.2, on and 0.27 or 0.14)
        t.text:SetTextColor(on and 1 or 0.79, on and 0.82 or 0.73, on and 0 or 0.56)
        t:Show()
        x = x + w + 3
    end
    for i = #ids + 1, #tabs do tabs[i]:Hide() end
    y = y - 26
    f.dungeon:ClearAllPoints()
    f.dungeon:SetPoint("TOPLEFT", 10, y)
    f.dungeon:SetText(inst and DungeonName(inst) or "")
    y = y - 18
    local lines = inst and ns.DungeonWatchLines(inst) or {}
    for i, l in ipairs(lines) do
        local r = Row(i)
        r.line, r.tip = l[1], l[2]
        r.name:SetText(l[1])
        r.sub:SetText(l[3] or "")
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 6, y)
        r:Show()
        y = y - ROW - 2
    end
    for i = #lines + 1, #rows do rows[i]:Hide() end
    f.none:ClearAllPoints()
    f.none:SetPoint("TOPLEFT", 12, y - 2)
    f.none:SetShown(#lines == 0)
    if #lines == 0 then y = y - 18 end
    y = y - 6
    f.hint:ClearAllPoints()
    f.hint:SetPoint("TOPRIGHT", -10, y - 4)
    f:SetHeight(-y + 24)
    f:Show()
end

function ns.ToggleDungeonWatchList()
    if f and f:IsShown() then f:Hide() return end
    Show(Here() or shownInst)
end
