local _, ns = ...

-- The zones' own maps on a continent map. Zoomed in on a continent, its art is
-- one picture stretched over many screens and goes blocky. Each zone's whole
-- map (its base art and its area pieces, at the zone map's own resolution) is
-- laid over it in place, cut to the zone's shape:
--
--   shape   a soft-edged mask of the zone's outline (Media\ZoneShapes\<edition>\
--           <uiMapID>.tga, listed in Data\ZoneShapes.lua). Made by
--           tools\zone_shapes.py from /bfi shapes: the game asked which zone
--           owns each spot of the continent (C_Map.GetMapInfoAtPosition), on a
--           fine grid. Our own data, per client: Classic Era ("Era") and Forever
--           draw some zones differently. The soft edge blends each zone into
--           the next, so borders aren't drawn in full detail. (The game's own
--           zone highlight can't be the mask: it has no alpha, its shape is
--           in its colours, drawn additively.)
--   fade    every zone alike, by how close the view is (Closeness: how big
--           the zones are drawn, as a share of their own fully-out view, the
--           median over the continent's zones; by the zoom alone, ViewHalf,
--           so the map's shape doesn't change it). The zone's base map (its plain
--           parchment, coasts, mountain lines) comes in from fadeFrom to
--           fadeFull, part way (VEIL): the continent's colours show through.
--   detail  the area pieces (each area's colours and drawings) lie over it,
--           rising evenly from fadeFrom to full by detailFull, near where the
--           wheel opens the zone; the base map goes full with them.
--   wash    (browse.zoneWash) the zone's colour on the continent's art, flat
--           under its map (Data\ZoneWash.lua, tools\zone_wash.py): fully in
--           by fadeFull, so the continent's blocky art is hidden from there
--           and the colour shows through the veiled base map instead.
--
-- Area pieces: explored ones always come from the client; unexplored ones from
-- Explore.lua's list (MapOverlays, or MapOverlaysEra on Classic Era), in the
-- Unexplored areas look and opacity when that layer is on, left out when it's
-- off (so they end as the zone map shows them). A zone with no mask (none made for this client yet)
-- gets its area pieces only, with no base art: its rectangle would cover the
-- zones next door.
--
-- ns.OverviewCap (MapControls' zoom steps): the continent zooms in only a
-- little past where every zone can be opened, so its own art is never seen
-- blown up.

local function Cfg() return ns.db.browse end

local T = Enum and Enum.UIMapType or {}

local CAP = 1.8                    -- the continent's closest zoom: this much past where its zones open
local VEIL = 0.6                   -- the base map's opacity at fadeFull (full with the areas)
local GLOW_GONE = 0.8              -- closeness from which the zone hover glow is gone
local GLOW_FROM = 0.65             -- ... fading out from here
local highlights = {}              -- the game's zone highlight pins (FixHighlight)

-- the hover glow, faded out as the zone maps fill the view (the big map stays
-- on the continent that close, so it would light up most of the map)
local function GlowAlpha(a)
    for pin in pairs(highlights) do
        if pin:GetAlpha() ~= a then pin:SetAlpha(a) end
    end
end

local host                -- on the canvas, with the map's art: holds every zone's frame
local zones = {}          -- [continent] = { zone, ... } (see ZonesOf)
local shownFor            -- the continent the zone frames are shown for

local function IsOverview(id)
    local info = id and C_Map.GetMapInfo(id)
    return info and T.Continent and info.mapType == T.Continent or false
end

-- the zone's outline mask, if one was made for this client (Data\ZoneShapes.lua)
local SHAPES = "Interface\\AddOns\\BattlefieldInfo\\Media\\ZoneShapes\\"
local function ShapeFile(id)
    local edition = ns.FOREVER and "Forever" or "Era"
    local list = ns.ZoneShapes and ns.ZoneShapes[edition]
    return list and list[id] and (SHAPES .. edition .. "\\" .. id) or nil
end
-- The fills, where the zone maps don't reach: plain paper on the land (land no
-- zone map covers, Quel'Thalas, the land between zone maps) and water on the
-- sea, each through its continent mask (land<continent>.tga, sea<continent>.tga:
-- the tool traced the coast from the continent's art). Paper.tga and Sea.tga
-- are our own grey grain, made from noise by the tool, tinted to colours
-- sampled from this continent's zone maps (in Data\ZoneShapes.lua): the paper
-- their plain parchment; the water Sea.tga twice, their warm open sea, then
-- their cool sea in patches (cool<continent>.tga, not tiled: no repeats). The zone maps keep
-- all of their own sea, so the water only shows past their rectangles. Both
-- come in with the zones' base maps, so close up nothing of the continent's
-- blocky art shows.
local PAPER = SHAPES .. "Paper"
local SEA = SHAPES .. "Sea"
local FILL_TILES = 40  -- paper tiles across a continent (their grain about a zone map's)
local SEA_TILES = 10   -- water tiles across a continent
local function Fills(cont)
    local edition = ns.FOREVER and "Forever" or "Era"
    local list = ns.ZoneShapes and ns.ZoneShapes[edition .. "Fill"]
    local tint = list and list[cont]
    if not tint or not tint[9] then return end
    local base = SHAPES .. edition .. "\\"
    return { land = base .. "land" .. cont, sea = base .. "sea" .. cont, cool = base .. "cool" .. cont }, tint
end

-- Capitals: their own maps are close-ups (Ironforge's and Undercity's floor plans
-- underground), far finer than the zones round them. Not drawn: the zone round
-- each paints it small, as its own map does (its mask covers the city too).
local CITIES = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true }

-- the zones on a continent and where each sits on it (0..1), cached
local function ZonesOf(cont)
    local list = zones[cont]
    if list then return list end
    list = {}
    if C_Map.GetMapChildrenInfo and C_Map.GetMapRectOnMap then
        local ok, children = pcall(C_Map.GetMapChildrenInfo, cont, T.Zone)
        for _, info in ipairs(ok and children or {}) do
            local ok2, l, r, t, b = pcall(C_Map.GetMapRectOnMap, info.mapID, cont)
            if ok2 and l and r > l and b > t and not CITIES[info.mapID] then
                local z = { id = info.mapID, cont = cont, l = l, r = r, t = t, b = b }
                z.shape = ShapeFile(info.mapID)
                list[#list + 1] = z
            end
        end
    end
    zones[cont] = list
    return list
end

-- Building ----------------------------------------------------------------------

-- The zone's own textures, reused when it's laid out again: on its frame
-- (the base map) or its pieces frame (the area pieces, faded on their own)
local function Tex(z, pieces, layer, sub)
    local list = pieces and z.pieceTex or z.baseTex
    local n = (pieces and z.usedPieces or z.usedBase) + 1
    if pieces then z.usedPieces = n else z.usedBase = n end
    local t = list[n]
    if not t then
        local owner = pieces and z.pieces or z.frame
        t = owner:CreateTexture(nil, layer, nil, sub)
        local mask = pieces and z.pieceMask or z.mask
        if mask then t:AddMaskTexture(mask) end
        if t.SetSnapToPixelGrid then
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
        end
        list[n] = t
    end
    t:ClearAllPoints()
    t:SetDesaturation(0)
    t:SetVertexColor(1, 1, 1, 1)
    t:Show()
    return t
end

-- the zone's frames over its rectangle of the canvas, each with the outline's mask
local function Place(z)
    local canvas = host:GetParent()
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    if not z.frame then
        z.frame = CreateFrame("Frame", nil, host)
        z.pieces = CreateFrame("Frame", nil, z.frame)
        z.pieces:SetAllPoints(z.frame)
        z.baseTex, z.pieceTex, z.usedBase, z.usedPieces = {}, {}, 0, 0
        if z.shape then
            -- (one mask per frame: made over the zone's own rectangle)
            for _, key in ipairs({ "mask", "pieceMask" }) do
                local owner = key == "mask" and z.frame or z.pieces
                local m = owner:CreateMaskTexture()
                m:SetTexture(z.shape, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                m:SetAllPoints(z.frame)
                z[key] = m
            end
        end
    end
    -- the wash: the zone's colour on the continent's art, flat, under its map
    -- (through its outline, so neighbours blend at their soft borders)
    if z.mask and not z.wash then
        local list = ns.ZoneWash and ns.ZoneWash[ns.FOREVER and "Forever" or "Era"]
        local rgb = list and list[z.id]
        if rgb then
            z.wash = z.frame:CreateTexture(nil, "BACKGROUND")
            z.wash:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
            z.wash:SetAllPoints(z.frame)
            z.wash:AddMaskTexture(z.mask)
        end
    end
    z.frame:ClearAllPoints()
    z.frame:SetPoint("TOPLEFT", host, "TOPLEFT", z.l * cw, -z.t * ch)
    z.frame:SetSize((z.r - z.l) * cw, (z.b - z.t) * ch)
end

-- the zone's base art, whole (its 256-pixel tiles, the last row and column cut to size)
local function LayBase(z, sx, sy)
    local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(z.id)
    local l = layers and layers[1]
    local ok, files = pcall(C_Map.GetMapArtLayerTextures, z.id, 1)
    if not (l and ok and files and files[1]) then return end
    local tw, th = l.tileWidth or 256, l.tileHeight or 256
    local across = math.ceil(l.layerWidth / tw)
    for i, fid in ipairs(files) do
        local col, row = (i - 1) % across, math.floor((i - 1) / across)
        local pw = math.min(tw, l.layerWidth - col * tw)
        local ph = math.min(th, l.layerHeight - row * th)
        if pw > 0 and ph > 0 then
            local t = Tex(z, false, "ARTWORK", -2)
            t:SetTexture(ns.MapArtFile and ns.MapArtFile(fid) or fid, nil, nil, "LINEAR")
            t:SetTexCoord(0, pw / tw, 0, ph / th)
            t:SetPoint("TOPLEFT", z.frame, "TOPLEFT", col * tw * sx, -row * th * sy)
            t:SetSize(pw * sx, ph * sy)
        end
    end
end

local function Build(z)
    local f = z.frame
    local keys = ns.ExploredOverlayKeys(z.id)
    local n = 0
    for _ in pairs(keys) do n = n + 1 end
    local ec = ns.db.explore
    local fog = ns.IsShown("explore")
    local want = n .. "|" .. tostring(fog) .. "|" .. tostring(ec.fogStyle) .. "|" .. tostring(ec.fogAlpha)
        .. "|" .. f:GetWidth()
    if z.builtFor == want then return end
    z.builtFor = want
    z.usedBase, z.usedPieces = 0, 0

    local aw, ah = ns.MapArtSize(z.id)
    local sx, sy = f:GetWidth() / aw, f:GetHeight() / ah
    if z.mask then LayBase(z, sx, sy) end

    local style = ns.FOG_STYLES[ec.fogStyle] or ns.FOG_STYLES.fog
    local fogA = (ec.fogAlpha or 0.7) * (ec.fogStyle == "faded" and 0.6 or 1)
    local function Getter(unexplored)
        return function()
            local t = Tex(z, true, "ARTWORK", 0)
            if unexplored and fog then
                t:SetDesaturation(style.desat)
                t:SetVertexColor(style.tint[1], style.tint[2], style.tint[3], fogA)
            end
            return t
        end
    end
    local list = ns.ZoneOverlays and ns.ZoneOverlays(z.id)
    if list then
        for _, o in ipairs(list) do
            -- (Unexplored areas off: only what you've found, as on the zone map)
            local unexplored = not keys[o.key]
            if fog or not unexplored then
                ns.LayMapOverlay(o, z.pieces, sx, sy, Getter(unexplored))
            end
        end
    else
        -- (a zone our list doesn't know: what the client says you've explored)
        local ok, explored = pcall(C_MapExplorationInfo.GetExploredMapTextures, z.id)
        for _, e in ipairs(ok and explored or {}) do
            ns.LayMapOverlay({ w = e.textureWidth, h = e.textureHeight, x = e.offsetX, y = e.offsetY,
                               files = e.fileDataIDs or {} }, z.pieces, sx, sy, Getter(false))
        end
    end

    for i = z.usedBase + 1, #z.baseTex do z.baseTex[i]:Hide() end
    for i = z.usedPieces + 1, #z.pieceTex do z.pieceTex[i]:Hide() end
end

-- Fading ------------------------------------------------------------------------

-- What the view shows, by the zoom alone: half its width and height in the
-- continent's 0..1, as if fully zoomed out showed the whole continent. Not the
-- map's real view: that is narrower on a narrow map, so its shape changed how
-- close the zones counted as (a narrow map brought them in sooner). Without
-- zoom levels yet, the real view.
local function ViewHalf(sc)
    local s = sc:GetCanvasScale()
    local lo = sc.zoomLevels and sc.zoomLevels[1] and sc.zoomLevels[1].scale
    if not (s and s > 0) then return end
    if lo and lo > 0 then return 0.5 * lo / s, 0.5 * lo / s end
    local cw, ch = sc.Child:GetWidth(), sc.Child:GetHeight()
    if not (cw > 0 and ch > 0) then return end
    return sc:GetWidth() / s / cw / 2, sc:GetHeight() / s / ch / 2
end

local function Smooth(v, a, b)
    if b <= a then return v >= b and 1 or 0 end
    local t = math.max(0, math.min(1, (v - a) / (b - a)))
    return t * t * (3 - 2 * t)
end

-- how big a zone is drawn now, as a share of its own fully-out view (1: as
-- big, where the wheel switches to it)
local function Closeness(z, hw, hh)
    local fw, fh = 0.5, 0.5
    -- (not `x and f()`: that keeps only f's first value, and this always fell back)
    local l, t, r, b, aw, ah
    if ns.ZoneBounds then l, t, r, b, aw, ah = ns.ZoneBounds(z.id) end
    if l and aw and aw > 0 and r > l and b > t then fw, fh = (r - l) / aw / 2, (b - t) / ah / 2 end
    local zhw, zhh = hw / (z.r - z.l), hh / (z.b - z.t)
    return math.max(fw / zhw, fh / zhh)
end

-- the continent's closeness: the median zone's, so every zone fades alike
local function Median(list, hw, hh)
    local v = {}
    for _, z in ipairs(list) do v[#v + 1] = Closeness(z, hw, hh) end
    if #v == 0 then return 0 end
    table.sort(v)
    return v[math.floor((#v + 1) / 2)]
end

-- The continent's closest zoom (a canvas scale): CAP times the zoom where its
-- last zone can be wheeled into (Browse.lua switches once a zone's own map can
-- show the view, a little past its own furthest zoom; the room past that lets
-- views near a zone's edge get inside it too)
-- How far a zone's own map zooms past its fully-out view (MapControls'
-- AddZoomLevels: closestX art on screen, on the big map as far as at your
-- normal size)
local function Reach(sc, id)
    if not (ns.ScaleForX and ns.NormalViewSize) then return 1.5 end
    local lo = ns.ZoneLowestScale(sc, id, ns.NormalViewSize(sc))
    if not (lo and lo > 0) then return 1.5 end
    return math.max(1.5, ns.ScaleForX(sc, ns.db.zoom.closestX or 8) / lo)
end

-- the big map: the wheel stays on the continent (Browse.lua), so it zooms on
-- as far as each zone's own map would
local function Big() return ns.MapIsBig and ns.MapIsBig() end

function ns.OverviewCap(sc)
    if not (ns.db and Cfg().enabled and sc and sc.mapID and IsOverview(sc.mapID) and ns.ZoneLowestScale) then return end
    local cw = sc.Child and sc.Child:GetWidth()
    if not (cw and cw > 0) then return end
    local most
    for _, z in ipairs(ZonesOf(sc.mapID)) do
        local lo, aw = ns.ZoneLowestScale(sc, z.id)
        if lo then
            -- (the zone's art is aw wide on its own map, (r - l) * cw on the continent's)
            local need = lo * aw / (cw * (z.r - z.l)) * CAP
            if Big() then need = math.max(need, need / CAP * Reach(sc, z.id)) end
            if not most or need > most then most = need end
        end
    end
    return most
end

-- Close-up detail on the big map's continent (Detail.lua): the zone under the
-- view's middle, measured as its own map would be. Times closer than its
-- fully-out view, and how far its map zooms past that; nil off a zone.
function ns.ContinentZoneZoom(map)
    local sc = map.ScrollContainer
    local id = map:GetMapID()
    if not (Big() and sc and sc.Child and id and IsOverview(id) and ns.ZoneLowestScale) then return end
    local cw, s = sc.Child:GetWidth(), sc:GetCanvasScale()
    if not (cw and cw > 0 and s and s > 0) then return end
    local x, y = sc.currentScrollX or 0.5, sc.currentScrollY or 0.5
    -- the zone there (its outline, from the game); else the smallest box round it
    local at
    local ok, info = pcall(C_Map.GetMapInfoAtPosition, id, x, y)
    local list = ZonesOf(id)
    for _, z in ipairs(list) do
        if ok and info and info.mapID == z.id then at = z break end
    end
    if not at then
        for _, z in ipairs(list) do
            if x >= z.l and x <= z.r and y >= z.t and y <= z.b
                and (not at or (z.r - z.l) * (z.b - z.t) < (at.r - at.l) * (at.b - at.t)) then at = z end
        end
    end
    if not at then return end
    local lo, aw = ns.ZoneLowestScale(sc, at.id)
    if not lo then return end
    return s / (lo * aw / (cw * (at.r - at.l))), Reach(sc, at.id)
end

-- The continent's own art, where no zone map covers it (open sea, its big
-- lettering, land between zone maps): zoomed in it showed hard stair-steps, as
-- if scaled pixel by pixel, though the game asks for smooth scaling. Each of
-- its tiles gets that again (soft and blurred instead of blocky); a tile the
-- game swaps in is caught on the next update.
local smoothed = setmetatable({}, { __mode = "k" })  -- [texture] = the file it was smoothed with
local function SmoothContinent(map)
    for _, layer in ipairs({ map:GetCanvas():GetChildren() }) do
        if layer.layerIndex ~= nil and not layer.bfiOwn then
            for _, r in ipairs({ layer:GetRegions() }) do
                if r:IsObjectType("Texture") and r:IsShown() then
                    local fid = r.GetTextureFileID and r:GetTextureFileID()
                    if fid and smoothed[r] ~= fid then
                        local c = { r:GetTexCoord() }  -- (its crop kept)
                        r:SetTexture(fid, nil, nil, "TRILINEAR")
                        if #c == 8 then r:SetTexCoord(unpack(c)) end
                        smoothed[r] = fid
                    end
                end
            end
        end
    end
end

local function Update()
    local map = BattlefieldMapFrame
    if not (host and map) then return end
    local c = Cfg()
    local id = map:GetMapID()
    if not (c.zoneArt and map:IsVisible() and IsOverview(id)) then
        host:Hide()
        GlowAlpha(1)
        return
    end
    ns.Safe("ZoneArt SmoothContinent", SmoothContinent, map)
    local sc = map.ScrollContainer
    local hw, hh = ViewHalf(sc)
    if not hw then host:Hide() return end
    local level = ns.ArtLevel(map, 0)
    if host:GetFrameLevel() ~= level then host:SetFrameLevel(level) end
    local list = ZonesOf(id)
    if shownFor ~= id then
        for _, other in pairs(zones) do
            for _, z in ipairs(other) do if z.frame then z.frame:Hide() end end
        end
        shownFor = id
    end
    local near = Median(list, hw, hh)
    GlowAlpha(1 - Smooth(near, GLOW_FROM, GLOW_GONE))
    local from, full = c.fadeFrom or 0.1, c.fadeFull or 0.25
    -- A crossfade, so colour never drops out: the area pieces rise evenly from
    -- fadeFrom to detailFull, and the base map comes in only to VEIL by
    -- fadeFull, the continent's own colours showing through it until the
    -- areas have taken over. (Base full and areas only after it left a plain
    -- grey-gold stretch with no colour at all.)
    local dFull = math.max(full, c.detailFull or 0.95)
    local detail = dFull > from and math.max(0, math.min(1, (near - from) / (dFull - from))) or 1
    -- s: the zone's frame (and the wash in it, when on: covering the continent's
    -- art); veil: the base map in it, so the wash shows through; a: the two
    local s = Smooth(near, from, full)
    local veil = VEIL + (1 - VEIL) * detail
    local a = s * veil
    local wash = c.zoneWash
    -- the map's own opacity fades the map art, not the frame: fade with it
    local global = map.GetGlobalAlpha and map:GetGlobalAlpha() or 1
    for _, z in ipairs(list) do
        if a > 0.01 then
            if not z.frame or not z.placed then Place(z) z.placed = true end
            ns.Safe("ZoneArt Build", Build, z)  -- (only once it shows, and again when it changes)
            z.frame:SetAlpha(s * global)
            if z.veil ~= veil or z.veilFor ~= z.builtFor then
                for i = 1, z.usedBase do z.baseTex[i]:SetAlpha(veil) end
                z.veil, z.veilFor = veil, z.builtFor
            end
            if z.wash then z.wash:SetShown(wash and true or false) end
            -- (without a mask the pieces are all there is: they take the base's fade)
            z.pieces:SetAlpha(z.mask and detail * veil or veil)
            z.frame:Show()
        elseif z.frame then
            z.frame:Hide()
        end
    end
    -- the fills, with the base maps (under every zone's frame: they're the host's own)
    local masks, tint = Fills(id)
    for _, f in ipairs(host.fills) do
        if masks and a > 0.01 then
            local file = masks[f.kind]
            if f.maskFor ~= file then
                f.mask:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                f.maskFor = file
            end
            local k = f.kind == "sea" and 1 or f.kind == "cool" and 4 or 7
            f.tex:SetVertexColor(tint[k], tint[k + 1], tint[k + 2])
            local cw, ch = host:GetWidth(), host:GetHeight()
            local n = f.kind == "land" and FILL_TILES or SEA_TILES
            if cw > 0 then f.tex:SetTexCoord(0, n, 0, n * ch / cw) end
            f.tex:SetAlpha(a * global)
            f.tex:Show()
        else
            f.tex:Hide()
        end
    end
    host:Show()
end
ns.UpdateZoneArt = Update

-- the highest frame level of the zone maps (their explored areas), for what
-- goes over them (Detail.lua); nil while they're not drawn. Read off the frames:
-- a child keeps its level when the host's changes after it was made.
function ns.ZoneArtTop()
    if not (host and host:IsShown() and shownFor) then return end
    local top = host:GetFrameLevel()
    for _, z in ipairs(zones[shownFor] or {}) do
        if z.pieces and z.frame:IsShown() then top = math.max(top, z.pieces:GetFrameLevel(), z.frame:GetFrameLevel()) end
    end
    return top
end

-- after a setting change: lay everything out again
function ns.RebuildZoneArt()
    for _, list in pairs(zones) do
        for _, z in ipairs(list) do z.builtFor = nil end
    end
    if ns.RefreshZoomLevels then ns.RefreshZoomLevels() end  -- (the continent's closest zoom)
    Update()
end

-- for /bfi check: zones on this continent, with an outline, built
function ns.ZoneArtInfo()
    local map = BattlefieldMapFrame
    local id = map and map:GetMapID()
    if not IsOverview(id) then return "not on a continent" end
    local n, shaped, built = 0, 0, 0
    for _, z in ipairs(ZonesOf(id)) do
        n = n + 1
        if z.shape then shaped = shaped + 1 end
        if z.builtFor then built = built + 1 end
    end
    return string.format("%d zones, %d with an outline, %d built, shown %s, alpha %.2f",
        n, shaped, built, tostring(host and host:IsShown()), host and host:GetEffectiveAlpha() or 0)
end

-- /bfi shapes ------------------------------------------------------------------

-- Asks the game which zone owns each spot of every continent, on a fine grid,
-- and keeps the answers in BattlefieldInfoDB.zoneShapes for tools\zone_shapes.py
-- (after a /reload). Each row is run lengths, "mapID*count ..." (0: no zone).
-- Run once per client: Classic Era and Forever place some zones differently.
local GRID_W = 600  -- spots across a continent (down: as its art's shape)

function ns.SampleZoneShapes()
    if not (C_Map.GetMapInfoAtPosition and C_Map.GetMapChildrenInfo and ns.StartDataJob) then
        ns.Log("this client can't tell zone shapes")
        return
    end
    local ok, list = pcall(C_Map.GetMapChildrenInfo, 947, T.Continent)
    local conts = {}
    for _, info in ipairs(ok and list or {}) do conts[#conts + 1] = info.mapID end
    local out = { edition = ns.FOREVER and "Forever" or "Era", client = ns.CLIENT,
                  build = select(2, GetBuildInfo()), grid = GRID_W, continents = {} }
    ns.Log(string.format("Zone shapes: sampling %d continents, about a minute. Carry on playing.", #conts))
    ns.StartDataJob("Zone shapes", function()
        for _, cont in ipairs(conts) do
            local aw, ah = ns.MapArtSize(cont)
            local W = GRID_W
            local H = math.floor(W * ah / aw + 0.5)
            local c = { id = cont, w = W, h = H, rows = {}, zones = {} }
            local zl = C_Map.GetMapChildrenInfo(cont, T.Zone) or {}
            for _, info in ipairs(zl) do
                local l, r, t, b = C_Map.GetMapRectOnMap(info.mapID, cont)
                if l and r > l and b > t then
                    c.zones[#c.zones + 1] = string.format("%d %.6f %.6f %.6f %.6f", info.mapID, l, r, t, b)
                end
            end
            for y = 0, H - 1 do
                local ny = (y + 0.5) / H
                local runs, last, n = {}, nil, 0
                for x = 0, W - 1 do
                    local info = C_Map.GetMapInfoAtPosition(cont, (x + 0.5) / W, ny)
                    local id = info and info.mapID ~= cont and info.mapID or 0
                    if id == last then
                        n = n + 1
                    else
                        if last then runs[#runs + 1] = last .. "*" .. n end
                        last, n = id, 1
                    end
                end
                runs[#runs + 1] = last .. "*" .. n
                c.rows[y + 1] = table.concat(runs, " ")
                if y % 4 == 3 then coroutine.yield() end
            end
            out.continents[#out.continents + 1] = c
            ns.Log(string.format("Zone shapes: %s done (%d zones).", (C_Map.GetMapInfo(cont) or {}).name or cont, #c.zones))
        end
    end, function(done)
        if not done then ns.Log("Zone shapes: stopped by an error") return end
        BattlefieldInfoDB.zoneShapes = out
        ns.Log("Zone shapes: all done. /reload so they're written to disk.")
    end)
end

-- The game's zone highlight (the gold outline under the cursor on a continent)
-- is one pin the size of the whole canvas. The Battlefield Map's pin scale
-- (0.6, times ours) shrank it toward the middle, so on a continent it sat small
-- and off its zone. It ignores the pin scale now. Its glow is additive and
-- bright over the zones' own art: softer (HIGHLIGHT_ALPHA).
local HIGHLIGHT_ALPHA = 0.45
local function FixHighlight(map)
    if not map.EnumeratePinsByTemplate then return end
    for pin in map:EnumeratePinsByTemplate("MapHighlightPinTemplate") do
        highlights[pin] = true
        if pin.HighlightTexture then pin.HighlightTexture:SetAlpha(HIGHLIGHT_ALPHA) end
        if pin.SetIgnoreGlobalPinScale and not pin.ignoreGlobalPinScale then
            pin:SetIgnoreGlobalPinScale(true)
            pin:SetScale(1)
            pcall(pin.ApplyCurrentPosition, pin)
        end
    end
end

function ns.SetupZoneArt(map)
    ns.Safe("ZoneArt FixHighlight", FixHighlight, map)
    if map.OnMapChanged then
        hooksecurefunc(map, "OnMapChanged", function() ns.Safe("ZoneArt FixHighlight", FixHighlight, map) end)
    end
    local canvas = map:GetCanvas()
    host = CreateFrame("Frame", nil, canvas)
    host:SetAllPoints(canvas)
    host:Hide()
    ns.debugFrames.zoneArt = host
    -- the fills: paper on the land, water on the sea, its cool patches over it,
    -- each through its own mask
    host.fills = {}
    for i, kind in ipairs({ "land", "sea", "cool" }) do
        local f = { kind = kind }
        f.tex = host:CreateTexture(nil, "BACKGROUND", nil, i - 1)
        f.tex:SetTexture(kind == "land" and PAPER or SEA, "REPEAT", "REPEAT", "TRILINEAR")
        f.tex:SetAllPoints(host)
        f.mask = host:CreateMaskTexture()
        f.mask:SetAllPoints(host)
        f.tex:AddMaskTexture(f.mask)
        f.tex:Hide()
        host.fills[#host.fills + 1] = f
    end

    if map.OnMapChanged then hooksecurefunc(map, "OnMapChanged", function() ns.Safe("ZoneArt", Update) end) end
    if map.OnCanvasScaleChanged then
        hooksecurefunc(map, "OnCanvasScaleChanged", function() ns.Safe("ZoneArt", Update) end)
    end
    -- (a new canvas size: the zones' frames are placed in its units)
    canvas:HookScript("OnSizeChanged", function()
        for _, list in pairs(zones) do
            for _, z in ipairs(list) do z.placed, z.builtFor = nil, nil end
        end
        ns.Safe("ZoneArt", Update)
    end)
    map:HookScript("OnShow", function() ns.Safe("ZoneArt", Update) end)

    -- now and then too: areas you discover, the map's opacity, the fog's settings
    local elapsed = 0
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 1 then return end
        elapsed = 0
        if map:IsVisible() then ns.Safe("ZoneArt", Update) end
    end)
end
