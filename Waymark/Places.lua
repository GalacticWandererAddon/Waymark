local _, ns = ...

-- The places: one list of where things are, read by As told, the Horizon, Landmarks and Relief's bake.
-- (The joint proposal of 2026-11-12, mockups\joint\proposal-v1.md: "the gazetteer comes first and draws
-- nothing".) It draws nothing and has no settings: it is there whether or not any sign is shown.
-- The data is Data\Landmarks.lua (tools\landmarks_bake.py), from the game's terrain files: every named
-- area at a point inside it, and the things a traveller steers by (mines, dens, towers, camps...).
--
-- A place is one row:
--   id       kept across rebakes: "a54" an area (its area id), "m12345" a mark (the files' own placement id)
--   name     the game's own name, or nil (most marks have none)
--   kind     nil for a plain area; else "mine", "den", "crypt", "tower", "camp", "graves", "wreck", "windmill",
--            "lumber", "statue", "bridge", "gate", "dock", "well", "sign", "farm", "field";
--            and three the list alone knows (no sign is drawn for them): "nest" (harpies, wyverns, raptors),
--            "ruin" (old walls and arches), "dig" (an excavation)
--   source   "area" or "mark"
--   map, cont        the zone's uiMapID, the continent's instance (0, 1)
--   x, y, rx, ry     on that map, 0 to 1; rx, ry half its reach (a mark's is small)
--   wx, wy           world yards (north, west)
--   pieces           how many things make it up (a camp's tents)
--   rank             its place in the zone's queue for the small map (marks only; 1 first)
--   checked          false where the zone's marks haven't been looked at by hand
--   painted          true where the zone's painted map already holds a sign at that place (marks; measured at bake)
--   found            true once THIS character has found it (kept up to date on the row)
--
-- Calls:
--   ns.Places                         every row of every zone, one plain list (ipairs)
--   ns.PlacesOn(map)                  the rows of one zone map (areas, then marks by rank); {} if none
--   ns.PlaceNamed(name, homeMap)      the row of that name: on homeMap first, else anywhere; "the " and case ignored
--   ns.PlacesNear(cont, wx, wy, yards, kinds)   rows within yards of a world point; kinds = { mine = true, ... } or nil
--   ns.PlaceFound(row)                "mine" (this character has seen it), "old" (another of yours has), or nil
--   ns.PlaceNameKnown(row)            true once the game has shown this character the name there
--   ns.OnPlaceFound(fn)               fn(row) when this character finds one (never for "old")
--   ns.PlaceToMap(map, wx, wy)        world yards to that map's 0..1, by the client's own box of the map
-- Found: a mark once you've stood within sight of it for three looks a second apart (a tower from far off,
-- a well only close by), never from a flight, as a ghost or inside. An area once the game has named it on
-- your screen while you stood in it. Kept in WaymarkCharDB.places (yours) and WaymarkDB.places (any of yours),
-- [map][id] = 1 seen, 2 seen and named: tables of their own, so no settings reset can empty them.
-- Cost: one look a second while you're outdoors and moving about: the rows of the zone you stand in.

local SIGHT = {              -- how far off you know a thing for what it is, yards
    camp = 80, mine = 45, den = 45, crypt = 45, tower = 120, wreck = 90, graves = 50, windmill = 120,
    lumber = 70, statue = 90, bridge = 100, gate = 90, dock = 50, well = 40, sign = 35, farm = 80, field = 60, nest = 70, ruin = 90, dig = 70,
}
local HOLD = 3               -- looks in a row before it counts: a gallop past doesn't spray ink

-- The rows ----------------------------------------------------------------------------------------------

-- the client's own box of a zone map (world x at the top, y at the left, x at the bottom, y at the right);
-- the baked box where the client can't say (the tools' tests, a map this client lacks)
local boxes = {}
local function Box(map)
    local b = boxes[map]
    if b == nil then
        b = false
        if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
            local ok, _, tl = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(0, 0))
            local ok2, _, br = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(1, 1))
            if ok and ok2 and tl and br then
                local top, left = tl:GetXY()
                local bottom, right = br:GetXY()
                if top ~= bottom and left ~= right then b = { top, left, bottom, right } end
            end
        end
        if not b then
            local z = ns.LandmarkData and ns.LandmarkData[map]
            if z and z.box then b = { z.box[3], z.box[4], z.box[1], z.box[2] } end
        end
        boxes[map] = b or false
    end
    return b or nil
end

