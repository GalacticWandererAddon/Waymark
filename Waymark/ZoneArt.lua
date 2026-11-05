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
local SHAPES = ns.MEDIA .. "ZoneShapes\\"
local function ShapeFile(id)
    local edition = ns.MapEdition()
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
-- Off the fill's own coasts, the zone maps' coastal hatching: short brown dashes,
-- long and dense at the shore (Hatch1.tga through hatchnear<continent>.tga), short
-- and sparse further out (Hatch2.tga, hatchfar<continent>.tga); our own, untinted.
local PAPER = SHAPES .. "Paper"
local SEA = SHAPES .. "Sea"
local FILL_TILES = 40  -- paper tiles across a continent (their grain about a zone map's)
local SEA_TILES = 10   -- water tiles across a continent
local HATCH_TILES = 40 -- dash tiles across a continent (a row about every 3 of a zone map's pixels)
local FILL_KINDS = {   -- { kind, texture, tiles across } bottom up
    { "land", PAPER, FILL_TILES }, { "sea", SEA, SEA_TILES }, { "cool", SEA, SEA_TILES },
    { "hatchfar", SHAPES .. "Hatch2", HATCH_TILES }, { "hatchnear", SHAPES .. "Hatch1", HATCH_TILES },
}
-- The continents' big names (KALIMDOR, EASTERN KINGDOMS) ghosted through the zone maps
-- while they fade in: over the land each is covered by the continent art with its
-- letters painted out (letters<continent>.tga, tools\continent_letters.py, whose BOXES
-- these are), coming in with the sea fills. { l, t, r, b } of the continent, per edition.
local LETTERS = {
    Forever = { [1414] = { 0.35, 0.48, 0.64, 0.54 }, [1415] = { 0.345, 0.545, 0.655, 0.65 } },
}
-- The Paint brush's fills (CutEdit.lua, continents): our own sea in a few hues, lined
-- up with the sea fill's tiling so it carries on seamlessly, and the hatching's dashes.
-- { name, file, tiles across a continent, colour from the continent's tints }
local PAINTS = {
    { "Sea, warm", SEA, SEA_TILES, function(t) return t[1], t[2], t[3] end },
    { "Sea, cool", SEA, SEA_TILES, function(t) return t[4], t[5], t[6] end },
    { "Sea, deep", SEA, SEA_TILES, function(t) return t[4] * 0.8, t[5] * 0.84, t[6] * 0.88 end },
    { "Sea, pale", SEA, SEA_TILES, function(t) return math.min(1, t[1] * 1.12), math.min(1, t[2] * 1.12), math.min(1, t[3] * 1.1) end },
    { "Waves, dense", SHAPES .. "Hatch1", HATCH_TILES, function() return 1, 1, 1 end },
    { "Waves, sparse", SHAPES .. "Hatch2", HATCH_TILES, function() return 1, 1, 1 end },
    -- (the bake tints each stroke to the nearest zone map's own sea there, rgb; till
    -- then, and in the preview, the warm sea)
    { "Sea, matched", SEA, SEA_TILES, function(t) return t[1], t[2], t[3] end },
    -- (a flat colour, picked off a zone map with a right-click: rgb; at a low strength
    -- it shifts the tone under it and leaves its lines showing)
    { "Colour, picked", "Interface\\Buttons\\WHITE8X8", 1, function() return 0.6, 0.6, 0.5 end },
}
ns.PAINT_MATCHED = #PAINTS - 1
ns.PAINT_COLOUR = #PAINTS

-- a zone map's colour at (ax, ay) of its art (Data\ZoneShapes.lua <edition>Colours: a
-- coarse grid, lines and lettering left out), 0-1; nil without one
function ns.ZoneArtColourAt(zid, ax, ay)
    local all = ns.ZoneShapes and ns.ZoneShapes[ns.MapEdition() .. "Colours"]
    local grid = all and all[zid]
    if not grid then return end
    local aw, ah = ns.MapArtSize(zid)
    local gx = math.max(0, math.min(all.w - 1, math.floor(ax / aw * all.w)))
    local gy = math.max(0, math.min(all.h - 1, math.floor(ay / ah * all.h)))
    local i = (gy * all.w + gx) * 6
    local function C(k) return tonumber(grid:sub(i + k, i + k + 1), 16) / 255 end
    return C(1), C(3), C(5)
end
local DEFAULT_TINT = { 0.64, 0.64, 0.54, 0.64, 0.7, 0.63, 0.85, 0.61, 0.22 }
ns.PAINT_NAMES = {}
for i, p in ipairs(PAINTS) do ns.PAINT_NAMES[i] = p[1] end

local Fills
-- the fill's file, tiles across, and colour on this continent (rgb: a baked
-- Sea, matched stroke's own)
function ns.ZoneArtPaint(cont, i, rgb)
    local p = PAINTS[i] or PAINTS[1]
    if rgb then return p[2], p[3], rgb[1], rgb[2], rgb[3] end
    local _, tint = Fills(cont)
    local r, g, b = p[4](tint or DEFAULT_TINT)
    return p[2], p[3], r, g, b
end

function Fills(cont)
    local edition = ns.MapEdition()
    local list = ns.ZoneShapes and ns.ZoneShapes[edition .. "Fill"]
    local tint = list and list[cont]
    if not tint or not tint[9] then return end
    local base = SHAPES .. edition .. "\\"
    local masks = { land = base .. "land" .. cont, sea = base .. "sea" .. cont, cool = base .. "cool" .. cont }
    local hatched = ns.ZoneShapes[edition .. "Hatch"]
    if hatched and hatched[cont] then
        masks.hatchnear, masks.hatchfar = base .. "hatchnear" .. cont, base .. "hatchfar" .. cont
    end
    return masks, tint
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
            local ok2, l, r, t, b = pcall(ns.MapRectOnMap, info.mapID, cont)
            if ok2 and l and r > l and b > t and not CITIES[info.mapID] then
                local z = { id = info.mapID, cont = cont, l = l, r = r, t = t, b = b }
                z.shape = ShapeFile(info.mapID)
                list[#list + 1] = z
            end
        end
    end
    -- (Forever's maps on Classic Era: the zones only Forever has, which the game doesn't list)
    local fm = ns.ForeverMapDev()
    for id, x in pairs(fm and fm.extra or {}) do
        local r = fm.rects[id]
        if x[1] == cont and r then
            list[#list + 1] = { id = id, cont = cont, l = r[2], r = r[3], t = r[4], b = r[5], shape = ShapeFile(id) }
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
        local list = ns.ZoneWash and ns.ZoneWash[ns.MapEdition()]
        local rgb = list and list[z.id]
        if rgb then
            z.wash = z.frame:CreateTexture(nil, "BACKGROUND")
            z.wash:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
            z.wash:SetAllPoints(z.frame)
            z.wash:AddMaskTexture(z.mask)
            -- (and through its land outline too, the masks multiplied: through the soft mask
            -- alone, which reaches over the zone's own sea, the land colour lay out at sea,
            -- green off Feralas' coast)
            local cut = ns.CutFile and ns.CutFile(z.id)
            if cut then
                z.washLand = z.frame:CreateMaskTexture()
                z.washLand:SetTexture(cut, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                z.washLand:SetAllPoints(z.frame)
                z.wash:AddMaskTexture(z.washLand)
            end
        end
    end
    z.frame:ClearAllPoints()
    z.frame:SetPoint("TOPLEFT", host, "TOPLEFT", z.l * cw, -z.t * ch)
    z.frame:SetSize((z.r - z.l) * cw, (z.b - z.t) * ch)
end

-- the zone's base art, whole (its 256-pixel tiles, the last row and column cut to size)
local function LayBase(z, sx, sy)
    local l, files = ns.MapArtLayer(z.id)
    if not (l and files and files[1]) then return end
    local tw, th = l.tileWidth or 256, l.tileHeight or 256
    local across = math.ceil(l.layerWidth / tw)
    for i, fid in ipairs(files) do
        local col, row = (i - 1) % across, math.floor((i - 1) / across)
        local pw = math.min(tw, l.layerWidth - col * tw)
        local ph = math.min(th, l.layerHeight - row * th)
        if pw > 0 and ph > 0 then
            local t = Tex(z, false, "ARTWORK", -2)
            -- (only when it's another file: set again on a resize, a tile dropped out till it reloaded)
            local file = ns.MapArtFile and ns.MapArtFile(fid) or fid
            if t.artFile ~= file then
                t:SetTexture(file, nil, nil, "LINEAR")
                t.artFile = file
            end
            t:SetTexCoord(0, pw / tw, 0, ph / th)
            t:SetPoint("TOPLEFT", z.frame, "TOPLEFT", col * tw * sx, -row * th * sy)
            t:SetSize(pw * sx, ph * sy)
        end
    end
end

local function Build(z)
    local f = z.frame
    -- (asked of the game at most every 2 s a zone: every zone is looked at on each
    -- step of a pan, and asking them all each time was a spike of up to 18 ms)
    local now = GetTime()
    if not z.keys or now - z.keysAt >= 2 then
        z.keys, z.keysAt, z.keysN = ns.ExploredOverlayKeys(z.id), now, 0
        for _ in pairs(z.keys) do z.keysN = z.keysN + 1 end
        -- (nothing yet, as on a map's first open after a reload: asked again next
        -- time, or zones stayed bare for the 2 s)
        if z.keysN == 0 then z.keysAt = now - 2 end
    end
    local keys, n = z.keys, z.keysN
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

-- Clone patches -------------------------------------------------------------------
-- Painted with /bfi cut's Clone brush on a continent (CutEdit.lua): a piece of a
-- zone's map (its base art and all its area pieces, as explored) drawn somewhere
-- else, through the strokes' mask: mountains carried into the land between zone
-- maps, a coast mended. The game's own art, drawn live; we ship only the masks
-- (packed onto sheets, Media\ZoneClone\<edition>\<n>.tga, a fixed set, so a bake
-- needs only a /reload) and Data\ZoneClone.lua: per continent { l, t, r, b = the
-- patch's box (0-1), dx, dy = where its art comes from (the source minus the spot),
-- zone =, n = its sheet, u0, v0, u1, v1 = its part of the sheet }.
-- Each patch: the zone's art tiles under it, each cropped to the patch's box and laid
-- shifted, through the patch's mask (not the zone's outline: that fades toward the
-- zone's border, where the mountains are; the preview shows what's taken). Newer
-- strokes go over older ones where they overlap: the bake gives each patch a depth
-- (1 + the deepest earlier patch its box overlaps), and each depth has its own draw
-- slot (a layer and sublevel; 32 to a frame, the frames a level apart). Patches at one
-- depth never overlap, so their order doesn't matter (the game draws equal ones in
-- any order, and changed it when they were shown again).

local CLONES = ns.MEDIA .. "ZoneClone\\"
local patches = {}        -- [continent] = { patch, ... }

-- A zone's art as a list of tiles, in its art's pixels: { fid, x, y, w, h, u, v
-- (the texture's used part), piece = an area piece's } (the base art, then the area
-- pieces laid as Explore.lua's LayOverlay); aw, ah its size. A patch lays only
-- those under it (one stroke's worth); CutEdit's preview crops them per brush dot.
local tilesOf = {}
local function Pow2(v) local p = 1 while p < v do p = p * 2 end return p end
function ns.ZoneArtTiles(id)
    local zt = tilesOf[id]
    if zt then return zt end
    local aw, ah = ns.MapArtSize(id)
    zt = { aw = aw, ah = ah }
    local l, files = ns.MapArtLayer(id)
    if l and files then
        local tw, th = l.tileWidth or 256, l.tileHeight or 256
        local across = math.ceil(l.layerWidth / tw)
        for i, fid in ipairs(files) do
            local col, row = (i - 1) % across, math.floor((i - 1) / across)
            local pw, ph = math.min(tw, l.layerWidth - col * tw), math.min(th, l.layerHeight - row * th)
            if pw > 0 and ph > 0 then zt[#zt + 1] = { fid, col * tw, row * th, pw, ph, pw / tw, ph / th } end
        end
    end
    for _, o in ipairs(ns.ZoneOverlays and ns.ZoneOverlays(id) or {}) do
        local across, down = math.ceil(o.w / 256), math.ceil(o.h / 256)
        for row = 1, down do
            local ph = row < down and 256 or (o.h - 256 * (down - 1))
            local fh = row < down and 256 or Pow2(ph)
            for col = 1, across do
                local fid = o.files[(row - 1) * across + col]
                if fid then
                    local pw = col < across and 256 or (o.w - 256 * (across - 1))
                    local fw = col < across and 256 or Pow2(pw)
                    zt[#zt + 1] = { fid, o.x + 256 * (col - 1), o.y + 256 * (row - 1), pw, ph, pw / fw, ph / fh, piece = true }
                end
            end
        end
    end
    tilesOf[id] = zt
    return zt
end

-- The Clone brush's tints: the art's colours times these ({ r, g, b, name })
local CLONE_TINTS = {
    { 1, 1, 1, "none" }, { 1, 0.94, 0.84, "warmer" }, { 0.9, 0.97, 1, "cooler" },
    { 0.86, 0.86, 0.86, "darker" }, { 0.72, 0.72, 0.72, "much darker" },
}
ns.CLONE_TINTS = CLONE_TINTS

-- Where a clone's art comes from, and laying it. A clone op (or patch) o: dx, dy the
-- source minus its anchor ax, ay (the stroke's first point; continent 0-1), rot
-- (degrees: how far the art is turned where it's laid), sc (its size there), flip
-- (mirrored, before turning). From a spot T: source = A + d + Flip(Size⁻¹(Turn⁻¹(T - A))),
-- worked in square units (y in widths). The art is laid over the box l, t, r, b: each
-- of the zone's tiles under it, by get(piece) for a texture. Turned by a quarter (or
-- not at all) a tile is cropped to what falls in the box; at other angles each tile
-- covers the whole box, its texture coordinates turned, clamped to transparent
-- past its edge (a faint seam can show where tiles meet).
function ns.LayCloneArt(get, frame, o, zid, zr, l, t, r, b, cw, ch)
    local zt = ns.ZoneArtTiles(zid)
    local aw, ah = zt.aw, zt.ah
    local k = ch / cw
    local rot = (o.rot or 0) % 360
    local th = math.rad(rot)
    local c, s = math.cos(th), math.sin(th)
    local sc = o.sc or 1
    local fl = o.flip and -1 or 1
    local ax, ay, dx, dy = o.ax or l, o.ay or t, o.dx or 0, o.dy or 0
    local zl, ztop, zw, zh = zr[1], zr[3], zr[2] - zr[1], zr[4] - zr[3]
    local function Src(x, y)              -- a spot -> the zone's art px
        local X, Y = x - ax, (y - ay) * k
        local rx, ry = c * X + s * Y, -s * X + c * Y
        rx, ry = rx / sc * fl, ry / sc
        return (ax + dx + rx - zl) / zw * aw, (ay + dy + ry / k - ztop) / zh * ah
    end
    local function Dst(px, py)            -- the zone's art px -> a spot
        local X = ((px / aw * zw + zl) - ax - dx) * fl * sc
        local Y = ((py / ah * zh + ztop) - ay - dy) * k * sc
        return ax + c * X - s * Y, ay + (s * X + c * Y) / k
    end
    local function UV(tl, px, py)
        return (px - tl[2]) / tl[4] * tl[6], (py - tl[3]) / tl[5] * tl[7]
    end
    -- the source's footprint (the box's corners, in art px)
    local cx, cy = {}, {}
    cx[1], cy[1] = Src(l, t)
    cx[2], cy[2] = Src(l, b)
    cx[3], cy[3] = Src(r, t)
    cx[4], cy[4] = Src(r, b)
    local fx0, fx1 = math.min(cx[1], cx[2], cx[3], cx[4]), math.max(cx[1], cx[2], cx[3], cx[4])
    local fy0, fy1 = math.min(cy[1], cy[2], cy[3], cy[4]), math.max(cy[1], cy[2], cy[3], cy[4])
    local square = math.abs(rot - math.floor(rot / 90 + 0.5) * 90) < 1e-3
    for _, tl in ipairs(zt) do
        if o.base and tl.piece then break end  -- (Base: the base art alone, land as unexplored; pieces come last)
        local x0, x1 = math.max(fx0, tl[2]), math.min(fx1, tl[2] + tl[4])
        local y0, y1 = math.max(fy0, tl[3]), math.min(fy1, tl[3] + tl[5])
        if x1 > x0 and y1 > y0 then
            local bl, bt, br, bb, wrap = l, t, r, b, "CLAMPTOBLACKADDITIVE"
            if square then
                -- (the crop's spot on the box)
                local ax1, ay1 = Dst(x0, y0)
                local ax2, ay2 = Dst(x1, y1)
                bl, br = math.max(l, math.min(ax1, ax2)), math.min(r, math.max(ax1, ax2))
                bt, bb = math.max(t, math.min(ay1, ay2)), math.min(b, math.max(ay1, ay2))
                wrap = nil
            end
            if br > bl and bb > bt then
                local tex = get(tl.piece)
                tex:SetTexture(ns.MapArtFile and ns.MapArtFile(tl[1]) or tl[1], wrap, wrap, "LINEAR")
                local ulx, uly = UV(tl, Src(bl, bt))
                local llx, lly = UV(tl, Src(bl, bb))
                local urx, ury = UV(tl, Src(br, bt))
                local lrx, lry = UV(tl, Src(br, bb))
                tex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
                tex:ClearAllPoints()
                tex:SetPoint("TOPLEFT", frame, "TOPLEFT", bl * cw, -bt * ch)
                tex:SetSize((br - bl) * cw, (bb - bt) * ch)
                tex:Show()
            end
        end
    end
end

local function PatchesOf(cont)
    local list = patches[cont]
    if list then return list end
    list = {}
    local edition = ns.MapEdition()
    local data = ns.ZoneClone and ns.ZoneClone[edition] and ns.ZoneClone[edition][cont]
    for _, d in ipairs(data or {}) do
        local z
        if d.stamp then
            -- (a Stamp: drawn baked only, tools\clone_art.py)
        elseif d.mat then
            -- (a Paint patch: a fill, no zone)
            list[#list + 1] = { d = d, cont = cont, file = CLONES .. edition .. "\\" .. d.n, tex = {}, used = 0 }
        end
        for _, zz in ipairs((d.mat or d.stamp) and {} or ZonesOf(cont)) do
            if zz.id == d.zone then z = zz break end
        end
        if not z and not (d.mat or d.stamp) and C_Map.GetMapRectOnMap then
            -- (a zone ZonesOf leaves out: a capital)
            local ok, l, r, t, b = pcall(ns.MapRectOnMap, d.zone, cont)
            if ok and l and r > l and b > t then z = { id = d.zone, l = l, r = r, t = t, b = b } end
        end
        if z then list[#list + 1] = { d = d, z = z, file = CLONES .. edition .. "\\" .. d.n, tex = {}, used = 0 } end
    end
    patches[cont] = list
    return list
end

-- The draw slots: depth 1 lowest. Each depth takes two sublevels (the base art, then
-- the area pieces over it) of one of a frame's four layers.
local SLOT_LAYERS = { "BACKGROUND", "BORDER", "ARTWORK", "OVERLAY" }
local slotFrames = {}     -- [k] the frame for depths 32k+1 .. 32k+32
local function SlotFrame(k)
    local f = slotFrames[k]
    if not f then
        f = CreateFrame("Frame", nil, host)
        f:SetAllPoints(host)
        slotFrames[k] = f
    end
    return f
end

local function Slot(depth)
    local s = math.max(0, (depth or 1) - 1)
    local k, i = math.floor(s / 32), s % 32
    return k, SLOT_LAYERS[math.floor(i / 8) + 1], (i % 8) * 2 - 8
end

local function PatchTex(p, f, layer, sub)
    p.used = p.used + 1
    local t = p.tex[p.used]
    if not t then
        t = f:CreateTexture(nil, layer, nil, sub)
        t:AddMaskTexture(p.mask)
        if t.SetSnapToPixelGrid then
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
        end
        p.tex[p.used] = t
    end
    t:ClearAllPoints()
    t:Show()
    return t
end

local function BuildPatch(p)
    local cw, ch = host:GetWidth(), host:GetHeight()
    if not (cw > 0 and ch > 0) then return end
    -- (whole units: the host's width comes from its anchors and can differ a hair with the
    -- zoom, which laid every patch again on each step)
    local size = math.floor(cw + 0.5)
    if p.builtFor == size then return end
    p.builtFor = size
    local d, z = p.d, p.z
    local k, layer, sub = Slot(d.depth)
    local f = SlotFrame(k)
    if not p.mask then
        p.mask = f:CreateMaskTexture()
        p.mask:SetTexture(p.file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    -- the mask: its sheet laid at the size that puts the patch's part (u0..u1, v0..v1)
    -- right over the patch's box; the textures reach no further than the box
    local fw, fh = (d.r - d.l) * cw, (d.b - d.t) * ch
    local u0, v0, u1, v1 = d.u0 or 0, d.v0 or 0, d.u1 or 1, d.v1 or 1
    local mw, mh = fw / math.max(1e-6, u1 - u0), fh / math.max(1e-6, v1 - v0)
    p.mask:ClearAllPoints()
    p.mask:SetPoint("TOPLEFT", host, "TOPLEFT", d.l * cw - u0 * mw, -d.t * ch + v0 * mh)
    p.mask:SetSize(mw, mh)
    p.used = 0
    if d.mat then
        -- a Paint patch: its fill over the box, tiled as the sea fill is (v in widths)
        local file, tiles, r, g, b = ns.ZoneArtPaint(p.cont, d.mat, d.rgb)
        local tex = PatchTex(p, f, layer, sub)
        tex:SetDrawLayer(layer, sub)
        tex:SetTexture(file, "REPEAT", "REPEAT", "TRILINEAR")
        tex:SetVertexColor(r, g, b)
        tex:SetTexCoord(d.l * tiles, d.r * tiles, d.t * ch / cw * tiles, d.b * ch / cw * tiles)
        tex:SetPoint("TOPLEFT", host, "TOPLEFT", d.l * cw, -d.t * ch)
        tex:SetSize(fw, fh)
        for i = p.used + 1, #p.tex do p.tex[i]:Hide() end
        p.fade = nil
        return
    end
    -- the zone's art under the patch's source (base art, then all its area pieces as
    -- explored), laid at the patch, turned and sized as painted, in its tint
    local tint = CLONE_TINTS[d.tint or 1] or CLONE_TINTS[1]
    ns.LayCloneArt(function(piece)
        local s = piece and sub + 1 or sub
        local tex = PatchTex(p, f, layer, s)
        tex:SetDrawLayer(layer, s)
        tex.piece = piece
        tex:SetVertexColor(tint[1], tint[2], tint[3])
        return tex
    end, host, d, z.id, { z.l, z.r, z.t, z.b }, d.l, d.t, d.r, d.b, cw, ch)
    for i = p.used + 1, #p.tex do p.tex[i]:Hide() end
    p.fade = nil
end

-- Off the view a patch is hidden but kept laid (each one draws a handful of masked
-- textures, and hundreds of them lagged the map even where you weren't looking)
local function Park(p)
    if p.parked then return end
    for i = 1, p.used do p.tex[i]:Hide() end
    p.parked = true
end

-- the view on the continent (0-1), and half as much again round it so a pan doesn't
-- show patches popping in; nil when it can't be told
local VIEW_MARGIN = 0.25
local function ViewBox()
    local sc = BattlefieldMapFrame and BattlefieldMapFrame.ScrollContainer
    local s = sc and sc:GetCanvasScale()
    local cw, ch = sc and sc.Child:GetWidth(), sc and sc.Child:GetHeight()
    if not (s and s > 0 and cw and cw > 0 and ch > 0) then return end
    local x, y = sc.currentScrollX or 0.5, sc.currentScrollY or 0.5
    local hw = sc:GetWidth() / s / cw / 2 * (1 + 2 * VIEW_MARGIN)
    local hh = sc:GetHeight() / s / ch / 2 * (1 + 2 * VIEW_MARGIN)
    return x - hw, y - hh, x + hw, y + hh
end

local patchesHidden = false  -- (ns.ZoneArtHidePatches)

-- Baked patches (tools\clone_art.py, Data\ZoneCloneArt.lua): an edition's clone and
-- paint work drawn as plain pictures instead, cut into cells over the continent:
-- f (base and area pieces) and b (the base alone), crossfaded as the zone maps' own
-- area pieces fade in. A few dozen textures where the live patches laid thousands
-- through their masks, which made zooming stutter.
local CLONE_ART = ns.MEDIA .. "ZoneCloneArt\\"
local bakedFrame          -- holds the cells' textures, for the continent bakedFor
local bakedFor, bakedW
local function BakedOf(cont)
    local all = ns.ZoneCloneArt and ns.ZoneCloneArt[ns.MapEdition()]
    return all and all[cont]
end

local function LayBaked(cont, data)
    local cw, ch = host:GetWidth(), host:GetHeight()
    if bakedFor == cont and bakedW == cw then return end
    if not bakedFrame then
        bakedFrame = CreateFrame("Frame", nil, host)
        bakedFrame:SetAllPoints(host)
        bakedFrame.tex = { f = {}, b = {}, l = {} }
        -- (the coast and land fills, l: their own frame, under the patches, faded with the
        -- sea fills rather than the zone maps)
        bakedFrame.fills = CreateFrame("Frame", nil, host)
        bakedFrame.fills:SetAllPoints(host)
    end
    bakedFor, bakedW = cont, cw
    local edition = ns.MapEdition()
    for sub, layer in ipairs({ "b", "f", "l" }) do
        local list, d = bakedFrame.tex[layer], data[layer]
        local owner = layer == "l" and bakedFrame.fills or bakedFrame
        local n = 0
        for _, c in ipairs(d or {}) do
            n = n + 1
            local t = list[n]
            if not t then
                t = owner:CreateTexture(nil, "ARTWORK", nil, sub)
                if t.SetSnapToPixelGrid then
                    t:SetSnapToPixelGrid(false)
                    t:SetTexelSnappingBias(0)
                end
                list[n] = t
            end
            local file = CLONE_ART .. edition .. "\\" .. cont .. "_" .. layer .. "_" .. c[1] .. "_" .. c[2]
            if t.artFile ~= file then  -- (a resize only moves it: see LayBase)
                t:SetTexture(file, "CLAMP", "CLAMP", "TRILINEAR")  -- (.blp with mips)
                t.artFile = file
            end
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", host, "TOPLEFT", c[1] / d.cols * cw, -c[2] / d.rows * ch)
            t:SetSize(cw / d.cols, ch / d.rows)
            t:Show()
        end
        for i = n + 1, #list do list[i]:Hide() end
        list.n = n
    end
end

local function ShowBaked(cont, a, s, veil, detail, global, seaA)
    local data = cont and BakedOf(cont)
    local on = data and a > 0.01 and true or false
    local fillsOn = data and seaA > 0.01 and true or false
    if bakedFrame then bakedFrame.on, bakedFrame.fillsOn = on, fillsOn end
    if not (on or fillsOn) then
        if bakedFrame then bakedFrame:Hide() bakedFrame.fills:Hide() end
        return
    end
    ns.Safe("ZoneArt LayBaked", LayBaked, cont, data)
    -- (over the zone maps' frames and pieces: the fills, then the patches over them)
    local level = host:GetFrameLevel() + 3
    if bakedFrame.fills:GetFrameLevel() ~= level then bakedFrame.fills:SetFrameLevel(level) end
    if bakedFrame:GetFrameLevel() ~= level + 1 then bakedFrame:SetFrameLevel(level + 1) end
    bakedFrame.fills:SetAlpha(seaA * global)
    bakedFrame.fills:SetShown(fillsOn and not patchesHidden)
    if not on then bakedFrame:Hide() return end
    bakedFrame:SetAlpha(s * global)
    for layer, k in pairs({ b = veil * (1 - detail), f = veil * detail }) do
        local list = bakedFrame.tex[layer]
        for i = 1, list.n or 0 do
            list[i]:SetAlpha(k)
            list[i]:SetShown(k > 0.01)
        end
    end
    bakedFrame:SetShown(not patchesHidden)
end

-- (the outline editor's before/after: Ctrl held on a continent hides them all)
function ns.ZoneArtHidePatches(hide)
    if patchesHidden == (hide and true or false) then return end
    patchesHidden = hide and true or false
    for _, f in pairs(slotFrames) do f:SetShown(not patchesHidden and f.on) end
    if bakedFrame then
        bakedFrame:SetShown(not patchesHidden and bakedFrame.on)
        bakedFrame.fills:SetShown(not patchesHidden and bakedFrame.fillsOn)
    end
end

-- shown as the zone maps are (s: the frames, veil: the base maps, detail: the areas)
local patchesFor          -- the continent whose patches are laid
local BUILDS_A_CALL = 20  -- (patches laid at once: the rest next frame, or a zoom into hundreds stuttered)
local buildsLeft          -- ShowPatches' latest arguments while some wait to be laid
local function ShowPatches(cont, a, s, veil, detail, global, seaA)
    if patchesFor ~= cont then
        -- (kept laid: wheeling out of a zone onto the continent laid every patch again)
        for _, p in ipairs(patchesFor and patches[patchesFor] or {}) do Park(p) end
        patchesFor = cont
    end
    -- (baked: the pictures, the live patches not laid at all; Era's cells are its land alone)
    local data = BakedOf(cont)
    local baked = data and data.f and #data.f > 0 or false
    ShowBaked(cont, a, s, veil, detail, global, seaA)
    local list = baked and {} or PatchesOf(cont)
    local on = a > 0.01 and #list > 0
    local level = host:GetFrameLevel() + 4  -- (over the zone maps' frames and pieces, and the land cells)
    for k, f in pairs(slotFrames) do
        if f:GetFrameLevel() ~= level + k then f:SetFrameLevel(level + k) end
        f:SetAlpha(s * global)
        f.on = on
        f:SetShown(on and not patchesHidden)
    end
    if not on then return end
    local fade = veil .. "|" .. detail
    local vl, vt, vr, vb = ViewBox()
    local size, built, waiting = math.floor(host:GetWidth() + 0.5), 0, false
    for _, p in ipairs(list) do
        local d = p.d
        local inView = not vl or (d.r > vl and d.l < vr and d.b > vt and d.t < vb)
        if not inView then
            Park(p)
        else
            if p.parked then
                for i = 1, p.used do p.tex[i]:Show() end
                p.parked = nil
            end
            -- (checked here: a call for each of hundreds already laid was most of the cost)
            if p.builtFor ~= size then
                if built < BUILDS_A_CALL then
                    built = built + 1
                    ns.Safe("ZoneArt BuildPatch", BuildPatch, p)
                else
                    waiting = true
                end
            end
        end
        if inView and p.fade ~= fade and p.builtFor == size then
            for i = 1, p.used do
                local t = p.tex[i]
                t:SetAlpha(t.piece and veil * detail or veil)
            end
            p.fade = fade
        end
    end
    if waiting then
        if not buildsLeft then
            C_Timer.After(0, function()
                local b = buildsLeft
                buildsLeft = nil
                ShowPatches(b[1], b[2], b[3], b[4], b[5], b[6], b[7])
            end)
        end
        buildsLeft = { cont, a, s, veil, detail, global, seaA }
    elseif buildsLeft then
        buildsLeft = { cont, a, s, veil, detail, global, seaA }
    end
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

-- a continent's median zone width (share of the continent), for the sea's fade
local SEA_REF = 0.0986   -- (the Eastern Kingdoms' (Forever): its sea's timing is the one kept)
local medianWidth = {}
local function MedianWidth(id, list)
    if not medianWidth[id] then
        local v = {}
        for _, z in ipairs(list) do if z.r > z.l then v[#v + 1] = z.r - z.l end end
        table.sort(v)
        medianWidth[id] = v[1] and v[math.floor((#v + 1) / 2)] or SEA_REF
    end
    return medianWidth[id]
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
                    -- (a tile still loading, as on the first open after a reload, is left
                    -- till it has: set again mid-load, the continent flashed empty)
                    local loading = r.IsObjectLoaded and not r:IsObjectLoaded()
                    if fid and smoothed[r] ~= fid and not loading then
                        local c = { r:GetTexCoord() }  -- (its crop kept)
                        r:SetTexture(fid, nil, nil, "TRILINEAR")
                        if #c == 8 then r:SetTexCoord(unpack(c)) end
                        smoothed[r] = fid
                        host.resets = (host.resets or 0) + 1  -- (for /bfi fillwatch)
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
    local t0 = debugprofilestop()  -- (the pieces timed for /bfi check's frame cost)
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
    ns.CostAdd("ZoneArt head", t0)
    t0 = debugprofilestop()
    for _, z in ipairs(list) do
        if a > 0.01 then
            if not z.frame or not z.placed then Place(z) z.placed = true end
            ns.Safe("ZoneArt Build", Build, z)  -- (only once it shows, and again when it changes)
            z.frame:SetAlpha(s * global)
            if z.veil ~= veil or z.veilFor ~= z.builtFor then
                for i = 1, z.usedBase do z.baseTex[i]:SetAlpha(veil) end
                z.veil, z.veilFor = veil, z.builtFor
            end
            -- (by its alpha, kept shown, its mask set again when it changes: a masked texture
            -- shown or faded again was only redrawn on the next zoom, so the toggle seemed to
            -- work once per zoom, then not at all)
            if z.wash and z.washOn ~= (wash and true or false) then
                z.washOn = wash and true or false
                z.wash:SetAlpha(wash and 1 or 0)
                z.wash:RemoveMaskTexture(z.mask)
                z.wash:AddMaskTexture(z.mask)
                if z.washLand then
                    z.wash:RemoveMaskTexture(z.washLand)
                    z.wash:AddMaskTexture(z.washLand)
                end
            end
            -- (without a mask the pieces are all there is: they take the base's fade)
            z.pieces:SetAlpha(z.mask and detail * veil or veil)
            z.frame:Show()
        elseif z.frame then
            z.frame:Hide()
        end
    end
    ns.CostAdd("ZoneArt zones", t0)
    t0 = debugprofilestop()
    -- (the sea fills come in whole and sooner, by halfway to fadeFull: crossfaded like the
    -- zone maps, the continent art's sea lettering, kraken and swirls ghosted through them;
    -- the baked coast and land fills come with them. By the zoom, not the zones' size:
    -- Kalimdor's zones are wider on their continent (median 0.14 against 0.099), so by
    -- `near` its sea came in a good step sooner than the Eastern Kingdoms')
    local seaNear = near * SEA_REF / MedianWidth(id, list)
    local seaA = Smooth(seaNear, from * 0.6, (from + full) / 2)
    host.near, host.a, host.seaA, host.baked = near, a, seaA, bakedFrame  -- (for /bfi fillwatch)
    ShowPatches(id, a, s, veil, detail, global, seaA)
    ns.CostAdd("ZoneArt patches", t0)
    t0 = debugprofilestop()
    -- the fills, with the base maps (under every zone's frame: they're the host's own)
    local masks, tint = Fills(id)
    for _, f in ipairs(host.fills) do
        local file = masks and masks[f.kind]
        local fa = (f.kind == "sea" or f.kind == "cool") and seaA or a
        if file and fa > 0.01 then
            if f.maskFor ~= file then
                f.mask:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                f.maskFor = file
            end
            local k = f.kind == "sea" and 1 or f.kind == "cool" and 4 or f.kind == "land" and 7
            if k then f.tex:SetVertexColor(tint[k], tint[k + 1], tint[k + 2]) end
            local cw, ch = host:GetWidth(), host:GetHeight()
            local n = f.tiles
            if cw > 0 then f.tex:SetTexCoord(0, n, 0, n * ch / cw) end
            f.tex:SetAlpha(fa * global)
            f.tex:Show()
        else
            f.tex:Hide()
        end
    end
    local edition = ns.MapEdition()
    local box = LETTERS[edition] and LETTERS[edition][id]
    if box and seaA > 0.01 then
        local cw, ch = host:GetWidth(), host:GetHeight()
        if host.lettersFor ~= edition .. id .. "|" .. cw then
            host.letters:SetTexture(SHAPES .. edition .. "\\letters" .. id, "CLAMP", "CLAMP", "LINEAR")
            host.letters:ClearAllPoints()
            host.letters:SetPoint("TOPLEFT", host, "TOPLEFT", box[1] * cw, -box[2] * ch)
            host.letters:SetSize((box[3] - box[1]) * cw, (box[4] - box[2]) * ch)
            host.lettersFor = edition .. id .. "|" .. cw
        end
        host.letters:SetAlpha(seaA * global)
        host.letters:Show()
    else
        host.letters:Hide()
    end
    host:Show()
    ns.CostAdd("ZoneArt fills", t0)
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
    for _, f in pairs(slotFrames) do
        if f:IsShown() then top = math.max(top, f:GetFrameLevel()) end
    end
    if bakedFrame and bakedFrame:IsShown() then top = math.max(top, bakedFrame:GetFrameLevel()) end
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
local canvasSized = { calls = 0, real = 0 }  -- (OnSizeChanged's count, for the check)
function ns.ZoneArtInfo()
    local map = BattlefieldMapFrame
    local id = map and map:GetMapID()
    if not IsOverview(id) then return "not on a continent" end
    local n, shaped, built, washes, washOn, veil = 0, 0, 0, 0, 0, nil
    for _, z in ipairs(ZonesOf(id)) do
        n = n + 1
        if z.shape then shaped = shaped + 1 end
        if z.builtFor then built = built + 1 end
        if z.wash then
            washes = washes + 1
            if z.wash:IsShown() and z.wash:GetAlpha() > 0.5 then washOn = washOn + 1 end
        end
        veil = veil or z.veil
    end
    return string.format("%d zones, %d with an outline, %d built, shown %s, alpha %.2f; wash %s, %d of %d lit, base veil %.2f; canvas sized %d times, %d real, now %s x %s, host %.3f",
        n, shaped, built, tostring(host and host:IsShown()), host and host:GetEffectiveAlpha() or 0,
        tostring(Cfg().zoneWash), washOn, washes, veil or -1, canvasSized.calls, canvasSized.real,
        tostring(canvasSized.w), tostring(canvasSized.h), host and host:GetWidth() or 0)
end

-- /bfi shapes ------------------------------------------------------------------

-- Asks the game which zone owns each spot of every continent, on a fine grid,
-- and keeps the answers in WaymarkDB.zoneShapes for tools\zone_shapes.py
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
        WaymarkDB.zoneShapes = out
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

-- Warming: the map's first open after a /reload flashed empty, or stayed blank till the
-- mouse came over it: our own textures (masks, fills, baked cells, the zones' base art),
-- hundreds of them, loading from disk on first use. So after login, and on reaching
-- another continent, the player's continent's are set on an unseen frame a few a frame, then
-- every other continent's, all kept (a file stays loaded while some texture holds it).
local WARM_PER_FRAME = 8
local warmFrame, warmTicker, warmFor
local warmTex = {}

local function PlayerContinent()
    local id = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    for _ = 1, 8 do
        local info = id and C_Map.GetMapInfo(id)
        if not info then return end
        if info.mapType == T.Continent then return id end
        id = info.parentMapID
    end
end

local warmCell = {}  -- [file] = true: a baked cell, set as it's drawn (LayBaked)

local function WarmList(cont)
    local files, seen = {}, {}
    local function Add(f)
        if f and not seen[f] then seen[f], files[#files + 1] = true, f end
    end
    for _, f in pairs(Fills(cont) or {}) do Add(f) end
    Add(PAPER) Add(SEA) Add(SHAPES .. "Hatch1") Add(SHAPES .. "Hatch2")
    local data, edition = BakedOf(cont), ns.MapEdition()
    for _, layer in ipairs({ "b", "f", "l" }) do
        for _, c in ipairs(data and data[layer] or {}) do
            local f = CLONE_ART .. edition .. "\\" .. cont .. "_" .. layer .. "_" .. c[1] .. "_" .. c[2]
            warmCell[f] = true
            Add(f)
        end
    end
    for _, z in ipairs(ZonesOf(cont)) do
        Add(z.shape)
        local _, tiles = ns.MapArtLayer(z.id)
        for _, fid in ipairs(tiles or {}) do Add(ns.MapArtFile and ns.MapArtFile(fid) or fid) end
    end
    -- (the zones' area pieces last: most of the files, and the detail that came in late)
    for _, z in ipairs(ZonesOf(cont)) do
        for _, o in ipairs(ns.ZoneOverlays and ns.ZoneOverlays(z.id) or {}) do
            for _, fid in ipairs(o.files or {}) do Add(ns.MapArtFile and ns.MapArtFile(fid) or fid) end
        end
    end
    return files
end

local function Warm()
    local cont = PlayerContinent()
    if not (cont and ns.db and Cfg().zoneArt) or warmFor then return end
    warmFor = cont
    if not warmFrame then
        -- (shown, a pixel in the screen's corner, all but see-through: a client may only
        -- load what it really draws, so not hidden, off the screen or at alpha 0)
        warmFrame = CreateFrame("Frame", nil, UIParent)
        warmFrame:SetSize(1, 1)
        warmFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
        warmFrame:SetAlpha(0.01)
        warmTicker = ns.TimedFrame("ZoneArt warm")
    end
    -- the player's continent first, then every other with our fills (the map is opened on
    -- other continents too: Kalimdor from Shadowfang Keep still flashed), all kept
    local conts = { cont }
    local fills = ns.ZoneShapes and ns.ZoneShapes[ns.MapEdition() .. "Fill"]
    local others = {}
    for id in pairs(fills or {}) do if id ~= cont then others[#others + 1] = id end end
    table.sort(others)
    for _, id in ipairs(others) do conts[#conts + 1] = id end
    local files, seen = {}, {}
    for _, id in ipairs(conts) do
        for _, f in ipairs(WarmList(id)) do
            if not seen[f] then seen[f], files[#files + 1] = true, f end
        end
    end
    local i = 0
    warmTicker:SetScript("OnUpdate", function(self)
        for _ = 1, WARM_PER_FRAME do
            i = i + 1
            local f = files[i]
            if not f then
                self:SetScript("OnUpdate", nil)
                return
            end
            if not warmTex[i] then
                warmTex[i] = warmFrame:CreateTexture()
                warmTex[i]:SetAllPoints(warmFrame)
            end
            if warmCell[f] then warmTex[i]:SetTexture(f, "CLAMP", "CLAMP", "TRILINEAR")
            else warmTex[i]:SetTexture(f) end
        end
    end)
end

function ns.SetupZoneArt(map)
    local warmEvents = CreateFrame("Frame")
    warmEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
    warmEvents:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    warmEvents:SetScript("OnEvent", function() ns.Safe("ZoneArt Warm", Warm) end)
    ns.Safe("ZoneArt Warm", Warm)
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
    for i, k in ipairs(FILL_KINDS) do
        local f = { kind = k[1], tiles = k[3] }
        f.tex = host:CreateTexture(nil, "BACKGROUND", nil, i - 1)
        f.tex:SetTexture(k[2], "REPEAT", "REPEAT", "TRILINEAR")
        f.tex:SetAllPoints(host)
        f.mask = host:CreateMaskTexture()
        f.mask:SetAllPoints(host)
        f.tex:AddMaskTexture(f.mask)
        f.tex:Hide()
        host.fills[#host.fills + 1] = f
    end
    -- (under the fills: it stands in for the continent's own art)
    host.letters = host:CreateTexture(nil, "BACKGROUND", nil, -1)
    host.letters:Hide()

    if map.OnMapChanged then hooksecurefunc(map, "OnMapChanged", function() ns.Safe("ZoneArt", Update) end) end
    if map.OnCanvasScaleChanged then
        hooksecurefunc(map, "OnCanvasScaleChanged", function() ns.Safe("ZoneArt", Update) end)
    end
    -- (a new canvas size: the zones' frames are placed in its units)
    canvas:HookScript("OnSizeChanged", function()
        -- (only a real change: it can fire with the same size, and laid every patch again)
        local w, h = math.floor(canvas:GetWidth() + 0.5), math.floor(canvas:GetHeight() + 0.5)
        canvasSized.calls = canvasSized.calls + 1
        if w == canvasSized.w and h == canvasSized.h then return end
        canvasSized.w, canvasSized.h, canvasSized.real = w, h, canvasSized.real + 1
        for _, list in pairs(zones) do
            for _, z in ipairs(list) do z.placed, z.builtFor = nil, nil end
        end
        for _, list in pairs(patches) do
            for _, p in ipairs(list) do p.builtFor = nil end
        end
        bakedW = nil
        ns.Safe("ZoneArt", Update)
    end)
    map:HookScript("OnShow", function() ns.Safe("ZoneArt", Update) end)

    -- now and then too: areas you discover, the map's opacity, the fog's settings
    -- and once the view has moved a good way (the patches off it are hidden)
    local elapsed, seenX, seenY = 0, nil, nil
    local ticker = ns.TimedFrame("ZoneArt tick")
    ticker:SetScript("OnUpdate", function(_, dt)
        local sc = map.ScrollContainer
        if host:IsShown() and sc and sc.currentScrollX then
            local l, t, r, b = ViewBox()
            local step = l and (r - l) * VIEW_MARGIN / (1 + 2 * VIEW_MARGIN) / 2
            if step and (not seenX or math.abs(sc.currentScrollX - seenX) > step
                    or math.abs(sc.currentScrollY - seenY) > step * (b - t) / (r - l)) then
                seenX, seenY = sc.currentScrollX, sc.currentScrollY
                ns.Safe("ZoneArt", Update)
                elapsed = 0
                return
            end
        end
        elapsed = elapsed + dt
        if elapsed < 1 then return end
        elapsed = 0
        if map:IsVisible() then ns.Safe("ZoneArt", Update) end
    end)
end
