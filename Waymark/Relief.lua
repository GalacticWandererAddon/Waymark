local _, ns = ...

-- The lie of the land, fifth edition (mockups\joint\relief-depth.md). Out of the Lab for 1.3 on 2026-11-14, at
-- the user's word: its settings are the addon's own (ns.db.relief; DEFAULTS in BattlefieldInfo.lua), so presets,
-- saved setups, per-character settings and Reset all carry them; its art is Media\Relief.
-- The map gets the land's depth: light and shade worked out from the game's real heights, and the light
-- moves with the hour. The user, 2026-11-12: "If you can nail the depth this shading from the relief is
-- adding to the map, make it work across zone-maps so it looks seamless, and moves with the hour, it will be
-- the best addition to a wow map i have ever seen." It says what the ground is, never where to go.
--
-- The light goes ROUND and never over. Its bearing is the hour x 15 degrees (east at 6, south at noon, west
-- at 18, north at midnight) and its height is always the same and low, so the map is never flat at noon and
-- nothing flips at dusk. By night it is weaker and cooler, by MapHour.lua's own measure of the dark (ns.Sky).
-- Round due south, about noon, it gives a little: the game's painters lit their mountains from the north-west.
-- "Steady light" holds it in the north-west, the map-maker's corner; performance mode (effects) does too.
--
-- Nine baked layers a zone (tools\relief_bake.py; <map>D0 .. D7.blp: the part of the slope that faces north,
-- north-east, east and so round; <map>LT its steepness; flat white, the strength in the alpha). Shading is a sum over the
-- light's direction, so the two layers that face the light are laid as light (ADD), the two that face away
-- and the steepness as shade (BLEND), and the hour only sets five strengths: within 1% of true shading
-- (tools\relief_hours.py). Every zone is baked from the one height field with the same rounding in yards, so
-- a ridge that crosses a border is the same ridge on both maps.
--
-- Eight more (<map>C0 .. C7.blp) hold the shadow the land throws under a low light from each of those sides;
-- the two the light stands between are laid as shade, by how near it is to each (/relief cast).
-- Each zone has its own shade and light by day (ns.ReliefTones: its painting's colour where the land slopes,
-- darker and lighter): one umber for all lay on Redridge's orange mountains as a smoky veil. The depth is cut
-- to the zone's painted land (the joined alpha of its explorable areas), not laid on the parchment beside it.
-- Two homes: the painted zone map at PAINTED of its strength, and the close-up (Detail.lua's tiles, the
-- game's own picture of the ground) at CLOSE, since those tiles carry a light already. A zone whose painting
-- does not lie where the land does (ns.ReliefPaintedOff, Data\ReliefZones.lua) gets none on the painting.
-- The depth lies over the whole zone, one texture a layer. /relief fog hides it where you haven't explored:
-- where part of the zone is unexplored each layer is then laid as COLS x ROWS pieces, a piece only
-- where you have explored (ns.IsUnexploredAt), with a soft-edged mask towards the fog (Edge<n>.tga). A zone
-- explored whole is one texture a layer.
-- With the close-up comes the rim of every fall that kills (<map>R1, R2): a small extra.
-- Kept to look at, off: /relief strokes (steep ground in strokes on the painted map; five zones have them).
--
-- Cost: five textures in a zone explored whole (5 x COLS x ROWS at most, none overlapping its neighbour in
-- a layer), the rim's two. One look a second with the map open, one each frame while it zooms; it compares a
-- few numbers and acts on a change. The light is looked at in steps of five game minutes: five SetAlpha
-- calls, and a recolour when the dark has moved a step.

-- (as DEFAULTS.relief in BattlefieldInfo.lua: this one only stands in before the settings are read)
local DEFAULT = { on = true, shade = true, shadeAlpha = 100, hour = true, cast = true, rim = false, rimAlpha = 100, ink = false, inkAlpha = 85 }
local RATE = 1               -- s between looks
local COLS, ROWS = 12, 8     -- a picture's pieces, where there is fog
local SMALL = 300            -- the zone narrower than this on screen: the thinned strokes
local PAINTED = 1.25         -- the depth's strength on the painted map (0.85 until the user's Loch Modan shot: "bold zones")
local ZONE_SHADE = 0.70      -- a zone's shade: this much of its own dark tone (the continent's shade is darker, and read better)
local ZONE_SLOPE = 0.85      -- a zone's slopes (each crag's lit and far side), against its thrown shadows. The painted zone map draws
                             -- every crag already: at full strength the facets broke the big shadows into scraps, and turning the
                             -- whole depth down smoothed it but lost "the deep shadowing cast in the ring" (the user, 2026-11-13)
local ZONE_CAST = 1.25       -- a zone's thrown shadows, against the continent's: they are the part to make bold
local CLOSE = 0.40           -- and on the close-up, whose tiles have a light of their own
local REACH = 0.92           -- how much of the light lies along the ground (it stands low)
local STEEP = 0.16           -- the steepness's shade
local NIGHT_LIT = 0.85        -- how much of the lit side the dark takes away: the map is tinted dark by night
                             -- (MapHour.lua) and our light is not, so a moonlight that is right by day's
                             -- measure lay on it as a pale haze (the user's shots, 2026-11-12)
local LIT_PART = 0.27        -- the lit side, against the far side. The lit faces are what gives a range its mass:
                             -- at 0.24 the joint picture lost its depth (scene3 against scene2, 2026-11-12)
local MOON = 0.85            -- the night's strength, of the day's
local NOON, NOON_SHADE, NOON_LIT = 45, 0.10, 0.0   -- within NOON degrees of due south the painter's own light (from
                             -- the north-west) is against ours: the shade gives this much, the light this much
