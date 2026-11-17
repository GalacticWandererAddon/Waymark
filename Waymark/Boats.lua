local _, ns = ...

-- Boats where they are (Lab, 2026-11-13; the user on the stills: "Yes": sails set, side-on, true size with a
-- floor). Out of the Lab for 1.3 (2026-11-14). The reckoning is BoatClock.lua; this file takes the sightings
-- and draws.
--
-- A ship (Media\Boats\Ship.tga) or zeppelin (Zeppelin.tga) on the Battlefield Map at the place its boat is right
-- now, on zone and continent maps. Side-on as a chart draws ships, facing the way it sails. At its true size
-- against the land where that is large enough to read, never smaller than FLOOR pixels.
--
-- NEVER a boat whose place we don't know. The game gives an addon no word of where a transport is, so a boat
-- shows only after a sighting ("fix"):
--   riding it. Twice a second, while on: are you being carried (moving while your own feet stand still, or
--   faster than a mount runs) along one boat's route, the way it sails? Three such looks in a row, agreeing on
--   the round's second, are a fix. Good to a second or two.
-- A fix is kept per realm (boats are the server's), for all your characters, and believed for a day
-- (BoatClock.MAX_AGE). Each new fix notes how far the old one's forecast was out: /boats lists it. That list is
-- how we learn what is still a guess: whether a fix lasts over a server restart, whether a round is the length
-- we reckon, whether Forever's new boats sail at the old boats' speed.
-- Not tried: fixes from standing on the pier (nothing tells us the boat came in), from other players (no
-- sharing, by the user's rule).
-- Skyships take the zeppelin's drawing until they have their own.
-- Cost: on, with the map open: thirteen rounds looked up ten times a second, one texture a boat in sight.
-- Map shut: the riding look only, twice a second, and only while you move.
-- It is part of the boats layer (ns.db.transports, Transports.lua), ink on the map and no pin: that layer's
-- Show, Boats, Zeppelins, "on the continent map too" and Opacity rule it too, and while a boat is drawn here
-- its pier marks stand down (ns.BoatLive). Its own switch (transports.live) only says whether boats are followed at all.
-- The wake (the user on the stills, 2026-11-13: "Yes, build it"): each ship drawn leaves dots on the way it
-- really came, WAKE seconds of it, smaller and fainter the older; none while it lies at a pier. It stands in
-- for the dotted routes near the coast, which crowded it (Transports.lua draws those from afar only).
-- Up to about twenty small textures a ship, placed again with the ship.
-- /boats: on or off. /boats list: what is known. /boats forget: drop every fix on this realm.
-- /boats wake: the wake on or off.

-- Out of the Lab for 1.3 on 2026-11-14 (cleared by the user: "In, cleared for ship, done"). Its two switches are
-- the boats layer's own (ns.db.transports.live and .wake, DEFAULTS in BattlefieldInfo.lua), so presets and saved
-- setups carry them; the sightings are kept apart from the settings (WaymarkDB.boatFixes, by realm). A dev copy's
-- Lab values and sightings are carried over once.
local DEFAULT = { live = true, wake = true }
local function Cfg()
    local c = ns.db and ns.db.transports
    if not c then return DEFAULT end
    local old = WaymarkDB and WaymarkDB.lab and WaymarkDB.lab.boats
    if old and not old.moved then
        if old.on ~= nil then c.live = old.on and true or false end
        if old.wake ~= nil then c.wake = old.wake and true or false end
        if old.fixes and not WaymarkDB.boatFixes then WaymarkDB.boatFixes = old.fixes end
        old.fixes, old.moved = nil, true
    end
    if c.live == nil then c.live = true end
    if c.wake == nil then c.wake = true end
    return c
end
ns.BoatsCfg = Cfg        -- (the test bench, which stays in the Lab)
local Clock = ns.BoatClock

local ART = { boat = "Ship.tga", zeppelin = "Zeppelin.tga", skyship = "Zeppelin.tga" }
local ACROSS = { boat = 114.6, zeppelin = 99.8, skyship = 99.8 }   -- yards a picture spans (tools\ship_art.py)
local FLOOR = 40          -- px on screen, the smallest a boat is drawn on a map 560 wide or more
local FLOOR_SMALL = 26    -- the same on the smallest maps
local FULL_AT = 560
local WAKE = 40           -- seconds of a ship's way that show behind it
local WAKE_GAP = 7        -- px on screen between two of its dots
local WAKE_DOT = 5        -- px, the newest dot; the oldest is half that
local WAKE_INK = { 0.24, 0.13, 0.07 }
local LOOKS = 3           -- looks in a row that must agree before a ride is a fix
local MOUNT = 16          -- yards a second: nothing on foot or hoof is this fast

local function Say(s) print("|cffc8a86eWaymark|r: " .. s) end
local function Num(v)
    if ns.Known then v = ns.Known(v) end
    return type(v) == "number" and v or nil
end

-- The server's clock, finer than its whole seconds: the largest (server seconds - our clock) seen is the one
-- taken just as a second turned.
local lead
local function Now()
    local d = GetServerTime() - GetTime()
    if not lead or d > lead or lead - d > 2 then lead = d end
    return GetTime() + lead
end

local function Store()
    Cfg()   -- (a dev copy's sightings carried over first)
    WaymarkDB.boatFixes = WaymarkDB.boatFixes or {}
    local all = WaymarkDB.boatFixes
    local realm = GetRealmName and GetRealmName() or "?"
    all[realm] = all[realm] or {}
    return all[realm]
end

local function Client() return ns.FOREVER and "forever" or "era" end
local SWITCH = { boat = "boats", zeppelin = "zeppelins", skyship = "zeppelins" }

-- Is this boat's place known and being drawn? (Transports.lua: then its pier marks stand down)
function ns.BoatLive(id)
    if not (WaymarkDB and Cfg().live) then return false end
    return Clock.Phase(Store(), id, Now()) ~= nil
end

local function Name(path)
    local seen, out = {}, {}
    for _, s in ipairs(path.stops) do
        if not seen[s[1]] then seen[s[1]] = true out[#out + 1] = s[1] end
    end
    return table.concat(out, " - ")
end

-- The mark's size on a map, px on screen: FLOOR on a wide map, down to FLOOR_SMALL on the smallest
function ns.LabMarkFloor(map, full, small)
    local sc = map and map.ScrollContainer
    local w = sc and sc:GetWidth()
    if not (type(w) == "number" and w > 0) then return full end
    return math.max(small, math.min(full, full * w / FULL_AT))
end

-- Sightings: riding -----------------------------------------------------------------------------------------

local last          -- the look before: { x, y, inst, at }
local run           -- looks in a row on one boat: { id, t, at, n }

local function Look()
    local x, y, inst = nil, nil, nil
    if ns.WorldPos then x, y, inst = ns.WorldPos() end
    local at = GetTime()
    if not x then last, run = nil, nil return end
    local was = last
    last = { x = x, y = y, inst = inst, at = at }
    if not (was and was.inst == inst) then run = nil return end
    local dt = at - was.at
    if dt < 0.2 or dt > 2 then run = nil return end
    local vx, vy = (x - was.x) / dt, (y - was.y) / dt
    local speed = (vx * vx + vy * vy) ^ 0.5
    if speed < 4 then run = nil return end
    if UnitOnTaxi and UnitOnTaxi("player") then run = nil return end
    local own = Num(GetUnitSpeed and GetUnitSpeed("player")) or 0
    -- carried: moving while standing, or faster than anything runs
    if not (own < 0.5 or speed > MOUNT) then run = nil return end
    local id, t = Clock.Riding(inst, x, y, vx, vy, Client())
    if not id then run = nil return end
    local period = Clock.Paths()[id].period
    if run and run.id == id then
        local step = (t - run.t) % period
        if math.abs(step - (at - run.at)) < 1.5 then
            run.n, run.t, run.at = run.n + 1, t, at
        else
            run = { id = id, t = t, at = at, n = 1 }
        end
    else
        run = { id = id, t = t, at = at, n = 1 }
    end
    if run.n >= LOOKS and (not run.fixed or at - run.fixed > 20) then
        run.fixed = at
        local store = Store()
        local first = not Clock.Phase(store, id, Now())
        local off = Clock.Fix(store, id, Now(), t)
        if first then
            Say("The " .. Name(Clock.Paths()[id]) .. " " .. Clock.Paths()[id].kind .. " is now on your map.")
        elseif off and math.abs(off) > Clock.OFF then
            Say(("The %s %s was %.0f seconds off on the map. Fixed."):format(
                Name(Clock.Paths()[id]), Clock.Paths()[id].kind, off))
        end
        if ns.BoatsRefresh then ns.BoatsRefresh() end
        if ns.RedrawTransports then ns.RedrawTransports() end
    end
end

-- Drawing ---------------------------------------------------------------------------------------------------

local host
local marks = {}      -- [path id] = texture
local wakes = {}      -- [path id] = { textures }

-- the dots behind a ship: on its own real way, from its place now back WAKE seconds, one every WAKE_GAP px
local function Wake(id, phase, inst, ui, W, H, scale, shown)
    local dots = wakes[id]
    local n = 0
    if shown and phase then
        if not dots then dots = {} wakes[id] = dots end
        local lx, ly
        for age = 0, WAKE do
            local i2, x, y = Clock.At(id, phase - age)
            if i2 ~= inst then break end            -- (the other side of a jump: she was not here then)
            local mx, my = ns.WorldToMap(ui, x, y, inst)
            if not mx then break end
            local px, py = mx * W, -my * H
            if not lx then
                lx, ly = px, py
            elseif ((px - lx) ^ 2 + (py - ly) ^ 2) ^ 0.5 * scale >= WAKE_GAP then
                lx, ly = px, py
                if mx > 0 and mx < 1 and my > 0 and my < 1 then
                    n = n + 1
                    local d = dots[n]
                    if not d then
                        d = host:CreateTexture(nil, "ARTWORK", nil, -1)
                        d:SetTexture(ns.MEDIA .. "InkDot")
                        d:SetVertexColor(WAKE_INK[1], WAKE_INK[2], WAKE_INK[3])
                        d.wake = true
                        dots[n] = d
                    end
                    local k = 1 - age / WAKE
                    local size = WAKE_DOT * (0.5 + 0.5 * k) / scale
                    d:SetSize(size, size)
                    d:ClearAllPoints()
                    d:SetPoint("CENTER", host, "TOPLEFT", px, py)
                    d:SetAlpha(0.9 * k ^ 1.3)
                    d:Show()
                end
            end
        end
    end
    if dots then
        for i = n + 1, #dots do dots[i]:Hide() end
    end
end
local facing = {}     -- [path id] = 1 (east) or -1

local function Mark(id, kind)
    local t = marks[id]
    if not t then
        t = host:CreateTexture(nil, "ARTWORK")
        t:SetTexture(ns.MEDIA .. "Boats\\" .. ART[kind])
        t.shownAt = nil
        marks[id] = t
    end
    return t
end

local function Draw()
    local map = BattlefieldMapFrame
    local c = Cfg()
    local layer = ns.db and ns.db.transports
    if not (c.live and layer and map and map:IsShown() and map.GetCanvas and ns.IsShown and ns.IsShown("transports")) then
        if host then host:Hide() end
        return
    end
    local ui = map:GetMapID()
    local info = ui and C_Map.GetMapInfo(ui)
    local T = Enum.UIMapType or {}
    if not info or info.mapType == T.World or (info.mapType == T.Continent and not layer.continent) then
        if host then host:Hide() end
        return
    end
    local canvas = map:GetCanvas()
    if not host then
        host = CreateFrame("Frame", nil, canvas)
        host:SetAllPoints(canvas)
        host.bfiNoHour = true     -- (the drawings carry their own colours)
    end
    -- over the continent's painted land and sea fill, and the relief on them (the user, 2026-11-13: the ship lay
    -- under the sea fill on Kalimdor's map)
    -- and over the close-up's terrain tiles (ns.ArtLevel "marks": the top of the map's art, under every pin)
    local level = ns.ArtLevel and ns.ArtLevel(map, "marks") or canvas:GetFrameLevel() + 6
    local top = ns.ZoneArtTop and ns.ZoneArtTop()
    if top and level < top + 5 then level = top + 5 end
    if host:GetFrameLevel() ~= level then host:SetFrameLevel(level) end
    local W, H = canvas:GetWidth(), canvas:GetHeight()
    local scale = map.GetCanvasScale and map:GetCanvasScale() or 1
    if type(scale) ~= "number" or scale <= 0 then scale = 1 end
    local floor = ns.LabMarkFloor(map, FLOOR, FLOOR_SMALL) / scale
    local store, now, client = Store(), Now(), Client()
    local any = false
    for id, path in pairs(Clock.Paths()) do
        local shown, where = false, nil
        if (not path.only or path.only == client) and layer[SWITCH[path.kind]] then
            local inst, x, y, dx, dy = Clock.Where(store, id, now)
            if inst then
                where = inst
                local mx, my = ns.WorldToMap(ui, x, y, inst)
                if mx and mx > -0.02 and mx < 1.02 and my > -0.02 and my < 1.02 then
                    -- yards to map units, from a second point a hundred yards north
                    local _, ny = ns.WorldToMap(ui, x + 100, y, inst)
                    local perYard = ny and math.abs(ny - my) * H / 100 or 0
                    -- (times the player's own size for them: transports.shipScale, 1 = true size with the floor)
                    local size = math.max(ACROSS[path.kind] * perYard, floor) * (layer.shipScale or 1)
                    local t = Mark(id, path.kind)
                    t:SetSize(size, size)
                    t:ClearAllPoints()
                    t:SetPoint("CENTER", host, "TOPLEFT", mx * W, -my * H)
                    -- (the world's second axis grows westward: east is its other way)
                    local east = dx and -dy or 0
                    if east > 0.15 then facing[id] = 1 elseif east < -0.15 then facing[id] = -1 end
                    if (facing[id] or 1) > 0 then t:SetTexCoord(0, 1, 0, 1) else t:SetTexCoord(1, 0, 0, 1) end
                    if not t.shownAt then t.shownAt = GetTime() end
                    t:SetAlpha(math.min(1, (GetTime() - t.shownAt) / 0.6))
                    t:Show()
                    shown, any = true, true
                end
            end
        end
        if not shown and marks[id] then
            marks[id]:Hide()
            marks[id].shownAt = nil
        end
        if shown or wakes[id] then
            Wake(id, shown and c.wake and Clock.Phase(store, id, now), where, ui, W, H, scale, shown and c.wake)
        end
    end
    host:SetAlpha(layer.alpha or 1)
    host:SetShown(any)
end

function ns.BoatsRefresh() pcall(Draw) end

local ticker = CreateFrame("Frame")
local sinceLook, sinceDraw = 0, 0
ticker:SetScript("OnUpdate", function(_, e)
    if not (WaymarkDB and Clock) then return end
    sinceLook, sinceDraw = sinceLook + e, sinceDraw + e
    if sinceLook < 0.5 and sinceDraw < 0.1 then return end
    local ok, c = pcall(Cfg)
    if not (ok and c.live) then
        if host and host:IsShown() then host:Hide() end
        sinceLook, sinceDraw = 0, 0
        return
    end
    if sinceLook >= 0.5 then
        sinceLook = 0
        local good, err = pcall(Look)
        if not good and ns.Log then ns.Log("Boats look:", err) end
    end
    if sinceDraw >= 0.1 then
        sinceDraw = 0
        local map = BattlefieldMapFrame
        if map and map:IsShown() then
            local good, err = pcall(Draw)
            if not good and ns.Log then ns.Log("Boats draw:", err) end
        end
    end
end)

-- /boats ----------------------------------------------------------------------------------------------------

local function Ago(s)
    if s < 90 then return ("%.0f s"):format(s) end
    if s < 5400 then return ("%.0f min"):format(s / 60) end
    return ("%.1f h"):format(s / 3600)
end

SLASH_WAYMARKBOATS1 = "/boats"
SlashCmdList.WAYMARKBOATS = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local c = Cfg()
    if msg == "list" then
        local store, now, client, n = Store(), Now(), Client(), 0
        for id, path in pairs(Clock.Paths()) do
            if not path.only or path.only == client then
                local fix = store[id]
                local line = Name(path) .. " (" .. path.kind .. "): "
                if not fix then
                    line = line .. "not seen yet."
                else
                    n = n + 1
                    local t, age = Clock.Phase(store, id, now)
                    line = line .. "seen " .. Ago(now - fix.at) .. " ago, " .. fix.n .. " time" .. (fix.n == 1 and "" or "s")
                    if not t then line = line .. ", too old to trust: not drawn" end
                    if fix.off then
                        line = line .. (". The sighting before, %s old, was %.1f s out"):format(Ago(fix.age or 0), fix.off)
                    end
                    if t then
                        local _, _, _, _, _, stop = Clock.At(id, t)
                        line = line .. (type(stop) == "string" and (". Now at " .. stop) or ". Now under way")
                    end
                    line = line .. "."
                end
                Say(line)
            end
        end
        if n == 0 then Say("Ride a boat or zeppelin once and it's on the map.") end
    elseif msg == "wake" then
        c.wake = not c.wake
        Say(c.wake and "A ship leaves a dotted wake." or "No wake.")
        pcall(Draw)
    elseif msg == "forget" then
        local store = Store()
        for k in pairs(store) do store[k] = nil end
        Say("Every sighting on this realm forgotten.")
        pcall(Draw)
        if ns.RedrawTransports then ns.RedrawTransports() end
    elseif msg == "" or msg == "on" or msg == "off" then
        if msg == "" then c.live = not c.live else c.live = msg == "on" end
        Say(c.live and "Boats you've ridden: shown. /boats list: known boats."
            or "Boats you've ridden: hidden.")
        pcall(Draw)
        if ns.RedrawTransports then ns.RedrawTransports() end
    else
        Say("/boats: on or off. /boats list: known boats. /boats wake: the wake on or off. /boats forget: drop every sighting on this realm.")
    end
end
