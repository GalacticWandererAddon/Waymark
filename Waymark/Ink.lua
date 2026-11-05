local _, ns = ...

-- Map ink: your own routes, marks and notes, drawn on the map as ink soaked
-- into the parchment (an explorer's markings), not icons on top of it.
--   - Shown on whatever the Battlefield Map shows: zone and continent maps,
--     caves, and our dungeon maps (Dungeon.lua), per map and floor:
--     ns.db.inkMarks[key] = { mark, ... }, key "m<uiMapID>" or "d<instance>:<floor>".
--   - A mark: { t = kind, v = version, ink = 1-3, r = seed, p = { x1, y1, ... }
--     (0-1 across the map), s = text, f = hand, note = tooltip, sc = its own
--     size, q = 2: the feathered quill's look }. Kinds: pen, route, wander,
--     pass (passage), tracks (a dog's paw prints), x, ring, q (?), bang (!), stairs,
--     jump, lock, chest, blot (spilt ink), text (f: its hand; "apple" is the whispers').
--   - Only that is saved: how a mark looks is worked out each time it's drawn,
--     so the look can change later and every mark you made follows.
--   - Drawn with Line objects through our brush (Media\InkBrush, round dots
--     through Media\InkDot; tools\ink_brush.py) on a frame on the map's canvas,
--     so it pans and zooms with the art. Started in mockups/map-ink.html; the
--     hand-drawn shapes are Data\InkGlyphs.lua. The seed keeps a mark's wobble
--     the same every time it's drawn.
--   - Drawing: the quill (shift-click the ink toggle button, /bfi ink, or a key),
--     the found notes' one (Notebook.lua): one bar for the book and the map.
--     While it's in hand, left-drag draws instead of panning; the wheel still
--     zooms. Drag a mark to move it (any tool but the path tools and rub out);
--     right-click it: rewrite, bigger, smaller, a tooltip, rub it out. Shift-click
--     a mark: its tooltip (marks with one show it on hover). Ctrl + wheel over
--     one: its size. New notes in the notebook's hands.

local function Cfg() return ns.db.ink end

local MEDIA = ns.MEDIA
local BRUSH = MEDIA .. "InkBrush"
local DOT = MEDIA .. "InkDot"  -- (the dots of ? and !: a short line would be a sliver)
-- sepia, red, blue-black
local INKS = { { 0.27, 0.16, 0.07 }, { 0.53, 0.16, 0.10 }, { 0.15, 0.19, 0.25 },  -- (sepia darkened 2026-10-30: read on the maps)
               { 0.31, 0.33, 0.19 }, { 0.24, 0.22, 0.20 } }  -- (4: Ewen's olive grey-green (2026-10-31: less blue on the warm paper), 5: Tam's charcoal from the fire)
-- the whispers' words (hand "apple") are never in anyone's ink: a violet-black of their own, bleeding a little
local WHISPER, WHISPER_BLEED = { 0.30, 0.10, 0.36 }, { 0.58, 0.30, 0.66, 0.45 }
ns.WHISPER_INK = WHISPER
local NOTE_COLOR = { 0.93, 0.82, 0.6 }
-- the hands for notes: key, name, file, size factor (the game's Morpheus, and
-- handwriting fonts we ship, OFL but Homemade Apple's Apache 2.0; their
-- licences in LICENSES\). Nothing You Could Do: Homemade Apple's look, less
-- joined up; Reenie Beanie: a rougher scrawl than Shadows Into Light.
local HANDS = {
    { "morpheus", "Morpheus", "Fonts\\MORPHEUS.ttf", 1.15 },
    { "kalam", "Kalam", MEDIA .. "Fonts\\Kalam-Regular.ttf", 1.0 },
    { "apple", "Homemade Apple", MEDIA .. "Fonts\\HomemadeApple-Regular.ttf", 0.8 },
    { "nothing", "Nothing You Could Do", MEDIA .. "Fonts\\NothingYouCouldDo.ttf", 1.0 },
    { "shadows", "Shadows Into Light", MEDIA .. "Fonts\\ShadowsIntoLight.ttf", 1.2 },
    { "reenie", "Reenie Beanie", MEDIA .. "Fonts\\ReenieBeanie.ttf", 1.35 },
}
ns.INK_HANDS = HANDS
local function Hand(key)
    for _, h in ipairs(HANDS) do if h[1] == key then return h end end
    return HANDS[1]
end

-- Building: a mark -> strokes of { x, y, w } in canvas units -----------------

local function Rng(seed)
    local s = (seed or 1) % 2147483646 + 1
    return function()
        s = s * 16807 % 2147483647
        return s / 2147483647
    end
end

local function Catmull(pts, n)
    n = n or 4
    if #pts < 3 then
        local out = {}
        for i, p in ipairs(pts) do out[i] = { p[1], p[2], p[3], p[4] } end
        return out
    end
    local out, no = {}, 0
    local np = #pts
    for i = 1, np - 1 do
        local p0, p1, p2, p3 = pts[i > 1 and i - 1 or 1], pts[i], pts[i + 1], pts[i + 2 <= np and i + 2 or np]
        local ax, bx, cx, dx = p0[1], p1[1], p2[1], p3[1]
        local ay, by, cy, dy = p0[2], p1[2], p2[2], p3[2]
        for k = 0, n - 1 do
            local t = k / n
            local t2, t3 = t * t, t * t * t
            no = no + 1
            out[no] = { 0.5 * (2 * bx + (-ax + cx) * t + (2 * ax - 5 * bx + 4 * cx - dx) * t2 + (-ax + 3 * bx - 3 * cx + dx) * t3),
                        0.5 * (2 * by + (-ay + cy) * t + (2 * ay - 5 * by + 4 * cy - dy) * t2 + (-ay + 3 * by - 3 * cy + dy) * t3),
                        p1[3] + (p2[3] - p1[3]) * t }
        end
    end
    local last = pts[#pts]
    out[#out + 1] = { last[1], last[2], last[3] }
    return out
end

-- (mid: the glyph's middle in its own units; ?/! run 0-0.9 down, an X is drawn round 0)
local function Glyph(g, cx, cy, G, r, mid)
    mid = mid or 0.4
    local out = {}
    for _, st in ipairs(g.strokes) do
        local pts = {}
        for i, q in ipairs(st) do
            local x, y = q[1], q[2]
            pts[i] = { cx + (x - (y - mid) * g.slant + (r() - 0.5) * 0.05) * G, cy + (y - mid + (r() - 0.5) * 0.05) * G, q[3] }
        end
        out[#out + 1] = Catmull(pts)
    end
    return out
end

-- a hand-drawn glyph's strokes for other layers (quest ground's X): { { {x, y, width}, ... } }
-- round cx, cy at G px a glyph unit; v picks the drawing (wraps), seed its wobble
function ns.InkGlyphStrokes(kind, v, cx, cy, G, seed)
    local list = (ns.INK_GLYPHS or {})[kind]
    if not (list and #list > 0) then return nil end
    return Glyph(list[(v - 1) % #list + 1], cx, cy, G, Rng(seed), 0)
end

local function Ring(v, cx, cy, G, r)
    local out, n, ph = {}, 44, r() * 6
    local cr, sr = math.cos(v.rot), math.sin(v.rot)
    for i = 0, n do
        local t = i / n
        local a = v.a0 + v.sweep * t
        local k = 1 + v.grow * t + math.sin(a * v.wf + ph) * v.wob
        local x, y = math.cos(a) * v.rx * k, math.sin(a) * v.ry * k
        local w = t < 0.15 and 0.7 + t * 2.4 or t > 0.85 and 1.05 - (t - 0.85) * 3 or 1.05
        out[#out + 1] = { cx + (x * cr - y * sr) * G, cy + (x * sr + y * cr) * G, w }
    end
    return { out }
end

-- along a path by distance: step(true) gives the first distance, then
-- step(false, x, y, angle) is called there and gives the next
local function Walk(pts, step)
    local want, have = step(true), 0
    for i = 2, #pts do
        local x0, y0, x1, y1 = pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2]
        local d = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
        local at = 0
        while have + d - at >= want do
            at = at + want - have
            have = 0
            local t = at / d
            want = step(false, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, math.atan2(y1 - y0, x1 - x0))
        end
        have = have + d - at
    end
end

local function Chevron(out, x, y, a, len)
    out[#out + 1] = { { x - math.cos(a - 0.5) * len, y - math.sin(a - 0.5) * len, 0.7 }, { x, y, 1 } }
    out[#out + 1] = { { x - math.cos(a + 0.55) * len * 0.85, y - math.sin(a + 0.55) * len * 0.85, 0.7 }, { x, y, 1 } }
end

-- pen down / pen up along the path, by distance
local function Dashes(pts, k, r, dMin, dMax, gMin, gMax, w)
    local out, down, cur = {}, true, nil
    Walk(pts, function(first, x, y)
        if not first then
            if down then
                cur = { { x, y, w } }
            elseif cur then
                cur[2] = { x, y, w * 0.8 }
                out[#out + 1] = cur
                cur = nil
            end
            down = not down
        end
        if down then return (gMin + r() * (gMax - gMin)) * k end
        return (dMin + r() * (dMax - dMin)) * k
    end)
    return out
end

-- the feathered quill: a broad nib held at a slant, so strokes are thick across
-- it and hairline along it; a drop of ink at the start, running drier on the way
local NIB = -0.7
local function Feather(P, k, r)
    local s = Catmull(P, 2)
    local run, total = 0, 0
    for i = 2, #s do total = total + math.sqrt((s[i][1] - s[i - 1][1]) ^ 2 + (s[i][2] - s[i - 1][2]) ^ 2) end
    for i = 1, #s do
        local a = s[math.min(#s, i + 1)]
        local b = s[math.max(1, i - 1)]
        if i > 1 then run = run + math.sqrt((s[i][1] - s[i - 1][1]) ^ 2 + (s[i][2] - s[i - 1][2]) ^ 2) end
        local ang = math.atan2(a[2] - b[2], a[1] - b[1])
        local w = 0.3 + 1.35 * math.abs(math.sin(ang - NIB))
        local ends = math.min(1, (i - 1) / 3, (#s - i) / 3)  -- (lifted in and out)
        s[i][3] = w * (0.45 + 0.55 * ends) * (0.92 + r() * 0.16)
        s[i][4] = 1 - 0.4 * math.min(1, run / math.max(220 * k, total))  -- (the nib drying)
    end
    local out = { s }
    if #s > 1 then out[2] = { { s[1][1], s[1][2], 1.9 }, { s[1][1] + 0.01, s[1][2], 1.9 } } end  -- the drop
    return out
end

-- a mark's own size (ctrl + wheel while drawing): its points spread from their
-- middle; a single-point mark grows instead
local function Scaled(P, sc)
    if sc == 1 or #P < 2 then return end
    local cx, cy = 0, 0
    for _, p in ipairs(P) do cx, cy = cx + p[1], cy + p[2] end
    cx, cy = cx / #P, cy / #P
    for _, p in ipairs(P) do p[1], p[2] = cx + (p[1] - cx) * sc, cy + (p[2] - cy) * sc end
end

-- a scene piece as one mark (the notebook's "before" pages): Data\InkScenes.lua's strokes round
-- the mark's spot, u pixels to a scene unit (a scene is 360 across), so it moves, sizes and rubs
-- out whole (wide pieces are placed at 0, 0)
local function SketchStrokes(m, x, y, u, r)
    local piece = ns.INK_SCENES and ns.INK_SCENES[m.piece]
    local out = {}
    -- (drawn, not ruled: long straight runs are broken into short steps that wander a little off the
    -- line and back, as a pen does; the width breathes along it)
    for _, st in ipairs(piece and piece.strokes or {}) do
        local pts, walk, wid = {}, 0, 0.85 + r() * 0.3
        local function Put(px, py, nx, ny)
            walk = walk * 0.75 + (r() - 0.5) * 0.9
            wid = math.max(0.7, math.min(1.2, wid + (r() - 0.5) * 0.12))
            pts[#pts + 1] = { x + (px + nx * walk) * u, y + (py + ny * walk) * u, wid }
        end
        for i = 1, #st - 1, 2 do
            local ax, ay = st[i], st[i + 1]
            local bx, by = st[i + 2], st[i + 3]
            if bx then
                local dx, dy = bx - ax, by - ay
                local len = math.sqrt(dx * dx + dy * dy)
                local nx, ny = len > 0 and -dy / len or 0, len > 0 and dx / len or 0
                local steps = math.max(1, math.floor(len / 5))
                for k = 0, steps - 1 do Put(ax + dx * k / steps, ay + dy * k / steps, nx, ny) end
            else
                Put(ax, ay, 0, 0)
            end
        end
        out[#out + 1] = Catmull(pts, 2)
    end
    return out
end
-- how far a point is from a sketch's strokes (px, on a host w x h)
function ns.InkSketchDist(m, w, h, cx, cy)
    local piece = ns.INK_SCENES and ns.INK_SCENES[m.piece]
    local u, x0, y0 = w / 360 * (m.sc or 1), m.p[1] * w, m.p[2] * h
    local d = math.huge
    for _, st in ipairs(piece and piece.strokes or {}) do
        local p = {}
        for i = 1, #st - 1, 2 do
            p[#p + 1] = (x0 + st[i] * u) / w
            p[#p + 1] = (y0 + st[i + 1] * u) / h
        end
        d = math.min(d, ns.InkPathDist(p, w, h, cx, cy))
    end
    return d
end

-- Rubbing out only what's under the rubber (radius px, on a host w x h; x, y 0-1): a drawn line
-- (pen, route, wanders, paw tracks) loses the stretch under it and goes on as the pieces either
-- side; a scene piece (sketch) first comes apart into its strokes; a small mark or written words
-- under it go whole. Changes the list in place; true when something went.
-- (paw prints' size on a map: the whole print and its dots; 0.8 started a little large)
local TRACK_PRINT = 0.65
local LINES = { pen = true, route = true, wander = true, tracks = true }
local function Strokes(m, w, h)  -- (a sketch's strokes as pen marks, 0-1 on the host)
    local piece = ns.INK_SCENES and ns.INK_SCENES[m.piece]
    local u, out = w / 360 * (m.sc or 1), {}
    for j, st in ipairs(piece and piece.strokes or {}) do
        local p = {}
        for i = 1, #st - 1, 2 do
            p[#p + 1] = (m.p[1] * w + st[i] * u) / w
            p[#p + 1] = (m.p[2] * h + st[i + 1] * u) / h
        end
        out[#out + 1] = { t = "pen", ink = m.ink, r = ((m.r or 1) + j * 31) % 2000000000 + 1, p = p }
    end
    return out
end
function ns.InkErase(list, x, y, w, h, radius)
    local cx, cy = x * w, y * h
    local changed, i = false, 1
    while i <= #list do
        local m = list[i]
        local near = (m.t == "sketch" and ns.InkSketchDist(m, w, h, cx, cy) or ns.InkPathDist(m.p, w, h, cx, cy)) < radius * 1.5
        if near and m.t == "sketch" then
            table.remove(list, i)
            for k, s in ipairs(Strokes(m, w, h)) do table.insert(list, i + k - 1, s) end
            changed = true
            m = list[i]
        end
        -- (a trail's ending, what the dog did there, lies past its last point: rubbed there, the ending
        -- goes and the trail stays; cutting the trail moved the ending back along it, out of reach)
        local tip
        if m and m.t == "tracks" and m.gait and m.gait ~= "run" and #m.p >= 4 then
            local n, kk = #m.p, w / 1002 * (m.sc or 1) * TRACK_PRINT
            local ex, ey = m.p[n - 1] * w, m.p[n] * h
            local bx, by = m.p[n - 3] * w, m.p[n - 2] * h
            local d = math.max(0.001, math.sqrt((ex - bx) ^ 2 + (ey - by) ^ 2))
            local mx, my = ex + (ex - bx) / d * 18 * kk, ey + (ey - by) / d * 18 * kk
            tip = math.sqrt((cx - mx) ^ 2 + (cy - my) ^ 2) < radius + 20 * kk
        end
        if tip then
            m.gait = nil
            changed = true
            i = i + 1
        elseif m and LINES[m.t] and #m.p >= 4 and near then
            -- (its points, a stretch at most half the rubber apart, so the cut is clean)
            local pts, step = {}, radius * 0.5
            for j = 1, #m.p - 1, 2 do
                local px, py = m.p[j] * w, m.p[j + 1] * h
                local last = pts[#pts]
                if last then
                    local d = math.sqrt((px - last[1]) ^ 2 + (py - last[2]) ^ 2)
                    for n = 1, math.floor(d / step) do
                        local t = n * step / d
                        pts[#pts + 1] = { last[1] + (px - last[1]) * t, last[2] + (py - last[2]) * t }
                    end
                end
                pts[#pts + 1] = { px, py }
            end
            local pieces, cur, cut = {}, {}, false
            for _, q in ipairs(pts) do
                if (q[1] - cx) ^ 2 + (q[2] - cy) ^ 2 < radius * radius then
                    cut = true
                    if #cur >= 2 then pieces[#pieces + 1] = cur end
                    cur = {}
                else
                    cur[#cur + 1] = q
                end
            end
            if #cur >= 2 then pieces[#pieces + 1] = cur end
            if cut then
                table.remove(list, i)
                for k, piece in ipairs(pieces) do
                    local p = {}
                    for _, q in ipairs(piece) do
                        p[#p + 1] = math.floor(q[1] / w * 10000 + 0.5) / 10000
                        p[#p + 1] = math.floor(q[2] / h * 10000 + 0.5) / 10000
                    end
                    local n = {}
                    for key, v in pairs(m) do n[key] = v end
                    n.p, n.r = p, ((m.r or 1) + k * 7) % 2000000000 + 1
                    -- (the ending stays with the piece that still has the trail's end, not every piece)
                    if k < #pieces or #cur < 2 then n.gait = n.gait == "run" and "run" or nil end
                    table.insert(list, i + k - 1, n)
                end
                i = i + #pieces
                changed = true
            else
                i = i + 1
            end
        elseif m and not LINES[m.t] and m.t ~= "sketch" then
            local d
            if m.t == "text" then
                local tx = math.max(m.p[1] * w, math.min(m.p[1] * w + #(m.s or "") * 7, cx))
                d = math.sqrt((cx - tx) ^ 2 + (cy - m.p[2] * h) ^ 2)
            else
                d = ns.InkPathDist(m.p, w, h, cx, cy) - (#m.p == 2 and 8 * (m.sc or 1) or 0)
            end
            if d < radius then
                table.remove(list, i)
                changed = true
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
    return changed
end
-- a list's marks copied (for one undo over a whole rubbing out)
function ns.InkCopyList(list)
    local function C(v)
        if type(v) ~= "table" then return v end
        local o = {}
        for k, x in pairs(v) do o[k] = C(x) end
        return o
    end
    return C(list)
end

-- a single-point mark: one of the hand-drawn shapes
local function Build1(m, t, glyphs, P, G, r)
    local x, y = P[1][1], P[1][2]
    if t == "x" and glyphs.x then
        return Glyph(glyphs.x[m.v or 1] or glyphs.x[1], x, y, G * 1.2, r, 0)
    elseif t == "q" and glyphs.q then
        return Glyph(glyphs.q[m.v or 1] or glyphs.q[1], x, y, G * 1.25, r)
    elseif t == "bang" and glyphs.bang then
        return Glyph(glyphs.bang[m.v or 1] or glyphs.bang[1], x, y, G * 1.25, r)
    elseif t == "ring" and ns.INK_RINGS then
        return Ring(ns.INK_RINGS[m.v or 1] or ns.INK_RINGS[1], x, y, G * 1.4, r)
    elseif (t == "stairs" or t == "jump" or t == "lock" or t == "chest") and glyphs[t] then
        return Glyph(glyphs[t][m.v or 1] or glyphs[t][1], x, y, G * 1.35, r, 0)
    elseif t == "sketch" then
        return SketchStrokes(m, x, y, G / 24 * 1002 / 360, r)
    elseif t == "blot" then  -- spilt ink: a few overlapping drops, spatter, now and then a run
        local out, R = {}, G * 0.25
        local function Dot(px, py, w) out[#out + 1] = { { px, py, w }, { px + 0.01, py, w } } end
        for _ = 1, 5 do
            local a, d = r() * 6.28, r() * R * 0.6
            Dot(x + math.cos(a) * d, y + math.sin(a) * d, 2.2 + r() * 1.4)
        end
        for _ = 1, 4 + math.floor(r() * 4) do
            local a, d = r() * 6.28, R * (1.4 + r() * 1.6)
            Dot(x + math.cos(a) * d, y + math.sin(a) * d, 0.5 + r() * 0.6)
        end
        if r() < 0.7 then
            local a = 1.2 + r() * 0.8
            out[#out + 1] = { { x, y, 1.6 }, { x + math.cos(a) * R * 1.8, y + math.sin(a) * R * 1.8, 0.7 } }
        end
        return out
    end
    return {}
end

-- strokes, and how much thicker than plain ink they're drawn
local function Build(m, W, H)
    local k = W / 1002
    local sc = m.sc or 1
    local G = 24 * k * sc
    local r = Rng(m.r)
    local P = {}
    for i = 1, #m.p - 1, 2 do P[#P + 1] = { m.p[i] * W, m.p[i + 1] * H, 1 } end
    if #P == 0 then return {}, 1 end
    Scaled(P, sc)
    local t = m.t
    local glyphs = ns.INK_GLYPHS or {}
    if #P == 1 then
        local out = Build1(m, t, glyphs, P, G, r)
        -- (turned, rot degrees clockwise, and flipped left to right, round its own spot)
        if m.rot or m.flip then
            local cx, cy = P[1][1], P[1][2]
            local a = math.rad(m.rot or 0)
            local ca, sa, fl = math.cos(a), math.sin(a), m.flip and -1 or 1
            for _, st in ipairs(out) do
                for _, q in ipairs(st) do
                    local dx, dy = (q[1] - cx) * fl, q[2] - cy
                    q[1], q[2] = cx + dx * ca - dy * sa, cy + dx * sa + dy * ca
                end
            end
        end
        return out, sc
    end
    if t == "pen" and m.q == 2 then return Feather(P, k, r), 1.15 end
    if t == "pen" then
        for _, p in ipairs(P) do p[3] = 0.85 + r() * 0.3 end
        return { Catmull(P, 2) }, 1
    elseif t == "route" then
        local s = Catmull(P, 2)
        local out = Dashes(s, k, r, 6, 11, 4, 7, 1)
        local a, b = s[#s], s[math.max(1, #s - 4)]
        Chevron(out, a[1], a[2], math.atan2(a[2] - b[2], a[1] - b[1]), 11 * k)
        return out, 1
    elseif t == "wander" then
        local s = Catmull(P, 2)
        if #s > 6 and math.sqrt((s[1][1] - s[#s][1]) ^ 2 + (s[1][2] - s[#s][2]) ^ 2) < 40 * k then
            s[#s + 1] = { s[1][1], s[1][2], s[1][3] }
        end
        local out, chev, run = {}, 75 + r() * 25, 0
        Walk(s, function(first, x, y, a)
            local gap = (5 + r() * 5) * k
            if not first then
                if r() < 0.6 then
                    out[#out + 1] = { { x, y, 1.15 }, { x + math.cos(a) * 0.9 * k, y + math.sin(a) * 0.9 * k, 1.15 } }
                else
                    local len = (2.5 + r() * 3.5) * k
                    out[#out + 1] = { { x, y, 0.9 }, { x + math.cos(a) * len, y + math.sin(a) * len, 0.75 } }
                    gap = gap + len
                end
                run = run + gap
                if run > chev * k then
                    run, chev = 0, 75 + r() * 25
                    Chevron(out, x, y, a, 6 * k)
                end
            end
            return gap
        end)
        return out, 1
    elseif t == "tracks" then  -- paw prints, left and right in turn, toes the way it went
        -- (a lobed pad and four oval toes in a wide arc, spaced so they stay apart. Made for the big maps;
        -- on the book's small page map nothing this fine reads, so it isn't sized for it. TRACK_PRINT
        -- scales the whole print, its dots too, so a print's shape stays the same at any size)
        local s, kk = Catmull(P, 2), k * sc * TRACK_PRINT
        local out, side = {}, 1
        local function Dot(x, y, w) out[#out + 1] = { { x, y, w }, { x + 0.01, y, w } } end
        -- one print at cx, cy, toes towards a; z its size (a hind foot a little smaller), deep how hard
        -- it came down (thicker dots), dug how far the toes dragged
        local function Print(cx, cy, a, z, deep, dug)
            z, deep, dug = z or 1, deep or 1, dug or 0
            local fx, fy = math.cos(a), math.sin(a)
            local nx, ny = -fy, fx
            local function D(along, across, w)
                Dot(cx + (fx * along + nx * across) * kk * z, cy + (fy * along + ny * across) * kk * z, w * deep)
            end
            D(0, -1.6, 2) D(0, 1.6, 2) D(-1.5, 0, 2) D(1.2, 0, 2)
            local function Toe(along, across, len) D(along, across, 1.5) D(along + len + dug, across, 1.5) end
            Toe(7.6, -7, 1.6) Toe(10.2, -2.6, 1.9) Toe(10.2, 2.6, 1.9) Toe(7.6, 7, 1.6)
        end
        -- (m.gait: how the dog goes, a quiet hint where it ends. nil walks; "run" bounds: prints in twos
        -- with long gaps, the hind foot's toes dug in with the dirt it kicked back, the front's come
        -- down hard. The rest are what it did at the end. No curves in them: an arc by two prints
        -- reads as a face)
        local n = 0
        Walk(s, function(first, x, y, a)
            if not first then
                n = n + 1
                local nx, ny = -math.sin(a), math.cos(a)
                local px, py = x + nx * side * 8 * kk, y + ny * side * 8 * kk
                if m.gait == "run" and n % 2 == 1 then
                    Print(px, py, a, 0.9, 1, 2.2)
                    for _ = 1, 3 do  -- (the kick)
                        local al, ac = -(6 + r() * 10), (r() - 0.5) * 10
                        Dot(px + (math.cos(a) * al + nx * ac) * kk, py + (math.sin(a) * al + ny * ac) * kk, 0.9)
                    end
                elseif m.gait == "run" then
                    Print(px, py, a, 1, 1.3)
                else
                    Print(px, py, a)
                end
                side = -side
            end
            if m.gait == "run" then
                return (n % 2 == 1 and 13 or 64 + r() * 8) * kk
            end
            return (28 + r() * 5) * kk
        end)
        local g = m.gait
        if g and g ~= "run" and #s >= 2 then
            local e, b = s[#s], s[math.max(1, #s - 4)]
            local ea = math.atan2(e[2] - b[2], e[1] - b[1])
            local fx, fy = math.cos(ea), math.sin(ea)
            local nx, ny = -fy, fx
            local function At(along, across)
                return e[1] + (fx * along + nx * across) * kk, e[2] + (fy * along + ny * across) * kk
            end
            -- short straight scuffs: n of them in a patch (along a0..a1, across +-c), w thick
            local function Scuffs(count, a0, a1, c, len, w, turn)
                for _ = 1, count do
                    local al, ac = a0 + r() * (a1 - a0), (r() - 0.5) * 2 * c
                    local an = (r() - 0.5) * (turn or 0.6)
                    local x0, y0 = At(al, ac)
                    local l = len * (0.6 + r() * 0.6) * kk
                    local d = ea + an
                    out[#out + 1] = { { x0, y0, w }, { x0 + math.cos(d) * l, y0 + math.sin(d) * l, w * 0.8 } }
                end
            end
            if g == "stop" or g == "sit" then
                -- (stood square, front feet side by side, facing what it stopped at)
                local fx1, fy1 = At(26, -6) Print(fx1, fy1, ea)
                local fx2, fy2 = At(26, 6) Print(fx2, fy2, ea)
                if g == "stop" then
                    local hx1, hy1 = At(2, -9) Print(hx1, hy1, ea, 0.85)
                    local hx2, hy2 = At(2, 9) Print(hx2, hy2, ea, 0.85)
                else
                    -- (sat down to it: the rump pressed into the dirt behind, a patch of short scuffs,
                    -- and the tail's brush to one side)
                    Scuffs(7, 2, 10, 7, 5, 1.1, 0.3)
                    Scuffs(3, -6, 0, 3, 7, 0.6, 0.2)
                end
            elseif g == "back" then
                -- (backed off: prints going back the way it came, toes still facing it, crowding the others)
                for j = 1, 3 do
                    local px, py = At(-8 - j * 13, (j % 2 == 0 and 1 or -1) * (13 + r() * 3))
                    Print(px, py, ea + (r() - 0.5) * 0.5)
                end
            elseif g == "dig" then
                -- (dug: front feet splayed, the earth torn up before them, the dirt thrown back behind)
                local ax, ay = At(20, -9) Print(ax, ay, ea - 0.45, 1, 1.15)
                local bx, by = At(20, 9) Print(bx, by, ea + 0.45, 1, 1.15)
                Scuffs(9, 30, 40, 9, 5, 1.2, 3)
                for _ = 1, 10 do
                    local px, py = At(-4 - r() * 26, (r() - 0.5) * 34)
                    Dot(px, py, 0.8 + r() * 0.7)
                end
            end
        end
        return out, sc * TRACK_PRINT
    elseif t == "pass" then
        local a, b = P[1], P[#P]
        local ang = math.atan2(b[2] - a[2], b[1] - a[1])
        local n = ang + math.pi / 2
        local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
        local ph, line = r() * 6, {}
        for i = 0, 12 do
            local f = i / 12
            local off = (math.sin(f * math.pi * 1.3 + ph) * 0.7 + (r() - 0.5) * 0.5) * k
            line[#line + 1] = { a[1] + math.cos(ang) * len * f + math.cos(n) * off, a[2] + math.sin(ang) * len * f + math.sin(n) * off, 1 }
        end
        local out = Dashes(line, k, r, 5, 7, 4, 6, 0.9)
        for _, q in ipairs({ a, b }) do
            local tilt, h, bend = n + (r() - 0.5) * 0.25, 8 * k, (r() - 0.5) * 1.4 * k
            out[#out + 1] = { { q[1] + math.cos(tilt) * h, q[2] + math.sin(tilt) * h, 0.8 },
                              { q[1] + math.cos(ang) * bend, q[2] + math.sin(ang) * bend, 1.15 },
                              { q[1] - math.cos(tilt) * h, q[2] - math.sin(tilt) * h, 0.7 } }
        end
        return out, 1
    end
    return {}, 1
end

-- Surfaces: where ink goes right now --------------------------------------------

local map           -- BattlefieldMapFrame
local zoneHost      -- on the zone map's canvas
local dungeonHost   -- on Dungeon.lua's canvas
local active        -- { host =, key =, level = (the catcher's frame level) } or nil
local drawing = false
local tool, inkIndex = "pen", 1
local cur           -- the mark being dragged
local shownKey, shownHost  -- what's drawn now
local Draw

local function MakeHost(parent)
    local h = CreateFrame("Frame", nil, parent)
    h:SetAllPoints(parent)
    h.ink, h.live = { lines = {}, dots = {}, nl = 0, nd = 0 }, { lines = {}, dots = {}, nl = 0, nd = 0 }
    h.texts, h.hits, h.halos = {}, {}, {}
    h.bfiOwn = true  -- (map art of ours: clear view cuts it to the zone)
    -- (a new floor or map resizes the canvas: drawn again at its size)
    h:SetScript("OnSizeChanged", function(self)
        if shownHost == self and shownKey then Draw(self, shownKey) end
    end)
    return h
end

local function Surface()
    if ns.DungeonInkSurface then
        local canvas, key = ns.DungeonInkSurface()
        if canvas then
            if not dungeonHost then
                dungeonHost = MakeHost(canvas)
                dungeonHost.paper = true  -- (big enough: the whispers' rim where they're drawn over)
            end
            local overlay = ns.dungeonOverlay
            return dungeonHost, key, (overlay and overlay:GetFrameLevel() or canvas:GetFrameLevel()) + 4
        end
    end
    local id = map and map:GetMapID()
    if not (id and zoneHost) then return end
    local _, top = ns.CanvasLevels(map)
    return zoneHost, "m" .. id, math.min(top + 10, 8900)
end

local function Marks(key, make)
    local all = ns.db.inkMarks
    if make and not all[key] then all[key] = {} end
    return all[key]
end

-- Drawing the marks --------------------------------------------------------------

-- a pool: { lines = {}, dots = {}, nl, nd } (lines and round dots in use)
local function Reset(pool)
    for _, o in ipairs(pool.lines) do o:Hide() end
    for _, o in ipairs(pool.dots) do o:Hide() end
    pool.nl, pool.nd = 0, 0
end

local function Line(h, pool)
    pool.nl = pool.nl + 1
    local l = pool.lines[pool.nl]
    if not l then
        l = h:CreateLine(nil, "ARTWORK")
        l:SetTexture(BRUSH)
        pool.lines[pool.nl] = l
    end
    return l
end

local function Dot(h, pool)
    pool.nd = pool.nd + 1
    local d = pool.dots[pool.nd]
    if not d then
        d = h:CreateTexture(nil, "ARTWORK")
        d:SetTexture(DOT)
        pool.dots[pool.nd] = d
    end
    return d
end

-- k: the thickness of plain ink (map scale, and a mark's own size). A stroke
-- of two points closer than its thickness is a dot; a point's 4th value dims it.
-- (never thinner than about a pixel and a half on screen: on a small map, as the
-- notebook's page, thinner lines break up)
-- join: each piece runs a little past its ends, so a thin curve's bends don't open into gaps (sketches)
-- avoid: { { x, y, r }, ... } in px: no piece is laid down there (a path lifts off a boss's skull)
local function PaintStrokes(h, pool, strokes, ink, k, join, avoid)
    local c = INKS[ink] or INKS[1]
    local least = 1.5 * UIParent:GetEffectiveScale() / math.max(0.01, h:GetEffectiveScale())
    for _, s in ipairs(strokes) do
        local a, b = s[1], s[2]
        local th = b and math.max(least, 2.6 * k * (a[3] + b[3]) / 2)
        if #s == 2 and math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2) < th * 0.8 then
            local d = Dot(h, pool)
            d:SetVertexColor(c[1], c[2], c[3], 0.95)
            d:SetSize(th * 1.25, th * 1.25)
            d:ClearAllPoints()
            d:SetPoint("CENTER", h, "TOPLEFT", (a[1] + b[1]) / 2, -(a[2] + b[2]) / 2)
            d:Show()
        else
            for i = 2, #s do
                a, b = s[i - 1], s[i]
                local clear = true
                for _, o in ipairs(avoid or {}) do
                    local mx, my = (a[1] + b[1]) / 2 - o[1], (a[2] + b[2]) / 2 - o[2]
                    if mx * mx + my * my < o[3] * o[3] then clear = false break end
                end
                if clear and (a[1] ~= b[1] or a[2] ~= b[2]) then
                    local l = Line(h, pool)
                    local t = math.max(least, 2.6 * k * (a[3] + b[3]) / 2)
                    l:SetVertexColor(c[1], c[2], c[3], 0.92 * ((a[4] or 1) + (b[4] or 1)) / 2)
                    l:SetThickness(t)
                    local ex, ey = 0, 0
                    if join then
                        local dx, dy = b[1] - a[1], b[2] - a[2]
                        local d = math.sqrt(dx * dx + dy * dy)
                        ex, ey = dx / d * t * 0.4, dy / d * t * 0.4
                    end
                    l:SetStartPoint("TOPLEFT", h, a[1] - ex, -(a[2] - ey))
                    l:SetEndPoint("TOPLEFT", h, b[1] + ex, -(b[2] + ey))
                    l:Show()
                end
            end
        end
    end
end

local function Text(h, i)
    local fs = h.texts[i]
    if not fs then
        fs = h:CreateFontString(nil, "OVERLAY")
        h.texts[i] = fs
    end
    return fs
end

-- the wanderer's written words: in their own hand ("nothing") or the other one, the whispers'
-- ("apple"), which the wanderer didn't write. A menu item to switch (done() redraws).
-- (and any written words: struck through or not; struck = the ink of the line through them,
-- true for their own)
function ns.InkHandItem(m, items, done)
    if m.t ~= "text" then return end
    items[#items + 1] = { m.struck and "unstrike it" or "strike it through", function()
        m.struck = not m.struck or nil
        done()
    end }
    if m.f ~= "nothing" and m.f ~= "apple" then return end
    items[#items + 1] = { m.f == "apple" and "in the wanderer's own hand" or "in the other hand (the whispers)", function()
        m.f = m.f == "apple" and "nothing" or "apple"
        done()
    end }
end

-- turning a mark (15 degrees a step) and flipping it left to right: one-point marks (x, ?, !, ring,
-- stairs, sketches...) and written words, where the game can turn words (no flip: mirrored letters).
-- get(): the mark to change (the writable copy); done() redraws
local TEXT_TURNS = UIParent:CreateFontString().SetRotation ~= nil
function ns.InkTurnItems(m, items, done, get)
    get = get or function() return m end
    -- (paw tracks: how the dog went, and what it did where they end; one row, its list beside it)
    if m.t == "tracks" then
        local sub = {}
        for _, o in ipairs({ { false, "walks on" }, { "stop", "stops there" },
                             { "sit", "sits there (found something)" }, { "back", "backs off" },
                             { "dig", "digs there" }, { "run", "runs" } }) do
            sub[#sub + 1] = { o[2], function()
                get().gait = o[1] or nil
                done()
            end, on = (m.gait or false) == o[1] }
        end
        items[#items + 1] = { "paw prints", sub = sub }
    end
    local one = m.p and #m.p == 2
    if not (one or (m.t == "text" and TEXT_TURNS)) then return end
    get = get or function() return m end
    local function Turn(d)
        local w = get()
        local r = ((w.rot or 0) + d) % 360
        w.rot = r ~= 0 and r or nil
        done()
    end
    items[#items + 1] = { "turn it left", function() Turn(-15) end }
    items[#items + 1] = { "turn it right", function() Turn(15) end }
    if m.rot then items[#items + 1] = { "straighten it", function() get().rot = nil done() end } end
    if one and m.t ~= "text" then
        items[#items + 1] = { m.flip and "flip it back" or "flip it", function()
            local w = get()
            w.flip = not w.flip or nil
            done()
        end }
    end
end

-- how far (px) a point is from a drawn line: along every stretch of it, not only its corners
-- (a trail of paw prints or a stroke through a word is picked anywhere along it)
function ns.InkPathDist(p, w, h, cx, cy)
    local d
    for j = 1, #p - 3, 2 do
        local ax, ay, bx, by = p[j] * w, p[j + 1] * h, p[j + 2] * w, p[j + 3] * h
        local vx, vy = bx - ax, by - ay
        local t = (vx * vx + vy * vy) > 0 and math.max(0, math.min(1, ((cx - ax) * vx + (cy - ay) * vy) / (vx * vx + vy * vy))) or 0
        local dj = math.sqrt((ax + vx * t - cx) ^ 2 + (ay + vy * t - cy) ^ 2)
        if not d or dj < d then d = dj end
    end
    return d or math.sqrt((p[1] * w - cx) ^ 2 + (p[2] * h - cy) ^ 2)
end

-- a way-shut mark's menu items: make it the lock, the key or the barred door (done() redraws)
function ns.InkLockItems(m, items, done)
    for i, g in ipairs((ns.INK_GLYPHS or {}).lock or {}) do
        if i ~= (m.v or 1) then
            items[#items + 1] = { "make it a " .. (g.name == "door" and "barred door" or g.name), function() m.v = i done() end }
        end
    end
end

-- a dungeon floor's name (OpenMap's floor index), for stairs leading there
local function FloorName(instance, floor)
    local f = instance and ns.MapDungeonMaps and ns.MapDungeonMaps[instance]
    f = f and f[floor]
    return f and f.name or ("floor " .. tostring(floor))
end

-- stairs on a dungeon floor: where they lead, asked when they're put down (and from
-- their menu). Another floor of the same map; done() redraws.
function ns.InkStairsMenu(m, key, done)
    local inst, here = (key or ""):match("^d(%d+):(%d+)$")
    inst, here = tonumber(inst), tonumber(here)
    local data = inst and ns.MapDungeonMaps and ns.MapDungeonMaps[inst]
    if not (data and ns.QuillMenu) then return end
    local items = {}
    for i, f in ipairs(data) do
        if i ~= here and f.tiles then
            items[#items + 1] = { "leading to " .. FloorName(inst, i), function() m.ti, m.to = inst, i done() end }
        end
    end
    if #items == 0 then return end
    items[#items + 1] = { "leading nowhere in particular", function() m.ti, m.to = nil, nil done() end }
    ns.QuillMenu(items)
end

local function NoteTip(self)
    if not self.note then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.note, NOTE_COLOR[1], NOTE_COLOR[2], NOTE_COLOR[3], true)
    GameTooltip:Show()
end

local function Hit(h, i)
    local f = h.hits[i]
    if not f then
        f = CreateFrame("Frame", nil, h)
        f:EnableMouse(true)
        -- (only the hover: clicks go on to the map)
        if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
        f:SetScript("OnEnter", NoteTip)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f:SetScript("OnMouseUp", function(self, button)
            local go = h.goFloor or ns.DungeonGoFloor
            if button == "LeftButton" and self.to and go then go(self.to[1], self.to[2]) end
            if button == "RightButton" and ns.InkMenuAt then ns.InkMenuAt() end
        end)
        h.hits[i] = f
    end
    return f
end

local function HideAll(pool) for _, o in ipairs(pool) do o:Hide() end end
local built = setmetatable({}, { __mode = "k" })  -- (a mark's strokes, while it stays the same: see DrawList)

local PAPER = { 0.78, 0.66, 0.46 }  -- (the page's own colour, for the rim round the whispers' words)
local FONT_MAX = 120  -- (the biggest font size the game draws)
local function DrawList(h, list)
    Reset(h.ink)
    HideAll(h.texts)
    HideAll(h.hits)
    HideAll(h.halos)
    local W, H = h:GetWidth(), h:GetHeight()
    if not (W and W > 0 and H and H > 0) then return end
    local k = W / 1002
    -- (the bosses' skulls on this floor, h.avoid 0-1: routes and paths lift off them; a skull is
    -- about 30 of the picture's 1002 px)
    local avoid
    if h.avoid and #h.avoid > 0 then
        avoid = {}
        for i, o in ipairs(h.avoid) do avoid[i] = { o[1] * W, o[2] * H, 15 * k } end
    end
    local nt, nh, nh2 = 0, 0, 0
    for _, m in ipairs(list) do
        if m.t == "text" then
            nt = nt + 1
            local fs, hand, c = Text(h, nt), Hand(m.f or Cfg().hand), INKS[m.ink] or INKS[1]
            local size = math.max(4, math.floor(17 * k * hand[4] * (Cfg().textSize or 1) * (m.sc or 1) + 0.5))
            -- (turned words are drawn twice the size and scaled down: turned at their own size the
            -- letters came out pixelated. The game draws no font past 120 (measured, 2026-11-03):
            -- asked for more, the words came out small and turned off their place on the zoomed
            -- book map, so never past it; past it even unturned, drawn at 120 and scaled up)
            local up = 1
            -- (ink.turnUp: the "twice", tried in game with /waymark turn <n>)
            if fs.SetScale then up = math.min(m.rot and (Cfg().turnUp or 2) or 1, FONT_MAX / size) end
            if fs.SetScale then fs:SetScale(1 / up) end
            if not fs:SetFont(hand[3], size * up, "") then fs:SetFont(HANDS[1][3], size * up, "") end
            fs:SetHeight(m.f == "apple" and size * 2 * up or 0)  -- (the whispers' long tails aren't cut off)
            -- (a faint halo of the paper's colour lifts the words off dark map art; the whispers bleed instead)
            if m.f == "apple" then
                c = WHISPER
                fs:SetShadowColor(WHISPER_BLEED[1], WHISPER_BLEED[2], WHISPER_BLEED[3], WHISPER_BLEED[4])
            else
                fs:SetShadowColor(0.95, 0.89, 0.74, 0.27)
            end
            fs:SetTextColor(c[1], c[2], c[3], 0.97)
            fs:SetShadowOffset(up, -up)
            fs:SetText(m.s or "")
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", h, "TOPLEFT", m.p[1] * W * up, -m.p[2] * H * up)
            if fs.SetRotation then fs:SetRotation(-math.rad(m.rot or 0)) end
            local tw0 = fs:GetStringWidth() / up  -- (its width on the map)
            -- (the whispers' words on a layer of their own, over the rim below)
            if m.f == "apple" and not h.top then
                h.top = CreateFrame("Frame", nil, h)
                h.top:SetAllPoints(h)
            end
            if h.top then h.top:SetFrameLevel(h:GetFrameLevel() + 1) end
            fs:SetParent(m.f == "apple" and h.top or h)
            fs:Show()
            -- (only where something is drawn under their words, and on the book's pages: maps show it)
            local under = m.struck and m.f == "apple" and h.paper or false  -- (its own strokes count)
            if m.f == "apple" and h.paper then
                local bx0, bx1 = m.p[1] * W - size * 0.3, m.p[1] * W + tw0 + size * 0.3
                local by0, by1 = -m.p[2] * H - size * 0.8, -m.p[2] * H + size * 0.8
                for _, o in ipairs(list) do
                    if o.t ~= "text" and o.p then
                        for q = 1, #o.p - 1, 2 do
                            local px, py = o.p[q] * W, -o.p[q + 1] * H
                            if px >= bx0 and px <= bx1 and py >= by0 and py <= by1 then under = true break end
                        end
                    end
                    if under then break end
                end
            end
            if under then
                -- (ink won't lie on their words: it pulls back from the letters, a thin rim of bare paper
                -- round them, so they read through anything drawn over them)
                local d = math.max(1, size * 0.045)
                for j, o in ipairs({ { d, 0 }, { -d, 0 }, { 0, d }, { 0, -d } }) do
                    nh2 = nh2 + 1
                    local hf = h.halos[nh2]
                    if not hf then
                        hf = h:CreateFontString(nil, "OVERLAY")
                        h.halos[nh2] = hf
                    end
                    if hf.SetScale then hf:SetScale(1 / up) end
                    if not hf:SetFont(hand[3], size * up, "") then hf:SetFont(HANDS[1][3], size * up, "") end
                    hf:SetTextColor(PAPER[1], PAPER[2], PAPER[3], 0.25)
                    hf:SetShadowOffset(0, 0)
                    hf:SetText(m.s or "")
                    if hf.SetRotation then hf:SetRotation(-math.rad(m.rot or 0)) end
                    hf:ClearAllPoints()
                    hf:SetPoint("LEFT", h, "TOPLEFT", (m.p[1] * W + o[1]) * up, (-m.p[2] * H + o[2]) * up)
                    hf:Show()
                end
            end
            if m.struck and m.f == "apple" then
                -- the whispers' words struck by the wanderer: hasty strokes that won't take them, the
                -- words staying whole on top of the ink (the same each time)
                local sc = INKS[type(m.struck) == "number" and m.struck or 3] or c
                local x0, y0, tw = m.p[1] * W, -m.p[2] * H, tw0
                local least = 1.5 * UIParent:GetEffectiveScale() / math.max(0.01, h:GetEffectiveScale())
                local seed = m.r or 0
                for b in (m.s or ""):gmatch(".") do seed = (seed * 31 + b:byte()) % 2147483647 end
                local function rnd(a, z)
                    seed = (seed * 16807) % 2147483647
                    return a + (z - a) * seed / 2147483647
                end
                local function Stroke(ax, ay, bx, by)
                    local l = Line(h, h.ink)
                    l:SetVertexColor(sc[1], sc[2], sc[3], rnd(0.7, 0.9))
                    l:SetThickness(math.max(least, size * rnd(0.09, 0.14)))
                    l:SetStartPoint("TOPLEFT", h, ax, ay)
                    l:SetEndPoint("TOPLEFT", h, bx, by)
                    l:Show()
                end
                -- (across them, hard and uneven, back and forth; under the words, which stay whole on top)
                local s = size
                Stroke(x0 - s * rnd(0.1, 0.3), y0 + s * rnd(-0.15, 0.15), x0 + tw + s * rnd(0, 0.3), y0 + s * rnd(-0.1, 0.25))
                Stroke(x0 + tw * rnd(0, 0.15), y0 - s * rnd(0.35, 0.55), x0 + tw * rnd(0.85, 1.05), y0 + s * rnd(0.3, 0.55))
                Stroke(x0 + tw * rnd(0.3, 0.5), y0 + s * rnd(0.3, 0.5), x0 + tw * rnd(0.9, 1.1), y0 - s * rnd(0.2, 0.45))
                if tw > s * 4 then Stroke(x0 + tw * rnd(0.05, 0.2), y0 + s * rnd(0.2, 0.4), x0 + tw * rnd(0.45, 0.65), y0 - s * rnd(0.1, 0.35)) end
            elseif m.struck then  -- a line through them, a little uneven
                local sc = INKS[type(m.struck) == "number" and m.struck or m.ink] or c
                local l = Line(h, h.ink)
                local x0, y0, tw = m.p[1] * W, -m.p[2] * H, tw0
                local least = 1.5 * UIParent:GetEffectiveScale() / math.max(0.01, h:GetEffectiveScale())
                l:SetVertexColor(sc[1], sc[2], sc[3], 0.9)
                l:SetThickness(math.max(least, size * 0.11))
                l:SetStartPoint("TOPLEFT", h, x0 - size * 0.15, y0 - size * 0.03)
                l:SetEndPoint("TOPLEFT", h, x0 + tw + size * 0.2, y0 + size * 0.06)
                l:Show()
            end
        else
            local p, c = m.p, built[m]
            local sig = W .. ":" .. H .. ":" .. #p .. ":" .. (p[1] or 0) .. ":" .. (p[2] or 0) .. ":" .. (p[#p] or 0)
                        .. ":" .. tostring(m.sc) .. ":" .. tostring(m.v) .. ":" .. tostring(m.t) .. ":" .. tostring(m.q)
                        .. ":" .. tostring(m.rot) .. ":" .. tostring(m.flip) .. ":" .. tostring(m.gait)
            if not c or c.sig ~= sig then
                local strokes, thick = Build(m, W, H)
                -- (thinned: no piece shorter than ~3 px, the ends kept; a dense scribble is thousands
                -- of tiny pieces otherwise, too many to lay down each time the page is drawn. Sketches
                -- too, to ~2 px: a small one, as a scene's dog, was hundreds of sub-pixel pieces, and the
                -- brush's tapered ends broke it into dashes)
                local least = (m.t == "sketch" and 2 or 3) * UIParent:GetEffectiveScale() / math.max(0.01, h:GetEffectiveScale())
                for si, s in ipairs((m.t == "pen" or m.t == "sketch") and strokes or {}) do  -- (glyphs keep their detail)
                    if #s > 3 then
                        local out, last = { s[1] }, s[1]
                        for i = 2, #s - 1 do
                            local q = s[i]
                            if (q[1] - last[1]) ^ 2 + (q[2] - last[2]) ^ 2 >= least * least then
                                out[#out + 1] = q
                                last = q
                            end
                        end
                        out[#out + 1] = s[#s]
                        strokes[si] = out
                    end
                end
                c = { sig = sig, strokes = strokes, thick = thick }
                built[m] = c
            end
            PaintStrokes(h, h.ink, c.strokes, m.ink, k * c.thick * (m.w or 1), m.t == "sketch",
                         (LINES[m.t] or m.t == "pass") and avoid or nil)  -- (w: a lighter or heavier hand)
        end
        local to = m.t == "stairs" and m.to
        if m.note or to then
            nh = nh + 1
            local f = Hit(h, nh)
            f.note = m.note or ("stairs to " .. FloorName(m.ti, to))
            -- (stairs that lead somewhere turn the map to that floor, while the quill's down)
            f.to = to and { m.ti, to } or nil
            if f.SetMouseClickEnabled then f:SetMouseClickEnabled(to and not drawing and not (ns.Quill and ns.Quill()) or false) end
            f:SetSize((to and 22 or 16) * k, (to and 22 or 16) * k)
            f:ClearAllPoints()
            f:SetPoint("CENTER", h, "TOPLEFT", m.p[1] * W, -m.p[2] * H)
            f:Show()
        end
    end
end

-- (with others' marks for the same place under yours, as the found notes' on a
-- dungeon floor: ns.InkExtra; they can't be picked or erased here)
Draw = function(h, key)
    local inst, floor = (key or ""):match("^d(%d+):(%d+)$")
    h.avoid = inst and ns.DungeonBossSpots and ns.DungeonBossSpots(tonumber(inst), tonumber(floor)) or nil
    local extra = ns.InkExtra and ns.InkExtra(key)
    if not (extra and #extra > 0) then return DrawList(h, Marks(key) or {}) end
    local all = {}
    for _, m in ipairs(extra) do all[#all + 1] = m end
    for _, m in ipairs(Marks(key) or {}) do all[#all + 1] = m end
    DrawList(h, all)
end

-- the mark being drawn, on its own lines
local function DrawLive()
    if not active then return end
    local h = active.host
    Reset(h.live)
    if cur and #cur.p >= 4 then
        local W, H = h:GetWidth(), h:GetHeight()
        local strokes, thick = Build(cur, W, H)
        PaintStrokes(h, h.live, strokes, cur.ink, W / 1002 * thick)
    end
end

local function Refresh(force)
    local host, key, level = Surface()
    -- (the ink button: the world map's ink; a dungeon floor's too only with "Dungeons too")
    local on = ns.IsShown("ink") or drawing
        or (key and key:find("^d%d+:") and not Cfg().dungeons) and true or false
    if shownHost and (shownHost ~= host or not on) then shownHost:Hide() end
    active = host and { host = host, key = key, level = level } or nil
    if not (host and on) then
        shownKey, shownHost = nil, nil
        return
    end
    if host == zoneHost then
        local lvl = ns.ArtLevel(map, 4)
        if host:GetFrameLevel() ~= lvl then host:SetFrameLevel(lvl) end
    end
    host:SetAlpha(Cfg().alpha or 1)
    host:Show()
    if force or key ~= shownKey or host ~= shownHost then Draw(host, key) end
    shownKey, shownHost = key, host
end
function ns.UpdateInk() Refresh(true) end

-- Editing ------------------------------------------------------------------------

local function Round(v) return math.floor(v * 10000 + 0.5) / 10000 end

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

-- The quill (Notebook.lua's: one bar for the book and the map) says the tool, the
-- ink and who's writing. As the wanderer on a found-notes dungeon floor the marks
-- are the book's (ns.QuillWanderer: the journal's map is this map); anywhere else yours.
local who = "you"
local function Current()
    if ns.Quill then
        local _, w, t, i = ns.Quill()
        who, tool, inkIndex = w, t, i
    end
end

-- the marks the quill works on here (other: the other hand's, to say whose they are)
local function List(make, other)
    local w = who
    if other then w = w == "wanderer" and "you" or "wanderer" end
    if w == "wanderer" and ns.QuillWanderer then
        local l = ns.QuillWanderer(active.key, make)
        if l then return l end
        if other then return {} end
    end
    return Marks(active.key, make) or {}
end

-- the mark under the cursor: within 10 px of a line, anywhere on a ring or a sign
-- as big as it's drawn, along a note's words
local function Nearest(x, y, other)
    local h = active.host
    local list = List(false, other)
    local w, hh = h:GetWidth(), h:GetHeight()
    local k = w / 1002
    local px = h:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local best, bd = nil, 10 / px
    local cx, cy = x * w, y * hh
    for i, m in ipairs(list) do
        local sc = m.sc or 1
        local mx, my = m.p[1] * w, m.p[2] * hh
        local d
        if m.t == "sketch" then
            d = ns.InkSketchDist(m, w, hh, cx, cy)
        elseif m.t == "text" then
            local size = 17 * k * Hand(m.f or Cfg().hand)[4] * (Cfg().textSize or 1) * sc
            local tx = math.max(mx, math.min(mx + #(m.s or "") * size * 0.42, cx))
            d = math.sqrt((cx - tx) ^ 2 + (cy - my) ^ 2) - size * 0.5
        elseif #m.p == 2 then
            d = math.sqrt((cx - mx) ^ 2 + (cy - my) ^ 2) - 24 * k * sc * 0.75
        else
            d = ns.InkPathDist(m.p, w, hh, cx, cy)
            -- (paw prints lie either side of their line, the ending past its end: any of it picks it)
            if m.t == "tracks" then
                local kk = k * sc * TRACK_PRINT
                local n = #m.p
                d = math.min(d - 16 * kk, math.sqrt((cx - m.p[n - 1] * w) ^ 2 + (cy - m.p[n] * hh) ^ 2) - 40 * kk)
            end
        end
        if d < bd then best, bd = i, d end
    end
    return best
end

-- changes, each on the quill's undo (the bar's)
local redrawn = { redraw = function() Refresh(true) end }
local function Undo(u)
    u.surf = redrawn
    if ns.QuillUndo then ns.QuillUndo(u) end
end

local function Add(m)
    local list = List(true)
    list[#list + 1] = m
    Undo({ list = list, add = m })
    Refresh(true)
end

local function RubOut(i)
    local list = List(true)
    Undo({ list = list, back = list[i], at = i })
    table.remove(list, i)
    Refresh(true)
end

local function Size(i, d)
    local m = List(true)[i]
    local sc = math.max(0.4, math.min(3, (m.sc or 1) * (d > 0 and 1.12 or 1 / 1.12)))
    sc = math.floor(sc * 100 + 0.5) / 100
    m.sc = math.abs(sc - 1) > 0.03 and sc or nil
    Refresh(true)
end

StaticPopupDialogs["BFI_INK_TEXT"] = {
    text = "%s",
    button1 = SAVE or "Save", button2 = CANCEL or "Cancel",
    hasEditBox = true, maxLetters = 255, editBoxWidth = 280,
    OnShow = function(self, data)
        local eb = self.editBox or (self.GetEditBox and self:GetEditBox())
        if eb then eb:SetText(data.value or "") eb:HighlightText() end
    end,
    OnAccept = function(self, data)
        local eb = self.editBox or (self.GetEditBox and self:GetEditBox())
        data.done(eb and strtrim(eb:GetText() or "") or "")
    end,
    EditBoxOnEnterPressed = function(eb)
        local p = eb:GetParent()
        StaticPopupDialogs["BFI_INK_TEXT"].OnAccept(p, p.data)
        p:Hide()
    end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
local function Ask(title, value, done)
    StaticPopup_Show("BFI_INK_TEXT", title, nil, { value = value, done = done })
end

local function Rewrite(i)
    local m = List(true)[i]
    Ask(who == "wanderer" and "The wanderer's words:" or "Your words on the map:", m.s or "", function(v)
        if v == "" then RubOut(i) else m.s = v Refresh(true) end
    end)
end

local function TipFor(i)
    local m = List(true)[i]
    Ask("A tooltip for this mark (empty: none):", m.note, function(v)
        m.note = v ~= "" and v or nil
        Refresh(true)
    end)
end

local function Whose()
    UIErrorsFrame:AddMessage(who == "wanderer" and "That's your own ink: rub it out writing as yourself."
        or "This ink is old and doesn't rub out easily.", 1, 0.82, 0.5)
end

local catcher

-- ?/!: their versions in the button's order: each plain one, "r" (a plain one
-- at random each time), then the hurried ones
local function Versions(kind)
    local plain, hurried = {}, {}
    for i, g in ipairs((ns.INK_GLYPHS or {})[kind] or {}) do
        if g.hurried then hurried[#hurried + 1] = i else plain[#plain + 1] = i end
    end
    local out, named = {}, ((ns.INK_GLYPHS or {})[kind] or {})[1]
    named = named and named.name  -- (versions that mean different things: no random one)
    for _, i in ipairs(plain) do out[#out + 1] = i end
    if #plain > 1 and not named then out[#out + 1] = "r" end
    for _, i in ipairs(hurried) do out[#out + 1] = i end
    return out, plain
end
local pick = { q = 1, bang = 1, lock = 1 }  -- (the place in Versions(kind))
-- stairs, drops and chests: a look of your choosing (fixed[kind]), else a different one each time
local fixed = {}
local LOOKS = {
    stairs = { "from the side", "rails and treads (an old map's)", "scrawled" },
    jump = { "over a ledge", "a hatched drop", "scrawled" },
    chest = { "domed", "strapped, with a gleam", "scrawled" },
}
local PLAIN = { q = "a question mark", bang = "an exclamation mark" }
-- the bar's dropdown for a tool: { { text, chosen, choose() }, ... }, nil when it has one look
function ns.InkChoices(kind)
    local out = {}
    if LOOKS[kind] then
        out[1] = { "a different one each time", not fixed[kind], function() fixed[kind] = nil end }
        for v, name in ipairs(LOOKS[kind]) do
            out[#out + 1] = { name, fixed[kind] == v, function() fixed[kind] = v end, { kind, v } }
        end
        return out
    end
    if not pick[kind] then return end
    local list, plain = Versions(kind)
    local n = 0
    for at, v in ipairs(list) do
        local g = v ~= "r" and ns.INK_GLYPHS[kind][v]
        local text
        if g and g.name then
            text = g.name == "door" and "barred door" or g.name
        elseif v == "r" then
            text = "steady, a different one each time"
        elseif g and g.hurried then
            text = "in a hurry"
        else
            n = n + 1
            text = "steady, the " .. ({ "first", "second", "third", "fourth" })[n] .. " way"
        end
        out[#out + 1] = { text, pick[kind] == at, function() pick[kind] = at end, v ~= "r" and { kind, v } or nil }
    end
    if PLAIN[kind] and #plain == 0 then return end
    return out
end
local function PickVersion(kind)
    local list, plain = Versions(kind)
    local v = list[pick[kind]] or list[1]
    if v == "r" then v = plain[math.random(1, #plain)] end
    return v
end
local function VersionLabel(kind, sym)
    local list = Versions(kind)
    local v = list[pick[kind]] or list[1]
    if v == "r" then return sym .. "r" end
    if v and ns.INK_GLYPHS[kind][v].name then return ns.INK_GLYPHS[kind][v].name end
    if v and ns.INK_GLYPHS[kind][v].hurried then return sym .. "h" end
    return sym .. (v or "")
end
-- (for the bar: a second click on ? or ! takes the next version)
function ns.InkVersionLabel(kind, sym) return VersionLabel(kind, sym) end
function ns.InkNextVersion(kind)
    if pick[kind] then pick[kind] = pick[kind] % #Versions(kind) + 1 end
end

local PATHS = { pen = true, feather = true, route = true, wander = true, pass = true, tracks = true }

-- what the tool does where you pressed
local function Press(x, y)
    local seed = math.random(1, 2000000000)
    local glyphs = ns.INK_GLYPHS or {}
    if tool == "x" or tool == "ring" then
        local count = tool == "x" and #(glyphs.x or {}) or #(ns.INK_RINGS or {})
        Add({ t = tool, v = math.random(1, math.max(1, count)), ink = inkIndex, r = seed, p = { Round(x), Round(y) } })
    elseif tool == "q" or tool == "bang" then
        Add({ t = tool, v = PickVersion(tool), ink = inkIndex, r = seed, p = { Round(x), Round(y) } })
    elseif tool == "stairs" or tool == "jump" or tool == "lock" or tool == "chest" or tool == "blot" then
        local m = ns.InkNewMark(tool, inkIndex, x, y)
        Add(m)
        if tool == "stairs" then ns.InkStairsMenu(m, active.key, function() Refresh(true) end) end
    elseif tool == "text" then
        local key, wanderer = active.key, who == "wanderer"
        Ask(wanderer and "The wanderer's words:" or "Your words on the map:", "", function(v)
            if v == "" or not (active and active.key == key) then return end
            -- (in the notebook's hands: yours, or the wanderer's)
            Add({ t = "text", s = v, f = ns.QuillHand and ns.QuillHand() or (wanderer and "nothing" or "reenie"), ink = inkIndex, r = 0, p = { Round(x), Round(y) } })
        end)
    elseif PATHS[tool] then
        cur = { t = tool == "feather" and "pen" or tool, q = tool == "feather" and 2 or nil, ink = inkIndex, r = seed, p = { Round(x), Round(y) } }
        cur.sx, cur.sy = GetCursorPosition()
    end
end

-- A press on a mark (any tool but the path tools and rub out) picks it up: dragged,
-- it moves; let go where it was, it's a click: a written note's words again (words
-- or note tool), else the tool's own click. The found notes' numbers on a dungeon
-- floor the same way (Notebook.lua's). Right-click a mark: its menu.
local grab  -- { i, x, y (0-1), sx, sy, moved, m, p0 } or { spot = true, x, y }

-- right-drag pans the map under the quill, the zone map or the dungeon map (a right-click
-- that doesn't move: the menu)
local pan
local function PanStart()
    local sx, sy = GetCursorPosition()
    pan = { sx = sx, sy = sy }
    if active and active.host == dungeonHost and ns.DungeonPanStart then
        pan.dungeon = ns.DungeonPanStart()
    else
        local sc = map and map.ScrollContainer
        if sc and sc.Child and sc.GetCanvasScale then
            pan.sc, pan.s = sc, sc:GetCanvasScale()
            pan.x, pan.y = sc.currentScrollX or 0.5, sc.currentScrollY or 0.5
        end
    end
end
local function PanUpdate()
    if not (pan and IsMouseButtonDown("RightButton")) then return end
    local sx, sy = GetCursorPosition()
    if not pan.moved then
        if math.sqrt((sx - pan.sx) ^ 2 + (sy - pan.sy) ^ 2) / UIParent:GetEffectiveScale() < 4 then return end
        pan.moved = true
    end
    if pan.dungeon then
        ns.DungeonPanMove(pan.dungeon)
        return
    end
    local sc = pan.sc
    if not (sc and ns.ApplyMapView) then return end
    local es, cw, ch = sc:GetEffectiveScale(), sc.Child:GetWidth(), sc.Child:GetHeight()
    if not (cw > 0 and ch > 0 and pan.s > 0) then return end
    local x = pan.x - (sx - pan.sx) / es / pan.s / cw
    local y = pan.y + (sy - pan.sy) / es / pan.s / ch
    -- (kept inside the map, as the game's own pan is: a view off it would trouble the map every frame)
    if sc.CalculateScrollExtentsAtScale then
        local ok, minX, maxX, minY, maxY = pcall(sc.CalculateScrollExtentsAtScale, sc, pan.s)
        if ok and minX then x, y = math.max(minX, math.min(maxX, x)), math.max(minY, math.min(maxY, y)) end
    end
    if x ~= x or y ~= y then return end
    pcall(ns.ApplyMapView, sc, pan.s, x, y)
    if sc.targetScrollX and sc.SetNormalizedHorizontalScroll then  -- (straight there, no glide)
        sc.currentScrollX, sc.currentScrollY = sc.targetScrollX, sc.targetScrollY
        pcall(sc.SetNormalizedHorizontalScroll, sc, sc.currentScrollX)
        pcall(sc.SetNormalizedVerticalScroll, sc, sc.currentScrollY)
    end
end

-- rubbing out, while the button's down (one undo for the whole of it)
local rubbing
local function RubAt()
    local h = active and active.host
    if not (rubbing and h) then return end
    local x, y = Cursor()
    if not x then return end
    local radius = 9 * UIParent:GetEffectiveScale() / math.max(0.01, h:GetEffectiveScale())
    if ns.InkErase(rubbing.list, x, y, h:GetWidth(), h:GetHeight(), radius) then
        rubbing.changed = true
        Refresh(true)
    end
end

local function MouseDown(button)
    if button == "RightButton" and active then PanStart() return end
    if button ~= "LeftButton" or not active then return end
    Current()
    local x, y = Cursor()
    if not x then return end
    if IsShiftKeyDown() then
        local i = Nearest(x, y)
        if i then TipFor(i) elseif active.host == dungeonHost and ns.DungeonBossNote then ns.DungeonBossNote() end
        return
    end
    if IsControlKeyDown() then  -- (Ctrl: move what's under it, whatever's in hand; Ctrl + wheel sizes it)
        if ns.QuillSpotDown and ns.QuillSpotDown(false) then
            grab = { spot = true, x = x, y = y, alt = true }
            return
        end
        local i = Nearest(x, y)
        if i then
            local sx, sy = GetCursorPosition()
            grab = { i = i, x = x, y = y, sx = sx, sy = sy, alt = true }
        end
        return
    end
    if ns.QuillSpotDown and ns.QuillSpotDown(tool == "erase") then
        if tool ~= "erase" then grab = { spot = true, x = x, y = y } end
        return
    end
    if tool == "erase" then
        local list = List(true)
        rubbing = { list = list, snap = ns.InkCopyList(list), changed = false }
        RubAt()
        if not rubbing.changed and Nearest(x, y, true) then Whose() end
        return
    end
    if PATHS[tool] then Press(x, y) return end
    local i = Nearest(x, y)
    if i then
        local sx, sy = GetCursorPosition()
        grab = { i = i, x = x, y = y, sx = sx, sy = sy }
    elseif tool ~= "words" then
        Press(x, y)
    end
end

local function MarkMenu(i)
    local m = List(false)[i]
    local items = {}
    if m.t == "text" then items[1] = { "rewrite it", function() Rewrite(i) end } end
    if m.t == "stairs" and active.key:match("^d") then
        local key = active.key
        items[#items + 1] = { "where they lead", function() ns.InkStairsMenu(m, key, function() Refresh(true) end) end }
    end
    if m.t == "lock" then ns.InkLockItems(m, items, function() Refresh(true) end) end
    if ns.InkHandItem then ns.InkHandItem(m, items, function() Refresh(true) end) end
    ns.InkTurnItems(m, items, function() Refresh(true) end, function() return List(true)[i] end)
    items[#items + 1] = { "bigger", function() Size(i, 1) end }
    items[#items + 1] = { "smaller", function() Size(i, -1) end }
    items[#items + 1] = { m.note and "its tooltip" or "a tooltip", function() TipFor(i) end }
    items[#items + 1] = { "rub it out", function() RubOut(i) end }
    ns.QuillMenu(items)
end

-- right-click with the quill's catcher (Controls.lua): a thing's menu, else the map's. The dungeon
-- map asks its own (rings, bosses, then the marks: ns.InkMenuAt)
local function Context()
    if not active then return end
    if active.host == dungeonHost and ns.DungeonMapUp then ns.DungeonMapUp("RightButton") return end
    local x, y = Cursor()
    local i = x and Nearest(x, y)
    if i and ns.QuillMenu then MarkMenu(i) return end
    if ns.MapRightClick then ns.MapRightClick(ns.MapOut, "zoom out") end
end

-- a mark under the cursor, its menu (true when there was one): the quill away too, where the
-- marks are shown
function ns.InkMenuAt()
    if not (active and ns.QuillMenu and (drawing or shownHost == active.host)) then return false end
    Current()
    local x, y = Cursor()
    local i = x and Nearest(x, y)
    if not i then return false end
    MarkMenu(i)
    return true
end

local function MouseUp(button)
    if not active then return end
    Current()
    if rubbing and button == "LeftButton" then
        local r = rubbing
        rubbing = nil
        if r.changed then Undo({ list = r.list, snapshot = r.snap }) end
        return
    end
    if button == "RightButton" then
        local moved = pan and pan.moved
        pan = nil
        if not moved and not cur and not grab then Context() end
        return
    end
    if grab then
        local g = grab
        grab = nil
        if g.spot then
            if not (ns.QuillSpotUp and ns.QuillSpotUp()) and not g.alt and tool ~= "words" and not PATHS[tool] then Press(g.x, g.y) end
            return
        end
        if g.moved then
            Undo({ mark = g.m, p = g.p0 })
            Refresh(true)
            return
        end
        if g.alt then return end
        local m = List(false)[g.i]
        if m and m.t == "text" and (tool == "words" or tool == "text") then
            Rewrite(g.i)
        elseif tool ~= "words" then
            Press(g.x, g.y)
        end
        return
    end
    if not cur then return end
    local m = cur
    cur = nil
    m.sx, m.sy = nil, nil
    Reset(active.host.live)
    if #m.p >= 4 then Add(m) end
end

local function DragUpdate()
    PanUpdate()
    if rubbing then
        if IsMouseButtonDown("LeftButton") then RubAt() else MouseUp("LeftButton") end
        return
    end
    if grab then
        if not IsMouseButtonDown("LeftButton") then MouseUp("LeftButton") return end
        if grab.spot then
            if ns.QuillSpotUpdate then ns.QuillSpotUpdate() end
            return
        end
        local sx, sy = GetCursorPosition()
        if not grab.moved then
            if math.sqrt((sx - grab.sx) ^ 2 + (sy - grab.sy) ^ 2) / UIParent:GetEffectiveScale() < 4 then return end
            grab.moved = true
            grab.m = List(true)[grab.i]
            grab.p0 = {}
            for j, v in ipairs(grab.m.p) do grab.p0[j] = v end
        end
        local x, y = Cursor()
        if not x then return end
        for j = 1, #grab.p0 - 1, 2 do
            grab.m.p[j], grab.m.p[j + 1] = Round(grab.p0[j] + x - grab.x), Round(grab.p0[j + 1] + y - grab.y)
        end
        Refresh(true)
        return
    end
    if not cur then return end
    if not IsMouseButtonDown("LeftButton") then MouseUp("LeftButton") return end
    local sx, sy = GetCursorPosition()
    -- (a new point every 3 px on screen, whatever the zoom)
    local s = UIParent:GetEffectiveScale()
    if math.sqrt((sx - cur.sx) ^ 2 + (sy - cur.sy) ^ 2) / s < 3 then return end
    local x, y = Cursor()
    if not x then return end
    cur.sx, cur.sy = sx, sy
    cur.p[#cur.p + 1] = Round(x)
    cur.p[#cur.p + 1] = Round(y)
    DrawLive()
end

-- Ctrl + wheel over a mark: its size; otherwise the map's own zoom (the
-- catcher takes the wheel so it can tell)
local function Wheel(delta)
    -- (a found note's ring under it first: its size, kept with the note)
    if IsControlKeyDown() and active and ns.QuillSpotSize and ns.QuillSpotSize(delta) then return end
    if IsControlKeyDown() and active then
        Current()
        local x, y = Cursor()
        local i = x and Nearest(x, y)
        if i then
            Size(i, delta)
            return
        end
    end
    if active and active.host == dungeonHost then
        local f = ns.dungeonOverlay
        local fn = f and f:GetScript("OnMouseWheel")
        if fn then fn(f, delta) end
    elseif ns.MapZoom then
        ns.MapZoom(delta > 0 and 1 or -1)  -- (as the zoom keys: the map's zoom and its centering)
    end
end

-- the catcher: over the map while the quill's in hand, takes the mouse buttons (not the wheel)
local function PlaceCatcher()
    if not (catcher and active) then return end
    local area = map.ScrollContainer or map
    catcher:SetAllPoints(area)
    catcher:SetFrameLevel(active.level)
end

function ns.InkDrawing() return drawing end

-- the catcher stood aside while something else takes the map's clicks (placing bosses: their
-- markers lie under it), the quill still in hand
local paused = false
function ns.InkCatcherPause(p)
    paused = p and true or false
    if catcher then catcher:SetShown(drawing and not paused) end
end

-- a press on something lying over the catcher (an object pin) handed on to the quill
-- (true when the catcher's out to take it)
function ns.InkCatcherPress(down, button)
    if not (catcher and catcher:IsShown()) then return false end
    if down then MouseDown(button) else MouseUp(button) end
    return true
end

-- Ink on other surfaces (the notebook's pages): the same marks and look, kept
-- and edited by their owner. A host on any frame (marks 0-1 across it), the
-- marks drawn on it, the one being drawn, and a new mark for a tool.
ns.INK_COLORS = INKS
function ns.InkHost(parent)
    local h = MakeHost(parent)
    h:SetScript("OnSizeChanged", nil)
    return h
end
ns.InkDrawList = DrawList
function ns.InkDrawLive(h, m)
    Reset(h.live)
    if m and #m.p >= 4 then
        local W, H = h:GetWidth(), h:GetHeight()
        local strokes, thick = Build(m, W, H)
        PaintStrokes(h, h.live, strokes, m.ink, W / 1002 * thick)
    end
end
function ns.InkNewMark(kind, ink, x, y, text, hand)
    local seed = math.random(1, 2000000000)
    local glyphs = ns.INK_GLYPHS or {}
    local p = { Round(x), Round(y) }
    if kind == "x" or kind == "ring" then
        local count = kind == "x" and #(glyphs.x or {}) or #(ns.INK_RINGS or {})
        return { t = kind, v = math.random(1, math.max(1, count)), ink = ink, r = seed, p = p }
    elseif kind == "q" or kind == "bang" or kind == "lock" then
        return { t = kind, v = PickVersion(kind), ink = ink, r = seed, p = p }
    elseif kind == "stairs" or kind == "jump" or kind == "chest" then  -- (chosen, else at random: no two alike)
        return { t = kind, v = fixed[kind] or math.random(1, math.max(1, #(glyphs[kind] or {}))), ink = ink, r = seed, p = p }
    elseif kind == "text" then
        return { t = "text", s = text, f = hand, ink = ink, r = 0, p = p }
    elseif kind == "feather" then
        return { t = "pen", q = 2, ink = ink, r = seed, p = p }
    elseif kind == "blot" then
        return { t = kind, ink = ink, r = seed, p = p }
    elseif kind == "route" or kind == "wander" or kind == "pass" or kind == "tracks" then
        return { t = kind, ink = ink, r = seed, p = p }
    end
    return { t = "pen", ink = ink, r = seed, p = p }
end
ns.InkAsk = function(title, value, done) Ask(title, value, done) end

-- the quill taken up or put down (Notebook.lua's SetWriting): the catcher over the map
function ns.InkQuill(on)
    drawing = on and true or false
    cur, grab = nil, nil
    if not map then return end
    Refresh(true)
    if drawing then
        PlaceCatcher()
        catcher:SetShown(not paused)
    else
        catcher:Hide()
    end
    if ns.ApplyClickThrough then ns.ApplyClickThrough() end
    if ns.RefreshToggles then ns.RefreshToggles() end
end

-- where the quill's bar goes while the notebook isn't open: the map's bottom edge
function ns.InkBarArea() return map and map:IsShown() and (map.ScrollContainer or map) or nil end

-- /bfi ink, the map's ink toggle, the key: the quill (opening the map)
function ns.ToggleInkBar(on)
    if not map then return end
    if on == nil then on = not drawing end
    if on and not map:IsShown() and ToggleBattlefieldMap then ToggleBattlefieldMap() end
    if ns.SetQuill then ns.SetQuill(on) else ns.InkQuill(on) end
end

function ns.SetupInk(m)
    map = m
    local canvas = map:GetCanvas()
    zoneHost = MakeHost(canvas)
    local area = map.ScrollContainer or map

    catcher = CreateFrame("Frame", nil, area)
    catcher:EnableMouse(true)
    catcher:EnableMouseWheel(true)  -- (Ctrl over a mark: its size; else on to the map's zoom)
    catcher:SetScript("OnMouseWheel", function(_, delta) Wheel(delta) end)
    catcher:SetScript("OnMouseDown", function(_, button) MouseDown(button) end)
    catcher:SetScript("OnMouseUp", function(_, button) MouseUp(button) end)
    catcher:SetScript("OnUpdate", DragUpdate)
    catcher:Hide()
    area:HookScript("OnSizeChanged", function() if drawing and ns.QuillPlace then ns.QuillPlace() end end)
    -- (the map put away: the quill stays while the notebook's open, the bar going under it)
    map:HookScript("OnHide", function()
        if not drawing then return end
        if ns.NotebookOpen and ns.NotebookOpen() then
            if ns.QuillPlace then ns.QuillPlace() end
        else
            ns.ToggleInkBar(false)
        end
    end)
    map:HookScript("OnShow", function()
        if not drawing then return end
        Refresh(true)
        PlaceCatcher()
        if ns.QuillPlace then ns.QuillPlace() end
    end)

    -- the surface changes with the map, the dungeon floor, the dungeon view
    -- coming and going: checked a few times a second, redrawn when it changed
    C_Timer.NewTicker(0.25, ns.Timed("Ink tick", function()
        if not map:IsVisible() then return end
        Refresh()
        if drawing then PlaceCatcher() end
    end))
    Refresh(true)
end
