local _, ns = ...

-- The pencilled map (the user, 2026-11-13, on the page "The Pencilled Map": "Yes!"). Cleared for 1.3 on
-- 2026-11-14; still Lab code until the release session takes it into a build.
-- Findings and the recipe: mockups\pencil-map.md. The sums are runtime() in tools\pencil_map.py.
--
-- Land you have not walked is drawn in pencil in place of the fog; land you have walked stays painted, and
-- when you find a new area the colour runs into the sketch from where you stand.
--
-- The game draws the pencil itself, from its own map art. Nothing drawn ships:
--   1 grey    the zone's art, all of it, desaturated
--   2 gain    four more copies of it added, each let through by a small mask (64 x 64: how dark the zone is
--             there). Paper goes to white, the painter's dark lines stay. This is the whole trick.
--   3 lift    our sheet of paper tooth, pressure and the ragged sheet edge, added: lines break and stop short
--   4 paper   our sheet, multiplied in
--   5 hatch   our strokes where the zone is darkest (a second small mask), and the ruled squares
-- Then the walked pieces, painted, on top.
--
-- THIS IS FIRST OF ALL A TEST. The sums were only worked through outside the game. /pencil step walks
-- through the five stages one at a time so a screenshot of each shows where the client departs from them.
-- Known to be unsure: a see-through map (the paper step may tint what shows through), pieces that overlap
-- (their added copies may land in the wrong order), the close-up detail tiles (same art level), weight.
--
-- Cost while it shows: the zone's tiles and pieces five times over, all still; laid out again only when
-- the map, its size or what you've explored changes. Nothing runs between, but for the 2.5 s of a find.
--
-- Colour where you walk (the user, 2026-11-13: "color the areas I'm walking, independent on getting the
-- explored trigger"). On by default with the pencil. The map is cut into 48 x 32 squares; standing within
-- 80 yards of a square's middle marks it, for this character (WaymarkCharDB.pencilWalk[map]), and only
-- marked ground is painted. Squares at the rim of what you've walked are painted through a soft round
-- blot, so the colour ends in an uneven blurred line; a new square fades in over a second. The game's
-- own "explored" no longer paints anything: the first time a zone is seen this way, what the game
-- already calls explored is taken over as walked, and each area found later fills its whole box too
-- (ground you cannot stand on would never fill otherwise). Not counted while on a flight path.
-- The rules of the squares are PencilWalk.lua (no game calls; tools\pencil_walk_test.lua).
-- Cost: one look every half second at where you stand. The painted part is laid again only when a new
-- square is marked, the pencil under it is not. A much-walked zone is many small textures: /pencil count.
-- /pencil: on or off. /pencil whole: the whole map in pencil, walked or not. /pencil step: the test.
-- /pencil walk: colour where you walk, or (off) whole areas as the game calls them explored.
-- /pencil tone 30..100: how bright the paper is (65 as it comes).
-- /pencil outline: the pencil kept inside the zone's own outline (clear view's, Media\ZoneCut), so the
--   neighbouring land on the sheet stays the plain parchment the game draws (the user, 2026-11-13: outside
--   the zone the pencil was "white drawing"). On as it comes. A zone without an outline is not cut.
-- /pencil blank: as forget, and what the game calls explored in this zone is set aside too: an empty sheet.
-- /pencil forget: this zone's walked ground, for this character. /pencil count: how many textures it holds.
--
-- Sighted land (the user, 2026-11-14: "the best use for it is sighted land ... land you've seen, or atleast
-- land you've been kind of near, rest staying unexplored. Because a zone in full pencil is a bit overwhelming
-- on the eye"). On as it comes; /pencil sight. Two styles, the user wants to see both (/pencil bare):
--   as it comes: "leaving the land not sighted as traditional unexplored, sighted gets sketching, and walked
--     gets paint": the map is as without the pencil (the unexplored look of the map's settings), and a
--     sighted area's sketch lies on it in the area's own shape;
--   bare: the whole sheet is the game's bare ground in pencil (coast and ridges, no roads, no names) and
--     the sketches are drawn onto it.
-- An area's sketch (its piece of the art) is drawn once you have
-- sighted it: been near it, looked down on it from a height, or seen it stand above you; from a flight
-- path you see as from 80 yards up. The rule is W.Sight in PencilWalk.lua, on the baked ground of
-- Data\PencilHeights.lua (a zone without it: the near land only). Per character:
-- WaymarkCharDB.pencilSight[map][piece]. Areas the game calls explored are known anyway; a character who
-- walked here before starts with what lies near the ground they walked. A newly sighted area fades in.
-- Cost: one look from each new 1/96 of the map you step into (about 0.03 ms), and fewer textures than the
-- full pencil, since unsighted areas are not drawn at all.
--
-- Only the part seen (the user, 2026-11-15, of whole areas sketched once a fifth of them was seen: "I thought
-- this was how it was supposed to work? not fill in big areas if i get closeish"). As it comes now, in the
-- first style: the sketch shows on the squares you have seen (WaymarkCharDB.pencilSeen[map]) and a square
-- past them, and ends in the same soft uneven line as the walked colour. How: a mask cannot be made of many
-- blots, and the pencil's added copies cannot overlap themselves, so the sketch is not cut. An area with
-- anything seen is sketched whole as before, and the game's own ground is laid back over the squares not
-- seen (LayBack: the base tiles, one texture a quad, by the paint's squares and blots). W.Unseen in
-- PencilWalk.lua says which squares and which areas. Ground seen just now has its cover fade off in a second.
-- With an unexplored look chosen in the settings, the unseen rest of a part-seen area is plain ground, not
-- that look (a see-through layer cannot end in overlapping blots); areas with nothing seen take the look.
-- The whole-area rule is still there for comparing (the test bench; /pencil part).

-- On as it comes since 2026-11-14: the user, asked what a new player's unexplored land is in 1.3, chose
-- "Blank + pencil" (answered in the session Idea hunt C, which sets the presets' unexplored land to Left blank).
-- A value already saved stays as it is.
local DEFAULT = { on = true, whole = false, walk = true, outline = true, sight = true }
-- Out of the Lab for 1.3 on 2026-11-14 (the user: "Move your done stuff from lab, pencil too"): its settings are
-- the addon's own (ns.db.pencil; DEFAULTS in BattlefieldInfo.lua, the same as DEFAULT here, which only stands in
-- before the settings are read), carried over once from the Lab's store where a dev copy had them there.
local function Cfg()
    local c = ns.db and ns.db.pencil
    if not c then return DEFAULT end
    local old = WaymarkDB and WaymarkDB.lab and WaymarkDB.lab.pencil
    if old and not old.moved then
        for k, v in pairs(old) do c[k] = v end
        old.moved = true
    end
    -- One style in 1.3 (the user, 2026-11-15: "Lets keep only this style for the pencil for 1.3 ... Keeps it
    -- simple for me to manage and test"): the part you have seen sketched, the rest the normal unexplored map,
    -- colour where you walk, inside the zone's outline. Whatever a dev copy saved for the other styles is put
    -- back at every read. Their code is still below, out of reach: ns.PencilAllStyles (set nowhere in the
    -- addon; tools\pencil_dry_run.lua sets it) lets it run.
    if not ns.PencilAllStyles then
        c.whole, c.walk, c.outline, c.sight, c.bare, c.part, c.share = false, true, true, true, false, true, nil
    end
    return c
end
ns.PencilCfg = Cfg       -- (the test bench, which stays in the Lab)

local PAPER = { 0.843, 0.748, 0.523 }   -- the sheet's colour (tools\pencil_bake.py prints it)
local tint = { 1, 1, 1 }         -- what the drawing's textures are coloured by: the paper, at its tone
local COPIES = 4                 -- (tools\pencil_bake.py bakes the mask for this many)
local DIR = ns.MEDIA .. "Pencil\\"
local RUN_IN = 2.5               -- seconds the colour takes
local STEPS = { "grey only", "grey + the added copies", "+ tooth, pressure, sheet edge", "+ paper", "+ hatching and squares (all of it)" }

-- where each piece is drawn: a pair of sublevels of its own (grey, then its added copies), in order
local SLOTS = {}
for _, layer in ipairs({ "BACKGROUND", "BORDER", "ARTWORK" }) do
    for sub = (layer == "BACKGROUND" and -6 or -8), 6, 2 do SLOTS[#SLOTS + 1] = { layer, sub } end
end

local mapFrame, host
local gainMask, darkMask, edgeMask
local zoneMask, zone             -- the zone's outline; zone: zoneMask while this map is cut to it
local pool, used = {}, 0
local sheets = {}
local laidFor
local lastKeys, lastMap
local runs = {}                  -- colour running in: { mask, t, size, key }

local REACH = 80                 -- yards: how near a square's middle you must come
local FADE = 1.0                 -- seconds a newly walked square takes to appear
local paintP = { tex = {}, n = 0, masks = {}, m = 0 }    -- the painted squares, and their blots
local backP = { tex = {}, n = 0, masks = {}, m = 0 }     -- the ground put back over what is not seen, and its blots
local paintFor
local backFor, backMap, backHide -- the ground put back: what it is laid for; the map and squares it covered last
local seenStamp = 0              -- goes up whenever a square is seen
local partOf = {}                -- [map] = { stamp, hide, show, n }: W.Unseen of what is seen (Part)
local leaving = {}               -- [square] = when it was seen: the ground over it fades off
local oldGround = {}             -- that ground's textures: { texture, born }
local walkStamp = 0              -- goes up whenever a square is marked
local born = {}                  -- [map .. ":" .. square] = when it was marked
local young = {}                 -- textures still fading in: { texture, born }
local rimCount = 0

local SKETCH_IN = 1.5            -- seconds a newly sighted area's sketch takes to appear
local sightStamp = 0             -- goes up whenever an area is sighted
local sightBorn = {}             -- [map .. ":" .. piece] = when it was sighted
local youngSketch = {}           -- its textures still fading in: { texture, born }
local sightCell                  -- where you last looked from
local Sighted, FadeTick, Sources, Part -- (further down)
local outlined = false           -- is this map's pencil kept to the zone's outline (the fill rules ask)
local tmasks, tmused = {}, 0     -- masks in the shape of a sighted area's tiles
local runningKeys                -- the areas whose colour is running in just now
-- where each sighted area is drawn: three sublevels of its own (grey; copies and lift; grain, hatch, squares)
local SIGHT_SLOTS = {}
for _, layer in ipairs({ "BACKGROUND", "BORDER", "ARTWORK" }) do
    for sub = (layer == "BACKGROUND" and -7 or -8), 5, 3 do SIGHT_SLOTS[#SIGHT_SLOTS + 1] = { layer, sub } end
end

-- is this map's pencil kept to sighted land?
local function SightOn(mapID)
    local c = Cfg()
    ns.PencilWalk.SIGHT.share = c.share or 0.2       -- (how much of an area you must have seen: /pencil share)
    return c.sight ~= false and not c.whole and ns.PencilCover and ns.PencilCover[mapID] and ns.PencilWalk.SightPieces and true or false
end

function ns.PencilOn(mapID)
    if not (mapFrame and Cfg().on) then return false end
    mapID = mapID or (mapFrame.GetMapID and mapFrame:GetMapID())
    -- (performance mode's "No map effects" rests it: a pencilled zone is several times the zone's own textures)
    if ns.Perf and ns.Perf("effects") then return false end
    -- (unexplored land drawn "As explored" leaves nothing to sketch: every area shows whole already, and a
    -- sketch would take the colour off land as you came near it. The sighted form rests then; the settings
    -- row greys. Idea hunt C's catch, 2026-11-14.)
    local c = Cfg()
    if c.sight ~= false and not c.bare and not c.whole and ns.IsShown and ns.IsShown("explore")
        and ns.db and ns.db.explore and ns.db.explore.fogStyle == "full" then return false end
    return (mapID and ns.PencilZones and ns.PencilZones[mapID] and ns.MapEdition() == "Forever") and true or false
end

-- a second mask beside a texture's own: the zone's outline, or none
local function Outline(t)
    if t.zMask ~= zone then
        if t.zMask then t:RemoveMaskTexture(t.zMask) end
        if zone then t:AddMaskTexture(zone) end
        t.zMask = zone
    end
end

local function Take(layer, sub, blend, desat, mask)
    used = used + 1
    local t = pool[used]
    if not t then
        t = host:CreateTexture()
        pool[used] = t
    end
    t:SetDrawLayer(layer, sub)
    t:SetBlendMode(blend)
    t:SetDesaturation(desat and 1 or 0)
    t:SetAlpha(1)
    if desat then t:SetVertexColor(tint[1], tint[2], tint[3]) else t:SetVertexColor(1, 1, 1) end
    if t.pMask ~= mask then
        if t.pMask then t:RemoveMaskTexture(t.pMask) end
        if mask then t:AddMaskTexture(mask) end
        t.pMask = mask
    end
    if t.dMask then          -- (a sighted area's hatching: where the zone is dark, beside its tile's shape)
        t:RemoveMaskTexture(t.dMask)
        t.dMask = nil
    end
    Outline(t)
    return t
end

-- Sighted land: an area's art, tile by tile ({ [piece] = { tile, ... } }, the tiles of Sources)
local tilesOf = {}
local function TilesOf(mapID)
    local t = tilesOf[mapID]
    if not t then
        t = {}
        for _, src in ipairs(Sources(mapID)) do
            if src.k > 0 then
                t[src.k] = t[src.k] or {}
                table.insert(t[src.k], src)
            end
        end
        tilesOf[mapID] = t
    end
    return t
end

-- a mask in the shape of one tile of an area's art (its own alpha), laid where the tile lies
local function TileMask(src, sx, sy)
    tmused = tmused + 1
    local m = tmasks[tmused]
    if not m then
        m = host:CreateMaskTexture()
        tmasks[tmused] = m
    end
    local file = ns.MapArtFile and ns.MapArtFile(src.fid) or src.fid
    if m.artFile ~= file then
        m:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m.artFile = file
    end
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", host, "TOPLEFT", src.x * sx, -src.y * sy)
    m:SetSize(src.fw * sx, src.fh * sy)
    m:Show()
    return m
end

-- one tile's share of one of our sheets (the sheets lie over the whole map), through that tile's mask
local function SheetTile(name, layer, sub, blend, mask, src, sx, sy, aw, ah)
    local t = Take(layer, sub, blend, false, mask)
    if t.SetSnapToPixelGrid then
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
    end
    local file = DIR .. name .. ".blp"
    if t.artFile ~= file then
        t:SetTexture(file, nil, nil, "LINEAR")
        t.artFile = file
    end
    t:SetTexCoord(src.x / aw, (src.x + src.w) / aw, src.y / ah, (src.y + src.h) / ah)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", host, "TOPLEFT", src.x * sx, -src.y * sy)
    t:SetSize(src.w * sx, src.h * sy)
    t:Show()
    return t
end

-- the zone's own picture: its base tiles, cut to the art's size
local function LayBase(mapID, sx, sy, get)
    local layer, files = ns.MapArtLayer(mapID)
    if not (layer and files) then return false end
    local lw, lh = layer.layerWidth, layer.layerHeight
    local cols = math.ceil(lw / 256)
    for i, fid in ipairs(files) do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        local pw, ph = math.min(256, lw - 256 * col), math.min(256, lh - 256 * row)
        if pw > 0 and ph > 0 then
            local t = get()
            if t.SetSnapToPixelGrid then
                t:SetSnapToPixelGrid(false)
                t:SetTexelSnappingBias(0)
            end
            local file = ns.MapArtFile and ns.MapArtFile(fid) or fid
            if t.artFile ~= file then
                t:SetTexture(file, nil, nil, "LINEAR")
                t.artFile = file
            end
            t:SetTexCoord(0, pw / 256, 0, ph / 256)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", host, "TOPLEFT", 256 * col * sx, -256 * row * sy)
            t:SetSize(pw * sx, ph * sy)
            t:Show()
        end
    end
    return true
end

local function Sheet(name, layer, sub, blend, mask, file)
    local t = sheets[name]
    if not t then
        t = host:CreateTexture(nil, layer, nil, sub)
        t:SetTexture(DIR .. (file or name) .. ".blp", nil, nil, "LINEAR")
        t:SetAllPoints(host)
        t:SetBlendMode(blend)
        sheets[name] = t
    end
    if t.pMask ~= mask then
        if t.pMask then t:RemoveMaskTexture(t.pMask) end
        if mask then t:AddMaskTexture(mask) end
        t.pMask = mask
    end
    Outline(t)
    return t
end

local function StopRuns()
    for _, r in ipairs(runs) do r.mask:Hide() end
    wipe(runs)
    if host then host:SetScript("OnUpdate", nil) end
end

local function Tick(_, dt)
    local busy = false
    for _, r in ipairs(runs) do
        if r.t < RUN_IN then
            r.t = r.t + dt
            local k = math.min(1, r.t / RUN_IN)
            k = 1 - (1 - k) * (1 - k)          -- quick at first, slowing as it soaks out
            r.mask:SetSize(math.max(1, r.size * k), math.max(1, r.size * k))
            busy = true
        end
    end
    if not busy then
        -- the colour is in: lay the map again without the blots
        StopRuns()
        laidFor = nil
        ns.PencilRefresh()
    end
end

local function Build(map, mapID, keys, fresh)
    used = 0
    StopRuns()
    local c = Cfg()
    local step = c.step or 5
    local canvas = map:GetCanvas()
    local aw, ah = ns.MapArtSize(mapID)
    local sx, sy = canvas:GetWidth() / aw, canvas:GetHeight() / ah
    local list = ns.ZoneOverlays(mapID) or {}

    if not gainMask then
        gainMask = host:CreateMaskTexture()
        gainMask:SetAllPoints(host)
        darkMask = host:CreateMaskTexture()
        darkMask:SetAllPoints(host)
    end
    if gainMask.pFile ~= mapID then
        gainMask:SetTexture(DIR .. mapID .. ".tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        darkMask:SetTexture(DIR .. mapID .. "d.blp", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        gainMask.pFile = mapID
    end

    local cut = c.outline ~= false and ns.CutFile and ns.CutFile(mapID) or nil
    if cut then
        if not zoneMask then
            zoneMask = host:CreateMaskTexture()
            zoneMask:SetAllPoints(host)
        end
        if zoneMask.pFile ~= cut then
            zoneMask:SetTexture(cut, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            zoneMask.pFile = cut
        end
    end
    -- Sighted land: only the areas you have sighted are sketched, each in its own shape (no outline cut:
    -- nothing of ours lies outside an area); the rest of the map is left as it is without the pencil
    -- (two styles, the user wants to see both: `islands`, the sketches lie on the map as it is; or c.bare,
    -- the whole sheet is the bare ground in pencil and the sketches are drawn onto it)
    local srec = SightOn(mapID) and Sighted(mapID, true) or nil
    local islands = srec and not c.bare
    -- (only the part seen: every area with a seen square is sketched, and LayBack covers the rest of it)
    local part = islands and c.part ~= false and Part(mapID) or nil
    local show = part and part.show or srec
    -- (islands: the outline plays no part at all, not in the paint's rules either. Seen 2026-11-14 with the
    -- paint still ending at the outline: a square outside it was left unpainted between hard-edged painted
    -- ones and showed the sketch under it as a dark block.)
    -- Then, the same day, in Elwynn: "it sketches parts of duskwood", and with the bare sheet "the parchment
    -- is back". An area's art runs past the zone's border as plain parchment; in colour nobody sees that, in
    -- pencil it greys the neighbour. So the sketches ARE cut to the outline (the mask), and only the paint's
    -- rules leave the outline out: soft rims everywhere, no border rule.
    zone = cut and zoneMask or nil
    outlined = (zone and not islands) and true or false
    -- The paper. It was one sheet multiplied in over everything, but a multiplied sheet cannot be cut to
    -- the outline: outside its mask it turns black and darkened the whole map there (seen 2026-11-13).
    -- So the paper's colour and tone go on the drawing's own textures, and its grain is a black sheet
    -- laid BLEND (alpha = how much darker), which is the same multiply and can be cut.
    local tone = c.tone or 0.65
    for i = 1, 3 do tint[i] = step >= 4 and PAPER[i] * tone or 1 end

    -- 1 and 2: the ground, then every piece over it, each grey and then added to itself. A piece's added
    -- copies must be drawn before the next piece is laid over them (pieces overlap a good deal; seen
    -- 2026-11-13: with all pieces on one level the overlaps were added twice and the lines went pale),
    -- so each piece takes the next two sublevels, up through three layers; past that, the order they
    -- were made in has to do.
    wipe(youngSketch)
    tmused = 0
    if islands then
        -- Sighted land (the user, 2026-11-14: "leaving the land not sighted as traditional unexplored, sighted
        -- gets sketching, and walked gets paint"). Three kinds of area:
        --   explored    nothing of ours: the game's own colours show (and the walked paint);
        --   sighted     its sketch, in its own shape: grey, the added copies and our lift (one sublevel, sums
        --               in any order), then grain, hatching and squares, each tile's share of our sheets laid
        --               through that tile's own alpha. Three sublevels an area, so the next area's grey covers
        --               all of the one under it where they overlap and nothing is laid twice;
        --   the rest    the unexplored look of the map's settings (Explore.lua's style and strength), or
        --               nothing at all when "Unexplored areas" is off there: the game's plain ground.
        for _, t in pairs(sheets) do t:Hide() end
        local e = ns.db and ns.db.explore
        local fog = e and ns.IsShown and ns.IsShown("explore") and ns.FOG_STYLES and (ns.FOG_STYLES[e.fogStyle] or ns.FOG_STYLES.fog) or nil
        local fogAlpha = e and (e.fogAlpha or 0.7) * (e.fogStyle == "faded" and 0.6 or 1) or 1
        local tiles = TilesOf(mapID)
        local now, drawn = GetTime(), 0
        for i, o in ipairs(list) do
            if keys[o.key] then
                -- explored
            elseif show[i] then
                drawn = drawn + 1
                local slot = SIGHT_SLOTS[math.min(drawn, #SIGHT_SLOTS)]
                local layer, sub = slot[1], slot[2]
                -- (part seen: nothing of a new area shows but under ground just uncovered, which fades off)
                local b = not part and sightBorn[mapID .. ":" .. i]
                if b and now - b >= SKETCH_IN then b = nil end
                local function Young(t)
                    if b then
                        t:SetAlpha((now - b) / SKETCH_IN)
                        youngSketch[#youngSketch + 1] = { t, b }
                    end
                    return t
                end
                ns.LayMapOverlay(o, host, sx, sy, function() return Young(Take(layer, sub, "BLEND", true)) end)
                if step >= 2 then
                    for _ = 1, COPIES do
                        ns.LayMapOverlay(o, host, sx, sy, function() return Young(Take(layer, sub + 1, "ADD", true, gainMask)) end)
                    end
                end
                if step >= 3 then
                    for _, src in ipairs(tiles[i] or {}) do
                        local m = TileMask(src, sx, sy)
                        Young(SheetTile("Lift", layer, sub + 1, "ADD", m, src, sx, sy, aw, ah)):SetVertexColor(tint[1], tint[2], tint[3])
                        if step >= 4 then Young(SheetTile("Grain", layer, sub + 2, "BLEND", m, src, sx, sy, aw, ah)) end
                        if step >= 5 then
                            -- (the hatching has three masks with the outline's: its tile, where the zone
                            -- is dark, the outline. Should the client refuse a third, it goes without
                            -- hatching past two rather than stop the map being laid.)
                            local h = Young(SheetTile("Hatch", layer, sub + 2, "BLEND", m, src, sx, sy, aw, ah))
                            if pcall(h.AddMaskTexture, h, darkMask) then h.dMask = darkMask else h:Hide() end
                            Young(SheetTile("Squares", layer, sub + 2, "BLEND", m, src, sx, sy, aw, ah))
                        end
                    end
                end
            elseif fog then
                ns.LayMapOverlay(o, host, sx, sy, function()
                    -- (part seen: over the ground LayBack puts back, which lies on every square not seen)
                    local t = Take(part and "OVERLAY" or "BACKGROUND", -8, "BLEND", false)
                    -- (not cut to the outline: this is the map's own unexplored look, as Explore.lua lays it)
                    if t.zMask then
                        t:RemoveMaskTexture(t.zMask)
                        t.zMask = nil
                    end
                    t:SetDesaturation(fog.desat)
                    t:SetVertexColor(fog.tint[1], fog.tint[2], fog.tint[3])
                    t:SetAlpha(fogAlpha)
                    return t
                end)
            end
        end
    else

    LayBase(mapID, sx, sy, function() return Take("BACKGROUND", -8, "BLEND", true) end)
    if step >= 2 then
        for _ = 1, COPIES do
            LayBase(mapID, sx, sy, function() return Take("BACKGROUND", -7, "ADD", true, gainMask) end)
        end
    end
    -- (Sighted land on the bare sheet: an area's sketch only once it is sighted, or explored; it fades in)
    local now = GetTime()
    for i, o in ipairs(list) do
        if not srec or srec[i] or keys[o.key] then
            local slot = math.min(i, #SLOTS)
            local layer, sub = SLOTS[slot][1], SLOTS[slot][2]
            local b = srec and sightBorn[mapID .. ":" .. i]
            if b and now - b >= SKETCH_IN then b = nil end
            local function Sketch(sublevel, blend, mask)
                local t = Take(layer, sublevel, blend, true, mask)
                if b then
                    t:SetAlpha((now - b) / SKETCH_IN)
                    youngSketch[#youngSketch + 1] = { t, b }
                end
                return t
            end
            ns.LayMapOverlay(o, host, sx, sy, function() return Sketch(sub, "BLEND") end)
            if step >= 2 then
                for _ = 1, COPIES do
                    ns.LayMapOverlay(o, host, sx, sy, function() return Sketch(sub + 1, "ADD", gainMask) end)
                end
            end
        end
    end

    -- 3 to 5: our own sheets
    -- Seen in game 2026-11-13, over three looks: the client does NOT clamp at white between layers. The
    -- added copies run past white on the painter's highlights, and the sheet's edge, when it was added as
    -- white, came out twice as bright as the paper under any strength of the paper step. (MOD is the
    -- plain product: the "twice the product" reading of the second look was this.) So nothing bright is
    -- added any more: the edge is the paper itself laid over the drawing through Edge.blp. The
    -- highlights past white stay: they read as chalk on toned paper.
    -- The paper's tone is the user's to set (/pencil tone): they liked it well under full strength.
    local lift = Sheet("Lift", "OVERLAY", -8, "ADD")
    lift:SetVertexColor(tint[1], tint[2], tint[3])
    lift:SetShown(step >= 3)
    Sheet("Grain", "OVERLAY", -7, "BLEND"):SetShown(step >= 4)
    if not edgeMask then
        edgeMask = host:CreateMaskTexture()
        edgeMask:SetAllPoints(host)
        edgeMask:SetTexture(DIR .. "Edge.blp", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    local edge = Sheet("PaperEdge", "OVERLAY", -6, "BLEND", edgeMask, "Paper")
    edge:SetVertexColor(tone, tone, tone)
    edge:SetShown(step >= 4)
    Sheet("Hatch", "OVERLAY", -5, "BLEND", darkMask):SetShown(step >= 5)
    Sheet("Squares", "OVERLAY", -4, "BLEND"):SetShown(step >= 5)

    end   -- (the whole sheet in pencil)
    for i = tmused + 1, #tmasks do tmasks[i]:Hide() end

    -- what you've explored, painted; a piece found just now has its colour run in from where you stand
    -- (with "colour where you walk" the painting is PaintWalked's)
    if not c.whole and not c.walk then
        local px, py
        if fresh and next(fresh) then
            local pos = C_Map.GetPlayerMapPosition(mapID, "player")
            if pos then px, py = pos:GetXY() end
        end
        for _, o in ipairs(list) do
            if keys[o.key] then
                local mask
                if px and fresh[o.key] then
                    mask = host:CreateMaskTexture()
                    mask:SetTexture(DIR .. "Blot.blp", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                    mask:SetPoint("CENTER", host, "TOPLEFT", px * canvas:GetWidth(), -py * canvas:GetHeight())
                    mask:SetSize(1, 1)
                    -- far enough to cover the piece from wherever in it you stand
                    runs[#runs + 1] = { mask = mask, t = 0, size = 2 * 1.4 * math.sqrt((o.w * sx) ^ 2 + (o.h * sy) ^ 2) }
                end
                ns.LayMapOverlay(o, host, sx, sy, function() return Take("OVERLAY", 0, "BLEND", false, mask) end)
            end
        end
    end

    for i = used + 1, #pool do pool[i]:Hide() end
    runningKeys = runs[1] and fresh or nil
    -- (StopRuns above took the script away: whatever was still fading goes on)
    if runs[1] then host:SetScript("OnUpdate", Tick)
    elseif youngSketch[1] or young[1] or oldGround[1] then host:SetScript("OnUpdate", FadeTick) end
end

-- Colour where you walk ----------------------------------------------------------------------------------

-- every area the game calls explored counts as walked, all of its box: mountains and shore you cannot
-- stand on fill in with the area's name (the user, 2026-11-13: "give exploration of an area credit to fill too")
local seedFor
-- What the game calls explored on a map, less what /pencil blank set aside: a test from an empty sheet in a zone
-- the character has already been through (the user, 2026-11-15: after /pencil forget "Still showing large parts
-- of elwyn"; forget takes the game's explored areas over again, by design). Areas found after it count as ever.
local function Explored(mapID)
    local keys = ns.ExploredOverlayKeys(mapID)
    local base = WaymarkCharDB and WaymarkCharDB.pencilBlank and WaymarkCharDB.pencilBlank[mapID]
    if not (base and keys) then return keys end
    local out = {}
    for k, v in pairs(keys) do
        if v and not base[k] then out[k] = v end
    end
    return out
end
local function SeedExplored(rec, mapID, keys)
    -- by what each area really paints, where that is baked: the game's own fill, and no gaps
    local cover = ns.PencilCover and ns.PencilCover[mapID]
    if cover then
        local found = {}
        for i, o in ipairs(ns.ZoneOverlays(mapID) or {}) do
            if keys[o.key] then found[i] = true end
        end
        ns.PencilWalk.SeedCover(rec, cover, found)
        return
    end
    local boxes, all = {}, {}
    for _, o in ipairs(ns.ZoneOverlays(mapID) or {}) do
        if keys[o.key] then boxes[#boxes + 1] = { o.left, o.top, o.right, o.bottom } end
        all[#all + 1] = { o.left, o.top, o.right, o.bottom, on = keys[o.key] and true or false }
    end
    local aw, ah = ns.MapArtSize(mapID)
    ns.PencilWalk.Seed(rec, boxes, aw, ah)
    -- and the ground no area covers goes with the nearest area
    ns.PencilWalk.SeedNear(rec, all, aw, ah)
end

local function Record(mapID, make)
    if not WaymarkCharDB then
        if not make then return end
        WaymarkCharDB = {}
    end
    local all = WaymarkCharDB.pencilWalk
    if not all then
        if not make then return end
        all = {}
        WaymarkCharDB.pencilWalk = all
        WaymarkCharDB.pencilWalkClean = 1
    end
    if WaymarkCharDB.pencilWalkClean ~= 1 then
        -- once: the border squares the old border rule crept into the saved ground (W.DropBorder)
        for id, r in pairs(all) do
            local cover = ns.PencilCover and ns.PencilCover[id]
            if cover then ns.PencilWalk.DropBorder(r, cover) end
        end
        WaymarkCharDB.pencilWalkClean = 1
        seedFor = nil
    end
    local rec = all[mapID]
    if not rec and make then
        rec = {}
        all[mapID] = rec
        -- what the game already calls explored here is yours: taken over once
        SeedExplored(rec, mapID, Explored(mapID))
    end
    return rec
end

-- how many yards the zone's map is across and down (the client's own box of it)
local yards = {}
local function Yards(mapID)
    local y = yards[mapID]
    if y then return y[1], y[2] end
    local w, h = 4000, 2667
    if C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local ok, _, tl = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0, 0))
        local ok2, _, br = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(1, 1))
        if ok and ok2 and tl and br then
            local a, b = math.abs(tl.y - br.y), math.abs(tl.x - br.x)
            if a > 100 and b > 100 then w, h = a, b end
        end
    end
    yards[mapID] = { w, h }
    return w, h
end

-- the zone's painted art as tiles in art pixels: the base, then each piece in the order they lie
local sourcesOf = {}
function Sources(mapID)
    if sourcesOf[mapID] then return sourcesOf[mapID] end
    local out = {}
    local layer, files = ns.MapArtLayer(mapID)
    if layer and files then
        local lw, lh = layer.layerWidth, layer.layerHeight
        local cols = math.ceil(lw / 256)
        for i, fid in ipairs(files) do
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            local pw, ph = math.min(256, lw - 256 * col), math.min(256, lh - 256 * row)
            if pw > 0 and ph > 0 then
                out[#out + 1] = { x = 256 * col, y = 256 * row, w = pw, h = ph, fw = 256, fh = 256, fid = fid, k = 0 }
            end
        end
    end
    local function Pow2(n)
        local p = 16
        while p < n do p = p * 2 end
        return p
    end
    for k, o in ipairs(ns.ZoneOverlays(mapID) or {}) do
        local across, down = math.ceil(o.w / 256), math.ceil(o.h / 256)
        for row = 1, down do
            local ph = row < down and 256 or (o.h - 256 * (down - 1))
            for col = 1, across do
                local fid = o.files[(row - 1) * across + col]
                if fid then
                    local pw = col < across and 256 or (o.w - 256 * (across - 1))
                    out[#out + 1] = { x = o.x + 256 * (col - 1), y = o.y + 256 * (row - 1), w = pw, h = ph,
                                      fw = col < across and 256 or Pow2(pw), fh = row < down and 256 or Pow2(ph), fid = fid, k = k }
                end
            end
        end
    end
    sourcesOf[mapID] = out
    return out
end

-- Sighted land: the areas this character has sighted on a map, { [piece's place in the zone's list] = true }.
-- Made the first time from the ground already walked: what lies near it has been seen.
-- Everything this character has seen on a map, square by square ({ [index] = true }, added to at every look
-- round): an area is sighted once a good part of it is in here (W.SightPieces).
local function SeenRec(mapID)
    WaymarkCharDB = WaymarkCharDB or {}
    WaymarkCharDB.pencilSeen = WaymarkCharDB.pencilSeen or {}
    local s = WaymarkCharDB.pencilSeen[mapID]
    if not s then
        s = {}
        WaymarkCharDB.pencilSeen[mapID] = s
    end
    return s
end

function Sighted(mapID, make)
    if not WaymarkCharDB then
        if not make then return end
        WaymarkCharDB = {}
    end
    -- once: what the first rule sighted (six squares of an area were enough) is forgotten, every zone starts
    -- again from its walked ground under the rule of 2026-11-14
    if WaymarkCharDB.pencilSightV ~= 2 then
        WaymarkCharDB.pencilSight, WaymarkCharDB.pencilSeen, WaymarkCharDB.pencilSightV = nil, nil, 2
    end
    local all = WaymarkCharDB.pencilSight
    if not all then
        if not make then return end
        all = {}
        WaymarkCharDB.pencilSight = all
    end
    local rec = all[mapID]
    if not rec and make then
        rec = {}
        all[mapID] = rec
        local cover = ns.PencilCover and ns.PencilCover[mapID]
        if cover then
            local W = ns.PencilWalk
            local w, h = Yards(mapID)
            local seen = SeenRec(mapID)
            for i in pairs(W.Near(Record(mapID, true), W.SIGHT.near / (w / W.GW), W.SIGHT.near / (h / W.GH), cover)) do seen[i] = true end
            for _, k in ipairs(W.SightPieces(cover, seen, rec) or {}) do rec[k] = true end
        end
    end
    return rec
end

function FadeTick()
    local now, busy = GetTime(), false
    for _, y in ipairs(young) do
        local a = (now - y[2]) / FADE
        if a < 1 then busy = true else a = 1 end
        y[1]:SetAlpha(a)
    end
    for _, y in ipairs(youngSketch) do
        local a = (now - y[2]) / SKETCH_IN
        if a < 1 then busy = true else a = 1 end
        y[1]:SetAlpha(a)
    end
    for _, y in ipairs(oldGround) do
        local a = 1 - (now - y[2]) / FADE
        if a > 0 then busy = true else a = 0 end
        y[1]:SetAlpha(a)
    end
    if not busy then
        wipe(young)
        wipe(youngSketch)
        wipe(oldGround)
        host:SetScript("OnUpdate", nil)
    end
end

-- The areas with anything seen, and the squares to put back (W.Unseen), worked out again only when a square
-- is seen. n: how many areas, which is what the sketches are laid again for.
function Part(mapID)
    local p = partOf[mapID]
    if p and p.stamp == seenStamp then return p end
    Sighted(mapID, true)         -- (the first time: what lies near the ground already walked has been seen)
    local hide, show = ns.PencilWalk.Unseen(ns.PencilCover[mapID], SeenRec(mapID))
    local n = 0
    for _ in pairs(show) do n = n + 1 end
    p = { stamp = seenStamp, hide = hide, show = show, n = n }
    partOf[mapID] = p
    return p
end

-- One quad of the zone's art (W.Quads), through its soft blot if it is a rim square's: the walked paint, and
-- the ground put back. P: its textures and blots; masks: the blots of this laying, by square.
local function LayQuad(P, q, sx, sy, bw, bh, masks)
    local mask
    if q.cell then
        mask = masks[q.cell]
        if not mask then
            P.m = P.m + 1
            mask = P.masks[P.m]
            if not mask then
                mask = host:CreateMaskTexture()
                mask:SetTexture(DIR .. "Soft.blp", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                P.masks[P.m] = mask
            end
            mask:ClearAllPoints()
            mask:SetPoint("CENTER", host, "TOPLEFT", q.cx * sx, -q.cy * sy)
            -- (a little larger than the painted square: the soft blot is gone at six sevenths of the
            -- way out, before the painted square's own edge, so no straight edge ever shows. Seen
            -- 2026-11-13 with the hard blot at this size: the rim read as blocks.)
            mask:SetSize(bw * 1.1, bh * 1.1)
            mask:Show()
            masks[q.cell] = mask
        end
    end
    P.n = P.n + 1
    local t = P.tex[P.n]
    if not t then
        t = host:CreateTexture()
        P.tex[P.n] = t
        if t.SetSnapToPixelGrid then
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
        end
    end
    local src = q.src
    local file = ns.MapArtFile and ns.MapArtFile(src.fid) or src.fid
    if t.artFile ~= file then
        t:SetTexture(file, nil, nil, "LINEAR")
        t.artFile = file
    end
    if t.pMask ~= mask then
        if t.pMask then t:RemoveMaskTexture(t.pMask) end
        if mask then t:AddMaskTexture(mask) end
        t.pMask = mask
    end
    -- (it ends on the zone's outline as the pencil does, not on the squares' straight edges)
    Outline(t)
    t:SetTexCoord((q.l - src.x) / src.fw, (q.r - src.x) / src.fw, (q.t - src.y) / src.fh, (q.b - src.y) / src.fh)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", host, "TOPLEFT", q.l * sx, -q.t * sy)
    t:SetSize((q.r - q.l) * sx, (q.b - q.t) * sy)
    t:SetAlpha(1)
    t:Show()
    return t
end

local function EndQuads(P)
    for i = P.n + 1, #P.tex do P.tex[i]:Hide() end
    for i = P.m + 1, #P.masks do P.masks[i]:Hide() end
end

local function HidePaint()
    paintP.n, paintP.m, paintFor = 0, 0, nil
    EndQuads(paintP)
    wipe(young)
end

local function HideBack()
    backP.n, backP.m, backFor = 0, 0, nil
    EndQuads(backP)
    wipe(oldGround)
end

-- Only the part seen: the game's own ground, laid back over every square of the zone you have not seen. It lies
-- over the sketches and under the walked colour. Where nothing is sketched it is the map's ground on itself.
local baseOf = {}
local function LayBack(map, mapID)
    backP.n, backP.m = 0, 0
    wipe(oldGround)
    local p = Part(mapID)
    local W = ns.PencilWalk
    local now = GetTime()
    -- squares seen since the last look at this same map: the ground over them fades off (also what you saw with
    -- the map shut, when you open it again). Not after a switch was thrown (backMap is cleared then), and not
    -- when it is a great deal at once, a flight's worth: that would be hundreds of textures for the one second.
    if backMap ~= mapID then
        wipe(leaving)
    elseif backHide and backHide ~= p.hide then
        local gone = {}
        for i in pairs(backHide) do
            if not p.hide[i] then gone[#gone + 1] = i end
        end
        if #gone <= 300 then
            for _, i in ipairs(gone) do leaving[i] = now end
        end
    end
    backMap, backHide = mapID, p.hide
    if p.n > 0 then
        local base = baseOf[mapID]
        if not base then
            base = {}
            for _, src in ipairs(Sources(mapID)) do
                if src.k == 0 then base[#base + 1] = src end
            end
            baseOf[mapID] = base
        end
        local canvas = map:GetCanvas()
        local aw, ah = ns.MapArtSize(mapID)
        local sx, sy = canvas:GetWidth() / aw, canvas:GetHeight() / ah
        local bw, bh = aw / W.GW * W.BLOT * sx, ah / W.GH * W.BLOT * sy
        local masks = {}
        for _, q in ipairs((W.Quads(base, W.States(p.hide, ns.PencilCover[mapID]), aw, ah))) do
            LayQuad(backP, q, sx, sy, bw, bh, masks):SetDrawLayer("ARTWORK", 7)
        end
        local ghost
        for i, b in pairs(leaving) do
            if now - b < FADE then
                ghost = ghost or {}
                ghost[i] = 1
            else
                leaving[i] = nil
            end
        end
        if ghost then
            masks = {}
            for _, q in ipairs((W.Quads(base, ghost, aw, ah))) do
                local t = LayQuad(backP, q, sx, sy, bw, bh, masks)
                t:SetDrawLayer("ARTWORK", 7)
                local b = leaving[q.cell]
                t:SetAlpha(1 - (now - b) / FADE)
                oldGround[#oldGround + 1] = { t, b }
            end
        end
    end
    EndQuads(backP)
    if oldGround[1] and not runs[1] then host:SetScript("OnUpdate", FadeTick) end
end

-- With "colour where you walk" off, whole areas are painted as the game calls them explored. The same
-- squares then say what else fills with them: the ground no area paints, and the zone's border (the user,
-- 2026-11-14, with it unticked: "line is visible"). An area whose colour is still running in is left out
-- until it is in.
local function FoundRecord(mapID, keys)
    local cover = ns.PencilCover and ns.PencilCover[mapID]
    if not cover then return nil end
    local found = {}
    for i, o in ipairs(ns.ZoneOverlays(mapID) or {}) do
        if keys[o.key] and not (runningKeys and runningKeys[o.key]) then found[i] = true end
    end
    local rec = {}
    ns.PencilWalk.SeedCover(rec, cover, found)
    return rec
end

local function PaintWalked(map, mapID, found)
    paintP.n, paintP.m = 0, 0
    wipe(young)
    local rec = found or Record(mapID, true)
    local canvas = map:GetCanvas()
    local aw, ah = ns.MapArtSize(mapID)
    local sx, sy = canvas:GetWidth() / aw, canvas:GetHeight() / ah
    -- (cut to the zone's outline: the border fills beside walked ground, and the outside is no rim)
    local cover = outlined and ns.PencilCover and ns.PencilCover[mapID] or nil
    if cover then
        -- (on a copy: the saved ground stays what you walked. Run on the record itself, every repaint took
        -- the colour two squares farther along the border; seen 2026-11-14, the zone filled by clicking.)
        local shown = {}
        for i in pairs(rec) do shown[i] = true end
        ns.PencilWalk.SeedBorder(shown, cover)
        rec = shown
    end
    local quads, rim = ns.PencilWalk.Quads(Sources(mapID), ns.PencilWalk.States(rec, cover), aw, ah)
    rimCount = rim
    local blot = ns.PencilWalk.BLOT
    local bw, bh = aw / ns.PencilWalk.GW * blot * sx, ah / ns.PencilWalk.GH * blot * sy
    local masks, now = {}, GetTime()
    for _, q in ipairs(quads) do
        local t = LayQuad(paintP, q, sx, sy, bw, bh, masks)
        t:SetDrawLayer("OVERLAY", math.min(q.src.k, 7))
        local b = q.cell and born[mapID .. ":" .. q.cell]
        if b and now - b < FADE then
            t:SetAlpha((now - b) / FADE)
            young[#young + 1] = { t, b }
        end
    end
    EndQuads(paintP)
    if young[1] and not runs[1] then host:SetScript("OnUpdate", FadeTick) end
end

-- where you stand, twice a second: mark the ground, look round, and draw it if its map is up
local function Walk()
    local c = Cfg()
    if not (mapFrame and c.on) then return end
    if ns.Perf and ns.Perf("effects") then return end
    local taxi = UnitOnTaxi and UnitOnTaxi("player") and true or false
    local mapID = C_Map.GetBestMapForUnit("player")
    if not (mapID and ns.PencilZones and ns.PencilZones[mapID] and ns.MapEdition() == "Forever") then return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end
    local u, v = pos:GetXY()
    local w, h = Yards(mapID)
    local W = ns.PencilWalk
    local changed = false
    local new = c.walk and not taxi and W.Mark(Record(mapID, true), u, v, REACH / w, REACH / h)
    if new then
        local now = GetTime()
        for _, i in ipairs(new) do born[mapID .. ":" .. i] = now end
        walkStamp = walkStamp + 1
        changed = true
    end
    -- Sighted land: a look round from each new cell of the ground you step into (not every half second)
    if SightOn(mapID) and u and v and u >= 0 and u <= 1 and v >= 0 and v <= 1 then
        local cell = mapID .. ":" .. math.floor(u * W.FW) .. ":" .. math.floor(v * W.FH) .. (taxi and "t" or "")
        if cell ~= sightCell then
            sightCell = cell
            local srec = Sighted(mapID, true)
            -- what is in view from here joins everything seen before; an area is sighted on the whole of it
            local now = W.Sight(ns.PencilHeights and ns.PencilHeights[mapID], u, v, w, h, taxi and W.SIGHT.saddle or nil)
            local seen, grew = SeenRec(mapID), false
            for i in pairs(now or {}) do
                if not seen[i] then
                    seen[i] = true
                    grew = true
                end
            end
            if grew then
                -- (only the part seen: the ground put back is laid again, and the sketches if an area is new)
                seenStamp = seenStamp + 1
                if c.part ~= false and not c.bare then changed = true end
            end
            local found = grew and W.SightPieces(ns.PencilCover[mapID], seen, srec)
            if found then
                local now = GetTime()
                for _, k in ipairs(found) do
                    srec[k] = true
                    sightBorn[mapID .. ":" .. k] = now
                end
                sightStamp = sightStamp + 1
                changed = true
            end
        end
    end
    if changed and mapFrame:IsShown() and mapFrame:GetMapID() == mapID then ns.PencilRefresh() end
end

-- Has this spot been walked (x, y: 0..1 on the map)? True wherever the pencil hides nothing: off, the
-- whole-areas way, a map without pencil. For marks that should appear only on painted ground (Landmarks).
function ns.PencilWalked(mapID, x, y)
    local c = Cfg()
    if not (c.on and c.walk and not c.whole and ns.PencilOn(mapID)) then return true end
    local rec = Record(mapID, true)
    if not (x and y) or x < 0 or x > 1 or y < 0 or y > 1 then return false end
    local W = ns.PencilWalk
    return rec[W.Index(math.min(W.GW - 1, math.floor(x * W.GW)), math.min(W.GH - 1, math.floor(y * W.GH)))] and true or false
end

-- The one switch players get: "Pencil in land I've seen" on The map's look and on Exploration (Options.lua,
-- PencilRow, which makes the row only while this function is there: so none on Classic Era). Asked with no
-- value, told with one, as ns.ReliefSetting. Everything else is fixed for players at the form the user
-- cleared for 1.3 on 2026-11-14: sighted land sketched, the rest the map's normal unexplored land, colour
-- where you walk; the other switches stay on the test bench.
if ns.FOREVER then
    local FIXED = { whole = false, walk = true, outline = true, sight = true, bare = false, part = true }
    function ns.PencilSetting(key, v)
        local c = Cfg()
        if v == nil then return c[key] end
        if key ~= "on" then return end
        c.on = v and true or false
        c.step = nil
        laidFor, paintFor, backFor = nil, nil, nil
        ns.PencilRefresh()
    end
    -- (Reset this page on The map's look, a preset, a saved setup: the row is a plain setting now, pencil.on, and
    -- the hook on ns.OnSettingChanged further down draws it again. Reset this page also puts back the form the one
    -- switch stands for, which only the test bench can change: Options.lua's ns.PageResets.)
    ns.PageResets = ns.PageResets or {}
    local before = ns.PageResets.look
    ns.PageResets.look = function()
        if before then before() end
        local c = Cfg()
        c.step = nil
        for k, v in pairs(FIXED) do c[k] = v end
        laidFor, paintFor, backFor = nil, nil, nil
        ns.PencilRefresh()
    end
end

function ns.PencilRefresh(force)
    local map = mapFrame
    if not (map and host) then return end
    local mapID = map:GetMapID()
    if not (map:IsShown() and ns.PencilOn(mapID)) then
        if host:IsShown() then
            host:Hide()
            StopRuns()
            HidePaint()
            HideBack()
            laidFor = nil
            if ns.UpdateExplore then ns.UpdateExplore(true) end
        end
        return
    end
    -- the fog's level (the fog steps aside for the pencil): under the close-up tiles and the relief's
    -- shading, which sit on "ground" and "wash". Seen 2026-11-13 on "ground": it covered both.
    -- "The whole map in pencil" goes one level up, to "ground": on "fog" it shares a level with the game's own
    -- explored art, which then drew over it, so explored areas stayed in colour (seen 2026-11-14). The price,
    -- taken at the user's word ("Yeah"): up there it also covers the close-up detail and the relief's print.
    local level = ns.ArtLevel(map, Cfg().whole and "ground" or "fog")
    if host:GetFrameLevel() ~= level then host:SetFrameLevel(level) end
    host:SetAlpha(map.GetGlobalAlpha and map:GetGlobalAlpha() or map.globalAlpha or 1)

    local keys = Explored(mapID)
    local n = 0
    for _ in pairs(keys) do n = n + 1 end
    local c = Cfg()
    local canvas = map:GetCanvas()
    local wide = math.floor(canvas:GetWidth() + 0.5)
    -- (only the part seen: the sketches are laid again when an area is new, not at every square seen)
    local part = SightOn(mapID) and not c.bare and c.part ~= false
    local want = mapID .. "|" .. (c.walk and "w" or n) .. "|" .. wide .. "|" .. tostring(c.step) .. "|" .. tostring(c.whole)
        .. "|" .. (SightOn(mapID) and (part and "p" .. Part(mapID).n or sightStamp) or "-") .. "|" .. tostring(c.bare)
    if SightOn(mapID) then
        -- (the unexplored look round the sketches is the map's own setting: laid again when it changes)
        local e = ns.db and ns.db.explore
        want = want .. "|" .. tostring(ns.IsShown and ns.IsShown("explore")) .. tostring(e and e.fogStyle) .. tostring(e and e.fogAlpha)
    end
    if force or laidFor ~= want then
        -- found since the last look at this same map: those run in
        local fresh
        if lastMap == mapID and lastKeys and not force then
            fresh = {}
            for k in pairs(keys) do
                if not lastKeys[k] then fresh[k] = true end
            end
        end
        lastMap, lastKeys = mapID, keys
        local wasShown = host:IsShown()
        host:Show()
        ns.Safe("Pencil Build", Build, map, mapID, keys, fresh)
        laidFor = want
        if not wasShown and ns.UpdateExplore then ns.UpdateExplore(true) end   -- (the fog steps aside)
    end
    -- the painted ground you've walked: its own layout, laid again when a square is marked
    if c.walk and not c.whole then
        if seedFor ~= mapID .. "|" .. n then
            seedFor = mapID .. "|" .. n
            SeedExplored(Record(mapID, true), mapID, keys)
            walkStamp = walkStamp + 1
        end
        local wantPaint = mapID .. "|" .. walkStamp .. "|" .. wide
        if force or paintFor ~= wantPaint then
            ns.Safe("Pencil PaintWalked", PaintWalked, map, mapID)
            paintFor = wantPaint
        end
    elseif not c.whole and ns.PencilCover and ns.PencilCover[mapID] then
        local wantPaint = mapID .. "|found" .. n .. "|" .. wide .. "|" .. (runningKeys and "running" or "")
        if force or paintFor ~= wantPaint then
            ns.Safe("Pencil PaintFound", PaintWalked, map, mapID, FoundRecord(mapID, keys))
            paintFor = wantPaint
        end
    elseif paintFor or paintP.n > 0 then
        HidePaint()
    end
    -- the ground put back over what is not seen: its own layout too, laid again when a square is seen
    if part then
        local wantBack = mapID .. "|" .. seenStamp .. "|" .. wide
        if force or backFor ~= wantBack then
            ns.Safe("Pencil LayBack", LayBack, map, mapID)
            backFor = wantBack
        end
    elseif backFor or backP.n > 0 then
        HideBack()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("MAP_EXPLORATION_UPDATED")
events:SetScript("OnEvent", function(_, event)
    if event == "MAP_EXPLORATION_UPDATED" then
        if mapFrame then C_Timer.After(0.1, function() ns.PencilRefresh() end) end
        return
    end
    C_Timer.After(3, function()
        local map = BattlefieldMapFrame
        if not map or mapFrame then return end
        mapFrame = map
        local canvas = map:GetCanvas()
        host = CreateFrame("Frame", nil, canvas)
        host:SetAllPoints(canvas)
        host.bfiOwn = true       -- (map art of ours: clear view cuts it to the zone)
        host:Hide()
        map:HookScript("OnShow", function() ns.PencilRefresh() end)
        if map.OnMapChanged then
            hooksecurefunc(map, "OnMapChanged", function() C_Timer.After(0, function() ns.PencilRefresh() end) end)
        end
        canvas:HookScript("OnSizeChanged", function() ns.PencilRefresh() end)
        C_Timer.NewTicker(0.5, function() ns.Safe("Pencil Walk", Walk) end)
        -- performance mode switched: the pencil rests or comes back at once (the fog with it)
        if ns.OnSettingChanged then
            hooksecurefunc(ns, "OnSettingChanged", function(group)
                if group == "pencil" then          -- (its own switch, from the settings, a preset or a reset)
                    Cfg().step = nil
                    laidFor, paintFor, backFor, backMap = nil, nil, nil, nil
                end
                if group == "pencil" or group == "perf" or group == "explore" then ns.PencilRefresh() end
                -- (the map's opacity, its own or clear view's: the pencil's sheets take it in PencilRefresh,
                -- which nothing called when the slider moved, so the sketched and the painted land stayed at
                -- full strength while the rest of the map faded. The user's two screenshots, 2026-11-15.)
                if (group == "mapFrame" or group == "clearView") and host and host:IsShown() and mapFrame then
                    local map = mapFrame
                    host:SetAlpha(map.GetGlobalAlpha and map:GetGlobalAlpha() or map.globalAlpha or 1)
                end
            end)
        end
        ns.PencilRefresh()
    end)
end)

SLASH_WAYMARKPENCIL1 = "/pencil"
SlashCmdList.WAYMARKPENCIL = function(msg)
    local c = Cfg()
    local word = (msg or ""):lower():match("^%s*(%a*)")
    local say
    local STYLE = { whole = true, outline = true, sight = true, share = true, bare = true, walk = true, part = true }
    if STYLE[word] and not ns.PencilAllStyles then
        print("|cffc79a52Waymark|r: The pencil has one style in 1.3. \"" .. word .. "\" is gone.")
        return
    end
    if word == "whole" then
        c.whole = not c.whole
        say = c.whole and "The whole map is in pencil." or "Walked land is painted again."
    elseif word == "step" then
        c.on = true
        c.step = (c.step or 0) % #STEPS + 1
        say = "test step " .. c.step .. " of " .. #STEPS .. ": " .. STEPS[c.step] .. "."
        if c.step == #STEPS then c.step = nil end
    elseif word == "tone" then
        local n = tonumber((msg or ""):match("(%d+)"))
        if n then c.tone = math.max(30, math.min(100, n)) / 100 end
        say = "The paper's tone is " .. math.floor((c.tone or 0.65) * 100 + 0.5) .. " (30 dark to 100 bright; /pencil tone 65)."
    elseif word == "outline" then
        c.outline = c.outline == false
        say = c.outline and "The pencil keeps inside the zone's outline." or "The pencil covers the whole sheet."
    elseif word == "sight" then
        c.sight = c.sight == false
        say = c.sight and "Only land you've seen is sketched. The rest stays blank." or "The whole zone is sketched."
    elseif word == "share" then
        local n = tonumber((msg or ""):match("(%d+)"))
        if n then
            c.share = math.max(5, math.min(50, n)) / 100
            -- (what you have seen is kept square by square: every zone is judged again from it)
            if WaymarkCharDB then WaymarkCharDB.pencilSight = nil end
            sightStamp = sightStamp + 1
        end
        say = "An area is sketched once you've seen " .. math.floor((c.share or 0.2) * 100 + 0.5) .. "% of it (5 to 50; /pencil share 20)."
    elseif word == "part" then
        c.part = c.part == false
        say = c.part and "Only the part of an area you've seen is sketched." or "A whole area is sketched once you've seen "
            .. math.floor((c.share or 0.2) * 100 + 0.5) .. "% of it (/pencil share)."
    elseif word == "bare" then
        c.bare = not c.bare
        say = c.bare and "Land you haven't seen is blank ground in pencil." or "Land you haven't seen stays the map's normal unexplored land."
    elseif word == "walk" then
        c.walk = not c.walk
        say = c.walk and "Colour follows where you walk." or "Whole areas are painted as the game calls them explored."
    elseif word == "forget" or word == "blank" then
        local mapID = mapFrame and mapFrame:GetMapID()
        if mapID and WaymarkCharDB then
            -- (blank: what the game calls explored here now is set aside too; forget alone takes it over again)
            WaymarkCharDB.pencilBlank = WaymarkCharDB.pencilBlank or {}
            local base
            if word == "blank" then
                base = {}
                for k, v in pairs(ns.ExploredOverlayKeys(mapID) or {}) do if v then base[k] = true end end
            end
            WaymarkCharDB.pencilBlank[mapID] = base
        end
        if mapID and WaymarkCharDB and WaymarkCharDB.pencilWalk then WaymarkCharDB.pencilWalk[mapID] = nil end
        if mapID and WaymarkCharDB and WaymarkCharDB.pencilSight then WaymarkCharDB.pencilSight[mapID] = nil end
        if mapID and WaymarkCharDB and WaymarkCharDB.pencilSeen then WaymarkCharDB.pencilSeen[mapID] = nil end
        sightCell = nil
        walkStamp = walkStamp + 1
        seedFor = nil
        say = word == "blank" and "This zone is a blank sheet: nothing walked, nothing seen, and what the game calls explored here is set aside (/pencil forget brings that back)."
            or "this zone's walked ground is forgotten (what the game calls explored is taken over again)."
    elseif word == "count" then
        say = used .. " textures for the pencil, " .. paintP.n .. " for the walked ground (" .. rimCount .. " squares on its rim), "
            .. backP.n .. " for the ground put back."
        local mapID = mapFrame and mapFrame:GetMapID()
        if mapID and SightOn(mapID) then
            local n = 0
            if c.part ~= false and not c.bare then
                n = Part(mapID).n
            else
                for _ in pairs(Sighted(mapID, true)) do n = n + 1 end
            end
            say = say .. " " .. n .. " of " .. #(ns.ZoneOverlays(mapID) or {}) .. " areas seen."
        end
    else
        c.on = not c.on
        c.step = nil
        say = c.on and "Unwalked land is in pencil." or "The pencil is off."
        if c.on and ns.Perf and ns.Perf("effects") then
            say = say .. " (Disabled while performance mode's \"No map effects\" is ticked.)"
        elseif c.on and mapFrame and not ns.PencilOn() then
            say = say .. " (This map has no pencil: zone maps on Forever only.)"
        end
    end
    -- (everything laid again, and what is seen read again: forget, blank and share change it)
    laidFor, paintFor, backFor, backMap = nil, nil, nil, nil
    seenStamp = seenStamp + 1
    ns.PencilRefresh()
    print("|cffc79a52Waymark|r: " .. say)
end
