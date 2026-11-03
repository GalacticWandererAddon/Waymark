local _, ns = ...

-- Dev tool: hand-adjusting clear view's outlines (ClearView.lua) on zone, city and
-- dungeon maps. /bfi cut opens a bar under the map; while it's open the map shows its
-- current outline (whatever clear view's settings say) and left-clicks are ours:
--   Keep / Cut          brush: drag to paint land back in, or cut it away. A stroke
--                       started where the last one ended carries it on; once it
--                       comes back round to its start it's an outline: the inside
--                       is kept (or cut) too
--   Keep shape / Cut shape   click the corners; click the first one again (or
--                       right-click) to close it: everything inside kept or cut
--   Eraser              click an edit to remove it (the one under the cursor shows
--                       white; inside an outline or shape counts); Undo brings it back
--   Undo                (Ctrl+Z, once per press) the last edit on the map open
--   Frames (continents) each zone map's rectangle and its burnt frame's line, outlined
--                       while you Clone or Paint (DrawFrames)
--   - / +               the brush size (click it: the list; the wheel over it steps);
--                       Peek: the cut-away map faintly round the
--                       cut, to trace along;  hold Shift to drag the map about
--   Edits               your strokes shown, faint or hidden, to see the map under
--                       them; hold Alt to hide them for a moment; hold Ctrl to
--                       see the whole map, the cut-away part too
--   View / New view     an optional view: a second outline for this map, named,
--                       its edits over the map's own outline; once baked, a check
--                       box on the Clear view page shows it in place of the usual one
--   Make usual          the view open becomes the usual outline, the usual one a view
--   Clone (continents)  right-click a spot of a zone map (zoomed in, where ZoneArt
--                       draws them) to take it as the source, then drag: that zone's
--                       art is drawn under the brush, each stroke from the source on
--                       (the marker shows it; it stays put between strokes). Previewed
--                       as you paint (the art under each brush dot); baked into patches
--                       ZoneArt draws (tools\cut_edits.py: Media\ZoneClone, Data\ZoneClone.lua).
--                       Saved as ops { op = "clone", dx, dy = source minus spot,
--                       z = the source's zone } under "c<continent>". Ctrl+right-click:
--                       in place, each stroke the zone's art from right under it (dx,
--                       dy 0): its own art, clean, over haze or a soft mask edge
--   Stamp (continents)  click to lay one of Data\MountainStamps.lua's mountains whole
--                       (tools\mountain_stamps.py: cut out along their ranges, so their
--                       peaks end as a zone map's do), the brush size its width, in a
--                       right-clicked spot's colour (else the colour where it's laid, else
--                       its own). Saved as { op = "stamp", t = "brush", p = { x, y }, w,
--                       piece, rot, sc, flip, a, rgb }; baked as a patch (cut_edits.py)
--   Box (continents)    Clone and Paint lay a rectangle, dragged corner to corner: saved
--                       as t = "shape", box = true, p = its four corners (the first where
--                       it was started), w = the brush size (how soft its baked edge is)
-- The game can't write textures, so edits are saved, drawn over the map (green kept,
-- red cut) and baked afterwards: /reload, then `python -I tools\cut_edits.py`
-- (Media\ZoneCut\<edition>\<name>.tga, Data\ZoneCut.lua). A new outline file (a city,
-- a dungeon floor) needs a game restart to load, a changed one a /reload.
-- Saved per edition and map: ns.db.cutEdits[edition][key] = { ar = width / height,
-- ops = { { op = "keep"|"cut", t = "brush"|"shape", w = brush width (0-1 of the
-- map's width), p = { x1, y1, ... } (0-1 across the map), fill = true: a brush
-- outline, its inside too }, ... } }, applied in order
-- over the zone's own outline (or, without one, all kept; all cut if any op keeps).
-- key as Ink's: "m<uiMapID>", "d<instance>:<floor>"; a view: "<key>/v<n>", its entry
-- with label = its name, own = true: its edits go over the map's base outline, not
-- over the usual one (a view made by Make usual).

local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local COLORS = { keep = { 0.25, 0.95, 0.35 }, cut = { 1, 0.2, 0.15 }, erase = { 1, 1, 1 }, clone = { 0.3, 0.65, 1 },
                 paint = { 0.95, 0.75, 0.3 } }
-- (the brush's width, of the map's width: fine steps down to a hair, for tight corners)
local SIZES = { 0.0003, 0.0004, 0.0005, 0.0006, 0.0008, 0.001, 0.0012, 0.0015, 0.0018, 0.0022, 0.0027,
                0.0033, 0.004, 0.005, 0.006, 0.0075, 0.009, 0.011, 0.013, 0.016, 0.02, 0.025, 0.03,
                0.037, 0.045, 0.055, 0.065, 0.08, 0.1, 0.12, 0.15 }

local map
local zoneHost, dungeonHost
local active            -- { host =, key =, base =, level = } or nil (key: base, or a view of it)
local viewOf = {}       -- [map key] = the view open on it ("v1"), nil: the map's own outline
local editing, peeking = false, false
local tool, sizeIndex = "keep", 21
local EDIT_ALPHAS = { { 1, "shown" }, { 0.3, "faint" }, { 0, "hidden" } }
local editsShown = 1    -- EDIT_ALPHAS index: how the saved edits show (Alt held: hidden)
local cur               -- the stroke or shape being made
local shownKey, shownHost
local BUDGET = 600      -- points drawn per frame (a big map's edits come in over a few frames)
local undo = {}         -- { key, op }
local catcher, bar, cursorRing
local Draw
local cloneSrc          -- { x, y, z = zone, here = in place } the Clone brush's source, picked by right-click
local srcRing           -- where the brush's art comes from
local cloneSoft = false -- the Soft button: strokes baked with a wide feathered edge (sea into sea)
local boxBrush = false  -- the Box button: Clone / Paint lay a rectangle, dragged corner to corner
local revealMode = false -- the Reveal button: the Clone brush in place, each stroke the zone map under it
local cloneBase = false  -- the Base button: Clone takes the zone map's base art alone (land as unexplored)
local paintMat = 1      -- the Paint brush's fill (ZoneArt.lua's ns.PAINT_NAMES)
local stampPiece = 1    -- the Stamp brush's mountain (Data\MountainStamps.lua)
local stampGhost, stampGhostMask  -- the stamp under the cursor, before it's laid
-- how the next Clone / Paint stroke lays its art (rot, sc, flip, tint: Clone's; a both):
-- changed just after a stroke, that stroke changes too (see Adjust)
local look = { rot = 0, sc = 1, flip = false, a = 1, tint = 1 }
local STRENGTHS = { 1, 0.75, 0.5, 0.25 }
local note              -- a word on the status line (Clone without a source)
local zHeld = false     -- Ctrl+Z down (a held key repeats: one undo per press)
-- Ctrl held alone: the before/after view (continents) and the whole map (zone maps).
-- Only once it's been held a moment with nothing else: Ctrl+Z, Ctrl+right-click or
-- Ctrl with the wheel used to hide all your work for as long as Ctrl was down.
local ctrlSince, ctrlUsed
local function CtrlAlone()
    if not IsControlKeyDown() then
        ctrlSince, ctrlUsed = nil, false
        return false
    end
    ctrlSince = ctrlSince or GetTime()
    if zHeld or IsMouseButtonDown("RightButton") or IsMouseButtonDown("LeftButton") then ctrlUsed = true end
    return not ctrlUsed and GetTime() - ctrlSince >= 0.35
end

function ns.CutEditing() return editing end
function ns.CutPeeking() return editing and peeking end
function ns.CutRevealing() return editing and CtrlAlone() end

-- the outline name of the view open on this map (by its outline name), or nil
function ns.CutEditView(name)
    if not (editing and active and active.key ~= active.base) then return end
    if tostring(ns.CutName(active.base)) == tostring(name) then return ns.CutName(active.key) end
end

local function Edits(key, make)
    local all = ns.db.cutEdits
    if not all then
        if not make then return end
        all = {}
        ns.db.cutEdits = all
    end
    local ed = ns.CutEdition()
    if make and not all[ed] then all[ed] = {} end
    local e = all[ed] and all[ed][key]
    if make and not e then
        e = { ops = {} }
        all[ed][key] = e
    end
    return e
end

-- how many of the map's edits are in its baked outline (Data\ZoneCut.lua's
-- ns.ZoneCutBaked: the bake's count and its last edit's first point): those aren't
-- drawn, the outline shows them (a big map's thousands of points were slow). 0: all
-- drawn (the Edits button right-clicked; the list changed since: Make usual, a
-- baked edit erased)
local showBaked = false
local unbaked = {}      -- [key] = true: its list rewritten this session (Make usual)
local function BakedCount(key)
    local b = ns.ZoneCutBaked and ns.ZoneCutBaked[ns.CutEdition()]
    b = b and b[key]
    local e = b and not (showBaked or unbaked[key]) and Edits(key)
    local o = e and e.ops[b[1]]
    if not (o and o.p[2] and math.abs(o.p[1] - b[2]) < 1e-6 and math.abs(o.p[2] - b[3]) < 1e-6) then return 0 end
    return b[1]
end

-- Surfaces -----------------------------------------------------------------------

local function MakeHost(parent)
    local h = CreateFrame("Frame", nil, parent)
    h:SetAllPoints(parent)
    h.lines, h.dots, h.live, h.liveDots = {}, {}, {}, {}
    -- (the saved edits on a layer of their own, to fade: Edits button, Alt; the
    -- stroke being drawn stays on h)
    h.done = CreateFrame("Frame", nil, h)
    h.done:SetAllPoints(h)
    h.n, h.m = 0, 0          -- lines and dots in use
    h.queue, h.qi = {}, 1    -- ops still to draw, the next one
    -- (the Clone brush's preview: the saved strokes' on h.done, the one being drawn on h)
    h.clone = { frame = h.done, tex = {}, masks = {}, nt = 0, nm = 0 }
    h.liveClone = { frame = h, tex = {}, masks = {}, nt = 0, nm = 0 }
    h.lens = { frame = h, tex = {}, masks = {}, nt = 0, nm = 0 }  -- (Reveal: the zone map in the ring)
    h:SetScript("OnSizeChanged", function(self)
        if shownHost == self and shownKey then Draw(self, shownKey) end
    end)
    return h
end

local function Surface()
    if ns.DungeonInkSurface then
        local canvas, key = ns.DungeonInkSurface()
        if canvas then
            if not dungeonHost then dungeonHost = MakeHost(canvas) end
            local overlay = ns.dungeonOverlay
            return dungeonHost, key, (overlay and overlay:GetFrameLevel() or canvas:GetFrameLevel()) + 4
        end
    end
    local id = map and map:GetMapID()
    if not (id and zoneHost) then return end
    local _, top = ns.CanvasLevels(map)
    -- (a continent: its key "c<id>", the Clone brush's)
    local info = C_Map.GetMapInfo(id)
    local cont = info and Enum.UIMapType and info.mapType == Enum.UIMapType.Continent
    return zoneHost, (cont and "c" or "m") .. id, math.min(top + 10, 8900)
end

-- Drawing ------------------------------------------------------------------------

local function Line(h, pool, i)
    local l = pool[i]
    if not l then
        l = (pool == h.lines and h.done or h):CreateLine(nil, "OVERLAY")
        pool[i] = l
    end
    return l
end

local function Dot(h, pool, i)
    local d = pool[i]
    if not d then
        d = (pool == h.dots and h.done or h):CreateTexture(nil, "OVERLAY")
        d:SetTexture(CIRCLE)
        pool[i] = d
    end
    return d
end

local function HideAll(pool) for _, o in ipairs(pool) do o:Hide() end end

-- Clone preview: before a bake, each clone stroke shows its source's art under
-- every brush dot (cropped to the dot's square, through a round mask; dots along
-- the stroke, and on a grid inside a filled outline). The bake draws it smooth.


local zoneRects = {}    -- ["cont:zone"] = { l, r, t, b } the zone on the continent
local function ZoneRect(cont, id)
    local k = cont .. ":" .. id
    if zoneRects[k] == nil then
        local ok, l, r, t, b = pcall(ns.MapRectOnMap, id, cont)
        zoneRects[k] = ok and l and r > l and b > t and { l, r, t, b } or false
    end
    return zoneRects[k]
end

local function PreviewTex(pv)
    pv.nt = pv.nt + 1
    local t = pv.tex[pv.nt]
    if not t then
        t = pv.frame:CreateTexture(nil, "ARTWORK")
        if t.SetSnapToPixelGrid then
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
        end
        pv.tex[pv.nt] = t
    end
    return t
end

local function PreviewMask(pv)
    pv.nm = pv.nm + 1
    local m = pv.masks[pv.nm]
    if not m then
        m = pv.frame:CreateMaskTexture()
        m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        pv.masks[pv.nm] = m
    end
    m:Show()
    return m
end

local function PreviewClear(pv)
    for i = 1, pv.nt do
        local t = pv.tex[i]
        t:Hide()
        for k = t:GetNumMaskTextures(), 1, -1 do t:RemoveMaskTexture(t:GetMaskTexture(k)) end
    end
    for i = 1, pv.nm do pv.masks[i]:Hide() end
    pv.nt, pv.nm = 0, 0
end

-- one dot of a clone op o: its source's art (turned, sized, mirrored, tinted as o says;
-- ZoneArt's ns.LayCloneArt) round x, y (0-1), r its radius (of the host's width), at
-- o's strength
local function PreviewDot(h, pv, o, rect, x, y, r)
    local W, H = h:GetWidth(), h:GetHeight()
    local mask = PreviewMask(pv)
    mask:ClearAllPoints()
    mask:SetPoint("CENTER", h, "TOPLEFT", x * W, -y * H)
    mask:SetSize(2 * r * W, 2 * r * W)
    local tint = ns.CLONE_TINTS and ns.CLONE_TINTS[o.tint or 1] or { 1, 1, 1 }
    local ry = r * W / H
    ns.LayCloneArt(function(piece)
        local tex = PreviewTex(pv)
        tex:SetDrawLayer("ARTWORK", piece and 1 or 0)
        tex:SetVertexColor(tint[1], tint[2], tint[3], o.a or 1)
        tex:AddMaskTexture(mask)
        return tex
    end, h, o, o.z, rect, x - r, y - ry, x + r, y + ry, W, H)
end

local function PointIn(p, x, y)
    local inside, n = false, #p / 2
    local j = n
    for i = 1, n do
        local xi, yi, xj, yj = p[2 * i - 1], p[2 * i], p[2 * j - 1], p[2 * j]
        if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then inside = not inside end
        j = i
    end
    return inside
end

-- a Paint dot: the fill round x, y, tiled as ZoneArt lays it (v in widths)
local function PaintDot(h, pv, file, tiles, cr, cg, cb, x, y, r)
    local W, H = h:GetWidth(), h:GetHeight()
    local mask = PreviewMask(pv)
    mask:ClearAllPoints()
    mask:SetPoint("CENTER", h, "TOPLEFT", x * W, -y * H)
    mask:SetSize(2 * r * W, 2 * r * W)
    local tex = PreviewTex(pv)
    tex:SetTexture(file, "REPEAT", "REPEAT", "TRILINEAR")
    tex:SetVertexColor(cr, cg, cb, pv.a or 1)
    local vy = y * H / W
    tex:SetTexCoord((x - r) * tiles, (x + r) * tiles, (vy - r) * tiles, (vy + r) * tiles)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", h, "TOPLEFT", x * W, -y * H)
    tex:SetSize(2 * r * W, 2 * r * W)
    tex:AddMaskTexture(mask)
    tex:Show()
end

-- a Stamp op's look on a texture: its piece of the atlas turned, sized and mirrored by
-- the four corners' texture coords (worked out as tools\clone_art.py lays it; past the
-- piece's round edge they reach its neighbours, so it's drawn through a round mask),
-- in o.rgb (else the piece's own colour) over the piece's paper grey
local STAMPS = ns.MEDIA .. "MountainStamps"
local function StampLook(tex, o, alpha)
    local lib = ns.MountainStamps
    local n = math.max(1, math.min(#lib, o.piece or 1))
    local cw, ch = 1 / lib.cols, 1 / lib.rows
    local cu, cv = ((n - 1) % lib.cols + 0.5) * cw, (math.floor((n - 1) / lib.cols) + 0.5) * ch
    local a = math.rad(o.rot or 0)
    local c, s = math.cos(a), math.sin(a)
    local fl = o.flip and -1 or 1
    local function At(X, Y) return cu + (c * X + s * Y) * fl * cw, cv + (-s * X + c * Y) * ch end
    local ulx, uly = At(-0.5, -0.5)
    local llx, lly = At(-0.5, 0.5)
    local urx, ury = At(0.5, -0.5)
    local lrx, lry = At(0.5, 0.5)
    tex:SetTexture(STAMPS, "CLAMP", "CLAMP", "TRILINEAR")
    tex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
    local rgb = o.rgb or lib[n].rgb
    local k = 1 / lib.paper
    tex:SetVertexColor(math.min(1, rgb[1] * k), math.min(1, rgb[2] * k), math.min(1, rgb[3] * k), alpha or o.a or 1)
end

-- a saved Stamp: its mountain round its spot
local function StampDot(h, pv, o)
    if not ns.MountainStamps then return end
    local W, H = h:GetWidth(), h:GetHeight()
    local x, y = o.p[1], o.p[2]
    local d = (o.w or 0.02) * (o.sc or 1) * W
    local mask = PreviewMask(pv)
    mask:ClearAllPoints()
    mask:SetPoint("CENTER", h, "TOPLEFT", x * W, -y * H)
    mask:SetSize(d, d)
    local tex = PreviewTex(pv)
    tex:SetDrawLayer("ARTWORK", 1)
    StampLook(tex, o)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", h, "TOPLEFT", x * W, -y * H)
    tex:SetSize(d, d)
    tex:AddMaskTexture(mask)
    tex:Show()
end

-- a clone or paint op's dots, from its point `from` on (a stroke being drawn: just its new ones)
local function PreviewOp(h, pv, cont, o, from)
    if o.box then
        -- (a box: its art over the rectangle, edge to edge, no round dots)
        local p = o.p
        local x0, x1 = math.min(p[1], p[5]), math.max(p[1], p[5])
        local y0, y1 = math.min(p[2], p[6]), math.max(p[2], p[6])
        if x1 <= x0 or y1 <= y0 or not cont then return end
        local W, H = h:GetWidth(), h:GetHeight()
        if o.op == "paint" then
            if not ns.ZoneArtPaint then return end
            local file, tiles, cr, cg, cb = ns.ZoneArtPaint(cont, o.mat or 1, o.rgb)
            local tex = PreviewTex(pv)
            tex:SetTexture(file, "REPEAT", "REPEAT", "TRILINEAR")
            tex:SetVertexColor(cr, cg, cb, o.a or 1)
            local k = H / W
            tex:SetTexCoord(x0 * tiles, x1 * tiles, y0 * k * tiles, y1 * k * tiles)
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", h, "TOPLEFT", x0 * W, -y0 * H)
            tex:SetSize((x1 - x0) * W, (y1 - y0) * H)
            tex:Show()
            return
        end
        local rect = o.z and ZoneRect(cont, o.z)
        if not rect then return end
        local oo = { dx = o.dx, dy = o.dy, z = o.z, rot = o.rot, sc = o.sc, flip = o.flip, tint = o.tint, a = o.a, base = o.base,
                     ax = p[1], ay = p[2] }
        local tint = ns.CLONE_TINTS and ns.CLONE_TINTS[o.tint or 1] or { 1, 1, 1 }
        ns.LayCloneArt(function(piece)
            local tex = PreviewTex(pv)
            tex:SetDrawLayer("ARTWORK", piece and 1 or 0)
            tex:SetVertexColor(tint[1], tint[2], tint[3], o.a or 1)
            return tex
        end, h, oo, o.z, rect, x0, y0, x1, y1, W, H)
        return
    end
    local Dot
    if o.op == "paint" then
        if not (cont and ns.ZoneArtPaint) then return end
        local file, tiles, cr, cg, cb = ns.ZoneArtPaint(cont, o.mat or 1, o.rgb)
        Dot = function(x, y, rad)
            pv.a = o.a
            PaintDot(h, pv, file, tiles, cr, cg, cb, x, y, rad)
        end
    else
        local rect = cont and o.z and ZoneRect(cont, o.z)
        if not rect then return end
        -- (the stroke's anchor: its first point)
        local oo = { dx = o.dx, dy = o.dy, z = o.z, rot = o.rot, sc = o.sc, flip = o.flip, tint = o.tint, a = o.a, base = o.base,
                     ax = o.ax or o.p[1], ay = o.ay or o.p[2] }
        Dot = function(x, y, rad) PreviewDot(h, pv, oo, rect, x, y, rad) end
    end
    local p, r = o.p, (o.w or 0.02) / 2
    local ar = h:GetHeight() / math.max(1, h:GetWidth())   -- (y in widths)
    local gap = r * 0.6
    local lx, ly = pv.lx, pv.ly
    for i = from or 1, #p / 2 do
        local x, y = p[2 * i - 1], p[2 * i]
        if not lx or i == #p / 2 or (x - lx) ^ 2 + ((y - ly) * ar) ^ 2 >= gap * gap then
            Dot(x, y, r)
            lx, ly = x, y
        end
    end
    pv.lx, pv.ly = lx, ly
    if o.fill and #p >= 6 then
        -- (inside the outline: a grid of dots)
        local x0, x1, y0, y1 = 1, 0, 1, 0
        for i = 1, #p, 2 do
            x0, x1 = math.min(x0, p[i]), math.max(x1, p[i])
            y0, y1 = math.min(y0, p[i + 1]), math.max(y1, p[i + 1])
        end
        local step = math.max(r * 1.2, (x1 - x0) / 60)
        for gy = y0, y1, step / ar do
            for gx = x0, x1, step do
                if PointIn(p, gx, gy) then Dot(gx, gy, step * 0.85) end
            end
        end
    end
end

-- one op on the host: n lines and m dots used so far; returns the new counts
local function PaintOp(h, lines, dots, n, m, o, open)
    -- (a saved clone stroke: its preview, no lines)
    if o.op == "stamp" and lines == h.lines then
        StampDot(h, h.clone, o)
        return n, m
    end
    if (o.op == "clone" or o.op == "paint") and lines == h.lines then
        h.clone.lx = nil
        PreviewOp(h, h.clone, h.cont, o)
        return n, m
    end
    local W, H = h:GetWidth(), h:GetHeight()
    local c = COLORS[o.op] or COLORS.keep
    local k = W / 1002
    local p = o.p
    local brush = o.t == "brush"
    local thick = brush and math.max(1, o.w * W) or 2.5 * k
    local alpha = brush and 0.4 or 0.9
    local count = #p / 2
    local function XY(i) return p[2 * i - 1] * W, -p[2 * i] * H end
    local segs = ((brush and not o.fill) or open) and count - 1 or count
    for i = 1, segs do
        local x0, y0 = XY(i)
        local x1, y1 = XY(i % count + 1)
        n = n + 1
        local l = Line(h, lines, n)
        l:SetColorTexture(c[1], c[2], c[3], alpha)
        l:SetThickness(thick)
        l:SetStartPoint("TOPLEFT", h, x0, y0)
        l:SetEndPoint("TOPLEFT", h, x1, y1)
        l:Show()
    end
    -- (a brush's round ends and joints; a shape's corners)
    local size = brush and thick or 7 * k
    for i = 1, count do
        -- (a brush: its ends and every third point are enough to round its joints)
        if not brush or i == 1 or i == count or i % 3 == 0 then
            local x, y = XY(i)
            m = m + 1
            local d = Dot(h, dots, m)
            d:SetVertexColor(c[1], c[2], c[3], brush and alpha or 1)
            d:SetSize(size, size)
            d:ClearAllPoints()
            d:SetPoint("CENTER", h, "TOPLEFT", x, y)
            d:Show()
        end
    end
    return n, m
end

-- the queue, a frame's worth at a time
local function Drain(h)
    local budget = BUDGET
    while budget > 0 and h.queue[h.qi] do
        local o = h.queue[h.qi]
        h.n, h.m = PaintOp(h, h.lines, h.dots, h.n, h.m, o)
        budget = budget - #o.p / 2
        h.qi = h.qi + 1
    end
    if not h.queue[h.qi] then
        wipe(h.queue)
        h.qi = 1
        h:SetScript("OnUpdate", nil)
    end
end

local function Queue(h, o)
    h.queue[#h.queue + 1] = o
    h:SetScript("OnUpdate", Drain)
end

-- everything on this map again
-- Zone frames (continents): each zone map's rectangle (where its art ends) and, inside
-- it, its burnt frame's line (zone_shapes FRAMES: 1.2% in on Forever, 3.5% on Classic
-- Era), so blending stops short of them; the zone the brush would take from (under the
-- cursor) brighter
local FRAME_IN = { Forever = 0.012, Era = 0.035 }
local showFrames = true
local framesFor           -- { [zone] = { l, r, t, b } } the continent drawn
local function FrameLine(h, i)
    local l = h.rects[i]
    if not l then
        l = h.rectFrame:CreateLine(nil, "OVERLAY")
        h.rects[i] = l
    end
    return l
end
local function DrawFrames(h, cont)
    h.rectN = 0
    if not h.rectFrame then
        h.rectFrame = CreateFrame("Frame", nil, h)
        h.rectFrame:SetAllPoints(h)
        h.rects = {}
    end
    local list = {}
    if cont then
        local ok, children = pcall(C_Map.GetMapChildrenInfo, cont, Enum.UIMapType.Zone)
        for _, c in ipairs(ok and children or {}) do list[c.mapID] = ZoneRect(cont, c.mapID) or nil end
        local fm = ns.ForeverMapDev()
        for zid, x in pairs(fm and fm.extra or {}) do
            if x[1] == cont then list[zid] = ZoneRect(cont, zid) or nil end
        end
    end
    framesFor = list
    local W, H = h:GetWidth(), h:GetHeight()
    for zid, r in pairs(list) do
        local fin = FRAME_IN[ns.MapEdition()] or FRAME_IN.Era
        local fx, fy = (r[2] - r[1]) * fin, (r[4] - r[3]) * fin
        for k, b in ipairs({ { r[1], r[2], r[3], r[4] }, { r[1] + fx, r[2] - fx, r[3] + fy, r[4] - fy } }) do
            local c = { { b[1], b[3], b[2], b[3] }, { b[2], b[3], b[2], b[4] }, { b[2], b[4], b[1], b[4] }, { b[1], b[4], b[1], b[3] } }
            for _, s in ipairs(c) do
                h.rectN = h.rectN + 1
                local l = FrameLine(h, h.rectN)
                l.zone, l.inner = zid, k == 2
                l:SetStartPoint("TOPLEFT", h, s[1] * W, -s[2] * H)
                l:SetEndPoint("TOPLEFT", h, s[3] * W, -s[4] * H)
                l:Show()
            end
        end
    end
    for i = h.rectN + 1, #(h.rects or {}) do h.rects[i]:Hide() end
    h.rectLit, h.rectPx = false, nil
end
-- each frame: shown or not, the lit zone, 1.5 screen px thick whatever the zoom
local function UpdateFrames(h, lit)
    if not h.rectFrame then return end
    local on = showFrames and h.cont and (tool == "clone" or tool == "paint" or tool == "stamp") and true or false
    h.rectFrame:SetShown(on)
    if not on then return end
    local px = UIParent:GetEffectiveScale() / math.max(1e-6, h:GetEffectiveScale())
    if h.rectLit == lit and h.rectPx == px then return end
    h.rectLit, h.rectPx = lit, px
    for i = 1, h.rectN do
        local l = h.rects[i]
        local hot = l.zone == lit
        if l.inner then
            l:SetColorTexture(1, 0.35, 0.25, hot and 0.85 or 0.35)
        else
            l:SetColorTexture(1, 0.85, 0.3, hot and 1 or 0.45)
        end
        l:SetThickness((hot and 2 or 1.25) * px)
    end
end

Draw = function(h, key)
    for i = 1, h.n do h.lines[i]:Hide() end
    for i = 1, h.m do h.dots[i]:Hide() end
    h.n, h.m = 0, 0
    PreviewClear(h.clone)
    h.cont = tonumber(key and key:match("^c(%d+)$"))
    wipe(h.queue)
    h.qi = 1
    local ops = (Edits(key) or {}).ops or {}
    for i = BakedCount(key) + 1, #ops do Queue(h, ops[i]) end
    DrawFrames(h, h.cont)
end

local function DrawLive()
    if not active then return end
    local h = active.host
    HideAll(h.live)
    HideAll(h.liveDots)
    if cur and #cur.p >= 2 then PaintOp(h, h.live, h.liveDots, 0, 0, cur, not cur.box) end
    -- (the clone stroke's preview: its new dots only)
    if cur and (cur.op == "clone" or cur.op == "paint") then
        local pv = h.liveClone
        if pv.of ~= cur or cur.box then PreviewClear(pv) pv.of, pv.lx, pv.done = cur, nil, 0 end
        PreviewOp(h, pv, tonumber(active.key:match("^c(%d+)$")), cur, pv.done + 1)
        pv.done = #cur.p / 2
    end
end

-- the stroke's done: its preview goes (the saved one's drawn instead)
local function EndLive(h)
    HideAll(h.live)
    HideAll(h.liveDots)
    PreviewClear(h.liveClone)
    h.liveClone.of = nil
end

local UpdateBar

local function Refresh(force)
    local host, base, level = Surface()
    if shownHost and (shownHost ~= host or not editing) then shownHost:Hide() end
    local key = base and viewOf[base] and (base .. "/" .. viewOf[base]) or base
    active = host and { host = host, key = key, base = base, level = level } or nil
    if not (host and editing) then
        shownKey, shownHost = nil, nil
        return
    end
    if host == zoneHost then
        local lvl = ns.ArtLevel(map, 6)
        -- (on a continent over every clone patch too: they stack a level per 32 deep)
        local top = ns.ZoneArtTop and ns.ZoneArtTop()
        if top and lvl <= top then lvl = top + 1 end
        if host:GetFrameLevel() ~= lvl then host:SetFrameLevel(lvl) end
    end
    host:Show()
    local changed = key ~= shownKey or host ~= shownHost
    if changed then cur = nil HideAll(host.live) HideAll(host.liveDots) end
    if force or changed then Draw(host, key) end
    shownKey, shownHost = key, host
    if changed and UpdateBar then UpdateBar() end
end

-- Editing ------------------------------------------------------------------------

local function Round(v) return math.floor(v * 100000 + 0.5) / 100000 end

-- the cursor on the active surface, 0-1
local function Cursor()
    local h = active and active.host
    if not h then return end
    local x, y = GetCursorPosition()
    local s = h:GetEffectiveScale()
    local l, t, w, hh = h:GetLeft(), h:GetTop(), h:GetWidth(), h:GetHeight()
    if not (l and t and w > 0 and hh > 0) then return end
    return (x / s - l) / w, (t - y / s) / hh
end

-- screen pixels (UI units) per unit of the surface's width
local function ScreenWidth()
    local h = active.host
    return h:GetWidth() * h:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

local function Add(o)
    local h = active.host
    local e = Edits(active.key, true)
    e.ar = Round(h:GetWidth() / math.max(1, h:GetHeight()))
    e.ops[#e.ops + 1] = o
    undo[#undo + 1] = { active.key, o }
    Queue(h, o)
    UpdateBar()
end

local function Shape() return tool == "keepShape" or tool == "cutShape" end
local function Op()
    if tool == "clone" or tool == "paint" then return tool end
    return (tool == "cut" or tool == "cutShape") and "cut" or "keep"
end
local function OnContinent() return active and active.key:sub(1, 1) == "c" end

-- the Clone brush's source: the zone map there (its art is what's drawn)
-- the zone map at a spot of the continent: the game's zone there, else (the sea: no
-- zone's, but a zone map's rectangle reaches it, waves and all) the smallest one there
local function ZoneAtSpot(id, x, y)
    -- (Forever's maps on Classic Era: the zones only Forever has, which the game doesn't know)
    local fm = ns.ForeverMapDev()
    for zid, xx in pairs(fm and fm.extra or {}) do
        local r = xx[1] == id and ZoneRect(id, zid)
        if r and x >= r[1] and x <= r[2] and y >= r[3] and y <= r[4] then return zid end
    end
    local ok, info = pcall(C_Map.GetMapInfoAtPosition, id, x, y)
    local z = ok and info and info.mapID ~= id and info.mapID
    if not z then
        local ok2, children = pcall(C_Map.GetMapChildrenInfo, id, Enum.UIMapType.Zone)
        local best
        for _, c in ipairs(ok2 and children or {}) do
            local r = ZoneRect(id, c.mapID)
            if r and x >= r[1] and x <= r[2] and y >= r[3] and y <= r[4]
                and (not best or (r[2] - r[1]) * (r[4] - r[3]) < best[2]) then
                best = { c.mapID, (r[2] - r[1]) * (r[4] - r[3]) }
            end
        end
        z = best and best[1]
    end
    return z
end

-- the colour of the zone map at a spot (its colour grid), 0-1, and the zone
local function ColourAtSpot(id, x, y)
    local z = ZoneAtSpot(id, x, y)
    local r = z and ZoneRect(id, z)
    if not (r and ns.ZoneArtColourAt) then return end
    local aw, ah = ns.MapArtSize(z)
    local cr, cg, cb = ns.ZoneArtColourAt(z, (x - r[1]) / (r[2] - r[1]) * aw, (y - r[3]) / (r[4] - r[3]) * ah)
    if cr then return { cr, cg, cb }, z end
end

local function PickSource(x, y)
    local id = tonumber(active.key:sub(2))
    local z = ZoneAtSpot(id, x, y)
    if not z then
        note = "no zone map there to clone from"
    else
        cloneSrc, note = { x = x, y = y, z = z, here = (IsControlKeyDown() or revealMode) or nil }, nil
    end
    UpdateBar()
end

-- Paint's Colour fill: right-click picks the colour of the zone map there
local paintRGB, paintRGBFrom
local function PickColour(x, y)
    local rgb, z = ColourAtSpot(tonumber(active.key:sub(2)), x, y)
    if not rgb then
        note = "no zone map colour there to pick"
    else
        local info = C_Map.GetMapInfo(z)
        paintRGB, paintRGBFrom, note = rgb, info and info.name or tostring(z), nil
    end
    UpdateBar()
end

-- the Stamp brush's colour at a spot: the picked one, else the zone map's there (nil: none,
-- the stamp keeps its own); the last spot's kept, as the ghost asks each frame
local stampAt, stampRGB
local function StampColour(x, y)
    if paintRGB then return paintRGB end
    local at = string.format("%.4f %.4f", x, y)
    if at ~= stampAt then
        stampAt, stampRGB = at, ColourAtSpot(tonumber(active.key:sub(2)), x, y)
    end
    return stampRGB
end

local function CloseShape()
    local o = cur
    cur = nil
    if active then HideAll(active.host.live) HideAll(active.host.liveDots) end
    if o and #o.p >= 6 then Add(o) end
end

-- Eraser -------------------------------------------------------------------------

local function InPolygon(p, x, y)
    local inside, n = false, #p / 2
    local j = n
    for i = 1, n do
        local xi, yi, xj, yj = p[2 * i - 1], p[2 * i], p[2 * j - 1], p[2 * j]
        if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then inside = not inside end
        j = i
    end
    return inside
end

-- squared distance from (x, y) to the side a-b
local function SegDist2(x, y, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len = dx * dx + dy * dy
    local t = len > 0 and math.max(0, math.min(1, ((x - ax) * dx + (y - ay) * dy) / len)) or 0
    local px, py = ax + t * dx - x, ay + t * dy - y
    return px * px + py * py
end

-- the latest edit under the cursor (0-1 across the map) and its place in the list:
-- on a stroke (or within 6 px of it), or inside an outline or shape
local function EditAt(x, y)
    local e = active and Edits(active.key)
    if not (e and #e.ops > 0) then return end
    local h = active.host
    local ar = h:GetHeight() / math.max(1, h:GetWidth())  -- (distances in map widths)
    local slack = 6 / math.max(1, ScreenWidth())
    for i = #e.ops, BakedCount(active.key) + 1, -1 do  -- (the ones drawn)
        local o = e.ops[i]
        local p, n = o.p, #o.p / 2
        local closed = o.t == "shape" or o.fill
        if closed and n >= 3 and InPolygon(p, x, y) then return o, i end
        local r = (o.t == "brush" and o.w / 2 or 0) + slack
        local sides = closed and n or math.max(1, n - 1)
        for k = 1, sides do
            local k2 = n > 1 and (k % n + 1) or k
            if SegDist2(x, y * ar, p[2 * k - 1], p[2 * k] * ar, p[2 * k2 - 1], p[2 * k2] * ar) <= r * r then
                return o, i
            end
        end
    end
end

-- the edit the eraser would take, shown white
local hoverOp
local lastX, lastY  -- (looked for again only when the cursor moves)
local function HoverErase(on)
    local o
    if on then
        local cx, cy = GetCursorPosition()
        if cx == lastX and cy == lastY then return end
        lastX, lastY = cx, cy
    else
        lastX = nil
    end
    if on and active and catcher:IsMouseOver() then
        local x, y = Cursor()
        if x then o = EditAt(x, y) end
    end
    if o == hoverOp then return end
    hoverOp = o
    if not active then return end
    local h = active.host
    HideAll(h.live)
    HideAll(h.liveDots)
    if o then PaintOp(h, h.live, h.liveDots, 0, 0, { op = "erase", t = o.t, w = o.w, p = o.p, fill = o.fill }) end
end

local function Erase()
    local x, y = Cursor()
    if not x then return end
    local o, i = EditAt(x, y)
    if not o then return end
    table.remove(Edits(active.key).ops, i)
    undo[#undo + 1] = { active.key, o, erased = i }
    HoverErase(false)
    Refresh(true)
    UpdateBar()
end

local function MouseDown(button)
    if not active then return end
    if IsControlKeyDown() then ctrlUsed = true end
    if tool == "erase" then
        if button == "LeftButton" then Erase() end
        return
    end
    local x, y = Cursor()
    if not x then return end
    if Shape() then
        if button == "RightButton" then CloseShape() return end
        if button ~= "LeftButton" then return end
        if not cur then cur = { op = Op(), t = "shape", p = {} } end
        -- (on the first corner again: closed)
        if #cur.p >= 6 then
            local px = ScreenWidth()
            local ar = active.host:GetHeight() / math.max(1, active.host:GetWidth())
            local dx, dy = (x - cur.p[1]) * px, (y - cur.p[2]) * px * ar
            if dx * dx + dy * dy < 100 then CloseShape() return end
        end
        cur.p[#cur.p + 1] = Round(x)
        cur.p[#cur.p + 1] = Round(y)
        DrawLive()
        return
    end
    if tool == "stamp" then
        if button == "RightButton" then
            -- (Ctrl+right-click: back to each stamp's own spot's colour)
            if IsControlKeyDown() then paintRGB, paintRGBFrom = nil, nil UpdateBar() else PickColour(x, y) end
            return
        end
        if button ~= "LeftButton" or not ns.MountainStamps then return end
        local rgb = StampColour(x, y)
        Add({ op = "stamp", t = "brush", w = SIZES[sizeIndex], p = { Round(x), Round(y) }, piece = stampPiece,
              rot = look.rot ~= 0 and look.rot or nil, sc = look.sc ~= 1 and look.sc or nil, flip = look.flip or nil,
              a = look.a < 1 and look.a or nil,
              rgb = rgb and { Round(rgb[1]), Round(rgb[2]), Round(rgb[3]) } or nil })
        return
    end
    if tool == "clone" and button == "RightButton" then PickSource(x, y) return end
    if tool == "paint" and button == "RightButton" then
        if paintMat == ns.PAINT_COLOUR then PickColour(x, y) end
        return
    end
    if button ~= "LeftButton" then return end
    local sx, sy = GetCursorPosition()
    cur = { op = Op(), t = "brush", w = SIZES[sizeIndex], p = { Round(x), Round(y) }, sx = sx, sy = sy }
    if tool == "clone" then
        if not cloneSrc then
            cur, note = nil, "right-click a spot to clone from first"
            UpdateBar()
            return
        end
        -- (every stroke starts from the source: it stays where it was picked)
        if cloneSrc.here then
            -- (Reveal with no zone picked: the zone map under the stroke's start)
            cur.dx, cur.dy, cur.z = 0, 0, cloneSrc.z or ZoneAtSpot(tonumber(active.key:sub(2)), x, y)
            if not cur.z then
                cur, note = nil, "no zone map here to reveal"
                UpdateBar()
                return
            end
        else
            cur.dx, cur.dy, cur.z = Round(cloneSrc.x - x), Round(cloneSrc.y - y), cloneSrc.z
        end
        cur.soft = cloneSoft or nil
        -- (Reveal: plain, so the bake makes it a mask edit, not a patch)
        if not revealMode then
            cur.base = cloneBase or nil
            cur.rot = look.rot ~= 0 and look.rot or nil
            cur.sc = look.sc ~= 1 and look.sc or nil
            cur.flip = look.flip or nil
            cur.tint = look.tint > 1 and look.tint or nil
        end
        cur.a = look.a < 1 and look.a or nil
    elseif tool == "paint" then
        cur.mat, cur.soft = paintMat, cloneSoft or nil
        cur.a = look.a < 1 and look.a or nil
        if paintMat == ns.PAINT_MATCHED then
            -- (Sea, matched: the zone map nearest the start, and the spot on its art the
            -- bake takes the sea's colour from)
            local cont = tonumber(active.key:sub(2))
            local ok, children = pcall(C_Map.GetMapChildrenInfo, cont, Enum.UIMapType.Zone)
            local best, bd
            for _, c in ipairs(ok and children or {}) do
                local r = ZoneRect(cont, c.mapID)
                if r then
                    local ddx = math.max(r[1] - x, 0, x - r[2])
                    local ddy = math.max(r[3] - y, 0, y - r[4])
                    local d = ddx * ddx + ddy * ddy - (r[2] - r[1]) * (r[4] - r[3]) * 1e-3  -- (inside: the smaller)
                    if not bd or d < bd then best, bd = c.mapID, d end
                end
            end
            local r = best and ZoneRect(cont, best)
            if r then
                -- (the nearest spot inside it, off its frame)
                local fx = (math.max(r[1], math.min(r[2], x)) - r[1]) / (r[2] - r[1])
                local fy = (math.max(r[3], math.min(r[4], y)) - r[3]) / (r[4] - r[3])
                local aw, ah = ns.MapArtSize(best)
                cur.z = best
                cur.zx = math.floor((0.06 + 0.88 * fx) * aw + 0.5)
                cur.zy = math.floor((0.06 + 0.88 * fy) * ah + 0.5)
                -- (its colour there now, from the colour grid, as a tint over the sea
                -- texture's grey (190): the preview shows it; the bake samples finer)
                local cr, cg, cb = ns.ZoneArtColourAt(best, cur.zx, cur.zy)
                if cr then
                    local k = 255 / 190
                    cur.rgb = { Round(math.min(1, cr * k)), Round(math.min(1, cg * k)), Round(math.min(1, cb * k)) }
                end
            end
        elseif paintMat == ns.PAINT_COLOUR then
            if not paintRGB then
                cur, note = nil, "right-click a spot to pick its colour first"
                UpdateBar()
                return
            end
            cur.rgb = { Round(paintRGB[1]), Round(paintRGB[2]), Round(paintRGB[3]) }
        end
    end
    if boxBrush and (tool == "clone" or tool == "paint") then
        -- (a box: its four corners, the first where it was started; the brush size its edge)
        local px, py = cur.p[1], cur.p[2]
        cur.t, cur.box, cur.p = "shape", true, { px, py, px, py, px, py, px, py }
    end
    DrawLive()
end

-- two points (0-1 across the surface) within reach of each other on screen: about
-- a brush and a half, at least 12 px
local function Near(x0, y0, x1, y1, w)
    local px = ScreenWidth()
    local ar = active.host:GetHeight() / math.max(1, active.host:GetWidth())
    local dx, dy = (x1 - x0) * px, (y1 - y0) * px * ar
    local reach = math.max(12, w * px * 1.5)
    return dx * dx + dy * dy <= reach * reach
end

-- the stroke goes on from the last one (started where it ended): joined to it, and
-- once the outline is back at its start, closed (fill)
local function MouseUp()
    if cur and cur.box then
        local o = cur
        cur = nil
        o.sx, o.sy = nil, nil
        if not active then return end
        EndLive(active.host)
        local p = o.p
        if p[1] ~= p[5] and p[2] ~= p[6] then Add(o) end
        return
    end
    if not cur or cur.t ~= "brush" then return end
    local o = cur
    cur = nil
    o.sx, o.sy = nil, nil
    if not active then return end
    EndLive(active.host)
    local e = Edits(active.key)
    local last = e and e.ops[#e.ops]
    local u = undo[#undo]
    -- (outlines only: Clone, Reveal and Paint strokes stay one each, so Undo and the Eraser
    -- take back just that one; joined, a run of short dabs went as one)
    local joins = o.op ~= "clone" and o.op ~= "paint"
        and last and u and u[1] == active.key and u[2] == last  -- (only your own last stroke, this session)
        and last.t == "brush" and last.op == o.op and not last.fill and last.dx == o.dx and last.dy == o.dy and last.soft == o.soft and last.mat == o.mat
        and (last.rgb and table.concat(last.rgb, ",")) == (o.rgb and table.concat(o.rgb, ","))
        and last.rot == o.rot and last.sc == o.sc and last.flip == o.flip and last.tint == o.tint and last.a == o.a
        and Near(last.p[#last.p - 1], last.p[#last.p], o.p[1], o.p[2], o.w)
    local target = o
    if joins then
        undo[#undo + 1] = { active.key, last, #last.p }
        for i = 3, #o.p do last.p[#last.p + 1] = o.p[i] end  -- (its first point: where the last ended)
        target = last
    end
    -- back at the start, after going some way round: an outline
    local p = target.p
    if #p >= 16 and Near(p[1], p[2], p[#p - 1], p[#p], target.w) then
        local far = false
        for i = 1, #p - 1, 2 do
            if not Near(p[1], p[2], p[i], p[i + 1], target.w * 3) then far = true break end
        end
        if far then target.fill = true end
    end
    if joins then
        -- (just the new stroke, and the closing side once it's closed)
        local h = active.host
        if (o.op == "clone" or o.op == "paint") and last.fill then
            Refresh(true)  -- (its inside too: all again)
        else
            -- (the joined piece drawn as the stroke it joins: its source, or its fill)
            -- (its anchor too: where the joined stroke began)
            local piece = {}
            for kk, v in pairs(last) do piece[kk] = v end
            piece.p, piece.fill = o.p, nil
            piece.ax, piece.ay = last.p[1], last.p[2]
            Queue(h, piece)
            if last.fill then
                local q = last.p
                Queue(h, { op = o.op, t = "brush", w = last.w, p = { q[#q - 1], q[#q], q[1], q[2] } })
            end
        end
        UpdateBar()
    else
        Add(o)
    end
end

-- the brush's size round the cursor (on the catcher, above the map)
local function PlaceRing()
    local l, b = catcher:GetLeft(), catcher:GetBottom()
    -- (the Stamp brush: the stamp itself, faint, where a click lays it)
    local stamping = tool == "stamp" and ns.MountainStamps and active and l and catcher:IsMouseOver() and not cur
    stampGhost:SetShown(stamping and true or false)
    if stamping then
        cursorRing:Hide()
        local x, y = GetCursorPosition()
        local s = catcher:GetEffectiveScale()
        local d = SIZES[sizeIndex] * look.sc * active.host:GetWidth() * active.host:GetEffectiveScale() / s
        local cx, cy = Cursor()
        StampLook(stampGhost, { piece = stampPiece, rot = look.rot, flip = look.flip, rgb = cx and StampColour(cx, cy) }, 0.7 * look.a)
        for _, t in ipairs({ stampGhost, stampGhostMask }) do
            t:SetSize(d, d)
            t:ClearAllPoints()
            t:SetPoint("CENTER", catcher, "BOTTOMLEFT", x / s - l, y / s - b)
        end
        return
    end
    if not (active and l and catcher:IsMouseOver()) or Shape() or tool == "erase"
        or (boxBrush and OnContinent()) then cursorRing:Hide() return end
    local x, y = GetCursorPosition()
    local s = catcher:GetEffectiveScale()
    local d = SIZES[sizeIndex] * active.host:GetWidth() * active.host:GetEffectiveScale() / s
    cursorRing:SetSize(d, d)
    cursorRing:ClearAllPoints()
    cursorRing:SetPoint("CENTER", catcher, "BOTTOMLEFT", x / s - l, y / s - b)
    cursorRing:Show()
end

-- the Clone brush's source: at the picked spot; while a stroke is made, moving
-- with the cursor from there
local function PlaceSource()
    if not (tool == "clone" and cloneSrc and not cloneSrc.here and active and OnContinent() and catcher:IsMouseOver()) then srcRing:Hide() return end
    local h = active.host
    local x, y = cloneSrc.x, cloneSrc.y
    if cur and cur.dx then
        local cx, cy = Cursor()
        if not cx then srcRing:Hide() return end
        x, y = cx + cur.dx, cy + cur.dy
    end
    local hs, cs = h:GetEffectiveScale(), catcher:GetEffectiveScale()
    local l, t, cl, cb = h:GetLeft(), h:GetTop(), catcher:GetLeft(), catcher:GetBottom()
    if not (l and cl) then srcRing:Hide() return end
    local px = (l + x * h:GetWidth()) * hs / cs - cl
    local py = (t - y * h:GetHeight()) * hs / cs - cb
    local d = math.max(8, SIZES[sizeIndex] * h:GetWidth() * hs / cs)
    srcRing:SetSize(d, d)
    srcRing:ClearAllPoints()
    srcRing:SetPoint("CENTER", catcher, "BOTTOMLEFT", px, py)
    srcRing:Show()
end

-- Shift held: clicks go through to the map, to drag it about (not mid-stroke; a drag
-- begun with Shift goes on until the button's let go)
local passing = false
local function PassThrough()
    local want = not (cur and (cur.t == "brush" or cur.box))
        and (IsShiftKeyDown() or (passing and IsMouseButtonDown("LeftButton")))
    if want ~= passing then
        passing = want
        catcher:EnableMouse(not want)
    end
end

-- the saved edits' layer: the Edits button's choice, hidden while Alt is held
local function FadeEdits()
    local h = active and active.host
    if not h then return end
    -- (Ctrl on a continent: before/after, the unbaked strokes hidden with the patches)
    local a = (IsAltKeyDown() or (CtrlAlone() and OnContinent())) and 0 or EDIT_ALPHAS[editsShown][1]
    if h.done:GetAlpha() ~= a then h.done:SetAlpha(a) end
end

-- Ctrl held: the whole map, the cut-away part too (Peek's copies at full alpha)
local revealing = false
local function Reveal()
    local want = CtrlAlone()
    if want ~= revealing then
        revealing = want
        if ns.CutUpdateGhosts then ns.CutUpdateGhosts() end
    end
    -- (on a continent: the map before your clone and paint work, while held)
    if ns.ZoneArtHidePatches then ns.ZoneArtHidePatches(want and OnContinent()) end
end

-- Reveal: the zone map it would bring back, shown in the ring while you hover (the
-- picked zone's, else the one under the cursor); gone while a stroke is drawn
local lensHost, lensAt
local function UpdateLens()
    local h = active and active.host
    local x, y
    if revealMode and h and tool == "clone" and not cur and not passing and OnContinent() and catcher:IsMouseOver() then
        x, y = Cursor()
    end
    local cont = x and tonumber(active.key:sub(2))
    local z = x and (cloneSrc and cloneSrc.z or ZoneAtSpot(cont, x, y))
    local rect = z and ZoneRect(cont, z)
    local at = rect and string.format("%d %.5f %.5f %d %.2f", z, x, y, sizeIndex, look.a) or nil
    if at == lensAt and h == lensHost then return end
    if lensHost then PreviewClear(lensHost.lens) end
    lensHost, lensAt = rect and h or nil, at
    if not rect then return end
    PreviewDot(h, h.lens, { dx = 0, dy = 0, z = z, a = look.a < 1 and look.a or nil }, rect, x, y, SIZES[sizeIndex] / 2)
end

local function DragUpdate()
    if active then
        local lit
        if showFrames and OnContinent() and catcher:IsMouseOver() then
            local x, y = Cursor()
            if cloneSrc and not cloneSrc.here and tool == "clone" then
                lit = cloneSrc.z
            elseif x then
                lit = ZoneAtSpot(active.host.cont or 0, x, y)
            end
        end
        UpdateFrames(active.host, lit)
    end
    PassThrough()
    FadeEdits()
    Reveal()
    UpdateLens()
    if passing then cursorRing:Hide() stampGhost:Hide() else PlaceRing() end
    PlaceSource()
    if tool == "erase" or hoverOp then HoverErase(tool == "erase" and not passing) end
    if cur and cur.box then
        -- (the box's far corner follows the cursor)
        if not IsMouseButtonDown("LeftButton") then MouseUp() return end
        local x, y = Cursor()
        if x then
            x, y = Round(math.max(0, math.min(1, x))), Round(math.max(0, math.min(1, y)))
            local p = cur.p
            p[3], p[5], p[6], p[8] = x, x, y, y
            DrawLive()
        end
        return
    end
    if cur and cur.t == "shape" then
        -- (the shape's next side follows the cursor)
        local x, y = Cursor()
        if x then
            local p, n = cur.p, #cur.p
            p[n + 1], p[n + 2] = x, y
            DrawLive()
            p[n + 2], p[n + 1] = nil, nil
        end
        return
    end
    if not cur then return end
    if not IsMouseButtonDown("LeftButton") then MouseUp() return end
    local sx, sy = GetCursorPosition()
    -- (a new point every quarter brush on screen, at least 3 px)
    local s = UIParent:GetEffectiveScale()
    local step = math.max(3, cur.w * ScreenWidth() * 0.25)
    if math.sqrt((sx - cur.sx) ^ 2 + (sy - cur.sy) ^ 2) / s < step then return end
    local x, y = Cursor()
    if not x then return end
    cur.sx, cur.sy = sx, sy
    cur.p[#cur.p + 1] = Round(x)
    cur.p[#cur.p + 1] = Round(y)
    DrawLive()
end

-- Adjusting the last stroke ----------------------------------------------------------
-- Right after a Clone or Paint stroke, the look's buttons and keys change it too (paint
-- roughly, then nudge, turn and size it into place, the preview following): the
-- arrows move its art a pixel (Shift: ten), N and M (or [ and ], where the layout has
-- them unshifted: not Nordic ones) turn it a degree (Shift: ten),
-- , and . size it 2% (Shift: 10%). The next stroke ends it.

-- the stroke just made on this map, if it's a Clone, Paint or Stamp one
local function Selected()
    local u = undo[#undo]
    local o = u and not u.erased and active and u[1] == active.key and u[2]
    return o and (o.op == "clone" or o.op == "paint" or o.op == "stamp") and o or nil
end

local function Adjust(field, value)
    look[field] = value
    local o = Selected()
    if o and (field == "a" or o.op == "clone" or (o.op == "stamp" and field ~= "tint")) then
        local plain = { rot = 0, sc = 1, flip = false, a = 1, tint = 1 }
        if value == plain[field] then o[field] = nil else o[field] = value end
        Refresh(true)
    end
    UpdateBar()
end

-- the last Clone stroke's art moved by px, py screen pixels (its source the other way);
-- the last Stamp itself
local function Nudge(px, py)
    local o = Selected()
    if not (o and (o.op == "clone" or o.op == "stamp")) then return false end
    local h = active.host
    local s = h:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if o.op == "stamp" then
        o.p[1] = Round(o.p[1] + px / (h:GetWidth() * s))
        o.p[2] = Round(o.p[2] + py / (h:GetHeight() * s))
        Refresh(true)
        return true
    end
    o.dx = Round((o.dx or 0) - px / (h:GetWidth() * s))
    o.dy = Round((o.dy or 0) - py / (h:GetHeight() * s))
    Refresh(true)
    return true
end

local function Turn(by) Adjust("rot", ((look.rot + by) % 360 + 360) % 360) end
local function Size(by) Adjust("sc", math.max(0.25, math.min(4, math.floor((look.sc + by) * 100 + 0.5) / 100))) end

local KEYS = {
    LEFT = function(n) return Nudge(-n, 0) end, RIGHT = function(n) return Nudge(n, 0) end,
    UP = function(n) return Nudge(0, -n) end, DOWN = function(n) return Nudge(0, n) end,
    ["["] = function(n) Turn(-n) return true end, ["]"] = function(n) Turn(n) return true end,
    N = function(n) Turn(-n) return true end, M = function(n) Turn(n) return true end,
    [","] = function(n) Size(n == 10 and -0.1 or -0.02) return true end,
    ["."] = function(n) Size(n == 10 and 0.1 or 0.02) return true end,
}

local function Undo()
    if cur then CloseShape() end
    -- (the latest edit on the map open: never one on a map out of sight)
    local u
    for i = #undo, 1, -1 do
        if active and undo[i][1] == active.key then u = table.remove(undo, i) break end
    end
    if not u then
        note = "nothing to undo on this map"
        UpdateBar()
        note = nil
        return
    end
    if u.erased then
        -- (an erased edit: back in its place)
        local ops = Edits(u[1], true).ops
        table.insert(ops, math.min(u.erased, #ops + 1), u[2])
    elseif u[3] then
        -- (a stroke joined on: back to where it was)
        for i = #u[2].p, u[3] + 1, -1 do u[2].p[i] = nil end
        u[2].fill = nil
    else
        local e = Edits(u[1])
        local ops = e and e.ops or {}
        for i = #ops, 1, -1 do
            if ops[i] == u[2] then table.remove(ops, i) break end
        end
    end
    Refresh(true)
    UpdateBar()
end

local function KeyUp(_, key)
    if key == "Z" or key == "LCTRL" or key == "RCTRL" then zHeld = false end
end

local function KeyDown(self, key)
    local fn = KEYS[key]
    local handled = false
    if key == "Z" and IsControlKeyDown() and not InCombatLockdown() then
        -- (once per press: a held key repeats, and each repeat took another stroke back)
        if not zHeld then Undo() end
        zHeld, ctrlUsed = true, true
        handled = true
    elseif fn and OnContinent() and (tool == "clone" or tool == "paint" or tool == "stamp") and not InCombatLockdown() then
        handled = fn(IsShiftKeyDown() and 10 or 1)
    end
    -- (anything else goes on to the game: moving, chat, binds)
    if not InCombatLockdown() then self:SetPropagateKeyboardInput(not handled) end
end

-- The bar ------------------------------------------------------------------------

local TOOLS = {
    { "keep", "Keep", "Drag to paint map back in. To outline an area, go round it: a stroke started where the last one ended carries it on, and back at the start the inside is kept too (the closing side shows)." },
    { "cut", "Cut", "Drag to cut map away. Go round an area, as with Keep, to cut its inside too." },
    { "keepShape", "Keep shape", "Click the corners; click the first one again (or right-click) to close it. Everything inside is kept." },
    { "cutShape", "Cut shape", "Click the corners; click the first one again (or right-click) to close it. Everything inside is cut away." },
    { "clone", "Clone", "Continents: right-click a spot of a zone map to clone from (zoom in till the zone maps show), then drag to paint its art somewhere else, e.g. mountains into the land between zones. The blue marker shows the source; every stroke starts from it, and while you drag it moves along with the cursor. Go round an area in one stroke to fill it. Ctrl+right-click: in place, each stroke that zone map's own art from right under it, clean over haze or a soft edge. The sea works too (a zone map's waves): its source is the smallest zone map that reaches it. It shows as you paint, in round dots; bake it smooth: /reload, tools\\cut_edits.py, /reload.", "cont" },
    { "paint", "Paint", "Continents: paint a fill (the button beside Soft picks it): our sea in four hues, lined up with the sea fill's grain so it carries on seamlessly, or the coast's wave dashes, dense or sparse. Go round an area in one stroke to fill it; Soft feathers the edge. Newer strokes go over older ones, Clone's too. Bake as Clone's.", "cont" },
    { "stamp", "Stamp", "Continents: click to lay a mountain range, whole: one of the zone maps' own (the Mountain button picks it; tools\\mountain_stamps.py cut them out along their ranges, so their peaks end as a zone map's do, not at the brush's edge). The brush size is its width; Turn, Size, Mirror and Strength work, and right after a stamp they (and the arrow keys) change that one. Its colour: right-click a spot to take that spot's colour for every stamp (Ctrl+right-click: each stamp the colour of the zone map where it's laid; with none there, its own). Overlap a few, turned and mirrored, for a range that doesn't repeat. Bake as Clone's.", "cont" },
    { "erase", "Eraser", "Click an edit to remove it: the one under the cursor shows white (the latest, where they overlap). An outline goes round in one piece, so it goes whole; clicking inside it takes it too. Undo brings it back." },
}
local TOOL_WHERE = {}   -- [tool] = "cont": continents only; nil: (the outlines') not on continents
for _, t in ipairs(TOOLS) do TOOL_WHERE[t[1]] = t[4] end

local SizeMenu
local function Button(parent, label, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 46, 18)
    b:SetText(label)
    local fs = b:GetFontString()
    if fs then fs:SetFontObject("GameFontHighlightSmall") end
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function Tip(b, title, text)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title)
        if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
end

-- Optional views ---------------------------------------------------------------

local function ViewLabel(key)
    local e = Edits(key)
    return e and e.label or key:match("/(.+)$") or key
end

-- the views made on this map: { "v1", "v2", ... }
local function ViewsOf(base)
    local list = {}
    local all = ns.db.cutEdits and ns.db.cutEdits[ns.CutEdition()]
    for k in pairs(all or {}) do
        local b, v = k:match("^(.-)/(.+)$")
        if b == base then list[#list + 1] = v end
    end
    table.sort(list, function(a, b) return (tonumber(a:match("%d+")) or 0) < (tonumber(b:match("%d+")) or 0) end)
    return list
end

-- v nil: the map's own outline
local function SetView(base, v)
    CloseShape()
    viewOf[base] = v
    Refresh(true)
    UpdateBar()
    if ns.ApplyClearView then ns.ApplyClearView() end
end

-- the next one along: the map's own, then each view
local function NextView()
    if not active then return end
    local list = ViewsOf(active.base)
    local open = viewOf[active.base]
    local nextV = list[1]
    for i, v in ipairs(list) do
        if v == open then nextV = list[i + 1] break end
    end
    SetView(active.base, nextV)
end

local function CopyOp(o)
    local c = {}
    for k, v in pairs(o) do c[k] = v end
    c.p = { unpack(o.p) }
    return c
end

-- the view becomes the map's usual outline (the usual one's edits, then its own; an
-- own view: just its own), and the usual one a view in its place, named text, with
-- its edits as its own (own = true: baked over the map's base outline, not the usual)
local function MakeUsual(key, text)
    local base = key:match("^(.-)/")
    local v, u = Edits(key), Edits(base, true)
    if not (base and v) then return end
    local ops = {}
    if not v.own then
        for _, o in ipairs(u.ops) do ops[#ops + 1] = CopyOp(o) end
    end
    for _, o in ipairs(v.ops) do ops[#ops + 1] = CopyOp(o) end
    v.ops, u.ops = u.ops, ops
    u.ar = u.ar or v.ar
    v.ar = v.ar or u.ar
    v.own, v.label = true, text
    unbaked[key], unbaked[base] = true, true
    -- (its check box now means the old usual one: off, so the new usual shows)
    ns.db.clearView["view_" .. ns.CutName(key)] = nil
    wipe(undo)  -- (its entries point into the old lists)
    Refresh(true)
    UpdateBar()
    if ns.ApplyClearView then ns.ApplyClearView() end
end

-- data: { base = map key } a new view; { key = a view's key } renaming it;
-- { swap = a view's key } making it the usual outline
local function NameView(data, text)
    if not data or text == "" then return end
    if data.swap then MakeUsual(data.swap, text) return end
    if data.key then
        Edits(data.key, true).label = text
        UpdateBar()
        return
    end
    local n = 1
    while Edits(data.base .. "/v" .. n) do n = n + 1 end
    Edits(data.base .. "/v" .. n, true).label = text
    SetView(data.base, "v" .. n)
end

local function PopupBox(self) return self.editBox or (self.GetEditBox and self:GetEditBox()) end
local function PopupText(self)
    local eb = PopupBox(self)
    return eb and strtrim(eb:GetText() or "") or ""
end

StaticPopupDialogs["BFI_CUT_VIEW"] = {
    text = "%s",
    button1 = OKAY or "OK", button2 = CANCEL or "Cancel",
    hasEditBox = true, maxLetters = 60,
    OnShow = function(self, data)
        data = data or self.data
        local eb = PopupBox(self)
        if eb then
            eb:SetText(data and data.key and ViewLabel(data.key) or "")
            eb:HighlightText()
            eb:SetFocus()
        end
    end,
    OnAccept = function(self, data) NameView(data or self.data, PopupText(self)) end,
    EditBoxOnEnterPressed = function(eb)
        local p = eb:GetParent()
        NameView(p.data, PopupText(p))
        p:Hide()
    end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["BFI_CUT_CLEAR"] = {
    text = "Remove all your outline edits on %s?",
    button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function(_, key)
        local all = ns.db.cutEdits and ns.db.cutEdits[ns.CutEdition()]
        if all then all[key] = nil end
        local base = key:match("^(.-)/")
        if base then SetView(base, nil) return end  -- (a view: gone)
        Refresh(true)
        UpdateBar()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function PlaceName(key)
    local base = key:match("^(.-)/")
    if base then return PlaceName(base) .. ", view \"" .. ViewLabel(key) .. "\"" end
    if key:sub(1, 1) == "m" or key:sub(1, 1) == "c" then
        local info = C_Map.GetMapInfo(tonumber(key:sub(2)))
        return (info and info.name or key) .. " (" .. key:sub(2) .. ")"
    end
    return "dungeon floor " .. key
end

-- the brush sizes as a list over the size button, two columns, the one in use lit
local sizeMenu
local function SizeLabel(v)
    return string.format(v < 0.001 and "%.2f%%" or "%.1f%%", v * 100)
end
SizeMenu = function(owner)
    if sizeMenu and sizeMenu:IsShown() then sizeMenu:Hide() return end
    if not sizeMenu then
        sizeMenu = CreateFrame("Frame", nil, bar, "BackdropTemplate")
        sizeMenu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                               edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        sizeMenu:SetBackdropColor(0.08, 0.06, 0.04, 0.95)
        sizeMenu:SetBackdropBorderColor(0.75, 0.6, 0.3)
        sizeMenu:SetFrameStrata("DIALOG")
        sizeMenu:EnableMouse(true)
        sizeMenu.rows = {}
        local rows = math.ceil(#SIZES / 2)
        for i, v in ipairs(SIZES) do
            local b = CreateFrame("Button", nil, sizeMenu)
            b:SetSize(56, 14)
            b:SetPoint("TOPLEFT", sizeMenu, "TOPLEFT", 6 + math.floor((i - 1) / rows) * 58, -6 - ((i - 1) % rows) * 14)
            b:SetNormalFontObject("GameFontHighlightSmall")
            b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            b:SetText(SizeLabel(v))
            b.mark = b:CreateTexture(nil, "BACKGROUND")
            b.mark:SetAllPoints()
            b.mark:SetColorTexture(0.75, 0.6, 0.3, 0.35)
            b:SetScript("OnClick", function()
                sizeIndex = i
                sizeMenu:Hide()
                UpdateBar()
            end)
            sizeMenu.rows[i] = b
        end
        sizeMenu:SetSize(12 + 2 * 58, 12 + rows * 14)
    end
    for i, b in ipairs(sizeMenu.rows) do b.mark:SetShown(i == sizeIndex) end
    sizeMenu:ClearAllPoints()
    sizeMenu:SetPoint("BOTTOM", owner, "TOP", 0, 4)
    sizeMenu:Show()
end

local function BuildBar(area)
    bar = CreateFrame("Frame", nil, map, "BackdropTemplate")
    bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                      edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    bar:SetBackdropColor(0.08, 0.06, 0.04, 0.9)
    bar:SetBackdropBorderColor(0.75, 0.6, 0.3)
    bar:EnableMouse(true)
    bar.items = {}
    for _, t in ipairs(TOOLS) do
        local b = Button(bar, t[2], t[1]:find("Shape") and 70 or nil)
        b.tool = t[1]
        if t[1] ~= "erase" then b.where = t[4] or "map" end
        b:SetScript("OnClick", function()
            if tool ~= t[1] then CloseShape() end
            tool = t[1]
            UpdateBar()
        end)
        Tip(b, t[2], t[3])
        bar.items[#bar.items + 1] = b
    end
    local smaller = Button(bar, "-", 20)
    smaller:SetScript("OnClick", function() sizeIndex = math.max(1, sizeIndex - 1) UpdateBar() end)
    Tip(smaller, "Smaller brush")
    bar.items[#bar.items + 1] = smaller
    bar.size = Button(bar, "", 50)
    bar.size:SetScript("OnClick", function(self) SizeMenu(self) end)
    bar.size:EnableMouseWheel(true)
    bar.size:SetScript("OnMouseWheel", function(_, d)
        sizeIndex = math.max(1, math.min(#SIZES, sizeIndex + d))
        UpdateBar()
    end)
    Tip(bar.size, "Brush size", "Click for the list of sizes (of the map's width); the mouse wheel here steps through them.")
    bar.items[#bar.items + 1] = bar.size
    local bigger = Button(bar, "+", 20)
    bigger:SetScript("OnClick", function() sizeIndex = math.min(#SIZES, sizeIndex + 1) UpdateBar() end)
    Tip(bigger, "Bigger brush")
    bar.items[#bar.items + 1] = bigger
    bar.soft = Button(bar, "Soft", 40)
    bar.soft:SetScript("OnClick", function() cloneSoft = not cloneSoft UpdateBar() end)
    Tip(bar.soft, "Soft edge", "Clone strokes made while it's on get a wide feathered edge when baked (about a third of the brush), so they melt into what's round them: for sea into sea, or breaking up a straight seam. Off: a crisp edge, for coasts and mountains. The preview looks the same either way.")
    bar.soft.where = "cont"
    bar.items[#bar.items + 1] = bar.soft
    bar.box = Button(bar, "Box", 36)
    bar.box:SetScript("OnClick", function() boxBrush = not boxBrush UpdateBar() end)
    Tip(bar.box, "Box", "Clone and Paint lay a rectangle: drag from one corner to the other. Its edges stay straight, for tight spots by a zone map's border, where a round brush picks up the frame. The brush size sets how soft its edge is baked (smallest: crisp); Soft feathers it wide. Click again for the round brush.")
    bar.box.where = "cont"
    bar.items[#bar.items + 1] = bar.box
    bar.base = Button(bar, "Base", 40)
    bar.base:SetScript("OnClick", function() cloneBase = not cloneBase UpdateBar() end)
    Tip(bar.base, "Base art", "Clone takes the zone map's base art alone: its land as it looks unexplored (plain parchment, mountains, rivers, the coast's hatching), without the explored areas' colour. For land no zone map covers, like Quel'Thalas. Shows in the preview as it will bake. Not with Reveal.")
    bar.base.where = "cont"
    bar.items[#bar.items + 1] = bar.base
    bar.reveal = Button(bar, "Reveal", 50)
    bar.reveal:SetScript("OnClick", function()
        revealMode = not revealMode
        CloseShape()
        tool = "clone"
        cloneSrc = revealMode and { here = true } or nil
        UpdateBar()
    end)
    Tip(bar.reveal, "Reveal", "Paint a zone map back in over haze, a soft edge or your own earlier strokes: each stroke shows the zone map under where it starts (right-click a spot first to keep to that zone, e.g. by a border). The bake makes it part of the zone's own mask, so it costs nothing to draw or ship, and it clears your earlier strokes under it. Strength and Soft work; Turn, Size, Mirror and Tint don't. While you hover, the ring shows the zone map it would bring back. Same as Clone in place (Ctrl+right-click). Click again for the plain Clone brush.")
    bar.reveal.where = "cont"
    bar.items[#bar.items + 1] = bar.reveal
    bar.frames = Button(bar, "Frames", 50)
    bar.frames:SetScript("OnClick", function() showFrames = not showFrames UpdateBar() end)
    Tip(bar.frames, "Zone frames", "Outlines each zone map while you Clone or Paint: gold where its art ends, red where its burnt frame begins inside it. Blend up to the red line, not past it. The zone the brush takes from (under the cursor; the source's with a picked source) shows brighter. Click to hide them.")
    bar.frames.where = "cont"
    bar.items[#bar.items + 1] = bar.frames
    bar.mat = Button(bar, "", 110)
    bar.mat:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bar.mat:SetScript("OnClick", function(_, button)
        local n = #(ns.PAINT_NAMES or { 1 })
        paintMat = (paintMat - 1 + (button == "RightButton" and n - 1 or 1)) % n + 1
        if tool ~= "paint" then CloseShape() tool = "paint" end
        UpdateBar()
    end)
    Tip(bar.mat, "Paint fill", "What the Paint brush lays: click for the next, right-click for the one before. Sea warm, cool, deep or pale (our sea texture in the continent's colours); the coast's wave dashes, dense or sparse (over what's there); Sea, matched (tinted to the nearest zone map's own sea); or Colour, picked: right-click a spot on the map to pick its colour (its paper's, the lines left out), then paint it as a flat wash. At 25-50% strength it shifts the tone under it and leaves the lines showing: for blending a compass rose's colours into the sea round it.")
    bar.swatch = bar.mat:CreateTexture(nil, "OVERLAY")
    bar.swatch:SetSize(10, 10)
    bar.swatch:SetPoint("RIGHT", bar.mat, "RIGHT", -5, 0)
    bar.swatch:SetColorTexture(1, 1, 1)
    bar.mat.where = "cont"
    bar.items[#bar.items + 1] = bar.mat
    bar.piece = Button(bar, "", 96)
    bar.piece:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local function NextPiece(by)
        local n = ns.MountainStamps and #ns.MountainStamps or 1
        stampPiece = (stampPiece - 1 + by) % n + 1
        if tool ~= "stamp" then CloseShape() tool = "stamp" end
        UpdateBar()
    end
    bar.piece:SetScript("OnClick", function(_, button) NextPiece(button == "RightButton" and -1 or 1) end)
    bar.piece:EnableMouseWheel(true)
    bar.piece:SetScript("OnMouseWheel", function(_, d) NextPiece(-d) end)
    Tip(bar.piece, "Mountain", "Which mountain range the Stamp brush lays: click for the next, right-click (or the mouse wheel here) for the one before. Hover the map to see it under the cursor.")
    bar.piece.where = "cont"
    bar.items[#bar.items + 1] = bar.piece
    -- the look (Clone: all; Paint: strength)
    local function LookButton(key, w, tip, onClick)
        local b = Button(bar, "", w)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(_, button) onClick(button == "RightButton") end)
        Tip(b, tip[1], tip[2])
        b.where = "cont"
        bar[key] = b
        bar.items[#bar.items + 1] = b
    end
    LookButton("turn", 64, { "Turn", "Clone and Stamp: how far the art is turned where it's laid. Click +15°, right-click -15°; N and M (or [ and ]) turn a degree (Shift: ten). Right after a stroke, it turns that stroke too. At a quarter turn it's exact; at other angles a faint seam can show where the source map's art tiles meet." },
        function(back) Turn(back and -15 or 15) end)
    LookButton("scale", 64, { "Size", "Clone and Stamp: the art's size where it's laid. Click +5%, right-click -5%; , and . size 2% (Shift: 10%). Right after a stroke, that stroke too." },
        function(back) Size(back and -0.05 or 0.05) end)
    LookButton("flip", 50, { "Mirror", "Clone and Stamp: the art mirrored left to right (before it's turned). Right after a stroke, that stroke too." },
        function() Adjust("flip", not look.flip) end)
    LookButton("str", 84, { "Strength", "Clone, Paint and Stamp: how strongly the stroke lays its art: 100, 75, 50 or 25%. Lower ones blend seams and tones. Click for the next, right-click back. Right after a stroke, that stroke too." },
        function(back)
            local i = 1
            for k, v in ipairs(STRENGTHS) do if v == look.a then i = k end end
            i = (i - 1 + (back and #STRENGTHS - 1 or 1)) % #STRENGTHS + 1
            Adjust("a", STRENGTHS[i])
        end)
    LookButton("tint", 96, { "Tint", "Clone: the art's colours shifted a little, to match where it's laid: warmer, cooler, darker. Click for the next, right-click back. Right after a stroke, that stroke too." },
        function(back)
            local n = #(ns.CLONE_TINTS or { 1 })
            Adjust("tint", (look.tint - 1 + (back and n - 1 or 1)) % n + 1)
        end)
    bar.peek = Button(bar, "Peek")
    bar.peek:SetScript("OnClick", function()
        peeking = not peeking
        UpdateBar()
        if ns.ApplyClearView then ns.ApplyClearView() end
    end)
    Tip(bar.peek, "Peek", "The map that's cut away, shown faintly round the cut, so you can trace along it with Keep. Click again to hide it. Hold Ctrl to see the whole map for a moment.")
    bar.peek.where = "map"
    bar.items[#bar.items + 1] = bar.peek
    bar.edits = Button(bar, "", 92)
    bar.edits:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bar.edits:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            showBaked = not showBaked
            Refresh(true)
        else
            editsShown = editsShown % #EDIT_ALPHAS + 1
        end
        UpdateBar()
    end)
    Tip(bar.edits, "Your edits", "How your green and red strokes show over the map: shown, faint or hidden, to see the map under them while you correct them. Hold Alt to hide them for a moment. With Peek on too, you see the whole map: what's kept, and the cut-away part faintly.\n\nEdits already baked into the outline aren't drawn (the outline shows them): right-click to draw them too, to erase one.")
    bar.items[#bar.items + 1] = bar.edits
    bar.view =Button(bar, "", 130)
    bar.view:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bar.view:SetScript("OnClick", function(_, button)
        if not active then return end
        if button == "RightButton" then
            if active.key ~= active.base then
                StaticPopup_Show("BFI_CUT_VIEW", "A new name for this view:", nil, { key = active.key })
            end
            return
        end
        NextView()
    end)
    Tip(bar.view, "View", "Which outline you're editing: the map's usual one, or one of its optional views. Click for the next one, right-click to rename a view. A view's edits go over the usual outline; once baked, it's a check box on the Clear view page, in place of the usual outline when ticked.")
    bar.view.where = "map"
    bar.items[#bar.items + 1] = bar.view
    local newView = Button(bar, "New view", 64)
    newView:SetScript("OnClick", function()
        if active then
            StaticPopup_Show("BFI_CUT_VIEW", "Name the new view of " .. PlaceName(active.base)
                .. " (its check box on the Clear view page):", nil, { base = active.base })
        end
    end)
    Tip(newView, "New view", "A second outline for this map, e.g. Elwynn Forest without Stormwind. It starts as the usual outline: cut or keep from there. Players pick it with its check box on the Clear view page.")
    newView.where = "map"
    bar.items[#bar.items + 1] = newView
    bar.swap = Button(bar, "Make usual", 70)
    bar.swap:SetScript("OnClick", function()
        if active and active.key ~= active.base then
            StaticPopup_Show("BFI_CUT_VIEW", "\"" .. ViewLabel(active.key) .. "\" becomes the usual outline of "
                .. PlaceName(active.base) .. ". Name the usual one, now a view in its place:", nil, { swap = active.key })
        end
    end)
    Tip(bar.swap, "Make usual", "This view becomes the map's usual outline (what clear view shows by default), and the usual one becomes a view with its own check box, under the name you give it. Bake afterwards as usual. Clears Undo.")
    bar.swap.where = "map"
    bar.items[#bar.items + 1] = bar.swap
    local undoBtn = Button(bar, "Undo")
    undoBtn:SetScript("OnClick", Undo)
    Tip(undoBtn, "Undo", "Takes back your last edit (the last stroke of an outline). Ctrl+Z too.")
    bar.items[#bar.items + 1] = undoBtn
    local clear = Button(bar, "Clear map", 64)
    clear:SetScript("OnClick", function()
        if active then StaticPopup_Show("BFI_CUT_CLEAR", PlaceName(active.key), nil, active.key) end
    end)
    Tip(clear, "Clear map", "Removes all your edits on this map (or dungeon floor). On a view: the view itself.")
    bar.items[#bar.items + 1] = clear
    local done = Button(bar, "Done")
    done:SetScript("OnClick", function() ns.ToggleCutEdit(false) end)
    Tip(done, "Done", "Close the outline editor. To bake your edits into the outlines: /reload, then run python -I tools\\cut_edits.py.")
    bar.items[#bar.items + 1] = done
    bar.status = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.status:SetJustifyH("LEFT")
    bar:Hide()

    cursorRing = catcher:CreateTexture(nil, "OVERLAY")
    cursorRing:SetTexture(CIRCLE)
    cursorRing:SetVertexColor(1, 1, 1, 0.25)
    cursorRing:Hide()
    stampGhost = catcher:CreateTexture(nil, "OVERLAY")
    stampGhostMask = catcher:CreateMaskTexture()
    stampGhostMask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    stampGhost:AddMaskTexture(stampGhostMask)
    stampGhost:Hide()
    srcRing = catcher:CreateTexture(nil, "OVERLAY")
    srcRing:SetTexture(CIRCLE)
    srcRing:SetVertexColor(COLORS.clone[1], COLORS.clone[2], COLORS.clone[3], 0.35)
    srcRing:Hide()
end

-- flowed in rows, the status line above them; outside the map, under it (over it
-- when there's no room below), so it never covers what you're outlining
local function LayoutBar()
    local area = map.ScrollContainer or map
    local maxW = math.max(320, (area:GetWidth() or 300) - 8)
    local x, y, rowH, widest = 6, -20, 18, 0
    for _, b in ipairs(bar.items) do
        local w = b:IsShown() and b:GetWidth()  -- (a hidden one takes no room)
        if w then
            if x + w > maxW and x > 6 then
                x, y = 6, y - rowH - 3
            end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", bar, "TOPLEFT", x, y - (rowH - b:GetHeight()) / 2)
            x = x + w + 3
            widest = math.max(widest, x)
        end
    end
    widest = math.max(widest, math.min(maxW, bar.status:GetStringWidth() + 12))
    bar.status:ClearAllPoints()
    bar.status:SetPoint("TOPLEFT", bar, "TOPLEFT", 7, -6)
    bar.status:SetWidth(widest - 10)
    bar:SetSize(widest + 3, -y + rowH + 6)
    bar:ClearAllPoints()
    local bottom = map:GetBottom()
    if bottom and bottom < bar:GetHeight() + 8 then
        bar:SetPoint("BOTTOM", map, "TOP", 0, 4)
    else
        bar:SetPoint("TOP", map, "BOTTOM", 0, -4)
    end
    bar:SetFrameLevel(ns.ButtonLevel(map) - 2)
end

UpdateBar = function()
    if not bar then return end
    -- (a continent: the Clone brush, not the outline tools)
    local onCont = OnContinent() and true or false
    if onCont ~= (TOOL_WHERE[tool] == "cont") and tool ~= "erase" then
        CloseShape()
        tool = onCont and "clone" or "keep"
    end
    for _, b in ipairs(bar.items) do
        if b.where then b:SetShown((b.where == "cont") == onCont) end
        if b.tool then
            if b.tool == tool then b:LockHighlight() else b:UnlockHighlight() end
        end
    end
    if peeking then bar.peek:LockHighlight() else bar.peek:UnlockHighlight() end
    if cloneSoft then bar.soft:LockHighlight() else bar.soft:UnlockHighlight() end
    if boxBrush then bar.box:LockHighlight() else bar.box:UnlockHighlight() end
    if revealMode and not (tool == "clone" and cloneSrc and cloneSrc.here) then revealMode = false end
    if revealMode then bar.reveal:LockHighlight() else bar.reveal:UnlockHighlight() end
    if cloneBase then bar.base:LockHighlight() else bar.base:UnlockHighlight() end
    if showFrames then bar.frames:LockHighlight() else bar.frames:UnlockHighlight() end
    bar.mat:SetText((ns.PAINT_NAMES and ns.PAINT_NAMES[paintMat]) or "Sea")
    bar.piece:SetText(string.format("Mountain %d/%d", stampPiece, ns.MountainStamps and #ns.MountainStamps or 0))
    -- (the picked colour, on the Colour fill)
    local showSwatch = paintMat == ns.PAINT_COLOUR and paintRGB
    if showSwatch then bar.swatch:SetColorTexture(paintRGB[1], paintRGB[2], paintRGB[3]) end
    bar.swatch:SetShown(showSwatch and true or false)
    bar.turn:SetText(string.format("Turn %d°", look.rot))
    bar.scale:SetText(string.format("Size %d%%", look.sc * 100 + 0.5))
    if look.flip then bar.flip:LockHighlight() else bar.flip:UnlockHighlight() end
    bar.str:SetText(string.format("Strength %d%%", look.a * 100))
    local tn = ns.CLONE_TINTS and ns.CLONE_TINTS[look.tint]
    bar.tint:SetText("Tint: " .. (tn and tn[4] or "none"))
    bar.size:SetText(SizeLabel(SIZES[sizeIndex]))
    local label = active and active.key ~= active.base and ViewLabel(active.key)
    if label and #label > 16 then label = label:sub(1, 15) .. "..." end
    bar.view:SetText("View: " .. (label or "usual"))
    bar.swap:SetEnabled(label and true or false)
    bar.edits:SetText("Edits: " .. EDIT_ALPHAS[editsShown][2] .. (showBaked and " +" or ""))
    if editsShown > 1 then bar.edits:LockHighlight() else bar.edits:UnlockHighlight() end
    FadeEdits()
    if active then
        local e = Edits(active.key)
        local n = e and #e.ops or 0
        local has
        if onCont then
            local info = cloneSrc and cloneSrc.z and C_Map.GetMapInfo(cloneSrc.z)
            if tool == "stamp" then
                has = note or (paintRGBFrom and ("stamping in the colour of " .. paintRGBFrom .. " (Ctrl+right-click: each spot's own)")
                    or "stamping in each spot's own colour (right-click a spot to pick one)")
            elseif tool == "paint" and paintMat == ns.PAINT_COLOUR then
                has = note or (paintRGBFrom and ("colour picked from " .. paintRGBFrom) or "right-click a spot to pick its colour")
            elseif cloneSrc and cloneSrc.here and not cloneSrc.z then
                has = note or "revealing the zone map under each stroke (right-click to keep to one)"
            else
                local name = info and info.name or (cloneSrc and "zone " .. cloneSrc.z)
                has = note or (name and ((cloneSrc.here and "in place from " or "cloning from ") .. name))
                    or "right-click a zone map spot to clone from"
            end
        else
            has = ns.CutFile(ns.CutName(active.key)) and "has an outline" or "no outline yet"
        end
        bar.status:SetText(PlaceName(active.key) .. ": " .. has .. ", " .. n .. (n == 1 and " edit" or " edits")
            .. " |cff999999(bake: /reload, tools\\cut_edits.py)|r")
    else
        bar.status:SetText("Not a map that can be cut")
    end
    LayoutBar()
end

local function PlaceCatcher()
    if not (catcher and active) then return end
    local area = map.ScrollContainer or map
    catcher:SetAllPoints(area)
    catcher:SetFrameLevel(active.level)
end

function ns.ToggleCutEdit(on)
    if not map then return end
    if on == nil then on = not editing end
    if on and not map:IsShown() and ToggleBattlefieldMap then ToggleBattlefieldMap() end
    if on and ns.InkDrawing and ns.InkDrawing() then ns.ToggleInkBar(false) end
    editing = on and true or false
    peeking = false
    wipe(viewOf)  -- (each time: the usual outlines first)
    cur = nil
    passing = false
    catcher:EnableMouse(true)
    Refresh(true)
    if editing then
        PlaceCatcher()
        catcher:Show()
        UpdateBar()
        bar:Show()
    else
        catcher:Hide()
        bar:Hide()
        cursorRing:Hide()
        srcRing:Hide()
        if ns.ZoneArtHidePatches then ns.ZoneArtHidePatches(false) end  -- (closed with Ctrl held)
    end
    if ns.ApplyClickThrough then ns.ApplyClickThrough() end
    if ns.ApplyClearView then ns.ApplyClearView() end
end

-- a snapshot of the edits to take back (tools\cut_edits.py --restore, Data\CutRestore.lua):
-- taken in once, the edits it replaces kept aside (cutEditsBeforeRestore)
local function TakeRestore()
    local r = ns.CutRestore
    if not (r and r.stamp and r.edits) or ns.db.cutRestored == r.stamp then return end
    ns.db.cutEdits = ns.db.cutEdits or {}
    ns.db.cutEditsBeforeRestore = {}
    for ed, maps in pairs(r.edits) do
        ns.db.cutEditsBeforeRestore[ed] = ns.db.cutEdits[ed]
        ns.db.cutEdits[ed] = maps
    end
    ns.db.cutRestored = r.stamp
    print("|cffffd200Waymark:|r outline, clone and paint edits taken back to the snapshot of "
        .. r.stamp .. ". /reload, then bake (tools\\cut_edits.py).")
end

function ns.SetupCutEdit(m)
    map = m
    ns.Safe("CutEdit restore", TakeRestore)
    zoneHost = MakeHost(map:GetCanvas())
    zoneHost:Hide()
    local area = map.ScrollContainer or map

    catcher = CreateFrame("Frame", nil, area)
    catcher:EnableMouse(true)
    catcher:EnableMouseWheel(false)  -- (the wheel goes on to the map: zoom while editing)
    if area.HookScript then
        area:HookScript("OnMouseWheel", function() if IsControlKeyDown() then ctrlUsed = true end end)
    end
    catcher:SetScript("OnMouseDown", function(_, button) MouseDown(button) end)
    -- (the adjusting keys on a continent; every other key goes on to the game)
    catcher:EnableKeyboard(true)
    catcher:SetPropagateKeyboardInput(true)
    catcher:SetScript("OnKeyDown", KeyDown)
    catcher:SetScript("OnKeyUp", KeyUp)
    catcher:SetScript("OnMouseUp", function() MouseUp() end)
    catcher:SetScript("OnUpdate", DragUpdate)
    catcher:SetScript("OnLeave", function() cursorRing:Hide() srcRing:Hide() end)
    catcher:Hide()
    BuildBar(area)
    area:HookScript("OnSizeChanged", function() if bar:IsShown() then LayoutBar() end end)
    map:HookScript("OnHide", function() if editing then ns.ToggleCutEdit(false) end end)

    -- the map, the dungeon floor: checked a few times a second while editing
    C_Timer.NewTicker(0.25, ns.Timed("CutEdit tick", function()
        if not (editing and map:IsVisible()) then return end
        Refresh()
        PlaceCatcher()
    end))
end
