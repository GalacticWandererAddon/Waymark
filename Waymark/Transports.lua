local _, ns = ...

-- Boats, zeppelins and the tram on the Battlefield Map (ns.db.transports): shown, alpha, scale,
-- boats, zeppelins, trams, continent (on the continents' maps too), boat ("cog" or "woodcut"). A fixed ink mark at each pier, tower and
-- tram stop, "to Theramore" on hover, on the zone's map and on the continent's. Nothing moves: the map only shows where a route leaves from. Places are by hand, map
-- percentages (the game's table names the routes but gives no spots). Art: tools\ink_marks.py.

local TEMPLATE = "BFITransportPinTemplate"
local MARKS = ns.MEDIA .. "Marks\\"
local BOAT_ART = { cog = "Cog", woodcut = "BoatWoodcut" }
local KIND = { boat = "Boat", zeppelin = "Zeppelin", skyship = "Skyship", tram = "Deeprun Tram" }
local SWITCH = { boat = "boats", zeppelin = "zeppelins", skyship = "zeppelins", tram = "trams" }  -- (skyships fly: with the zeppelins)

-- [uiMap] = { { "boat", "zeppelin" or "tram", x, y, where it goes, where it's from, only on
-- "era" or "forever" (Forever's Menethil boat stops at Southshore on its way round) }, ... }
-- Stormwind Harbor and Powderfuse Port: Forever's AreaPOI and TaxiNodes, turned into map percentages.
-- Forever's skyships (Valanaar on Zephras Isle to Dalaran and to Skywatcher Plateau): the user's
-- coordinates at each dock, 2026-11-08.
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

local FULL_AT = 560   -- map units across the map's view: from here down, boats and their words shrink
local FONT = 14

-- a small map (docked over the minimap, ~350 across) gets smaller boats and words: at full size they
-- covered the continent (the user, 2026-11-08). 1 at FULL_AT and wider, never under 0.55
local function Small(map)
    local sc = map and map.ScrollContainer
    local w = sc and sc:GetWidth()
    if not (w and w > 0) then return 1 end
    return math.max(0.55, math.min(1, w / FULL_AT))
end

BFITransportPinMixin = CreateFromMixins(MapCanvasPinMixin)
BFITransportPinMixin.CheckMouseButtonPassthrough = ns.SafePassthrough  -- see Pin.lua

function BFITransportPinMixin:OnLoad()
    if self.UseFrameLevelType then
        pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_BFI_TOWNSFOLK")
    end
end

function BFITransportPinMixin:ApplyCurrentScale()
    local map = self:GetMap()
    local canvasScale = map and map.GetCanvasScale and map:GetCanvasScale() or 1
    if not canvasScale or canvasScale <= 0 then canvasScale = 1 end
    self:SetScale(ns.PinScale("transports", Cfg().scale) * Small(map) / canvasScale)
    ns.ReanchorPin(self, map)
end

function BFITransportPinMixin:ApplyCurrentAlpha()
    self:SetAlpha(ns.PinAlpha("transports"))
end

function BFITransportPinMixin:OnAcquired(spot, x, y)
    self.spot = spot
    local art = spot[1] == "boat" and (BOAT_ART[Cfg().boat] or BOAT_ART.cog) or spot[1] == "tram" and "Tram" or "Airship"
    self.Icon:SetTexture(MARKS .. art)
    self:ApplyCurrentScale()
    self:ApplyCurrentAlpha()
    self:SetPosition(x, y)
end

function BFITransportPinMixin:OnEnter()
    local s = self.spot
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("to " .. s[4], 1, 0.82, 0)
    GameTooltip:AddLine(KIND[s[1]] .. " from " .. s[5], 1, 1, 1)
    GameTooltip:Show()
end

function BFITransportPinMixin:OnLeave()
    GameTooltip:Hide()
end
-- the map wires a pin's mouse-over to these (see Pin.xml)
BFITransportPinMixin.OnMouseEnter = BFITransportPinMixin.OnEnter
BFITransportPinMixin.OnMouseLeave = BFITransportPinMixin.OnLeave

BFITransportProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)
local DrawRoutes  -- (below)

function BFITransportProviderMixin:RemoveAllData()
    local map = self:GetMap()
    pcall(map.RemoveAllPinsByTemplate, map, TEMPLATE)
end

function BFITransportProviderMixin:RefreshAllData()
    self:RemoveAllData()
    local map = self:GetMap()
    local mapID = map:GetMapID()
    pcall(DrawRoutes, map)
    if not (mapID and ns.IsShown("transports")) then return end
    local c = Cfg()
    local client = ns.FOREVER and "forever" or "era"
    local function Mark(zone, left, right, top, bottom)
        for _, spot in ipairs(SPOTS[zone]) do
            if c[SWITCH[spot[1]]] and (not spot[6] or spot[6] == client) then
                ns.Safe("Transports pin", map.AcquirePin, map, TEMPLATE, spot,
                    left + (right - left) * spot[2] / 100, top + (bottom - top) * spot[3] / 100)
            end
        end
    end
    if SPOTS[mapID] then return Mark(mapID, 0, 1, 0, 1) end
    -- a continent (or Azeroth): every zone's marks, where that zone sits on it
    local info = c.continent and C_Map.GetMapInfo(mapID)
    if not (info and Enum.UIMapType and (info.mapType == Enum.UIMapType.Continent or info.mapType == Enum.UIMapType.World)) then return end
    for zone in pairs(SPOTS) do
        local ok, left, right, top, bottom = pcall(C_Map.GetMapRectOnMap, zone, mapID)
        if ok and left and right > left then Mark(zone, left, right, top, bottom) end
    end
end

function BFITransportProviderMixin:OnMapChanged()
    self:RefreshAllData()
end

-- ---- Routes: a dotted ink line from each pier to where its boat goes ------------------------------
-- On a continent's map, and on Azeroth's. A route to the other continent runs to the map's edge, with
-- "to Theramore" there. Boats go their way by sea (Data/BoatRoutes.lua, tools/boat_routes.py), round
-- the land; zeppelins fly straight, aimed at the far tower on Azeroth's map. Worked out once per map;
-- a zoom only changes the line's thickness and the labels' size.

local WORLD = 947
local DOTS = MARKS .. "RouteDots"
local INK = { 0.24, 0.13, 0.07 }
local THICK = 3.5   -- px on screen
local EDGE = 0.01
local host, holder
local lines, labels, tags = {}, {}, {}
local LABEL_GAP = 16  -- px between two labels' middles on one edge
local LABEL_LIFT = 9  -- px a label sits off its line's end
local legs = {}     -- for the map shown: { x1, y1, x2, y2, ..., label = at the last point, or nil }
local legsFor

local function Name(s) return (s:gsub("^the ", ""):lower()) end

-- where a spot sits on a map (0-1), or nil if that zone isn't on it
local function Place(zone, spot, mapID)
    local ok, left, right, top, bottom = pcall(C_Map.GetMapRectOnMap, zone, mapID)
    if not (ok and left and right > left) then return end
    return left + (right - left) * spot[2] / 100, top + (bottom - top) * spot[3] / 100
end

-- the pier a route arrives at: one at that place, best the one going back (then true: both ways)
local function Arrival(spot, client)
    local want, first = Name(spot[4])
    for zone, list in pairs(SPOTS) do
        for _, s in ipairs(list) do
            if s[1] == spot[1] and Name(s[5]) == want and (not s[6] or s[6] == client) then
                if Name(s[4]) == Name(spot[5]) then return zone, s, true end
                first = first or { zone, s }
            end
        end
    end
    if first then return first[1], first[2] end
end

-- a boat's way by sea on this map, from the pier on it (on Azeroth's, all of it); then true if it ends at
-- the edge (the route goes on to the other continent)
local function SeaWay(spot, mapID)
    local a, b = Name(spot[5]), Name(spot[4])
    if b < a then a, b = b, a end
    local r = ns.BoatRoutes and ns.BoatRoutes[a .. "|" .. b]
    if not r then return end
    local function Onto(list, cont, out, backwards)
        local ok, l, rr, t, bb = pcall(C_Map.GetMapRectOnMap, cont, mapID)
        if cont == mapID then l, rr, t, bb = 0, 1, 0, 1 elseif not (ok and l and rr > l) then return end
        local n = #list / 2
        for k = 1, n do
            local i = backwards and (n - k + 1) or k
            out[#out + 1] = l + (rr - l) * list[i * 2 - 1]
            out[#out + 1] = t + (bb - t) * list[i * 2]
        end
        return out
    end
    if r[mapID] then
        local other = false
        for cont in pairs(r) do if type(cont) == "number" and cont ~= mapID then other = true end end
        return Onto(r[mapID], mapID, {}), other
    end
    local out, parts = {}, 0
    for cont, list in pairs(r) do
        if type(cont) == "number" then
            parts = parts + 1
            -- the second continent's half is walked back from its edge to its pier
            if not Onto(list, cont, out, parts == 2) then return end
        end
    end
    if parts > 0 then return out, false end
end

-- cut a line from inside the map at the map's edge
local function Clip(x1, y1, x2, y2)
    local t = 1
    local dx, dy = x2 - x1, y2 - y1
    if x2 < EDGE then t = math.min(t, (EDGE - x1) / dx) end
    if x2 > 1 - EDGE then t = math.min(t, (1 - EDGE - x1) / dx) end
    if y2 < EDGE then t = math.min(t, (EDGE - y1) / dy) end
    if y2 > 1 - EDGE then t = math.min(t, (1 - EDGE - y1) / dy) end
    return x1 + dx * t, y1 + dy * t
end

local function FindLegs(mapID)
    wipe(legs)
    local c = Cfg()
    local client = ns.FOREVER and "forever" or "era"
    local okRect, cl, cr, ct, cb = pcall(C_Map.GetMapRectOnMap, mapID, WORLD)
    local onWorld = mapID ~= WORLD and okRect and cl and cr > cl
    local done = {}
    for zone, list in pairs(SPOTS) do
        for _, spot in ipairs(list) do
            local kind = spot[1]
            if kind ~= "tram" and c[SWITCH[kind]] and (not spot[6] or spot[6] == client) then
                local key = kind .. ":" .. table.concat({ Name(spot[4]), Name(spot[5]) }, "|")
                local back = kind .. ":" .. Name(spot[5]) .. "|" .. Name(spot[4])
                local toZone, to, both = Arrival(spot, client)
                if to and not done[key] and not done[back] then
                    done[key] = true
                    local x1, y1 = Place(zone, spot, mapID)
                    local x2, y2 = Place(toZone, to, mapID)
                    local sea, edge
                    if kind == "boat" then sea, edge = SeaWay(spot, mapID) end
                    if sea then
                        if edge then
                            sea.label = x1 and ("to " .. spot[4]) or ((both and "to " or "from ") .. spot[5])
                        end
                        legs[#legs + 1] = sea
                    elseif x1 and x2 then
                        legs[#legs + 1] = { x1, y1, x2, y2 }
                    elseif (x1 or x2) and onWorld then
                        -- one end is on the other continent: aim the line at it, stop at the edge
                        local far, farZone, label = to, toZone, "to " .. spot[4]
                        if not x1 then x1, y1, far, farZone, label = x2, y2, spot, zone, (both and "to " or "from ") .. spot[5] end
                        local wx, wy = Place(farZone, far, WORLD)
                        if wx then
                            local ex, ey = Clip(x1, y1, (wx - cl) / (cr - cl), (wy - ct) / (cb - ct))
                            legs[#legs + 1] = { x1, y1, ex, ey, label = label }
                        end
                    end
                end
            end
        end
    end
end

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

function DrawRoutes(map)
    if not host then return end
    local mapID = map:GetMapID()
    local info = mapID and C_Map.GetMapInfo(mapID)
    local c = Cfg()
    -- (a continent's map only: on Azeroth's, with both continents, the lines were too many; the user 2026-11-08)
    local wanted = info and Enum.UIMapType and info.mapType == Enum.UIMapType.Continent
    if not (wanted and ns.IsShown("transports") and c.continent and c.routes ~= false) then
        host:Hide()
        legsFor = nil
        return
    end
    local key = mapID .. (c.boats and "b" or "") .. (c.zeppelins and "z" or "")
    if legsFor ~= key then
        FindLegs(mapID)
        legsFor = key
    end
    local canvas = map:GetCanvas()
    local W, H = canvas:GetWidth(), canvas:GetHeight()
    local scale = map:GetCanvasScale() or 1
    if scale <= 0 then scale = 1 end
    holder:SetScale(1 / scale)
    local small = Small(map)
    local size = math.floor(FONT * small + 0.5)
    local gap, lift0 = LABEL_GAP * small, LABEL_LIFT * small
    local nl, nseg = 0, 0
    for _, leg in ipairs(legs) do
        -- one line a stretch; the dots run on from one stretch to the next
        local u = 0
        for k = 1, #leg / 2 - 1 do
            nseg = nseg + 1
            local l = lines[nseg]
            if not l then
                l = host:CreateLine(nil, "ARTWORK")
                l:SetTexture(DOTS, "REPEAT", "REPEAT")
                l:SetVertexColor(INK[1], INK[2], INK[3], 0.85)
                lines[nseg] = l
            end
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
    for i = nseg + 1, #lines do lines[i]:Hide() end
    for i = nl + 1, #labels do labels[i]:Hide() end
    host:SetAlpha(ns.PinAlpha("transports"))
    host:Show()
end

function BFITransportProviderMixin:OnCanvasScaleChanged()
    if host and host:IsShown() then pcall(DrawRoutes, self:GetMap()) end
end

function BFITransportProviderMixin:OnCanvasSizeChanged()
    if host and host:IsShown() then pcall(DrawRoutes, self:GetMap()) end
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
        pcall(provider.RefreshAllData, provider)
    end
end
