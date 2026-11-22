local _, ns = ...

-- The shaded land on the game's own world map (the user, 2026-11-18: "Yes, start it", after "Its apparent we
-- need to get this worldmap solution" and a third player asking for Waymark's land on the map he already uses).
-- Began as a one-day Lab trial to learn two things: does laying our pictures on the game's map taint it (the
-- quest log lives in that window on Forever), and what does it cost with that map open. The user's look in game,
-- 2026-11-19: no blocked action, 0.075 ms a look, Questie, the game's objectives, the quest log, a fight and a
-- controller all fine, beside Leatrix Maps too: "ship it, one switch, off for now". Out of the Lab that day.
-- Its switch is the relief's own setting `world` (The map's look; off as it comes), `worldUnseen` the
-- unexplored land (on). Its strength is the relief's. Rests where the relief rests in performance mode.
--
-- How little it touches: one frame of ours, a child of the world map's canvas, with the zone's seventeen
-- relief layers as textures (Relief.lua's own art, light and sums: ns.ReliefLight, ns.ReliefPlan,
-- ns.ReliefCoords). Nothing is written to the world map or its pins: no field set, no script replaced, no
-- size, place or level of theirs changed. We read its map ID and the explored art's frame level, and hook
-- OnShow and OnMapChanged after the game's own code (HookScript, hooksecurefunc).
-- Zone maps only. Not here: the continents (ours lie on Waymark's painted continents, the game's have their
-- coasts elsewhere), the night's colours (the game's map is never dark), the close-up, the fog pieces.
--
-- Unexplored land (the user's first look, 2026-11-19: "Looks good, but i dont have a way to see unexplored
-- areas"): the game's map leaves it bare, so the depth lay on bare paper there. With `unseen` on (the default)
-- the area art you have not found is laid too, in full colour, at the explored art's own level (the two never
-- overlap) and under the depth: Explore.lua's own list and layer (ns.ZoneOverlays, ns.LayMapOverlay).
-- Laid again only when the map, its size or what you have explored changes.

local NAMES = { "C0", "C1", "C2", "C3", "C4", "C5", "C6", "C7", "D0", "D1", "D2", "D3", "D4", "D5", "D6", "D7", "LT" }
local ART = "Relief\\"
local RATE = 1                       -- s between looks while the world map is open
local ZONE_CAST = 1.25               -- (as Relief.lua's)
local UMBER, STRAW = { 90 / 255, 58 / 255, 30 / 255 }, { 1, 240 / 255, 200 / 255 }
local OFF = {}

-- the relief's own settings (ns.db.relief: world, worldUnseen, shadeAlpha). What a dev copy had switched in the
-- Lab's store is carried over once.
local function Cfg()
    local r = ns.db and ns.db.relief
    if not r then return OFF end
    local old = WaymarkDB and WaymarkDB.lab and WaymarkDB.lab.worldRelief
    if old and not old.moved then
        if old.on ~= nil then r.world = old.on and true or false end
        if old.unseen ~= nil then r.worldUnseen = old.unseen and true or false end
        old.moved = true
    end
    return r
end

local host                           -- our frame on the world map's canvas
local tex = {}                       -- [name] = texture
local shownKey, laidKey
local shown = 0
local unseenHost, unseenTex, unseenKey, unseenShown = nil, {}, nil, 0
local night                          -- the hour's colours: one sheet under the depth (only where the Lab asks)
local stats = { looks = 0, ms = 0, worst = 0, work = 0 }   -- how long our looks took (debugprofilestop)
local blockedAt                      -- how many blocked actions the addon had logged when this went on

local function Blocked()
    local list = WaymarkDB and WaymarkDB.blockedLog
    return list and #list or 0
end

local function Hide()
    if host and host:IsShown() then host:Hide() end
    if unseenHost and unseenHost:IsShown() then unseenHost:Hide() end
    shownKey, shown = nil, 0
end

-- the area art you have not found, at the explored art's level (level: the depth's, one above it)
local function Unseen(map, canvas, mapID, level, on)
    local list = on and ns.ZoneOverlays and ns.ZoneOverlays(mapID)
    if not (list and ns.ExploredOverlayKeys and ns.LayMapOverlay and ns.MapArtSize) then
        if unseenHost then unseenHost:Hide() end
        unseenShown = 0
        return
    end
    if not unseenHost then
        unseenHost = CreateFrame("Frame", nil, canvas)
        unseenHost:SetAllPoints(canvas)
    end
    local at = math.max(1, level - 1)
    if unseenHost:GetFrameLevel() ~= at then unseenHost:SetFrameLevel(at) end
    local keys = ns.ExploredOverlayKeys(mapID)
    local n = 0
    for _ in pairs(keys) do n = n + 1 end
    local want = mapID .. ":" .. n .. ":" .. canvas:GetWidth()
    if want ~= unseenKey then
        unseenKey = want
        local aw, ah = ns.MapArtSize(mapID)
        local sx, sy = canvas:GetWidth() / aw, canvas:GetHeight() / ah
        local used = 0
        local function Get()
            used = used + 1
            local t = unseenTex[used]
            if not t then
                t = unseenHost:CreateTexture(nil, "ARTWORK")
                unseenTex[used] = t
            end
            return t
        end
        for _, o in ipairs(list) do
            if not keys[o.key] then ns.LayMapOverlay(o, unseenHost, sx, sy, Get) end
        end
        for i = used + 1, #unseenTex do unseenTex[i]:Hide() end
        unseenShown = used
    end
    unseenHost:Show()