local STEADY = 315           -- the steady light's bearing: north-west
local UMBER, NIGHT = { 90 / 255, 58 / 255, 30 / 255 }, { 8 / 255, 10 / 255, 22 / 255 }              -- the shade, by day and by night
local STRAW, MOONLIGHT = { 1, 240 / 255, 200 / 255 }, { 120 / 255, 140 / 255, 190 / 255 }            -- the light
local ART = "Relief\\"
-- (thrown shadows first: under the slopes' light. C<k>, D<k>: k x 45 degrees, 0 north, 2 east, 4 south, 6 west)
local NAMES = { "C0", "C1", "C2", "C3", "C4", "C5", "C6", "C7", "D0", "D1", "D2", "D3", "D4", "D5", "D6", "D7", "LT" }
local CAST = 0.80            -- a thrown shadow's strength, of the shade's

local mapFrame, inkHost, rimHost
local pieces = {}            -- the strokes
local rim = {}               -- the west and east half
local layer = {}             -- [name] = { host, list, role, tone }
local shownKey, laidKey, shadeKey

local function Cfg()
    local c = ns.db and ns.db.relief
    if not c then return DEFAULT end          -- (before the settings are read: nothing is drawn yet)
    -- carried over once from the Lab's store, where they lived until 1.3 (dev copies and friends' builds only)
    local old = WaymarkDB and WaymarkDB.lab and WaymarkDB.lab.relief
    if old and not old.moved then
        for k, v in pairs(old) do c[k] = v end
        old.moved = true
    end
    if c.edition ~= 5 then   -- (earlier editions saved strokes on, a wash, a steady switch of another meaning)
        c.edition, c.ink, c.wash, c.steady, c.strength = 5, false, nil, nil, nil
        if not c.inkAlpha or c.inkAlpha == 70 then c.inkAlpha = DEFAULT.inkAlpha end
    end
    return c
end

-- a strength as the test panel has set it (Lab/ReliefPanel.lua keeps them in the settings' tune table), or the
-- constant itself. ns.ReliefDefaults: the constants, for the panel's sliders and its "as built"
local function V(name, default)
    local t = Cfg().tune
    local v = t and t[name]
    if v == nil then return default end
    return v
end
ns.ReliefDefaults = { PAINTED = PAINTED, CLOSE = CLOSE, LIT_PART = LIT_PART, STEEP = STEEP, MOON = MOON, ZONE_SHADE = ZONE_SHADE, ZONE_SLOPE = ZONE_SLOPE }

-- is the map itself dark by night? Only a zone map with the hour's tint on (MapHour.lua; never a continent).
-- Where it is not, the night's blue-black shade lay on a bright map as black spots (the user's shots of the
-- Eastern Kingdoms at 0:00 and 5:45, 2026-11-13): there the shade keeps the day's colour all night.
local function Bright(continent)
    local m = ns.db and ns.db.mapHour
    if not (m and m.on) or (ns.Perf and ns.Perf("effects")) then return true end
    if continent then return Cfg().contNight == false or not ns.MapHourTint end
    return false
end

