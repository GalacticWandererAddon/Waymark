local _, ns = ...

-- "Am I in a town?" for town view and the Towns & cities profile. A town is
-- where townsfolk gather, so their positions show without zooming yourself,
-- and the open world stays uncluttered. In order:
--   1. a sub-zone you marked "town" or "not a town": that wins
--   2. a sub-zone learned as a town (so all of Kharanos counts, not just
--      round its inn)
--   3. two kinds of service NPC close by (inn, flight, repair, mail, stable,
--      bank, auction; QuestieDB's data) -> also learns the sub-zone
--   4. only without that data (no QuestieDB): resting, or near a flight point
-- Resting alone doesn't count where there's data: the rested area round a
-- capital reaches its gates (Gates of Ironforge, no townsfolk there).

local FLIGHT_ENTER, FLIGHT_LEAVE = 200, 300   -- yards
-- two kinds of service NPC this close (150 / 250 counted the open snow south
-- of Kharanos as a town)
local NPC_ENTER, NPC_LEAVE, NPC_MIN = 60, 100, 2

local state = { inTown = false, why = "-", inCity = false }

-- capital cities (their own maps): city view, not town view. Classic's six,
-- and TBC's three for the TBC client.
local CITY_MAPS = {
    [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true,
    [1947] = true, [1954] = true, [1955] = true,
}

-- on a capital's map, or a map inside one (its parents up to the zone)
local function InCapital()
    if IsInInstance() then return false end
    local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local seen = 0
    while mapID and seen < 4 do
        if CITY_MAPS[mapID] then return true end
        local info = C_Map.GetMapInfo(mapID)
        if not info or (Enum and Enum.UIMapType and info.mapType <= Enum.UIMapType.Zone) then return false end
        mapID, seen = info.parentMapID, seen + 1
    end
    return false
end
ns.CITY_MAPS = CITY_MAPS

local function Towns() return ns.db.towns end

local function SubZone()
    local s = GetSubZoneText and GetSubZoneText() or ""
    if s == "" then s = GetMinimapZoneText and GetMinimapZoneText() or "" end
    return s
end

local function PlayerOnMap()
    local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not (pos and pos.x) or (pos.x == 0 and pos.y == 0) then return mapID end
    return mapID, pos.x, pos.y
end

-- yards from the player to the nearest flight point on this map (nil: none)
local function NearestFlightPoint(mapID, px, py)
    if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap and px) then return end
    local w, h = ns.MapYards(mapID)
    if not w then return end
    local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
    if not (ok and nodes) then return end
    local best
    for _, node in ipairs(nodes) do
        local p = node.position
        local nx, ny
        if p and p.GetXY then nx, ny = p:GetXY() elseif p then nx, ny = p.x, p.y end
        if nx then
            local d = math.sqrt(((nx - px) * w) ^ 2 + ((ny - py) * h) ^ 2)
            if not best or d < best then best = d end
        end
    end
    return best
end

-- the zone's own name: where there's no sub-zone, SubZone() falls back to it
local function IsZoneName(sub)
    return sub == (GetZoneText and GetZoneText() or "") or sub == (GetRealZoneText and GetRealZoneText() or "")
end

-- Only service NPCs together teach a sub-zone; never the zone's own name (that
-- made all of Westfall a town), not resting (Gates of Ironforge) and not a
-- flight point (its 200 yards reach into Gold Road by the Crossroads).
local function Learn(sub)
    if sub ~= "" and not IsZoneName(sub) and Towns().marked[sub] == nil and not IsInInstance() then
        Towns().learned[sub] = true
    end
end

local function Detect()
    local sub = SubZone()
    local marked = Towns().marked[sub]
    if marked ~= nil then return marked, marked and "marked by you" or "marked: not a town" end

    if IsInInstance() then return false, "in an instance" end
    if sub ~= "" and Towns().learned[sub] then
        if not IsZoneName(sub) then return true, "known town: " .. sub end
        Towns().learned[sub] = nil  -- (a zone learned by mistake before)
    end

    local mapID, px, py = PlayerOnMap()
    if not px then return false, "no position" end

    local n, found, ready = 0, "", false
    if ns.TownServicesNear then
        n, found, ready = ns.TownServicesNear(mapID, px, py, state.inTown and NPC_LEAVE or NPC_ENTER)
    end
    if n >= NPC_MIN then
        Learn(sub)
        return true, "service NPCs: " .. found
    end
    if ready then
        return false, n == 1 and ("only one kind of service NPC near: " .. found) or "no service NPCs near"
    end

    -- no townsfolk data (no Questie, or not indexed yet): the game's own signs
    if IsResting() then return true, "resting (no townsfolk data)" end
    local d = NearestFlightPoint(mapID, px, py)
    if d and d <= (state.inTown and FLIGHT_LEAVE or FLIGHT_ENTER) then
        return true, string.format("flight point %d yd (no townsfolk data)", d)
    end
    return false, "nothing town-like near"
