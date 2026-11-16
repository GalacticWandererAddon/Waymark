local _, ns = ...

-- Boats, zeppelins and the tram on the Battlefield Map (ns.db.transports: shown, alpha, scale, boats,
-- zeppelins, trams, continent (on the continents' maps too), routes).
--
-- INK ON THE MAP, NOT PINS (the user, 2026-11-13: "Decouple it from townsfolk alltogether, it shouldnt act in
-- the same context as map pins"). Nothing here is a map pin: no pin template, no pin group, no pin size or
-- opacity, no mouse. It is drawn on the map's sheet like the map's own art, under every pin:
--   a dotted line along the way each boat and zeppelin really goes, bend for bend, from the game's own paths
--     (Data\TransportPaths.lua, tools\transport_paths.py). On a continent's map only, at its four widest
--     zoom steps (nearer, and on a zone's map, the loops by the piers crowded the coast). Where the
--     game jumps the boat to the other continent, a painted way runs on to the map's edge, "to Booty Bay" there;
--   (ns.db.transports.marks, OFF since 2026-11-13) a quiet mark where each one leaves from: a small anchor at a pier, a small pennant on its mast at a
--     tower, the tram at its stop. NO SHIP stands at a pier (the user, 2026-11-13: "We can remove the
--     stationary boats ... a small pier or nautical texture, for undiscovered ones, has to be subtle"): a
--     ship on the map is only ever a real boat at its real place (Lab\Boats.lua), and while one is drawn
--     its piers' anchors stand down. Placed where the path's own stop lies (the tram and any stop the game
--     can't place: by hand, SPOTS).
-- Art: Media\Marks\Anchor.tga, Mast.tga (tools\pier_marks.py), Tram.tga, RouteDots.tga. Worked out once
-- per map; a zoom only changes sizes.
-- Removed 2026-11-13: the pins and their tooltip, the cog and woodcut marks and their setting, the reckoned
-- sea ways (Data\BoatRoutes.lua, tools\boat_routes.py) and the straight zeppelin lines.

local MARKS = ns.MEDIA .. "Marks\\"
local ART = { boat = "Anchor", zeppelin = "Mast", skyship = "Mast", tram = "Tram" }
local QUIET = { Anchor = true, Mast = true }   -- (the small ones: MARK_QUIET px, not MARK)
local SWITCH = { boat = "boats", zeppelin = "zeppelins", skyship = "zeppelins", tram = "trams" }  -- (skyships fly: with the zeppelins)

-- [uiMap] = { { "boat", "zeppelin", "skyship" or "tram", x, y, where it goes, where it's from, only on
-- "era" or "forever" (Forever's Menethil boat stops at Southshore on its way round) }, ... }
-- x, y: by hand, map percentages; used for the tram and wherever the game can't place the path's own stop.
local SPOTS = {
    [1437] = { { "boat", 4.6, 57.1, "Auberdine", "Menethil Harbor", "era" }, { "boat", 4.6, 57.1, "Southshore", "Menethil Harbor", "forever" },
               { "boat", 4.9, 63.6, "Theramore", "Menethil Harbor" } },
    [1424] = { { "boat", 48.5, 62.0, "Auberdine", "Southshore", "forever" } },
    [1446] = { { "boat", 67.0, 22.5, "Powderfuse Port", "Steamwheedle Port", "forever" } },
    [1453] = { { "tram", 69.0, 30.8, "Ironforge", "Stormwind" }, { "boat", 42.2, 49.9, "Auberdine", "Stormwind Harbor", "forever" } },
    [2521] = { { "skyship", 68, 92, "Dalaran", "Valanaar", "forever" }, { "skyship", 62, 96, "Skywatcher Plateau", "Valanaar", "forever" } },
    [1416] = { { "skyship", 15, 80, "Valanaar", "Dalaran", "forever" } },
    [1412] = { { "skyship", 45, 55, "Valanaar", "Skywatcher Plateau", "forever" } },
    [2548] = { { "boat", 79.0, 52.3, "Steamwheedle Port", "Powderfuse Port", "forever" } },
    [1455] = { { "tram", 76.6, 51.2, "Stormwind", "Ironforge" } },
    [1445] = { { "boat", 71.6, 56.4, "Menethil Harbor", "Theramore" } },
    [1439] = { { "boat", 32.4, 43.8, "Menethil Harbor", "Auberdine" }, { "boat", 33.2, 40.2, "Rut'theran Village", "Auberdine" },
               { "boat", 32.6, 45.4, "Stormwind Harbor", "Auberdine", "forever" } },
    [1438] = { { "boat", 52.4, 89.4, "Auberdine", "Rut'theran Village" } },
    [1413] = { { "boat", 63.7, 38.6, "Booty Bay", "Ratchet" } },
    [1434] = { { "boat", 25.9, 73.1, "Ratchet", "Booty Bay" },
               { "zeppelin", 31.5, 29.9, "Orgrimmar", "Grom'gol" }, { "zeppelin", 31.3, 28.2, "Undercity", "Grom'gol" } },
    [1444] = { { "boat", 31.0, 39.8, "the Forgotten Coast", "Feathermoon Stronghold" },
               { "boat", 43.3, 42.8, "Feathermoon Stronghold", "the Forgotten Coast" } },
    [1411] = { { "zeppelin", 50.8, 13.8, "Undercity", "Orgrimmar" }, { "zeppelin", 50.6, 12.6, "Grom'gol", "Orgrimmar" } },
    [1420] = { { "zeppelin", 60.7, 58.8, "Orgrimmar", "the Undercity" }, { "zeppelin", 61.9, 59.0, "Grom'gol", "the Undercity" } },
}

local function Cfg() return ns.db.transports end
local function Client() return ns.FOREVER and "forever" or "era" end

local FULL_AT = 560   -- map units across the map's view: from here down, marks and words shrink
local FONT = 14
local MARK = 24       -- px on screen, the tram's mark at size 1 on a full map
local MARK_QUIET = 16 -- the same for an anchor or a mast: small, they only say "from here"
local DOTS = MARKS .. "RouteDots"
local INK = { 0.24, 0.13, 0.07 }
local THICK = 3.5     -- px on screen
local EDGE = 0.01
local TOL = 0.0025    -- of the map: a bend that moves the line less than this is dropped
local JUMP = 150 * 150   -- yards, squared: a stretch ending this near the next one's start is one loop, no jump
local ROUTE_STEPS = 4 -- the dotted ways show on a continent's map at its four widest zoom steps only (see Draw)
local FADE = 4        -- dotted stretches at a drawn way's start that come up from nothing
local LABEL_GAP = 16  -- px between two labels' middles on one edge
local LABEL_LIFT = 9  -- px a label sits off its line's end

-- a small map (docked over the minimap, ~350 across) gets smaller marks and words: at full size they
-- covered the continent (the user, 2026-11-08). 1 at FULL_AT and wider, never under 0.55
local function Small(map)
    local sc = map and map.ScrollContainer
    local w = sc and sc:GetWidth()
    if not (w and w > 0) then return 1 end
    return math.max(0.55, math.min(1, w / FULL_AT))
end

local function Name(s) return (s:gsub("^the ", ""):lower()) end

-- which zoom step the map is at or heading for: 1 at its widest
local function ZoomStep(map)
    local sc = map and map.ScrollContainer
    local levels = sc and sc.zoomLevels
    if not (levels and levels[1] and sc.GetCanvasScale) then return 1 end
    local s = sc.targetScale or sc:GetCanvasScale()
    if type(s) ~= "number" then return 1 end
    local step = 1
    for i, z in ipairs(levels) do
        if z.scale and s >= z.scale - 1e-4 then step = i end
    end
    return step
end

-- A spot's place on its zone's map, in percent: the stop of the real path that goes from its place to where
-- it says it goes, if that stop lies on the zone's map; else as set by hand. Asked once a spot (again while
-- the game can't say yet). Also notes the spot's path (spot.path), for Lab\Boats.lua.
local function SpotXY(zone, spot)
    if spot.real == nil and ns.TransportPaths and ns.WorldToMap then
        local client = Client()
        local from, to = Name(spot[5]), Name(spot[4])
        local found
        for _, p in ipairs(ns.TransportPaths) do
            if p[2] == spot[1] and (not p[3] or p[3] == client) then
                local here, there
                for _, s in ipairs(p.stops) do
                    if Name(s[1]) == from then here = here or s elseif Name(s[1]) == to then there = s end
                end
                if here and there then found = here spot.path = p[1] break end
            end
        end
        if not found then
            spot.real = false
        else
            local mx, my = ns.WorldToMap(zone, found[3], found[4], found[2])
            if mx then
                if mx > 0 and mx < 1 and my > 0 and my < 1 then
                    spot.real = { mx * 100, my * 100 }
                else
                    spot.real = false
                end
            end
        end
    end
    if spot.real then return spot.real[1], spot.real[2] end
    return spot[2], spot[3]
end

-- a bent line with the points dropped that it can do without (none moves it more than TOL of the map)
local function Thin(run)
    local n = #run / 2
    if n < 3 then return run end
    local keep = { [1] = true, [n] = true }
    local stack = { 1, n }
    while #stack > 0 do
        local b = table.remove(stack)
        local a = table.remove(stack)
        local ax, ay, bx, by = run[a * 2 - 1], run[a * 2], run[b * 2 - 1], run[b * 2]
        local dx, dy = bx - ax, by - ay
        local len = (dx * dx + dy * dy) ^ 0.5
        local worst, at = TOL, nil
        for i = a + 1, b - 1 do
            local px, py = run[i * 2 - 1] - ax, run[i * 2] - ay
            local d
            if len < 1e-9 then
                d = (px * px + py * py) ^ 0.5
            else
                local f = (px * dx + py * dy) / (len * len)
                f = f < 0 and 0 or f > 1 and 1 or f
                d = ((px - dx * f) ^ 2 + (py - dy * f) ^ 2) ^ 0.5
            end
            if d > worst then worst, at = d, i end
        end
        if at then
            keep[at] = true
            stack[#stack + 1] = a stack[#stack + 1] = at
            stack[#stack + 1] = at stack[#stack + 1] = b
        end
    end
    local out = {}
    for i = 1, n do
        if keep[i] then out[#out + 1] = run[i * 2 - 1] out[#out + 1] = run[i * 2] end
    end
    return out
end

-- Routes ------------------------------------------------------------------------------------------------
-- for the map shown: { x1, y1, x2, y2, ..., label = at the last point, or nil }, 0-1 on the map
local legs = {}
local legsFor

-- A boat's path is stretches (one a continent); each is drawn where it lies on the map. Where a stretch ends
-- the game takes the boat out of sight and puts it down elsewhere. What the map draws from there:
--   to the other continent: a PAINTED way on to the edge of the map (the path's `sea`, tools\sea_ways.py:
--     by sea round the land, bent like a pen's line; the user, 2026-11-13: "I know there is no route across
--     the ocean, but paint one on that looks believeable"), with "to Booty Bay" where it leaves the map.
--     On a zone's map the same way, cut where it leaves the zone's sheet. So a name only ever stands at an
--     edge, at the end of a line that goes there;
--   A stretch is drawn a little off where the boat sails, on purpose (the path's `draw`, tools\transport_paths.py
--     _natural; the user's own sketch, 2026-11-13: "more natural starts and ends ... it reduces accuracy, but its
--     needed"): it swings into the painted way early in one curve, and it comes up out of nothing at its start;
--   back in sight at once on the same land (Rut'theran's round, drawn in one piece): the line runs on;
--   back in sight FAR OFF on the same land (the Grom'gol-Undercity zeppelin, flown unseen the length of the
--     Eastern Kingdoms): NO way is drawn for it at all (OverLand). Joined up it was two dotted lines down the
--     whole continent (the user, 2026-11-15: "I want no lines running across like this. The lines from ships
--     going out to sea can stay"), and without the join its two ends are tails that lead nowhere;
--   to a place no map here shows (a skyship's island): the name where it is lost to sight. (No skyship is
--     drawn since 2026-11-15, see FindLegs: this is what was there, kept for a path that may come.)
local CONT = { [1] = 1414, [0] = 1415 }   -- the world's instance: its continent's map

-- Is this a transport the game takes out of sight and sets down far off on the same land? (asked once a path)
local function OverLand(p)
    if p.overland == nil then
        p.overland = false
        for li, leg in ipairs(p.legs) do
            local nxt = p.legs[li % #p.legs + 1]
            if nxt ~= leg and nxt[1] == leg[1] then
                local dx, dy = nxt[2] - leg[#leg - 2], nxt[3] - leg[#leg - 1]
                if dx * dx + dy * dy > JUMP then p.overland = true end
            end
        end
    end
    return p.overland
end

-- where a continent's map lies on the map shown (left, right, top, bottom, as that continent's own 0-1)
local function Sheet(mapID, cont)
    if not cont then return end
    if mapID == cont then return 0, 1, 0, 1 end
    -- (the map shown on the continent: turned about, to bring the continent's points onto the map)
    local ok, l, r, t, b = pcall(C_Map.GetMapRectOnMap, mapID, cont)
    if ok and l and r > l and b > t then return l, r, t, b end
end

-- the first stop on the stretches after stretch li (the stops are in the path's order)
local function NextStop(p, li)
    for k = 1, #p.legs do
        local after = p.legs[(li + k - 1) % #p.legs + 1]
        for _, s in ipairs(p.stops) do
            if s[2] == after[1] then
                for i = 2, #after, 3 do
                    if math.abs(after[i] - s[3]) < 1 and math.abs(after[i + 1] - s[4]) < 1 then return s[1] end
                end
            end
        end
    end
    return "sea"
end

local function FindLegs(mapID)
    wipe(legs)
    local paths = ns.TransportPaths
    if not (paths and ns.WorldToMap) then return end
    local c = Cfg()
    local client = Client()
    for _, p in ipairs(paths) do
        -- (no skyship's way either: a short arc over land and "to Valanaar" set on the map's art where it is
        -- lost to sight. The user, 2026-11-15: "Remove them. I dont want that text on the mapart, also, dont
        -- know how else to show it. I'll figure it out for 1.3.1")
        if c[SWITCH[p[2]]] and (not p[3] or p[3] == client) and not OverLand(p) and p[2] ~= "skyship" then
            for li, leg in ipairs(p.legs) do
                local inst = leg[1]
                if ns.WorldToMap(mapID, leg[2], leg[3], inst) then
                    -- (the stretch as it is drawn, where that is not where the boat sails: p.draw)
                    local src, first, step = leg, 2, 3
                    local drawn = p.draw and p.draw[li]
                    if drawn then src, first, step = drawn, 1, 2 end
                    local run, lx, ly, last
                    local function Close()
                        if run and #run >= 4 then
                            local head = run.fromStart and math.min(FADE + 1, #run / 2 - 1) or 0
                            if head >= 2 then
                                -- a drawn stretch comes in out of nothing: its first few dots stay as they
                                -- are (not thinned away), to be faded in
                                local rest = {}
                                for k = head * 2 - 1, #run do rest[#rest + 1] = run[k] end
                                rest = Thin(rest)
                                last = {}
                                for k = 1, (head - 1) * 2 do last[k] = run[k] end
                                for k = 1, #rest do last[#last + 1] = rest[k] end
                                last.fade = head - 1
                            else
                                last = Thin(run)
                            end
                            legs[#legs + 1] = last
                        else
                            last = nil
                        end
                        run = nil
                    end
                    for i = first, #src, step do
                        local mx, my = ns.WorldToMap(mapID, src[i], src[i + 1], inst)
                        if mx and mx >= EDGE and mx <= 1 - EDGE and my >= EDGE and my <= 1 - EDGE then
                            if not run then run = { fromStart = drawn ~= nil and i == first } end
                            if mx ~= lx or my ~= ly then
                                run[#run + 1] = mx
                                run[#run + 1] = my
                                lx, ly = mx, my
                            end
                        else
                            Close()
                            lx, ly = nil, nil
                        end
                    end
                    local open = run ~= nil
                    Close()
                    -- the stretch ran to its own end on this map: what then?
                    local nxt = p.legs[li % #p.legs + 1]
                    if open and last then
                        local ex, ey = last[#last - 1], last[#last]
                        local way = p.sea and nxt[1] ~= inst and p.sea[inst]
                        local l, r, t, b = Sheet(mapID, CONT[inst])
                        if way and l then
                            -- a jump to the other continent: the painted way on to the map's edge, the name there
                            for i = 3, #way, 2 do
                                local x, y = (way[i] - l) / (r - l), (way[i + 1] - t) / (b - t)
                                local cx = x < EDGE and EDGE or x > 1 - EDGE and 1 - EDGE or x
                                local cy = y < EDGE and EDGE or y > 1 - EDGE and 1 - EDGE or y
                                if cx ~= x or cy ~= y then
                                    -- it leaves the sheet between the last point and this one: cut it there
                                    local f = 1
                                    if x ~= ex then f = math.min(f, (cx - ex) / (x - ex)) end
                                    if y ~= ey then f = math.min(f, (cy - ey) / (y - ey)) end
                                    if f < 0 then f = 0 end
                                    ex, ey = ex + (x - ex) * f, ey + (y - ey) * f
                                    last[#last + 1] = ex
                                    last[#last + 1] = ey
                                    last.label = "to " .. NextStop(p, li)
                                    break
                                end
                                last[#last + 1] = x
                                last[#last + 1] = y
                                ex, ey = x, y
                                if i >= #way - 1 then last.label = "to " .. NextStop(p, li) end
                            end
                        elseif nxt[1] == inst then
                            -- the same land: the boat is back in sight at once at the next stretch's start (a
                            -- round's end and its start): the line runs on to it. (Never far: see OverLand)
                            local nx, ny = ns.WorldToMap(mapID, nxt[2], nxt[3], inst)
                            if nx and nx >= EDGE and nx <= 1 - EDGE and ny >= EDGE and ny <= 1 - EDGE then
                                last[#last + 1] = nx
                                last[#last + 1] = ny
                            end
                        else
                            -- somewhere the map can't show (a skyship's island): named where it is lost to sight
                            last.label = "to " .. NextStop(p, li)
                        end
                    end
                end
            end
        end
    end
end

-- Drawing -----------------------------------------------------------------------------------------------

local host, holder
local lines, labels, tags, marks = {}, {}, {}, {}

local function Label(i)
    local f = labels[i]
    if not f then
        f = holder:CreateFontString(nil, "OVERLAY")
        f:SetFont(ns.MEDIA .. "Fonts\\Felipa-Regular.ttf", FONT, "OUTLINE")
        -- parchment-pale letters in a thin dark outline: clear on paper, sea and the game's own art
        f:SetTextColor(0.96, 0.89, 0.72)
        f:SetShadowOffset(0, 0)
        labels[i] = f
    end
    return f
end

local function Draw(map)
    if not host then return end
    local mapID = map:GetMapID()
    local info = mapID and C_Map.GetMapInfo(mapID)
    local c = Cfg()
    if not (info and ns.IsShown("transports")) then
        host:Hide()
        legsFor = nil
        return
    end
    local T = Enum.UIMapType or {}
    local continent = info.mapType == T.Continent
    local wide = continent or info.mapType == T.World
    if wide and not c.continent then
        host:Hide()
        legsFor = nil
        return
    end
    local canvas = map:GetCanvas()
    local W, H = canvas:GetWidth(), canvas:GetHeight()
    local scale = map:GetCanvasScale() or 1
    if scale <= 0 then scale = 1 end
    local small = Small(map)
    -- over the continent's painted land and sea (ZoneArt) and the relief on them; under every pin
    -- and over the close-up's terrain tiles and the unexplored pieces (ns.ArtLevel: near the coast, where the
    -- close-up has tiles, lines and boats went faint under them; the user, 2026-11-13)
    local level = ns.ArtLevel and ns.ArtLevel(map, "ink") or canvas:GetFrameLevel() + 1
    local top = ns.ZoneArtTop and ns.ZoneArtTop()
    if top and level < top + 3 then level = top + 3 end
    if host:GetFrameLevel() ~= level then
        host:SetFrameLevel(level)
        holder:SetFrameLevel(level + 1)
    end
    holder:SetScale(1 / scale)

    -- the routes: on a continent's map, at its four widest zoom steps. Not nearer and not on a zone's map:
    -- there the boats' loops in and out of harbour crowd the coast (the user, 2026-11-13: "Dotted lines not
    -- landing its making the coast busy. Maybe we do only on outest 4 zoom steps in continent"). From afar
    -- the loops are a speck and what shows is the sea lanes and their names. (Not on Azeroth's map: with
    -- both continents the lines were too many; the user 2026-11-08.)
    local nl, nseg = 0, 0
    if c.routes ~= false and continent and ZoomStep(map) <= ROUTE_STEPS then
        local key = mapID .. (c.boats and "b" or "") .. (c.zeppelins and "z" or "")
        if legsFor ~= key then
            FindLegs(mapID)
            legsFor = key
        end
        local size = math.floor(FONT * small + 0.5)
        local gap, lift0 = LABEL_GAP * small, LABEL_LIFT * small
        for _, leg in ipairs(legs) do
            -- one line a stretch; the dots run on from one stretch to the next
            local u = 0
            for k = 1, #leg / 2 - 1 do
                nseg = nseg + 1
                local l = lines[nseg]
                if not l then
                    l = host:CreateLine(nil, "ARTWORK")
                    l:SetTexture(DOTS, "REPEAT", "REPEAT")
                    lines[nseg] = l
                end
                l:SetVertexColor(INK[1], INK[2], INK[3], leg.fade and k <= leg.fade and 0.85 * k / (leg.fade + 1) or 0.85)
                local x1, y1, x2, y2 = leg[k * 2 - 1] * W, leg[k * 2] * H, leg[k * 2 + 1] * W, leg[k * 2 + 2] * H
                local n = ((x2 - x1) ^ 2 + (y2 - y1) ^ 2) ^ 0.5 * scale / (THICK * 2)
                l:SetStartPoint("TOPLEFT", host, x1, -y1)
                l:SetEndPoint("TOPLEFT", host, x2, -y2)
                l:SetThickness(THICK / scale)
                l:SetTexCoord(u, u + n, 0, 1)
                u = (u + n) % 1
                l:Show()
            end
            if leg.label then
                nl = nl + 1
                local f = Label(nl)
                if f.size ~= size then
                    local font, _, flags = f:GetFont()
                    f:SetFont(font, size, flags)
                    f.size = size
                end
                f:SetText(leg.label)
                local ex, ey = leg[#leg - 1], leg[#leg]
                local side = ex <= EDGE + 0.001 and "LEFT" or ex >= 1 - EDGE - 0.001 and "RIGHT"
                    or ey <= EDGE + 0.001 and "TOP" or "BOTTOM"
                -- (beside the line's end, not on it: above it on the side edges, off it on the others)
                local lift = (side == "LEFT" or side == "RIGHT") and lift0 or 0
                tags[nl] = { f = f, side = side, x = ex * W * scale, y = -ey * H * scale + lift }
            end
        end
        -- the labels along one edge, spread so none sits on another (in order down the edge, or across it)
        for i = nl + 1, #tags do tags[i] = nil end
        table.sort(tags, function(a, b)
            if a.side ~= b.side then return a.side < b.side end
            if a.side == "LEFT" or a.side == "RIGHT" then return a.y > b.y end
            return a.x < b.x
        end)
        local last
        for _, t in ipairs(tags) do
            local f = t.f
            f:ClearAllPoints()
            if t.side == "LEFT" or t.side == "RIGHT" then
                if last and last.side == t.side and last.y - t.y < gap then t.y = last.y - gap end
                f:SetPoint(t.side, holder, "TOPLEFT", t.x + (t.side == "LEFT" and 4 or -4), t.y)
            else
                if last and last.side == t.side and t.x - last.x < last.w then t.x = last.x + last.w end
                t.w = (f:GetStringWidth() or 0) + 10
                t.x = t.x + lift0
                f:SetPoint(t.side, holder, "TOPLEFT", t.x, t.y + (t.side == "TOP" and -4 or 4))
            end
            f:Show()
            last = t
        end
    end
    for i = nseg + 1, #lines do lines[i]:Hide() end
    for i = nl + 1, #labels do labels[i]:Hide() end

    -- the marks at the piers, towers and stops
    local nm = 0
    local client = Client()
    local unit = (c.scale or 1) * small / scale
    local function Mark(zone, left, right, top0, bottom)
        for _, spot in ipairs(SPOTS[zone]) do
            -- (the anchors and pennants: their own switch, off since 2026-11-13; the tram's mark goes by "The tram")
            if c[SWITCH[spot[1]]] and (not spot[6] or spot[6] == client) and (c.marks or not QUIET[ART[spot[1]]]) then
                local sx, sy = SpotXY(zone, spot)
                -- (its boat's own place known and drawn: the ship on the map is the boat, the pier's stands down)
                if not (spot.path and ns.BoatLive and ns.BoatLive(spot.path)) then
                    nm = nm + 1
                    local t = marks[nm]
                    if not t then
                        t = host:CreateTexture(nil, "ARTWORK", nil, 2)
                        marks[nm] = t
                    end
                    if t.art ~= ART[spot[1]] then
                        t.art = ART[spot[1]]
                        t:SetTexture(MARKS .. t.art)
                    end
                    local size = (QUIET[t.art] and MARK_QUIET or MARK) * unit
                    t:SetSize(size, size)
                    t:ClearAllPoints()
                    t:SetPoint("CENTER", host, "TOPLEFT", (left + (right - left) * sx / 100) * W, -(top0 + (bottom - top0) * sy / 100) * H)
                    t:Show()
                end
            end
        end
    end
    if SPOTS[mapID] then
        Mark(mapID, 0, 1, 0, 1)
    elseif wide then
        -- a continent (or Azeroth): every zone's marks, where that zone sits on it
        for zone in pairs(SPOTS) do
            local ok, left, right, top0, bottom = pcall(C_Map.GetMapRectOnMap, zone, mapID)
            if ok and left and right > left then Mark(zone, left, right, top0, bottom) end
        end
    end
    for i = nm + 1, #marks do marks[i]:Hide() end

    if nm == 0 and nseg == 0 then
        host:Hide()
        return
    end
    host:SetAlpha(c.alpha or 1)
    host:Show()
end

-- (a data provider only to hear the map change: it owns no pins)
BFITransportProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)

function BFITransportProviderMixin:RemoveAllData() end

function BFITransportProviderMixin:RefreshAllData()
    pcall(Draw, self:GetMap())
end

function BFITransportProviderMixin:OnMapChanged()
    pcall(Draw, self:GetMap())
end

function BFITransportProviderMixin:OnCanvasScaleChanged()
    -- (also while nothing shows: zooming out brings the ways back)
    if host then pcall(Draw, self:GetMap()) end
end

function BFITransportProviderMixin:OnCanvasSizeChanged()
    if host and host:IsShown() then pcall(Draw, self:GetMap()) end
end

function ns.SetupTransports(map)
    local provider = CreateFromMixins(BFITransportProviderMixin)
    local ok, err = pcall(map.AddDataProvider, map, provider)
    if not ok then
        ns.Log("Transports layer failed:", err)
        return
    end
    local canvas = map:GetCanvas()
    host = CreateFrame("Frame", nil, canvas)
    host:SetAllPoints(canvas)
    host:Hide()
    holder = CreateFrame("Frame", nil, host)
    holder:SetSize(1, 1)
    holder:SetPoint("TOPLEFT")
    function ns.RedrawTransports()
        legsFor = nil
        pcall(Draw, map)
    end
end
