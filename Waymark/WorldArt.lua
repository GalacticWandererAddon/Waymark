local _, ns = ...

-- Waymark's map art on the game's own world map, past the shaded land (WorldRelief.lua): the painted
-- continents (each zone's own map laid into the continent through its outline, our paper and sea round them,
-- the baked coast, sea and brush work), the continent's depth over them, and the night's colours on a
-- continent. The night on a zone map is WorldRelief.lua's, asked from here (ns.WorldArtNight).
-- The user, 2026-11-19, after the shaded land there was cleared: "What about the rest of our mapart? whole
-- shebang"; seen in game that day ("It works ... Its even pretty snappy and fast"); and for 1.3.2: "include
-- ... the new map art to world map setting (only the art)". Out of the Lab that day: one switch, The map's
-- look, off as it comes (ns.db.worldArt.on; `night` its colours by the hour, where the map follows the hour).
--
-- ONLY THE ART. Our zoom and way out on that map were tried the same day (`nav`) and blocked the game's own
-- actions in fights and with a controller: every one of its writes to the game's window turned ours. That part
-- (Lab\WorldArtNav.lua) was taken out on 2026-11-22, the user: "It goes, it can never work because of taint".
-- Not to be tried another way. This file writes nothing to
-- the game's window: no field set, no script replaced, no size, place, zoom or map of theirs changed.
--
-- ZoneArt.lua paints the continents on Waymark's own map and is built round that one map: its zoom, its fades,
-- its view. Here nothing fades and nothing follows a zoom, so this is the same picture laid once, in its
-- end state (zone maps full, areas full, sea full), from the same data (ns.ZoneArtParts, ns.ZoneShapeFile,
-- ns.ZoneOverlays, ns.LayMapOverlay, the relief's own art and sums).
--
-- One frame of ours a continent on the world map's canvas, just over the explored art's level, everything in
-- it ordered by draw layer so it needs one frame level only (the game's pins start two or three levels up):
--   BACKGROUND -8 the continent's art with its big letters painted out; -7..-3 paper, sea, cool sea, hatching
--              -2 the game's sea (two halves); 5 each zone's wash; 6 the zones' base maps; 7 their area pieces
--   BORDER     with the game's sea: 0 the fills' open sea in its colours (h), 1 the baked coast and land fills
--              (l), 2 the baked brush work (f), 3 the painted sea in its colours (g). Without it (Era): l, w, f, s
--   ARTWORK    0 the night (one sheet, MOD); 1 the depth's light (ADD); 2 its shade
-- A zone is laid a frame, a few milliseconds at most, the first time its continent shows.
-- The depth on a continent is the shaded land's own switch there (relief.world), unexplored land its tick.

local OFF = { on = false }
-- its settings (ns.db.worldArt: on, night). What a dev copy had switched in the Lab's store is carried over once.
local function Cfg()
    local c = ns.db and ns.db.worldArt
    if not c then return OFF end
    local old = WaymarkDB and WaymarkDB.lab and WaymarkDB.lab.worldArt
    if old and not old.moved then
        if old.on ~= nil then c.on = old.on and old.continents ~= false and true or false end
        if old.night ~= nil then c.night = old.night and true or false end
        old.moved = true
    end
    return c
end

local NAMES = { "C0", "C1", "C2", "C3", "C4", "C5", "C6", "C7", "D0", "D1", "D2", "D3", "D4", "D5", "D6", "D7", "LT" }
local RATE = 1                 -- s between looks while the world map is open
local BUILD_MS = 5             -- laying zones stops for the frame past this
local T = Enum and Enum.UIMapType or {}

local conts = {}               -- [continent] = { host, zones, ... }
local showing                  -- the continent shown
local stats = { looks = 0, ms = 0, worst = 0, laid = 0 }
local blockedAt

local function Blocked()
    local list = WaymarkDB and WaymarkDB.blockedLog
    return list and #list or 0
end

local function Soft(t)
    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
    if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
    return t
end

local function IsContinent(id)
    local info = id and C_Map.GetMapInfo(id)
    return info and T.Continent and info.mapType == T.Continent or false
end

-- just over the explored art, under the game's lowest pins (read only; as WorldRelief.lua)
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

local function HideAll()
    for _, C in pairs(conts) do
        if C.host:IsShown() then C.host:Hide() end
    end
    showing = nil
end

-- the zones on a continent and where each lies on it (0 to 1), as ZoneArt.lua's own list
local function ZonesOf(cont, P)
    local list = {}
    local ok, children = pcall(C_Map.GetMapChildrenInfo, cont, T.Zone)
    for _, info in ipairs(ok and children or {}) do
        local ok2, l, r, t, b = pcall(ns.MapRectOnMap, info.mapID, cont)
        if ok2 and l and r > l and b > t and not (P.CITIES and P.CITIES[info.mapID]) then
            list[#list + 1] = { id = info.mapID, l = l, r = r, t = t, b = b, tex = {}, used = 0,
                                shape = ns.ZoneShapeFile and ns.ZoneShapeFile(info.mapID) }
        end
    end
    return list
end

local function Continent(cont, canvas)
    local C = conts[cont]
    if C then return C end
    local P = ns.ZoneArtParts
    C = { id = cont, host = CreateFrame("Frame", nil, canvas), fills = {}, relief = {},
          baked = { l = {}, w = {}, f = {}, s = {}, g = {}, h = {} } }
    C.host:SetAllPoints(canvas)
    C.host:Hide()
    C.zones = ZonesOf(cont, P)
    C.letters = Soft(C.host:CreateTexture(nil, "BACKGROUND", nil, -8))
    C.letters:Hide()
    for i, k in ipairs(P.FILL_KINDS) do
        local f = { kind = k[1], tiles = k[3] }
        f.tex = C.host:CreateTexture(nil, "BACKGROUND", nil, i - 8)
        f.tex:SetTexture(k[2], "REPEAT", "REPEAT", "TRILINEAR")
        f.tex:SetAllPoints(C.host)
        f.mask = C.host:CreateMaskTexture()
        f.mask:SetAllPoints(C.host)
        f.tex:AddMaskTexture(f.mask)
        f.tex:Hide()
        C.fills[i] = f
    end
    -- (the game's sea, over our fills and under every zone map, as on Waymark's own map: west half, east half)
    C.ocean = {}
    for k = 1, 2 do
        local tex = Soft(C.host:CreateTexture(nil, "BACKGROUND", nil, -2))
        tex:SetPoint("TOPLEFT", C.host, k == 1 and "TOPLEFT" or "TOP")
        tex:SetPoint("BOTTOMRIGHT", C.host, k == 1 and "BOTTOM" or "BOTTOMRIGHT")
        tex:Hide()
        C.ocean[k] = tex
    end
    C.night = C.host:CreateTexture(nil, "ARTWORK", nil, 0)
    C.night:SetAllPoints(C.host)
    C.night:SetColorTexture(1, 1, 1, 1)
    C.night:SetBlendMode("MOD")
    C.night:Hide()
    conts[cont] = C
    return C
end

-- Zones -----------------------------------------------------------------------------

-- a texture of the zone's, on the continent's one frame, through the zone's outline
local function ZoneTex(C, z, sub)
    z.used = z.used + 1
    local t = z.tex[z.used]
    if not t then
        t = Soft(C.host:CreateTexture(nil, "BACKGROUND", nil, sub))
        if z.mask then t:AddMaskTexture(z.mask) end
        z.tex[z.used] = t
    end
    t:SetDrawLayer("BACKGROUND", sub)
    t:ClearAllPoints()
    t:Show()
    return t
end

local function LayZone(C, z, cw, ch, unseen)
    -- (a plain frame over the zone's rectangle, holding nothing: what the zone's pieces are placed by)
    if not z.at then
        z.at = CreateFrame("Frame", nil, C.host)
        if z.shape then
            z.mask = C.host:CreateMaskTexture()
            z.mask:SetTexture(z.shape, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            z.mask:SetAllPoints(z.at)
            local list = ns.ZoneWash and ns.ZoneWash[ns.MapEdition()]
            local rgb = list and list[z.id]
            if rgb then
                z.wash = C.host:CreateTexture(nil, "BACKGROUND", nil, 5)
                z.wash:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
                z.wash:SetAllPoints(z.at)
                z.wash:AddMaskTexture(z.mask)
                local cut = ns.CutFile and ns.CutFile(z.id)
                if cut then
                    z.washLand = C.host:CreateMaskTexture()
                    z.washLand:SetTexture(cut, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                    z.washLand:SetAllPoints(z.at)
                    z.wash:AddMaskTexture(z.washLand)
                end
            end
        end
    end
    z.at:ClearAllPoints()
    z.at:SetPoint("TOPLEFT", C.host, "TOPLEFT", z.l * cw, -z.t * ch)
    z.at:SetSize((z.r - z.l) * cw, (z.b - z.t) * ch)
    z.used = 0
    local aw, ah = ns.MapArtSize(z.id)
    local sx, sy = (z.r - z.l) * cw / aw, (z.b - z.t) * ch / ah

    -- the base map, whole (only through an outline: its rectangle would cover the zones next door)
    if z.mask then
        local l, files = ns.MapArtLayer(z.id)
        if l and files and files[1] then
            local tw, th = l.tileWidth or 256, l.tileHeight or 256
            local across = math.ceil(l.layerWidth / tw)
            for i, fid in ipairs(files) do
                local col, row = (i - 1) % across, math.floor((i - 1) / across)
                local pw, ph = math.min(tw, l.layerWidth - col * tw), math.min(th, l.layerHeight - row * th)
                if pw > 0 and ph > 0 then
                    local t = ZoneTex(C, z, 6)
                    local file = ns.MapArtFile and ns.MapArtFile(fid) or fid
                    if t.artFile ~= file then
                        t:SetTexture(file, nil, nil, "LINEAR")
                        t.artFile = file
                    end
                    t:SetTexCoord(0, pw / tw, 0, ph / th)
                    t:SetPoint("TOPLEFT", z.at, "TOPLEFT", col * tw * sx, -row * th * sy)
                    t:SetSize(pw * sx, ph * sy)
                end
            end
        end
    end
    -- the area pieces: what you have found, and the rest too when unexplored land is shown
    local keys = ns.ExploredOverlayKeys(z.id)
    local function Get() return ZoneTex(C, z, 7) end
    for _, o in ipairs(ns.ZoneOverlays(z.id) or {}) do
        if unseen or keys[o.key] then ns.LayMapOverlay(o, z.at, sx, sy, Get) end
    end
    for i = z.used + 1, #z.tex do z.tex[i]:Hide() end
    stats.laid = stats.laid + 1
end

local function ExploredCount(id)
    local n = 0
    for _ in pairs(ns.ExploredOverlayKeys(id)) do n = n + 1 end
    return n
end

-- lays the zones that want it, until the frame's budget is spent; true while some still wait
local function LayZones(C, cw, ch, unseen, t0)
    -- (what you have explored: asked once a zone as it is laid, and after that of one zone a look, in turn.
    -- Asking every zone at once was a spike of up to 18 ms on Waymark's own map: ZoneArt.lua's note)
    C.turn = (C.turn or 0) % #C.zones + 1
    local again = C.zones[C.turn]
    if again and again.n then again.n = ExploredCount(again.id) end
    for _, z in ipairs(C.zones) do
        if not z.n then
            if debugprofilestop() - t0 > BUILD_MS then return true end
            z.n = ExploredCount(z.id)
        end
        local want = cw .. ":" .. z.n .. ":" .. tostring(unseen)
        if z.laidFor ~= want then
            if debugprofilestop() - t0 > BUILD_MS then return true end
            z.laidFor = want
            LayZone(C, z, cw, ch, unseen)
        end
    end
    return false
end

-- Fills, letters, the baked work ---------------------------------------------------------

local function LayRest(C, cw, ch)
    local P = ns.ZoneArtParts
    local key = cw .. ":" .. ch
    if C.restFor == key then return end
    C.restFor = key
    local edition = ns.MapEdition()
    local masks, tint = P.Fills(C.id)
    for _, f in ipairs(C.fills) do
        local file = masks and masks[f.kind]
        if file then
            f.mask:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            local k = f.kind == "sea" and 1 or f.kind == "cool" and 4 or f.kind == "land" and 7
            if k then f.tex:SetVertexColor(tint[k], tint[k + 1], tint[k + 2]) end
            f.tex:SetTexCoord(0, f.tiles, 0, f.tiles * ch / cw)
            -- (a masked texture is drawn late after a new size: its mask taken off and put on, as ZoneArt.lua)
            f.tex:RemoveMaskTexture(f.mask)
            f.tex:AddMaskTexture(f.mask)
            f.tex:Show()
        else
            f.tex:Hide()
        end
    end
    local box = P.LETTERS[edition] and P.LETTERS[edition][C.id]
    if box then
        C.letters:SetTexture(P.SHAPES .. edition .. "\\letters" .. C.id, "CLAMP", "CLAMP", "LINEAR")
        C.letters:ClearAllPoints()
        C.letters:SetPoint("TOPLEFT", C.host, "TOPLEFT", box[1] * cw, -box[2] * ch)
        C.letters:SetSize((box[3] - box[1]) * cw, (box[4] - box[2]) * ch)
        C.letters:Show()
    else
        C.letters:Hide()
    end
    -- (the game's sea, where the continent has its pictures: ZoneArt.lua's GameSea. Their mips carry the bold
    -- rows for a small map and the fine ones close: tools/sea_cover.py)
    local sea = P.GameSea and P.GameSea(C.id)
    for k, tex in ipairs(C.ocean) do
        if sea then
            tex:SetTexture(P.SHAPES .. edition .. "\\ocean" .. C.id .. "_" .. (k - 1), "CLAMP", "CLAMP", "TRILINEAR")
            tex:Show()
        else
            tex:Hide()
        end
    end
    local data = P.BakedOf and P.BakedOf(C.id)
    -- (in ZoneArt.lua's order, end state. With the game's sea: the fills' open sea in its colours under the land
    -- fills (their rows run on over it to their ragged ends), the brush work, the painted sea in its colours.
    -- Without: the land fills, their open sea over them, the brush work, the painted sea over that. The sea was
    -- baked into layers of its own on 2026-11-19 (tools/clone_art.py `s`, `w`, `g`, `h`).)
    local order = sea and { "h", "l", "f", "g" } or { "l", "w", "f", "s" }
    local used = {}
    for sub, layer in ipairs(order) do
        used[layer] = true
        local list, d = C.baked[layer], data and data[layer]
        local n = 0
        for _, c in ipairs(d or {}) do
            n = n + 1
            local t = list[n]
            if not t then
                t = Soft(C.host:CreateTexture(nil, "BORDER", nil, sub - 1))
                list[n] = t
            end
            t:SetDrawLayer("BORDER", sub - 1)
            local file = P.CLONE_ART .. edition .. "\\" .. C.id .. "_" .. layer .. "_" .. c[1] .. "_" .. c[2]
            if t.artFile ~= file then
                t:SetTexture(file, "CLAMP", "CLAMP", "TRILINEAR")
                t.artFile = file
            end
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", C.host, "TOPLEFT", c[1] / d.cols * cw, -c[2] / d.rows * ch)
            t:SetSize(cw / d.cols, ch / d.rows)
            t:Show()
        end
        for i = n + 1, #list do list[i]:Hide() end
    end
    for layer, list in pairs(C.baked) do
        if not used[layer] then for i = 1, #list do list[i]:Hide() end end
    end
end

-- The depth and the night ------------------------------------------------------------

local function LayRelief(C, cw, ch)
    local r = ns.db and ns.db.relief
    local data = ns.ReliefContinents and ns.ReliefContinents[C.id]
    local on = r and r.world and data and ns.ReliefPlan and ns.ReliefLight and ns.ReliefContinentPlace
        and not (ns.Perf and ns.Perf("relief"))
    if not on then
        for _, t in pairs(C.relief) do t:Hide() end
        C.reliefKey = nil
        return
    end
    local steady = r.hour == false or (ns.Perf and ns.Perf("reliefHour")) or false
    local hour = steady and 0 or math.floor((ns.MapHourNow and ns.MapHourNow() or 12) * 12)
    local key = table.concat({ cw, r.shadeAlpha or 100, tostring(steady), hour, tostring(r.cast) }, ":")
    if key == C.reliefKey then return end
    C.reliefKey = key
    if C.reliefW ~= cw then
        C.reliefW = cw
        local l, rr, t, b = ns.ReliefContinentPlace(C.id, data)
        if not l then return end
        for _, name in ipairs(NAMES) do
            local tex = C.relief[name]
            if not tex then
                tex = Soft(C.host:CreateTexture(nil, "ARTWORK", nil, 2))
                tex:SetTexture(ns.MEDIA .. "Relief\\" .. "c" .. C.id .. name)   -- (c<continent><layer>: Relief.lua's own sheets)
                C.relief[name] = tex
            end
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", C.host, "TOPLEFT", l * cw, -t * ch)
            tex:SetPoint("BOTTOMRIGHT", C.host, "TOPLEFT", rr * cw, -b * ch)
        end
    end
    local D = ns.ReliefDefaults or {}
    local strength = (D.CONTINENT or 1) * (r.shadeAlpha or 100) / 100
    local e, n, k, _, lit = ns.ReliefLight(nil, steady, true)
    local plan = ns.ReliefPlan(e, n, k * strength, lit, r.cast)
    local shade = D.CONT_SHADE or 0.19
    for _, name in ipairs(NAMES) do
        local tex, role, a = C.relief[name], plan[name][1], plan[name][2]
        local shown = tex and a > 0.004
        if shown then
            -- (the pictures carry the map's own colour: the light is that colour, the shade a part of it)
            local v = role == "lit" and 1 or shade
            tex:SetBlendMode(role == "lit" and "ADD" or "BLEND")
            tex:SetDrawLayer("ARTWORK", role == "lit" and 1 or 2)
            tex:SetVertexColor(v, v, v, math.min(1, a))
        end
        if tex then tex:SetShown(shown) end
    end
end

-- the hour's tint, when this file's night is on and the map follows the hour (r, g, b; 1, 1, 1 by day)
local function NightTint()
    local c = Cfg()
    local hourOn = ns.db and ns.db.mapHour and ns.db.mapHour.on
    if not (c.on and c.night ~= false and hourOn and ns.MapHourTint) or (ns.Perf and ns.Perf("effects")) then return 1, 1, 1 end
    local r, g, b = ns.MapHourTint()
    return r, g, b
end
-- (WorldRelief.lua asks this for a zone map on the world map: its own sheet, under its depth)
function ns.WorldArtNight() return NightTint() end


-- Looks -----------------------------------------------------------------------------

local pending = false

local function Update()
    local map = WorldMapFrame
    local c = Cfg()
    local P = ns.ZoneArtParts
    if not (map and c.on and P and map:IsShown() and map.GetMapID and map.GetCanvas)
        or (ns.Perf and ns.Perf("art")) then
        pending = false
        return HideAll()
    end
    local id = map:GetMapID()
    if not (IsContinent(id) and P.Fills(id)) then
        pending = false
        return HideAll()
    end
    local canvas = map:GetCanvas()
    local cw, ch = canvas and canvas:GetWidth() or 0, canvas and canvas:GetHeight() or 0
    if cw <= 0 then return HideAll() end
    local t0 = debugprofilestop()
    local C = Continent(id, canvas)
    if showing and showing ~= id and conts[showing] then conts[showing].host:Hide() end
    showing = id
    local level = Level(map, canvas)
    if C.host:GetFrameLevel() ~= level then C.host:SetFrameLevel(level) end
    LayRest(C, cw, ch)
    local unseen = not (ns.db and ns.db.relief and ns.db.relief.worldUnseen == false)
    pending = LayZones(C, cw, ch, unseen, t0)
    LayRelief(C, cw, ch)
    local r, g, b = NightTint()
    if r > 0.995 and g > 0.995 and b > 0.995 then
        C.night:Hide()
    else
        C.night:SetVertexColor(r, g, b, 1)
        C.night:Show()
    end
    C.host:Show()
end

local function Look()
    local t0 = debugprofilestop()
    if ns.Safe then ns.Safe("World map art", Update) else Update() end
    local ms = debugprofilestop() - t0
    stats.looks, stats.ms = stats.looks + 1, stats.ms + ms
    if ms > stats.worst then stats.worst = ms end
end

function ns.WorldArtRefresh()
    for _, C in pairs(conts) do
        C.restFor, C.reliefKey = nil, nil
        for _, z in ipairs(C.zones) do z.laidFor, z.n = nil, nil end
    end
    Look()
    if ns.WorldReliefRefresh then ns.WorldReliefRefresh() end   -- (the night on a zone map is its)
end

function ns.WorldArtSet(on)
    local c = Cfg()
    if c == OFF then return end
    c.on = on and true or false
    if c.on then
        blockedAt = Blocked()
        stats.looks, stats.ms, stats.worst = 0, 0, 0
    end
    ns.WorldArtRefresh()
end

local ticker = CreateFrame("Frame")
local since, hooked = 0, false
ticker:SetScript("OnUpdate", function(_, e)
    since = since + e
    if not (pending or since >= RATE) then return end
    if not (WaymarkDB and WorldMapFrame and ns.db) then since = 0 return end
    if since >= RATE then since = 0 end
    if not Cfg().on then
        if showing then HideAll() end
        pending = false
        return
    end
    -- (hooked only once it is on: a player who never ticks it has nothing of ours on the game's map)
    if not hooked then
        hooked = true
        WorldMapFrame:HookScript("OnShow", function() since = RATE end)
        if WorldMapFrame.OnMapChanged then
            hooksecurefunc(WorldMapFrame, "OnMapChanged", function() since = RATE end)
        end
    end
    blockedAt = blockedAt or Blocked()
    if WorldMapFrame:IsShown() then Look() else pending = false end
end)

-- a setting of ours changed (the settings window, a setup loaded)
if ns.OnSettingChanged then
    hooksecurefunc(ns, "OnSettingChanged", function(group)
        if group == "worldArt" and ns.db then
            if ns.db.worldArt and ns.db.worldArt.on then blockedAt = blockedAt or Blocked() end
            ns.WorldArtRefresh()
        end
    end)
end

function ns.WorldArtInfo()
    local c = Cfg()
    if not c.on then return "our map art on the game's world map is off." end
    local lines = {}
    local new = Blocked() - (blockedAt or Blocked())
    lines[1] = new > 0
        and ("|cffff7060%d blocked action(s) blamed on Waymark since this went on.|r /bfi check has them."):format(new)
        or "no blocked action blamed on Waymark since this went on."
    local n, zones = 0, 0
    local C = showing and conts[showing]
    if C then
        for _, z in ipairs(C.zones) do
            if z.laidFor then zones = zones + 1 n = n + z.used end
        end
        lines[2] = ("continent %d: %d of %d zones laid, %d pieces; "):format(showing, zones, #C.zones, n)
    else
        lines[2] = "no continent shown; "
    end
    if stats.looks > 0 then
        lines[2] = lines[2] .. ("%.2f ms a look, the worst %.1f ms."):format(stats.ms / stats.looks, stats.worst)
    end
    return table.concat(lines, "\n")
end

-- /worldart: on and off; /worldart night; /worldart info
SLASH_WAYMARKWORLDART1 = "/worldart"
SlashCmdList.WAYMARKWORLDART = function(msg)
    local function Say(s) print("|cffc79a52Waymark|r: " .. s) end
    local word = (msg or ""):lower():match("^%s*(%S*)")
    local c = Cfg()
    if c == OFF then return end
    if word == "info" then
        Say(ns.WorldArtInfo())
    elseif word == "night" then
        c.night = c.night == false
        Say("the night's colours on the world map are " .. (c.night and "on." or "off."))
        ns.WorldArtRefresh()
    else
        ns.WorldArtSet(not c.on)
        Say("our map art on the game's world map is " .. (c.on and "on: open the world map on a continent." or "off."))
    end
end