-- the light held still by performance mode (its page's second tick for this; PerfOff further down is the first)
local function PerfSteady() return ns.Perf and ns.Perf("reliefHour") or false end

-- where the light stands and what it is like: its east and north part, its strength, how dark the hour is,
-- and the lit side's share. Round due south it gives a little: it stands against the painter's own light there
local function Light(hour, steady, bright)
    if steady then
        local b = math.rad(STEADY)
        return math.sin(b) * REACH, math.cos(b) * REACH, 1, 0, V("LIT_PART", LIT_PART)
    end
    hour = (hour or (ns.MapHourNow and ns.MapHourNow()) or 12) % 24
    local dark = 0
    if ns.Sky then dark = select(4, ns.Sky(hour)) or 0 end
    local deg = hour * 15
    local b = math.rad(deg)
    local south = math.max(0, math.min(1, (NOON - math.abs(deg - 180)) / 15))
    local k = (1 - (1 - V("MOON", MOON)) * dark) * (1 - NOON_SHADE * south)
    if bright then dark = 0 end          -- (the colours and the lit side follow the map; the strength the hour)
    return math.sin(b) * REACH, math.cos(b) * REACH, k, dark,
        V("LIT_PART", LIT_PART) * (1 - NOON_LIT * south) * (1 - NIGHT_LIT * dark)
end
ns.ReliefLight = Light       -- (tools\relief_lua_test.lua)

-- each layer's part at this light: "lit" or "dark", and its strength (the same sums as tools\relief_hours.py).
-- Eight layers for eight ways a slope can face. The light stands between two of them: those two are the lit
-- side, the two opposite the far side, each by how near the light is to it. With four layers a light from a
-- corner (8:00, 15:00) laid light and shade over one another on every slope that faced between: "incredibly
-- busy" at those hours and "great" at 12:00 (the user, in game).
local function Plan(e, n, k, lit, cast, castK, slopeK)
    slopeK = slopeK or 1
    lit = lit or V("LIT_PART", LIT_PART)
    local plan = { LT = { "dark", V("STEEP", STEEP) * k * slopeK } }
    for i = 0, 7 do
        plan["D" .. i] = { "dark", 0 }
        plan["C" .. i] = { "dark", 0 }
    end
    local bearing = math.deg(math.atan2(e, n)) % 360
    local i = math.floor(bearing / 45) % 8
    local f = bearing / 45 - math.floor(bearing / 45)
    local reach = math.sqrt(e * e + n * n)
    for step = 0, 1 do
        local w = step == 0 and (1 - f) or f
        local a = (i + step) % 8
        plan["D" .. a] = { "lit", reach * k * lit * w * slopeK }
        plan["D" .. (a + 4) % 8] = { "dark", reach * k * w * slopeK }
        plan["C" .. a] = { "dark", cast == false and 0 or reach / REACH * k * V("CAST", CAST) * (castK or 1) * w }
    end
    return plan
end
ns.ReliefPlan = Plan

-- A relief picture is stretched far past its own points on a big or zoomed map. Left to itself the game
-- snaps a texture's points to screen pixels, which shows as blocks that change with the map's size (the
-- user's shots, 2026-11-13). The rest of the addon turns this off for map art; so does the relief.
local function Smooth(t)
    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
    if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
    return t
end

local function Host(map, level)
    local canvas = map:GetCanvas()
    local f = CreateFrame("Frame", nil, canvas)
    f:SetAllPoints(canvas)
    f.bfiOwn = true          -- (map art of ours: clear view cuts it to the zone)
    f.bfiNoHour = true       -- (MapHour.lua's tint stays off it)
    f.bfiLevel = level
    return f
end

-- One frame holds every layer of a map, and a layer is a group of its textures. The layers used to be a frame
-- each at one frame level, where the game chooses the order: a slope's light could be drawn over a thrown
-- shadow, and small lit crags stood in the Twilight Grove's evening shadow as bright scraps (the user's shots,
-- 2026-11-13: "maybe it's the highlights being places they shouldn't"). In one frame the order is ours: the
-- light first (BORDER), the shade and the thrown shadows over it (ARTWORK), so a shadow covers what lies in it.
-- A group stands in for the frame it had: shown, alpha, colour and part are its textures'.
local function Group(frame)
    local g = { frame = frame, tex = {}, shown = false, alpha = 1, r = 1, g = 1, b = 1, bfiLevel = frame.bfiLevel }
    local function Paint(t)
        t:SetBlendMode(g.role == "lit" and "ADD" or "BLEND")
        t:SetDrawLayer(g.role == "lit" and "BORDER" or "ARTWORK")
        t:SetVertexColor(g.r, g.g, g.b, g.alpha)
    end
    function g:CreateTexture()
        local t = Smooth(frame:CreateTexture(nil, "ARTWORK"))
        self.tex[#self.tex + 1] = t
        self.made = #self.tex
        t.laid = true
        Paint(t)
        t:SetShown(self.shown)
        return t
    end
    function g:CreateMaskTexture(...) self.masks = (self.masks or 0) + 1 return frame:CreateMaskTexture(...) end
    function g:Lay(t, laid)
        t.laid = laid
        t:SetShown(self.shown and laid)
    end
    function g:Dress(role, r, gr, b)
        self.role, self.r, self.g, self.b = role, r, gr, b
        for _, t in ipairs(self.tex) do Paint(t) end
    end
    function g:SetAlpha(a)
        self.alphas = (self.alphas or 0) + 1
        if a == self.alpha then return end
        self.alpha = a
        for _, t in ipairs(self.tex) do t:SetVertexColor(self.r, self.g, self.b, a) end
    end
    function g:SetShown(on)
        on = on and true or false
        if on == self.shown then return end
        self.shown = on
        for _, t in ipairs(self.tex) do t:SetShown(on and t.laid) end
    end
    function g:Show() self:SetShown(true) end
    function g:Hide() self:SetShown(false) end
    function g:IsShown() return self.shown end
    function g:GetFrameLevel() return frame:GetFrameLevel() end
    function g:SetFrameLevel(l) self.level = l frame:SetFrameLevel(l) end
    return g
end
local function Lay(host, p, on)
    if host.Lay then host:Lay(p, on) else p:SetShown(on) end
end

local function Lift(f, map)
    if not ns.ArtLevel then return end
    local level = ns.ArtLevel(map, ns.ART_LEVELS and f.bfiLevel or (f.bfiLevel == "wash" and 2 or 1))
    -- (live Forever leaves two levels between the explored art and the lowest pin, 2001 and 2003: ArtLevel then
    -- sets a wash AT the explored art's level and the game drew that art over the depth; the user's shots,
    -- 2026-11-13. Over the explored art always, under the pins where there is room.)
    if ns.CanvasLevels then
        local explore, _, bottom = ns.CanvasLevels(map)
        if explore and level <= explore then level = explore + 1 end
        if bottom and level >= bottom and bottom - 1 > (explore or 0) then level = bottom - 1 end
    end
    if f:GetFrameLevel() ~= level then f:SetFrameLevel(level) end
end

-- the part of each picture this client's map of the zone covers (Era's box differs for some zones)
local function Coords(mapID, box)
    local l, r, t, b = 0, 1, 0, 1
    if C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local ok, _, tl = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0, 0))
        local ok2, _, br = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(1, 1))
        if ok and ok2 and tl and br then
            local top, left = tl:GetXY()
            local bottom, right = br:GetXY()
            local wide, tall = box[4] - box[2], box[3] - box[1]
            if wide ~= 0 and tall ~= 0 and top ~= bottom and left ~= right then
                l, r = (box[4] - left) / wide, (box[4] - right) / wide
                t, b = (box[3] - top) / tall, (box[3] - bottom) / tall
            end
        end
    end
    return l, r, t, b
end
ns.ReliefCoords = Coords

-- a piece is under the fog when most of it lies in ground you haven't explored
local SPOTS = { { 0.5, 0.5 }, { 0.2, 0.2 }, { 0.8, 0.2 }, { 0.2, 0.8 }, { 0.8, 0.8 } }
local function Fogged(mapID, col, row)
    -- (off unless asked for, /relief fog: in game the pieces showed as rectangles with and without depth,
    -- because the fog's own shapes are not a grid; the user's shots, 2026-11-12)
    if not Cfg().fog then return false end
    if not (ns.IsUnexploredAt and ns.IsShown and ns.IsShown("explore")) then return false end
    local n = 0
    for _, s in ipairs(SPOTS) do
        if ns.IsUnexploredAt(mapID, (col + s[1]) / COLS, (row + s[2]) / ROWS) then n = n + 1 end
    end
    return n >= 3
end

local function Unmask(p)
    if p.masked then
        p:RemoveMaskTexture(p.mask)
        p.masked = false
    end
    p.sides = 0
end