function ns.PlaceToMap(map, wx, wy)
    local z = ns.LandmarkData and ns.LandmarkData[map]
    if ns.WorldToMap and z then
        local x, y = ns.WorldToMap(map, wx, wy, z.cont)
        if x then return x, y end
    end
    local b = Box(map)
    if not b then return end
    return (b[2] - wy) / (b[2] - b[4]), (b[1] - wx) / (b[1] - b[3])
end

local function Seen(map, id)
    local t = WaymarkCharDB and WaymarkCharDB.places and WaymarkCharDB.places[map]
    return t and t[id] and true or nil
end

local built = {}
local function Build(map)
    local rows = built[map]
    if rows then return rows end
    rows = {}
    built[map] = rows
    local z = ns.LandmarkData and ns.LandmarkData[map]
    local b = z and Box(map)
    if not b then return rows end
    local wide, tall = math.abs(b[2] - b[4]), math.abs(b[1] - b[3])
    for _, a in ipairs(z.areas or {}) do
        local x, y = ns.PlaceToMap(map, a[3], a[4])
        if x and x > 0 and x < 1 and y > 0 and y < 1 then
            rows[#rows + 1] = { id = a[1], name = a[2], source = "area", map = map, cont = z.cont, x = x, y = y,
                rx = a[5] / wide, ry = a[6] / tall, wx = a[3], wy = a[4], pieces = 1, checked = true, found = Seen(map, a[1]) }
        end
    end
    local rank = 0
    for _, m in ipairs(z.marks or {}) do
        local x, y = ns.PlaceToMap(map, m[3], m[4])
        if x and x > 0.01 and x < 0.99 and y > 0.01 and y < 0.99 then
            rank = rank + 1
            rows[#rows + 1] = { id = m[1], kind = m[2], name = m[6], source = "mark", map = map, cont = z.cont, x = x, y = y,
                rx = 20 / wide, ry = 20 / tall, wx = m[3], wy = m[4], pieces = m[5] or 1, rank = rank,
                checked = z.checked and true or false, painted = m[7] and true or nil, found = Seen(map, m[1]) }
        end
    end
    return rows
end

function ns.PlacesOn(map) return map and Build(map) or {} end