end

function ns.IsInTown() return state.inTown end

-- force: refresh what depends on it even if nothing changed (town view
-- switched on or off)
function ns.UpdateTown(force)
    if not ns.db then return end
    local ok, inTown, why = pcall(Detect)
    if not ok then inTown, why = false, "error: " .. tostring(inTown) end
    local okCity, inCity = pcall(InCapital)
    inCity = okCity and inCity or false
    local changed = force or inTown ~= state.inTown
    local viewChanged = changed or inCity ~= state.inCity
    state.inTown, state.why, state.inCity = inTown and true or false, why, inCity
    if changed and ns.UpdateProfile then ns.UpdateProfile() end
    -- town or city view's own pin sizes (ns.PinScale) and townsfolk list
    if viewChanged and ns.ApplyScales then pcall(ns.ApplyScales, "objectives") end
    if viewChanged and (ns.db.townView.ownTypes or ns.db.cityView.ownTypes) and ns.RedrawTownsfolk then
        pcall(ns.RedrawTownsfolk)
    end
    if viewChanged and ns.RefreshViewGlow then ns.RefreshViewGlow() end
end

-- Town view (its own settings page): while you're in a town the map can zoom in
-- (townView.zoom, MapControls' AutoZoom) and pins have their own size
-- (townView.pinScale, ns.PinSize). In a capital it's city view instead
-- (cityView, its own page): the same settings, by default the whole city.
-- (A capital still counts as a town for the Towns & cities profile: IsInTown.)
-- (townView.enabled off: no town view at all, though "in town" is still worked
-- out for the Town view page)
function ns.InCityView() return state.inCity end
function ns.InTownView() return ns.db.townView.enabled and state.inTown and not state.inCity or false end

-- settings: mark where you stand
function ns.CurrentSubZone() return SubZone() end
function ns.MarkTown(value)  -- true = town, false = not a town, nil = automatic
    local sub = SubZone()
    if sub == "" then return end
    Towns().marked[sub] = value
    if value == nil then Towns().learned[sub] = nil end
    ns.UpdateTown()
end
function ns.ForgetLearnedTowns()
    wipe(Towns().learned)
    ns.UpdateTown()
end
function ns.TownStatus() return state.inTown, state.why end

-- /bfi town: every step, to see why it decides what it does
function ns.TownProbe()
    local L = ns.Log
    local sub = SubZone()
    local mapID, px, py = PlayerOnMap()
    local w, h = ns.MapYards(mapID)
    L("sub-zone:", sub ~= "" and sub or "-", "| resting:", tostring(IsResting()), "| marked:", tostring(Towns().marked[sub]),
      "| learned:", tostring(Towns().learned[sub] or false))
    L("map:", tostring(mapID), px and string.format("at %.3f, %.3f", px, py) or "no position",
      "| size:", w and string.format("%d x %d yd", w, h) or "unknown")
    local d = NearestFlightPoint(mapID, px, py)
    L("nearest flight point:", d and string.format("%d yd", d) or "none / no data")
    if ns.TownServicesNear and px then
        local n1, f1 = ns.TownServicesNear(mapID, px, py, NPC_ENTER)
        local n2, f2 = ns.TownServicesNear(mapID, px, py, 250)
        L(string.format("kinds of service NPC within %d yd: %d (%s)", NPC_ENTER, n1, f1))
        L(string.format("within 250 yd: %d (%s)", n2, f2))
    end
    ns.UpdateTown()
    L("=> in town:", tostring(state.inTown), "(" .. state.why .. ")", "| capital (city view):", tostring(state.inCity))
end

function ns.SetupTown()
    -- town zoom used to be auto-zoom's "in towns": keep what you had, once
    local tv = ns.db.townView
    if not tv.migrated then
        tv.zoom = (ns.db.zoom.autoZoom and ns.db.zoom.inTowns) and true or false
        tv.migrated = true
    end
    -- towns learned before resting was the only teacher had whole zones and
    -- the sub-zones next to flight points in them: start over once (inns and
    -- capitals are learned again the moment you rest there; marks are kept)
    local towns = Towns()
    -- (and again once resting stopped teaching: it had taught capitals' gates)
    if (towns.learnedVersion or 1) < 3 then
        wipe(towns.learned)
        towns.learnedVersion = 3
    end
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
                         "ZONE_CHANGED_NEW_AREA", "PLAYER_UPDATE_RESTING" }) do
        f:RegisterEvent(e)
    end
    f:SetScript("OnEvent", function() ns.UpdateTown() end)
    -- walking up to a flight point or vendors fires no event: check every 2 s
    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 2 then return end
        elapsed = 0
        ns.UpdateTown()
    end)
    ns.UpdateTown()
end