end

-- just over the explored art, under the game's lowest pins (read only)
local function Level(map, canvas)
    local level
    if map.EnumeratePinsByTemplate then
        pcall(function()
            for pin in map:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
                local l = pin:GetFrameLevel()
                if not level or l > level then level = l end
            end
        end)
    end
    return (level or canvas:GetFrameLevel()) + 1
end

local function Update()
    local map = WorldMapFrame
    local c = Cfg()
    if not (map and c.world and map:IsShown() and map.GetMapID and map.GetCanvas) then return Hide() end
    if ns.Perf and ns.Perf("relief") then return Hide() end
    if not (ns.ReliefZones and ns.ReliefLight and ns.ReliefPlan and ns.ReliefCoords) then return Hide() end
    local mapID = map:GetMapID()
    local box = mapID and ns.ReliefZones[mapID]
    if not box or (ns.ReliefPaintedOff and ns.ReliefPaintedOff[mapID]) then return Hide() end
    local canvas = map:GetCanvas()
    if not canvas then return Hide() end

    Unseen(map, canvas, mapID, Level(map, canvas), c.worldUnseen ~= false)

    local relief = c
    local steady = relief.hour == false or (ns.Perf and ns.Perf("reliefHour")) or false
    local hour = steady and 0 or math.floor((ns.MapHourNow and ns.MapHourNow() or 12) * 12)   -- (five minutes)
    local nightKey = ns.WorldArtNight and math.floor(((ns.MapHourNow and ns.MapHourNow()) or 12) * 12) .. tostring(select(1, ns.WorldArtNight())) or ""
    local key = table.concat({ mapID, canvas:GetWidth(), c.shadeAlpha or 100, tostring(steady), hour, tostring(relief.cast), nightKey }, ":")
    if key == shownKey then return end
    shownKey = key
    stats.work = stats.work + 1

    if not host then
        host = CreateFrame("Frame", nil, canvas)
        host:SetAllPoints(canvas)
        for _, name in ipairs(NAMES) do
            local t = host:CreateTexture(nil, "ARTWORK")
            if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
            if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
            t:SetAllPoints(host)
            tex[name] = t
        end
    end
    local level = Level(map, canvas)
    if host:GetFrameLevel() ~= level then host:SetFrameLevel(level) end

    -- the night's colours (WorldArt.lua's, with its switch on and the map following the hour): one sheet that multiplies what lies
    -- under it, the game's art and the unexplored land, by the hour's tint; under the depth's own layers
    local nr, ng, nb = 1, 1, 1
    if ns.WorldArtNight then nr, ng, nb = ns.WorldArtNight() end
    if nr > 0.995 and ng > 0.995 and nb > 0.995 then
        if night then night:Hide() end
    else
        if not night then
            night = host:CreateTexture(nil, "BACKGROUND")
            night:SetAllPoints(host)
            night:SetColorTexture(1, 1, 1, 1)
            night:SetBlendMode("MOD")
        end
        night:SetVertexColor(nr, ng, nb, 1)
        night:Show()
    end

    local lay = mapID .. ":" .. canvas:GetWidth()
    if lay ~= laidKey then
        laidKey = lay
        local l, r, t, b = ns.ReliefCoords(mapID, box)
        for _, name in ipairs(NAMES) do
            tex[name]:SetTexture(ns.MEDIA .. ART .. mapID .. name)
            tex[name]:SetTexCoord(l, r, t, b)
        end
    end

    local D = ns.ReliefDefaults or {}
    local strength = (D.PAINTED or 1.25) * (c.shadeAlpha or 100) / 100
    local e, n, k, _, lit = ns.ReliefLight(nil, steady, true)      -- (true: the game's map is bright at every hour)
    local plan = ns.ReliefPlan(e, n, k * strength, lit, relief.cast, ZONE_CAST, D.ZONE_SLOPE or 0.85)
    local own = ns.ReliefTones and ns.ReliefTones[mapID]
    local deep = D.ZONE_SHADE or 0.70
    shown = 0
    for _, name in ipairs(NAMES) do
        local t, role, a = tex[name], plan[name][1], plan[name][2]
        local on = a > 0.004
        if on then
            local col = role == "lit" and (own and own[2] or STRAW) or (own and own[1] or UMBER)
            local day = role == "lit" and 1 or deep
            t:SetBlendMode(role == "lit" and "ADD" or "BLEND")
            t:SetDrawLayer(role == "lit" and "BORDER" or "ARTWORK")      -- (the light first, the shade over it)
            t:SetVertexColor(col[1] * day, col[2] * day, col[3] * day, math.min(1, a))
            shown = shown + 1
        end
        t:SetShown(on)
    end
    host:Show()
end

local function Look()
    local t0 = debugprofilestop and debugprofilestop()
    if ns.Safe then ns.Safe("World map relief", Update) else Update() end
    if t0 then
        local ms = debugprofilestop() - t0
        stats.looks, stats.ms = stats.looks + 1, stats.ms + ms
        if ms > stats.worst then stats.worst = ms end
    end
end

function ns.WorldReliefRefresh()
    shownKey = nil
    Look()
end

-- one look a second while the world map is open and this is on; at once when it opens or changes map
local ticker = CreateFrame("Frame")
local since, hooked = 0, false
ticker:SetScript("OnUpdate", function(_, e)
    since = since + e
    if since < RATE then return end
    since = 0
    if not (WaymarkDB and WorldMapFrame) then return end
    if not hooked then
        hooked = true
        WorldMapFrame:HookScript("OnShow", function() since = RATE end)
        if WorldMapFrame.OnMapChanged then
            hooksecurefunc(WorldMapFrame, "OnMapChanged", function() shownKey = nil since = RATE end)
        end
    end
    if not Cfg().world then
        if (host and host:IsShown()) or (unseenHost and unseenHost:IsShown()) then Hide() end
        return
    end
    blockedAt = blockedAt or Blocked()      -- (on since before this load)
    if WorldMapFrame:IsShown() then Look() end
end)

function ns.WorldReliefInfo()
    local c = Cfg()
    if not c.world then return "the shaded land on the game's world map is off." end
    local lines = {}
    if not WorldMapFrame then
        lines[1] = "this client has no world map frame."
    elseif shown > 0 then
        lines[1] = ("shown: %d of 17 layers, one texture each; %d pieces of unexplored land."):format(shown, unseenShown)
    elseif WorldMapFrame:IsShown() then
        lines[1] = "nothing shown: this map is not a zone we have depth for."
    else
        lines[1] = "the world map is closed."
    end
    if stats.looks > 0 then
        lines[#lines + 1] = ("%d looks, %d of them did work; %.3f ms a look, the worst %.2f ms."):format(
            stats.looks, stats.work, stats.ms / stats.looks, stats.worst)
    end
    local new = Blocked() - (blockedAt or Blocked())
    -- (first: the test bench shows only two lines of an answer, and this is the one that decides)
    table.insert(lines, 1, new > 0
        and ("|cffff7060%d blocked action(s) blamed on Waymark since this went on.|r /bfi check has them."):format(new)
        or "no blocked action blamed on Waymark since this went on.")
    return table.concat(lines, "\n")
end

function ns.WorldReliefSet(on)
    local c = Cfg()
    c.world = on and true or false
    if c.world then
        blockedAt = Blocked()
        stats.looks, stats.ms, stats.worst, stats.work = 0, 0, 0, 0
    end
    ns.WorldReliefRefresh()
end

-- /worldrelief: on and off; /worldrelief info; /worldrelief unseen: unexplored land
SLASH_WAYMARKWORLDRELIEF1 = "/worldrelief"
SlashCmdList.WAYMARKWORLDRELIEF = function(msg)
    local function Say(s) print("|cffc79a52Waymark|r: " .. s) end
    local word = (msg or ""):lower():match("^%s*(%S*)")
    if word == "info" then
        Say(ns.WorldReliefInfo())
    elseif word == "unseen" then
        local c = Cfg()
        c.worldUnseen = c.worldUnseen == false
        ns.WorldReliefRefresh()
        Say("unexplored land on the world map is " .. (c.worldUnseen and "shown." or "left as the game has it."))
    else
        ns.WorldReliefSet(not Cfg().world)
        Say("the shaded land on the game's world map is " .. (Cfg().world and "on: open the world map in a zone." or "off."))
    end
end
