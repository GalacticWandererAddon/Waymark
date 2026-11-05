local _, ns = ...

-- Minimap replacement (dock.on): the Battlefield Map takes the minimap's place.
-- One square, two faces: the game's own minimap (made square and north up, its
-- round border art hidden) and the map, laid over it at the same size. The
-- map frame (border, header, buttons) stays open on both faces; the minimap
-- face hides only its picture (ApplyFace). Closing the map (its key, its X)
-- switches faces instead; the BFI_DOCK key turns the whole mode off.
--   size      the square's side, UI units (the corner grip sets it too)
--   corner    the square pushed into the screen's top-right corner, our frame
--             and header flush with it (else where the minimap was)
--   wheel     the wheel zooms the minimap; out past its farthest zoom
--             (friction more clicks, the edge glowing on each but the last)
--             opens the map as close as the minimap was. Wheeling in on the
--             map at the minimap's scale or closer, with you in view (the
--             same friction), goes back to the minimap at the matching zoom.
--             A double-click on the map goes back too, at its farthest zoom;
--             a drag on the minimap opens the map there and pans it.
--   mapOnly   never the minimap face (the button by the corner grip)
-- On the minimap face our pins lie over the minimap (the map's canvas kept on
-- you at the minimap's zoom, its picture see-through): the minimap's own
-- tracking blips can't be read by addons, so this is how both show at once.
--   big       the map face as a big map beside the square (the big-map key /
--             arrow), bigW x bigH, at bigTR once dragged; the square stays
--             the minimap meanwhile (DockPlace, SquareFrame)
--
-- The minimap is never put inside our frames: a frame holding it becomes
-- protected and couldn't show or hide in combat (see Dungeon.lua's minimap
-- view). It stays the game's; the map is anchored to the screen over the same
-- spot. Changing the minimap (mask, size, anchor, its art, its buttons) waits
-- for the end of combat; switching faces works in a fight.