-- every row, one list. The same table always: filled when the files load (from the baked boxes) and again
-- at login, when the client can be asked for its own map boxes and the character's finds are there.
ns.Places = {}
local byName               -- [plain name] = { rows }
local function Fill()
    for k in pairs(built) do built[k] = nil end
    for k in pairs(boxes) do boxes[k] = nil end
    for i = #ns.Places, 1, -1 do ns.Places[i] = nil end
    byName = nil
    local maps = {}
    for map in pairs(ns.LandmarkData or {}) do maps[#maps + 1] = map end
    table.sort(maps)
    for _, map in ipairs(maps) do
        for _, r in ipairs(Build(map)) do ns.Places[#ns.Places + 1] = r end
    end
end
ns.PlacesFill = Fill
Fill()

local function Plain(name)
    name = (name or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    name = name:gsub("^the%s+", "")
    return name
end

function ns.PlaceNamed(name, homeMap)
    if not ns.LandmarkData then return end
    if not byName then
        byName = {}
        for map in pairs(ns.LandmarkData) do
            for _, r in ipairs(Build(map)) do
                if r.name then
                    local k = Plain(r.name)
                    byName[k] = byName[k] or {}
                    table.insert(byName[k], r)
                end
            end
        end
    end
    local list = byName[Plain(name)]
    if not list then return end
    -- (the home map's first; a mine's mark and its area share a name and a place, and the mark tells more)
    local best, bestScore
    for _, r in ipairs(list) do
        local score = (r.map == homeMap and 2 or 0) + (r.source == "mark" and 1 or 0)
        if not bestScore or score > bestScore then best, bestScore = r, score end
    end
    return best
end

function ns.PlacesNear(cont, wx, wy, yards, kinds)
    local out = {}
    if not (ns.LandmarkData and wx and wy) then return out end
    local r2 = (yards or 100) ^ 2
    for map, z in pairs(ns.LandmarkData) do
        -- (a zone's box, grown by the reach: most zones are skipped at once)
        if z.cont == cont and wx > z.box[1] - yards and wx < z.box[3] + yards and wy > z.box[2] - yards and wy < z.box[4] + yards then
            for _, r in ipairs(Build(map)) do
                if (not kinds or (r.kind and kinds[r.kind])) and (r.wx - wx) ^ 2 + (r.wy - wy) ^ 2 <= r2 then
                    out[#out + 1] = r
                end
            end
        end
    end
    return out
end

-- Found ---------------------------------------------------------------------------------------------------

local function Mine(map)
    WaymarkCharDB = WaymarkCharDB or {}
    WaymarkCharDB.places = WaymarkCharDB.places or {}
    local t = WaymarkCharDB.places
    t[map] = t[map] or {}
    return t[map]
end

local function Ours(map)
    WaymarkDB = WaymarkDB or {}
    WaymarkDB.places = WaymarkDB.places or {}
    local t = WaymarkDB.places
    t[map] = t[map] or {}
    return t[map]
end

function ns.PlaceFound(row)
    if not row then return end
    if WaymarkCharDB and WaymarkCharDB.places and WaymarkCharDB.places[row.map] and WaymarkCharDB.places[row.map][row.id] then return "mine" end
    if WaymarkDB and WaymarkDB.places and WaymarkDB.places[row.map] and WaymarkDB.places[row.map][row.id] then return "old" end
end

function ns.PlaceNameKnown(row)
    return row and row.name and WaymarkCharDB and WaymarkCharDB.places and WaymarkCharDB.places[row.map]
        and WaymarkCharDB.places[row.map][row.id] == 2 or false
end

-- this character forgets a zone's places (a dev's and a tester's tool: /landmarks forget)
function ns.PlacesForgetFound(map)
    if WaymarkCharDB and WaymarkCharDB.places then WaymarkCharDB.places[map] = nil end
    for _, r in ipairs(Build(map)) do r.found = nil end
end

local listeners = {}
function ns.OnPlaceFound(fn) listeners[#listeners + 1] = fn end
local function Tell(row)
    for _, fn in ipairs(listeners) do
        if ns.Safe then ns.Safe("place found", fn, row) else fn(row) end
    end
end

local holding = {}

-- one look around from a world point on a zone's map; sub, mini: the place names on the screen now.
-- Returns how many were newly found.
local function Look(map, wx, wy, sub, mini)
    local rows = Build(map)
    if #rows == 0 then return 0 end
    local mine, ours = Mine(map), Ours(map)
    local new = 0
    for _, r in ipairs(rows) do
        local state = mine[r.id]
        if r.source == "area" then
            -- an area is found when the game names it to you; that is also its name known
            if state ~= 2 and r.name and (r.name == sub or r.name == mini) then
                mine[r.id], ours[r.id] = 2, 2
                r.found = true
                new = new + 1
                Tell(r)
            end
        elseif state ~= 2 then
            local reach = SIGHT[r.kind] or 50
            if r.kind == "camp" then reach = reach + math.min(60, r.pieces * 3) end
            local dx, dy = r.wx - wx, r.wy - wy
            if dx * dx + dy * dy <= reach * reach then
                if not state then
                    local n = (holding[r.id] or 0) + 1
                    holding[r.id] = n
                    if n >= HOLD then
                        holding[r.id] = nil
                        state = 1
                        mine[r.id], ours[r.id] = 1, ours[r.id] or 1
                        r.found = true
                        new = new + 1
                        Tell(r)
                    end
                end
                if state == 1 and r.name and (r.name == sub or r.name == mini) then
                    mine[r.id], ours[r.id] = 2, 2
                    Tell(r)
                end
            elseif holding[r.id] then
                holding[r.id] = nil
            end
        end
    end
    return new
end
ns.PlacesLook = Look

local function Here()
    if IsInInstance and IsInInstance() then return end
    if UnitOnTaxi and UnitOnTaxi("player") then return end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
    local x, y, cont
    if ns.WorldPos then x, y, cont = ns.WorldPos() end
    if type(x) ~= "number" then
        local ok, a, b, _, c = pcall(UnitPosition, "player")
        if not (ok and type(a) == "number" and type(b) == "number") then return end
        x, y, cont = a, b, c
    end
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local z = map and ns.LandmarkData and ns.LandmarkData[map]
    if not z then
        -- (a cave's own map, a town's: the zone above it)
        local info = map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
        map = info and info.parentMapID
        z = map and ns.LandmarkData and ns.LandmarkData[map]
    end
    if not z or (cont and z.cont ~= cont) then return end
    return map, x, y
end

local function Known(v) return ns.Known and ns.Known(v) or v end

local ticker = CreateFrame("Frame")
local since = 0
ticker:SetScript("OnUpdate", function(_, e)
    since = since + e
    if since < 1 then return end
    since = 0
    if not (WaymarkDB and ns.LandmarkData) then return end
    local map, x, y = Here()
    if not map then return end
    local sub = Known(GetSubZoneText and GetSubZoneText() or "")
    local mini = Known(GetMinimapZoneText and GetMinimapZoneText() or "")
    if ns.Safe then ns.Safe("Places look", Look, map, x, y, sub, mini) else Look(map, x, y, sub, mini) end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    Fill()
end)