-- a picture laid on a host: whole where nothing is under the fog, else in pieces, none under the fog and
-- those beside it ending softly on that side (Edge<n>.tga: 1 north, 2 east, 4 south, 8 west)
local function LayPieces(host, list, file, map, mapID, box)
    local canvas = map:GetCanvas()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local l, r, t, b = Coords(mapID, box)
    local fog, any = {}, false
    for row = 0, ROWS - 1 do
        for col = 0, COLS - 1 do
            local f = Fogged(mapID, col, row)
            fog[row * COLS + col + 1] = f
            any = any or f
        end
    end
    local function Piece(i)
        local p = list[i]
        if not p then
            p = Smooth(host:CreateTexture(nil, "ARTWORK"))
            list[i] = p
        end
        return p
    end
    if not any then
        local p = Piece(1)
        Unmask(p)
        p:SetTexture(file)
        p:SetTexCoord(l, r, t, b)
        p:ClearAllPoints()
        p:SetAllPoints(host.frame or host)
        Lay(host, p, true)
        for i = 2, #list do Lay(host, list[i], false) end
        return 1
    end
    local function Fog(col, row) return col >= 0 and col < COLS and row >= 0 and row < ROWS and fog[row * COLS + col + 1] end
    local shown = 0
    for row = 0, ROWS - 1 do
        for col = 0, COLS - 1 do
            local i = row * COLS + col + 1
            local p = Piece(i)
            local sides = fog[i] and 0 or (Fog(col, row - 1) and 1 or 0) + (Fog(col + 1, row) and 2 or 0) + (Fog(col, row + 1) and 4 or 0) + (Fog(col - 1, row) and 8 or 0)
            if p.sides ~= sides and host.CreateMaskTexture then
                if sides > 0 then
                    if not p.mask then
                        p.mask = host:CreateMaskTexture()
                        p.mask:SetAllPoints(p)
                    end
                    p.mask:SetTexture(ns.MEDIA .. ART .. "Edge" .. sides, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                    if not p.masked then
                        p:AddMaskTexture(p.mask)
                        p.masked = true
                    end
                    p.sides = sides
                else
                    Unmask(p)
                end
            end
            if fog[i] then
                Lay(host, p, false)
            else
                local x0, x1, y0, y1 = col / COLS, (col + 1) / COLS, row / ROWS, (row + 1) / ROWS
                p:SetTexture(file)
                p:SetTexCoord(l + (r - l) * x0, l + (r - l) * x1, t + (b - t) * y0, t + (b - t) * y1)
                p:ClearAllPoints()
                p:SetPoint("TOPLEFT", host.frame or host, "TOPLEFT", x0 * w, -y0 * h)
                p:SetPoint("BOTTOMRIGHT", host.frame or host, "TOPLEFT", x1 * w, -y1 * h)
                Lay(host, p, true)
                shown = shown + 1
            end
        end
    end
    return shown
end

-- a layer's part: light or shade, in this tone
local function Dress(L, role, tone)
    if L.role == role and L.tone == tone then return end
    L.role, L.tone = role, tone
    local c = L.color
    L.host:Dress(role, c[1], c[2], c[3])       -- (pieces made later come dressed: the group's)
end

-- The continent map (continentmap 2.0; mockups\joint\continent-relief-plan.md). One height field a continent
-- (tools\relief_continent.py; Media\Relief\c<continent><layer>.blp), so the depth runs unbroken over
-- every zone border: terrain has no zones. The same seventeen layers and the same sums by the hour. These
-- pictures carry the map's own colour under each spot (blurred wide), so one vertex colour a layer gives every
-- land its own shade and light: CONT_SHADE of that colour for the shade, the colour itself for the light.
-- One texture a layer, at most seven drawn. Laid over the zone maps and the strokes (ns.ZoneArtTop).
local CONTINENT = 1.0        -- the depth's strength on a continent
local CONT_SHADE = 0.19      -- the shade: this much of the baked colour
local CONT_NIGHT, CONT_MOON = { 0.04, 0.05, 0.11 }, { 0.47, 0.55, 0.75 }     -- the shade and the light by night
local CONT_NIGHT_LIT = 0.50  -- how much of the lit side the dark takes on a continent: moonlight on the ranges (a zone: NIGHT_LIT)
local cont = {}              -- [name] = { host, tex }
ns.ReliefGroups = { zone = layer, continent = cont }       -- (tools/relief_lua_test.lua)
local nightHost, nightTex    -- the continent's night: one sheet that multiplies the art under it by the hour's tint
ns.ReliefDefaults.CAST, ns.ReliefDefaults.CONTINENT, ns.ReliefDefaults.CONT_SHADE = CAST, CONTINENT, CONT_SHADE
local contKey, contLaid, contShown = nil, nil, 0
local contPart               -- "whole", or what part of the pictures is laid (ViewPart)

-- A continent's picture is one texture a layer, stretched over the whole land. Zoomed far in on a continent
-- (the wheel between two zones keeps the continent's map; then pan) that one texture is tens of thousands of
-- pixels across on screen, and the game stops drawing it: the layers were counted as shown and nothing was
-- there (the user's shot of the Twilight Grove, 2026-11-15: "then panning, its gone"). Past WHOLE pixels
-- only the part round the view is laid, by its texture coordinates: still one texture a layer. The part is
-- the view and a view's width more on every side, moved in steps of a quarter view, so a pan is a few calls.
-- Returns the part (left, right, top, bottom, as shares of the canvas, within the box given) and its name.
local WHOLE = 10000          -- px on screen: no bigger than this, a picture is laid whole (a zone's is, at any zoom)
local function ViewPart(map, l, r, t, b)
    local canvas, sc = map:GetCanvas(), map.ScrollContainer
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local cs = canvas.GetEffectiveScale and canvas:GetEffectiveScale() or 1
    local px = cs * (GetPhysicalScreenSize and (select(2, GetPhysicalScreenSize()) or 768) or 768) / 768
    if (r - l) * w * px <= WHOLE and (b - t) * h * px <= WHOLE then return l, r, t, b, "whole" end
    if not (sc and sc.GetLeft and canvas.GetLeft) then return l, r, t, b, "whole" end
    local cl, ct = canvas:GetLeft(), canvas:GetTop()
    local sl, sr, st, sb = sc:GetLeft(), sc:GetRight(), sc:GetTop(), sc:GetBottom()
    if not (cl and ct and sl and sr and st and sb and w > 0 and h > 0 and cs > 0) then return l, r, t, b, "whole" end
    local k = sc:GetEffectiveScale() / cs        -- (the view's edges in the canvas's own units)
    local x0, x1 = (sl * k - cl) / w, (sr * k - cl) / w
    local y0, y1 = (ct - st * k) / h, (ct - sb * k) / h
    local vw, vh = x1 - x0, y1 - y0
    if not (vw > 0 and vh > 0) then return l, r, t, b, "whole" end
    local qx, qy = math.floor((x0 + x1) / 2 / (vw / 4) + 0.5), math.floor((y0 + y1) / 2 / (vh / 4) + 0.5)
    local cx, cy = qx * vw / 4, qy * vh / 4
    x0, x1 = math.max(l, cx - vw * 1.5), math.min(r, cx + vw * 1.5)
    y0, y1 = math.max(t, cy - vh * 1.5), math.min(b, cy + vh * 1.5)
    if x1 <= x0 or y1 <= y0 then return l, l, t, t, "none" end        -- (the view is off the pictures)
    return x0, x1, y0, y1, qx .. "," .. qy .. "," .. math.floor(vw * 1e7)
end
ns.ReliefViewPart = ViewPart       -- (tools/relief_lua_test.lua)

-- how much of the close-up shows (Detail.lua's own word for it; without that file, the zoom's)
local function CloseUp(map)
    if ns.DetailShows then return ns.DetailShows(map) end
    if not (ns.IsShown and ns.IsShown("detail")) or (ns.Perf and ns.Perf("detail")) then return 0 end
    local d = ns.db and ns.db.detail
    return math.max(0, math.min(1, (d and d.always) and 1 or (ns.DetailFade and ns.DetailFade(map) or 0)))
end

local function HideContinent()
    if contKey == false then return end
    for _, L in pairs(cont) do L.host:Hide() end
    if nightHost then nightHost:Hide() end
    contKey, contShown = false, 0
end

-- Night on a continent (the user, 2026-11-13: "Make night on continent!"). MapHour.lua tints a zone's art piece
-- by piece; a continent has hundreds of pieces, so here it is one sheet in MOD blend over the zone maps and the
-- strokes, under the depth: the same multiply, one texture. With the hour's tint on, not in performance mode.
local function ContinentNight(map, c, level)
    local r, g, b = 1, 1, 1
    if c.hour and not Bright(true) then r, g, b = ns.MapHourTint() end        -- (a steady light: no hour, no night)
    if r > 0.995 and g > 0.995 and b > 0.995 then
        if nightHost then nightHost:Hide() end
        return
    end
    if not nightHost then
        nightHost = Host(map, "wash")
        nightTex = Smooth(nightHost:CreateTexture(nil, "ARTWORK"))
        nightTex:SetAllPoints(nightHost)
        nightTex:SetColorTexture(1, 1, 1, 1)
        nightTex:SetBlendMode("MOD")
    end
    if nightHost:GetFrameLevel() ~= level then nightHost:SetFrameLevel(level) end
    -- (zoomed far in the sheet is as big as the canvas: the part round the view, as the pictures)
    local x0, x1, y0, y1, part = ViewPart(map, 0, 1, 0, 1)
    if part ~= nightTex.part then
        nightTex.part = part
        nightTex:ClearAllPoints()
        if part == "whole" then
            nightTex:SetAllPoints(nightHost)
        else
            local w, h = nightHost:GetWidth(), nightHost:GetHeight()
            nightTex:SetPoint("TOPLEFT", nightHost, "TOPLEFT", x0 * w, -y0 * h)
            nightTex:SetPoint("BOTTOMRIGHT", nightHost, "TOPLEFT", x1 * w, -y1 * h)
        end
    end
    nightTex:SetVertexColor(r, g, b, 1)
    nightHost:Show()
end

-- the part of the canvas a continent's pictures cover (left, right, top, bottom, as shares of it)
local function ContinentPlace(mapID, data)
    if ns.FOREVER and data.frac then return data.frac[1], data.frac[2], data.frac[3], data.frac[4] end
    local l, r, t, b = Coords(mapID, data.box)
    if l == 0 and r == 1 and t == 0 and b == 1 then      -- (the client could not say)
        if data.frac then return data.frac[1], data.frac[2], data.frac[3], data.frac[4] end
        return
    end
    return -l / (r - l), (1 - l) / (r - l), -t / (b - t), (1 - t) / (b - t)
end
ns.ReliefContinentPlace = ContinentPlace

local function Continent(map, c, mapID, data)
    if not cont.LT then
        local frame = Host(map, "wash")
        for _, name in ipairs(NAMES) do
            local host = Group(frame)
            cont[name] = { host = host, tex = Smooth(host:CreateTexture()) }
        end
    end
    -- over the zone maps, their areas and the strokes
    local level = ns.ArtLevel and ns.ArtLevel(map, "wash") or 2
    local top = ns.ZoneArtTop and ns.ZoneArtTop()
    if top and level < top + 2 then level = top + 2 end
    for _, L in pairs(cont) do
        if L.host:GetFrameLevel() ~= level then L.host:SetFrameLevel(level) end
    end
    ContinentNight(map, c, level - 1)
    local canvas = map:GetCanvas()
    local mapAlpha = map.GetGlobalAlpha and map:GetGlobalAlpha() or map.globalAlpha or 1
    local steady = not c.hour or PerfSteady()
    local hour = steady and 0 or math.floor((ns.MapHourNow and ns.MapHourNow() or 12) * 12)
    local close = CloseUp(map)          -- (how much of the close-up shows: its tiles carry a light already, as in a zone)
    local l, r, t, b = ContinentPlace(mapID, data)
    if not l then return HideContinent() end
    local x0, x1, y0, y1, part = ViewPart(map, l, r, t, b)
    local key = table.concat({ mapID, math.floor(mapAlpha * 50), math.floor(close * 25), canvas:GetWidth(), tostring(c.cast), tostring(c.shade), c.shadeAlpha or 0, tostring(steady), hour, tostring(Bright(true)), part }, ":")
    if key == contKey then return end
    contKey = key
    local shadeA = c.shade and mapAlpha * (V("CONTINENT", CONTINENT) * (1 - close) + V("CLOSE", CLOSE) * close) * (c.shadeAlpha or 100) / 100 or 0
    if shadeA <= 0.02 then
        for _, L in pairs(cont) do L.host:Hide() end
        contShown = 0
        return
    end
    local lay = mapID .. ":" .. canvas:GetWidth() .. ":" .. part
    if lay ~= contLaid then
        contLaid, contPart = lay, part
        local w, h = canvas:GetWidth(), canvas:GetHeight()
        for _, name in ipairs(NAMES) do
            local L = cont[name]
            L.tex:SetTexture(ns.MEDIA .. ART .. "c" .. mapID .. name)
            L.tex:SetTexCoord((x0 - l) / (r - l), (x1 - l) / (r - l), (y0 - t) / (b - t), (y1 - t) / (b - t))
            L.tex:ClearAllPoints()
            L.tex:SetPoint("TOPLEFT", L.host.frame, "TOPLEFT", x0 * w, -y0 * h)
            L.tex:SetPoint("BOTTOMRIGHT", L.host.frame, "TOPLEFT", x1 * w, -y1 * h)
        end
    end
    local e, n, k, dark, lit = Light(nil, steady, Bright(true))
    lit = V("LIT_PART", LIT_PART) * (1 - CONT_NIGHT_LIT * dark)      -- (moonlight: more of it than on a zone)
    local tone = math.floor(dark * 10 + 0.5) / 10
    local plan = Plan(e, n, k * shadeA, lit, c.cast)
    contShown = 0
    for _, name in ipairs(NAMES) do
        local L, role, a = cont[name], plan[name][1], plan[name][2]
        local on = a > 0.004
        if on then
            if L.role ~= role or L.toneAt ~= tone then
                L.role, L.toneAt = role, tone
                local day = role == "lit" and 1 or V("CONT_SHADE", CONT_SHADE)
                local night = role == "lit" and CONT_MOON or CONT_NIGHT
                L.host:Dress(role, day + (night[1] - day) * tone, day + (night[2] - day) * tone, day + (night[3] - day) * tone)
            end
            L.host:SetAlpha(math.min(1, a))
            contShown = contShown + 1
        end
        L.host:SetShown(on)
    end
end

local lastShown, lastLayers = 0, 0
-- Performance mode: one line on its page, two ticks (the user, 2026-11-14, for 1.3: "Relief off in performance
-- mode. Pmode has ticks. 1 line for relief, 2 toggles"). "Off", ticked as it comes: none of it while performance
-- mode is on. Unticked it stays, and "Steady light", ticked as it comes, holds its light in the north-west: one
-- slope layer and one shadow layer in place of two of each. The player's own setting stays either way.
local function PerfOff() return ns.Perf and ns.Perf("relief") or false end

local function Update()
    local map = mapFrame
    if not map then return end
    local c = Cfg()
    local on = c.on and not PerfOff()
    local mapID = map:IsShown() and map:GetMapID()
    local box = mapID and ns.ReliefZones and ns.ReliefZones[mapID]
    -- (the continent's relief lies on Waymark's painted continent: the game's own has its coasts elsewhere)
    local b = ns.db and ns.db.browse
    local painted = b and b.zoneArt and not (ns.Perf and ns.Perf("art"))
    local whole = mapID and on and painted and c.continent ~= false and ns.ReliefContinents and ns.ReliefContinents[mapID]
    if whole then Continent(map, c, mapID, whole) elseif cont.LT then HideContinent() end
    if not (on and box) or (ns.MapOnContinent and ns.MapOnContinent()) then
        if inkHost then
            inkHost:Hide()
            rimHost:Hide()
            for _, L in pairs(layer) do L.host:Hide() end
        end
        shownKey, laidKey, shadeKey = nil, nil, nil
        return
    end
    if not inkHost then
        inkHost = Host(map, "ground")
        local frame = Host(map, "wash")          -- (over the close-up tiles, which are the ground)
        for _, name in ipairs(NAMES) do
            layer[name] = { host = Group(frame), list = {}, color = { 1, 1, 1 } }
        end
        rimHost = Host(map, "wash")
        for i = 1, 2 do rim[i] = Smooth(rimHost:CreateTexture(nil, "ARTWORK")) end
    end
    Lift(inkHost, map)
    Lift(rimHost, map)
    for _, L in pairs(layer) do Lift(L.host, map) end
    local canvas = map:GetCanvas()
    -- how wide the zone is on screen, how see-through the map, how much of the close-up shows
    local scale = canvas:GetEffectiveScale() / ((UIParent and UIParent:GetEffectiveScale()) or 1)
    local thin = canvas:GetWidth() * scale < SMALL
    local mapAlpha = map.GetGlobalAlpha and map:GetGlobalAlpha() or map.globalAlpha or 1
    local close = CloseUp(map)
    local alpha = mapAlpha * (1 - close)     -- for what lies on the painted map alone
    local _, explored = nil, 0
    if ns.ExplorationProgress then _, explored = ns.ExplorationProgress(mapID) end
    local steady = not c.hour or PerfSteady()
    local hour = steady and 0 or math.floor((ns.MapHourNow and ns.MapHourNow() or 12) * 12)   -- (five minutes: the light's step)
    local fogOn = tostring(ns.IsShown and ns.IsShown("explore"))
    local key = table.concat({ mapID, tostring(thin), math.floor(mapAlpha * 50), math.floor(close * 25), explored or 0, fogOn, canvas:GetWidth(),
        tostring(c.fog), tostring(c.cast), tostring(c.shade), c.shadeAlpha or 0, tostring(steady), hour, tostring(c.tga), tostring(c.rim), c.rimAlpha or 0, tostring(c.ink), c.inkAlpha or 0 }, ":")
    if key == shownKey then return end
    shownKey = key

    -- the land's depth: on the painted map where the land lies as painted, and on the close-up
    local onPaint = (ns.ReliefPaintedOff and ns.ReliefPaintedOff[mapID]) and 0 or V("PAINTED", PAINTED)
    local shadeA = c.shade and mapAlpha * (onPaint * (1 - close) + V("CLOSE", CLOSE) * close) * (c.shadeAlpha or 100) / 100 or 0
    if shadeA > 0.02 then
        local folder = ART
        local lay = table.concat({ mapID, explored or 0, canvas:GetWidth(), fogOn, folder, tostring(c.fog) }, ":")
        if lay ~= shadeKey then
            shadeKey = lay
            for _, name in ipairs(NAMES) do layer[name].tone = nil end      -- (another zone: its own tones)
            for _, name in ipairs(NAMES) do
                lastLayers = LayPieces(layer[name].host, layer[name].list, ns.MEDIA .. folder .. mapID .. name, map, mapID, box)
            end
        end
        local e, n, k, dark, lit = Light(nil, steady, Bright())
        local tone = math.floor(dark * 10 + 0.5)
        local plan = Plan(e, n, k * shadeA, lit, c.cast, ZONE_CAST, V("ZONE_SLOPE", ZONE_SLOPE) * (1 - close) + close)     -- (the close-up has no painted crags: full slopes)
        local deep = V("ZONE_SHADE", ZONE_SHADE)
        for _, name in ipairs(NAMES) do
            local L, role = layer[name], plan[name][1]
            local own = ns.ReliefTones and ns.ReliefTones[mapID]
            local a, b = role == "lit" and (own and own[2] or STRAW) or (own and own[1] or UMBER), role == "lit" and MOONLIGHT or NIGHT
            local day = role == "lit" and 1 or deep
            for i = 1, 3 do L.color[i] = a[i] * day + (b[i] - a[i] * day) * tone / 10 end
            Dress(L, role, tone)
            L.host:SetAlpha(math.min(1, plan[name][2]))
            L.host:SetShown(plan[name][2] > 0.004)
        end
    else
        for _, L in pairs(layer) do L.host:Hide() end
    end

    -- the rim, with the close-up. Each half is placed by the ground it covers, so a client whose map of the
    -- zone is cut a little differently (Era's Redridge) still has it true
    local rimA = c.rim and mapAlpha * close * (c.rimAlpha or 100) / 100 or 0
    if rimA > 0.02 then
        if rim.file ~= mapID or rim.w ~= canvas:GetWidth() then
            rim.file, rim.w = mapID, canvas:GetWidth()
            local w, h = canvas:GetWidth(), canvas:GetHeight()
            local l, r, t, b = Coords(mapID, box)
            for i = 1, 2 do
                local tx = rim[i]
                tx:SetTexture(ns.MEDIA .. ART .. mapID .. "R" .. i)
                tx:ClearAllPoints()
                tx:SetPoint("TOPLEFT", rimHost, "TOPLEFT", ((i - 1) / 2 - l) / (r - l) * w, -(0 - t) / (b - t) * h)
                tx:SetPoint("BOTTOMRIGHT", rimHost, "TOPLEFT", (i / 2 - l) / (r - l) * w, -(1 - t) / (b - t) * h)
            end
        end
        rimHost:SetAlpha(rimA)
        rimHost:Show()
    else
        rimHost:Hide()
    end

    -- the strokes on the painted map (to look at; only the zones baked with them)
    local ink = c.ink and alpha > 0.02 and ns.ReliefStrokes and ns.ReliefStrokes[mapID]
    if ink then
        local lay = table.concat({ mapID, tostring(thin), explored or 0, canvas:GetWidth(), fogOn }, ":")
        if lay ~= laidKey then
            laidKey = lay
            lastShown = LayPieces(inkHost, pieces, ns.MEDIA .. ART .. mapID .. (thin and "T" or "H"), map, mapID, box)
        end
        inkHost:SetAlpha((c.inkAlpha or 85) / 100 * alpha)
    end
    inkHost:SetShown(ink and true or false)
end

function ns.ReliefRefresh()
    shownKey = nil
    if contKey then contKey = nil end
    for _, L in pairs(cont) do L.toneAt = nil end
    for _, L in pairs(layer) do L.tone = nil end
    if ns.Safe then ns.Safe("Relief", Update) else Update() end
end

-- What a player may set (Options.lua, The map's look): on, the light by the hour, thrown shadows, the strength.
-- Asked with no value, told with one. Options shows the rows only while this is here, so a build without the
-- relief has no dead rows. The rest stays as tuned (the panel is a dev tool).
local PLAYER = { on = true, hour = true, cast = true, shadeAlpha = 100 }
function ns.ReliefSetting(key, v)
    local c = Cfg()
    if v == nil then return c[key] end
    if PLAYER[key] == nil then return end
    c[key] = v
    ns.ReliefRefresh()
end
ns.ReliefCfg = Cfg       -- (the dev tools that stay in the Lab: Lab\ReliefPanel.lua, the test bench)

-- for /relief info and the test
function ns.ReliefInfo()
    if contShown > 0 then
        local _, _, k, dark = Light(nil, not Cfg().hour)
        return ("relief: the continent's depth shown (%d layers, one texture each, %s; strength %d%%, dark %d%%)"):format(contShown,
            contPart == "whole" and "laid whole" or "the part in view laid", k * 100, dark * 100)
    end
    if not inkHost then return "relief: nothing laid yet (open the map in a zone that has its art)" end
    local e, n, k, dark = Light(nil, not Cfg().hour)
    local on = layer.LT.host:IsShown()
    local n9 = 0
    for _, L in pairs(layer) do if L.host:IsShown() then n9 = n9 + 1 end end
    return ("relief: the depth %s (" .. n9 .. " layers showing, %d textures each; light from %s, strength %d%%, dark %d%%); the rim %s (it shows zoomed in); strokes %s"):format(
        on and "shown" or "hidden", lastLayers, (n > 0.3 and "north" or n < -0.3 and "south" or "") .. (e > 0.3 and "east" or e < -0.3 and "west" or ""),
        k * 100, dark * 100, rimHost:IsShown() and ("shown at %d%%"):format(rimHost:GetAlpha() * 100) or "hidden",
        inkHost:IsShown() and ("shown, %d pieces"):format(lastShown) or "hidden")
end

local function Setup()
    local map = BattlefieldMapFrame
    if not map or mapFrame then return mapFrame ~= nil end
    mapFrame = map
    map:HookScript("OnShow", ns.ReliefRefresh)
    if map.OnMapChanged then
        hooksecurefunc(map, "OnMapChanged", function() C_Timer.After(0, ns.ReliefRefresh) end)
    end
    if ns.OnSettingChanged then
        hooksecurefunc(ns, "OnSettingChanged", function(group, key)
            if group == "relief" or group == "perf" or (group == "browse" and key == "zoneArt") then ns.ReliefRefresh() end
        end)
    end
    ns.ReliefRefresh()
    return true
end

-- one look a second while the map is open (and until the map frame exists: it can come late)
local ticker = ns.TimedFrame and ns.TimedFrame("Relief tick") or CreateFrame("Frame")
local since, lastScale = 0, nil
local lastLeft, lastTop
ticker:SetScript("OnUpdate", function(_, e)
    since = since + e
    -- (zoomed far in on a continent only the part in view is laid: it follows a pan and a zoom at once)
    if contPart and contPart ~= "whole" and contKey and mapFrame and mapFrame:IsShown() then
        local canvas = mapFrame:GetCanvas()
        local x, y = canvas:GetLeft(), canvas:GetTop()
        if x ~= lastLeft or y ~= lastTop then
            lastLeft, lastTop = x, y
            since = RATE
        end
    end
    -- (while the map zooms, every frame: the depth and the rim follow the close-up, not a second behind it)
    if mapFrame and mapFrame:IsShown() and rimHost and mapFrame.GetCanvasScale then
        local s = mapFrame:GetCanvasScale()
        if s ~= lastScale then
            lastScale = s
            since = RATE
        end
    end
    if since < RATE then return end
    since = 0
    if not mapFrame then
        if WaymarkDB then Setup() end
        return
    end
    if mapFrame:IsShown() and (Cfg().on or shownKey) then
        if ns.Safe then ns.Safe("Relief", Update) else Update() end
    end
end)

-- /relief: on and off; /relief shade; /relief hour: the light moves with the hour, or stays in the north-west;
-- /relief hour 18: look at that hour (the map's own pretend hour, MapHour.lua: the tint and the Horizon go
-- with it; /relief now: the real hour again); /relief rim; /relief strokes; /relief tga; /relief info
SLASH_WAYMARKRELIEF1 = "/relief"
SlashCmdList.WAYMARKRELIEF = function(msg)
    local c = Cfg()
    local word, n = (msg or ""):lower():match("^%s*(%a*)%s*([%d.]*)")
    local function Say(s) print("|cffc79a52Waymark|r: " .. s) end
    if word == "hour" and tonumber(n) then
        local hour = math.max(0, math.min(24, tonumber(n)))
        if ns.MapHourPretend then ns.MapHourPretend(hour) end
        c.hour = true
        Say(("the map is lit as at %d:%02d. /relief now: the real hour again."):format(math.floor(hour), (hour % 1) * 60))
    elseif word == "now" then
        if ns.MapHourPretend then ns.MapHourPretend(nil) end
        Say("the map is lit by the real hour.")
    elseif word == "hour" or word == "light" or word == "steady" then
        c.hour = not c.hour
        Say("the land's light " .. (c.hour and "moves with the hour." or "stays in the north-west."))
    elseif word == "shade" or word == "depth" then
        c.shade = not c.shade
        Say("the land's depth is " .. (c.shade and "on." or "off."))
    elseif word == "rim" then
        c.rim = not c.rim
        Say("the rim of a deadly fall is " .. (c.rim and "on: zoom the map in until the ground shows." or "off."))
    elseif word == "ink" or word == "strokes" then
        c.ink = not c.ink
        Say("the strokes on the painted map are " .. (c.ink and "on (to look at; Elwynn, Westfall, Duskwood, Redridge, Thousand Needles)." or "off."))
    elseif word == "cast" or word == "shadows" then
        c.cast = not c.cast
        Say("the shadows the land throws are " .. (c.cast and "on." or "off."))
    elseif word == "continent" or word == "whole" then
        c.continent = c.continent == false
        Say("the depth on the continent map is " .. (c.continent and "on." or "off."))
    elseif word == "panel" or word == "test" then
        if ns.ReliefPanel then ns.ReliefPanel() end
    elseif word == "fog" then
        c.fog = not c.fog
        Say("the depth is " .. (c.fog and "hidden where you haven't explored (in pieces: it can show as rectangles)." or "shown over the whole zone."))
    elseif word == "info" then
        Say(ns.ReliefInfo())
    else
        c.on = not c.on
        Say("the shape of the ground is " .. (c.on and "on, where there is art for the zone." or "off."))
    end
    ns.ReliefRefresh()
    if ns.RefreshControls then ns.RefreshControls() end
end

-- (Its rows on the Lab's ground page went with the move: players' rows are on The map's look, Options.lua; the
-- rim, the strokes, the continent's depth and the fine strengths are /relief words and the test bench's.)
