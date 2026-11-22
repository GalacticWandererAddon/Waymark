local _, ns = ...

-- The book's camps on the map (2026-11-11; cleared by the user and on the ship list since 2026-11-14, Forever).
-- Each "before we go" page of the found notes was written somewhere: the tower on Sentinel Hill, the inn at
-- Kharanos, the Pool of Tears. At that spot on its zone map, a small campfire in the wanderer's ink: brown before
-- Blackfathom, the deep's blue-black after it, brown again at Thorium Point. It asks for nothing: no glow, no
-- ping, no mark of what you've read. Hovering it names the place in his words and lists who asked the company
-- there (your own quests for that dungeon: taken, done, not taken, as on a dungeon's door); a click opens the
-- page. What it gives a player is the dungeon's errands at the place they're picked up; the story is there for
-- whoever reads on.
--   A few textures and buttons on the zone you're looking at (two at most, the Barrens three), redrawn only when
--   the map, its size or the setting changes. ns.db.notebook.camps = false: off.
--   Places: CAMPS below, { zone map, x, y } in percent; WaymarkDB.campEdits[id] over them (dev: /waymark camp <id>
--   puts one where the cursor is on the map, or where you stand; in the dev copy, Ctrl + drag a campfire;
--   /waymark camp list prints them; tools/bake_camps.py writes them into this table for shipping).

-- Where a camp goes (the user, 2026-11-14): where the page's drawing shows it. Where the drawing names no spot, a
-- sensible place to camp outside the dungeon, or the nearest small town. Never in the middle of a busy town,
-- where the pointer rests on quest givers (its tooltip must not come up by accident), and clear of other pins.
local CAMPS = {
    deadmines   = { 1436, 59.6, 50.6 },  -- the foot of Sentinel Hill, on the road in from Lakeshire
    wailing     = { 1413, 49.5, 38.6 },  -- the oasis under the caverns' rock (the drawing)
    ragefire    = { 1411, 46.4, 14.8 },  -- before Orgrimmar's gate (the drawing: three figures walking in)
    thanes      = { 1426, 54.6, 37.2 },  -- under Ironforge's gates, in the snow
    ruins       = { 1420, 67.6, 62.6 },  -- off the Bulwark road, east of the old capital (an Alliance company: never by Brill)
    shadowfang  = { 1421, 47.6, 64.0 },  -- off the Pyrewood road, short of the village (worgen by night), the keep above
    blackfathom = { 1440, 17.0, 21.7 },  -- Zoram Strand, the arch in the surf (the drawing; the page names Auberdine, a day behind)
    stockade    = { 1453, 41.5, 59.0 },  -- Stormwind, the canals
    excavation  = { 1437, 38.0, 51.0 },  -- Whelgar's dig
    gnomeregan  = { 1426, 45.0, 50.2 },  -- Kharanos' edge (the drawing is Kharanos: the tower and the lodge)
    dalaran     = { 1416, 20.5, 86.0 },  -- the lake shore below Dalaran
    kraul       = { 1413, 49.4, 84.2 },  -- Bael Modan's edge: the Explorers' League dig by the thorns (Alliance dwarves, not Dark Iron)
    monastery   = { 1420, 79.3, 41.6 },  -- Faol's Rest, under the monastery (they come north from the Bulwark)
    downs       = { 1413, 47.2, 90.0 },  -- below the Kraul
    uldaman     = { 1418, 42.6, 18.2 },  -- the Badlands, the dig
    zulfarrak   = { 1446, 47.2, 24.6 },  -- the dunes between Gadgetzan and the troll city
    maraudon    = { 1443, 33.6, 56.6 },  -- the Valley of Spears
    temple      = { 1435, 63.0, 52.5 },  -- the Pool of Tears' west shore, the temple in the lake (the drawing)
    depths      = { 1427, 36.2, 33.4 },  -- under Thorium Point, the mountain ahead
    spire       = { 1428, 80.6, 66.4 },  -- west of Morgan's Vigil, the spire in sight
    diremaul    = { 1444, 55.6, 46.4 },  -- the road in under the great trees, the ruin ahead
    scholomance = { 1422, 59.0, 79.0 },  -- Darrowmere's shore, Caer Darrow across the water
    stratholme  = { 1423, 78.6, 63.0 },  -- outside Light's Hope
}
local GLYPH = ns.MEDIA .. "Notes\\Camp"
local BROWN, DEEP = { 0.27, 0.16, 0.07 }, { 0.15, 0.19, 0.25 }  -- (as Ink.lua's sepia and blue-black on maps)
-- (the small fire and its thread of smoke, with the map zoomed out; zoomed in it grows with the land, though
-- less than the land does: 14 x 7 at every zoom was too small to find, the user's first look)
local TALL, WIDE = 20, 14   -- (Camp.tga is 44 x 64)
local HOVER = 0.35         -- (seconds the pointer must rest on it before its tooltip: never by accident)

local map, host
local DragStart, DragStop
local buttons, used = {}, 0
local edits = 0  -- (a camp moved: drawn again)

local function Cfg() return ns.db and ns.db.notebook end

local function Where(id)
    local e = WaymarkDB and WaymarkDB.campEdits and WaymarkDB.campEdits[id]
    return e or CAMPS[id]
end

-- (a campsite the player hid, right-click > hide campsite: ns.db.notebook.campsHidden[id]; /waymark camp show
-- brings them all back)
local function Hidden(id)
    local c = Cfg()
    return c and c.campsHidden and c.campsHidden[id] or false
end
local function HiddenCount()
    local n = 0
    for _ in pairs(Cfg() and Cfg().campsHidden or {}) do n = n + 1 end
    return n
end

-- the book's pages with a camp on this map: { dg, ink }
local function On(mapID)
    local out, i, deep = {}, 0, false
    for _, dg in ipairs(ns.FoundNotes or {}) do
        if not dg.hidden then
            i = i + 1
            local c = dg.before and Where(dg.id)
            if c and c[1] == mapID and not Hidden(dg.id) and (ns.FOREVER or not dg.forever)
               and not (ns.NotebookLocked and ns.NotebookLocked(i)) then
                -- (a page's "before" was written on the road there: Blackfathom's own still in brown)
                out[#out + 1] = { dg, (deep and not dg.sepia) and DEEP or BROWN, c }
            end
            if dg.id == "blackfathom" then deep = true end
        end
    end
    return out
end

local function Tip(self)
    local dg = self.dg
    local b = dg.before
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(b.where or "A camp", 0.93, 0.82, 0.6, true)
    GameTooltip:AddLine(b.title or ("Before " .. (dg.title or dg.tab or dg.id)), 1, 1, 1)
    local ok, qs = pcall(ns.NotebookQuests or function() end, dg.instance)
    if ok and qs and #qs > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Quests from the found notes", 1, 0.82, 0)
        for _, q in ipairs(qs) do
            local okP, pv = pcall(ns.QuestPreview or function() end, q.quest)
            local name = okP and pv and pv.name or q.who or ("quest " .. q.quest)
            if q.state == "have" then
                GameTooltip:AddDoubleLine(name, "in your log", 1, 1, 1, 0.25, 1, 0.25)
            elseif q.state == "done" then
                GameTooltip:AddDoubleLine(name, "done", 0.55, 0.55, 0.55, 0.55, 0.55, 0.55)
            else
                GameTooltip:AddDoubleLine(name, "not taken", 0.8, 0.8, 0.8, 0.55, 0.55, 0.55)
            end
        end
    end
    if ns.Hints then ns.Hints({ { "Click", "the page" }, { "Right-click", "more" } }) end
    GameTooltip:Show()
end

-- (the mark darkens at once; its words wait until the pointer has rested on it)
local function Enter(self)
    self.glyph:SetAlpha(1)
    self.over = (self.over or 0) + 1
    local n = self.over
    C_Timer.After(HOVER, function()
        if self.over == n and self:IsShown() and self:IsMouseOver() then Tip(self) end
    end)
end

local function Leave(self)
    self.over = (self.over or 0) + 1
    GameTooltip:Hide()
    self.glyph:SetAlpha(0.85)
end

-- Left: the page; again with the book open at it, the book is put away. Right: a list with "hide campsite".
local function Click(self, button)
    if self.dragged and GetTime() - self.dragged < 0.3 then return end  -- (the end of a dev drag, not a click)
    GameTooltip:Hide()
    self.over = (self.over or 0) + 1  -- (no tooltip over what the click brought up)
    local dg = self.dg
    if button == "RightButton" then
        if not ns.QuillMenu then return end
        ns.QuillMenu({ { "hide campsite", function()
            local c = Cfg()
            if not c then return end
            c.campsHidden = c.campsHidden or {}
            c.campsHidden[dg.id] = true
        end } })
        return
    end
    if not ns.OpenNotebook then return end
    if ns.NotebookBeforeOpen and ns.NotebookBeforeOpen() == dg.instance and ns.ToggleNotebook then
        ns.ToggleNotebook()
    else
        ns.OpenNotebook(dg.instance, nil, true)
    end
end

-- dev: Ctrl + drag a campfire to a new spot (the controls' one scheme: Ctrl + drag moves anything movable)
local function Cursor()
    if not (map and map.GetNormalizedCursorPosition) then return end
    local x, y = map:GetNormalizedCursorPosition()
    if not (x and y) then return end
    return math.min(1, math.max(0, x)), math.min(1, math.max(0, y))
end
local function Follow(self)
    local x, y = Cursor()
    if not x then return end
    self:ClearAllPoints()
    self:SetPoint("BOTTOM", host, "TOPLEFT", x * self.W, -y * self.H - 3 * self.k)
end
DragStart = function(self)
    if not (IsControlKeyDown() and self.W) then return end
    self.over = (self.over or 0) + 1
    GameTooltip:Hide()
    self.moving = true
    self:SetScript("OnUpdate", Follow)
end
DragStop = function(self)
    if not self.moving then return end
    self.moving = nil
    self:SetScript("OnUpdate", nil)
    self.dragged = GetTime()
    local x, y = Cursor()
    local mapID = map:GetMapID()
    if not (x and mapID) then edits = edits + 1 return end
    WaymarkDB.campEdits = WaymarkDB.campEdits or {}
    WaymarkDB.campEdits[self.dg.id] = { mapID, math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10 }
    edits = edits + 1
    print(string.format("|cff33ff99Waymark camps:|r %s at %.1f, %.1f on map %d (tools/bake_camps.py ships it)",
        self.dg.id, x * 100, y * 100, mapID))
end

local function Button()
    used = used + 1
    local b = buttons[used]
    if not b then
        b = CreateFrame("Button", nil, host)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b.glyph = b:CreateTexture(nil, "ARTWORK")
        b.glyph:SetPoint("BOTTOM")
        b.glyph:SetTexture(GLYPH)
        b:SetScript("OnEnter", Enter)
        b:SetScript("OnLeave", Leave)
        b:SetScript("OnClick", Click)
        -- (dev copy only, DevBar.lua loaded: Ctrl + drag moves it, saved in WaymarkDB.campEdits; the user
        -- 2026-11-22: "a dev tool that lets me easily move the campsites", baked by tools/bake_camps.py)
        if ns.DevCommands then
            b:RegisterForDrag("LeftButton")
            b:SetScript("OnDragStart", DragStart)
            b:SetScript("OnDragStop", DragStop)
        end
        buttons[used] = b
    end
    return b
end

local function Draw()
    used = 0
    local c = Cfg()
    local mapID = map:GetMapID()
    local story = not ns.BookKindNow or ns.BookKindNow() == "story"
    local list = (c and c.camps ~= false and story and mapID) and On(mapID) or {}
    if #list > 0 then
        local canvas = map:GetCanvas()
        local W, H = canvas:GetWidth(), canvas:GetHeight()
        if W and W > 0 and H and H > 0 then
            host:SetParent(canvas)
            host:SetAllPoints(canvas)
            -- (a camp is always there, so it gives way to everything that comes and goes: with the marks printed on
            -- the map, under the quest ground, the nodes and the wilds, and, as all map art, under every pin. A pin
            -- or a mark over it takes the pointer, and its tooltip, first. Level 8 until 2026-11-14)
            host:SetFrameLevel(ns.ArtLevel and ns.ArtLevel(map, "marks") or canvas:GetFrameLevel() + 1)
            host:Show()
            local k = UIParent:GetEffectiveScale() / math.max(0.01, host:GetEffectiveScale())
            -- (how far the map is zoomed in: the whole map's width on the screen over the window's)
            local sc = map.ScrollContainer
            if sc and sc:GetWidth() > 0 then
                local zoom = W * host:GetEffectiveScale() / (sc:GetWidth() * math.max(0.01, sc:GetEffectiveScale()))
                -- (0.7 and no ceiling until 2026-11-19: zoomed in ten times, as a docked map often is, the fire stood
                -- 100 px tall; a player on CurseForge called the marks "absolutely massive". Now 44 px at the most)
                k = k * math.min(2.2, math.max(1, zoom) ^ 0.4)
            end
            for _, row in ipairs(list) do
                local b = Button()
                b.dg = row[1]
                b.glyph:SetVertexColor(row[2][1], row[2][2], row[2][3])
                b.glyph:SetAlpha(0.85)
                b.glyph:SetSize(WIDE * k, TALL * k)
                b.W, b.H, b.k = W, H, k  -- (for a dev drag)
                -- (what the pointer can touch: the fire itself and a little round it, not the smoke)
                b:SetSize(14 * k, 12 * k)
                b:ClearAllPoints()
                b:SetPoint("BOTTOM", host, "TOPLEFT", row[3][2] / 100 * W, -row[3][3] / 100 * H - 3 * k)
                b:Show()
            end
        end
    end
    for k = used + 1, #buttons do buttons[k]:Hide() end
    if used == 0 then host:Hide() end
end

local function Signature()
    local c = Cfg()
    local canvas = map:GetCanvas()
    return table.concat({ tostring(map:GetMapID()), tostring(c and c.camps), tostring(ns.BookKindNow and ns.BookKindNow()),
        tostring(math.floor(canvas:GetWidth() + 0.5)), string.format("%.3f", host:GetEffectiveScale()), tostring(edits), tostring(HiddenCount()) }, ":")
end

function ns.SetupCamps(m)
    map = m
    host = CreateFrame("Frame", nil, map:GetCanvas())
    host:EnableMouse(false)
    host:Hide()
    local last, t = nil, 0
    local ticker = ns.TimedFrame and ns.TimedFrame("Camps tick", map) or CreateFrame("Frame", nil, map)
    ticker:SetScript("OnUpdate", function(_, e)
        t = t + e
        if t < (ns.Tick and ns.Tick(0.25) or 0.25) then return end
        t = 0
        if not ns.db then return end
        local ok, sig = pcall(Signature)
        if ok and sig ~= last then
            last = sig
            local okD, err = pcall(Draw)
            if not okD and ns.Log then ns.Log("Camps:", tostring(err)) end
        end
    end)
    -- (for /bfi check)
    function ns.CampsInfo() return string.format("%d camps drawn", used) end
end

-- dev: a camp put where the cursor is on the Battlefield map, or where you stand (/waymark camp <id>);
-- /waymark camp list: the moved ones, as rows for CAMPS; /waymark camps: the marks on or off;
-- /waymark camp show: the campsites a right-click hid, back
function ns.CampDev(arg)
    local P = function(...) print("|cff33ff99Waymark camps:|r", ...) end
    if arg == "" then
        local c = Cfg()
        if not c then return end
        c.camps = c.camps == false and true or false
        P(c.camps and "shown" or "hidden")
        return
    end
    if arg == "show" then
        if Cfg() then Cfg().campsHidden = nil end
        P("every hidden campsite is back")
        return
    end
    WaymarkDB.campEdits = WaymarkDB.campEdits or {}
    if arg == "reset" then
        WaymarkDB.campEdits = nil
        edits = edits + 1
        P("every moved campsite is back where Camps.lua has it")
        return
    end
    if arg == "list" then
        local n = 0
        for id, e in pairs(WaymarkDB.campEdits) do
            P(string.format("    %s = { %d, %.1f, %.1f },", id, e[1], e[2], e[3]))
            n = n + 1
        end
        if n == 0 then P("none moved") end
        return
    end
    if not CAMPS[arg] then P("no page called " .. arg) return end
    if not map then return end
    local mapID, x, y = map:GetMapID(), nil, nil
    if map.ScrollContainer and map.ScrollContainer:IsMouseOver() and map.GetNormalizedCursorPosition then
        x, y = map:GetNormalizedCursorPosition()
    elseif mapID and C_Map and C_Map.GetPlayerMapPosition then
        local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
        if ok and pos then x, y = pos:GetXY() end
    end
    if not (mapID and x and y) then P("no spot: hover the Battlefield map, or stand in the zone it shows") return end
    WaymarkDB.campEdits[arg] = { mapID, math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10 }
    edits = edits + 1
    P(string.format("%s at %.1f, %.1f on map %d", arg, x * 100, y * 100, mapID))
end