local GLOW_FADE = 0.45     -- seconds a blink takes to fade
local PUSH_RESET = 1.0     -- seconds without a click: the friction starts again
local DOUBLE_CLICK = 0.35  -- seconds between the two clicks
local SIZE, BIG_SIZE = 160, 360  -- defaults, UI units
local MIN_SIZE, MAX_SIZE = 100, 400
local SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"
-- (live Forever's own, as its minimap sets it; the old path masks the picture away)
local ROUND_MASK = ns.FOREVER and "ui-hud-minimap-frame-generic-mask" or "Textures\\MinimapMask"
-- across the minimap at each of its zooms (0: farthest), yards, outdoors / indoors
local YARDS_OUT = { 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local YARDS_IN = { 300, 240, 180, 120, 80, 50 }
local DRAG = 6  -- pixels the cursor moves before a press on the minimap is a drag
-- the round minimap's art, hidden while it's square, with the zone name bar
-- (the map's header has the zone) and its X; every texture on the minimap's
-- cluster and backdrop goes too (the title bar's art by any name); the zoom
-- buttons while the wheel zooms
local ART = { "MinimapBorder", "MinimapBorderTop", "MinimapNorthTag", "MinimapCompassTexture",
              "MinimapZoneTextButton", "MinimapToggleButton" }
local ZOOM_BUTTONS = { "MinimapZoomIn", "MinimapZoomOut" }
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }

local function Cfg() return ns.db.dock end
local function InCombat() return InCombatLockdown and InCombatLockdown() end
local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local applied      -- the minimap as it was before we squared it (nil: it's the game's)
local pending      -- a change asked for in combat: done when it ends
local LiftButtons  -- (below, with the buttons)
local mapWas       -- the map's own anchors and strata before docking
local edge, glow, host
local push, pushAt = 0, 0
local lastZoom = 0 -- the minimap's zoom before this frame's wheel click
local atTop = false  -- the docked map at the minimap's scale or closer before this frame's input
local insets       -- the map's border round its scroll area: { left, right, top, bottom }
local undocking
local canvasFixes = 0  -- times the canvas had lost its place on screen (SetupDock)

function ns.Docked() return applied ~= nil end

local function StrataN(f)
    local s = f:GetFrameStrata()
    for n, name in ipairs(STRATA) do if name == s then return n end end
    return 1
end

-- Hiding the round art: into a hidden holder (the game shows some of it again
-- on its own, e.g. the north tag when rotation changes)
local holder = CreateFrame("Frame")
holder:Hide()

local function Stash(r, list)
    if type(r) == "string" then r = _G[r] end
    if not (r and r.SetParent and r.GetParent) or r:GetParent() == holder then return end
    list[#list + 1] = { r, r:GetParent() }
    r:SetParent(holder)
end

-- Glow and rim ----------------------------------------------------------------

local function GlowEdge(point, w, h, orient, fromEdge)
    local t = glow:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetBlendMode("ADD")
    t:SetPoint(point)
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
    local on, off = { 1, 0.78, 0.25, 0.9 }, { 1, 0.78, 0.25, 0 }
    local a, b = fromEdge and on or off, fromEdge and off or on
    if CreateColor and pcall(t.SetGradient, t, orient, CreateColor(unpack(a)), CreateColor(unpack(b))) then
        -- (the current API)
    elseif t.SetGradientAlpha then
        t:SetGradientAlpha(orient, a[1], a[2], a[3], a[4], b[1], b[2], b[3], b[4])
    end
    return t
end

-- a ring of width w, `from` units outside the frame's edge
local function Ring(f, from, w, r, g, b)
    local function Strip(p1, x1, y1, p2, x2, y2)
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(r, g, b, 1)
        t:SetPoint(p1, f, p1, x1, y1)
        t:SetPoint(p2, f, p2, x2, y2)
    end
    local i = from - w
    Strip("TOPLEFT", -from, from, "TOPRIGHT", from, from - w)         -- top
    Strip("BOTTOMLEFT", -from, -from + w, "BOTTOMRIGHT", from, -from) -- bottom
    Strip("TOPLEFT", -from, i, "BOTTOMLEFT", -from + w, -i)           -- left
    Strip("TOPRIGHT", from - w, i, "BOTTOMRIGHT", from, -i)           -- right
end

-- our frames only follow the minimap (anchored to it, never holding it)
local function CreateFrames()
    if edge then return end
    -- a dark rim round the square: a ring, not a filled square behind it (that
    -- showed as a grey square whenever the minimap sank under it, until a
    -- click raised the minimap again)
    edge = CreateFrame("Frame", nil, UIParent)
    edge:SetAllPoints(Minimap)
    edge:EnableMouse(false)
    Ring(edge, 3, 2, 0, 0, 0)
    Ring(edge, 1, 1, 0.42, 0.40, 0.36)
    edge:Hide()
    -- (shown while squared) every frame: the minimap's zoom before the next wheel click
    edge:SetScript("OnUpdate", function() lastZoom = Minimap:GetZoom() end)

    -- the friction's glow, over both faces
    glow = CreateFrame("Frame", nil, UIParent)
    glow:SetAllPoints(Minimap)
    glow:SetFrameStrata("HIGH")
    glow:EnableMouse(false)
    local size = 16
    GlowEdge("TOPLEFT", size, nil, "HORIZONTAL", true):SetPoint("BOTTOMLEFT")
    GlowEdge("TOPRIGHT", size, nil, "HORIZONTAL", false):SetPoint("BOTTOMRIGHT")
    GlowEdge("TOPLEFT", nil, size, "VERTICAL", false):SetPoint("TOPRIGHT")
    GlowEdge("BOTTOMLEFT", nil, size, "VERTICAL", true):SetPoint("BOTTOMRIGHT")
    glow:Hide()
    glow:SetScript("OnUpdate", function(self)
        local a = self.peak * (1 - (GetTime() - self.at) / GLOW_FADE)
        if a <= 0 then self:Hide() else self:SetAlpha(a) end
    end)

    -- the minimap's buttons, moved onto this while docked (LiftButtons)
    host = CreateFrame("Frame", nil, UIParent)
    host:SetAllPoints(Minimap)
    host:EnableMouse(false)
    ns.debugFrames.dockEdge, ns.debugFrames.dockGlow, ns.debugFrames.dockButtons = edge, glow, host
end

local function Blink(n, need)
    glow.peak = 0.5 + 0.5 * n / math.max(1, need - 1)
    glow.at = GetTime()
    glow:SetAlpha(glow.peak)
    glow:Show()
end

-- a click past the end: true once the friction is used up (else a blink)
local function Push()
    local now = GetTime()
    if now - pushAt > PUSH_RESET then push = 0 end
    push, pushAt = push + 1, now
    local need = math.max(1, (Cfg().friction or 2) + 1)
    if push >= need then
        push = 0
        glow:Hide()
        return true
    end
    Blink(push, need)
    return false
end

-- The minimap ------------------------------------------------------------------

local function SideOnMinimap()
    return (Cfg().size or SIZE) * ns.AddonScale() * UIParent:GetEffectiveScale() / Minimap:GetEffectiveScale()
end

-- the game redraws the minimap at a new size on a zoom change; there and back
-- in one frame doesn't count, so back a frame later
local function Redraw()
    local z = Minimap:GetZoom()
    Minimap:SetZoom(z > 0 and z - 1 or z + 1)
    C_Timer.After(0, function() Minimap:SetZoom(z) end)
end

-- where the square's top-right corner goes, in UIParent units from its
-- top-right (negative: in from the edge); corner: our frame's outer edge
-- (border, outside header) flush with the screen's corner
local function CornerOffsets()
    local map = BattlefieldMapFrame
    local right, top = 4, 4  -- (before the map is there to measure)
    if map and insets then
        local k = map:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local out = type(ns.BorderOutset and ns.BorderOutset()) == "number" and ns.BorderOutset() or 0
        right, top = (insets[2] + out) * k, (insets[3] + out) * k
        -- a header standing above the frame
        local h = ns.ZoneHeader
        if h and h:IsShown() and h:GetTop() and map:GetTop() then
            local above = h:GetTop() * h:GetEffectiveScale() / UIParent:GetEffectiveScale() - map:GetTop() * k
            if above > 0 then top = top + above end
        end
    end
    return -right, -top
end

local function PlaceMinimap()
    if not applied or InCombat() then return end
    local mm = Minimap
    if Cfg().corner then
        local x, y = CornerOffsets()
        local k = UIParent:GetEffectiveScale() / mm:GetEffectiveScale()
        mm:ClearAllPoints()
        mm:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", x * k, y * k)
    elseif ns.FOREVER and MinimapCluster and MinimapCluster:GetRight() then
        -- (flush with Edit Mode's minimap box, as with the corner above: where the minimap
        -- sat in it left the square off the box)
        local x, y = CornerOffsets()
        local c, e = MinimapCluster, mm:GetEffectiveScale()
        local k = UIParent:GetEffectiveScale() / e
        mm:ClearAllPoints()
        mm:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", c:GetRight() * c:GetEffectiveScale() / e + x * k,
            c:GetTop() * c:GetEffectiveScale() / e + y * k)
    else
        -- where it was: its top-right corner stays, so a bigger square grows down and left
        mm:ClearAllPoints()
        mm:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", applied.right, applied.top)
    end
end

local function Square()
    if applied or not Minimap then return end
    if ns.GiveBackMinimap then ns.GiveBackMinimap() end  -- (Dungeon.lua's minimap view)
    local mm = Minimap
    local a = { points = {}, w = mm:GetWidth(), h = mm:GetHeight(), stashed = {},
                shape = GetMinimapShape, rotate = GetCVar and GetCVar("rotateMinimap"),
                wheel = mm.IsMouseWheelEnabled and mm:IsMouseWheelEnabled(),
                right = mm:GetRight(), top = mm:GetTop() }
    for i = 1, mm:GetNumPoints() do a.points[i] = { mm:GetPoint(i) } end
    applied = a
    if a.right then PlaceMinimap() end
    local s = SideOnMinimap()
    mm:SetSize(s, s)
    mm:SetMaskTexture(SQUARE_MASK)
    GetMinimapShape = function() return "SQUARE" end  -- (LibDBIcon places buttons by it)
    if a.rotate == "1" then SetCVar("rotateMinimap", "0") end
    for _, name in ipairs(ART) do Stash(name, a.stashed) end
    if Cfg().hideSun then Stash("GameTimeFrame", a.stashed) end  -- (the day / night sun and moon)
    -- (live Forever's title bar, over our header. The tracking button is anchored to it
    -- and stays where it is. The old global name in ART finds nothing there.)
    if Cfg().hideTitle ~= false and MinimapCluster and MinimapCluster.ZoneTextButton then
        Stash(MinimapCluster.ZoneTextButton, a.stashed)
    end
    for _, f in ipairs({ MinimapCluster, MinimapBackdrop }) do
        if f then for _, r in ipairs({ f:GetRegions() }) do Stash(r, a.stashed) end end
    end
    if Cfg().wheel then
        for _, name in ipairs(ZOOM_BUTTONS) do Stash(name, a.stashed) end
        mm:EnableMouseWheel(true)
    end
    CreateFrames()
    edge:SetFrameStrata(mm:GetFrameStrata())
    edge:Show()
    lastZoom = mm:GetZoom()
    Redraw()
end

local function Unsquare()
    if not applied then return end
    local mm, a = Minimap, applied
    applied = nil
    mm:ClearAllPoints()
    for _, p in ipairs(a.points) do mm:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
    mm:SetSize(a.w, a.h)
    mm:SetMaskTexture(ROUND_MASK)
    GetMinimapShape = a.shape
    if a.rotate == "1" then SetCVar("rotateMinimap", "1") end
    for _, s in ipairs(a.stashed) do s[1]:SetParent(s[2]) end
    mm:EnableMouseWheel(a.wheel and true or false)
    if edge then edge:Hide() end
    Redraw()
end

-- The map over it ----------------------------------------------------------------

-- the border round the scroll area, from the scroll area's own anchors (its
-- size lags a layout pass behind a resize; the anchors don't)
local function Insets(map)
    local sc = map.ScrollContainer
    local l, r, t, b
    for i = 1, sc:GetNumPoints() do
        local point, rel, _, x, y = sc:GetPoint(i)
        if rel == map then
            if point == "TOPLEFT" then l, t = x, -y
            elseif point == "BOTTOMRIGHT" then r, b = -x, y end
        end
    end
    if l and r then
        insets = { l, r, t, b }
    elseif not insets and sc:GetWidth() > 0 then
        local bx, by = map:GetWidth() - sc:GetWidth(), map:GetHeight() - sc:GetHeight()
        insets = { bx / 2, bx / 2, by / 2, by / 2 }
    end
    return insets or { 0, 0, 0, 0 }
end

local function IsBig() return applied and Cfg().big and Cfg().face == "map" end

-- MapControls: the map's size while docked: its scroll area the minimap's
-- square, or the big square
-- the big map's own width and height (UI units; its shape is free), from
-- the square bigSize it had before
local function BigWH()
    local c = Cfg()
    local s = c.bigSize or BIG_SIZE
    return c.bigW or s, c.bigH or s
end

function ns.DockedSize(map)
    if not (applied and map.ScrollContainer) then return end
    local i = Insets(map)
    if IsBig() then
        local u = UIParent:GetEffectiveScale() / map:GetEffectiveScale()
        local w, h = BigWH()
        return w * u + i[1] + i[2], h * u + i[3] + i[4]
    end
    local side = Minimap:GetWidth() * Minimap:GetEffectiveScale() / map:GetEffectiveScale()
    return side + i[1] + i[2], side + i[3] + i[4]
end

-- before the map first moves: its own anchors and strata, kept for undocking;
-- and every time one strata over the minimap's (it may change after we dock:
-- /bfi check saw it HIGH with the map still MEDIUM under it)
local function RaiseMap(map)
    if not mapWas then
        mapWas = { strata = map:GetFrameStrata(), points = {} }
        for i = 1, map:GetNumPoints() do mapWas.points[i] = { map:GetPoint(i) } end
    end
    local want = math.min(#STRATA, StrataN(Minimap) + 1)
    if StrataN(map) ~= want then map:SetFrameStrata(STRATA[want]) end
end

-- MapControls: placed so its scroll area's top-right corner is the minimap's
-- (the same square, or the big map growing down and left from it); false
-- when not docked. (Anchored to the screen at that spot, not to the minimap:
-- a frame hanging off a protected one can't move in combat.)
-- The big map isn't over the square: the minimap stays there as it is (its
-- buttons, a border of our style, the zone name: SquareFrame), and the big map
-- opens left of it, tops level, or where you dragged it to (dock.bigTR, its
-- top-right corner in UI units, the corner a resize keeps; only the big map
-- moves while docked).
local BIG_GAP = 24  -- between the square's border and the big map's, map units

function ns.DockPlace(map)
    if not applied then return false end
    local l, r, t = Minimap:GetLeft(), Minimap:GetRight(), Minimap:GetTop()
    if not r then return false end
    RaiseMap(map)
    local k = Minimap:GetEffectiveScale() / map:GetEffectiveScale()
    local i = Insets(map)
    map:ClearAllPoints()
    if IsBig() then
        local pos = Cfg().bigTR
        if pos then
            local u = UIParent:GetEffectiveScale() / map:GetEffectiveScale()
            map:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", pos[1] * u, pos[2] * u)
        else
            local out = type(ns.BorderOutset and ns.BorderOutset()) == "number" and ns.BorderOutset() or 0
            map:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", l * k - BIG_GAP - 2 * out, t * k + i[3])
        end
        return true
    end
    map:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", r * k + i[2], t * k + i[3])
    return true
end

-- MapControls' edge mover: only the big map, and to its own spot
function ns.DockBigMovable() return IsBig() and true or false end
function ns.DockBigMoved(map)
    local k = map:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if map:GetRight() then
        Cfg().bigTR = { map:GetRight() * k, map:GetTop() * k }
        Cfg().bigPos = nil  -- (the top-left one an earlier version kept)
    end
end

-- The canvas scale at which the minimap's side shows as many yards as the
-- minimap at zoom z (default: its farthest, 0), on the big map too. capInfo:
-- the last working-out, for /bfi check.
local capInfo = "not worked out yet"
local function Yards() return IsIndoors and IsIndoors() and YARDS_IN or YARDS_OUT end

local function MinimapScale(sc, z)
    local yards = sc.mapID and ns.MapYards and ns.MapYards(sc.mapID)
    local cw = sc.Child and sc.Child:GetWidth()
    local w = Minimap:GetWidth() * Minimap:GetEffectiveScale() / sc:GetEffectiveScale()
    local list = Yards()
    local across = list[(z or 0) + 1] or list[1]
    local s = yards and cw and cw > 0 and w > 0 and w * yards / (cw * across) or nil
    if not z or z == 0 then
        capInfo = string.format("map %s, %s yd wide, canvas %s, square %s, minimap %d yd: scale %s",
            tostring(sc.mapID), tostring(yards and math.floor(yards)), tostring(cw and math.floor(cw)),
            tostring(math.floor(w)), across, s and string.format("%.2f", s) or "none")
    end
    return s
end

-- the minimap zoom nearest to a canvas scale
local function ZoomForScale(sc, s)
    local s0 = MinimapScale(sc)
    if not (s0 and s and s > 0) then return 0 end
    local list = Yards()
    local want = list[1] * s0 / s  -- yards across at that scale
    local best, z = math.huge, 0
    for i, y in ipairs(list) do
        if math.abs(y - want) < best then best, z = math.abs(y - want), i - 1 end
    end
    return math.min(z, Minimap:GetZoomLevels() - 1)
end


-- the view kept within the zoom steps after they change (the game's wheel
-- code errored every frame on the big map, a view past its steps likely)
local function KeepInRange()
    local map = BattlefieldMapFrame
    local sc = map and map.ScrollContainer
    if not (sc and ns.ZoomRange and ns.ApplyMapView) then return end
    local lo, hi = ns.ZoomRange(sc)
    local s = sc:GetCanvasScale()
    if not (lo and s) then return end
    if s < lo * 0.999 or s > hi * 1.001 then
        pcall(ns.ApplyMapView, sc, Clamp(s, lo, hi), sc.currentScrollX or 0.5, sc.currentScrollY or 0.5)
    end
end

local function LowerMap(map)
    if not mapWas then return end
    local was = mapWas
    mapWas = nil
    map:SetFrameStrata(was.strata)
    -- a map you'd never moved hangs off its tab again
    local pos = ns.db.mapFrame.pos
    if not (pos and pos.kind == "topleft") and was.points[1] then
        map:ClearAllPoints()
        for _, p in ipairs(was.points) do map:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
    end
end

-- The corner grip goes to the bottom-left corner while docked (the square
-- grows down and left from its top-right corner), its art mirrored
local gripWas
local function PlaceGrip(map)
    local grip = ns.debugFrames.grip
    if not grip then return end
    local function Mirror(on)
        for _, t in ipairs({ grip:GetNormalTexture(), grip:GetPushedTexture(), grip:GetHighlightTexture() }) do
            if on then t:SetTexCoord(1, 0, 0, 1) else t:SetTexCoord(0, 1, 0, 1) end
        end
    end
    -- (its "Resize" tooltip off while docked: it came up over the minimap)
    if applied and not gripWas then
        gripWas = { enter = grip:GetScript("OnEnter") }
        for i = 1, grip:GetNumPoints() do gripWas[i] = { grip:GetPoint(i) } end
        grip:ClearAllPoints()
        grip:SetPoint("BOTTOMLEFT", map, "BOTTOMLEFT", 2, 2)
        grip:SetScript("OnEnter", nil)
        Mirror(true)
    elseif not applied and gripWas then
        grip:ClearAllPoints()
        for _, p in ipairs(gripWas) do grip:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
        grip:SetScript("OnEnter", gripWas.enter)
        gripWas = nil
        Mirror(false)
    end
end

-- While the map is big (beside the square), the square keeps a frame of its
-- own: a border of the map's style round the minimap (the game's own style
-- drawn as the dialog one; none: just the rim) and the zone name over it.
-- Our map frame, with its buttons, is the big map meanwhile.
local square
local function SquareFrame()
    if not (applied and IsBig()) then
        if square then square:Hide() end
        return
    end
    if not square then
        square = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        square:EnableMouse(false)
        square.zone = square:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
            square:RegisterEvent(e)
        end
        square:SetScript("OnEvent", function(self) self.zone:SetText(GetMinimapZoneText()) end)
        ns.debugFrames.dockSquare = square
    end
    local b = ns.db.border
    local style = ns.MapBorderStyle and ns.MapBorderStyle() or b.style
    if style == "game" then style = "dialog" end
    local out = ns.DressBorder and ns.DressBorder(square, Minimap, style, b.size, b.gap, b.color)
    if not out then
        square:SetBackdrop(nil)
        square:ClearAllPoints()
        square:SetAllPoints(Minimap)
        out = 3
    end
    square:SetFrameStrata(Minimap:GetFrameStrata())
    square:SetFrameLevel(Minimap:GetFrameLevel() + 2)
    square.zone:ClearAllPoints()
    square.zone:SetPoint("BOTTOM", Minimap, "TOP", 0, out + 2)
    square.zone:SetText(GetMinimapZoneText())
    square:Show()
end

-- the map's size, place, grip and zoom steps after a change; time: glide
local function UpdateMap(time)
    local map = BattlefieldMapFrame
    if not map then return end
    if not applied then LowerMap(map) end  -- (docking raises it: DockPlace)
    if ns.RefreshZoomLevels then ns.RefreshZoomLevels() end
    undocking = not applied
    if ns.UpdateMapShape then ns.Safe("Dock UpdateShape", ns.UpdateMapShape, not time, true, time) end
    undocking = nil
    if ns.RestoreMapPosition then ns.RestoreMapPosition() end
    PlaceGrip(map)
    -- the edge mover (MapControls): its hit box covers the square and 14 px
    -- round it, so it took the minimap's clicks (right-click, pings) and showed
    -- its "drag the edge" tooltip over it; the docked map isn't moved anyway
    -- (the big map moves by it, to its own spot: DockBigMoved)
    if ns.mapMover then ns.mapMover:EnableMouse(applied == nil or IsBig() and true or false) end
    if ns.RefreshBigButton then ns.RefreshBigButton() end
    -- (docked, the map's buttons have their own moved places: MapControls Positions)
    if ns.RelayoutMapButtons then ns.RelayoutMapButtons() end
    if host then host:SetShown(applied ~= nil) end
    SquareFrame()
    if ns.ApplyClickThrough then ns.ApplyClickThrough() end  -- (off while docked)
    if ns.UpdateZoneName then ns.UpdateZoneName() end  -- (big: the zone with the sub-zone; ZoneName Compose)
    KeepInRange()
end

-- MapControls SetShape, after a resize: true when it's ours to place. Docked:
-- on the minimap. Undocking: left to RestorePosition, on your saved spot as
-- it was (SetShape keeps a right-half map's right edge by moving that spot,
-- and from the square back to your size that moved it left every time)
function ns.DockShaping(map)
    if undocking then return true end
    return ns.DockPlace(map)
end

-- Faces ------------------------------------------------------------------------

-- The map frame stays open on both faces, so its border, header and buttons
-- frame the minimap too. On the minimap face the map's canvas stays, kept
-- every frame on you at the minimap's own zoom (MinimapFaceView), with its
-- picture see-through: the minimap shows beneath, its tracking blips and all,
-- and our pins lie on it in the same places. The mouse and wheel go through
-- to the minimap (the pins keep theirs, for tooltips). dock.face: "minimap"
-- or "map", kept over a reload; mapOnly: never the minimap face.
local mouseWas  -- the map's and the scroll area's own mouse settings, while it lets them through
local faded = {}  -- [frame] = its own alpha, see-through on the minimap face

local function MinimapFace() return applied and Cfg().face ~= "map" and not Cfg().mapOnly end
ns.DockMinimapFace = MinimapFace  -- (MapControls: no centering of its own meanwhile)

-- On the minimap face the map's view must reach as close as the minimap's closest
-- zoom, or the pins stop lining up past the closest zoom setting (every minimap
-- level was past it: the pins stayed put as the minimap zoomed). MapControls'
-- zoom levels take this as their top meanwhile; nil off the minimap face.
function ns.DockMinimapReach(sc)
    if not (MinimapFace() and sc and Minimap.GetZoomLevels) then return nil end
    return MinimapScale(sc, Minimap:GetZoomLevels() - 1)
end

-- the map picture's frames (as ClearView.lua finds them: the game's art
-- layers, the explored-area pieces, ours), and the map's own arrow and group
-- dots (the minimap draws its own)
local function EachPicture(map, fn)
    for _, layer in ipairs({ map:GetCanvas():GetChildren() }) do
        if layer.layerIndex ~= nil or layer.bfiOwn or layer.pinTemplate == "MapExplorationPinTemplate"
           or layer.pinTemplate == "GroupMembersPinTemplate" then
            fn(layer)
        end
    end
end

-- The game sets its layers' alpha as it zooms and pans, in its own update:
-- set back once a frame, the art flashed through whenever the game ran last
-- (flicker). So each frame's SetAlpha is hooked: while see-through, the
-- alpha the game asks for is kept (for the map face) and 0 set in the same
-- call. New frames (pins made since) are picked up every frame.
local holding = false  -- the picture is held see-through
local hooked = {}
local zeroing = {}     -- [frame] = true: our own SetAlpha(0) on it (not a field on the game's frames)

local function Zero(f)
    zeroing[f] = true
    f:SetAlpha(0)
    zeroing[f] = nil
end

local function HoldAtZero(f, alpha)
    if not holding or zeroing[f] or faded[f] == nil then return end
    faded[f] = alpha
    Zero(f)
end

local function FadePicture(map, on)
    holding = on
    if on then
        EachPicture(map, function(f)
            if faded[f] == nil then faded[f] = f:GetAlpha() end
            if not hooked[f] then
                hooked[f] = true
                hooksecurefunc(f, "SetAlpha", HoldAtZero)
            end
            if f:GetAlpha() ~= 0 then Zero(f) end
        end)
    else
        for f, a in pairs(faded) do f:SetAlpha(a) end
        wipe(faded)
    end
end

-- the whole canvas, pins too: where the game gives no position on the map
-- (instances), nothing on it lines up with the minimap (the world map's city
-- POIs and its zone hover highlight showed through)
local function FadeCanvas(map, on)
    local c = map:GetCanvas()
    if on then
        if faded[c] == nil then faded[c] = c:GetAlpha() end
        if not hooked[c] then
            hooked[c] = true
            hooksecurefunc(c, "SetAlpha", HoldAtZero)
        end
        if c:GetAlpha() ~= 0 then Zero(c) end
    elseif faded[c] ~= nil then
        local a = faded[c]
        faded[c] = nil
        c:SetAlpha(a)
    end
end

-- The cave view (Cave.lua) and the dungeon view (Dungeon.lua) lie over the
-- map area with mouse of their own: on the minimap face see-through and the
-- mouse through, so the real minimap shows in caves and instances too.
local function Overlays() return { cave = ns.caveView, dungeon = ns.dungeonOverlay } end  -- (either may be missing)

local function OverlaysThrough(on)
    for _, f in pairs(Overlays()) do
        f:SetAlpha(on and 0 or 1)
        f:EnableMouse(not on)
        f:EnableMouseWheel(not on)
    end
end

-- Cave.lua: the cave view's zoom scaled to the square's width against your
-- map's (your normal size's scroll area), so it shows as much of the cave
function ns.DockViewFactor(vw)
    local map = BattlefieldMapFrame
    if not (applied and map and ns.MapManualSize and insets) then return 1 end
    local w = ns.MapManualSize()
    local nw = w and w - insets[1] - insets[2]
    if not (nw and nw > 0 and vw and vw > 0) then return 1 end
    return vw / nw
end

local function ApplyFace()
    local map = BattlefieldMapFrame
    local sc = map and map.ScrollContainer
    if not sc then return end
    if ns.ApplyGroups then ns.ApplyGroups() end  -- (ns.PinAlpha: givers unseen on the minimap face)
    if not (ns.MapCollapsed and ns.MapCollapsed()) then sc:Show() end
    OverlaysThrough(MinimapFace())
    if MinimapFace() then
        if not mouseWas then
            mouseWas = { map:IsMouseEnabled(), sc:IsMouseEnabled(), sc:IsMouseWheelEnabled() }
        end
        map:EnableMouse(false)
        sc:EnableMouse(false)
        sc:EnableMouseWheel(false)
        FadePicture(map, true)
    else
        if mouseWas then
            map:EnableMouse(mouseWas[1])
            sc:EnableMouse(mouseWas[2])
            sc:EnableMouseWheel(mouseWas[3])
            mouseWas = nil
        end
        FadePicture(map, false)
    end
end

-- on the minimap face: the canvas on you at the minimap's zoom (its pins
-- where the minimap's ground is; at a zone's edge the canvas can't go past
-- its art, so pins there sit a little off)
local function MinimapFaceView(map)
    local sc = map.ScrollContainer
    -- (first: in instances there's no position, and the art covered the minimap)
    FadePicture(map, true)
    local s = MinimapScale(sc, Minimap:GetZoom())
    -- (the zoom levels made before this face, or for another map: rebuilt to reach it)
    local _, hi = ns.ZoomRange and ns.ZoomRange(sc)
    if s and hi and s > hi * 1.001 and ns.RefreshZoomLevels then ns.RefreshZoomLevels() end
    local pos = C_Map.GetPlayerMapPosition(map:GetMapID(), "player")
    FadeCanvas(map, not (pos and pos.x))
    if not (s and pos and pos.x and ns.ApplyMapView) then return end
    if ns.StopZoomAnim then ns.StopZoomAnim() end  -- (town view's auto-zoom would pull the other way)
    if math.abs(sc:GetCanvasScale() - s) > s * 0.001 or math.abs((sc.currentScrollX or 0) - pos.x) > 1e-5
       or math.abs((sc.currentScrollY or 0) - pos.y) > 1e-5 then
        pcall(ns.ApplyMapView, sc, s, pos.x, pos.y)
    end
end

-- you (the arrow) inside the map's view
local function PlayerInView(map)
    local sc = map.ScrollContainer
    local pos = C_Map.GetPlayerMapPosition(map:GetMapID(), "player")
    local s, cw, ch = sc:GetCanvasScale(), sc.Child and sc.Child:GetWidth(), sc.Child and sc.Child:GetHeight()
    if not (pos and pos.x and s and cw and cw > 0 and ch > 0) then return false end
    local hw, hh = sc:GetWidth() / (cw * s) / 2, sc:GetHeight() / (ch * s) / 2
    return math.abs(pos.x - (sc.currentScrollX or 0.5)) <= hw and math.abs(pos.y - (sc.currentScrollY or 0.5)) <= hh
end

-- the map open (its addon loaded the first time; not in combat)
local function ShowMap()
    local map = BattlefieldMapFrame
    if map and map:IsShown() then return true end
    if not map and InCombat() then return false end
    if ToggleBattlefieldMap then pcall(ToggleBattlefieldMap) end
    return BattlefieldMapFrame and BattlefieldMapFrame:IsShown()
end

-- the map's view as close as the minimap was, on you
local function ViewAtMinimap()
    local map = BattlefieldMapFrame
    local sc = map and map:IsShown() and map.ScrollContainer
    if not (sc and ns.ZoomRange and ns.ApplyMapView) then return end
    if ns.RefreshZoomLevels then ns.RefreshZoomLevels() end
    -- (the closest zoom on the square; the big map zooms closer, so worked out)
    local _, top = ns.ZoomRange(sc)
    local s = MinimapScale(sc) or top
    local pos = C_Map.GetPlayerMapPosition(map:GetMapID(), "player")
    local x, y = 0.5, 0.5
    if pos and pos.x and (pos.x > 0 or pos.y > 0) then x, y = pos.x, pos.y end
    if s and top then pcall(ns.ApplyMapView, sc, math.min(s, top), x, y) end
end

-- The game redraws the picture's layers only on a zoom: coming back from the
-- see-through minimap face (or the big map growing from it) it showed the
-- minimap until the first wheel click or pan. So a tiny zoom there and back.
local function RedrawPicture(map)
    local sc = map and map.ScrollContainer
    if not (sc and ns.ApplyMapView) then return end
    local s, x, y = sc:GetCanvasScale(), sc.currentScrollX or 0.5, sc.currentScrollY or 0.5
    pcall(ns.ApplyMapView, sc, s * 1.002, x, y)
    C_Timer.After(0, function() pcall(ns.ApplyMapView, sc, s, x, y) end)
end

local function SetFace(face)
    Cfg().face = face
    push = 0
    if glow then glow:Hide() end
    -- (the zoom levels: up to the minimap's closest on its face, your own on the map's)
    if ns.RefreshZoomLevels then ns.RefreshZoomLevels() end
    ApplyFace()
    LiftButtons()
    if face == "map" then RedrawPicture(BattlefieldMapFrame) end
end

-- the map face, as close as the minimap was, on you
local function OpenMap()
    if not ShowMap() then return end
    SetFace("map")
    -- (after the game's own reset and MapControls' recheck of the view)
    C_Timer.After(0.15, ViewAtMinimap)
end

-- back to the minimap face, at zoom z (default its farthest, where the map took over)
local function CloseMap(z)
    if Cfg().mapOnly then
        -- (Map only: never the minimap face; the big map still goes back to the square)
        if IsBig() then
            Cfg().big = false
            UpdateMap()
        end
        return
    end
    if ns.Browsing and ns.Browsing() and ns.BrowseHome then ns.BrowseHome() end
    local wasBig = IsBig()
    SetFace("minimap")
    if wasBig then
        Cfg().big = false
        UpdateMap()
    end
    z = z or 0
    if applied and Minimap:GetZoom() ~= z then Minimap:SetZoom(z) end
end
-- (Dungeon.lua: the dungeon map's Minimap button while docked)
function ns.DockShowMinimap() CloseMap() end

-- MapControls ToggleBigMap while docked: the big map face, grown from the
-- square's corner, and back to the square (still the map face). At once, not
-- in a glide: each step of one rebuilt the zoom steps and the game faded its
-- picture out and in again, so the map went see-through while it grew. The
-- big map opens on your whole zone (fully zoomed out). Back on the square:
-- your own map again (out of the continent or any map browsed to on the big
-- one) and the view the square had (smallView, with its map: keeping the big
-- map's zoom relative to its size gave another one).
local smallView  -- { scale, scrollX, scrollY, mapID, held, minimapZoom = from the minimap face }

function ns.DockToggleBig()
    if not applied then return end
    local map = BattlefieldMapFrame
    local sc = map and map.ScrollContainer
    if IsBig() then
        Cfg().big = false
        local away = ns.Browsing and ns.Browsing()
        if away and ns.BrowseHome then ns.BrowseHome() end
        UpdateMap()
        local v = smallView
        smallView = nil
        -- went big from the minimap face: back to it, at the zoom it had
        -- (the map at its scale came back as the whole zone)
        if v and v.minimapZoom and not Cfg().mapOnly then
            if ns.ReleaseMapView then ns.ReleaseMapView() end  -- (the big map's zoom-out held it)
            SetFace("minimap")
            if Minimap:GetZoom() ~= v.minimapZoom then Minimap:SetZoom(v.minimapZoom) end
            return
        end
        if v and sc and ns.ApplyMapView then
            -- (after the square's layout rebuilds the zoom steps, and after a
            -- map change settles: it resets the view; a change of zoom, so the
            -- picture is redrawn by it too)
            -- (held as it was: the big map's zoom-out held the view)
            if v[5] and ns.HoldMapView then ns.HoldMapView(map)
            elseif ns.ReleaseMapView then ns.ReleaseMapView() end
            local function Put()
                if map:GetMapID() == v[4] then pcall(ns.ApplyMapView, sc, v[1], v[2], v[3]) end
            end
            for _, t in ipairs(away and { 0.15, 0.35 } or { 0, 0.1 }) do C_Timer.After(t, Put) end
            return
        end
    else
        local wasShown = map and map:IsShown()
        local wasMap = Cfg().face == "map"  -- (from the minimap face the view was following you)
        if Cfg().face ~= "map" then
            if not ShowMap() then return end
            SetFace("map")
        end
        if wasShown and sc then
            -- (on the minimap face the canvas was at the minimap's zoom already)
            smallView = { sc:GetCanvasScale(), sc.currentScrollX or 0.5, sc.currentScrollY or 0.5, map:GetMapID(),
                          wasMap and ns.MapViewHeld and ns.MapViewHeld(),
                          minimapZoom = not wasMap and Minimap:GetZoom() or nil }
        end
        Cfg().big = true
        UpdateMap()
        -- the whole zone, once the big size's zoom steps are in
        if ns.MapZoomOutFully then C_Timer.After(0.1, ns.MapZoomOutFully) end
    end
    RedrawPicture(map)
end

-- Buttons ----------------------------------------------------------------------

-- (the big map shows the givers the minimap face leaves to the game, ns.PinAlpha; some of
-- its ways through never reach ApplyFace)
do
    local toggle = ns.DockToggleBig
    function ns.DockToggleBig()
        toggle()
        if ns.ApplyGroups then ns.ApplyGroups() end
    end
end

-- The minimap's buttons (mail, tracking, clock, other addons'...) are its and
-- its cluster's children. Moved onto our host frame, one strata over the map,
-- so the map face doesn't cover them (they keep their anchors, so their
-- places); protected ones (the queue button) can't move, they're lifted to that
-- strata instead. Out of combat only; again after login (addons make theirs
-- late) and on every face switch.
local moved = {}   -- [frame] = its own parent
local lifted = {}  -- [frame] = its own strata
local points = {}  -- [frame] = its own anchors, put back on undocking
local movable = {} -- [frame] = true: holding it moves it (MapControls HoldToMove)
-- (addon buttons, LibDBIcon's: their own left-drag slides them round the minimap's
-- edge toward the cursor, and the two drags together left them well off the
-- pointer. Theirs is off while docked, back on undocking.)
local ownDrag = {} -- [button] = true: has a left-drag of its own
local dragOff = false  -- theirs switched off now
local function OwnDrags(off)
    if dragOff == off then return end
    dragOff = off
    for b in pairs(ownDrag) do
        if off then b:RegisterForDrag() else b:RegisterForDrag("LeftButton") end
    end
end

-- Hold any of them (and its buttons) to move it, as the map's own buttons;
-- saved with the docked set (dock.buttonPos, by its name), placed from the
-- docked frame's corners. Only while docked.
local function MakeMovable(child)
    -- (live Forever's tracking button sits in a frame with no name)
    local name = child:GetName() or (MinimapCluster and child == MinimapCluster.Tracking and "MinimapTracking")
    if movable[child] or not name or not ns.HoldToMove then return end
    movable[child] = true
    local key = "minimap:" .. name
    local function Hold(b)
        b.bfiDockOnly, b.bfiMinimapButton = true, true
        ns.HoldToMove(b, key, child)
        if b.RegisterForDrag and b:GetScript("OnDragStart") and not ownDrag[b] then
            ownDrag[b] = true
            if dragOff then b:RegisterForDrag() end  -- (none: ours only)
        end
    end
    if child:IsMouseEnabled() then Hold(child) end
    for _, b in ipairs({ child:GetChildren() }) do
        if b:IsObjectType("Button") or b:IsObjectType("DropdownButton") then Hold(b) end
    end
end

function LiftButtons()
    if not (applied and host) or InCombat() then return end
    OwnDrags(true)  -- (docked: holding moves them, their own drag off)
    local map = BattlefieldMapFrame
    if map and mapWas then RaiseMap(map) end
    local over = math.max(map and mapWas and StrataN(map) or 1, StrataN(Minimap) + 1)
    local wantN = math.min(#STRATA, over + 1)
    if StrataN(host) ~= wantN then host:SetFrameStrata(STRATA[wantN]) end
    -- never a frame the minimap itself sits in: its cluster keeps it in an
    -- unnamed container, and moving that took the minimap along, up over the
    -- map, the map over it, and so on to TOOLTIP (/bfi check)
    local holds = {}
    local p = Minimap
    while p do holds[p] = true p = p:GetParent() end
    for _, parent in ipairs({ Minimap, MinimapCluster, MinimapBackdrop }) do
        if parent then
            for _, child in ipairs({ parent:GetChildren() }) do
                if not holds[child] and child ~= MinimapBackdrop and child ~= host then
                    if child:IsProtected() then
                        if not lifted[child] then lifted[child] = child:GetFrameStrata() end
                        if StrataN(child) ~= wantN then child:SetFrameStrata(STRATA[wantN]) end
                    else
                        moved[child] = parent
                        if not points[child] then
                            points[child] = {}
                            for i = 1, child:GetNumPoints() do points[child][i] = { child:GetPoint(i) } end
                        end
                        child:SetParent(host)
                        MakeMovable(child)
                    end
                end
            end
        end
    end
    ns.PlaceMinimapButtons()
end

-- each moved one at its saved place, else its own (MapControls RelayoutButtons
-- calls this too, after a move or a right-click back)
local function OwnPoints(child)
    local p = points[child]
    if not p then return end
    child:ClearAllPoints()
    for _, q in ipairs(p) do child:SetPoint(q[1], q[2], q[3], q[4], q[5]) end
end

-- Their saved places are from the docked map frame's corners; while the map
-- is big (away from the square) they're placed from a stand-in of the small
-- frame over the square instead, so they stay with the minimap. (Not moved
-- by hand meanwhile: ns.DockButtonMovable.)
local ghost
local function Ghost(map)
    if not ghost then
        ghost = CreateFrame("Frame", nil, UIParent)
        ghost:EnableMouse(false)
    end
    local i = Insets(map)
    local k = map:GetEffectiveScale() / UIParent:GetEffectiveScale()
    ghost:ClearAllPoints()
    ghost:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -i[1] * k, i[3] * k)
    ghost:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", i[2] * k, -i[4] * k)
    return ghost
end

function ns.PlaceMinimapButtons()
    if ns.PlaceMapOnlyButton then ns.PlaceMapOnlyButton() end  -- (ours: in combat too)
    if InCombat() then return end
    local map = BattlefieldMapFrame
    local saved = Cfg().buttonPos
    for child in pairs(moved) do
        local p = saved and child.bfiMoveKey and saved[child.bfiMoveKey]
        if applied and IsBig() and p and map then
            child:ClearAllPoints()
            child:SetPoint(p[1], p[5] and UIParent or Ghost(map), p[2], p[3], p[4])
        elseif not (applied and ns.PlaceMoved and ns.PlaceMoved(child)) then
            OwnPoints(child)
        end
    end
end

-- MapControls HoldToMove: the docked buttons move only while docked; the
-- minimap's not on the big map (their places are from the small frame)
function ns.DockButtonMovable(b)
    return applied ~= nil and not (b.bfiMinimapButton and IsBig())
end

local function LowerButtons()
    if InCombat() then return end
    for child, parent in pairs(moved) do
        child:SetParent(parent)
        OwnPoints(child)
    end
    for child, strata in pairs(lifted) do child:SetFrameStrata(strata) end
    OwnDrags(false)  -- (their own drag back: undocked, it's theirs again)
    wipe(moved)
    wipe(lifted)
    wipe(points)
end

-- for /bfi check
function ns.DockInfo()
    local map = BattlefieldMapFrame
    local names = {}
    for child in pairs(moved) do
        names[#names + 1] = (child:GetName() or "?") .. (child:IsVisible() and "" or " (hidden)")
    end
    for child, was in pairs(lifted) do
        names[#names + 1] = (child:GetName() or "?") .. " " .. was .. ">" .. child:GetFrameStrata()
            .. (child:IsVisible() and "" or " (hidden)")
    end
    table.sort(names)
    local parent = Minimap:GetParent()
    return string.format("%s, face %s%s, size %d, minimap %s/%d (in %s) %s zoom %d, rim %s/%d, buttons %s, map %s; "
        .. "canvas placed again %d times; %d parked; buttons: %s; %s",
        applied and "docked" or "not docked", tostring(Cfg().face),
        (IsBig() and " big" or "") .. (Cfg().mapOnly and " (map only)" or ""), Cfg().size or 0,
        Minimap:GetFrameStrata(), Minimap:GetFrameLevel(), parent and parent:GetName() or "?",
        Minimap:IsVisible() and "shown" or "hidden", Minimap:GetZoom(),
        edge and edge:GetFrameStrata() or "-", edge and edge:GetFrameLevel() or 0,
        host and host:GetFrameStrata() or "-",
        map and (map:GetFrameStrata() .. (map:IsShown() and " shown" or " closed")) or "not loaded",
        canvasFixes, applied and #applied.stashed or 0, #names > 0 and table.concat(names, ", ") or "none", capInfo)
end

-- MapControls SetMapSize, the corner grip while docked (bottom-left): the
-- square's size, or the big map's; a drag left or down grows it. Let go:
-- kept. nil (right-click): back to the default.
local dragBase  -- { w, h, side } at the drag's start
-- The big map: its width and height apart (a drag left: wider, down: taller;
-- its top-right corner stays). Not resized live: each step rebuilt the zoom
-- steps and the game faded its picture out and in (flicker, the map gone, a
-- game error); a gold outline shows the size meanwhile, the map takes it on
-- letting go.
local outline
local function Outline(map, w, h)
    if not outline then
        outline = CreateFrame("Frame", nil, UIParent)
        outline:SetFrameStrata("DIALOG")
        outline:EnableMouse(false)
        Ring(outline, 1, 2, 1, 0.82, 0)
    end
    if not w then outline:Hide() return end
    local k = map:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local i = Insets(map)
    outline:ClearAllPoints()
    -- (the scroll area's top-right: the map's, in by its insets)
    outline:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", map:GetRight() * k - i[2] * k, map:GetTop() * k - i[3] * k)
    outline:SetSize(w, h)
    outline:Show()
end

local function ResizeBig(map, w, h, dragging)
    local c = Cfg()
    if not w then
        c.bigW, c.bigH = nil, nil
        c.bigSize = BIG_SIZE
    elseif dragging then
        if not dragBase then
            local bw, bh = BigWH()
            dragBase = { w = w, h = h, bw = bw, bh = bh }
        end
        local k = map:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local most = UIParent:GetHeight() * 0.95
        dragBase.nw = math.floor(Clamp(dragBase.bw + (dragBase.w - w) * k, MIN_SIZE * 1.5, UIParent:GetWidth() * 0.95) + 0.5)
        dragBase.nh = math.floor(Clamp(dragBase.bh + (h - dragBase.h) * k, MIN_SIZE * 1.5, most) + 0.5)
        Outline(map, dragBase.nw, dragBase.nh)
        return
    else
        if dragBase and dragBase.nw then c.bigW, c.bigH = dragBase.nw, dragBase.nh end
        dragBase = nil
    end
    Outline(map, nil)
    if ns.UpdateMapShape then ns.Safe("Dock UpdateShape", ns.UpdateMapShape, true, true) end
    RedrawPicture(map)
end

function ns.DockResize(map, w, h, dragging)
    if IsBig() then return ResizeBig(map, w, h, dragging) end
    local c = Cfg()
    local key, default = "size", SIZE
    if not w then
        c[key] = default
    elseif dragging then
        if not dragBase then dragBase = { w = w, h = h, side = c[key] or default } end
        local grow = math.max(dragBase.w - w, h - dragBase.h) * map:GetEffectiveScale() / UIParent:GetEffectiveScale()
        c[key] = math.floor(Clamp(dragBase.side + grow, MIN_SIZE, MAX_SIZE) + 0.5)
    else
        dragBase = nil
    end
    if key == "size" then
        if InCombat() then pending = true return end
        local s = SideOnMinimap()
        Minimap:SetSize(s, s)
    end
    if ns.UpdateMapShape then ns.Safe("Dock UpdateShape", ns.UpdateMapShape, true, true) end
    if not dragging then
        if key == "size" then Redraw() end
        if ns.DockMoveBuffs then ns.Safe("Dock buffs", ns.DockMoveBuffs) end
        if ns.RefreshControls then ns.RefreshControls() end  -- (the Size slider)
    end
end

-- The wheel and the double-click --------------------------------------------------

-- the wheel on the minimap: in / out a zoom; out past the farthest, the map
local function OnMinimapWheel(_, delta)
    if not (applied and Cfg().wheel) then return end
    -- (another addon zooming it on the wheel too: the zoom has moved already,
    -- so we don't zoom it again, and only count the clicks past the end)
    local before = lastZoom
    if delta > 0 then
        push = 0
        if Minimap:GetZoom() == before then
            Minimap:SetZoom(math.min(before + 1, Minimap:GetZoomLevels() - 1))
        end
    elseif before > 0 then
        push = 0
        if Minimap:GetZoom() == before then Minimap:SetZoom(before - 1) end
    elseif ns.HomeIsArt and ns.HomeIsArt() then
        push = 0  -- (in a dungeon or cave its map opens on its button, not the wheel)
    elseif not IsBig() and Push() then  -- (the big map is open beside it already)
        OpenMap()
    end
    lastZoom = Minimap:GetZoom()
end

-- the wheel on the docked map: in at the minimap's scale or closer, the
-- minimap at the zoom nearest the map's. Only with you in view (else it
-- would jump to you from where you'd panned to); not on the big map (only
-- its key or arrow makes it small again), not with map only on.
local function OnMapWheel(_, delta)
    if not (applied and Cfg().wheel and delta > 0 and atTop) or IsBig() or Cfg().mapOnly then
        if delta < 0 then push = 0 end
        return
    end
    if ns.Browsing and ns.Browsing() then return end  -- (another map: Browse.lua's)
    local map = BattlefieldMapFrame
    if not PlayerInView(map) then push = 0 return end
    if Push() then CloseMap(ZoomForScale(map.ScrollContainer, map.ScrollContainer:GetCanvasScale())) end
end

-- a double-click on the map face (two clicks, not drags): back to the minimap
local downX, downY, lastClick = 0, 0, 0
local function OnMapDown(_, button)
    if button == "LeftButton" then downX, downY = GetCursorPosition() end
end
-- (map only, or the big map, where it stays the map: back on you at the
-- minimap's farthest zoom, followed again, with a flash)
local function OnMapUp(_, button)
    if not applied or button ~= "LeftButton" or Cfg().face ~= "map" then return end
    local x, y = GetCursorPosition()
    if math.abs(x - downX) + math.abs(y - downY) > 6 then lastClick = 0 return end  -- (a drag)
    local now = GetTime()
    if now - lastClick > DOUBLE_CLICK then lastClick = now return end
    lastClick = 0
    if Cfg().mapOnly or IsBig() then
        if ns.Browsing and ns.Browsing() and ns.BrowseHome then ns.BrowseHome() end
        if ns.ReleaseMapView then ns.ReleaseMapView() end
        ViewAtMinimap()
        Blink(1, 2)
    else
        CloseMap()
    end
end

-- the cave and dungeon views take the map's double-click too (they cover it)
local overlaysHooked = {}
local function HookOverlays()
    for _, f in pairs(Overlays()) do
        if not overlaysHooked[f] then
            overlaysHooked[f] = true
            f:HookScript("OnMouseDown", OnMapDown)
            f:HookScript("OnMouseUp", function(self, button) ns.Safe("Dock double-click", OnMapUp, self, button) end)
        end
    end
end

-- A drag on the minimap face: once the cursor has moved, the map face takes
-- over at the zoom it's at (the canvas is there already) and the drag pans it
-- until the button is let go; the view then stays where you put it. Out of
-- combat (the minimap's own mouse-up, its ping, is set aside meanwhile).
local press   -- { x, y }: the left button went down on the minimap face there
local drag    -- { x, y, scrollX, scrollY, scale }: the pan under way
local upWas   -- the minimap's OnMouseUp, set aside during the drag

-- (No right-click to the map face: a right-click that just missed a pin dropped you
-- out of the minimap's zoom, the user. The wheel, a drag and its button do it.)
local function OnMinimapDown(_, button)
    if not MinimapFace() then return end
    -- (clicks here reach the minimap, not the map's Browse: an ink mark's or a quest
    -- ground's menu is asked for here. Not with a modifier, as on the map.)
    if button == "RightButton" and not IsModifierKeyDown() then
        -- (a frame later: the menu closes on any press, this one too)
        C_Timer.After(0, function()
            ns.Safe("Dock menus", function()
                if not (ns.InkMenuAt and ns.InkMenuAt()) and ns.QuestGroundMenuAt then ns.QuestGroundMenuAt() end
            end)
        end)
    elseif button == "LeftButton" and not InCombat() then
        press = { GetCursorPosition() }
    end
end

local function Drag(map)
    local sc = map.ScrollContainer
    if press then
        if not IsMouseButtonDown("LeftButton") then press = nil return end
        local x, y = GetCursorPosition()
        if math.abs(x - press[1]) + math.abs(y - press[2]) < DRAG then return end
        drag = { press[1], press[2], sc.currentScrollX or 0.5, sc.currentScrollY or 0.5, sc:GetCanvasScale() }
        press = nil
        upWas = Minimap:GetScript("OnMouseUp")
        Minimap:SetScript("OnMouseUp", nil)
        SetFace("map")
        -- (the press began on the minimap: the map gets no mouse-up without its mouse-down)
        sc:EnableMouse(false)
        if ns.HoldMapView then ns.HoldMapView(map) end
    end
    if not drag then return end
    if not IsMouseButtonDown("LeftButton") then
        drag = nil
        sc:EnableMouse(true)
        if ns.HoldMapView then ns.HoldMapView(map) end
        -- (a frame later: the mouse-up goes by first)
        C_Timer.After(0, function()
            if upWas and not InCombat() then Minimap:SetScript("OnMouseUp", upWas) end
            upWas = nil
        end)
        return
    end
    local child = sc.Child
    local px = child and child:GetWidth() * child:GetEffectiveScale()  -- (the canvas on screen, pixels)
    local py = child and child:GetHeight() * child:GetEffectiveScale()
    if not (px and px > 0 and py > 0 and ns.ApplyMapView) then return end
    local x, y = GetCursorPosition()
    -- (the canvas follows the cursor: the view's centre moves the other way; y runs down the map)
    pcall(ns.ApplyMapView, sc, drag[5], drag[3] - (x - drag[1]) / px, drag[4] + (y - drag[2]) / py)
end

-- Map only (the button in the bottom-left corner): never the minimap face
local onlyButton

local function RefreshOnlyButton()
    if not onlyButton then return end
    onlyButton:SetShown(applied ~= nil)
    local on = Cfg().mapOnly and true or false
    onlyButton.icon:SetDesaturated(not on)
    onlyButton.icon:SetAlpha(on and 1 or 0.7)
end

local function ToggleMapOnly()
    Cfg().mapOnly = not Cfg().mapOnly
    if not applied then return end
    if Cfg().mapOnly and Cfg().face ~= "map" then
        if ShowMap() then
            SetFace("map")
            C_Timer.After(0.15, ViewAtMinimap)
        end
    else
        ApplyFace()
    end
    RefreshOnlyButton()
    if onlyButton and onlyButton:IsMouseOver() then onlyButton:GetScript("OnEnter")(onlyButton) end
end

-- the setting (Options.lua's Minimap replacement page), as the button did
function ns.DockSetMapOnly(on)
    if (Cfg().mapOnly and true or false) ~= (on and true or false) then ToggleMapOnly() end
end

local function CreateOnlyButton(map)
    local b = CreateFrame("Button", nil, map)
    b:SetSize(16, 16)
    b:SetFrameLevel(ns.ButtonLevel(map))  -- (with the map's other buttons)
    -- hold to move it, as the map's buttons (saved with the docked set,
    -- dock.buttonPos.dockMapOnly); else right of the corner grip, which sits
    -- in the corner while docked
    function ns.PlaceMapOnlyButton()
        if ns.PlaceMoved and ns.PlaceMoved(b) then return end
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", map, "BOTTOMLEFT", 20, 2)
    end
    ns.PlaceMapOnlyButton()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    ns.SetArt(b.icon, "Interface\\Icons\\INV_Misc_Map03")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", ToggleMapOnly)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine("Map only")
        GameTooltip:AddLine(Cfg().mapOnly and "On: the map never turns into the minimap"
            or "Off: the minimap shows at its own zooms", 1, 1, 1, true)
        ns.Hints({ { "Click", Cfg().mapOnly and "off" or "on" }, { "Hold", "move it" } })
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- (after its OnClick: holding wraps it, so a move doesn't also click)
    b.bfiDockOnly = true
    if ns.HoldToMove then ns.HoldToMove(b, "dockMapOnly") end
    onlyButton = b
    ns.debugFrames.dockMapOnly = b
    RefreshOnlyButton()
end

-- The Battlefield Map's own key (Shift+M) does nothing while docked: its keys
-- are bound over to a button that does nothing (as Tracker.lua's quest log
-- key). Out of combat only (bindings can't change in a fight: after it then).
-- Set on docking and at login, not on every UPDATE_BINDINGS: the override
-- itself fires that.
local noKey = CreateFrame("Button", "WaymarkDockNoKey", UIParent)
local keyPending
local MAP_KEYS = { "TOGGLEBATTLEFIELDMINIMAP", "TOGGLEBATTLEFIELDMAP" }

local function BlockMapKey()
    if InCombat() then keyPending = true return end
    keyPending = nil
    ClearOverrideBindings(noKey)
    if not applied then return end
    for _, action in ipairs(MAP_KEYS) do
        for _, key in ipairs({ GetBindingKey(action) }) do
            SetOverrideBindingClick(noKey, false, key, "WaymarkDockNoKey")
        end
    end
end

-- Apply ------------------------------------------------------------------------

function ns.ApplyDock()
    if not (ns.db and Minimap) then return end
    if InCombat() then pending = true return end
    pending = nil
    if Cfg().on then
        if applied then
            -- a new size, or the wheel switched: square it afresh
            LowerButtons()
            Unsquare()
        end
        Square()
        ShowMap()  -- (our frame stays round the minimap)
    else
        LowerButtons()
        Unsquare()
        Cfg().big = false
    end
    UpdateMap()
    PlaceMinimap()  -- (now the map's insets and header are known)
    if applied then UpdateMap() end
    LiftButtons()
    ApplyFace()
    RefreshOnlyButton()
    BlockMapKey()
    if ns.RefreshViewGlow then ns.RefreshViewGlow() end  -- (the dock button's, Options.lua)
    if ns.DockHookBuffs then ns.DockHookBuffs() end
    ns.Safe("Dock buffs", ns.DockMoveBuffs)
end

-- Buffs out of the way ----------------------------------------------------------
-- The game's buffs and weapon enchants sit in the screen's top-right corner, left of
-- where the minimap is. A square grown bigger (or the map open beside it) would lie
-- over them: while docked they move left, both by the same step so they keep their
-- order, to end 10 px left of the leftmost of the square and the map near the top.
-- Back where the game had them once undocked. Never in a fight (waits for its end).
local BUFF_FRAMES = { "BuffFrame", "TemporaryEnchantFrame" }
local buffHome = {}   -- [frame] = { points, right, top } as the game had it (UIParent units)
local buffBusy, buffWaiting

local function UIUnits(f)
    return f:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

local function BuffRestore(f)
    local h = buffHome[f]
    if not h then return end
    buffBusy = true
    f:ClearAllPoints()
    for _, p in ipairs(h.points) do f:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
    buffBusy = nil
    buffHome[f] = nil
end

function ns.DockMoveBuffs()
    if InCombat() then buffWaiting = true return end
    buffWaiting = nil
    -- the left edge of what's docked near the top of the screen (nil: nothing)
    local left
    if applied then
        local top = UIParent:GetTop()
        for _, f in ipairs({ Minimap, BattlefieldMapFrame }) do
            if f and f:IsVisible() and f:GetLeft() and f:GetTop() then
                local k = UIUnits(f)
                if f:GetTop() * k > top - 160 then
                    local l = f:GetLeft() * k
                    left = left and math.min(left, l) or l
                end
            end
        end
    end
    -- how far the furthest right of them must move
    local frames, over = {}, 0
    for _, name in ipairs(BUFF_FRAMES) do
        local f = _G[name]
        if f and f.GetPoint and f:GetRight() then
            frames[#frames + 1] = f
            if left then
                if not buffHome[f] then
                    local h = { points = {}, right = f:GetRight() * UIUnits(f), top = f:GetTop() * UIUnits(f) }
                    for i = 1, f:GetNumPoints() do h.points[i] = { f:GetPoint(i) } end
                    buffHome[f] = h
                end
                over = math.max(over, buffHome[f].right - (left - 10))
            end
        end
    end
    for _, f in ipairs(frames) do
        local h = buffHome[f]
        if left and over > 0 and h then
            buffBusy = true
            f:ClearAllPoints()
            f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT",
                (h.right - over - UIParent:GetRight()) / f:GetScale(), (h.top - UIParent:GetTop()) / f:GetScale())
            buffBusy = nil
        else
            BuffRestore(f)
        end
    end
end

-- (the game puts them back now and then: after it, ours again)
-- (on ns: ApplyDock, above it in the file, calls it)
local buffHooked
function ns.DockHookBuffs()
    if buffHooked then return end
    buffHooked = true
    for _, name in ipairs(BUFF_FRAMES) do
        local f = _G[name]
        if f and f.SetPoint then
            hooksecurefunc(f, "SetPoint", function()
                if buffBusy or not applied then return end
                buffHome[f] = nil  -- (where the game wants it now: its new home)
                C_Timer.After(0, function() ns.Safe("Dock buffs", ns.DockMoveBuffs) end)
            end)
        end
    end
    -- the square or the map changing size, opening or closing
    for _, f in ipairs({ Minimap, BattlefieldMapFrame }) do
        if f then
            for _, s in ipairs({ "OnSizeChanged", "OnShow", "OnHide" }) do
                f:HookScript(s, function()
                    if applied or next(buffHome) then
                        C_Timer.After(0, function() ns.Safe("Dock buffs", ns.DockMoveBuffs) end)
                    end
                end)
            end
        end
    end
end

-- the BFI_DOCK key
function ns.ToggleDock()
    Cfg().on = not Cfg().on
    ns.ApplyDock()
    if ns.UpdateQuickButton then ns.UpdateQuickButton() end  -- (the dock button)
    if ns.RefreshControls then ns.RefreshControls() end
end

-- Setup ------------------------------------------------------------------------

-- The map face's view over a reload: the map opens afresh and the game shows
-- the whole zone, so the view (map, zoom, centre, held or following) is kept
-- on logout (dock.lastView) and put back once the world is in, on the same
-- map; elsewhere, the minimap's farthest zoom on you. (The minimap face sets
-- its own view anyway.)
local function SaveLastView()
    local map = BattlefieldMapFrame
    local sc = map and map.ScrollContainer
    if not (applied and sc and map:IsShown() and not MinimapFace()) then Cfg().lastView = nil return end
    Cfg().lastView = { map:GetMapID(), sc:GetCanvasScale(), sc.currentScrollX or 0.5, sc.currentScrollY or 0.5,
                       ns.MapViewHeld and ns.MapViewHeld() or false }
end

local function RestoreLastView()
    local map = BattlefieldMapFrame
    local sc = map and map:IsShown() and map.ScrollContainer
    if not (applied and sc and ns.ApplyMapView) or MinimapFace() then return end
    local v = Cfg().lastView
    if v and v[1] == map:GetMapID() then
        if v[5] and ns.HoldMapView then ns.HoldMapView(map) end
        pcall(ns.ApplyMapView, sc, v[2], v[3], v[4])
    elseif not IsBig() then
        ViewAtMinimap()
    end
end

-- the minimap side: at login, map or no map
local events = CreateFrame("Frame")
local restored  -- (the view is put back once per login)
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        Minimap:HookScript("OnMouseWheel", function(self, delta)
            ns.Safe("Dock minimap wheel", OnMinimapWheel, self, delta)
        end)
        Minimap:HookScript("OnMouseDown", OnMinimapDown)
        if Cfg().on and not ns.standBy then ns.ApplyDock() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- the minimap draws its new size once the world is in; buttons other
        -- addons made since; the header placed by now
        for _, t in ipairs({ 0.5, 3 }) do
            C_Timer.After(t, function()
                if not applied or InCombat() then return end
                Redraw()
                PlaceMinimap()
                UpdateMap()
                LiftButtons()
            end)
        end
        -- (after the map has opened and settled; again in case the game reset it)
        if not restored then
            restored = true
            for _, t in ipairs({ 0.6, 1.5 }) do C_Timer.After(t, RestoreLastView) end
        end
    elseif event == "PLAYER_LOGOUT" then
        SaveLastView()
    elseif pending then
        ns.ApplyDock()
    else
        LiftButtons()  -- (asked for in combat)
        if keyPending then BlockMapKey() end
        if buffWaiting then ns.Safe("Dock buffs", ns.DockMoveBuffs) end
    end
end)

-- the map side, once the Battlefield Map's addon has loaded
function ns.SetupDock(map)
    local sc = map.ScrollContainer
    if not sc then return end
    sc:HookScript("OnMouseWheel", function(self, delta)
        ns.Safe("Dock map wheel", OnMapWheel, self, delta)
    end)
    sc:HookScript("OnMouseDown", OnMapDown)
    sc:HookScript("OnMouseUp", function(self, button) ns.Safe("Dock double-click", OnMapUp, self, button) end)
    -- (its insets are only known after a layout pass)
    sc:HookScript("OnSizeChanged", function() if applied then ns.DockPlace(map) end end)
    -- Docked, the canvas can lose its place on screen (its GetLeft nil) while you
    -- pan, resize or move a minimap button; the game's own update measures the
    -- cursor from it and errored (MapCanvas_ScrollContainerMixin.lua:748). The
    -- ticker below places it again, but may run after the game's update: so the
    -- same check here, first.
    local gameUpdate = sc:GetScript("OnUpdate")
    if gameUpdate then
        sc:SetScript("OnUpdate", function(self, ...)
            if applied and self.Child and not self.Child:GetLeft() and ns.ApplyMapView then
                canvasFixes = canvasFixes + 1
                pcall(ns.ApplyMapView, self, self:GetCanvasScale(), self.currentScrollX or 0.5, self.currentScrollY or 0.5)
                if not self.Child:GetLeft() then return end  -- (still nowhere: skip the game's this frame)
            end
            return gameUpdate(self, ...)
        end)
    end
    -- docked, the frame stays: closing the map (its key, its X) switches faces
    -- instead. (Not when its parent hid it, e.g. the whole UI hidden: then
    -- it's still "shown" itself.)
    map:HookScript("OnHide", function(self)
        push = 0
        if not applied or self:IsShown() then return end
        C_Timer.After(0, function()
            if not applied or self:IsShown() then return end
            self:Show()
            if Cfg().face == "map" then CloseMap() else OpenMap() end
        end)
    end)
    map:HookScript("OnShow", function() ApplyFace() end)
    -- (Map only: no button any more, its setting on the Minimap replacement page)
    HookOverlays()  -- (Cave.lua and Dungeon.lua set theirs up just before)
    -- every frame: the wheel needs to know where the zoom stood before it
    local ticker = ns.TimedFrame("Dock tick", map)
    local since = 0
    ticker:SetScript("OnUpdate", function(_, dt)
        if not applied then atTop = false return end
        Drag(map)
        if MinimapFace() then
            atTop = false
            if sc:IsVisible() then MinimapFaceView(map) end
        else
            local s0 = MinimapScale(sc)
            atTop = s0 and (sc.targetScale or sc:GetCanvasScale()) >= s0 * 0.98 or false
        end
        -- Scrolling the big map, the canvas lost its place on screen (its
        -- GetLeft nil): the game's wheel and click code errored on it and
        -- the map froze until a pan placed the canvas again. Placed again
        -- here the same way (the view as it is); counted for /bfi check.
        if applied and sc:IsVisible() and sc.Child and not sc.Child:GetLeft() and ns.ApplyMapView then
            canvasFixes = canvasFixes + 1
            pcall(ns.ApplyMapView, sc, sc:GetCanvasScale(), sc.currentScrollX or 0.5, sc.currentScrollY or 0.5)
        end
        since = since + dt
        if applied and since > 0.25 then
            since = 0
            KeepInRange()
        end
    end)
    if applied then
        UpdateMap()
        PlaceMinimap()
        UpdateMap()
        LiftButtons()
        ApplyFace()
    end
end

-- Edit Mode: the game's minimap box is the cluster, which the docked square isn't in. While
-- Edit Mode is open the square keeps up with the box (PlaceMinimap), and the corner
-- setting goes off, you've picked a place. (Nothing to save: the layout keeps the box.)
if ns.FOREVER and EventRegistry and MinimapCluster then
    local watch = CreateFrame("Frame")
    watch:Hide()
    local x0, y0
    local function Follow()
        if not applied or InCombat() then return end
        local c = MinimapCluster
        local l, t, s = c:GetLeft(), c:GetTop(), c:GetEffectiveScale()
        if not (l and t) then return end
        local x, y = l * s, t * s
        if not x0 then x0, y0 = x, y return end
        if math.abs(x - x0) < 0.5 and math.abs(y - y0) < 0.5 then return end
        x0, y0 = x, y
        if Cfg().corner then
            Cfg().corner = false
            if ns.RefreshControls then ns.RefreshControls() end
        end
        PlaceMinimap()
        UpdateMap()
    end
    watch:SetScript("OnUpdate", function() ns.Safe("Dock Edit Mode", Follow) end)
    EventRegistry:RegisterCallback("EditMode.Enter", function()
        x0, y0 = nil, nil
        watch:Show()
    end, watch)
    EventRegistry:RegisterCallback("EditMode.Exit", function()
        watch:Hide()
        -- (leaving without saving puts the box back: a frame later, it's there)
        C_Timer.After(0, function() ns.Safe("Dock Edit Mode", Follow) end)
    end, watch)
end
