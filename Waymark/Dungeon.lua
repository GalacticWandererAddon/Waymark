local _, ns = ...

-- Caves and dungeons on the Battlefield Map.
--  followMaps: when the game puts you on a cave, dungeon or other small map
--              that has art, switch the Battlefield Map to it (and back out
--              to the zone when you leave). The game's own arrow and pins then
--              work there as far as the client allows.
--  fallback:   inside an instance whose map the game won't switch to, draw the
--              dungeon's map ourselves: Blizzard's art (tile data from
--              OpenMap, MIT) with our boss spots. No player arrow there: the
--              game doesn't tell addons where you are (see the minimap view).
--  showInside: open the Battlefield Map when you enter a dungeon.
--  bosses / bossList: markers and a list of the bosses (the game's encounter
--              list; spots on Blizzard's art are ours, /bfi bosses place).
-- /bfi probe prints what the client reports, to see what's possible.

local function Cfg() return ns.db.dungeon end

local SMALL_MAP_TYPES = {}  -- filled in Setup, from Enum.UIMapType
local switchedTo            -- mapID we switched the Battlefield Map to

local function MapType(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    return info and info.mapType, info
end

local function HasArt(mapID)
    return C_Map.GetMapArtID and C_Map.GetMapArtID(mapID) ~= nil
end

-- Follow caves/dungeons -------------------------------------------------------

local function Follow(map)
    if not Cfg().followMaps then return end
    if ns.Browsing and ns.Browsing() then return end  -- (another map you're looking at)
    if ns.HoldOnTaxi and ns.HoldOnTaxi() then return end
    local best = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not best then return end
    local current = map:GetMapID()
    if SMALL_MAP_TYPES[MapType(best) or -1] and HasArt(best) then
        if current ~= best then
            switchedTo = best
            map:SetMapID(best)
        end
    elseif switchedTo and current == switchedTo then
        -- left the cave: back to the zone the game puts you on
        switchedTo = nil
        local zone = MapUtil and MapUtil.GetMapParentInfo and MapUtil.GetMapParentInfo(best, Enum.UIMapType.Zone, true)
        map:SetMapID(zone and zone.mapID or best)
    end
end

-- Fallback dungeon map -------------------------------------------------------

local overlay, tiles, floorText, prevBtn, nextBtn
local floorCount  -- docked: the floor's "(2/3)", bottom middle between the arrows (floorText keeps the name)
local titleName, titleCounter  -- the floor shown: its name and "(2/5)", for the header
local floors, floorIndex, shownInstance
-- the dungeon the Bosses slip is about while it is unpinned from the map and no dungeon map is up (the one you
-- stand in, else the one last shown); nil whenever a dungeon map is up (then it is shownInstance)
local listInst
local preview  -- a dungeon you clicked on the zone map, shown from outside (further down)
local viewBtn  -- the Map / Minimap switch
local zoneView -- inside: right-clicked out to the dungeon's zone (instance ID), when browsing can't hold it
local coversIn -- the instance whose map this view has covered (ns.DungeonArtHome)
local manualFloor = false  -- you picked a floor with < >: stop auto-picking

-- the floor the monsters you meet say you're on (DungeonWhere.lua): the game doesn't say inside
local function GuessedFloor()
    local inst, floor = ns.DungeonWhere and ns.DungeonWhere()
    if not (inst and inst == shownInstance and floors) then return end
    for i, f in ipairs(floors) do
        if (f.index or i) == floor then return i end
    end
end

-- the floor whose name (or wing) appears in what the game calls where you are:
-- SM's floors are its wings ("Graveyard"), others are areas inside
local function MatchFloor()
    local here = {}
    for _, fn in ipairs({ GetSubZoneText, GetMinimapZoneText, GetZoneText, GetRealZoneText }) do
        local ok, s = pcall(fn)
        if ok and s and s ~= "" then here[#here + 1] = s:lower() end
    end
    local lfgID = select(10, GetInstanceInfo())
    if lfgID and GetLFGDungeonInfo then
        local ok, s = pcall(GetLFGDungeonInfo, lfgID)
        if ok and type(s) == "string" then here[#here + 1] = s:lower() end
    end
    -- an exact name first: inside WC the zone is "Wailing Caverns", which is also
    -- part of a longer floor name ("Wailing Caverns (Entrance)"); the dungeon map must win
    for i, f in ipairs(floors) do
        for _, key in ipairs(f.outside and {} or { f.name, f.wing }) do
            if key then
                key = key:lower()
                for _, s in ipairs(here) do
                    if s == key then return i end
                end
            end
        end
    end
    for i, f in ipairs(floors) do
        for _, key in ipairs(f.outside and {} or { f.name, f.wing }) do
            if key then
                key = key:lower()
                for _, s in ipairs(here) do
                    if s:find(key, 1, true) or key:find(s, 1, true) then return i end
                end
            end
        end
    end
end

-- The bosses: the game's DungeonEncounter table names each instance's in kill
-- order (Data\DungeonEncounters.lua, the names ENCOUNTER_END gives). Where they
-- stand on Blizzard's maps is ours, placed by hand: Data\DungeonBosses.lua, with
-- your own placing (/bfi bosses place, ns.db.bossSpots) over it; false = removed.
-- (the bosses, then the rare elites, then friendly NPCs; kind[name] = "rare" /
-- "friend", nil for a boss)
local function Encounters(instanceID)
    local out, rares, friends, kind = {}, {}, {}, {}
    for _, e in ipairs(ns.DungeonEncounters and ns.DungeonEncounters[instanceID] or {}) do
        if not (e.forever and not ns.FOREVER) and not (e.era and ns.FOREVER) then
            if e.rare then
                rares[#rares + 1] = e[1]
                kind[e[1]] = "rare"
            elseif e.friend then
                friends[#friends + 1] = e[1]
                kind[e[1]] = "friend"
            else
                out[#out + 1] = e[1]
            end
        end
    end
    -- (the shipped kill order over the game's (Data\DungeonBosses.lua, baked from yours), then your own
    -- over that: /bfi bosses place, the wheel over a name. ns.db.bossOrder[instance] = names; any it
    -- doesn't name keep their place after it)
    for _, mine in ipairs({ ns.DungeonBossOrder and ns.DungeonBossOrder[instanceID] or false,
                            ns.db and ns.db.bossOrder and ns.db.bossOrder[instanceID] or false }) do
        if mine then
            local has, ordered = {}, {}
            for _, n in ipairs(out) do has[n] = true end
            for _, n in ipairs(mine) do
                if has[n] then ordered[#ordered + 1] = n has[n] = false end
            end
            for _, n in ipairs(out) do if has[n] then ordered[#ordered + 1] = n end end
            out = ordered
        end
    end
    for _, n in ipairs(rares) do out[#out + 1] = n end
    for _, n in ipairs(friends) do out[#out + 1] = n end
    return out, kind
end

local KIND_COLOR = { rare = { 0.7, 0.82, 1 }, friend = { 0.45, 1, 0.45 } }
-- the painted skull for a rare or friendly NPC: greyed, then tinted a little
-- (still the map's ink, just cooler or greener)
local SKULL_TINT = { rare = { 0.9, 0.92, 0.98 }, friend = { 0.7, 0.95, 0.62 } }  -- (rare: silver, 2026-10-31)

-- Your notes on the bosses: shift-click one on the map or in the list; shown
-- in its tooltip, in the parchment's ink colour
local NOTE_COLOR = { 0.93, 0.82, 0.6 }
local function Note(instanceID, name)
    local t = instanceID and ns.db.bossNotes[instanceID]
    return t and t[name]
end
local RefreshNotes  -- (whatever shows a note, once one changed: further down)
local function EditNote(instanceID, name)
    if not (instanceID and name) then return end
    ns.Ask({ text = "Your note on " .. name .. ":", edit = Note(instanceID, name) or "", ok = SAVE or "Save",
             onAccept = function(text)
                 local t = ns.db.bossNotes[instanceID] or {}
                 ns.db.bossNotes[instanceID] = t
                 t[name] = text ~= "" and text or nil
                 if RefreshNotes then RefreshNotes() end
             end })
end

-- { floor (OpenMap's index), x, y } or nil
local function Spot(instanceID, name)
    local mine = ns.db.bossSpots[instanceID]
    if mine and mine[name] ~= nil then return mine[name] or nil end
    local shipped = ns.DungeonBosses and ns.DungeonBosses[instanceID]
    return shipped and shipped[name]
end

-- each Blizzard floor's bosses from the spots: { name, x, y, n = kill order }
local function SpotBosses(list, instanceID)
    for _, f in ipairs(list) do
        if f.tiles then f.bosses = {} end
    end
    local names, kind = Encounters(instanceID)
    for n, name in ipairs(names) do
        local s = Spot(instanceID, name)
        for _, f in ipairs(list) do
            if s and f.tiles and f.index == s[1] then
                f.bosses[#f.bosses + 1] = { name = name, x = s[2], y = s[3], n = n, kind = kind[name] }
            end
        end
    end
end

-- the area outside a dungeon that has its own cave map (Blizzard's micro map,
-- same 4 x 3 tiles): [instance ID] = { the caves' uiMapIDs in OpenMap's caves,
-- in the game's floor order (UiMapGroupMember) }
local BLACKROCK = { 33, 34, 35 }
local OUTSIDE = {
    [36] = { 55 },        -- Deadmines: the mine under Moonbrook
    [43] = { 11 },        -- Wailing Caverns
    [70] = { 16 },        -- Uldaman
    [189] = { 19 },       -- Scarlet Monastery
    [349] = { 67, 68 },   -- Maraudon
    [229] = BLACKROCK, [230] = BLACKROCK, [409] = BLACKROCK, [469] = BLACKROCK,
}
-- a cave of several levels: each level's name (the game's floor names)
local CAVE_FLOOR = {
    [33] = "Blackrock Spire level", [34] = "Blackrock Caverns level", [35] = "Blackrock Depths level",
    [67] = "The Wicked Grotto", [68] = "Foulspore Cavern",
}
-- the other way round: a cave's dungeon and its floor there ("out", "out2"); Blackrock's
-- caves go with its lowest instance ID (Cave.lua: the dungeon map in these caves)
local OUTSIDE_OF = {}
for inst, caves in pairs(OUTSIDE) do
    for n, cave in ipairs(caves) do
        if not OUTSIDE_OF[cave] or inst < OUTSIDE_OF[cave][1] then
            OUTSIDE_OF[cave] = { inst, n == 1 and "out" or ("out" .. n) }
        end
    end
end
function ns.DungeonOutsideOf(caveID)
    local o = caveID and OUTSIDE_OF[caveID]
    if o then return o[1], o[2] end
end

-- OpenMap's floors: 12 tiles each (4 x 3 of 256 px, the picture 1002 x 668 of it);
-- index = its place in OpenMap's list (what a boss spot names); the outside
-- caves come first, index "out", "out2", ...
local function OpenMapFloors(instanceID)
    local data = ns.MapDungeonMaps and ns.MapDungeonMaps[instanceID]
    if not data then return end
    local out = {}
    for _, uiMapID in ipairs(OUTSIDE[instanceID] or {}) do
        local cave = ns.MapCaves and ns.MapCaves[uiMapID]
        if cave and cave[11] and #cave[11] == 12 then
            local n = #out + 1
            out[n] = { tiles = cave[11], name = "Outside" .. (CAVE_FLOOR[uiMapID] and (": " .. CAVE_FLOOR[uiMapID]) or ""),
                index = n == 1 and "out" or ("out" .. n), outside = true }
        end
    end
    local outside = #out
    for i, f in ipairs(data) do
        if f.tiles and #f.tiles == 12 then out[#out + 1] = { tiles = f.tiles, name = f.name, index = i } end
    end
    if #out == outside then return end
    if #out == 0 then return end
    SpotBosses(out, instanceID)
    return out
end

-- Pan and zoom, like the cave view: the floor's picture sits on a canvas whose
-- units are the picture's own pixels; the canvas is scaled and moved inside the
-- clipping overlay. zoom 1 = the floor covers the whole view, as the zone maps
-- do (MapControls' CoverScale): no empty bands, the long side trimmed. Wheel:
-- zoom; left-drag: pan; right-click: out to the dungeon's zone (ns.DungeonZoneView;
-- from outside, back to the zone). Never panned past the picture's edges.
local canvas
local PW, PH = 1002, 668               -- the picture's size (Blizzard's dungeon maps)
local zoom = 1
local centerX, centerY = 0, 0          -- view centre, picture px from the picture's centre (y down)
local drag

local function ClampMid(v, lo, hi)
    if lo > hi then return (lo + hi) / 2 end
    return math.max(lo, math.min(hi, v))
end

local ResizeMarkers  -- (boss markers, further down: sized with the map)

local function Layout()
    local W, H = overlay:GetWidth(), overlay:GetHeight()
    if not (W and W > 0 and H and H > 0) then return end
    local k = math.max(W / PW, H / PH) * zoom
    local hw, hh = W / (2 * k), H / (2 * k)
    centerX = ClampMid(centerX, -PW / 2 + hw, PW / 2 - hw)
    centerY = ClampMid(centerY, -PH / 2 + hh, PH / 2 - hh)
    canvas:SetScale(k)
    canvas:ClearAllPoints()
    -- (canvas units; screen y points up, picture y down)
    canvas:SetPoint("CENTER", overlay, "CENTER", -centerX, centerY)
    if ResizeMarkers then ResizeMarkers(k) end
    return k
end

-- the floor buttons < >: either side of the header while it carries the floor's name (on the
-- header itself, so the map's clipping can't cut them off), else either side of the floor text
-- over the map's top-edge strip (Dock.lua), which lay over their upper half: its strata and above
-- it, whatever theirs was (fstack, the user 2026-11-07: the strip HIGH 22, the arrows under it)
local function OverRim(b)
    local strip = ns.MapRimTop and ns.MapRimTop()
    if not (b and strip) then return end
    b:SetFrameStrata(strip:GetFrameStrata())
    b:SetFrameLevel(strip:GetFrameLevel() + 2)
end

local function PlaceSteps(show)
    local h = ns.ZoneHeader
    local onHeader = show and h and ns.IsShown("zoneName") and h:IsShown()
    local parent = onHeader and h or floorText:GetParent()
    for i, b in ipairs({ prevBtn, nextBtn }) do
        if b:GetParent() ~= parent then b:SetParent(parent) end
        b:ClearAllPoints()
        if onHeader and ns.Docked and ns.Docked() then
            -- (docked the header fills the square's top: beside it the arrows sat on the gear. Under its
            -- middle instead, the two side by side)
            b:SetFrameLevel(h:GetFrameLevel() + 5)
            if i == 1 then b:SetPoint("TOPRIGHT", h, "BOTTOM", -1, -1) else b:SetPoint("TOPLEFT", h, "BOTTOM", 1, -1) end
        elseif onHeader then
            b:SetFrameLevel(h:GetFrameLevel() + 5)
            if i == 1 then b:SetPoint("RIGHT", h, "LEFT", -2, 0) else b:SetPoint("LEFT", h, "RIGHT", 2, 0) end
        elseif floorCount and floorCount:IsShown() then
            if i == 1 then b:SetPoint("RIGHT", floorCount, "LEFT", -4, 0) else b:SetPoint("LEFT", floorCount, "RIGHT", 4, 0) end
        elseif i == 1 then
            b:SetPoint("RIGHT", floorText, "LEFT", -6, 0)
        else
            b:SetPoint("LEFT", floorText, "RIGHT", 6, 0)
        end
        OverRim(b)
        b:SetShown(show and true or false)
    end
end

-- (Dock.lua, whenever it places the frame's rim: docking or undocking moves the header, and the
-- arrows went on beside it, under the gear, the user)
local ShowFloor, shownDocked  -- (below; docked or not when the floor was last laid out)
function ns.DungeonButtonsOverRim()
    local docked = ns.Docked and ns.Docked() or false
    if overlay and docked ~= shownDocked then
        -- (docked or undocked: the floor's name and count go elsewhere, and the view may change with it
        -- (the minimap view is the undocked map's only): all of it again, once the dock has settled.
        -- Only the floor laid out again left the name hidden after a dock, the user)
        shownDocked = docked
        C_Timer.After(0, function() if ns.UpdateDungeon then ns.UpdateDungeon() end end)
    elseif prevBtn and floors and #floors > 1 and overlay and overlay:IsShown() then
        PlaceSteps(prevBtn:IsShown())
    end
    OverRim(prevBtn) OverRim(nextBtn)
    OverRim(viewBtn)
end

ShowFloor = function()
    local f = floors[floorIndex]
    shownDocked = ns.Docked and ns.Docked() or false
    for _, tex in ipairs(tiles) do tex:Hide() end
    if f.tiles then
        -- 12 tiles of 256 px (4 x 3); the picture is their top-left 1002 x 668,
        -- so the last column and row are trimmed to it
        PW, PH = 1002, 668
        for i = 1, 12 do
            local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
            local pw, ph = math.min(256, PW - col * 256), math.min(256, PH - row * 256)
            local tex = tiles[i]
            tex:SetTexture(f.tiles[i])
            tex:SetTexCoord(0, pw / 256, 0, ph / 256)
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", canvas, "TOPLEFT", col * 256, -row * 256)
            tex:SetSize(pw, ph)
            tex:Show()
        end
    end
    canvas:SetSize(PW, PH)
    Layout()
    local count = #floors
    -- (a floor without a name of its own: the dungeon's, numbered where it has several such)
    local e = ns.DungeonEntrances and shownInstance and ns.DungeonEntrances[shownInstance]
    local unnamed = 0
    for _, g in ipairs(floors) do if not g.name then unnamed = unnamed + 1 end end
    local name = f.name or (e and (e[1] .. (unnamed > 1 and (" " .. (f.index or floorIndex)) or "")))
        or ("Floor " .. floorIndex)
    -- inside, the header already names where you are: no second copy of it here
    local sub = GetSubZoneText and GetSubZoneText() or ""
    local zone = GetZoneText and GetZoneText() or ""
    local said = not preview and ns.IsShown("zoneName")
        and (name:lower() == sub:lower() or name:lower() == zone:lower())
    local counter = count > 1 and ("(" .. floorIndex .. "/" .. count .. ")") or ""
    titleName, titleCounter = name, counter
    -- (docked, the header hidden: the name top middle, shaded and outlined; the count and the arrows at
    -- the bottom middle, clear of the gear and buttons on a small square, the user 2026-11-07)
    local split = ns.Docked and ns.Docked() and not ns.IsShown("zoneName") and count > 1
    floorCount:SetShown(split)
    floorCount:SetText(split and counter or "")
    floorText:SetFont(floorText.font, floorText.size, split and "OUTLINE" or "")
    if ns.IsShown("zoneName") then
        floorText:SetText("")  -- (the header carries the floor's name: ZoneName.lua, ns.DungeonFloorTitle)
    elseif split then
        floorText:SetText(name)
    elseif count <= 1 and not (preview and f.name) then
        floorText:SetText("")  -- one floor: nothing to tell apart (a preview keeps the dungeon's name)
    else
        floorText:SetText(said and counter or (name .. (counter ~= "" and ("  " .. counter) or "")))
    end
    if ns.UpdateZoneName then ns.UpdateZoneName() end
    PlaceSteps(count > 1)
    floorText.shade(split and floorText:GetText() ~= "")
    floorCount.shade(false)  -- (none under the count, the user: its outline is enough)
end

-- Boss markers -----------------------------------------------------------------
-- Where the bosses are: our spots on Blizzard's art (SpotBosses),
-- the skull painted on that dungeon's own maps (cut out of the game's tile at
-- runtime, Data\DungeonSkulls.lua); a rare's greyed to a cool blue, a friendly
-- NPC's to green (SKULL_TINT). A killed one is crossed out in red ink, so the map shows where you've been.

local markerLayer
local bossMarkers = {}
local markerByName = {}  -- [boss name] = its marker on this floor

-- this run's kills, kept in the saved variables so a /reload or a death and
-- run back keeps them; a new run (another dungeon, or an hour outside) clears them
local function Run() return ns.db.dungeonRun end
local function Kills() return Run().kills end
-- (a dungeon looked at from outside isn't this run's)
local function KilledHere(name)
    return Run().id == (shownInstance or listInst) and Kills()[name:lower()] or false
end

local placing = false  -- /bfi bosses place: a click on the map puts the picked boss there
local picked           -- the boss a click places
local UpdateList       -- (the list, further down)

local function Marker(i)
    local m = bossMarkers[i]
    if m then return m end
    m = CreateFrame("Frame", nil, markerLayer)
    m:SetSize(20, 20)
    -- our badge: a dark round with the boss's number (Blizzard's art)
    m.badge = m:CreateTexture(nil, "ARTWORK")
    m.badge:SetAllPoints()
    m.badge:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    m.badge:SetVertexColor(0.08, 0.05, 0.02, 0.85)
    m.num = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    m.num:SetPoint("CENTER", 0, 0)
    -- by a painted skull: its kill order in the notebook's hand and ink, as written on the map
    -- by a painted skull: its kill order, as the chest pins write their count (the game's small
    -- font, cream, shadowed)
    m.kill = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    m.kill:SetPoint("CENTER", m, "TOPRIGHT", 0, 0)
    m.kill:SetTextColor(1, 0.9, 0.6)
    -- a boss: the map's own painted skull, through a soft round mask so its
    -- glow fades into the parchment under it
    m.skull = m:CreateTexture(nil, "ARTWORK")
    m.skull:SetPoint("CENTER")
    m.skullMask = m:CreateMaskTexture()
    m.skullMask:SetTexture(ns.MEDIA .. "SkullMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m.skullMask:SetAllPoints(m.skull)
    m.skull:AddMaskTexture(m.skullMask)
    m.skull:Hide()
    -- hovered (here or in the list): a soft warm light from its middle, a few faint rounds one in another
    -- (a single yellow disc was too loud), laid over the skull as light (added): under it, the skull's
    -- own piece of the map hid it
    m.glows = {}
    for k = 1, 4 do
        local g = m:CreateTexture(nil, "OVERLAY", nil, k - 5)
        g:SetPoint("CENTER")
        g:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        g:SetBlendMode("ADD")
        g:SetVertexColor(0.22, 0.16, 0.06, 0.5)  -- (four laid over each other: kept low, 0.55 was a sun)
        g:Hide()
        m.glows[k] = g
    end
    m.done = m:CreateTexture(nil, "OVERLAY", nil, 2)
    m.done:SetSize(22, 22)
    m.done:SetPoint("CENTER")
    m.done:SetTexture(ns.MEDIA .. "KilledX")  -- (our ink's X, tools\killed_x.py)
    m.done:SetVertexColor(0.53, 0.16, 0.10, 0.95)                             -- (the red ink)
    -- an invisible point on the canvas: the marker hangs on it, so it moves with
    -- the map but keeps its own size whatever the zoom
    m.anchor = canvas:CreateTexture(nil, "BACKGROUND")
    m.anchor:SetSize(1, 1)
    m:EnableMouse(true)
    -- (placing: dragged where it belongs; it follows the cursor, and lands on the release)
    m.bfiTag = "boss marker"
    m:SetScript("OnMouseDown", function(self, button)
        ns.CTrace("marker down", button, self.name)
        if not (placing and self.ours and button == "LeftButton") then
            -- (a press on the skull is the map's: a drag pans, a note's ring on it is picked up)
            if button == "LeftButton" and not IsShiftKeyDown() and ns.DungeonMapDown then ns.DungeonMapDown(button) end
            return
        end
        local sx, sy = GetCursorPosition()
        self.drag = { sx = sx, sy = sy }
    end)
    m:SetScript("OnUpdate", function(self)
        local d = self.drag
        if not d then return end
        local sx, sy = GetCursorPosition()
        if not d.moved and math.sqrt((sx - d.sx) ^ 2 + (sy - d.sy) ^ 2) / UIParent:GetEffectiveScale() < 4 then return end
        d.moved = true
        local s = canvas:GetEffectiveScale()
        self.anchor:ClearAllPoints()
        self.anchor:SetPoint("CENTER", canvas, "TOPLEFT", sx / s - canvas:GetLeft(), sy / s - canvas:GetTop())
    end)
    m:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.bossName)
        if self.kind then GameTooltip:AddLine(self.kind == "rare" and "Rare" or "Friendly", unpack(KIND_COLOR[self.kind])) end
        if self.killed then GameTooltip:AddLine("Defeated", 0.3, 1, 0.3) end
        if ns.DangersBossLines and not self.killed then ns.DangersBossLines(shownInstance, self.name) end  -- (what kills here, of this boss)
        ns.DungeonBossQuestLines(shownInstance, self.name)
        local note = Note(shownInstance, self.name)
        if note then GameTooltip:AddLine(note, NOTE_COLOR[1], NOTE_COLOR[2], NOTE_COLOR[3], true) end
        ns.Hints({ placing and self.ours and { "Click", "pick it" } or nil,
                   placing and self.ours and { "Drag", "move it" } or nil,
                   not placing and { "Shift-click", note and "your note" or "add a note" } or nil,
                   { "Right-click", "its menu" } })
        GameTooltip:Show()
        UpdateList(self.name)
    end)
    m:SetScript("OnLeave", function()
        GameTooltip:Hide()
        UpdateList()
    end)
    m:SetScript("OnMouseUp", function(self, button)
        ns.CTrace("marker up", button, self.name)
        local drag = self.drag
        self.drag = nil
        if placing and self.ours and button == "LeftButton" then
            picked = self.name
            if drag and drag.moved and ns.PlaceBossAtCursor then ns.PlaceBossAtCursor(self.name) return end
            UpdateList()
            return
        end
        if button == "LeftButton" and IsShiftKeyDown() and not placing then
            EditNote(shownInstance, self.name)
            return
        end
        -- (right-click: its menu, never out of the map; a left press was the map's)
        if button == "RightButton" then ns.DungeonThingMenu(self.name) return end
        if ns.DungeonMapUp then ns.DungeonMapUp(button) end
    end)
    bossMarkers[i] = m
    return m
end

-- sized in the picture's own pixels, so the X shrinks and grows with the map; our badges kept readable
local MARKER_PX = 22
local function ResizeMarker(m, k)
    local s = MARKER_PX * k
    if m.ours then s = math.max(14, math.min(26, s * 1.3)) end
    m:SetSize(s, s)
    -- (the skull exactly as big as the painted ones on the map)
    local sk = (ns.DUNGEON_SKULL_PX or 30) * k
    m.sk = sk
    m.skull:SetSize(sk * (m.lit and 1.1 or 1), sk * (m.lit and 1.1 or 1))
    m.done:SetSize(s * 1.9, s * 1.9)                       -- (past the ring: crossed out, plain to see)
    for k, g in ipairs(m.glows) do g:SetSize(math.max(s, sk) * (1.5 - k * 0.25), math.max(s, sk) * (1.5 - k * 0.25)) end
    local font, size, flags = m.num:GetFont()
    local want = math.floor(s * 0.62 + 0.5)
    if font and size ~= want then m.num:SetFont(font, want, flags or "") end
    local kfile, kf, kflags = m.kill:GetFont()
    local kw = math.max(10, math.floor(sk * 0.42 + 0.5))
    if kfile and kf ~= kw then m.kill:SetFont(kfile, kw, kflags or "") end
    m.kill:ClearAllPoints()
    m.kill:SetPoint("CENTER", m, "CENTER", sk * 0.4, sk * 0.36)
end
ResizeMarkers = function(k)
    for _, m in ipairs(bossMarkers) do ResizeMarker(m, k) end
end

local function DrawBosses()
    local skulls = ns.DungeonSkulls
    for _, m in ipairs(bossMarkers) do m:Hide() end
    wipe(markerByName)
    local f = floors and floors[floorIndex]
    if Cfg().bosses and f and f.bosses then
        local n = 0
        for _, b in ipairs(f.bosses) do
            if b.name and b.x and b.y then
                n = n + 1
                local m = Marker(n)
                m.anchor:ClearAllPoints()
                m.anchor:SetPoint("CENTER", canvas, "TOPLEFT", b.x * PW, -b.y * PH)
                m:ClearAllPoints()
                m:SetPoint("CENTER", m.anchor, "CENTER")
                m.name, m.bossName = b.name, b.label or b.name
                m.bx, m.by = b.x, b.y
                m.ours = true
                m.killed = KilledHere(b.name) and true or false
                local skull = m.ours and skulls and (skulls[shownInstance] or skulls.default)
                if skull then
                    local l, t, px = skull[2] / 256, skull[3] / 256, (ns.DUNGEON_SKULL_PX or 30) / 256
                    m.skull:SetTexture(skull[1])
                    m.skull:SetTexCoord(l, l + px, t, t + px)
                    local tint = SKULL_TINT[b.kind]
                    m.skull:SetDesaturated(tint and true or false)
                    m.skull:SetVertexColor(unpack(tint or { 1, 1, 1 }))
                end
                m.skull:SetShown(skull and true or false)
                m.badge:SetShown(m.ours and not skull)
                -- (a boss's kill order by its skull too, top right; not the rares', and not where a found
                -- note rings it: the ring's number is the book's, the list keeps the order, never both)
                local ring = skull and ns.FoundNoteAt and ns.FoundNoteAt(shownInstance, f.index, b.x, b.y)
                m.num:SetShown(m.ours and not skull)
                m.num:SetText(b.n or "")
                -- (A skull under ANOTHER boss's book ring could not be pointed at: the ring's frame, a fifth wider
                -- than the ring, lay over it, and the neighbour's note answered. Velratha in Zul'Farrak, Moira
                -- beside the Emperor, Phalanx beside Plugger, eight in all; tools\dangers_overlap.lua, NO REACH.
                -- Such a skull gets a frame over the book's that hands everything on to the marker. Drawn as
                -- before: only the pointer's reach changes. A skull inside its OWN ring stays the ring's: one
                -- place, one mark, the user's rule of 2026-11-15.)
                do
                    local own = false
                    if ring then
                        local n, _, vx, vy, mark = ns.FoundNoteAt(shownInstance, f.index, b.x, b.y)
                        own = n and not mark and true or false
                        if own then
                            local mine = math.max(math.abs(b.x - vx), math.abs(b.y - vy) * 0.667)
                            for _, o in ipairs(f.bosses) do
                                if o ~= b and o.x and o.y and math.max(math.abs(o.x - vx), math.abs(o.y - vy) * 0.667) < mine then own = false end
                            end
                        end
                    end
                    if not own and not m.reach then
                        local r = CreateFrame("Frame", nil, m)
                        r:SetAllPoints(m)
                        r:EnableMouse(true)
                        r.bfiTag = "boss marker"
                        for _, script in ipairs({ "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp" }) do
                            r:SetScript(script, function(_, ...) local fn = m:GetScript(script) if fn then fn(m, ...) end end)
                        end
                        m.reach = r
                    end
                    if m.reach then
                        m.reach:SetShown(not own)
                        m.reach:SetFrameLevel(canvas:GetFrameLevel() + 8)   -- (over the book's frames, + 6; under a danger's, + 9)
                    end
                end
                m.kill:SetShown(m.ours and skull and not b.kind and not ring or false)
                m.kill:SetText(b.n or "")
                m.kind = b.kind
                m.num:SetTextColor(unpack(KIND_COLOR[b.kind] or { 1, 0.82, 0 }))
                m.skull:SetAlpha(m.killed and 0.5 or 1)
                m.badge:SetAlpha(m.killed and 0.5 or 1)
                m.num:SetAlpha(m.killed and 0.5 or 1)
                m.done:SetShown(m.killed)
                m:Show()
                markerByName[b.name] = m
            end
        end
        ResizeMarkers(canvas:GetScale())  -- (new markers: the current size straight away)
    end
    UpdateList()
end

function ns.DungeonQuillChanged() if overlay and overlay:IsShown() then DrawBosses() end end

local function MarkKilled(name)
    name = ns.Known(name)  -- (an event's name could come secret inside on live Forever: then no tick)
    if not name then return end
    Kills()[name:lower()] = true
    DrawBosses()
end

-- Bosses without an encounter (most in Blackfathom Deeps, Gnomeregan, Sunken
-- Temple on Era) give no ENCOUNTER_END: one of the list dead as your target or
-- under the mouse counts too
-- the copy of the dungeon a monster is in (the 5th part of its GUID): a new one is a reset run,
-- whoever reset it and wherever you were. And the game's "X has been reset." from your own reset.
local function CheckCopy(unit)
    if not (IsInInstance() and UnitExists(unit)) or UnitIsPlayer(unit) then return end
    local guid = ns.Known(UnitGUID(unit))  -- (can be secret inside on live Forever, as the name below)
    local kind, _, _, _, copy = strsplit("-", guid or "")
    if kind ~= "Creature" or not copy then return end
    local r = Run()
    if r.id ~= select(8, GetInstanceInfo()) then return end
    if r.copy and r.copy ~= copy then
        r.kills = {}
        DrawBosses()
    end
    r.copy = copy
end

local function CheckReset(msg)
    local fmt = INSTANCE_RESET_SUCCESS
    msg = ns.Known(msg)  -- (chat inside can be secret on live Forever)
    if not (fmt and msg) then return end
    local pat = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)")
    local name = msg:match("^" .. pat .. "$")
    local r = Run()
    if name and r.name and name == r.name then
        r.kills, r.copy = {}, nil
        DrawBosses()
    end
end

-- one of the list died (DungeonWhere.lua hears it in the combat log, where the client lets it)
function ns.DungeonUnitDied(name)
    if not (IsInInstance() and name) or Kills()[name:lower()] then return end
    for _, n in ipairs(Encounters(select(8, GetInstanceInfo()))) do
        if n == name then MarkKilled(name) return end
    end
end

local function CheckDeadUnit(unit)
    if not (IsInInstance() and UnitExists(unit) and ns.Known(UnitIsDead(unit))) or UnitIsPlayer(unit) then return end
    local name = ns.Known(UnitName(unit))
    if not name or Kills()[name:lower()] then return end
    for _, n in ipairs(Encounters(select(8, GetInstanceInfo()))) do
        if n == name then MarkKilled(name) return end
    end
end

-- The list --------------------------------------------------------------------
-- A checklist on a slip of the found notes' paper, pinned in the map's top-left
-- corner (below the Map / Minimap switch) with a brass pin: the bosses in kill
-- order in the notebook's hand, each ticked in your ink and struck through when
-- killed this run; the rares under "if we're lucky" (friendly NPCs left off).
-- A red ring with a number: the found notes say something there (hover: it;
-- click: the notebook at it). Hover a name: its marker lights up. Click: the floor
-- it's on. The title folds it. Placing: the picked one red, those not placed yet
-- with a "?"; a click picks one.

local NOTES = ns.MEDIA .. "Notes\\"
local HAND = ns.MEDIA .. "Fonts\\Felipa-Regular.ttf"
local HAND_BODY = ns.MEDIA .. "Fonts\\NothingYouCouldDo.ttf"
local P_INK, P_SOFT = { 0.17, 0.12, 0.07 }, { 0.35, 0.23, 0.11 }
local P_RED, P_BLUE = { 0.54, 0.165, 0.11 }, { 0.13, 0.17, 0.26 }
local ROUND = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local list, listTitle, listRows = nil, nil, {}
-- The Bosses list (2026-11-14, after three looks that each covered half of a small map: pale paper, glass,
-- ink in the margin; the user plays with the map about 390 px wide in a corner, and: "Needs to be a
-- check-slip"): on the map only a small glass COUNT, "BOSSES 2 of 8" (list, a child of the map). The list
-- itself is a slip you check: it unfolds under the count while the pointer is on the count or on it, and
-- folds again when the pointer has left; a click on the count keeps it open (bossListOpen) until the next
-- click. The slip is its own frame on the screen (listSlip, UIParent's), so the map's clipping and scale
-- don't shrink it: readable at any map size, and never on the map unless asked for.
local listSlip, listHover, listAway = nil, false, 0
local listWait = false   -- closed by a click: the pointer must leave the count before it may open the slip again
local ListMenu, ListOpenMap, ListDragStart, ListDragStop   -- (with the unpinned slip, below)
-- (dark glass: its colours, and plain type for the names)
local G_TEXT, G_SOFT, G_FAINT = { 0.91, 0.89, 0.85 }, { 0.66, 0.64, 0.58 }, { 0.46, 0.44, 0.40 }
local G_GOLD, G_HAND, G_RED, G_BLUE = { 0.73, 0.55, 0.32 }, { 0.85, 0.73, 0.54 }, { 0.86, 0.40, 0.30 }, { 0.56, 0.69, 0.82 }
local LIST_EDGE = 18
local function SetPlain(fs, size) fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "") end

local function SetHand(fs, size, font)
    if not (pcall(fs.SetFont, fs, font or HAND, size, "") and fs:GetFont()) then
        fs:SetFont("Fonts\\FRIZQT__.TTF", math.floor(size * 0.85), "")
    end
end

-- a line drawn by hand on the slip (a, b: its ends from the frame's top-left)
local function InkLine(f, color, alpha, thick)
    local l = f:CreateLine(nil, "OVERLAY")
    l:SetColorTexture(color[1], color[2], color[3], alpha or 0.85)
    l:SetThickness(thick or 1.4)
    return l
end
local function Ends(l, f, x1, y1, x2, y2)
    l:SetStartPoint("TOPLEFT", f, x1, y1)
    l:SetEndPoint("TOPLEFT", f, x2, y2)
end

-- A note's paper (the Bosses slip here; Dangers.lua's note and its hover slip): a window of the book's paper for
-- its body, and round it Media\Notes\Slip (tools\slip_art.py) cut in nine: a torn, uneven edge, the paper
-- darker where it's been held, and a soft shadow down and to the right. Before 2026-11-11 a note was a
-- straight-sided rectangle with a black box behind it for a shadow (the user: a new pass on the look). The
-- rim's middle is clear, so the body keeps Paper's own grain at any size; the rim hides the body's straight sides.
-- l, r, t, b: the window of Paper. The frame must be at least 36 across and high.
function ns.PaperSlip(f, l, r, t, b)
    local body = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    body:SetPoint("TOPLEFT", 3, -3)
    body:SetPoint("BOTTOMRIGHT", -3, 3)
    body:SetTexture(NOTES .. "Paper")
    body:SetTexCoord(l, r, t, b)
    body:SetVertexColor(0.96, 0.92, 0.84)
    local C, O, T = 28, 10, 56 / 256   -- a corner piece; how far the picture reaches past the paper's edge; a corner's share of the picture
    local function Piece(u0, u1, v0, v1)
        local p = f:CreateTexture(nil, "BORDER")
        p:SetTexture(NOTES .. "Slip")
        p:SetTexCoord(u0, u1, v0, v1)
        return p
    end
    local tl, tr = Piece(0, T, 0, T), Piece(1 - T, 1, 0, T)
    local bl, br = Piece(0, T, 1 - T, 1), Piece(1 - T, 1, 1 - T, 1)
    tl:SetSize(C, C)
    tl:SetPoint("TOPLEFT", f, "TOPLEFT", -O, O)
    tr:SetSize(C, C)
    tr:SetPoint("TOPRIGHT", f, "TOPRIGHT", O, O)
    bl:SetSize(C, C)
    bl:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -O, -O)
    br:SetSize(C, C)
    br:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", O, -O)
    for _, e in ipairs({ { Piece(T, 1 - T, 0, T), tl, "TOPRIGHT", tr, "BOTTOMLEFT" }, { Piece(T, 1 - T, 1 - T, 1), bl, "TOPRIGHT", br, "BOTTOMLEFT" },
                         { Piece(0, T, T, 1 - T), tl, "BOTTOMLEFT", bl, "TOPRIGHT" }, { Piece(1 - T, 1, T, 1 - T), tr, "BOTTOMLEFT", br, "TOPRIGHT" } }) do
        e[1]:SetPoint("TOPLEFT", e[2], e[3])
        e[1]:SetPoint("BOTTOMRIGHT", e[4], e[5])
    end
    return body
end
-- Dark glass (2026-11-14, the user's pick over the pale slips: "Dark glass for what kills here FOR SURE"; the
-- Bosses list's count and the slip it unfolds on wear it too): As told's panel (AsToldPanel.lua): a dark ground that is full under the words and
-- fades out at the right over `edge`, a gold rule along its top. Three textures, no art. The paper above stays
-- for what lies ON the map by the cursor (the dangers' hover tag).
function ns.GlassPanel(f, edge, alpha)
    edge, alpha = edge or 24, alpha or 0.8
    local back = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    back:SetPoint("TOPLEFT")
    back:SetPoint("BOTTOMRIGHT", -edge, 0)
    back:SetColorTexture(0.055, 0.06, 0.07, alpha)
    local fade = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    fade:SetPoint("TOPLEFT", back, "TOPRIGHT")
    fade:SetPoint("BOTTOMRIGHT")
    fade:SetColorTexture(1, 1, 1, 1)
    local faded = false
    if fade.SetGradient and CreateColor then
        faded = pcall(fade.SetGradient, fade, "HORIZONTAL", CreateColor(0.055, 0.06, 0.07, alpha), CreateColor(0.055, 0.06, 0.07, 0))
    end
    if not faded and fade.SetGradientAlpha then
        faded = pcall(fade.SetGradientAlpha, fade, "HORIZONTAL", 0.055, 0.06, 0.07, alpha, 0.055, 0.06, 0.07, 0)
    end
    if not faded then fade:SetColorTexture(0.055, 0.06, 0.07, alpha * 0.5) end
    local rule = f:CreateTexture(nil, "BORDER")
    rule:SetPoint("TOPLEFT")
    rule:SetPoint("TOPRIGHT", -edge, 0)
    rule:SetHeight(1)
    rule:SetColorTexture(0.73, 0.55, 0.32, 0.95)
    f.glassRule = rule
    return back
end
-- the brass pin through a note's top (Media\Notes\Pin: its dome lit from the top left, its shadow, the paper
-- drawn in round it); y: its middle, down from the note's top
function ns.PaperPin(f, y)
    local t = f:CreateTexture(nil, "ARTWORK", nil, 3)
    t:SetTexture(NOTES .. "Pin")
    t:SetSize(22, 22)
    t:SetPoint("CENTER", f, "TOP", 1, (y or -9) - 1)
    return t
end
-- a line ruled across a note by hand: three strokes, not quite level. Answers SetShown, as a texture would.
function ns.InkRule(f, inset, y)
    local pts = { { "TOPLEFT", inset, y }, { "TOP", -24, y + 0.7 }, { "TOP", 30, y - 0.5 }, { "TOPRIGHT", -inset, y + 0.4 } }
    local rule = { lines = {} }
    for i = 1, 3 do
        local l = f:CreateLine(nil, "ARTWORK")
        l:SetColorTexture(P_SOFT[1], P_SOFT[2], P_SOFT[3], 0.42)
        l:SetThickness(1.1)
        l:SetStartPoint(pts[i][1], f, pts[i][2], pts[i][3])
        l:SetEndPoint(pts[i + 1][1], f, pts[i + 1][2], pts[i + 1][3])
        rule.lines[i] = l
    end
    function rule:SetShown(on) for _, l in ipairs(self.lines) do l:SetShown(on) end end
    return rule
end

-- the floor (index into floors) a boss is drawn on
local function FloorOf(name)
    for i, f in ipairs(floors or {}) do
        for _, b in ipairs(f.bosses or {}) do
            if b.name == name then return i end
        end
    end
end

local function ShowFloorOf(name)
    local i = FloorOf(name)
    if i and i ~= floorIndex then
        floorIndex, manualFloor = i, true
        centerX, centerY = 0, 0
        ShowFloor()
        DrawBosses()
    end
end

-- what the found notes say at a boss's spot: its number, its words (Notebook.lua)
local function FoundNote(name)
    local s = Spot((shownInstance or listInst), name)
    if s and ns.FoundNoteAt then return ns.FoundNoteAt((shownInstance or listInst), s[1], s[2], s[3]) end
end

-- a boss's menu (its marker or its name in the list): your note, killed, the found notes'
-- note at its spot; placing: its spot taken off
local function BossMenu(name)
    if not (name and ns.QuillMenu) then return end
    local items = {}
    items[#items + 1] = { Note(shownInstance, name) and "your note on it" or "a note on it", function() EditNote(shownInstance, name) end }
    if Run().id == shownInstance then
        local key = name:lower()
        items[#items + 1] = { Kills()[key] and "not killed yet" or "killed", function()
            Kills()[key] = (not Kills()[key]) or nil
            DrawBosses()
        end }
    end
    local s = Spot(shownInstance, name)
    if s and FoundNote(name) and ns.OpenNotebook then
        items[#items + 1] = { "found notes on this boss", function() ns.OpenNotebook(shownInstance, s[1]) end }
    end
    if ns.HasBossLoot and ns.HasBossLoot(shownInstance, name) then
        local inst = shownInstance
        items[#items + 1] = { "what they carry", function() ns.OpenBossLoot(inst, name) end }
    end
    -- (the ring taken now: by the click on this row the cursor is on the menu, not on it)
    local ring = markerByName[name] and ns.FoundSpotGrab and ns.FoundSpotGrab()
    if ring then
        items[#items + 1] = { "the note's ring...", function() ns.QuillSpotMenu(true, nil, ring) end }
    end
    if placing and s then
        items[#items + 1] = { "take its spot off the map", function() ns.RemoveBossSpot(name) end }
    end
    ns.QuillMenu(items)
end

-- the boss whose skull stands at this place on the floor shown (a found note's ring snapped onto it:
-- Notebook.lua): its name as the map says it, whether it is dead this run, its kind, the name its menu takes.
-- For the ring's slip and menu, which answer for the skull under them.
function ns.DungeonBossAt(x, y)
    for name, m in pairs(markerByName) do
        if m:IsShown() and m.bx and math.abs(m.bx - x) * PW < 1.5 and math.abs(m.by - y) * PH < 1.5 then
            return m.bossName or name, m.killed, m.kind, name
        end
    end
end
function ns.DungeonBossMenu(name) BossMenu(name) end

-- right-click on a thing on the dungeon map (Controls.lua): its menu, true when there was one. A
-- note's ring sits on its boss's skull: the quill out, the ring's menu (the boss's at its end); else
-- the boss's (the ring's in it). Then the ink's marks.
function ns.DungeonThingMenu(boss)
    if not boss then
        for name, m in pairs(markerByName) do
            if m:IsVisible() and m:IsMouseOver() then boss = name break end
        end
    end
    local ring = ns.FoundSpotUnder and ns.FoundSpotUnder()
    ns.CTrace("thing menu: boss", tostring(boss), "ring", tostring(ring))
    if ring and (ns.QuillOut() or not boss) then
        return ns.QuillSpotMenu(true, boss and { { boss .. "...", function() BossMenu(boss) end } } or nil)
    end
    if boss then
        BossMenu(boss)
        return true
    end
    return ns.InkMenuAt and ns.InkMenuAt() or false
end

-- Shift-click with the quill's catcher over the markers (Ink.lua): the boss's note
function ns.DungeonBossNote()
    for name, m in pairs(markerByName) do
        if m:IsVisible() and m:IsMouseOver() then EditNote(shownInstance, name) return true end
    end
    return false
end

local function RowTip(self, ring)
    local n, text = FoundNote(self.name)
    local note = Note((shownInstance or listInst), self.name)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.name)
    if n then GameTooltip:AddLine(n .. ".  " .. text:gsub("~", ""), 1, 0.93, 0.78, true) end
    if ns.DangersBossLines then ns.DangersBossLines((shownInstance or listInst), self.name, n and text) end  -- (what kills here, of this boss; the book's note is said already)
    ns.DungeonBossQuestLines((shownInstance or listInst), self.name)
    if note then GameTooltip:AddLine(note, NOTE_COLOR[1], NOTE_COLOR[2], NOTE_COLOR[3], true) end
    ns.Hints({ { "Click", ring and "found notes on this boss" or "its floor" },
               not ring and { "Shift-click", note and "your note" or "add a note" } or nil,
               { "Right-click", "its menu" },
               placing and not ring and { "Wheel", "earlier or later in the kill order" } or nil })
    GameTooltip:Show()
end

-- Unpinned from the map (the user, 2026-11-14: "let unpin from map and keep open with map closed on screen";
-- "Right click>dropdown>unpin from map"): dungeon.bossListAt = { left, top } on the screen. The slip then stays
-- open where it is put, with a heading of its own, map up or shut; a drag moves it; its menu or its "x" puts
-- it back on the map.
local function ListUnpin()
    local c = Cfg()
    local l, t = listSlip:IsShown() and listSlip:GetLeft(), listSlip:GetTop()
    if not (l and t) then
        -- (folded: where it would unfold, under the count; the count is in the map's own scale)
        local k = list:GetEffectiveScale() / UIParent:GetEffectiveScale()
        l, t = (list:GetLeft() or 20) * k, (list:GetBottom() or 400) * k
    end
    c.bossListAt = { l, t }
    UpdateList()
end
-- back on the map. From the menu ("Back on the map") it stays open there; from the slip's "x" it is shut, the
-- count alone left (the user, 2026-11-15: the x "should close. 'Back to map' should stay open")
local function ListRepin(open)
    local c = Cfg()
    c.bossListAt = nil
    c.bossListOpen = open and true or nil
    listHover, listWait = false, true
    UpdateList()
end
function ListMenu()
    if not ns.QuillMenu then return end
    if Cfg().bossListAt then
        ns.QuillMenu({ { "back on the map", function() ListRepin(true) end } })
    else
        ns.QuillMenu({ { "unpin from map", ListUnpin } })
    end
end
function ListOpenMap()
    local map = BattlefieldMapFrame
    if map and not map:IsShown() and not ns.standBy then map:Show() end
    if listInst and ns.PreviewDungeon then ns.PreviewDungeon(listInst) end
end
-- A drag moves the unpinned slip. Moved by hand, not by the game's StartMoving: the drag usually begins on a
-- row, and a row is laid out again whenever the list is redrawn, which ended the game's own move at once
-- ("bosses slip doesnt move", the user 2026-11-15). So: where the pointer took hold is kept here, the slip's
-- OnUpdate follows the pointer, and the move ends when the button is let go (looked at there too, so it
-- does not hang on any frame's OnDragStop). While it moves the list is not redrawn.
function ListDragStart()
    if not Cfg().bossListAt or listSlip.moving then return end
    local s = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    listSlip.moving = { cx / s - (listSlip:GetLeft() or 0), cy / s - (listSlip:GetTop() or 0) }
    GameTooltip:Hide()
end
function ListDragStop() end
-- the dungeon you are standing in, if we know its bosses
local function ListHere()
    if not (IsInInstance and IsInInstance()) then return end
    local id = select(8, GetInstanceInfo())
    if not id then return end
    local names = Encounters(id)
    return names and #names > 0 and id or nil
end

local function ListRow(i)
    local r = listRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, listSlip)
    r:SetHeight(18)
    r.hl = r:CreateTexture(nil, "BACKGROUND", nil, 2)
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(G_GOLD[1], G_GOLD[2], G_GOLD[3], 0.16)
    -- the box: four straight sides, and the game's own tick in gold. (It was drawn by hand, each side a little
    -- off, for the paper slip; thin slanted lines on dark glass came out jagged: the user, 2026-11-14,
    -- "Tickboxes pixelated".)
    for _, side in ipairs({ { 4, -4, 11, 1 }, { 4, -14, 11, 1 }, { 4, -4, 1, 11 }, { 14, -4, 1, 11 } }) do
        local e = r:CreateTexture(nil, "ARTWORK")
        e:SetColorTexture(G_FAINT[1], G_FAINT[2], G_FAINT[3], 0.95)
        e:SetPoint("TOPLEFT", r, "TOPLEFT", side[1], side[2])
        e:SetSize(side[3], side[4])
    end
    local tick = r:CreateTexture(nil, "OVERLAY")
    tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    tick:SetVertexColor(1, 0.86, 0.55)
    tick:SetSize(17, 17)
    tick:SetPoint("CENTER", r, "TOPLEFT", 10, -9)
    r.tick = { tick }
    r.text = r:CreateFontString(nil, "OVERLAY")
    SetPlain(r.text, 12)
    r.text:SetPoint("LEFT", 22, 0)
    r.text:SetJustifyH("LEFT")
    r.strike = InkLine(r, G_FAINT, 0.9, 1.1)
    r.mark = r:CreateFontString(nil, "OVERLAY")  -- (your note: a red asterisk)
    SetHand(r.mark, 15)
    r.mark:SetPoint("LEFT", r.text, "RIGHT", 2, 2)
    r.mark:SetTextColor(G_RED[1], G_RED[2], G_RED[3])
    r.mark:SetText("*")
    -- the found notes' number, ringed
    r.ref = CreateFrame("Button", nil, r)
    r.ref:SetSize(18, 18)
    r.ref:SetPoint("RIGHT", -2, 0)
    -- (a clean ring for the glass: a red disc with a dark one on it. The book's hand-drawn ring, a 64 px
    -- picture squeezed to 18, and the hand's digits at 11 came out jagged on the dark slip: the user,
    -- 2026-11-14, "at low size the ink gets jagged and pixelated". On the map the book's own rings are untouched.)
    local ring = r.ref:CreateTexture(nil, "ARTWORK", nil, 1)
    ring:SetPoint("CENTER")
    ring:SetSize(17, 17)
    ring:SetTexture(ROUND)
    ring:SetVertexColor(G_RED[1], G_RED[2], G_RED[3], 0.95)
    local hole = r.ref:CreateTexture(nil, "ARTWORK", nil, 2)
    hole:SetPoint("CENTER")
    hole:SetSize(14.5, 14.5)
    hole:SetTexture(ROUND)
    hole:SetVertexColor(0.075, 0.08, 0.09, 1)
    r.ref.n = r.ref:CreateFontString(nil, "OVERLAY")
    SetPlain(r.ref.n, 10)
    r.ref.n:SetPoint("CENTER", 0, 0)
    r.ref.n:SetTextColor(G_RED[1], G_RED[2], G_RED[3])
    r.ref:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.ref:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if shownInstance then BossMenu(r.name) else ListMenu() end
            return
        end
        local inst = shownInstance or listInst
        local s = Spot(inst, r.name)
        if s and ns.OpenNotebook then ns.OpenNotebook(inst, s[1]) end
    end)
    r.ref:SetScript("OnEnter", function() RowTip(r, true) end)
    r.ref:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnEnter", function(self)
        UpdateList(self.name)
        RowTip(self)
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() UpdateList() end)
    r:SetScript("OnMouseWheel", function(self, d)
        if placing and ns.MoveBoss then ns.MoveBoss(self.name, d > 0 and -1 or 1) end
    end)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:RegisterForDrag("LeftButton")
    r:SetScript("OnDragStart", ListDragStart)
    r:SetScript("OnDragStop", ListDragStop)
    r:SetScript("OnClick", function(self, button)
        -- (unpinned, and no dungeon map up: a click brings that dungeon's map; a right-click, the slip's menu)
        if not shownInstance then
            if button == "RightButton" then ListMenu() else ListOpenMap() end
            return
        end
        if button == "RightButton" then BossMenu(self.name) return end
        if IsShiftKeyDown() and not placing then EditNote(shownInstance, self.name) return end
        if placing then picked = self.name end
        ShowFloorOf(self.name)
        UpdateList(self.name)
    end)
    listRows[i] = r
    return r
end

-- (lit: the boss under the mouse, in the list or on the map)
UpdateList = function(lit)
    if not list then return end
    -- (the one hovered: lit, and its skull a little bigger)
    for _, m in pairs(markerByName) do
        m.lit = m.name == lit
        for _, g in ipairs(m.glows) do g:SetShown(m.lit) end
        if m.sk then m.skull:SetSize(m.sk * (m.lit and 1.1 or 1), m.sk * (m.lit and 1.1 or 1)) end
    end
    if listSlip.moving then return end                    -- (being dragged: as it is until let go)
    local c = Cfg()
    local free = c.bossListAt and true or false           -- unpinned from the map
    local onMap = shownInstance and canvas:IsShown() and true or false
    if shownInstance then c.bossListInst = shownInstance end
    listInst = (not shownInstance and free) and (ListHere() or c.bossListInst) or nil
    local inst = shownInstance or listInst
    local names, kind = {}, {}
    if inst then names, kind = Encounters(inst) end
    -- (on the docked small square too, since 2026-11-14: a count is small enough there, where a list never was)
    if not (c.bossList and #names > 0 and (onMap or free)) then
        list:Hide()
        listSlip:Hide()
        return
    end
    local killed, bosses = 0, 0
    for _, name in ipairs(names) do
        if not kind[name] then
            bosses = bosses + 1
            if KilledHere(name) then killed = killed + 1 end
        end
    end
    local folded = not (placing or free or c.bossListOpen or listHover)
    listTitle.text:SetText(placing and "PLACING" or "BOSSES")
    listTitle.text:SetTextColor(unpack(placing and G_RED or G_SOFT))
    listTitle.count:SetText(killed .. " of " .. bosses)
    -- (the count ends square, no fade: the "!" joins straight on to it, one bar. The user, 2026-11-15, of the
    -- gap and the fade between the two: "Maybe we should just let these two join together?")
    local chipW = listTitle.text:GetStringWidth() + listTitle.count:GetStringWidth() + 34
    local w = chipW
    -- (rows kept up while they're used: hiding the one under the mouse fired its OnLeave, which
    -- redrew the list unlit, so hovering a name never lit its skull)
    local used = {}
    list.lucky:Hide()
    local y = -6
    -- (unpinned: a heading of its own, as the count may not be on the screen)
    listSlip.head:SetShown(free)
    -- (its own gold rule only while unpinned: under the count it was a second rule a few pixels below the
    -- count's, ending almost, not quite, at the "!": the user, 2026-11-15)
    if listSlip.glassRule then listSlip.glassRule:SetShown(free) end
    if free then
        local nm = ns.DungeonEntranceInfo and ns.DungeonEntranceInfo(inst)
        listSlip.title:SetText("BOSSES")
        listSlip.sub:SetText(nm and nm[1] or "")
        listSlip.count:SetText(killed .. " of " .. bosses)
        w = math.max(w, listSlip.title:GetStringWidth() + listSlip.sub:GetStringWidth() + listSlip.count:GetStringWidth() + 62 + LIST_EDGE)
        y = -26
    end
    if not folded then
        local blizzard = floors and floors[floorIndex] and floors[floorIndex].tiles
        -- the bosses, then the rares under their line
        local order = {}
        for _, name in ipairs(names) do if not kind[name] then order[#order + 1] = name end end
        local nBosses = #order
        for _, name in ipairs(names) do if kind[name] == "rare" then order[#order + 1] = name end end
        for i, name in ipairs(order) do
            if i == nBosses + 1 then
                list.lucky:ClearAllPoints()
                list.lucky:SetPoint("TOPLEFT", listSlip, "TOPLEFT", 12, y - 4)
                list.lucky:Show()
                y = y - 20
            end
            local r = ListRow(i)
            r.name = name
            local done = KilledHere(name) and true or false
            local unplaced = placing and blizzard and not Spot(inst, name)
            r.text:SetText(name .. (unplaced and "  ?" or ""))
            local col = (placing and name == picked) and G_RED or kind[name] == "rare" and G_BLUE or G_TEXT
            r.text:SetTextColor(col[1], col[2], col[3])
            r.text:SetAlpha(done and 0.45 or unplaced and 0.6 or 1)
            for _, t in ipairs(r.tick) do t:SetShown(done) end
            local tw = r.text:GetStringWidth()
            r.strike:SetShown(done)
            Ends(r.strike, r, 20, -9.5, 24 + tw, -9.5)
            r.mark:SetShown(Note(inst, name) ~= nil)
            local n = FoundNote(name)
            r.ref:SetShown(n ~= nil)
            if n then r.ref.n:SetText(n) end
            r.hl:SetShown(name == lit or (placing and name == picked))
            -- (only then: else the wheel zooms the map. Set only when it changes: setting it on the row
            -- under the mouse each redraw threw the hover off, so the list's hover never lit the skull)
            local wheel = placing and not kind[name] or false
            if r.wheel ~= wheel then
                r.wheel = wheel
                r:EnableMouseWheel(wheel)
            end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", listSlip, "TOPLEFT", 8, y)
            r:SetPoint("RIGHT", listSlip, "RIGHT", -LIST_EDGE, 0)
            r:Show()
            used[r] = true
            w = math.max(w, tw + 22 + 14 + (n and 22 or 0) + 12 + LIST_EDGE)
            y = y - 18
        end
    end
    for _, r in ipairs(listRows) do if not used[r] then r:Hide() end end
    -- (under the count, the slip's dark ground runs at least to the "!"'s right edge before it starts to fade
    -- (the "!" is 24 wide, 3 off the count: Dangers.lua). It stopped a few pixels short of that line; the user,
    -- 2026-11-15: "extend the area before feathering began ... a few pixels". Nothing else changes width: a
    -- first try made the slip square and widened the count to fit, "janky". A list with longer names than
    -- that still runs further, as it must.)
    -- (the count and the "!" are the map's children, the slip is the screen's: where the map has a scale of its
    -- own their pixels are not the slip's, and the line was still some pixels out in the user's marked shot)
    -- (and the other way round: names longer than the count made the list's ground run on past the "!", so the
    -- heading stopped short of the list under it. The user, 2026-11-16: "Header not lining up". With the list
    -- open the count is as wide as the list's dark ground, the "!" at its end; folded, it is its own width)
    local headW = chipW
    if not free then
        local k = (list:GetEffectiveScale() or 1) / math.max(0.01, listSlip:GetEffectiveScale() or 1)
        local bang = ns.dangersTab and ns.dangersTab:IsShown() and 24 or 0   -- (the "!" joined to the count, if it is there)
        w = math.max(w, (chipW + bang) * k + LIST_EDGE)
        -- (to the slip's outer edge, not to where its ground starts to fade: over the dark map the 18 px fade
        -- reads as solid ground, and the heading still looked short by that much in the user's second shot)
        if not folded then headW = math.max(chipW, w / k - bang) end
    end
    local map = BattlefieldMapFrame
    local border = map and map.BorderFrame
    if onMap then
        -- the count alone is on the map
        list:ClearAllPoints()
        if viewBtn and viewBtn:IsShown() and ns.Docked and ns.Docked() then
            list:SetPoint("TOPLEFT", viewBtn, "BOTTOMLEFT", 2, -8)
        else
            -- (18 down, not 8: the map's own border frame takes the mouse along the top edge, and the count and
            -- the "!" beside it had their top under it: the user, 2026-11-14, "hitbox on them are not all the way up")
            list:SetPoint("TOPLEFT", overlay, "TOPLEFT", 6, -18)
        end
        -- (its full size at any map size: shrunk with a small map its letters and the "!" beside it went jagged)
        list:SetScale(1)
        list:SetWidth(headW)
        list:SetHeight(24)
        -- (the count takes the mouse only if nothing of the map lies over it: the game's own border frame is in a
        -- higher strata than the map and had the pointer at the map's top, /fstack in the user's shots, and the
        -- map's header and buttons are far above the dungeon overlay's level. So: the border's strata, over it.
        -- The first build sat at the overlay's level + 10 and never got its OnEnter: "Bosses slip doesnt open".)
        if border then
            list:SetFrameStrata(border:GetFrameStrata())
            list:SetFrameLevel(math.min(9900, border:GetFrameLevel() + 12))
        elseif ns.ButtonLevel and map then
            list:SetFrameLevel(math.min(9900, ns.ButtonLevel(map) + 12))
        end
        list:Show()
    else
        list:Hide()
    end
    if folded then
        listSlip:Hide()
    else
        -- (the slip: over the map's border when the map is up, so the pointer reaches it wherever it lies; kept
        -- on the screen if the list is long)
        if border and map:IsShown() then
            listSlip:SetFrameStrata(border:GetFrameStrata())
            listSlip:SetFrameLevel(math.min(9950, border:GetFrameLevel() + 17))
        else
            listSlip:SetFrameStrata("MEDIUM")
            listSlip:SetFrameLevel(40)
        end
        listSlip:SetSize(w, -y + 8)
        if not listSlip.moving then
            listSlip:ClearAllPoints()
            if free then
                listSlip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", c.bossListAt[1], c.bossListAt[2])
            else
                listSlip:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, 0)
            end
        end
        if not listSlip:IsShown() then
            listAway = 0
            listSlip.fade = 0          -- (soft, as the dangers note unfolds: its own OnUpdate brings it in)
            listSlip:SetAlpha(0)
            listSlip:Show()
        end
    end
end

RefreshNotes = function() UpdateList() end

local function CreateList(parent)
    list = CreateFrame("Frame", nil, parent)
    ns.dungeonBossList = list  -- (Dangers.lua: its "!" tab sits beside this slip)
    -- (over the dungeon's object pins, DungeonObjects.lua at the canvas + 6 to 8: a quest pin sat on it)
    list:SetFrameLevel(parent:GetFrameLevel() + 10)
    list:SetSize(140, 24)
    list:EnableMouse(true)  -- (a click beside the words isn't one on the map)
    -- the slip the list unfolds on: the screen's own, not the map's (see the top of this part)
    listSlip = CreateFrame("Frame", nil, UIParent)
    listSlip:SetClampedToScreen(true)
    listSlip:EnableMouse(true)
    ns.GlassPanel(listSlip, LIST_EDGE, 0.9)
    listSlip:RegisterForDrag("LeftButton")
    listSlip:SetScript("OnDragStart", ListDragStart)
    listSlip:SetScript("OnDragStop", ListDragStop)
    listSlip:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then ListMenu() end
    end)
    -- its heading while unpinned: BOSSES, the dungeon's name, the count, and an "x" that puts it back on the map
    local head = CreateFrame("Frame", nil, listSlip)
    head:SetPoint("TOPLEFT", 0, -1)
    head:SetPoint("TOPRIGHT", -LIST_EDGE, -1)
    head:SetHeight(22)
    -- (the heading takes the mouse itself: a press on it takes hold of the slip at once, a right-click is the
    -- slip's menu. Left to the slip under it, a drag on the title did nothing: the user, 2026-11-15)
    head:EnableMouse(true)
    head:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then ListDragStart() end
    end)
    head:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then ListMenu() end
    end)
    listSlip.head = head
    listSlip.title = head:CreateFontString(nil, "OVERLAY")
    SetPlain(listSlip.title, 10)
    listSlip.title:SetTextColor(G_SOFT[1], G_SOFT[2], G_SOFT[3])
    listSlip.title:SetPoint("LEFT", 10, 0)
    listSlip.sub = head:CreateFontString(nil, "OVERLAY")
    SetPlain(listSlip.sub, 10)
    listSlip.sub:SetTextColor(G_GOLD[1], G_GOLD[2], G_GOLD[3])
    listSlip.sub:SetPoint("LEFT", listSlip.title, "RIGHT", 8, 0)
    listSlip.count = head:CreateFontString(nil, "OVERLAY")
    SetPlain(listSlip.count, 10)
    listSlip.count:SetTextColor(G_SOFT[1], G_SOFT[2], G_SOFT[3])
    listSlip.count:SetPoint("RIGHT", -22, 0)
    local back = CreateFrame("Button", nil, head)
    back:SetSize(18, 18)
    back:SetPoint("RIGHT", -2, 0)
    back.x = back:CreateFontString(nil, "OVERLAY")
    SetPlain(back.x, 11)
    back.x:SetTextColor(G_FAINT[1], G_FAINT[2], G_FAINT[3])
    back.x:SetPoint("CENTER")
    back.x:SetText("x")
    back:SetScript("OnClick", function() GameTooltip:Hide() ListRepin(false) end)
    back:SetScript("OnEnter", function(self)
        self.x:SetTextColor(G_TEXT[1], G_TEXT[2], G_TEXT[3])
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Close")
        GameTooltip:AddLine("Back to the boss count on the map.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    back:SetScript("OnLeave", function(self)
        self.x:SetTextColor(G_FAINT[1], G_FAINT[2], G_FAINT[3])
        GameTooltip:Hide()
    end)
    head:Hide()
    -- (unpinned, it follows the run with no map up: looked at twice a second, redrawn only when the dungeon
    -- shown, the one you stand in or the kills change. With it pinned this is one comparison.)
    local watch, since2, last = CreateFrame("Frame", nil, UIParent), 0, nil
    watch:SetScript("OnUpdate", function(_, e)
        since2 = since2 + e
        if since2 < 0.5 then return end
        since2 = 0
        if not (ns.db and Cfg() and Cfg().bossListAt) then last = nil return end
        local n = 0
        for _ in pairs(Kills() or {}) do n = n + 1 end
        -- ((ListHere()) in brackets: outside a dungeon it returns nothing at all, and tostring of nothing is an
        -- error, eight of them a few seconds after the slip was first unpinned, 2026-11-15)
        local sig = tostring(shownInstance) .. ":" .. tostring((ListHere())) .. ":" .. tostring(Run().id) .. ":" .. n
        if sig ~= last then
            last = sig
            UpdateList()
        end
    end)
    listSlip:Hide()
    -- (the pointer on the count, looked at by where it is, ten times a second: it opens the slip even where
    -- another frame of the map has the mouse and the count's own OnEnter never comes)
    local poll = 0
    list:SetScript("OnUpdate", function(self, e)
        poll = poll + e
        if poll < 0.1 then return end
        poll = 0
        local on = self:IsMouseOver()
        if listWait then
            if not on then listWait = false end
        elseif not listHover and on then
            listHover = true
            UpdateList()
        end
    end)
    list:HookScript("OnHide", function()   -- (the map shut, or another map shown: the slip goes with its count...)
        listHover = false
        if not Cfg().bossListAt then listSlip:Hide() end   -- (...unless it is unpinned from the map)
    end)
    -- (it folds when the pointer has been off the count and the slip for a moment; not while kept open by a
    -- click, while placing, or while a menu asked from one of its rows is up)
    local since = 0
    listSlip:SetScript("OnUpdate", function(self, e)
        if self.moving then
            local sc = UIParent:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            local l, t = cx / sc - self.moving[1], cy / sc - self.moving[2]
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
            if not IsMouseButtonDown("LeftButton") then
                self.moving = nil
                if Cfg().bossListAt then Cfg().bossListAt = { self:GetLeft() or l, self:GetTop() or t } end   -- (as clamped to the screen)
                UpdateList()
            end
            return
        end
        if self.fade then
            self.fade = self.fade + e
            local a = math.min(1, self.fade / 0.25)
            self:SetAlpha(a)
            if a >= 1 then self.fade = nil end
        end
        since = since + e
        if since < 0.15 then return end
        if placing or Cfg().bossListOpen or Cfg().bossListAt or self:IsMouseOver() or list:IsMouseOver()
            or (ns.QuillMenuShown and ns.QuillMenuShown()) then
            listAway, since = 0, 0
            return
        end
        listAway, since = listAway + since, 0
        if listAway >= 0.4 then
            listHover = false
            UpdateList()
        end
    end)
    -- dark glass with a gold rule (ns.GlassPanel, above; before 2026-11-14 a torn slip of pale paper with a
    -- brass pin: the user, "Not loving the pale parchment")
    ns.GlassPanel(list, 0)
    listTitle = CreateFrame("Button", nil, list)
    listTitle:SetPoint("TOPLEFT", 0, -1)
    listTitle:SetPoint("RIGHT", list, "RIGHT", -6, 0)
    listTitle:SetHeight(23)
    listTitle.text = listTitle:CreateFontString(nil, "OVERLAY")
    SetPlain(listTitle.text, 10)
    listTitle.text:SetPoint("LEFT", 10, 0)
    listTitle.count = listTitle:CreateFontString(nil, "OVERLAY")
    SetPlain(listTitle.count, 10)
    listTitle.count:SetPoint("RIGHT", -4, 0)
    listTitle.count:SetTextColor(G_GOLD[1], G_GOLD[2], G_GOLD[3])
    listTitle:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    listTitle:SetScript("OnClick", function(_, button)
        GameTooltip:Hide()
        if button == "RightButton" then ListMenu() return end
        if Cfg().bossListAt then return end   -- (unpinned: the slip is open elsewhere; its menu brings it back)
        Cfg().bossListOpen = not Cfg().bossListOpen or nil   -- (kept open, or back to opening under the pointer)
        -- (clicked shut: it stays shut while the pointer is still on the count, the user 2026-11-14)
        if not Cfg().bossListOpen then listHover, listWait = false, true end
        UpdateList()
    end)
    listTitle:SetScript("OnEnter", function(self)
        if not listWait then
            listHover = true
            UpdateList()
        end
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:AddLine("Bosses")
        -- (its explanation only while Shift is held, as the hints are: the name says enough, and the tooltip
        -- sat large over the map each time the pointer came to open the slip. The user, 2026-11-15)
        ns.ShiftLines(self, { "Bosses in kill order, then rares. Ticked when killed this run. A ringed number has a found note." })
        ns.Hints({ not Cfg().bossListAt and { "Click", Cfg().bossListOpen and "fold the list again" or "keep the list open" } or nil,
                   { "Right-click", Cfg().bossListAt and "put the list back on the map" or "unpin the list from the map" } })
        GameTooltip:Show()
    end)
    listTitle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    list.lucky = listSlip:CreateFontString(nil, "OVERLAY")   -- (the one line still in a hand: the wanderer's aside)
    SetHand(list.lucky, 12, HAND_BODY)
    list.lucky:SetTextColor(G_HAND[1], G_HAND[2], G_HAND[3])
    list.lucky:SetText("if we're lucky")
    list:Hide()
end

-- Placing ---------------------------------------------------------------------
-- /bfi bosses place: pick a boss in the list (the first not placed is picked
-- for you), click its spot on the map; the next one is picked. A marker's
-- left-click picks it to move, its right-click removes it. On Blizzard's
-- art. Saved in ns.db.bossSpots by OpenMap's
-- floor index and 0-1 across the picture; tools/boss_spots.lua bakes them into
-- Data\DungeonBosses.lua.

local function NextUnplaced(after)
    local names = Encounters(shownInstance)
    local start = 1
    for i, n in ipairs(names) do
        if n == after then start = i + 1 end
    end
    for i = start, #names do
        if not Spot(shownInstance, names[i]) then return names[i] end
    end
    for i = 1, #names do
        if not Spot(shownInstance, names[i]) then return names[i] end
    end
end

local UpdateDevList  -- (/bfi bosses list, below)

local function SpotsChanged()
    if floors then SpotBosses(floors, shownInstance) end
    DrawBosses()
    UpdateDevList()
end

function ns.RemoveBossSpot(name)
    local mine = ns.db.bossSpots[shownInstance] or {}
    ns.db.bossSpots[shownInstance] = mine
    local shipped = ns.DungeonBosses and ns.DungeonBosses[shownInstance]
    mine[name] = (shipped and shipped[name]) and false or nil
    picked = name
    SpotsChanged()
end

-- a boss a place earlier (d = -1) or later (1) in the kill order; saved as yours (ns.db.bossOrder)
function ns.MoveBoss(name, d)
    if not shownInstance then return end
    local names, kind = Encounters(shownInstance)
    local order = {}
    for _, n in ipairs(names) do if not kind[n] then order[#order + 1] = n end end
    for i, n in ipairs(order) do
        if n == name then
            local j = i + d
            if j < 1 or j > #order then return end
            order[i], order[j] = order[j], order[i]
            ns.db.bossOrder = ns.db.bossOrder or {}
            ns.db.bossOrder[shownInstance] = order
            picked = name
            SpotsChanged()
            return
        end
    end
end

-- the cursor's place on the picture, 0-1
local function CursorOnPicture()
    local x, y = GetCursorPosition()
    local s = canvas:GetEffectiveScale()
    local l, t = canvas:GetLeft(), canvas:GetTop()
    if not (l and t) then return end
    return (x / s - l) / PW, (t - y / s) / PH
end

local function Round(v) return math.floor(v * 10000 + 0.5) / 10000 end

local function PlaceAtCursor()
    local f = floors and floors[floorIndex]
    if not (placing and picked and f and f.tiles) then return end
    local x, y = CursorOnPicture()
    if not (x and x >= 0 and x <= 1 and y >= 0 and y <= 1) then return end
    local mine = ns.db.bossSpots[shownInstance] or {}
    ns.db.bossSpots[shownInstance] = mine
    mine[picked] = { f.index, Round(x), Round(y) }
    picked = NextUnplaced(picked)
    SpotsChanged()
    if not picked then ns.Log("every boss of this dungeon has a spot. /waymark bosses place again to stop.") end
end

-- (a marker dragged while placing: that boss where it was let go)
function ns.PlaceBossAtCursor(name)
    picked = name
    PlaceAtCursor()
    picked = name
    UpdateList()
end

-- the bosses' spots on a floor (OpenMap's index), 0-1: { { x, y }, ... }
function ns.DungeonBossSpots(instanceID, floor)
    local out = {}
    for _, name in ipairs(Encounters(instanceID)) do
        local s = Spot(instanceID, name)
        if s and s[1] == floor then out[#out + 1] = { s[2], s[3] } end
    end
    return out
end

function ns.ToggleBossPlacing()
    if placing then
        placing, picked = false, nil
        if ns.InkCatcherPause then ns.InkCatcherPause(false) end
        ns.Log("placing bosses: off. Your spots are saved; /reload, then tell Claude to bake them in.")
        UpdateList()
        return
    end
    if not (overlay and overlay:IsShown() and canvas:IsShown() and floors and shownInstance) then
        ns.Log("open a dungeon's map first (click its entrance on the zone map, or be inside)")
        return
    end
    if #Encounters(shownInstance) == 0 then
        ns.Log("no boss list for this instance")
        return
    end
    placing = true
    if ns.InkCatcherPause then ns.InkCatcherPause(true) end  -- (the markers take the clicks, not the quill)
    picked = NextUnplaced()
    ns.Log("placing bosses: click the gold boss's spot on the map; click a name to pick another; right-click a marker to remove it; the wheel over a name moves it in the kill order. /waymark bosses place again to stop.")
    UpdateList()
end

-- /bfi bosses list (dev, for placing): every dungeon and raid with Blizzard's
-- map, by level, with how many of its list have a spot; a click opens its map
-- as its entrance pin does. The levels are only for the order.
local DEV_LEVELS = {
    [389] = 13, [43] = 17, [36] = 18, [33] = 22, [48] = 24, [34] = 24, [90] = 29, [47] = 29, [189] = 34,
    [129] = 37, [70] = 41, [209] = 44, [349] = 46, [109] = 50, [230] = 52, [229] = 55, [429] = 57, [329] = 58,
    [289] = 58, [309] = 60, [249] = 60, [409] = 60, [469] = 60, [509] = 60, [531] = 60, [533] = 60,
}
local devList

local function DevListRows()
    local ids = {}
    for id in pairs(ns.MapDungeonMaps or {}) do
        if ns.DungeonEncounters and ns.DungeonEncounters[id] then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b)
        local la, lb = DEV_LEVELS[a] or 99, DEV_LEVELS[b] or 99
        if la ~= lb then return la < lb end
        return a < b
    end)
    return ids
end

UpdateDevList = function()
    if not (devList and devList:IsShown()) then return end
    for i, id in ipairs(devList.ids) do
        local r = devList.rows[i]
        local names = Encounters(id)
        local n = 0
        for _, name in ipairs(names) do
            if Spot(id, name) then n = n + 1 end
        end
        local e = ns.DungeonEntrances and ns.DungeonEntrances[id]
        local name = e and e[1] or (ns.MapDungeonMaps[id][1] and ns.MapDungeonMaps[id][1].name) or ("instance " .. id)
        r.text:SetText(string.format("%s  %s", DEV_LEVELS[id] or "?", name))
        r.count:SetText(n .. "/" .. #names)
        if n == #names then r.count:SetTextColor(0.3, 1, 0.3)
        elseif n > 0 then r.count:SetTextColor(1, 0.82, 0)
        else r.count:SetTextColor(0.6, 0.6, 0.6) end
        r.hl:SetShown(id == shownInstance and overlay:IsShown())
    end
end

function ns.ToggleDevBossList()
    if devList then
        devList:SetShown(not devList:IsShown())
        UpdateDevList()
        return
    end
    devList = CreateFrame("Frame", "WaymarkDevBossList", UIParent, "BasicFrameTemplateWithInset")
    devList.ids, devList.rows = DevListRows(), {}
    devList:SetSize(250, 40 + #devList.ids * 16)
    devList:SetPoint("LEFT", 40, 0)
    devList:SetFrameStrata("HIGH")
    devList:SetMovable(true)
    devList:EnableMouse(true)
    devList:RegisterForDrag("LeftButton")
    devList:SetScript("OnDragStart", devList.StartMoving)
    devList:SetScript("OnDragStop", devList.StopMovingOrSizing)
    devList:SetScript("OnShow", UpdateDevList)
    local title = devList:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
    title:SetText("Dungeon maps (dev)")
    for i, id in ipairs(devList.ids) do
        local r = CreateFrame("Button", nil, devList)
        r:SetSize(226, 16)
        r:SetPoint("TOPLEFT", 12, -28 - (i - 1) * 16)
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(1, 0.82, 0, 0.2)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", 4, 0)
        r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.count:SetPoint("RIGHT", -4, 0)
        r:SetScript("OnClick", function()
            if IsInInstance() then
                ns.Log("from outside only")
                return
            end
            local map = BattlefieldMapFrame
            local opened = not (map and map:IsShown())
            if opened and ToggleBattlefieldMap then pcall(ToggleBattlefieldMap) end
            if ns.Docked and ns.Docked() and ns.db.dock.face ~= "map" and ns.DockToggleBig then
                ns.Log("Undock to see dungeon map.")
            end
            -- (just opened: after the game puts it on your map, which would end a preview)
            C_Timer.After(opened and 0.4 or 0, function()
                ns.PreviewDungeon(id)
                UpdateDevList()
            end)
        end)
        devList.rows[i] = r
    end
    UpdateDevList()
end

-- entering or leaving an instance: keep or start a run
local RUN_TIMEOUT = 3600  -- an hour outside: a new run
local function UpdateRun()
    local r = Run()
    local inInstance = IsInInstance()
    if inInstance then
        local instanceID = select(8, GetInstanceInfo())
        if r.id ~= instanceID or (r.leftAt > 0 and time() - r.leftAt > RUN_TIMEOUT) then
            r.id, r.kills, r.copy = instanceID, {}, nil
        end
        r.name = GetInstanceInfo()                         -- (as the reset message names it)
        r.leftAt = 0
    elseif r.id and r.leftAt == 0 then
        r.leftAt = time()
    end
end

-- Minimap view ---------------------------------------------------------------------
-- Inside instances the game won't tell addons where you are, but the minimap knows
-- and draws it. So: borrow the real minimap and show it large in the map, with the
-- game's own arrow, party and detail. There's only one minimap, so while borrowed
-- it's missing from its usual place; it goes back when you switch view, leave, or
-- close the map. (Its buttons, other addons' too, are hidden meanwhile.)

-- Combat: the minimap holds protected parts (the queue button...), so moving it,
-- resizing it or hiding its children is blocked in combat ("blocked from an
-- action only available to the Blizzard UI"). Worse, a frame holding a protected
-- frame becomes protected itself, so while borrowed even our frames and the map
-- couldn't be shown or hidden in a fight. So the minimap goes back the moment
-- combat starts (PLAYER_REGEN_DISABLED comes just before the lock), the map
-- view shows during the fight, and the minimap view returns after it.
local function InCombat() return InCombatLockdown and InCombatLockdown() end

local holder, borrowed

local function FitMinimap()
    if not (borrowed and holder) or InCombat() then return end
    local s = math.min(holder:GetWidth(), holder:GetHeight())
    if s and s > 0 then Minimap:SetSize(s, s) end
end

local function Borrow()
    if borrowed or not Minimap or InCombat() then return end
    local mm = Minimap
    borrowed = { parent = mm:GetParent(), points = {}, w = mm:GetWidth(), h = mm:GetHeight(),
                 scale = mm:GetScale(), strata = mm:GetFrameStrata(), level = mm:GetFrameLevel(), hidden = {} }
    for i = 1, mm:GetNumPoints() do borrowed.points[i] = { mm:GetPoint(i) } end
    for _, child in ipairs({ mm:GetChildren() }) do
        if child:IsShown() then
            child:Hide()
            borrowed.hidden[#borrowed.hidden + 1] = child
        end
    end
    holder:Show()
    mm:SetParent(holder)
    mm:SetScale(1)
    mm:ClearAllPoints()
    mm:SetPoint("CENTER", holder, "CENTER")
    mm:SetFrameStrata(holder:GetFrameStrata())
    mm:SetFrameLevel(holder:GetFrameLevel() + 1)
    FitMinimap()
end

local function GiveBack()
    -- (in combat it can't; it already went back when combat started)
    if not borrowed or InCombat() then return end
    local mm, b = Minimap, borrowed
    borrowed = nil
    mm:SetParent(b.parent)
    mm:SetScale(b.scale)
    mm:ClearAllPoints()
    for _, p in ipairs(b.points) do mm:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
    mm:SetSize(b.w, b.h)
    mm:SetFrameStrata(b.strata)
    mm:SetFrameLevel(b.level)
    for _, child in ipairs(b.hidden) do child:Show() end
    if holder then holder:Hide() end
end
ns.GiveBackMinimap = GiveBack

-- In a cave that's a dungeon's outside floor (Cave.lua): that floor here, with everything the
-- dungeon map carries on it (ink, the book's rings, monster dots, objects), and your arrow
-- from your world position. outside = { inst, key = its floor's index, x, y = you, 0-1 on it }
local outside, you
local function PlaceYou()
    local f = floors and floors[floorIndex]
    if not (outside and overlay and overlay:IsShown() and canvas:IsShown() and f and f.index == outside.key) then
        if you then you:Hide() end
        return
    end
    if not you then
        you = CreateFrame("Frame", nil, canvas)
        you.bfiNoEdgeFade = true  -- (you: never faded away, SoftEdges.lua)
        you.tex = you:CreateTexture(nil, "OVERLAY")
        you.tex:SetAllPoints()
        if ns.CaveArrowTexture then ns.CaveArrowTexture(you.tex) end
    end
    you:SetFrameLevel(canvas:GetFrameLevel() + 30)  -- (over the rings, dots and object pins)
    local size = (ns.db.cave.arrowSize or 24) * overlay:GetEffectiveScale() / canvas:GetEffectiveScale()
    you:SetSize(size, size)
    you:ClearAllPoints()
    you:SetPoint("CENTER", canvas, "TOPLEFT", outside.x * PW, -outside.y * PH)
    local ok, facing = pcall(GetPlayerFacing)
    if ok and type(facing) == "number" then you.tex:SetRotation(facing) end
    you:Show()
end
-- (inst nil: not in such a cave)
function ns.DungeonOutside(inst, key, x, y)
    local was = outside and (outside.inst .. ":" .. outside.key)
    outside = inst and { inst = inst, key = key, x = x, y = y } or nil
    if was ~= (inst and (inst .. ":" .. key)) then ns.UpdateDungeon() end
    PlaceYou()
end
function ns.DungeonOutsideArrowStyle() if you and ns.CaveArrowTexture then ns.CaveArrowTexture(you.tex) end end

local function UpdateFallback(map)
    if not overlay then return end
    local inInstance = IsInInstance()
    -- looking at a dungeon from outside: left alone, until you go into one
    if preview and not inInstance then DrawBosses() return end  -- (its markers and list: settings may have changed)
    preview = nil
    local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    if zoneView ~= (inInstance and instanceID or nil) then zoneView = nil end
    -- only when the game didn't give us a real map of the place
    local best = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local native = best and SMALL_MAP_TYPES[MapType(best) or -1] and HasArt(best) and map:GetMapID() == best
    -- (looking at another map: the right-click out to the zone, or any browsing)
    local away = zoneView or (ns.Browsing and ns.Browsing())
    -- in a dungeon's outside cave: its outside floor (the steps still go on inside)
    if outside and not inInstance and Cfg().fallback and not away and map:IsVisible() then
        GiveBack()
        if shownInstance ~= outside.inst or not floors then
            shownInstance = outside.inst
            floors = OpenMapFloors(outside.inst)
            manualFloor = false
        end
        if not floors then
            overlay:Hide()
            shownInstance = nil
            return
        end
        if not manualFloor then
            for i, f in ipairs(floors) do if f.index == outside.key then floorIndex = i end end
        end
        overlay:Show()
        viewBtn:Hide()  -- (no minimap to borrow out here)
        canvas:Show()
        markerLayer:Show()
        floorText:Show()
        ShowFloor()
        DrawBosses()
        PlaceYou()
        return
    end
    if not (Cfg().fallback and inInstance and not native and not away and map:IsVisible()) then
        GiveBack()
        overlay:Hide()
        shownInstance = nil
        return
    end
    if shownInstance ~= instanceID then
        shownInstance = instanceID
        floors = OpenMapFloors(instanceID)
        floorIndex = 1
        while floors and floors[floorIndex + 1] and floors[floorIndex].outside do floorIndex = floorIndex + 1 end  -- (you're inside)
        manualFloor = false
    end

    -- (in combat the minimap stays in its own place: the map view meanwhile;
    -- docked over the minimap, Dock.lua, it's the other face already: the
    -- button turns to that face, unless the dock is set to the map only)
    local docked = ns.Docked and ns.Docked()
    local minimapView = Cfg().view == "minimap" and not InCombat() and not docked
    -- (docked: the square's minimap face, Dock.lua; the switch stays, all else of the dungeon map goes)
    local dockMini = docked and ns.DockDungeonMinimap and ns.DockDungeonMinimap()
    -- (docked: under the header, top left; else bottom left, over the coordinates, as in caves: the user)
    viewBtn:ClearAllPoints()
    if docked then
        viewBtn:SetPoint("TOPLEFT", overlay, "TOPLEFT", 4, -26)
    else
        viewBtn:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 6, 6 + (ns.CoordsCornerLift and ns.CoordsCornerLift() or 0) + (ns.SearchCornerLift and ns.SearchCornerLift() or 0))
    end
    if not floors and not minimapView then overlay:Hide() return end  -- (no art: the minimap view still works)
    overlay:Show()
    coversIn = instanceID
    local art = ns.MEDIA .. ((minimapView or dockMini) and "StudMap" or "StudNeedle")
    viewBtn.icon:SetTexture(art)
    viewBtn.shine:SetTexture(art)
    -- (nothing to switch to without art)
    viewBtn:SetShown(floors ~= nil)
    if ns.MapRimClearLeft then ns.MapRimClearLeft((viewBtn:IsShown() and docked) and 34 or 0) end

    if minimapView then
        canvas:Hide()
        markerLayer:Hide()
        floorText:Hide()
        prevBtn:Hide()
        nextBtn:Hide()
        UpdateList()
        Borrow()
    elseif dockMini then
        canvas:Hide()
        markerLayer:Hide()
        floorText:Hide()
        prevBtn:Hide()
        nextBtn:Hide()
        if list then list:Hide() end  -- (see-through, but its tooltips still came up)
    else
        GiveBack()
        canvas:Show()
        markerLayer:Show()
        floorText:Show()
        if not manualFloor then floorIndex = GuessedFloor() or MatchFloor() or floorIndex end
        ShowFloor()
        DrawBosses()
    end
end

-- the zone a dungeon is entered from: the map under its entrance, climbed to
-- the zone (Stockades: Stormwind City)
local function DungeonZone(instanceID)
    local e = ns.DungeonEntrances and ns.DungeonEntrances[instanceID]
    if not (e and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return end
    local ok, mapID = pcall(C_Map.GetMapPosFromWorldPos, e[3], CreateVector2D(e[4], e[5]))
    if not (ok and mapID) then return end
    local zone = MapUtil and MapUtil.GetMapParentInfo and MapUtil.GetMapParentInfo(mapID, Enum.UIMapType.Zone, true)
    return zone and zone.mapID or mapID
end

-- Right-click inside: out to the dungeon's zone map. As browsing (Browse.lua),
-- so its ways home bring the dungeon map back; where the zone is the map the
-- game calls yours, browsing can't hold it: then until you click the dungeon's
-- entrance, close the map or leave.
function ns.DungeonZoneView()
    local map = BattlefieldMapFrame
    local zone = shownInstance and DungeonZone(shownInstance)
    if not (map and zone) then return end
    GiveBack()
    overlay:Hide()
    if ns.BrowseTo then ns.BrowseTo(zone) end
    if not (ns.Browsing and ns.Browsing()) then
        zoneView = shownInstance
        map:SetMapID(zone)
    end
end

-- the dungeon map covers the map: its tooltips and hover marks stay off
function ns.DungeonMapShown() return overlay and overlay:IsShown() or false end

-- the guess moved to another floor (DungeonWhere.lua): the map turns there, unless you picked one
function ns.DungeonFollowFloor()
    if manualFloor or preview or not (overlay and overlay:IsShown() and floors) then return end
    local i = GuessedFloor()
    if not i or i == floorIndex then return end
    floorIndex = i
    centerX, centerY = 0, 0
    ShowFloor()
    DrawBosses()
end

-- a dungeon's bosses in the order they're usually killed, the rares and the friendly left out (Dangers.lua:
-- which danger is next)
function ns.DungeonBossesInOrder(instance)
    local names, kind = Encounters(instance)
    local out = {}
    for _, n in ipairs(names) do if not kind[n] then out[#out + 1] = n end end
    return out
end

-- stairs in the ink that lead to another floor (Ink.lua): a click turns the map there
function ns.DungeonGoFloor(instance, floor)
    if not (overlay and overlay:IsShown() and floors and shownInstance == instance) then return end
    for i, f in ipairs(floors) do
        if (f.index or i) == floor then
            manualFloor = true
            floorIndex = i
            centerX, centerY = 0, 0
            ShowFloor()
            DrawBosses()
            return
        end
    end
end

-- where map ink goes on it (Ink.lua): the canvas and a key for this floor,
-- while a floor's picture shows (not the borrowed minimap)
function ns.DungeonInkSurface()
    if not (overlay and overlay:IsShown() and canvas:IsShown() and shownInstance and floors) then return end
    local f = floors[floorIndex]
    if not f then return end
    return canvas, "d" .. shownInstance .. ":" .. tostring(f.index or floorIndex)
end

-- what clear view cuts on it (ClearView.lua): as the ink surface, plus the
-- floor's picture tiles and the black behind them
function ns.DungeonCutTarget()
    local c, key = ns.DungeonInkSurface()
    if not c then return end
    return c, key, tiles, overlay.bfiBg, markerLayer
end

-- In an instance where this view covers your own map (the art, or the borrowed
-- minimap), even while you've right-clicked out of it: your own map is then
-- this view, not the map under it (Browse.lua: climbing onto that one doesn't
-- bring the dungeon back; Dock.lua: the wheel on the minimap face doesn't open it)
function ns.DungeonArtHome()
    if not (Cfg().fallback and coversIn and IsInInstance()) then return false end
    return select(8, GetInstanceInfo()) == coversIn
end

local function CursorInOverlay()
    local x, y = GetCursorPosition()
    local s = overlay:GetEffectiveScale()
    return x / s, y / s
end

-- the map panned from outside (Ink.lua: right-drag while the quill's in hand): start gives the
-- state, move follows the cursor from it
function ns.DungeonPanStart()
    if not (overlay and overlay:IsShown()) then return end
    local mx, my = CursorInOverlay()
    return { mx = mx, my = my, cx = centerX, cy = centerY }
end
function ns.DungeonPanMove(p)
    local k = Layout() or 1
    local mx, my = CursorInOverlay()
    centerX = p.cx - (mx - p.mx) / k
    centerY = p.cy + (my - p.my) / k
    Layout()
end

-- above every map pin (they sit around 2000-2500): zone pins don't belong on
-- it. (The gear, town / city and toggle buttons go above this: Options.)
function ns.DungeonOverlayLevel(map)
    local area = map.ScrollContainer or map
    return math.min(area:GetFrameLevel() + 5000, 8990)
end

local function CreateOverlay(map)
    local area = map.ScrollContainer or map
    overlay = CreateFrame("Frame", nil, area)
    overlay:SetAllPoints(area)
    overlay:SetFrameLevel(ns.DungeonOverlayLevel(map))
    overlay.bfiCoversMap = true  -- (Explore's hover names: not through it)
    ns.dungeonOverlay = overlay  -- (Dock.lua: see-through on the minimap face, its double-click)
    overlay:EnableMouse(true)  -- the zone map underneath isn't where you are
    overlay.bfiTag = "dungeon map"
    overlay:EnableMouseWheel(true)
    overlay:SetClipsChildren(true)
    local bg = overlay:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 1)
    overlay.bfiBg = bg

    canvas = CreateFrame("Frame", nil, overlay)
    canvas:SetSize(PW, PH)
    tiles = {}
    for i = 1, 12 do tiles[i] = canvas:CreateTexture(nil, "ARTWORK") end

    -- boss markers: above the art, not scaled with it (they hang on canvas points)
    markerLayer = CreateFrame("Frame", nil, overlay)
    markerLayer:SetAllPoints(overlay)
    markerLayer:SetFrameLevel(canvas:GetFrameLevel() + 2)

    -- where the borrowed minimap goes
    holder = CreateFrame("Frame", nil, overlay)
    holder:SetAllPoints(overlay)
    holder:SetFrameLevel(canvas:GetFrameLevel() + 3)
    holder:SetScript("OnSizeChanged", FitMinimap)
    holder:Hide()

    overlay:SetScript("OnMouseWheel", function(_, delta)
        -- (Shift: the floors, as on the notebook's maps)
        if IsShiftKeyDown() and not borrowed and ns.DungeonStepFloor then ns.DungeonStepFloor(delta > 0 and -1 or 1) return end
        if borrowed then
            -- the minimap's own zoom levels (0 = furthest out)
            local z = Minimap:GetZoom() + (delta > 0 and 1 or -1)
            Minimap:SetZoom(math.max(0, math.min(Minimap:GetZoomLevels() - 1, z)))
            return
        end
        zoom = math.max(1, math.min(6, zoom * (delta > 0 and 1.25 or 0.8)))
        Layout()
    end)
    -- The scheme (Controls.lua): a press on a note's ring picks it up (Ctrl, or the quill out), else a
    -- drag pans; a click on a ring opens the book there; placing, a click puts the picked boss down.
    -- Right-click: a thing's menu; on empty map out to the zone (a preview: back to it), on the
    -- release (on the press the release went on to the zone map under it: a map further up), never
    -- with a modifier; the quill out: the map's menu. Boss markers and object pins hand their
    -- presses on to these.
    local spotDown
    local function Out()
        if preview then ns.EndDungeonPreview()
        elseif overlay:IsShown() and (IsInInstance() or outside) then ns.DungeonZoneView() end
    end
    function ns.DungeonMapDown(button)
        if button ~= "LeftButton" then return end
        spotDown = ns.PicksUp() and ns.QuillSpotDown and ns.QuillSpotDown(false, true) or nil
        ns.CTrace("map down: picks up", tostring(ns.PicksUp()), "ring grabbed", tostring(spotDown))
        if spotDown then return end
        local mx, my = CursorInOverlay()
        drag = { mx = mx, my = my, cx = centerX, cy = centerY }
    end
    function ns.DungeonMapUp(button)
        if button == "RightButton" then
            drag = nil
            if ns.DungeonThingMenu() then return end
            ns.MapRightClick((preview or IsInInstance() or outside) and Out or nil, preview and "back to the zone" or "out to the zone")
            return
        end
        if button ~= "LeftButton" then return end
        if spotDown then
            spotDown = nil
            if not ns.QuillSpotUp() and not IsControlKeyDown() and ns.FoundSpotOpen then ns.FoundSpotOpen() end
            return
        end
        local d = drag
        drag = nil
        if not d then return end
        local mx, my = CursorInOverlay()
        if math.abs(mx - d.mx) >= 4 or math.abs(my - d.my) >= 4 then return end
        if placing then PlaceAtCursor() return end
        if ns.DungeonWhereRecording and ns.DungeonWhereRecording() then  -- (/bfi where rec: you're here)
            local f, x, y = floors and floors[floorIndex], CursorOnPicture()
            if f and x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then ns.DungeonWhereMark(shownInstance, f.index or floorIndex, x, y) end
            return
        end
        if not IsModifierKeyDown() and ns.FoundSpotOpen then ns.FoundSpotOpen() end
    end
    overlay:SetScript("OnMouseDown", function(_, button) ns.DungeonMapDown(button) end)
    overlay:SetScript("OnMouseUp", function(_, button) ns.DungeonMapUp(button) end)
    overlay:SetScript("OnUpdate", function()
        if spotDown and ns.QuillSpotUpdate then ns.QuillSpotUpdate() end
        if not drag then return end
        local k = Layout() or 1
        local mx, my = CursorInOverlay()
        -- drag right: the picture moves right, so the view centre moves left
        centerX = drag.cx - (mx - drag.mx) / k
        centerY = drag.cy + (my - drag.my) / k
        Layout()
    end)

    -- the floor label and buttons on their own frame above the canvas (a child
    -- frame draws over its parent's textures, so on the overlay they'd be covered)
    local top = CreateFrame("Frame", nil, overlay)
    top:SetAllPoints(overlay)
    top:SetFrameLevel(canvas:GetFrameLevel() + 5)

    floorText = top:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    floorText:SetPoint("TOP", 0, -4)
    floorText:SetShadowOffset(1, -1)
    floorText.font, floorText.size = floorText:GetFont()
    floorCount = top:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    floorCount:SetPoint("BOTTOM", 0, 6)
    floorCount:SetFont(floorText.font, floorText.size, "OUTLINE")
    floorCount:Hide()
    -- the quest tracker's shade behind a line (Media\TextShade.tga: soft ends, Tracker.lua's Band)
    local function Shade(fs)
        local b = {}
        for k, l in ipairs({ 0, 0.25, 0.75 }) do
            b[k] = top:CreateTexture(nil, "BACKGROUND")
            b[k]:SetTexture(ns.MEDIA .. "TextShade")
            b[k]:SetTexCoord(l, k == 2 and 0.75 or l + 0.25, 0, 1)
            b[k]:SetVertexColor(0, 0, 0, 0.6)
            b[k]:Hide()
        end
        b[2]:SetPoint("TOPLEFT", fs, "TOPLEFT", 0, 4)
        b[2]:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 0, -4)
        b[1]:SetPoint("TOPRIGHT", b[2], "TOPLEFT")
        b[1]:SetPoint("BOTTOMRIGHT", b[2], "BOTTOMLEFT")
        b[3]:SetPoint("TOPLEFT", b[2], "TOPRIGHT")
        b[3]:SetPoint("BOTTOMLEFT", b[2], "BOTTOMRIGHT")
        b[1]:SetWidth(7)  -- (hugging the text's ends, the user)
        b[3]:SetWidth(7)
        fs.shade = function(on) for _, t in ipairs(b) do t:SetShown(on and true or false) end end
    end
    Shade(floorText)
    Shade(floorCount)
    local function Step(d)
        manualFloor = true
        floorIndex = (floorIndex - 1 + d) % #floors + 1
        centerX, centerY = 0, 0
        ShowFloor()
        DrawBosses()
    end
    ns.DungeonStepFloor = function(d) if floors and #floors > 1 then Step(d) end end
    -- (ink, no box: the user picked A in mockups/dungeon-buttons.html. The arrows in the header's gold,
    -- the switch a word in the notes' ink, underlined in red; the hit areas as the old buttons')
    local function InkButton(w, h, font, size, color, hover)
        local b = CreateFrame("Button", nil, top)
        b:SetSize(w, h)
        local fs = b:CreateFontString(nil, "OVERLAY")
        SetHand(fs, size, font)
        b:SetFontString(fs)
        b.ink, b.inkHover = color, hover
        local function Paint(over)
            local c = over and b.inkHover or b.ink
            fs:SetTextColor(c[1], c[2], c[3])
        end
        b.Paint = Paint
        b:HookScript("OnEnter", function() Paint(true) end)
        b:HookScript("OnLeave", function() Paint(false) end)
        Paint(false)
        return b, fs
    end
    local GOLD, GOLD_HI = { 1, 0.82, 0 }, { 1, 0.95, 0.77 }
    local fs
    prevBtn, fs = InkButton(22, 20, HAND, 20, GOLD, GOLD_HI)
    fs:SetShadowOffset(1, -1)
    prevBtn:SetText("<")
    prevBtn:SetPoint("RIGHT", floorText, "LEFT", -6, 0)
    prevBtn:SetScript("OnClick", function() Step(-1) end)
    nextBtn, fs = InkButton(22, 20, HAND, 20, GOLD, GOLD_HI)
    fs:SetShadowOffset(1, -1)
    nextBtn:SetText(">")
    nextBtn:SetPoint("LEFT", floorText, "RIGHT", 6, 0)
    nextBtn:SetScript("OnClick", function() Step(1) end)
    for _, b in ipairs({ prevBtn, nextBtn }) do
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(self == prevBtn and "Previous floor" or "Next floor")
            ns.Hints({ { "Shift-wheel on the map", "the floors too" } })
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- Map / Minimap switch, top left (the gear and toggle buttons are top right)
    -- (a brass stud, as the boss list's pin: a compass needle to the minimap, a folded map back; the
    -- user picked "a, needle" in mockups/dungeon-buttons.html. Small, for the docked square)
    -- (on a frame of its own beside the overlay, not in it: docked on the minimap face the overlay goes
    -- see-through (Dock.lua) and took the switch with it, the way back. Shown and hidden with it)
    local holder = CreateFrame("Frame", nil, overlay:GetParent():GetParent() or overlay:GetParent())
    holder:SetAllPoints(overlay)
    hooksecurefunc(overlay, "Show", function() holder:Show() end)
    hooksecurefunc(overlay, "Hide", function() holder:Hide() end)
    hooksecurefunc(overlay, "SetShown", function(_, on) holder:SetShown(on) end)
    holder:SetShown(overlay:IsShown())
    viewBtn = CreateFrame("Button", nil, holder)
    viewBtn:SetSize(22, 22)
    viewBtn.icon = viewBtn:CreateTexture(nil, "ARTWORK")
    viewBtn.icon:SetAllPoints()
    viewBtn.icon:SetTexture(ns.MEDIA .. "StudNeedle")
    viewBtn.shine = viewBtn:CreateTexture(nil, "HIGHLIGHT")
    viewBtn.shine:SetAllPoints()
    viewBtn.shine:SetTexture(ns.MEDIA .. "StudNeedle")
    viewBtn.shine:SetBlendMode("ADD")
    viewBtn.shine:SetAlpha(0.25)
    viewBtn:SetScript("OnMouseDown", function(self)
        self.icon:ClearAllPoints()
        self.icon:SetPoint("TOPLEFT", 1, -1)
        self.icon:SetPoint("BOTTOMRIGHT", 1, -1)
    end)
    viewBtn:SetScript("OnMouseUp", function(self)
        self.icon:ClearAllPoints()
        self.icon:SetAllPoints()
    end)
    -- (the map's top-edge strip stops short of it while it shows, Dock.lua)
    viewBtn:HookScript("OnShow", function()
        if ns.MapRimClearLeft then ns.MapRimClearLeft((ns.Docked and ns.Docked()) and 34 or 0) end
    end)
    viewBtn:HookScript("OnHide", function() if ns.MapRimClearLeft then ns.MapRimClearLeft(0) end end)
    OverRim(viewBtn)
    viewBtn:SetPoint("TOPLEFT", overlay, "TOPLEFT", 4, -4)
    viewBtn:SetScript("OnClick", function(self)
        if ns.Docked and ns.Docked() then
            -- (docked: the square's other face, the minimap; the X, the map's key or this brings it back)
            GameTooltip:Hide()  -- (the switch goes with the dungeon map)
            if ns.DockToggleDungeonMinimap then ns.DockToggleDungeonMinimap() end
            return
        end
        local c = Cfg()
        c.view = c.view == "minimap" and "art" or "minimap"
        if ns.RefreshControls then ns.RefreshControls() end
        ns.UpdateDungeon()
        -- (the tooltip says what a click does next: told again, the user)
        if GameTooltip:IsOwned(self) and self:IsMouseOver() then self:GetScript("OnEnter")(self) end
    end)
    viewBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local onMinimap = Cfg().view == "minimap" and not (ns.Docked and ns.Docked())
        GameTooltip:AddLine(onMinimap and "The dungeon's map" or "Your minimap")
        if ns.Docked and ns.Docked() then
            ns.ShiftLines(self, { "The game's minimap in this frame. Click the X or press the map key for the dungeon map." })
        else
            ns.ShiftLines(self, { "Minimap: the game's minimap in this frame.",
                                  "Map: dungeon map." })
        end
        GameTooltip:Show()
    end)
    viewBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    CreateList(top)  -- the bosses, below the switch

    overlay:SetScript("OnSizeChanged", function()
        if floors and overlay:IsShown() then
            Layout()
            UpdateList()  -- (docked: the list only on the big map)
        end
    end)
    overlay:HookScript("OnShow", function() if ns.UpdateZoneName then ns.UpdateZoneName() end end)
    overlay:HookScript("OnHide", function()
        PlaceSteps(false)  -- (off the header, back with the floor text)
        if ns.UpdateZoneName then ns.UpdateZoneName() end
    end)
    overlay:Hide()
end

-- for the header (ZoneName.lua): the floor's name and counter while a floor's picture shows
function ns.DungeonFloorTitle()
    if not (overlay and overlay:IsShown() and canvas:IsShown() and floors and floors[floorIndex]) then return end
    return titleName, titleCounter
end

-- Looking at a dungeon from outside -----------------------------------------------
-- Click a dungeon entrance on the zone map: its map opens in the same view as
-- inside (floors, boss markers); a right-click (or Back) returns to the zone.

-- (preview, declared above UpdateFallback: the instance shown because you clicked it)

local function EndPreview()
    if not preview then return end
    preview = nil
    shownInstance = nil
    overlay:Hide()
    ns.UpdateDungeon()
end
ns.EndDungeonPreview = EndPreview
function ns.DungeonPreviewing() return preview ~= nil end

function ns.PreviewDungeon(id)
    if not overlay then return end
    if IsInInstance() then
        -- the entrance of the dungeon you're in, from its zone: back inside
        if id ~= select(8, GetInstanceInfo()) then return end
        zoneView = nil
        if ns.Browsing and ns.Browsing() then ns.BrowseHome() else ns.UpdateDungeon() end
        return
    end
    local found = OpenMapFloors(id)
    local e = ns.DungeonEntrances and ns.DungeonEntrances[id]
    if not found then
        ns.Log("no map of " .. (e and e[1] or ("instance " .. id)) .. " to show")
        return
    end
    GiveBack()
    preview, shownInstance = id, id
    floors, floorIndex, manualFloor = found, 1, true
    zoom, centerX, centerY, drag = 1, 0, 0, nil
    overlay:Show()
    canvas:Show()
    markerLayer:Show()
    floorText:Show()
    viewBtn:Hide()  -- (right-click returns to the zone)
    if placing then picked = NextUnplaced() end  -- (another dungeon: its first boss without a spot)
    ShowFloor()
    DrawBosses()
end

-- Dungeon entrances on the zone map ---------------------------------------------

local ENTRANCE_TEMPLATE = "BFIDungeonPinTemplate"

local function EntranceCfg() return ns.db.dungeons end

-- the doors' map: "zone", "continent" (only with the setting: some 30 doors on one map,
-- drawn smaller), or nil (none)
local function DoorMap(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    local T = Enum and Enum.UIMapType
    if not (info and T) then return end
    if info.mapType == T.Zone then return "zone" end
    if info.mapType == T.Continent and ns.db.dungeons.continent then return "continent" end
end
local CONTINENT_SCALE = 0.6

-- where each entrance is on a map (cached per map): { id, x, y }
local entrancesOn = {}
local function EntrancesOn(mapID)
    if entrancesOn[mapID] then return entrancesOn[mapID] end
    local info = C_Map.GetMapInfo(mapID)
    local wide = info and Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.Continent
    local out = {}
    if ns.DungeonEntrances and C_Map.GetMapPosFromWorldPos and CreateVector2D then
        for id, e in pairs(ns.DungeonEntrances) do
            local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, e[3], CreateVector2D(e[4], e[5]), mapID)
            if ok and pos then
                local x, y = pos:GetXY()
                if x >= 0 and x <= 1 and y >= 0 and y <= 1 then out[#out + 1] = { id = id, x = x, y = y } end
            end
        end
    end
    -- (Forever's own dungeons, which the game's files give no entrance: the known and walked-in ones,
    -- on their own map only. The user, 2026-11-09: the Hall of Thanes)
    local function Add(id, m, x, y)
        if m == mapID and not (ns.DungeonEntrances and ns.DungeonEntrances[id]) then
            for _, o in ipairs(out) do if o.id == id then return end end
            out[#out + 1] = { id = id, x = x, y = y }
        end
    end
    for id in pairs(ns.ForeverQuestData and ns.ForeverQuestData.entrances or {}) do
        if ns.LearnedEntrance then Add(id, ns.LearnedEntrance(id)) end
    end
    for id in pairs(WaymarkDB and WaymarkDB.entrances or {}) do
        if ns.LearnedEntrance then Add(id, ns.LearnedEntrance(id)) end
    end
    -- entrances on one spot (Blackrock Mountain's four): side by side, so each can be clicked
    -- (on a continent the spot and the step are smaller, as its doors are)
    local near, step = wide and 0.004 or 0.012, wide and 0.006 or 0.014
    table.sort(out, function(a, b) return a.id < b.id end)
    for i, a in ipairs(out) do
        local n = 0
        for j = 1, i - 1 do
            local b = out[j]
            if math.abs(a.x - b.x) < near and math.abs(a.y - b.y) < near then n = n + 1 end
        end
        a.x = a.x + n * step
    end
    entrancesOn[mapID] = out
    return out
end
-- (a newly learned entrance: placed again, Learn.lua)
function ns.ForgetEntranceSpots() wipe(entrancesOn) end

-- the dungeon doors on the zone you're in (Notebook.lua: the book opens where you are)
function ns.EntrancesOnZone()
    local m = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local zone = Enum and Enum.UIMapType and Enum.UIMapType.Zone
    while m and zone do
        local info = C_Map.GetMapInfo(m)
        if not info or info.mapType < zone then return end
        if info.mapType == zone then return EntrancesOn(m) end
        m = info.parentMapID
    end
end

-- A door's tooltip: the found notes' quests for it (Notebook.lua), yours marked: in your log,
-- done, or not taken. The same on the Battlefield map and the world map. True if the book has
-- a page on it.
local function BookLines(id)
    local qs = ns.NotebookQuests and ns.NotebookQuests(id)
    if not qs then return false end
    if #qs > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Quests from the found notes", 1, 0.82, 0)
    end
    for _, q in ipairs(qs) do
        local ok, pv = pcall(ns.QuestPreview or function() end, q.quest)
        local name = ok and pv and pv.name or q.who or ("quest " .. q.quest)
        if q.state == "have" then
            GameTooltip:AddDoubleLine(name, "in your log", 1, 1, 1, 0.25, 1, 0.25)
        elseif q.state == "done" then
            GameTooltip:AddDoubleLine(name, "done", 0.55, 0.55, 0.55, 0.55, 0.55, 0.55)
        else
            GameTooltip:AddDoubleLine(name, "not taken", 0.8, 0.8, 0.8, 0.55, 0.55, 0.55)
        end
    end
    return true
end

-- The icon: the map's own dungeon entrance swirl (the `dungeon` atlas), the
-- same as the Dungeon entrances toggle button
local function EntranceIcon(pin)
    ns.SetArt(pin.Icon, "dungeon")
end

BFIDungeonPinMixin = CreateFromMixins(MapCanvasPinMixin)
BFIDungeonPinMixin.CheckMouseButtonPassthrough = ns.SafePassthrough  -- see Pin.lua

function BFIDungeonPinMixin:OnLoad()
    if self.UseFrameLevelType then pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_BFI_DUNGEONS") end
end

function BFIDungeonPinMixin:ApplyCurrentScale()
    local map = self:GetMap()
    local canvasScale = map and map.GetCanvasScale and map:GetCanvasScale() or 1
    if not canvasScale or canvasScale <= 0 then canvasScale = 1 end
    local small = DoorMap(map and map:GetMapID()) == "continent" and CONTINENT_SCALE or 1
    if map == WorldMapFrame then  -- (the world map's own size: as its other pins, not the Battlefield map's)
        self:SetScale(1.5 * small / canvasScale)
        ns.ReanchorPin(self, map)
        return
    end
    self:SetScale(ns.PinScale("dungeons", EntranceCfg().scale) * small / canvasScale)  -- (PinScale: town view, small map)
    ns.ReanchorPin(self, map)
end

function BFIDungeonPinMixin:ApplyCurrentAlpha() self:SetAlpha(ns.PinAlpha("dungeons")) end

function BFIDungeonPinMixin:OnAcquired(p)
    self.info = p
    EntranceIcon(self)
    self:ApplyCurrentScale()
    self:ApplyCurrentAlpha()
    self:SetPosition(p.x, p.y)
end

-- an entrance's name and raid flag (Forever's own: from the instance's name)
local function EntranceInfo(id)
    local e = ns.DungeonEntrances and ns.DungeonEntrances[id]
    if e then return e end
    local name = GetRealZoneText and GetRealZoneText(id)
    return { (name and name ~= "") and name or ("Instance " .. id), false }
end
ns.DungeonEntranceInfo = EntranceInfo

function BFIDungeonPinMixin:OnEnter()
    local e = EntranceInfo(self.info.id)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(e[1])
    GameTooltip:AddLine(e[2] and "Raid" or "Dungeon", 1, 1, 1)
    local book = BookLines(self.info.id)
    -- (the world map: a click opens the found notes; the Battlefield map: its map, Shift for the notes)
    local hints = {}
    if self:GetMap() == WorldMapFrame then
        if book then hints[1] = { "Click", "the found notes" } end
    else
        local has = OpenMapFloors(self.info.id)
        if not has then GameTooltip:AddLine("No map for this dungeon.", 0.6, 0.6, 0.6) end
        if has then hints[#hints + 1] = { "Click", "its map" } end
        if book then hints[#hints + 1] = { "Shift-click", "the found notes" } end
    end
    ns.PinHints(hints)
    GameTooltip:Show()
end

function BFIDungeonPinMixin:OnLeave() GameTooltip:Hide() end
-- the map wires a pin's mouse-over to these (see Pin.xml)
BFIDungeonPinMixin.OnMouseEnter = BFIDungeonPinMixin.OnEnter
BFIDungeonPinMixin.OnMouseLeave = BFIDungeonPinMixin.OnLeave

function BFIDungeonPinMixin:OnMouseUp(button)
    if button == "RightButton" then  -- (its menu: Controls.lua)
        local id = self.info.id
        local items = {}
        if self:GetMap() ~= WorldMapFrame and OpenMapFloors(id) then
            items[1] = { "dungeon map", function() ns.PreviewDungeon(id) end }
        end
        if ns.NotebookQuests and ns.NotebookQuests(id) then
            items[#items + 1] = { "found notes: quests", function() ns.OpenNotebook(id, nil, true) end }
        end
        if ns.HasBossLoot and ns.HasBossLoot(id) then items[#items + 1] = { "what they carry", function() ns.OpenBossLoot(id) end } end
        ns.PinMenu(self, items, EntranceInfo(id)[1])
        return
    end
    local book = button == "LeftButton" and ns.NotebookQuests and ns.NotebookQuests(self.info.id)
    if book and (IsShiftKeyDown() or self:GetMap() == WorldMapFrame) then
        ns.OpenNotebook(self.info.id, nil, true)  -- (its "before we go" page: who asked us)
    elseif self:GetMap() == WorldMapFrame then
        return
    elseif button == "LeftButton" and not IsModifierKeyDown() then
        ns.PreviewDungeon(self.info.id)
    elseif ns.PinAltClick then
        ns.PinAltClick(self, button)  -- line target (Line.lua)
    end
end

-- The world map's doors (the game's world map, not the Battlefield map): our pins there, with the
-- found notes' quests on hover and a click to the book. A client whose world map draws its own
-- dungeon entrances keeps them; the lines and the Shift-click go on those instead.
BFIWorldDungeonProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)
function BFIWorldDungeonProviderMixin:RemoveAllData()
    local map = self:GetMap()
    pcall(map.RemoveAllPinsByTemplate, map, "BFIDungeonPinTemplate")
end
function BFIWorldDungeonProviderMixin:RefreshAllData()
    self:RemoveAllData()
    local map = self:GetMap()
    local mapID = map:GetMapID()
    if not (DoorMap(mapID) and ns.IsShown("dungeons")) then return end
    for _, p in ipairs(EntrancesOn(mapID)) do
        pcall(map.AcquirePin, map, "BFIDungeonPinTemplate", p)
    end
end
function BFIWorldDungeonProviderMixin:OnMapChanged() self:RefreshAllData() end

local function GameDoorID(pin)
    local name = pin and (pin.name or pin.dungeonName)
    if not name then return end
    for id, e in pairs(ns.DungeonEntrances or {}) do
        if e[1] == name then return id end
    end
end

function ns.SetupWorldMapDoors()
    if not (WorldMapFrame and WorldMapFrame.AddDataProvider) then return end
    local game = DungeonEntranceDataProviderMixin
    local theirs = false
    for dp in pairs(WorldMapFrame.dataProviders or {}) do
        if game and dp.RefreshAllData == game.RefreshAllData then theirs = true end
    end
    if theirs and DungeonEntrancePinMixin then
        hooksecurefunc(DungeonEntrancePinMixin, "OnMouseEnter", function(pin)
            local id = GameDoorID(pin)
            if id and GameTooltip:IsOwned(pin) and BookLines(id) then
                ns.Hints({ { "Shift-click", "the found notes" } })
                GameTooltip:Show()
            end
        end)
        if DungeonEntrancePinMixin.OnMouseClickAction then
            hooksecurefunc(DungeonEntrancePinMixin, "OnMouseClickAction", function(pin, button)
                local id = GameDoorID(pin)
                if id and button == "LeftButton" and IsShiftKeyDown() and ns.NotebookQuests(id) then
                    ns.OpenNotebook(id, nil, true)
                end
            end)
        end
        return
    end
    -- (the pins' frame level, as on the Battlefield map: BattlefieldInfo.lua)
    local mgr = WorldMapFrame.GetPinFrameLevelsManager and WorldMapFrame:GetPinFrameLevelsManager()
    if mgr then pcall(mgr.AddFrameLevel, mgr, "PIN_FRAME_LEVEL_BFI_DUNGEONS") end
    local provider = CreateFromMixins(BFIWorldDungeonProviderMixin)
    if pcall(WorldMapFrame.AddDataProvider, WorldMapFrame, provider) then
        ns.worldDoors = provider
    end
end

BFIDungeonProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)

function BFIDungeonProviderMixin:RemoveAllData()
    local map = self:GetMap()
    pcall(map.RemoveAllPinsByTemplate, map, ENTRANCE_TEMPLATE)
end
function BFIDungeonProviderMixin:RefreshAllData() self:Draw() end
function BFIDungeonProviderMixin:OnMapChanged()
    EndPreview()  -- (another map: the preview was of this one's dungeon)
    self:Draw()
end

function BFIDungeonProviderMixin:Draw()
    self:RemoveAllData()
    local map = self:GetMap()
    local mapID = map:GetMapID()
    if not (mapID and ns.IsShown("dungeons")) then return end
    -- on zone maps; on continents too with the setting (smaller there)
    if not DoorMap(mapID) then return end
    for _, p in ipairs(EntrancesOn(mapID)) do
        pcall(map.AcquirePin, map, ENTRANCE_TEMPLATE, p)
    end
end

-- Probe ---------------------------------------------------------------------

function ns.Probe()
    local L = ns.Log
    local inInstance, kind = IsInInstance()
    local name, iType, _, _, _, _, _, instanceID = GetInstanceInfo()
    L("instance:", tostring(inInstance), tostring(kind), "|", tostring(name), tostring(iType), "id", tostring(instanceID))
    local best = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local mtype, info = MapType(best)
    L("best map:", tostring(best), info and info.name or "-", "type", tostring(mtype), "art", tostring(best and C_Map.GetMapArtID and C_Map.GetMapArtID(best)))
    local pos = best and C_Map.GetPlayerMapPosition(best, "player")
    L("position on it:", pos and string.format("%.3f, %.3f", pos.x, pos.y) or "none (the game won't say)")
    local map = BattlefieldMapFrame
    L("Battlefield Map shows:", tostring(map and map:GetMapID()), map and map:IsShown() and "(open)" or "(closed)")
    L("Blizzard art (OpenMap data):", OpenMapFloors(instanceID) and "yes" or "no")

    -- What else the client gives inside, for finding your position another way.
    -- (pcall + type checks: some of these are blocked, or "secret", in instances)
    local function Show(v)
        if type(v) == "number" then return string.format("%.2f", v) end
        return tostring(v) .. " (" .. type(v) .. ")"
    end
    local ok, a, b, c, d = pcall(UnitPosition, "player")
    L("raw world position (UnitPosition):", ok and (Show(a) .. ", " .. Show(b) .. ", z " .. Show(c) .. ", map " .. Show(d)) or ("error: " .. tostring(a)))
    local okF, facing = pcall(GetPlayerFacing)
    local okS, speed, run = pcall(GetUnitSpeed, "player")
    L("facing:", okF and Show(facing) or "error", "| speed:", okS and (Show(speed) .. " (run " .. Show(run) .. ")") or "error",
      "| indoors:", tostring(IsIndoors and IsIndoors()))
    L("sub-zone:", tostring(GetSubZoneText and GetSubZoneText()), "| minimap zone:", tostring(GetMinimapZoneText and GetMinimapZoneText()),
      "| zone:", tostring(GetZoneText and GetZoneText()))
    L("Run this in two different spots inside: if the position numbers change, we have it.")
end

-- Setup ---------------------------------------------------------------------

function ns.UpdateDungeon()
    local map = BattlefieldMapFrame
    if not map then return end
    pcall(Follow, map)
    pcall(UpdateFallback, map)
end

-- The game's Battlefield Map is for battlegrounds and the open world only
-- (GetBattlefieldMapInstanceType is nil in a dungeon): there its Toggle just
-- closes it, and its zone and widget events close it again. In a dungeon or
-- raid: Toggle opens and closes it, the widget events leave it be, and on
-- entering it stays (or opens) with showInside; else the game closes it as before.
local KEEP_EVENTS = { PLAYER_ENTERING_WORLD = true, ZONE_CHANGED_NEW_AREA = true,
                      UPDATE_ALL_UI_WIDGETS = true, UPDATE_UI_WIDGET = true }

local function InDungeon()
    local inInstance, kind = IsInInstance()
    return inInstance and (kind == "party" or kind == "raid")
end

local function AllowInDungeons(map)
    local gameToggle = map.Toggle
    if gameToggle then
        function map:Toggle(...)
            if not InDungeon() then
                -- (the game's own Toggle saves "2" in the open world, and "2" leaves the map closed
                -- after a reload there; "1" is what reopens it)
                gameToggle(self, ...)
                if self:IsShown() then SetCVar("showBattlefieldMinimap", "1") end
                return
            end
            if self:IsShown() then
                SetCVar("showBattlefieldMinimap", "0")
                self:Hide()
            else
                -- ("1", as the game's own Toggle: the value it opens the map with at
                -- login; "2" left it closed after every reload)
                SetCVar("showBattlefieldMinimap", "1")
                self:Show()
            end
        end
    end
    local gameOnEvent = map:GetScript("OnEvent")
    if not (gameOnEvent and MapCanvasMixin and MapCanvasMixin.OnEvent) then return end
    map:SetScript("OnEvent", function(self, event, ...)
        if KEEP_EVENTS[event] and InDungeon() then
            local entering = event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA"
            if not entering or Cfg().showInside then
                MapCanvasMixin.OnEvent(self, event, ...)
                if entering then
                    local mapID = MapUtil.GetDisplayableMapForPlayer()
                    if mapID then self:SetMapID(mapID) end
                    self:Show()
                end
                return
            end
        end
        -- (open world: we save "1", which the game reads as battlegrounds only, and all four
        -- events run its show-or-hide check, so it closed on every zone change and left a pin's
        -- tooltip on the cursor; the user, 2026-11-03. An open map is never hidden here.)
        if KEEP_EVENTS[event] and self:IsShown() and not InDungeon() then
            MapCanvasMixin.OnEvent(self, event, ...)
            if (event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA")
                and not (ns.HoldOnTaxi and ns.HoldOnTaxi()) then
                local mapID = MapUtil.GetDisplayableMapForPlayer()
                if mapID then self:SetMapID(mapID) end
            end
            return
        end
        return gameOnEvent(self, event, ...)
    end)
end

function ns.SetupDungeon(map)
    local T = Enum and Enum.UIMapType or {}
    for _, k in ipairs({ "Dungeon", "Micro", "Orphan" }) do
        if T[k] then SMALL_MAP_TYPES[T[k]] = true end
    end
    CreateOverlay(map)
    pcall(AllowInDungeons, map)

    local events = ns.TimedFrame("Dungeon")
    -- (no combat log: on this client it's off-limits to addons, and even
    -- registering or unregistering it is a forbidden action. Kills come from
    -- ENCOUNTER_END and BOSS_KILL.)
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
                         "ENCOUNTER_END", "BOSS_KILL", "PLAYER_LOGOUT", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
                         "UNIT_HEALTH", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "CHAT_MSG_SYSTEM" }) do
        pcall(events.RegisterEvent, events, e)
    end
    events:SetScript("OnEvent", function(_, event, ...)
        if ns.DungeonsOff then return end
        if event == "UNIT_HEALTH" then
            local unit = ...
            if unit == "target" or unit == "mouseover" then
                CheckDeadUnit(unit)
                -- (at no health it isn't dead yet: a rare has no encounter to end, so look again)
                -- (live Forever hands addons a secret number here: it can't be compared, so no second look)
                local hp = UnitExists(unit) and UnitHealth(unit)
                if hp and not (issecretvalue and issecretvalue(hp)) and hp == 0 then
                    C_Timer.After(0.5, function() CheckDeadUnit(unit) end)
                end
            end
            return
        end
        if event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" then
            local unit = event == "PLAYER_TARGET_CHANGED" and "target" or "mouseover"
            CheckCopy(unit)
            CheckDeadUnit(unit)
            return
        end
        if event == "CHAT_MSG_SYSTEM" then
            CheckReset(...)
            return
        end
        if event == "PLAYER_LOGOUT" then
            GiveBack()  -- never log out with the minimap borrowed
            -- (open at logout or reload: open again after it, however it was opened; a map only a
            -- profile has hidden counts as open)
            local open = map:IsShown() or (ns.MapHiddenByProfile and ns.MapHiddenByProfile())
            SetCVar("showBattlefieldMinimap", open and "1" or "0")
            return
        end
        if event == "PLAYER_REGEN_DISABLED" then
            -- just before the combat lock: the last moment it may be moved
            GiveBack()
            pcall(UpdateFallback, map)
            return
        end
        if event == "PLAYER_REGEN_ENABLED" then
            pcall(UpdateFallback, map)  -- back to the minimap view, if that's the choice
            return
        end
        if event == "ENCOUNTER_END" then
            local _, encounterName, _, _, success = ...
            if ns.Known(success) == 1 then MarkKilled(encounterName) end
            return
        end
        if event == "BOSS_KILL" then
            local _, encounterName = ...
            MarkKilled(encounterName)
            return
        end
        if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
            UpdateRun()
        end
        if event == "PLAYER_ENTERING_WORLD" and Cfg().showInside then
            local inInstance, kind = IsInInstance()
            if inInstance and (kind == "party" or kind == "raid") and not map:IsShown() then map:Show() end
        end
        -- the game also resets the map on these; act just after it
        C_Timer.After(0.2, ns.UpdateDungeon)
    end)
    -- closing the map gives the minimap back straight away (and ends a preview)
    map:HookScript("OnHide", function()
        GiveBack()
        zoneView = nil
        EndPreview()
        if placing then ns.ToggleBossPlacing() end
    end)

    -- dungeon entrances on zone maps: click one to see its map
    local provider = CreateFromMixins(BFIDungeonProviderMixin)
    if pcall(map.AddDataProvider, map, provider) then
        function ns.RedrawDungeonEntrances()
            if map:IsShown() then ns.Safe("Dungeon entrances", provider.Draw, provider) end
            if ns.worldDoors and WorldMapFrame:IsShown() then
                ns.Safe("World map doors", ns.worldDoors.RefreshAllData, ns.worldDoors)
            end
        end
    end
    ns.Safe("World map doors", ns.SetupWorldMapDoors)

    -- caves have no zone event at every entrance, so check now and then too
    local elapsed = 0
    local ticker = ns.TimedFrame("Dungeon tick")
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 2 or not map:IsVisible() or ns.DungeonsOff then return end
        elapsed = 0
        ns.UpdateDungeon()
    end)
end
