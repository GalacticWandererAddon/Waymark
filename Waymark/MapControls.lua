local _, ns = ...

-- Battlefield Map frame controls: drag to move, keep centered on the player,
-- player arrow and group icon size. Written against the game's own map API.

local function Cfg() return ns.db.mapFrame end

local defaultW, defaultH  -- the map's own size from the game, taken at setup (Shape, Zoom)

local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Leatrix Maps can do the same things; both at once would fight over the map
function ns.LeatrixBattleMapActive()
    return LeaMapsDB and LeaMapsDB["EnhanceBattleMap"] == "On" or false
end

-- Moving ------------------------------------------------------------------

-- The map itself is moved. (Blizzard hangs it off its "Zone Map" tab; moving
-- the tab instead made the map jump away from the cursor.) The saved position
-- is the map's top-left corner in UIParent units, so changing the map's scale
-- keeps that corner where it is.

local function TopLeftUI(map)
    local s = map:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return map:GetLeft() * s, map:GetTop() * s
end

-- x, y: UIParent units from its bottom-left
local function PinTopLeft(map, x, y)
    local s = UIParent:GetEffectiveScale() / map:GetEffectiveScale()
    map:ClearAllPoints()
    map:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x * s, y * s)
end

-- The tab: hidden if you asked (it sits above the map and keeps it from
-- reaching the top of the screen), else kept just above the moved map. Placed
-- on its own, not anchored to the map: Blizzard anchors the map to the tab, and
-- anchoring both ways round would be a loop.
-- Hiding the tab: it goes into a hidden holder frame. A hidden parent keeps it
-- out of sight however often the game shows or fades it in (it does on every
-- mouse-over), with no code of ours running inside Blizzard's. (Hooking its Show
-- and hiding it again fought the game's fade on every mouse-over.)
local tabHolder = CreateFrame("Frame")
tabHolder:Hide()
local tabParent  -- the tab's own parent, to put it back

local function PlaceTab(map)
    local tab = BattlefieldMapTab
    if not tab then return end
    -- (docked over the minimap, Dock.lua: the tab would float where the map was)
    if Cfg().hideTab or (ns.Docked and ns.Docked()) then
        if tab:GetParent() ~= tabHolder then
            tabParent = tab:GetParent()
            tab:SetParent(tabHolder)
        end
        return
    elseif tab:GetParent() == tabHolder then
        tab:SetParent(tabParent or UIParent)
    end
    local pos = Cfg().pos
    if not (pos and pos.kind == "topleft") then return end
    local s = map:GetEffectiveScale() / tab:GetEffectiveScale()
    tab:ClearAllPoints()
    tab:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", map:GetLeft() * s, map:GetTop() * s)
end

-- pos.w: the width (UIParent units) pos.x was saved for; pos.right: the map stood in the right half
-- of the screen, so a change of shape keeps its right edge (SetShape). Both are saved: after a load
-- the frame has the game's own size and the screen's size isn't final, so neither can be read then.
local function SavePosition(map)
    local x, y = TopLeftUI(map)
    local w = map:GetWidth() * map:GetEffectiveScale() / UIParent:GetEffectiveScale()
    Cfg().pos = { kind = "topleft", x = x, y = y, w = w, right = x + w / 2 > UIParent:GetWidth() / 2 }
end

local function RestorePosition(map)
    -- docked over the minimap (Dock.lua): its place, not yours
    if ns.DockPlace and ns.DockPlace(map) then PlaceTab(map) return end
    local pos = Cfg().pos
    -- (positions saved by the earlier tab-moving version are left alone)
    if pos and pos.kind == "topleft" then
        -- never off the screen: at least a corner's worth of it left on
        -- (undocking once pushed it thousands of units off the left edge). Kept on as shown, not as saved:
        -- at load the screen's size isn't final (the UI scale comes seconds later), and writing the clamp
        -- back pulled a map in a corner toward the middle at every load (players on CurseForge, 2026-11-08)
        -- All of it on, at the size it has now (2026-11-18, a player's map stood a quarter above his screen
        -- and stayed there): it was "a corner's worth". A map bigger than the screen keeps its top-left on.
        local s = map:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local w, h = map:GetWidth() * s, map:GetHeight() * s
        local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
        PinTopLeft(map, Clamp(pos.x, 0, math.max(0, sw - w)), Clamp(pos.y, math.min(h, sh), sh))
    end
    PlaceTab(map)
end
function ns.RestoreMapPosition()
    if BattlefieldMapFrame then RestorePosition(BattlefieldMapFrame) end
end

-- "Reset the map's place" (Options, Shape page; the header's menu): the map opens in the middle of the
-- screen. Docked over the minimap: the square back on the minimap's spot, the big map beside it.
function ns.ResetMapPlace()
    local map = BattlefieldMapFrame
    if not (map and ns.db) then return end
    if ns.db.dock then ns.db.dock.bigTR = nil end
    -- (the world map's own place too, shown or not: fix 8 of reports/2026-11-22 world map switch behaviour.md)
    Cfg().worldPos = nil
    if ns.WorldMapUp and ns.WorldMapUp() and ns.NormalMapSize then
        -- (the small map's own place, centred for its own size: the critic's find)
        local s = map:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local nw, nh = ns.NormalMapSize(map)
        nw, nh = (nw or 300) * s, (nh or 200) * s
        local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
        Cfg().smallPos = { kind = "topleft", x = math.max(0, (sw - nw) / 2), y = math.min(sh, (sh + nh) / 2), w = nw, right = false }
    end
    if ns.Docked and ns.Docked() then
        if ns.DockSpotReset then ns.DockSpotReset() end
        return
    end
    if not map:IsShown() and ToggleBattlefieldMap then pcall(ToggleBattlefieldMap) end
    local s = map:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local w, h = map:GetWidth() * s, map:GetHeight() * s
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    Cfg().pos = { kind = "topleft", x = math.max(0, (sw - w) / 2), y = math.min(sh, (sh + h) / 2), w = w, right = false }
    RestorePosition(map)
end

-- ...and placed again when the UI scale lands (it doesn't always come with a size change; the clock
-- showed it, Clock.lua). Twice a second, not while it's being moved or in combat
local mapMoving
do
    local watch, last, wait = CreateFrame("Frame"), nil, 0
    watch:SetScript("OnUpdate", function(_, dt)
        wait = wait - dt
        if wait > 0 then return end
        wait = 0.5
        local map = BattlefieldMapFrame
        if not (map and ns.db) then return end
        local now = UIParent:GetEffectiveScale() .. ":" .. UIParent:GetWidth() .. ":" .. UIParent:GetHeight()
        if now == last then return end
        if last == nil then last = now return end
        if mapMoving or InCombatLockdown() then return end   -- (later: tried again)
        last = now
        ns.Safe("MapControls scale", RestorePosition, map)
    end)
end

local mover

-- An invisible frame just behind the map area whose hit box sticks out 14px all
-- round, so dragging the map's edge moves it while the middle still pans
local function SetupMover(map)
    local area = map.ScrollContainer or map
    mover = CreateFrame("Frame", nil, area)
    mover:SetAllPoints()
    mover:SetHitRectInsets(-14, -14, -14, -14)
    mover:SetFrameLevel(math.max(0, area:GetFrameLevel() - 1))
    mover:EnableMouse(true)
    ns.mapMover = mover  -- (Dock.lua: its mouse off while docked; it caught the minimap's clicks)

    -- moving the map by hand (the edge here, the header in ZoneName.lua)
    local moving = false
    function ns.MapMoveStart()
        if Cfg().locked then return end  -- (locked in place: the header's menu, Placement)
        -- (docked over the minimap, Dock.lua: only the big map moves, to its own spot)
        if ns.Docked and ns.Docked() and not (ns.DockBigMovable and ns.DockBigMovable()) then
            if ns.DockSquareDragStart then ns.DockSquareDragStart() end  -- (the square itself, by its header)
            return
        end
        -- detach from the tab exactly where it is, so it starts under the cursor
        local x, y = TopLeftUI(map)
        PinTopLeft(map, x, y)
        map:SetMovable(true)
        map:SetClampedToScreen(true)
        if map.SetDontSavePosition then pcall(map.SetDontSavePosition, map, true) end  -- we save it
        map:StartMoving()
        moving, mapMoving = true, true
    end
    function ns.MapMoveStop()
        if ns.DockSquareDragStop and ns.DockSquareDragStop() then return end
        if not moving then return end
        moving, mapMoving = false, false
        map:StopMovingOrSizing()
        if ns.Docked and ns.Docked() then
            if ns.DockBigMoved then ns.DockBigMoved(map) end  -- (not your map's own spot)
        else
            SavePosition(map)
        end
        RestorePosition(map)  -- back to our own anchor, tab follows
    end
    mover:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then ns.MapMoveStart() end
    end)
    mover:SetScript("OnMouseUp", function() ns.MapMoveStop() end)
    mover:SetScript("OnEnter", function()
        GameTooltip:SetOwner(mover, "ANCHOR_CURSOR")
        ns.Hints({ { "Drag", "move the map" } })
        GameTooltip:Show()
    end)
    mover:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Zone bounds ---------------------------------------------------------------

-- fitting the zone: the zoom option, or auto width (a narrowed map showing the
-- whole art would be mostly empty)
local function FitOn() return ns.db.zoom.fitZone or Cfg().autoWidth end

-- A view centre (0..1) at scale s, kept so the view stays inside the zone's
-- bounds where it can: following you to the zone's edge stops scrolling there
-- and the arrow moves on toward the edge, instead of showing the next zone.
-- Along an axis where the view is bigger than the zone: the zone's middle.
local function ZoneClamp(sc, s, x, y)
    if not (FitOn() and ns.ZoneBounds and sc.mapID and s and s > 0) then return x, y end
    local l, t, r, b, aw, ah = ns.ZoneBounds(sc.mapID)
    if not l then return x, y end
    local hw, hh = sc:GetWidth() / s / 2, sc:GetHeight() / s / 2  -- half the view, art pixels
    local function Axis(v, lo, hi, half, size)
        if hi - lo <= half * 2 then return (lo + hi) / 2 / size end
        return Clamp(v, (lo + half) / size, (hi - half) / size)
    end
    return Axis(x, l, r, hw, aw), Axis(y, t, b, hh, ah)
end

-- Centering ---------------------------------------------------------------

local pauseUntil = 0  -- a short settle after the view is restored
local ribbon          -- the map as a band round you (Collapse.lua's ribbon; ns.MapRibbon below)
local anim            -- an auto-zoom animation in progress (Zoom section)

-- After you pan or zoom yourself the view stays where you put it until you
-- move: heldAt is where you stood then ({ mapID, x, y }; false = not on this map).
local HOLD_MOVE = 0.001  -- of the map: a few yards
local heldAt

local function Hold(map)
    local mapID = map:GetMapID()
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    heldAt = (pos and pos.x) and { mapID, pos.x, pos.y } or false
end
-- (Browse.lua: a view it put on a new map is yours, held as if you'd zoomed there)
ns.HoldMapView = Hold
-- (Dock.lua's double-click: back on you, followed again)
function ns.ReleaseMapView() heldAt = nil end
-- (Dock.lua's big map: whether the square's view was yours or following you)
function ns.MapViewHeld() return heldAt ~= nil end

-- still held? Lets go once you've moved (or the map changed)
local function Held(mapID, pos)
    if heldAt == nil then return false end
    if heldAt and heldAt[1] == mapID and pos
       and math.abs(pos.x - heldAt[2]) < HOLD_MOVE and math.abs(pos.y - heldAt[3]) < HOLD_MOVE then
        return true
    end
    if heldAt == false and pos == nil then return true end  -- (nowhere to measure from yet)
    heldAt = nil
    return false
end

local function IsWorld(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    return info and Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.World or false
end

local function CenterOnPlayer(map)
    local sc = map.ScrollContainer
    if not (sc and sc.SetPanTarget and sc.CalculateScrollExtentsAtScale) then return end
    if anim or GetTime() < pauseUntil or IsShiftKeyDown() then return end
    if sc.IsPanning and sc:IsPanning() then return end

    local mapID = map:GetMapID()
    if IsWorld(mapID) then return end  -- (the world map stays on its continents)
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")  -- nil in instances
    if not (pos and pos.x) or (pos.x == 0 and pos.y == 0) then return end
    if Held(mapID, pos) then return end

    -- limits at the zoom it's heading to: at the current one, mid-zoom, the
    -- limits are too tight and the pan has to catch up later (a jump)
    local s = sc.targetScale or sc:GetCanvasScale()
    local x, y = ZoneClamp(sc, s, pos.x, pos.y)
    local minX, maxX, minY, maxY = sc:CalculateScrollExtentsAtScale(s)
    sc:SetPanTarget(Clamp(x, minX, maxX), Clamp(y, minY, maxY))
end

-- Zoom ----------------------------------------------------------------------

local ZOOM_STEP = 1.5  -- each extra level is this much closer than the last

-- The world map's continents together, with a margin: left, top, right, bottom
-- (0..1 of the art), cached per map. Fully out, the world view centres on them,
-- not on the art's middle.
local WORLD_MARGIN = 0.02
local worldCache = {}
local function WorldBounds(mapID)
    if worldCache[mapID] ~= nil then return unpack(worldCache[mapID] or {}) end
    local kids = C_Map.GetMapChildrenInfo and C_Map.GetMapChildrenInfo(mapID, Enum.UIMapType.Continent)
    local l, t, r, b = math.huge, math.huge, -math.huge, -math.huge
    for _, k in ipairs(kids or {}) do
        local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, k.mapID, mapID)
        if ok and minX and maxX > minX and maxY > minY then
            l, r = math.min(l, minX), math.max(r, maxX)
            t, b = math.min(t, minY), math.max(b, maxY)
        end
    end
    if l >= r then worldCache[mapID] = false return end
    local v = { math.max(0, l - WORLD_MARGIN), math.max(0, t - WORLD_MARGIN),
                math.min(1, r + WORLD_MARGIN), math.min(1, b + WORLD_MARGIN) }
    worldCache[mapID] = v
    return unpack(v)
end

-- The world map always opens on its continents, even with the map kept on you
local function Follows(sc)
    return (Cfg().center or ribbon) and not IsWorld(sc.mapID)
end

-- The scale at which the zone's own bounds (ns.ZoneBounds) fill the view, and
-- the bounds' centre (0..1); nil when off or unknown. The world map: its
-- continents (WorldBounds), always.
local function ZoneFit(sc)
    if sc.mapID and IsWorld(sc.mapID) then
        local l, t, r, b = WorldBounds(sc.mapID)
        local layers = l and C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(sc.mapID)
        local a = layers and layers[1]
        local w, h = sc:GetWidth(), sc:GetHeight()
        if not (a and a.layerWidth and a.layerWidth > 0 and w and h and w > 0 and h > 0) then return end
        local aw, ah = a.layerWidth, a.layerHeight
        return math.min(w / ((r - l) * aw), h / ((b - t) * ah)), (l + r) / 2, (t + b) / 2
    end
    if not (FitOn() and ns.ZoneBounds and sc.mapID) then return end
    local l, t, r, b, aw, ah = ns.ZoneBounds(sc.mapID)
    if not l or r <= l or b <= t then return end
    local w, h = sc:GetWidth(), sc:GetHeight()
    if not (w and h and w > 0 and h > 0) then return end
    -- the canvas is the art's size, so at scale s the view shows w/s by h/s of it
    return math.min(w / (r - l), h / (b - t)), (l + r) / 2 / aw, (t + b) / 2 / ah
end

-- The scale at which the art covers the whole view. The game's furthest zoom
-- fits the art inside instead, which on a map you've made taller or narrower
-- than 3:2 leaves empty bands; zoomed out never goes past this.
local function CoverScale(sc)
    local layers = sc.mapID and C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(sc.mapID)
    local l = layers and layers[1]
    if not (l and l.layerWidth and l.layerWidth > 0 and l.layerHeight > 0) then return end
    return math.max(sc:GetWidth() / l.layerWidth, sc:GetHeight() / l.layerHeight)
end

-- One measure of zoom: how big the map art is drawn on screen, in screen
-- pixels per pixel of the art ("art at 2x": each art pixel two screen pixels
-- wide). It's the same whatever the map's size, its scale or the zone, so the
-- closest zoom, close-up detail, auto-zoom's "how close" and the zoom kept
-- between zones all use it. (The game's own zoom steps move with the map's
-- size, and measuring against them made a big map lose its close-up detail.)
local function PixelsPerUnit(sc)
    return sc:GetEffectiveScale() * ns.PhysicalPerUI()
end

-- screen pixels per UI unit at scale 1 (the UI is 768 units tall)
function ns.PhysicalPerUI()
    local physH
    if GetPhysicalScreenSize then physH = select(2, GetPhysicalScreenSize()) end
    return (physH and physH > 0) and physH / 768 or 1
end

local function ArtX(sc, s)  -- canvas scale -> art on screen
    return s * PixelsPerUnit(sc)
end

local function ScaleForX(sc, x)  -- art on screen -> canvas scale
    return x / PixelsPerUnit(sc)
end
ns.ScaleForX = ScaleForX
ns.ArtX = function(map)
    local sc = map and map.ScrollContainer
    return sc and ArtX(sc, sc:GetCanvasScale()) or 0
end

-- the art layer the game draws at a scale (most zones have one)
local function LayerFor(base, s)
    local layer = base[1] and base[1].layerIndex or 1
    for _, l in ipairs(base) do
        if l.scale <= s * 1.001 then layer = l.layerIndex end
    end
    return layer
end

-- The big map zooms as far past fully out as your normal size does. The closest
-- zoom is art on screen, and fully out a big map already draws the zone bigger,
-- so it had fewer steps left; close-up detail (times closer than fully out)
-- then came in only on the last one or two.
-- the scroll area's size at your normal map size (the big map's own otherwise)
function ns.NormalViewSize(sc)
    local map = BattlefieldMapFrame
    if not (Cfg().big and map and ns.NormalMapSize) then return sc:GetWidth(), sc:GetHeight() end
    local w, h = ns.NormalMapSize(map)
    if not w then return sc:GetWidth(), sc:GetHeight() end
    -- (the border round the scroll area is the same at any size)
    return math.max(1, w - (map:GetWidth() - sc:GetWidth())), math.max(1, h - (map:GetHeight() - sc:GetHeight()))
end

local function BigReach(sc)
    -- (docked over the minimap, Dock.lua: your map's big doesn't apply; it
    -- reached 145x art there)
    if ns.Docked and ns.Docked() then return 1 end
    if not (Cfg().big and ns.ZoneLowestScale and sc.mapID) then return 1 end
    local big = ns.ZoneLowestScale(sc, sc.mapID)
    local normal = ns.ZoneLowestScale(sc, sc.mapID, ns.NormalViewSize(sc))
    if not (big and normal and normal > 0) then return 1 end
    return math.max(1, big / normal)
end

-- The scroll container keeps its zoom steps in zoomLevels ({ scale, layerIndex },
-- closest last) and never zooms past the last one. Rebuilt by the game on every
-- map change, hence the hook; ours replace the game's: from fully out (the zone
-- fitted, no empty bands) to the closest zoom (zoom.closestX, art on screen),
-- in even steps of 1.5x split into zoom.smoothness smaller ones.
local function AddZoomLevels(sc)
    local levels = sc.zoomLevels
    if not (levels and levels[1] and type(levels[#levels].scale) == "number") then return end
    -- the game's own levels (for their art layers and how far out they go),
    -- kept for when we rebuild the same list later
    if sc.bfiBaseFor ~= levels or sc.bfiBaseMap ~= sc.mapID then
        local base = {}
        for _, l in ipairs(levels) do
            if not l.bfiExtra then base[#base + 1] = l end
        end
        if not base[1] then return end
        sc.bfiBase, sc.bfiBaseFor, sc.bfiBaseMap = base, levels, sc.mapID
    end
    local base = sc.bfiBase
    local z = ns.db.zoom
    local fit = ZoneFit(sc)
    -- (the world map: fully out is the zone's whole map, not the zone's own outline fitted, which cut off its edges,
    -- Darnassus off Teldrassil, at any shape of window. The user, 2026-11-22. Azeroth's own fit stays)
    if fit and ns.WorldMapUp and ns.WorldMapUp() and not IsWorld(sc.mapID) then fit = nil end
    local lo = math.max(base[1].scale, fit or 0, CoverScale(sc) or 0)
    local hi = math.max(lo * ZOOM_STEP, ScaleForX(sc, (z.closestX or 8) * BigReach(sc)))
    -- a continent: as far as a little past where every zone opens (ZoneArt.lua),
    -- no further and no less (the closest zoom setting is for zone maps: on a
    -- continent it stopped short of the bigger zones, so they never opened)
    local cap = ns.OverviewCap and ns.OverviewCap(sc)
    if cap then hi = math.max(lo * ZOOM_STEP, cap) end
    -- docked on the minimap face: as close as the minimap's closest zoom (Dock.lua)
    local reach = ns.DockMinimapReach and ns.DockMinimapReach(sc)
    if reach then hi = math.max(hi, reach * 1.01) end
    local ratio = ZOOM_STEP ^ (1 / math.max(1, math.floor(z.smoothness or 1)))
    local n = math.max(1, math.ceil(math.log(hi / lo) / math.log(ratio) - 0.01))
    wipe(levels)
    for i = 0, n do
        local s = lo * (hi / lo) ^ (i / n)
        levels[#levels + 1] = { scale = s, layerIndex = LayerFor(base, s), bfiExtra = true,
                                bfiFit = i == 0 and fit ~= nil and fit >= lo * 0.999 or nil }
    end
    -- if the closest zoom just came nearer, don't stay zoomed past it
    local top = levels[#levels].scale
    if sc.targetScale and sc.targetScale > top and sc.SetZoomTarget then sc:SetZoomTarget(top) end
    -- ... and not further out than the zone fit
    local bottom = levels[1].scale
    if sc.targetScale and sc.targetScale < bottom and sc.SetZoomTarget then sc:SetZoomTarget(bottom) end
end

-- Fully zoomed out on a fitted zone: look at the zone, not the art's middle
-- (where the game puts it). Not when the map follows you anyway.
local function CenterZoneFit(sc)
    local levels = sc.zoomLevels
    if not (levels and levels[1]) or Follows(sc) then return end
    if ns.WorldMapUp and ns.WorldMapUp() and not IsWorld(sc.mapID) then return end   -- (the whole map, its own middle)
    if (sc.targetScale or sc:GetCanvasScale()) > levels[1].scale * 1.01 then return end
    local _, cx, cy = ZoneFit(sc)
    if not cx or not sc.SetPanTarget then return end
    local minX, maxX, minY, maxY = sc:CalculateScrollExtentsAtScale(levels[1].scale)
    if minX then cx, cy = Clamp(cx, minX, maxX), Clamp(cy, minY, maxY) end
    sc:SetPanTarget(cx, cy)
end

-- Zooming out: the game zooms around the cursor and would show the
-- neighbouring zones until something re-centred. Head for a view inside the
-- zone instead, the pan and the zoom in one move. (Fully out, that's the zone's
-- middle.) Zooming in is left alone: that's you looking at something.
local function ZoomOutInZone(sc)
    local s = sc.targetScale or sc:GetCanvasScale()
    local x = sc.targetScrollX or sc.currentScrollX
    local y = sc.targetScrollY or sc.currentScrollY
    if not (s and x and y and sc.SetPanTarget) then return end
    local cx, cy = ZoneClamp(sc, s, x, y)
    if cx == x and cy == y then return end
    local minX, maxX, minY, maxY = sc:CalculateScrollExtentsAtScale(s)
    if minX then cx, cy = Clamp(cx, minX, maxX), Clamp(cy, minY, maxY) end
    sc:SetPanTarget(cx, cy)
end

-- the map's scale changed (BattlefieldInfo's ns.SetScale), or the closest zoom:
-- the levels' art size on screen changes with it
function ns.RefreshZoomLevels()
    local sc = BattlefieldMapFrame and BattlefieldMapFrame.ScrollContainer
    if sc then pcall(AddZoomLevels, sc) end
end

local function ZoomRange(sc)
    local levels = sc.zoomLevels
    if not (levels and levels[1]) then return end
    return levels[1].scale, levels[#levels].scale
end
ns.ZoomRange = ZoomRange

-- How close as a setting (town, city and cluster zoom): art on screen (ArtX),
-- 0 = fully out; kept within this map's zoom range
local function ScaleAtX(sc, x)
    local lo, hi = ZoomRange(sc)
    if not lo then return end
    if not x or x <= 0 then return lo end
    return Clamp(ScaleForX(sc, x), lo, hi)
end

-- Where the zoom is, to put on another map: fully out and all the way in stay
-- that (their art size differs with the zone and the map), else the art size
local function ZoomSpot(sc, s)
    local lo, hi = ZoomRange(sc)
    if not (lo and s and s > 0) then return end
    if s <= lo * 1.01 then return { out = true } end
    if s >= hi * 0.99 then return { top = true } end
    return { x = ArtX(sc, s) }
end

local function ScaleAtSpot(sc, spot)
    local lo, hi = ZoomRange(sc)
    if not (lo and spot) then return end
    if spot.out then return lo end
    if spot.top then return hi end
    return ScaleAtX(sc, spot.x)
end

-- 0 = fully out, 1 = closest (including our extra levels)
function ns.ZoomFraction(map)
    local sc = map and map.ScrollContainer
    if not sc then return 0 end
    local lo, hi = ZoomRange(sc)
    if not lo or hi <= lo then return 0 end
    return Clamp((sc:GetCanvasScale() - lo) / (hi - lo), 0, 1)
end

-- where the zoom is, counted in wheel steps: 1 = fully out, n = closest, with
-- fractions while a zoom animates. Returns pos, n.
function ns.ZoomLevelPos(map)
    local sc = map and map.ScrollContainer
    local levels = sc and sc.zoomLevels
    if not (levels and levels[1]) then return 1, 1 end
    local s, n = sc:GetCanvasScale(), #levels
    for i = 1, n - 1 do
        local a, b = levels[i].scale, levels[i + 1].scale
        if s <= b then
            local t = (b > a and s > 0) and (math.log(s / a) / math.log(b / a)) or 0
            return i + Clamp(t, 0, 1), n
        end
    end
    return n, n
end

-- "In town" is decided in Town.lua (shared with the Towns & cities profile)
local function InTown()
    if ns.InTownView then return ns.InTownView() end
    return IsResting()
end

-- a capital: city view (its own switch and how close, cityView)
local function InCity()
    return ns.InCityView and ns.InCityView() or false
end

-- town or city view wants to zoom (and follow)
local function TownZoomOn()
    return ns.db.townView.enabled and ns.db.townView.zoom
end

local function AnyAutoZoom()
    return TownZoomOn() or ns.db.cityView.zoom
end

-- Animated zoom: scale and view centre move together, one eased curve (slow
-- start, slow finish), with the centre heading for your arrow. Leaving it to
-- the game zoomed around the old centre and only then panned, so it jumped.
local animFrame = CreateFrame("Frame")  -- (anim itself is declared with pauseUntil)

local function StopAnim()
    local a = anim
    anim = nil
    animFrame:SetScript("OnUpdate", nil)
    if a and a.onStop then a.onStop() end  -- (a glide cut short: GlideView)
end

local function PlayerPos(map)
    local pos = C_Map.GetPlayerMapPosition(map:GetMapID(), "player")
    if pos and pos.x and (pos.x > 0 or pos.y > 0) then return pos.x, pos.y end
end

-- one frame of view: scale kept within the zoom steps (a view saved before the
-- map's shape or the zone fit changed can be further out than now allowed),
-- centre clamped to what's valid at that scale
local function ApplyView(sc, s, x, y)
    local levels = sc.zoomLevels
    if levels and levels[1] then s = Clamp(s, levels[1].scale, levels[#levels].scale) end
    if sc.CalculateScrollExtentsAtScale then
        local minX, maxX, minY, maxY = sc:CalculateScrollExtentsAtScale(s)
        if minX then x, y = Clamp(x, minX, maxX), Clamp(y, minY, maxY) end
    end
    -- (true: go right to x, y. Without it the game only goes part of the way on a change of
    -- scale, and the pan target below then slid the view, pins and all, the rest of it)
    if sc.InstantPanAndZoom then sc:InstantPanAndZoom(s, x, y, true) end
    -- and where it's heading: the scroll area glides "current" toward "target"
    -- on its own, so a stale target pulls the view back to the old centre
    -- after the animation (it missed the arrow, then centering had to fix it)
    sc:SetZoomTarget(s)
    sc:SetPanTarget(x, y)
end
ns.ApplyMapView = ApplyView  -- (Browse.lua: the view across a map change)
ns.MapZoneClamp = ZoneClamp   -- (Dock.lua: a view on you starts on the zone's useful part, as following would glide to)

local function AnimateTo(map, toScale)
    local sc = map.ScrollContainer
    local from = sc:GetCanvasScale()
    if not (from and from > 0 and toScale and toScale > 0) then return end
    anim = {
        s0 = from, s1 = toScale, t0 = GetTime(),
        x0 = sc.currentScrollX or 0.5, y0 = sc.currentScrollY or 0.5,
        dur = math.max(0.1, ns.db.zoom.animTime or 1),
    }
    animFrame:SetScript("OnUpdate", function()
        if not (anim and map:IsVisible()) then StopAnim() return end
        local t = Clamp((GetTime() - anim.t0) / anim.dur, 0, 1)
        local e = t * t * (3 - 2 * t)                  -- ease in and out
        local s = anim.s0 * (anim.s1 / anim.s0) ^ e    -- even steps in zoom
        local px, py = PlayerPos(map)
        if px then px, py = ZoneClamp(sc, s, px, py) end  -- (lands where centering would)
        local x = anim.x0 + ((px or anim.x0) - anim.x0) * e
        local y = anim.y0 + ((py or anim.y0) - anim.y0) * e
        if not pcall(ApplyView, sc, s, x, y) or t >= 1 then StopAnim() end
    end)
end
ns.StopZoomAnim = StopAnim

-- A glide to a view asked for (Browse.lua's right-click):
-- zoom and centre in one eased move (ease-out: it answers the click at once),
-- the zoom even in log scale, the centre moving with it as a zoom about one
-- spot on screen does, and clamped at every step to what's valid at that zoom.
-- (Left to the game, the zoom ran ahead of the pan: zoomed out near the
-- continent's edge, empty space opened past the map until the pan caught up.)
-- done() at the end; onStop() if anything stops it first (your wheel or drag).
function ns.GlideView(map, s1, x1, y1, dur, done, onStop)
    local sc = map.ScrollContainer
    local s0 = sc and sc:GetCanvasScale()
    if not (s0 and s0 > 0 and s1 and s1 > 0 and x1 and y1) then return false end
    StopAnim()
    local a = { glide = true, t0 = GetTime(), dur = dur, s0 = s0, s1 = s1, onStop = onStop,
                x0 = sc.currentScrollX or 0.5, y0 = sc.currentScrollY or 0.5, x1 = x1, y1 = y1 }
    anim = a
    animFrame:SetScript("OnUpdate", function()
        if anim ~= a then return end
        if not map:IsVisible() then StopAnim() return end
        local t = Clamp((GetTime() - a.t0) / a.dur, 0, 1)
        local e = 1 - (1 - t) ^ 3
        local s = a.s0 * (a.s1 / a.s0) ^ e
        local k = e
        if math.abs(a.s1 - a.s0) > a.s0 * 0.001 then k = (1 / s - 1 / a.s0) / (1 / a.s1 - 1 / a.s0) end
        local ok = pcall(ApplyView, sc, s, a.x0 + (a.x1 - a.x0) * k, a.y0 + (a.y1 - a.y0) * k)
        if not ok or t >= 1 then
            a.onStop = ok and nil or a.onStop
            StopAnim()
            if ok and done then done() end
        end
    end)
    return true
end

-- how long a glide over this much zoom takes: longer for a longer way
function ns.GlideTime(s0, s1, base, most)
    local steps = math.abs(math.log(math.max(s0, s1) / math.max(1e-6, math.min(s0, s1))) / math.log(2))
    return math.min(most, base + 0.06 * steps)
end

-- Zooms only when the reason changes (entering/leaving town or a cluster), so a
-- zoom you choose yourself in between is left alone. Leaving goes back to the
-- zoom you had before it zoomed in, not all the way out.
local lastWant
local zoomBefore  -- your canvas scale just before auto-zoom zoomed in
local function AutoZoom(map)
    local z = ns.db.zoom
    local townZoom = TownZoomOn()  -- (town view: its own switches)
    local cityZoom = ns.db.cityView.zoom  -- (city view: its own too)
    local sc = map.ScrollContainer
    if not (AnyAutoZoom() and sc and sc.SetZoomTarget) then lastWant = nil return end
    if GetTime() < pauseUntil or anim then return end
    if ns.Browsing and ns.Browsing() then return end  -- (waits until you're back on your map)

    local mapID = map:GetMapID()
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if Held(mapID, pos and pos.x and pos or nil) then return end  -- (waits for you to move too)
    if not (pos and pos.x) or (pos.x == 0 and pos.y == 0) then return end

    -- why to be zoomed in: "city", "town", or false. In a capital it's city view or nothing:
    -- never a town close-up.
    local want = false
    local inCity = InCity()
    if inCity then
        want = cityZoom and "city" or false
    elseif townZoom and InTown() then
        want = "town"
    end
    if want ~= lastWant then
        local first = lastWant == nil
        local wasIn = lastWant
        lastWant = want
        local lo = ZoomRange(sc)
        if lo then
            if want then
                -- remember your own zoom only when coming in from outside, not
                -- when going from a cluster into town
                if not wasIn then zoomBefore = sc:GetCanvasScale() end
                -- how close: art on screen (ArtX), 0 = fully out
                local x = want == "city" and (ns.db.cityView.zoomX or 0)
                    or z.townX
                AnimateTo(map, ScaleAtX(sc, x))  -- (ApplyView keeps it within the levels)
            elseif not first then
                -- (on the very first check outside town there's nothing to undo)
                AnimateTo(map, zoomBefore or lo)
                zoomBefore = nil
            end
        end
    end
    -- (while it wants you zoomed in, the view follows you: every frame, below)
end

-- Remember the view when the map closes, put it back when it opens. The game
-- resets the zoom on show; auto-zoom carries on from where it was (so opening
-- the map in town doesn't count as "just arrived" and zoom in again).
local savedView
local function ViewCenter(sc)
    -- where it actually is (current), not where an unfinished pan was headed
    return sc.currentScrollX or sc.targetScrollX or 0.5, sc.currentScrollY or sc.targetScrollY or 0.5
end

local function SaveView(map)
    local sc = map.ScrollContainer
    if not sc then return end
    local x, y = ViewCenter(sc)
    savedView = { mapID = map:GetMapID(), scale = sc:GetCanvasScale(), x = x, y = y, want = lastWant }
end

-- quiet: re-applying only, don't touch the auto-zoom state again
local function RestoreView(map, quiet)
    local sc = map.ScrollContainer
    local v = savedView
    if not (sc and v and v.mapID == map:GetMapID()) then
        if not quiet then lastWant = nil end  -- a different map: decide afresh
        return
    end
    -- where to look: if the map is going to follow you anyway (centering, or
    -- auto-zoom in town), go straight to you, in one move with the zoom.
    -- Otherwise the old view's centre.
    local x, y = v.x, v.y
    if Cfg().center or (AnyAutoZoom() and v.want) then
        local pos = C_Map.GetPlayerMapPosition(map:GetMapID(), "player")
        -- (to the view following you would glide to: the arrow held inside the zone's useful part, as
        -- CenterOnPlayer's ZoneClamp does, not dead centre. Else it opened on the arrow, then panned there:
        -- the user, 2026-11-22, back from the world map to the docked square, "We want it to start on the useful
        -- part, not on the player arrow in the middle")
        if pos and pos.x and (pos.x > 0 or pos.y > 0) then x, y = ZoneClamp(sc, v.scale, pos.x, pos.y) end
    end
    -- a centre that's valid at this zoom: too near the edge leaves a gap that
    -- the game then scrolls away (the "settling")
    if sc.CalculateScrollExtentsAtScale then
        local minX, maxX, minY, maxY = sc:CalculateScrollExtentsAtScale(v.scale)
        if minX then x, y = Clamp(x, minX, maxX), Clamp(y, minY, maxY) end
    end
    pcall(ApplyView, sc, v.scale, x, y)  -- sets current and target alike
    if not quiet then lastWant = v.want end
    pauseUntil = GetTime() + 1  -- let it settle before centering/auto-zoom move it
end

-- the next opening starts afresh, not on the view it closed with (Dock.lua)
function ns.ForgetMapView() savedView = nil end

-- the game may reset the view again a moment after showing: if the zoom isn't
-- what was restored, put it back once more
local function RecheckView(map)
    local sc, v = map.ScrollContainer, savedView
    if not (sc and v and v.mapID == map:GetMapID() and map:IsShown()) then return end
    if math.abs(sc:GetCanvasScale() - v.scale) > v.scale * 0.01 then RestoreView(map, true) end
end

-- Into another zone: the game starts it fully zoomed out. Keep how close you
-- were instead (ZoomSpot: the same art size on screen), on you. Zone maps
-- only: a cave or dungeon map doesn't count, and coming back out of one
-- carries the zone's closeness from before.
local kept           -- where the zoom was on a zone map (ZoomSpot)
local lastMap        -- the map the zoom levels were last built for
local carry          -- { mapID, spot, untilT }: put on the new map; kept while its shape settles
local CARRY_SETTLE = 1.5

local function IsZoneMap(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    return info and Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.Zone or false
end

-- Over a reload or a login (kotanna on CurseForge, 2026-11-10: "would be great if it remembered zoom level
-- between reloads"): the closeness is written to the character's saved file as it changes and read back once.
local zoomRead
local PutZoom       -- (defined below KeepZoom)
local function ReadKept()
    if zoomRead then return end
    zoomRead = true
    local z = WaymarkCharDB and WaymarkCharDB.mapZoom
    if type(z) ~= "table" then return end
    if z.out then kept = { out = true }
    elseif z.top then kept = { top = true }
    elseif type(z.x) == "number" and z.x > 0 then kept = { x = z.x } end
    return kept ~= nil
end

-- every half second: how close you are now
local function KeepZoom(map)
    local sc = map.ScrollContainer
    local mapID = map:GetMapID()
    -- (not auto-zoom's town, city or cluster zoom: that's not yours)
    if anim or lastWant or not (sc and sc.zoomLevels and IsZoneMap(mapID)) then return end
    if ns.Browsing and ns.Browsing() then return end  -- (another zone's zoom isn't yours)
    if carry and carry.mapID == mapID and GetTime() < carry.untilT then return end  -- (still settling)
    if ReadKept() then  -- (the first look after a reload: put the saved closeness on, don't read the fresh map's)
        carry = { mapID = mapID, spot = kept, untilT = GetTime() + CARRY_SETTLE }
        PutZoom(map, kept)
        return
    end
    kept = ZoomSpot(sc, sc.targetScale or sc:GetCanvasScale()) or kept
    if kept then
        WaymarkCharDB = WaymarkCharDB or {}
        local z = WaymarkCharDB.mapZoom
        if type(z) ~= "table" then z = {}; WaymarkCharDB.mapZoom = z end
        z.out, z.top, z.x = kept.out, kept.top, kept.x
    end
end

function PutZoom(map, spot)
    local sc = map.ScrollContainer
    local s = ScaleAtSpot(sc, spot)
    if not s then return end
    local x, y = ViewCenter(sc)
    local px, py = PlayerPos(map)
    if px then
        x, y = ZoneClamp(sc, s, px, py)
    else
        local _, cx, cy = ZoneFit(sc)
        if cx then x, y = cx, cy end
    end
    pcall(ApplyView, sc, s, x, y)
end

-- the zoom levels were built: on a new zone map, put the closeness back
local function CarryZoom(map)
    local mapID = map:GetMapID()
    local changed = mapID ~= lastMap
    lastMap = mapID
    ReadKept()
    -- (the same map reopened is RestoreView's; a zone you browse opens fully
    -- zoomed out, and coming back to yours gets your closeness again)
    if not (changed and kept and map:IsShown() and IsZoneMap(mapID)) then return end
    if ns.Browsing and ns.Browsing() then return end
    -- (wheeled in from the continent onto your own zone: Browse.lua has put the
    -- view where you were looking; your closeness would jump it onto you)
    if ns.BrowsePlacedView and ns.BrowsePlacedView() then return end
    carry = { mapID = mapID, spot = kept, untilT = GetTime() + CARRY_SETTLE }
    PutZoom(map, kept)
end

-- the new map's shape is still gliding in: each new size gets the same closeness
local function Carrying(map)
    return carry and carry.mapID == map:GetMapID() and GetTime() < carry.untilT
end

-- Icon sizes --------------------------------------------------------------

-- The classic map arrow on the zone map too (one setting with the cave view's,
-- cave.classicArrow). The game's player-and-group pin keeps one appearance per
-- unit type; SetAppearanceField is called with a dot, as Leatrix does: it's
-- shared, not per pin. Its default isn't readable from outside, so switching
-- back off takes a /reload.
local CLASSIC_ARROW = "Interface\\WorldMap\\WorldMapArrow"
local classicApplied = false
local function ApplyArrowTexture(gm)
    if not (ns.db.cave and ns.db.cave.classicArrow) then
        if classicApplied then
            ns.Log("The zone map's arrow changes back after a /reload.")
            classicApplied = false
        end
        return
    end
    local pin = gm.pin
    if not pin then return end
    if pin.SetAppearanceField then pcall(pin.SetAppearanceField, "player", "texture", CLASSIC_ARROW) end
    if pin.UpdateAppearanceData then pcall(pin.UpdateAppearanceData, pin) end
    if pin.SetPinTexture then pcall(pin.SetPinTexture, pin, "player", CLASSIC_ARROW) end
    classicApplied = true
end

-- Group members' dots in their class colour (party.classColors). The game's
-- pin has the switch; which way it's called differs between clients, so both.
local function ApplyClassColors(gm)
    local pin = gm.pin
    if not pin then return end
    local on = ns.db.party.classColors and true or false
    for _, unitType in ipairs({ "party", "raid" }) do
        if pin.SetUseClassColor then pcall(pin.SetUseClassColor, pin, unitType, on) end
        if pin.SetAppearanceField then pcall(pin.SetAppearanceField, unitType, "useClassColor", on) end
    end
    if pin.UpdateAppearanceData then pcall(pin.UpdateAppearanceData, pin) end
end

-- The arrow stays one size on screen while the map grows round it, so close up it
-- looked tiny (the user): it grows a little with the zoom, about twice at the closest.
local gameArrow, lastArrow, arrowHooked
local function SetArrowSize(map, gm)
    local c = Cfg()
    local base = c.arrowSize and c.arrowSize > 0 and c.arrowSize or gameArrow
    if not base then return end
    local sc = map.ScrollContainer
    -- (no zoom levels yet while the map is set up: GetScaleForMinZoom errors then)
    local lo, s = sc and sc.zoomLevels and sc:GetScaleForMinZoom(), sc and sc:GetCanvasScale()
    local size = base
    if lo and s and lo > 0 and s > lo then size = base * (s / lo) ^ 0.35 end
    -- (docked: the minimap's arrow's size close in, so there's no jump between them; further out it
    -- grows, up to 50% at the widest, where it looked small, the user, and at mid zoom too)
    if ns.Docked and ns.Docked() then
        local out = lo and s and lo > 0 and math.max(0, 1 - (s / lo - 1) / 6) or 0
        size = base * 1.12 * (1 + 0.5 * out)
    end
    if lastArrow and math.abs(size - lastArrow) < 0.25 then return end
    lastArrow = size
    pcall(gm.SetUnitPinSize, gm, "player", size)
    if gm.pin and gm.pin.SynchronizePinSizes then pcall(gm.pin.SynchronizePinSizes, gm.pin) end
end

local function ApplySizes(map)
    local gm = map.groupMembersDataProvider
    if gm then pcall(ApplyClassColors, gm) end
    if not (gm and gm.SetUnitPinSize) then return end
    local c = Cfg()
    if not gameArrow and gm.GetUnitPinSizesTable then gameArrow = gm:GetUnitPinSizesTable().player end
    lastArrow = nil
    SetArrowSize(map, gm)
    if not arrowHooked then
        arrowHooked = true
        hooksecurefunc(map, "OnCanvasScaleChanged", function() ns.Safe("MapControls arrow zoom", SetArrowSize, map, gm) end)
    end
    if c.groupSize and c.groupSize > 0 then
        pcall(gm.SetUnitPinSize, gm, "party", c.groupSize)
        pcall(gm.SetUnitPinSize, gm, "raid", c.groupSize)
    end
    if gm.pin and gm.pin.SynchronizePinSizes then pcall(gm.pin.SynchronizePinSizes, gm.pin) end
    ApplyArrowTexture(gm)
end

-- Fading ------------------------------------------------------------------

-- The whole map fades (on top of its own opacity) while you move and/or in
-- combat (fade.movingAlpha / combatAlpha, in %), and comes back under the mouse
-- if fade.hover. Not on a flight path: that's when you'd look at it.
local FADE_RATE = 3       -- alpha per second
local STOP_GRACE = 0.4    -- seconds of standing still before it counts as stopped
local fadeAlpha, lastMoved = 1, 0

local function FadeTarget(map)
    if ns.WorldMapUp and ns.WorldMapUp() then return 1 end   -- (the world map never fades: the switch's picks)
    local f = ns.db.fade
    if f.hover and (ns.MouseOnMap and ns.MouseOnMap(map) or map:IsMouseOver()) then return 1 end
    local want = 1
    if f.moving then
        if GetUnitSpeed("player") > 0 and not UnitOnTaxi("player") then lastMoved = GetTime() end
        if GetTime() - lastMoved < STOP_GRACE then want = math.min(want, f.movingAlpha / 100) end
    end
    if f.combat and UnitAffectingCombat("player") then
        want = math.min(want, f.combatAlpha / 100)
    end
    return want
end

local function UpdateFade(map, dt)
    local want = FadeTarget(map)
    if fadeAlpha == want then return end
    local step = FADE_RATE * dt
    if math.abs(want - fadeAlpha) <= step then
        fadeAlpha = want
    elseif want > fadeAlpha then
        fadeAlpha = fadeAlpha + step
    else
        fadeAlpha = fadeAlpha - step
    end
    map:SetAlpha(fadeAlpha)
end

-- Group member tooltip --------------------------------------------------------

-- Hovering a group member's dot: name and level in class colour, health and
-- distance. Ours replaces the game's own name-only tooltip while it's on.
local HOVER_RADIUS = 9  -- UI pixels around a dot

local function GroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    else
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    return units
end

local function ClassColor(unit)
    local _, class = UnitClass(unit)
    local c = class and (C_ClassColor and C_ClassColor.GetClassColor(class) or RAID_CLASS_COLORS[class])
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local hovering = false
local function UpdateGroupTooltip(map)
    local sc = map.ScrollContainer
    local child = sc and sc.Child
    local mapID = map:GetMapID()
    local found
    local covered = ns.DungeonMapShown and ns.DungeonMapShown()  -- (party under the dungeon map)
    if ns.db.party.hover and child and mapID and sc:IsMouseOver() and IsInGroup() and not covered then
        local cx, cy = GetCursorPosition()
        local s = child:GetEffectiveScale()
        local left, top = child:GetLeft(), child:GetTop()
        local w, h = child:GetWidth(), child:GetHeight()
        local radius = HOVER_RADIUS * map:GetEffectiveScale()
        if left and top then
            found = {}
            for _, unit in ipairs(GroupUnits()) do
                if not UnitIsUnit(unit, "player") then
                    local pos = C_Map.GetPlayerMapPosition(mapID, unit)
                    local x, y = pos and pos.x, pos and pos.y
                    if x and (x > 0 or y > 0) then
                        local px, py = (left + x * w) * s, (top - y * h) * s
                        if (px - cx) ^ 2 + (py - cy) ^ 2 <= radius ^ 2 then
                            found[#found + 1] = { unit = unit, x = x, y = y }
                        end
                    end
                end
            end
            if #found == 0 then found = nil end
        end
    end

    if not found then
        if hovering and GameTooltip:IsOwned(map) then GameTooltip:Hide() end
        hovering = false
        return
    end
    hovering = true
    GameTooltip:SetOwner(map, "ANCHOR_CURSOR")
    local me = C_Map.GetPlayerMapPosition(mapID, "player")
    local yw, yh = ns.MapYards(mapID)
    for i, m in ipairs(found) do
        if i > 1 then GameTooltip:AddLine(" ") end
        local r, g, b = ClassColor(m.unit)
        local level = UnitLevel(m.unit)
        GameTooltip:AddDoubleLine(UnitName(m.unit) or "?", level and level > 0 and ("Level " .. level) or "",
                                  r, g, b, 0.8, 0.8, 0.8)
        local state
        if not UnitIsConnected(m.unit) then
            state = "|cff999999Offline|r"
        elseif UnitIsDeadOrGhost(m.unit) then
            state = "|cffff4040Dead|r"
        else
            local hp, max = UnitHealth(m.unit), UnitHealthMax(m.unit)
            local secret = issecretvalue and (issecretvalue(hp) or issecretvalue(max))  -- (live Forever)
            if not secret and max and max > 0 then state = string.format("Health %d%%", hp / max * 100) end
        end
        local dist
        if me and me.x and yw then
            local d = math.sqrt(((m.x - me.x) * yw) ^ 2 + ((m.y - me.y) * yh) ^ 2)
            dist = string.format("%d yd", d)
        end
        GameTooltip:AddDoubleLine(state or "", dist or "", 1, 1, 1, 1, 0.82, 0)
    end
    GameTooltip:Show()
end

-- the game's own group tooltip steps aside while ours is on
local function WrapGameGroupTooltip(map)
    local pin = map.groupMembersDataProvider and map.groupMembersDataProvider.pin
    if not (pin and pin.UpdateTooltips) or pin.bfiWrapped then return end
    local orig = pin.UpdateTooltips
    pin.UpdateTooltips = function(...)
        if ns.db.party.hover then return end
        return orig(...)
    end
    pin.bfiWrapped = true
end

-- Key zoom ------------------------------------------------------------------

-- dir: 1 in, -1 out. Centering and auto-zoom wait for you to move, as with the wheel.
function ns.MapZoom(dir)
    local map = BattlefieldMapFrame
    local sc = map and map.ScrollContainer
    if not (sc and map:IsShown()) then return end
    Hold(map)
    StopAnim()
    local f = dir > 0 and sc.ZoomIn or sc.ZoomOut
    if not (f and pcall(f, sc)) then
        local wheel = sc:GetScript("OnMouseWheel")
        if wheel then pcall(wheel, sc, dir) end
    end
    if dir < 0 then
        pcall(CenterZoneFit, sc)
        pcall(ZoomOutInZone, sc)
    end
end

-- All the way out in one glide (Browse.lua's right-click): on a zone, to its
-- fitted middle, as RefitZoom places a fully-out view. Your own zoom, as with the wheel.
-- (instant: straight there, for the docked big map opening)
function ns.MapZoomOutFully(instant)
    local map = BattlefieldMapFrame
    local sc = map and map.ScrollContainer
    local levels = sc and sc.zoomLevels
    if not (levels and levels[1] and sc.SetZoomTarget and map:IsShown()) then return end
    Hold(map)
    local s = levels[1].scale
    local x = sc.targetScrollX or sc.currentScrollX or 0.5
    local y = sc.targetScrollY or sc.currentScrollY or 0.5
    local _, cx, cy = ZoneFit(sc)
    if cx and not Follows(sc) then x, y = cx, cy end
    local minX, maxX, minY, maxY = sc:CalculateScrollExtentsAtScale(s)
    if minX then x, y = Clamp(x, minX, maxX), Clamp(y, minY, maxY) end
    if instant then ApplyView(sc, s, x, y) return end
    ns.GlideView(map, s, x, y, ns.GlideTime(sc:GetCanvasScale(), s, 0.3, 0.45))
end

-- Shape -------------------------------------------------------------------

-- The map is the game's size (about 3:2) until you drag its corner; your size is
-- kept in Cfg().width/height (map units, before its scale). Auto width (auto
-- shape): on each map you go to, the map takes on part of the zone's shape
-- (ns.ZoneBounds; shapeFollow, 0..1) at about your size: the same area, so a
-- wide zone like Duskwood gets wider and shorter, not twice as wide. The more
-- the zone's shape differs from yours, the more it may grow (shapeGrow, up to
-- that much more area), so more of the zone shows. Dragging the corner on a map
-- keeps that shape for it (zoneSizes[mapID], with rememberShapes on; off,
-- they're kept stored but not used); your size follows the drag's
-- area, in your own shape, for the zones you haven't shaped.
local MIN_W, MIN_H = 120, 90
local SHAPE_TIME = 0.35        -- seconds a size change glides
local shapeTarget              -- { width, height } being glided to
local shapeDragging = false    -- the corner grip is held: leave the size to it
local shapeFrame = CreateFrame("Frame")

local function ManualSize()
    local c = Cfg()
    return c.width or defaultW, c.height or defaultH
end

-- Close-up detail fades in from detail.fromZoom to full at detail.fullZoom,
-- both in times closer than fully zoomed out (on a zone map: the zone fitted).
-- That's the same view of the zone whatever the map's size: measured as art on
-- screen (ArtX, before), a bigger map drew the zone bigger fully zoomed out, so
-- resizing the map changed the detail. Full is never past this map's closest
-- zoom, so it can always be reached. 0..1.
local DETAIL_REACH = 8   -- (a usual map's room, fully out to closest)
function ns.DetailFade(map)
    local sc = map.ScrollContainer
    if not sc then return 1 end
    local lo, hi = ZoomRange(sc)
    if not lo then return 1 end
    -- By how close you are to the closest step, as on a map of DETAIL_REACH steps' room: the same zoom
    -- the same detail at any size of the map (by fully out, a resize moved you along the fade), and
    -- none fully out (a big map has little room: fully out is near the closest; the user 2026-11-08)
    local s = sc:GetCanvasScale()
    local fade = ns.DetailFadeAt(DETAIL_REACH * s / hi, DETAIL_REACH)
    return fade * Clamp((s / lo - 1) / 0.25, 0, 1)
end

-- the same for x times closer than fully out, on a map that goes reach times
-- (ZoneArt's ns.ContinentZoneZoom: a zone seen on the big map's continent)
function ns.DetailFadeAt(x, reach)
    local d = ns.db.detail
    local full0, from0 = d.fullZoom or 5.5, d.fromZoom or 3.5
    -- A big map has less zoom room: fully out is closer already, the closest step the same. Cut to
    -- that room, both ends landed on the closest step: a hard switch there, and with no room left the
    -- detail full at once (corner-dragged into the screen's bottom, the user 2026-11-08). Short of
    -- room, the fade is spread over what there is instead; with none, there's no detail
    if not reach or reach <= 1.05 then return 0 end
    local full, from = full0, from0
    if reach < full0 and full0 > 1 then
        full = reach
        from = 1 + (from0 - 1) * (reach - 1) / (full0 - 1)
    end
    from = math.min(from, full)
    if full <= from * 1.001 then return x >= full * 0.999 and 1 or 0 end
    return Clamp(math.log(math.max(x, 1e-6) / from) / math.log(full / from), 0, 1)
end

-- auto shape's own sizes, per map, on (not in a cave, where the size is yours)
local function PerZone(map)
    return Cfg().autoWidth and ns.ZoneBounds and map:GetMapID() and not (ns.InCave and ns.InCave())
end

-- In a dungeon or raid the map has a size of its own a dungeon (dungeonSizes, by instance): the first
-- time in, the size the map had as you went in, or your normal size if it was closed; after that what
-- you leave it at (the user, 2026-11-07: the dungeon's own shape opened it big).
local function DungeonKey()
    local inside, kind = IsInInstance()
    if not (inside and (kind == "party" or kind == "raid")) then return end
    if ns.Browsing and ns.Browsing() then return end
    return select(8, GetInstanceInfo())
end

local function DungeonSize(map)
    local key = DungeonKey()
    if not key then return end
    local c = Cfg()
    c.dungeonSizes = c.dungeonSizes or {}
    local s = c.dungeonSizes[key]
    if not s then
        local w, h = ManualSize()
        if map:IsShown() and not c.big and not (ns.Docked and ns.Docked()) then
            w, h = map:GetWidth(), map:GetHeight()
        end
        s = { math.max(MIN_W, w), math.max(MIN_H, h) }
        c.dungeonSizes[key] = s
    end
    return s[1], s[2]
end

local function NormalSize(map)
    local dw, dh = DungeonSize(map)
    if dw then return dw, dh end
    local w, h = ManualSize()
    local c = Cfg()
    if not PerZone(map) then return w, h end
    local mapID = map:GetMapID()
    local own = c.rememberShapes and c.zoneSizes[mapID]
    if own then return own[1], own[2] end  -- dragged to that on this map
    local l, t, r, b = ns.ZoneBounds(mapID)
    if not l or r <= l or b <= t then return w, h end
    local sc = map.ScrollContainer
    -- the border round the scroll area stays the same whatever the size
    local bx, by = map:GetWidth() - sc:GetWidth(), map:GetHeight() - sc:GetHeight()
    local iw, ih = math.max(1, w - bx), math.max(1, h - by)
    local yours, zone = iw / ih, (r - l) / (b - t)
    -- part way from your shape to the zone's (evenly in ratio: 2x as wide at
    -- half way is about 1.41x), the rest left to the zoomed-out view, which
    -- shows the whole zone with a strip of its neighbours
    local follow = Clamp(c.shapeFollow or 0.7, 0, 1)
    local shape = yours * (zone / yours) ^ follow
    -- a little more room the more the shapes differ (all of shapeGrow from 2x on)
    local differ = math.min(1, math.abs(math.log(zone / yours)) / math.log(2))
    local area = iw * ih * (1 + Clamp(c.shapeGrow or 0, 0, 1) * differ)
    return math.max(MIN_W, math.sqrt(area * shape) + bx), math.max(MIN_H, math.sqrt(area / shape) + by)
end

-- Big map: one key (or the red shrink button that shows while it's big) glides
-- the map to its big size and back. The big size is its own (bigWidth /
-- bigHeight, the corner grip sets it while big), the same on every zone; it
-- starts at BIG_DEFAULT times your size, and never past the screen. The corner
-- nearest the screen's edges stays put while it grows (bigCorner: right edge,
-- bottom edge), and again on the way back, so it shrinks to where it was.
local BIG_DEFAULT = 1.8
local BIG_TIME = 0.45  -- seconds the change glides

-- the screen in the map's units, a little margin left
local function ScreenRoom(map)
    local k = UIParent:GetEffectiveScale() / map:GetEffectiveScale()
    -- (the quest log that opens with the big map, Tracker.lua questlog.withBig: its width stays free)
    local side = ns.QuestLogSideRoom and ns.QuestLogSideRoom() or 0
    local sw = UIParent:GetWidth()
    return math.max(sw * 0.95 - side, sw * 0.4) * k, UIParent:GetHeight() * k * 0.95
end

local function FitScreen(map, w, h, most)
    local mw, mh = ScreenRoom(map)
    local k = math.min(most, mw / w, mh / h)
    return math.max(MIN_W, w * k), math.max(MIN_H, h * k)
end

ns.NormalMapSize = NormalSize

-- (the world map keeps its own size, worldW / worldH, apart from the big map's: fix 3 of the switch's report)
local function BigSize(map)
    local c = Cfg()
    local w, h = c.bigWidth, c.bigHeight
    local world = ns.MapKind and ns.MapKind() == "world"
    -- (no size of its own yet: the big map's tuned size to start from, so the first world map is not the default)
    if world then w, h = c.worldW or c.bigWidth, c.worldH or c.bigHeight end
    local most = 1
    if not w then
        w, h = NormalSize(map)
        most = BIG_DEFAULT
    end
    return FitScreen(map, w, h, most)
end

local RIBBON_MIN = 40  -- the band's least height, map units

local function WantedSize(map)
    if ns.DockedSize then
        local w, h = ns.DockedSize(map)
        if w then return w, h end
    end
    if ribbon then
        local w, h
        if Cfg().big then w, h = BigSize(map) else w, h = NormalSize(map) end
        return w, math.max(RIBBON_MIN, h * Clamp(ns.db.collapse.ribbonHeight or 0.25, 0.1, 0.6))
    end
    if Cfg().big then return BigSize(map) end
    return NormalSize(map)
end

-- the scroll area changed size: the game's zoom steps (and our fit) depend on
-- it. Fully zoomed out stays fully out, on the zone; zoomed in, the view stays
-- as close relative to fully out, on the same spot: the same part of the zone,
-- drawn bigger or smaller with the map (keeping the scale instead showed more
-- of the zone in a bigger map, and the close-up detail, measured from fully
-- out, changed as you resized)
local function RefitZoom(map)
    local sc = map.ScrollContainer
    if not (sc and sc.CreateZoomLevels and sc.mapID) then return end
    local levels = sc.zoomLevels
    local s0 = sc.targetScale or sc:GetCanvasScale()
    local lo0 = levels and levels[1] and levels[1].scale
    local wasOut = lo0 and s0 <= lo0 * 1.01
    local x0, y0 = ViewCenter(sc)
    sc.bfiReshaping = true
    pcall(sc.CreateZoomLevels, sc)  -- (our hook adds our levels)
    sc.bfiReshaping = nil
    if Carrying(map) then PutZoom(map, carry.spot) return end  -- (a new zone's shape gliding in)
    levels = sc.zoomLevels
    if not (levels and levels[1]) then return end
    if wasOut then
        local x, y = x0, y0
        local _, cx, cy = ZoneFit(sc)
        if cx and not Follows(sc) then x, y = cx, cy end
        pcall(ApplyView, sc, levels[1].scale, x, y)
    elseif lo0 and lo0 > 0 and not anim then
        -- (zoomed in, a resize keeps the zoom: you see more or less of the map, the close-up detail
        -- stays as it was. It was kept as times closer than fully out, which moved with the size)
        pcall(ApplyView, sc, Clamp(s0, levels[1].scale, levels[#levels].scale), x0, y0)
    end
end

local growCorner  -- { right, bottom }: the edges kept still while the big map glides
local settleAt    -- GetTime() from which the screen's size is taken as final (SetupMapControls)

-- a moved map in the right half of the screen keeps its right edge (gliding
-- to or from big: the edges in growCorner)
local function SetShape(map, w, h)
    local oldW, oldH = map:GetWidth(), map:GetHeight()
    if math.abs(oldW - w) < 0.5 and math.abs(oldH - h) < 0.5 then return end
    local pos = Cfg().pos
    local moved = pos and pos.kind == "topleft"
    local docked = ns.Docked and ns.Docked()
    -- (the first seconds after a load the screen's size isn't final: nothing about the place is
    -- decided or written down from it then)
    local settled = settleAt and GetTime() > settleAt
    local keepRight, keepBottom
    if growCorner then
        keepRight, keepBottom = growCorner[1], growCorner[2]
    elseif moved and not docked then
        -- (from the saved place, not from where the frame is: undocking shapes the map while it still
        -- lies on the docked spot, and a map of the left half was marked as the right half's)
        if pos.right == nil and settled then
            local sw = pos.w or oldW * map:GetEffectiveScale() / UIParent:GetEffectiveScale()
            pos.right = pos.x + sw / 2 > UIParent:GetWidth() / 2
        end
        -- (not under the corner grip: it's the bottom-right corner, so the left edge stays and the
        -- corner follows the cursor. With the right edge kept the drag went the wrong way, as if the
        -- grip were still in the docked map's left corner; the user, 2026-11-14)
        keepRight = pos.right and not shapeDragging
        -- (the grip in another corner, mapFrame.gripCorner: the corner opposite it stands still)
        if shapeDragging then
            local gc = Cfg().gripCorner
            keepRight = gc == "BL" or gc == "TL"
            keepBottom = gc == "TR" or gc == "TL"
        end
    end
    map:SetSize(w, h)
    -- docked: centred on the minimap (Dock.lua); your own place and its width stay as saved
    if ns.DockShaping and ns.DockShaping(map) and docked then return end
    if not moved or (ns.Docked and ns.Docked()) then return end
    -- The right edge is kept from the width the place was saved for (pos.w), never from the width
    -- the frame happened to have: after a load that's the game's own size, after undocking the
    -- square's, and the difference went into the saved place at every /reload (a map in the right
    -- half walked sideways, a narrow one to the right; the user, 2026-11-14). A place saved without
    -- its width keeps its left edge this once.
    local k = map:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if keepRight and pos.w then pos.x = pos.x + pos.w - w * k end
    if pos.w or settled then pos.w = w * k end
    if keepBottom then pos.y = pos.y + (h - oldH) * k end
    -- (always, not only when a kept edge moved the place: the new size may reach past the screen, and
    -- RestorePosition holds the map on it. Not under a drag: the frame is the cursor's then)
    if keepRight or keepBottom or not mapMoving then RestorePosition(map) end
    -- (the zoom is refitted from the scroll area's OnSizeChanged: its size only
    -- updates on the next layout pass, so reading it here gets the old one)
end

local function StopGlide()
    shapeTarget, growCorner = nil, nil
    shapeFrame:SetScript("OnUpdate", nil)
end

-- force: even while browsing (the big map key); time: seconds to glide
local function UpdateShape(instant, force, time)
    local map = BattlefieldMapFrame
    if not (map and defaultW and map.ScrollContainer) or shapeDragging then return end
    -- browsing other maps (Browse.lua): the shape stays, so going between
    -- zone and continent is one smooth zoom; back home it's your zone's again
    if ns.Browsing and ns.Browsing() and not force then return end
    local tw, th = WantedSize(map)
    if shapeTarget and math.abs(tw - shapeTarget[1]) < 1 and math.abs(th - shapeTarget[2]) < 1 then
        return  -- already heading there
    end
    local fw, fh = map:GetWidth(), map:GetHeight()
    if instant or not map:IsShown() or (math.abs(tw - fw) < 1 and math.abs(th - fh) < 1) then
        shapeTarget = nil
        shapeFrame:SetScript("OnUpdate", nil)
        SetShape(map, tw, th)
        growCorner = nil
        return
    end
    shapeTarget = { tw, th }
    local t = 0
    shapeFrame:SetScript("OnUpdate", function(_, dt)
        t = math.min(1, t + dt / (time or SHAPE_TIME))
        local e = t * t * (3 - 2 * t)  -- slow start, slow finish
        ns.Safe("MapControls SetShape", SetShape, map, fw + (tw - fw) * e, fh + (th - fh) * e)
        if t >= 1 then StopGlide() end
    end)
end
ns.UpdateMapShape = UpdateShape

-- The ribbon (Collapse.lua): folded, the map is a band of the ground round you.
-- The frame keeps its width and goes down to a share of its height (WantedSize),
-- the view goes closer (collapse.ribbonZoom times the zone fully out, or your own
-- zoom if that was closer) and follows you whatever Keep me centred says. Opening
-- puts the size, the zoom and (not following) the spot back as they were.
-- false: no ribbon here (docked, browsing another map, no place for you on this
-- map), and the caller folds the map away as before.
local function GoView(map, s, x, y)
    if map:IsVisible() then
        ns.GlideView(map, s, x, y, SHAPE_TIME)
    else
        pcall(ApplyView, map.ScrollContainer, s, x, y)
    end
end

function ns.MapRibbon(on)
    local map = BattlefieldMapFrame
    local sc = map and map.ScrollContainer
    if not (sc and defaultW) then return false end
    if on then
        if ribbon then return true end
        if (ns.Docked and ns.Docked()) or (ns.Browsing and ns.Browsing()) then return false end
        local px, py = PlayerPos(map)
        if not px then return false end
        local s = sc.targetScale or sc:GetCanvasScale()
        local lo = sc.zoomLevels and sc.zoomLevels[1] and sc.zoomLevels[1].scale
        if not (s and s > 0) then return false end
        local x, y = ViewCenter(sc)
        ribbon = { scale = s, x = x, y = y, held = heldAt, lo = lo or s }
        heldAt = nil
        GoView(map, math.max(s, ribbon.lo * Clamp(ns.db.collapse.ribbonZoom or 2.5, 1, 8)), px, py)
        UpdateShape(not map:IsVisible(), true)
        return true
    end
    local r = ribbon
    if not r then return false end
    ribbon = nil
    local x, y = r.x, r.y
    if Cfg().center then
        local px, py = PlayerPos(map)
        if px then x, y = px, py end
    end
    heldAt = r.held
    GoView(map, r.scale, x, y)
    UpdateShape(not map:IsVisible(), true)
    return true
end

function ns.MapIsRibbon() return ribbon ~= nil end

-- (collapse.ribbonHeight or ribbonZoom changed while it's a ribbon)
function ns.MapRibbonRefresh()
    local map = BattlefieldMapFrame
    local sc = map and map.ScrollContainer
    if not (ribbon and sc) then return end
    UpdateShape(false, true)
    local px, py = PlayerPos(map)
    if px then GoView(map, math.max(ribbon.scale, ribbon.lo * Clamp(ns.db.collapse.ribbonZoom or 2.5, 1, 8)), px, py) end
end

-- for /bfi check: the map's shape and zoom, to see why a view doesn't fill
function ns.ViewInfo()
    local map = BattlefieldMapFrame
    local sc = map and map.ScrollContainer
    if not sc then return end
    local levels = sc.zoomLevels or {}
    local mw, mh = ManualSize()
    -- (not `x and f()`: that keeps only f's first value)
    local l, t, r, b
    if ns.ZoneBounds then l, t, r, b = ns.ZoneBounds(map:GetMapID()) end
    return {
        frame = { map:GetWidth(), map:GetHeight() }, scroll = { sc:GetWidth(), sc:GetHeight() },
        manual = { mw, mh }, wanted = { WantedSize(map) }, autoWidth = Cfg().autoWidth, big = Cfg().big or false,
        zoneShaped = Cfg().zoneSizes[map:GetMapID()] and true or false,
        scale = sc:GetCanvasScale(), target = sc.targetScale,
        minLevel = levels[1] and levels[1].scale, minIsOurs = levels[1] and levels[1].bfiExtra or false,
        cover = CoverScale(sc), fit = ZoneFit(sc), levels = #levels,
        bounds = l and { l, t, r, b } or nil,
    }
end

function ns.MapManualSize() return ManualSize() end

-- the map's scale changed by k (old / new; ns.SetScale): every size we keep
-- changes by k, so the map stays the size it was on screen
function ns.KeepScreenSize(k)
    local map = BattlefieldMapFrame
    if not (map and defaultW and k and k > 0) then return end
    local c = Cfg()
    local w, h = ManualSize()
    c.width, c.height = math.max(MIN_W, w * k), math.max(MIN_H, h * k)
    for id, s in pairs(c.zoneSizes) do
        c.zoneSizes[id] = { math.max(MIN_W, s[1] * k), math.max(MIN_H, s[2] * k) }
    end
    if c.bigWidth then
        c.bigWidth, c.bigHeight = math.max(MIN_W, c.bigWidth * k), math.max(MIN_H, c.bigHeight * k)
    end
    if c.worldW then
        c.worldW, c.worldH = math.max(MIN_W, c.worldW * k), math.max(MIN_H, c.worldH * k)
    end
    for id, s in pairs(c.dungeonSizes or {}) do
        c.dungeonSizes[id] = { math.max(MIN_W, s[1] * k), math.max(MIN_H, s[2] * k) }
    end
    StopGlide()
    UpdateShape(true)
end

-- from the corner grip. dragging: the size follows the cursor. With auto shape
-- on your size takes the drag's area (in your shape) for the maps you haven't
-- shaped, and with rememberShapes it's this map's own size from then on (off:
-- the zone's shape comes back once you let go). nil, nil: this map back to
-- automatic; where it already was, the game's size. While the map is big: the
-- big size (nil, nil: back to BIG_DEFAULT times your size).
function ns.SetMapSize(w, h, dragging)
    local map = BattlefieldMapFrame
    if not (map and defaultW) then return end
    -- docked over the minimap (Dock.lua): the grip sizes the square
    if ns.Docked and ns.Docked() then ns.DockResize(map, w, h, dragging) return end
    local c = Cfg()
    local perZone = PerZone(map)
    local mapID = perZone and c.rememberShapes and map:GetMapID()
    if c.big then
        local world = ns.MapKind and ns.MapKind() == "world"
        if w then
            w, h = math.max(MIN_W, w), math.max(MIN_H, h)
            if world then c.worldW, c.worldH = w, h else c.bigWidth, c.bigHeight = w, h end
        elseif world then
            -- (right-click on the grip: the zone art's own shape, 3:2 in its picture, at the height it has now, so
            -- the whole zone fills it. The user: "right click on the cornergrab, it resets to the aspect")
            local sc = map.ScrollContainer
            local bw = sc and (map:GetWidth() - sc:GetWidth()) or 0
            local bh = sc and (map:GetHeight() - sc:GetHeight()) or 0
            local ph = math.max(MIN_H, map:GetHeight()) - bh
            c.worldW, c.worldH = math.max(MIN_W, ph * 1002 / 668 + bw), ph + bh
        else
            c.bigWidth, c.bigHeight = nil, nil
        end
    elseif DungeonKey() then
        Cfg().dungeonSizes = Cfg().dungeonSizes or {}
        local mw, mh = ManualSize()
        Cfg().dungeonSizes[DungeonKey()] = w and { math.max(MIN_W, w), math.max(MIN_H, h) } or { mw, mh }
    elseif w then
        w, h = math.max(MIN_W, w), math.max(MIN_H, h)
        if perZone then
            if mapID then c.zoneSizes[mapID] = { w, h } end
            local bw, bh = ManualSize()
            local k = math.sqrt((w * h) / (bw * bh))
            c.width, c.height = math.max(MIN_W, bw * k), math.max(MIN_H, bh * k)
        else
            c.width, c.height = w, h
        end
    elseif mapID and c.zoneSizes[mapID] then
        c.zoneSizes[mapID] = nil
    else
        c.width, c.height = nil, nil
    end
    shapeDragging = dragging and true or false
    if dragging then
        StopGlide()
        ns.Safe("MapControls SetShape", SetShape, map, w, h)
    else
        -- (let go: which half of the screen it stands in now, from the place and the width just dragged)
        local pos = c.pos
        if pos and pos.kind == "topleft" and pos.w then pos.right = pos.x + pos.w / 2 > UIParent:GetWidth() / 2 end
        UpdateShape()
    end
end

local bigButton  -- the red arrow beside the X: shrink while the map is big, grow while small
-- Which big map (2026-11-22, the user: "yo, you like this type of big map, or this other type? Pick one"): "big",
-- your map made bigger (the arrow, the glide), or "world", the world map of our own (Lab/WorldPanel.lua: your map
-- in a window with the quest log). One setting; stored as the Lab's worldLog.on while it is in the Lab. The
-- settings window (Settings small fixes) asks and sets it through ns.SetMapKind. "world" only where the world
-- map is built in (Lab/WorldPanel.lua loaded).
-- The world map is the big map (the user, 2026-11-22: "We have no need for "bigmap" without it being worldmap"):
-- no pick in the settings any more. A save that has not said (no worldLog.on) is "world", as Lab/WorldLog.lua's
-- DEFAULTS; a save from before, set to the big map by the old pick, is moved to the world map once (onlyWorld).
-- worldLog.on stays a dev switch: the bench's world map tab, /worldlog.
function ns.MapKind()
    if not ns.WorldMapHideNow then return "big" end
    local lab = WaymarkDB and WaymarkDB.lab
    local c = lab and lab.worldLog
    if c and not c.onlyWorld then c.onlyWorld, c.on = true, true end
    local on = c and c.on
    if on == nil then on = true end
    return on and "world" or "big"
end
-- the world map is up now (never docked: ToggleBigMap lends the dock out for it)
function ns.WorldMapUp()
    local map = BattlefieldMapFrame
    return ns.MapKind() == "world" and Cfg().big and map and map:IsShown() and not (ns.Docked and ns.Docked()) and true or false
end
-- (the arrow stays with the world map picked, with its own icon: RefreshBigButton. The user, 2026-11-22: "bring
-- back the arrow, other icon when worldmap is switched on"; it was gone that morning, "no arrow to grow")
function ns.WorldArrowGone() return false end
function ns.ApplyRedButtons()
    local map = BattlefieldMapFrame
    local close = map and map.BorderFrame and map.BorderFrame.CloseButton
    local red = ns.db and ns.db.toggles and ns.db.toggles.hideRed and true or false
    for i = 1, 2 do
        local f = i == 1 and close or bigButton
        -- (the world map on: no arrow to grow, there is no big map. The user, 2026-11-22, "no arrow to grow when
        -- using worldmap, and esc always closes it")
        local hide = red or (i == 2 and ns.WorldArrowGone and ns.WorldArrowGone())
        -- (shown again only if it was this switch that hid it: a folded map keeps its own count, Collapse.lua)
        if not f then
            -- (no such button on this client)
        elseif hide then
            if f:IsShown() then
                f.bfiRedHidden = true
                f:Hide()
            end
        elseif f.bfiRedHidden then
            f.bfiRedHidden = nil
            f:Show()
        end
    end
    if ns.UpdateQuickButton then ns.UpdateQuickButton() end
end
local CLOSE_ART = 0.7  -- the close X's art: this much of its button (SetupBigButton)
local closeHome  -- where the close X sits by default; .art: its art there (SetupBigButton)

-- the arrow: where it was moved to, else left of the X's art (or in its place,
-- when the X was moved away)
local function PlaceBigButton()
    if not bigButton or ns.PlaceMoved(bigButton) then return end
    bigButton:ClearAllPoints()
    local close = BattlefieldMapFrame.BorderFrame and BattlefieldMapFrame.BorderFrame.CloseButton
    if closeHome and ns.ButtonMoved(close) then
        bigButton:SetPoint("RIGHT", closeHome.art, "RIGHT")
    elseif closeHome then
        bigButton:SetPoint("RIGHT", closeHome.art, "LEFT", -1, 0)
    else
        bigButton:SetPoint("TOPRIGHT", BattlefieldMapFrame, "TOPRIGHT", -26, -2)
    end
end

-- big: docked over the minimap (Dock.lua) its own big, not your map's
local function IsBig()
    if ns.Docked and ns.Docked() then return ns.db.dock.big and true or false end
    return Cfg().big and true or false
end

local function RefreshBigButton()
    local big = IsBig()
    -- (with the world map picked: the game's red button with a globe, the Lab's art (Lab/WorldPanel.lua names it,
    -- ns.WORLD_ARROW_ART, so a release, which has neither, holds no path to it). It opens the world map; it never
    -- reads as grow. The world map's own window has its close)
    local art = ns.MapKind and ns.MapKind() == "world" and ns.WORLD_ARROW_ART
    local look = art and "world" or big and "big" or "small"
    if not bigButton or bigButton.look == look then return end
    bigButton.big, bigButton.look = big, look
    -- (the game's own red button with its rim, as the X beside it wears (the user, 2026-11-22: "it needs same border
    -- as X"): the X's own art, its middle covered by a piece of its own red face, the folded map laid on that)
    local b = bigButton
    if art and not b.mapFace then
        b.mapFace = b:CreateTexture(nil, "OVERLAY", nil, 1)
        b.mapGlyph = b:CreateTexture(nil, "OVERLAY", nil, 2)
        b:HookScript("OnMouseDown", function(self)
            if self.look ~= "world" then return end
            ns.SetArtPart(self.mapFace, "redbutton-exit-pressed-2x", 0.16, 0.26, 0.16, 0.26)
            self.mapGlyph:SetPoint("CENTER", 1, -1)
        end)
        b:HookScript("OnMouseUp", function(self)
            if self.look ~= "world" then return end
            ns.SetArtPart(self.mapFace, "redbutton-exit-2x", 0.16, 0.26, 0.16, 0.26)
            self.mapGlyph:SetPoint("CENTER", 0, 0)
        end)
    end
    if b.mapFace then
        b.mapFace:SetShown(art and true or false)
        b.mapGlyph:SetShown(art and true or false)
    end
    if art then
        ns.SetArt(b:GetNormalTexture(), "redbutton-exit-2x")
        ns.SetArt(b:GetPushedTexture(), "redbutton-exit-pressed-2x")
        ns.SetArtPart(b.mapFace, "redbutton-exit-2x", 0.16, 0.26, 0.16, 0.26)
        b.mapFace:ClearAllPoints()
        b.mapFace:SetPoint("TOPLEFT", b, "TOPLEFT", b:GetWidth() * 0.2, -b:GetHeight() * 0.2)
        b.mapFace:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -b:GetWidth() * 0.2, b:GetHeight() * 0.2)
        b.mapGlyph:SetTexture(art.glyph)
        b.mapGlyph:ClearAllPoints()
        b.mapGlyph:SetPoint("CENTER", 0, 0)
        b.mapGlyph:SetSize(b:GetWidth() * 0.82, b:GetHeight() * 0.82)
    else
        ns.SetArt(b:GetNormalTexture(), big and "redbutton-condense-2x" or "redbutton-expand-2x")
        ns.SetArt(b:GetPushedTexture(), big and "redbutton-condense-pressed-2x" or "redbutton-expand-pressed-2x")
    end
    -- (the gear and the toggles line up left of it: Options)
    if ns.UpdateQuickButton then ns.UpdateQuickButton() end
    if ns.LayoutToggles then ns.LayoutToggles() end
end

-- the map closed: open it, and big (it may have closed big already); opened so, the next press
-- closes it again, back to small for next time (the user, 2026-11-03: M as a big map of its own).
-- Open already: big and small.
local openedBig  -- the big map key opened the map (cleared when the map closes any way)
local keyGrew    -- the big map key grew a map that was open already (cleared when it's small again)

-- Escape puts the big map away (the user 2026-11-17: "Opened by keybind, close on esc. Opened by
-- arrow, shrink to small"): shut if its key opened the map, back to small however else it got big
-- (the arrow button, the key on an open map). Not the docked big map.
-- How: a frame with nothing to see, in the game's list of windows Escape closes, shown while the
-- map is big. The game hides it on Escape and its OnHide does the rest. (The map itself is not in
-- that list: small, it is made to stay open.)
local escape, escapeOurs
local function EscapeWatch()
    local map = BattlefieldMapFrame
    local want = map and map:IsShown() and Cfg().big and not (ns.Docked and ns.Docked()) and true or false
    if want and not escape then
        escape = CreateFrame("Frame", "WaymarkBigMapEscape")
        escape:SetSize(1, 1)
        escape:Hide()
        escape:SetScript("OnHide", function()
            if escapeOurs then return end
            local m = BattlefieldMapFrame
            if not (m and m:IsShown() and Cfg().big) then openedBig, keyGrew = nil, nil return end
            if ns.Docked and ns.Docked() then return end
            if openedBig then ns.ToggleBigMap(true) else keyGrew = nil ns.ToggleBigMap() end
        end)
        tinsert(UISpecialFrames, "WaymarkBigMapEscape")
    end
    if escape and escape:IsShown() ~= want then
        escapeOurs = true
        escape:SetShown(want)
        escapeOurs = nil
    end
    if ns.QuestLogFollowBig then ns.QuestLogFollowBig(want) end  -- (Tracker.lua: the quest log comes and goes with the big map)
end

-- back to small without the grow animation (the map closed, or about to show)
local function SmallNow()
    local c = Cfg()
    -- (a small map's place waiting while the world map was up: back, whatever made the map small)
    if c.smallPos then c.pos, c.smallPos = c.smallPos, nil end
    if not c.big then return end
    c.big = false
    StopGlide()
    ns.Safe("MapControls UpdateShape", UpdateShape, true, true)
    RefreshBigButton()
    EscapeWatch()
end

-- The world map (Lab/WorldPanel.lua) is a thing of its own, not a grown map: with it on there is no big map,
-- the key and the arrow open it straight, at its own place, and closing it closes it (the user, 2026-11-22:
-- "make it something of its own", "Either have bigmap, or worldmap on, cant have both", "worldmap doesnt grow
-- and shrink to docked map etc, it just closes"). No glide either way. The window goes first, so it never
-- wraps the small map for a blink. A small map that was up before comes back as it was, at its own place.
-- What the world map leaves alone (the user, 2026-11-22, "All six, go"): folding, fading, clicks through, soft edges,
-- clear view's cuts and the map's opacity are the small map's; each asks ns.WorldMapUp, and here they hear it changed
local ApplyOpacity   -- (below, in Setup)
-- On the world map a zone opens whole, fully out at its middle, however it was reached (a click on the continent,
-- the log, the place path): the user, 2026-11-22, "Clicking from continent to a zone in worldmap should open the zone
-- fully zoomed out". After the game's own view for the new map, a moment later, as WorldAround's opening
local worldMapHooked
-- the whole zone, fully out: at the middle of the art, or, when the map follows you, at the spot following would
-- glide to (the arrow held in the zone's useful part, CenterOnPlayer's ZoneClamp), so it does not open and then pan.
-- The user, 2026-11-22: "Worldmap actually blinks, then pans. because it zooms out first from my docked zoom"
local function WorldWholeView(map, sc)
    local lv = sc.zoomLevels
    if not (lv and lv[1]) then return end
    local x, y = 0.5, 0.5
    if (Cfg().center or ribbon) and not IsWorld(sc.mapID) then
        local pos = map:GetMapID() and C_Map.GetPlayerMapPosition(map:GetMapID(), "player")
        if pos and pos.x and (pos.x > 0 or pos.y > 0) then x, y = ZoneClamp(sc, lv[1].scale, pos.x, pos.y) end
    end
    pcall(ApplyView, sc, lv[1].scale, x, y)
end
local function WorldZoneWhole(map)
    if worldMapHooked or not (map and map.OnMapChanged) then return end
    worldMapHooked = true
    hooksecurefunc(map, "OnMapChanged", function()
        if not (ns.WorldMapUp and ns.WorldMapUp() and C_Timer) then return end
        C_Timer.After(0.05, function()
            if not ns.WorldMapUp() then return end
            local sc = map.ScrollContainer
            local info = sc and sc.mapID and C_Map.GetMapInfo(sc.mapID)
            if not (info and Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.Zone) then return end
            pcall(AddZoomLevels, sc)
            WorldWholeView(map, sc)
        end)
    end)
end
local function WorldAround(map)
    WorldZoneWhole(map)
    if ns.UnfoldForWorld and ns.WorldMapUp() then ns.Safe("World map unfold", ns.UnfoldForWorld) end
    ns.Safe("MapControls ApplyOpacity", ApplyOpacity, map)
    if ns.ApplyClickThrough then ns.Safe("World map clicks", ns.ApplyClickThrough) end
    if ns.UpdateSoftEdges then ns.UpdateSoftEdges() end
    if ns.PlaceSearch then ns.Safe("World map search", ns.PlaceSearch) end   -- (the magnifier rests: the log's box finds it all)
    if ns.ApplyClearView and ns.ClearView and ns.ClearView() then ns.Safe("World map clear view", ns.ApplyClearView) end
    -- (its zoom steps again: the world map's furthest is the whole zone, the small map's covers its pane. Opened,
    -- it shows the whole zone, a moment later, once the window has given the map its size)
    local sc = map.ScrollContainer
    if sc then
        pcall(AddZoomLevels, sc)
        if ns.WorldMapUp() and C_Timer then
            -- (at once too, at the size it has so far: else the docked square's zoom showed for a moment first, the
            -- "blink"; the moment later sets it again at the window's own size)
            WorldWholeView(map, sc)
            C_Timer.After(0.05, function()
                if not ns.WorldMapUp() then return end
                pcall(AddZoomLevels, sc)
                WorldWholeView(map, sc)
            end)
        end
    end
end
-- (mapFrame.worldBack: the world map opened over a small map that was showing, kept over a /reload; mapFrame.
-- dockLent: it opened from the docked square, which is lent out meanwhile and docked again when it closes)
local function WorldOpen(map, fromSmall)
    local c = Cfg()
    -- (the small or docked map's own view, kept for when the world map closes: hidden on the way out, the map
    -- saves the world map's view, and the small map came back at its zoom. The user, 2026-11-22: "Map carried the
    -- zoom level from worldmap to docked"; the trace: RestoreView put the world map's 0.78 over the docked 1.45)
    if map:IsShown() then pcall(SaveView, map) end
    map.wmSmallView = savedView
    -- (a square browsing out on a continent or the world: the world map opens on your own zone, as a middle-click
    -- brings it home. The user, 2026-11-22: "Continent zoom carried from docked to worldmap too", then "Yes, my zone")
    local info = C_Map.GetMapInfo(map:GetMapID() or 0)
    local T = Enum and Enum.UIMapType
    map.wmSmallMap = nil
    if info and T and info.mapType < T.Zone and ns.Browsing and ns.Browsing() and ns.BrowseHome then
        map.wmSmallMap = map:GetMapID()   -- (the square goes back to it when the world map closes)
        ns.Safe("World map opens home", ns.BrowseHome)
    end
    if fromSmall and map:GetLeft() then SavePosition(map) end
    c.smallPos = c.pos
    if c.worldPos then c.pos = c.worldPos end
    c.big = true
    StopGlide()
    growCorner = nil
    ns.Safe("MapControls UpdateShape", UpdateShape, true, true)
    RestorePosition(map)
    c.worldBack = fromSmall and true or nil
    RefreshBigButton()
    EscapeWatch()
    WorldAround(map)
    if ns.WorldMapShowNow then ns.Safe("World map open", ns.WorldMapShowNow) end
end
local worldClosing
-- The game's minimap kept out of sight while the docked square is lent to the world map: undocking puts it back at
-- its default place, and it blinked into the top right while the world map was up, wherever the square is kept. The
-- user, 2026-11-22: "minimap blinks into existence in the top right, even if one uses the docked in the leftside",
-- then "A, empty corner". Shown again as the world map closes (the dock then takes it again)
local minimapHid
local function MinimapAside(hide)
    local c = MinimapCluster
    if not c then return end
    if hide then
        if c:IsShown() then c:Hide() minimapHid = true end
    elseif minimapHid then
        minimapHid = nil
        c:Show()
    end
end
local function WorldClose(map)
    if worldClosing then return end   -- (its own ToggleBattlefieldMap below comes back through the map's OnHide)
    worldClosing = true
    if ns.WorldMapHideNow then ns.Safe("World map close", ns.WorldMapHideNow) end
    local c = Cfg()
    if map:GetLeft() and c.big then SavePosition(map) c.worldPos = c.pos end
    c.pos = c.smallPos or c.pos
    c.smallPos = nil
    local back, lent = c.worldBack, c.dockLent
    c.worldBack, c.dockLent = nil, nil
    openedBig, keyGrew = nil, nil
    if not back and map:IsShown() and ToggleBattlefieldMap then pcall(ToggleBattlefieldMap) end
    -- (the small or docked map's own view back, kept at WorldOpen: its OnShow restores this one, not the world's)
    if map.wmSmallView then savedView = map.wmSmallView end
    map.wmSmallView = nil
    -- (the square was out on a continent: back on it, its own view with it. The user, 2026-11-22: "Worldmap brings
    -- docked back to zone when switching back")
    if map.wmSmallMap and ns.BrowseTo then ns.Safe("World map, the square's map back", ns.BrowseTo, map.wmSmallMap) end
    map.wmSmallMap = nil
    SmallNow()
    RestorePosition(map)
    if back and map:IsShown() then pcall(RestoreView, map) end   -- (over a small map that stayed up: its view now)
    worldClosing = nil
    EscapeWatch()
    WorldAround(map)
    -- (opened from the docked square: docked again. In a fight the dock waits for its end, Dock.lua)
    MinimapAside(false)
    if lent and ns.db and ns.db.dock then
        ns.db.dock.on = true
        if ns.ApplyDock then ns.Safe("World map dock back", ns.ApplyDock) end
    end
end
function ns.CloseWorldMap()
    local map = BattlefieldMapFrame
    if map and ns.WorldMapUp() then WorldClose(map) end
end
-- After a /reload or a login with the dock lent out (Dock.lua's login asks this before it docks): docked again,
-- the small map's place back, nothing left big
function ns.DockLentBack()
    local c = ns.db and ns.db.mapFrame
    if not (c and c.dockLent) then return end
    c.dockLent, c.worldBack, c.big = nil, nil, false
    c.pos = c.smallPos or c.pos
    c.smallPos = nil
    if ns.db.dock then ns.db.dock.on = true end
end
-- Docked, the key opens the world map at its own place and the square goes back to the game's minimap meanwhile
-- (the user's pick, 2026-11-22): the dock is lent out as the dock key would, and comes back on close. In a fight
-- the dock can't change: the world map opens when the fight ends.
local worldAfterFight
local function WorldFromDock()
    if InCombatLockdown and InCombatLockdown() then
        if not worldAfterFight then
            worldAfterFight = CreateFrame("Frame")
            worldAfterFight:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                -- (a moment later: the dock's own wait docks it first)
                C_Timer.After(0.2, function()
                    if ns.Docked and ns.Docked() and ns.MapKind() == "world" then ns.Safe("World map from the dock", WorldFromDock) end
                end)
            end)
        end
        worldAfterFight:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if ns.MapIsBig() and ns.DockToggleBig then ns.DockToggleBig() end   -- (a docked big map from before the pick: small first)
    local c = Cfg()
    ns.db.dock.on = false
    if ns.ApplyDock then ns.ApplyDock() end
    local map = BattlefieldMapFrame
    if not map then c.dockLent = nil ns.db.dock.on = true return end
    if not map:IsShown() and ToggleBattlefieldMap then pcall(ToggleBattlefieldMap) end
    if map:IsShown() then
        WorldOpen(map, false)
        c.dockLent = true
        MinimapAside(true)
    else
        ns.db.dock.on = true
        if ns.ApplyDock then ns.ApplyDock() end
    end
end

-- (fromKey: the key binding, Keys.lua; the arrow button and menus only grow and shrink, and a
-- grow or shrink by them keeps the map open on the next press)
function ns.ToggleBigMap(fromKey)
    -- (docked over the minimap, Dock.lua: its own big map, grown from the
    -- square's corner; saving the position below would keep the docked spot as yours)
    -- (a dock waiting for a fight's end to come back counts as docked for the world map: the critic's find)
    local dockDue = ns.MapKind() == "world" and ns.db and ns.db.dock and ns.db.dock.on and not (ns.Docked and ns.Docked())
        and InCombatLockdown and InCombatLockdown()
    if (ns.Docked and ns.Docked()) or dockDue then
        if ns.MapKind() == "world" then WorldFromDock() return end
        ns.DockToggleBig()
        RefreshBigButton()
        return
    end
    local map = BattlefieldMapFrame
    if map and defaultW and ns.MapKind() == "world" then
        if map:IsShown() and Cfg().big then
            WorldClose(map)
        elseif map:IsShown() then
            WorldOpen(map, true)
        else
            if ToggleBattlefieldMap then pcall(ToggleBattlefieldMap) end
            if map:IsShown() then WorldOpen(map, false) end
        end
        return
    end
    if map and map:IsShown() and openedBig and fromKey then
        openedBig = nil
        if ToggleBattlefieldMap then pcall(ToggleBattlefieldMap) end
        if not map:IsShown() then SmallNow() end
        EscapeWatch()
        return
    end
    openedBig, keyGrew = nil, nil
    local opened  -- (opened now: straight to big, no grow; the user, 2026-11-03)
    if not (map and map:IsShown()) then
        if ToggleBattlefieldMap then pcall(ToggleBattlefieldMap) end
        map = BattlefieldMapFrame
        if not (map and map:IsShown()) then return end
        openedBig = fromKey or nil
        if Cfg().big then EscapeWatch() return end
        opened = true
    end
    if not defaultW then EscapeWatch() return end
    local c = Cfg()
    c.big = not c.big
    keyGrew = c.big and fromKey and not opened or nil
    if c.big then
        -- the map is placed by its top-left corner from here on (as when you
        -- drag it), so the kept corner can move it
        if not (c.pos and c.pos.kind == "topleft") and map:GetLeft() then
            SavePosition(map)
            RestorePosition(map)
        end
        local x, y = map:GetCenter()
        local k = map:GetEffectiveScale() / UIParent:GetEffectiveScale()
        c.bigCorner = x and { x * k > UIParent:GetWidth() / 2, y * k < UIParent:GetHeight() / 2 } or nil
    end
    StopGlide()
    growCorner = c.bigCorner
    ns.Safe("MapControls UpdateShape", UpdateShape, opened or false, true, BIG_TIME)
    RefreshBigButton()
    EscapeWatch()
end

function ns.MapIsBig() return IsBig() end

-- (M and the map you picked: the settings window's own question binds M to the Big map key, Options.lua; the
-- key opens whichever kind is picked, ToggleBigMap. Nothing here binds a key.)

-- The switch (the settings window calls it; /worldlog too): which big map is yours. Safe at any time, in a fight,
-- docked, mid-glide: a big or world map that is up is put away the old kind's way first, then the kind changes,
-- so no place, size or window is left half one and half the other (fix 2 of the switch's report). Each kind keeps
-- its own place and size for when it comes back.
function ns.SetMapKind(kind)
    kind = kind == "world" and "world" or "big"
    if kind == ns.MapKind() then return end
    if kind == "world" and not ns.WorldMapHideNow then return end   -- (no world map in this build)
    local map = BattlefieldMapFrame
    -- (a big map closed big, as the game's key leaves it: small for next time, so the new kind opens its own way)
    if map and not map:IsShown() and Cfg().big and not (ns.Docked and ns.Docked()) then SmallNow() end
    if map and map:IsShown() and IsBig() then
        if ns.Docked and ns.Docked() then
            ns.DockToggleBig()
        elseif ns.MapKind() == "world" then
            WorldClose(map)
        else
            local key = openedBig
            StopGlide()
            SmallNow()
            if key and ToggleBattlefieldMap then pcall(ToggleBattlefieldMap) end
        end
    end
    openedBig, keyGrew = nil, nil
    if not (WaymarkDB and ns.LabCfg) then return end
    ns.LabCfg("worldLog").on = kind == "world"
    ns.Safe("Map kind", function()
        ns.ApplyRedButtons()
        RefreshBigButton()
        EscapeWatch()
        if ns.BigMapKeyNames then ns.BigMapKeyNames() end   -- (Keys.lua, the settings session)
        if ns.ApplyQuestWindow then ns.ApplyQuestWindow("keyL") end   -- (L is off with the world map: Tracker.lua)
        if ns.PlaceSearch then ns.PlaceSearch() end
        if ns.WorldPanelChanged then ns.WorldPanelChanged() end
    end)
end
-- (the corner grip, before a drag from a corner other than the bottom right: the map is placed by its
-- top-left corner from here on, as when you drag it, so the corner that stands still can move it)
function ns.EnsureMapPlaced()
    local map, c = BattlefieldMapFrame, Cfg()
    if not map or (ns.Docked and ns.Docked()) then return end
    if not (c.pos and c.pos.kind == "topleft") and map:GetLeft() then
        SavePosition(map)
        RestorePosition(map)
    end
end
-- (Dock.lua: docking changes what big means; and whatever made the map big or small, Escape's watch follows)
ns.RefreshBigButton = function() RefreshBigButton() EscapeWatch() end

-- left of the map's close X, as big as its red X art (the button itself is
-- larger: a click margin round the art); the game's red "condense" button while
-- the map is big, "expand" while it's small, in their 2x art (the 1x one is a
-- few pixels across and blurred when drawn this big; Era: our own, Art.lua)
local function SetupBigButton(map)
    local border = map.BorderFrame
    local close = border and border.CloseButton
    -- the close X in the same 2x art, CLOSE_ART of the button's size in its
    -- middle (this art has no margin round it, the game's had), and only that
    -- part clickable. Our own Era art (Art.lua) is drawn at 70 % of that: it
    -- has no see-through edge, so it looked bigger than the game's.
    local k = CLOSE_ART * (ns.UsingSubstitutes() and 0.7 or 1)
    if close then
        local w, h = close:GetSize()
        for _, s in ipairs({ { "Normal", "redbutton-exit-2x" }, { "Pushed", "redbutton-exit-pressed-2x" },
                             { "Disabled", "redbutton-exit-disabled-2x" }, { "Highlight", "redbutton-highlight-2x" } }) do
            local tex = close["Get" .. s[1] .. "Texture"](close)
            if tex then
                ns.SetArt(tex, s[2])
                if w > 0 then
                    tex:ClearAllPoints()
                    tex:SetPoint("CENTER")
                    tex:SetSize(w * k, h * k)
                end
            end
        end
        local mx, my = w * (1 - k) / 2, h * (1 - k) / 2
        close:SetHitRectInsets(mx, mx, my, my)
    end
    local art = close and close:GetNormalTexture()
    local edge = (art and art:GetWidth() > 0) and art or close
    -- where the X is by default, kept when it's moved (hold to move, below): a
    -- frame on the X's own anchors, its art's size in the middle
    if close then
        local w, h = close:GetSize()
        closeHome = CreateFrame("Frame", nil, map)
        closeHome:SetSize(w, h)
        for i = 1, close:GetNumPoints() do closeHome:SetPoint(close:GetPoint(i)) end
        closeHome.art = CreateFrame("Frame", nil, closeHome)
        closeHome.art:SetPoint("CENTER")
        closeHome.art:SetSize(edge:GetSize())
        -- (the X's right edge: what the gear lines up against with the two red buttons hidden)
        closeHome.edge = CreateFrame("Frame", nil, closeHome)
        closeHome.edge:SetSize(1, 1)
        closeHome.edge:SetPoint("LEFT", closeHome.art, "RIGHT")
        ns.closeHome = closeHome
    end
    local b = CreateFrame("Button", nil, map)
    local size = edge and edge:GetHeight() or 0
    if size <= 0 then size = 22 * k / CLOSE_ART end
    b:SetSize(size, size)
    -- above the border art and the dungeon map, like the gear (ns.ButtonLevel)
    b:SetFrameLevel(ns.ButtonLevel(map))
    for _, s in ipairs({ "Normal", "Pushed", "Highlight" }) do
        b["Set" .. s .. "Texture"](b, "Interface\\Buttons\\WHITE8X8")
    end
    ns.SetArt(b:GetHighlightTexture(), "redbutton-highlight-2x")
    local glow = b:GetHighlightTexture()
    if glow then glow:SetBlendMode("ADD") end
    b:SetScript("OnClick", function() ns.ToggleBigMap() end)
    bigButton = b  -- (no tooltip, like the close X)
    ns.bigMapButton = b
    ns.debugFrames.bigMap = b
    RefreshBigButton()
    if close then
        ns.HoldToMove(close, "close")
        ns.PlaceMoved(close)
    end
    ns.HoldToMove(b, "bigMap")
    PlaceBigButton()
    -- "Hide the close and grow buttons" (toggles.hideRed; asked on CurseForge, 2026-11-17): both gone for
    -- good, the map's key, the header's menu and Escape still shut and grow it. Whatever shows one again
    -- (the game's border, a fold opening) finds it hidden again.
    for _, f in ipairs(close and { close, b } or { b }) do
        f:HookScript("OnShow", function(self)
            if ns.db and ns.db.toggles and ns.db.toggles.hideRed or (self == b and ns.WorldArrowGone and ns.WorldArrowGone()) then
                self.bfiRedHidden = true
                self:Hide()
            end
        end)
    end
    ns.ApplyRedButtons()
end

-- Hold to move -------------------------------------------------------------

-- Press and hold any of the map's buttons (the close X, the arrow, the gear,
-- the town / city buttons, a toggle button: that takes its whole strip) and it
-- follows the mouse until you let go; that click doesn't count. Right-click
-- while holding: back to its usual place. Saved in WaymarkDB.buttonPos
-- [key] = { its point, the map's nearest corner, x, y } (in its own units), so
-- it stays put on the big map too; 5th field true: dropped away from the map,
-- so on the screen's nearest corner instead (still shown with the map). A moved button leaves the row by the X; the
-- others close up (Options InRow). A toggle button held with Shift leaves its strip and goes alone
-- (buttonPos["toggle:<id>"]; the row closes up), and held again it moves alone, Shift or not;
-- right-click while holding slots it back in the row.
local HOLD = 0.4        -- seconds held before it moves
local OFF_MAP = 30      -- dropped further than this outside the map: kept on the screen, not the map
local held, dragging    -- the button pressed; the frame being moved
local grabX, grabY      -- that frame's point minus the cursor, in screen pixels
local holdDriver

-- where a frame's point is, in screen pixels
local function PointXY(f, point)
    local l, b, w, h = f:GetRect()
    if not l then return nil end
    local s = f:GetEffectiveScale()
    local x = point:find("LEFT") and l or point:find("RIGHT") and l + w or l + w / 2
    local y = point:find("BOTTOM") and b or point:find("TOP") and b + h or b + h / 2
    return x * s, y * s
end

local function MovePoint(f) return f.bfiMovePoint and f.bfiMovePoint() or "CENTER" end

-- the frame being moved, to the cursor (kept the grab's distance off it)
local function FollowCursor(f)
    local cx, cy = GetCursorPosition()
    local s = f:GetEffectiveScale()
    f:ClearAllPoints()
    f:SetPoint(MovePoint(f), UIParent, "BOTTOMLEFT", (cx + grabX) / s, (cy + grabY) / s)
end

-- the moved buttons' places in use: docked over the minimap (Dock.lua) its
-- own set, dock.buttonPos (yours had the toggles off the screen there);
-- create: make the table if there's none
local function Positions(create)
    local owner, key = ns.db, "buttonPos"
    if ns.Docked and ns.Docked() then owner = ns.db.dock end
    if create and not owner[key] then owner[key] = {} end
    return owner[key], owner
end

function ns.ButtonMoved(f)
    -- (the one being moved counts as moved: out of the row, so the buttons
    -- anchored to it, e.g. city view beside town view, stay put)
    if f and f == dragging then return true end
    local pos = f and f.bfiMoveKey and ns.db and Positions()
    return (pos and pos[f.bfiMoveKey]) and true or false
end

-- a moved frame to its saved place (true); false: lay it out as usual
function ns.PlaceMoved(f)
    local map = BattlefieldMapFrame
    if not (map and ns.ButtonMoved(f)) then return false end
    if f == dragging then FollowCursor(f) return true end
    local p = Positions()[f.bfiMoveKey]
    f:ClearAllPoints()
    f:SetPoint(p[1], p[5] and UIParent or map, p[2], p[3], p[4])
    return true
end

-- every map button to its saved or usual place
local function RelayoutButtons()
    local close = BattlefieldMapFrame and BattlefieldMapFrame.BorderFrame and BattlefieldMapFrame.BorderFrame.CloseButton
    if close and not ns.PlaceMoved(close) and closeHome then
        close:ClearAllPoints()
        close:SetAllPoints(closeHome)
    end
    PlaceBigButton()
    if ns.UpdateQuickButton then ns.UpdateQuickButton() end  -- (gear, town / city, toggles)
    if ns.PlaceMinimapButtons then ns.PlaceMinimapButtons() end  -- (docked: the minimap's, Dock.lua)
end

-- (docked: the docked set)
function ns.ResetButtonPositions()
    if ns.db then
        local _, owner = Positions()
        owner.buttonPos = nil
    end
    RelayoutButtons()
end
ns.RelayoutMapButtons = RelayoutButtons  -- (Dock.lua: docking swaps the set)

local function StopDrag(keep)
    local f = dragging
    dragging, held = nil, nil
    if not f then return end
    local positions, owner = Positions(true)
    local map = BattlefieldMapFrame
    local point = MovePoint(f)
    local x, y = PointXY(f, point)
    local l, b, w, h = map:GetRect()
    if keep and x and l then
        local ms = map:GetEffectiveScale()
        l, b, w, h = l * ms, b * ms, w * ms, h * ms
        -- dropped well away from the map: kept on the screen instead (its nearest
        -- corner), so moving or resizing the map leaves it be
        local away = math.max(l - x, x - (l + w), b - y, y - (b + h)) / UIParent:GetEffectiveScale()
        local screen = away > OFF_MAP or nil
        if screen then
            local us = UIParent:GetEffectiveScale()
            l, b, w, h = 0, 0, UIParent:GetWidth() * us, UIParent:GetHeight() * us
        end
        local corner = (y > b + h / 2 and "TOP" or "BOTTOM") .. (x > l + w / 2 and "RIGHT" or "LEFT")
        local cx = corner:find("LEFT") and l or l + w
        local cy = corner:find("TOP") and b + h or b
        local s = f:GetEffectiveScale()
        positions[f.bfiMoveKey] = { point, corner, (x - cx) / s, (y - cy) / s, screen }
    else
        positions[f.bfiMoveKey] = nil
        if not next(positions) then owner.buttonPos = nil end
    end
    RelayoutButtons()
end

local function HoldUpdate()
    local left = IsMouseButtonDown("LeftButton")
    if dragging then
        if IsMouseButtonDown("RightButton") then
            StopDrag(false)
        elseif not left then
            StopDrag(true)
        else
            FollowCursor(dragging)
        end
        return
    end
    if held and left then
        if GetTime() - held.bfiDownAt >= HOLD then
            local f = held.bfiMoveTarget
            if held.bfiMoveKey and f ~= held and (IsShiftKeyDown() or ns.ButtonMoved(held)) then f = held end
            local px, py = PointXY(f, MovePoint(f))
            if not px then return end
            -- (from where it was pressed: the mouse may have moved while held)
            grabX, grabY = px - held.bfiDownX, py - held.bfiDownY
            dragging = f
            held.bfiSwallow = true
            if held.CloseMenu then held:CloseMenu() end  -- (a menu that opened on the press)
            GameTooltip:Hide()
            -- the others it was anchored to close up now, not on the drop
            RelayoutButtons()
            FollowCursor(f)
        end
        return
    end
    held = nil
    -- (both buttons up: the click they made has been swallowed; clicks count again)
    if not (left or IsMouseButtonDown("RightButton")) then
        holdDriver:Hide()
        C_Timer.After(0.1, function()
            for _, b in ipairs(ns.holdButtons) do b.bfiSwallow = nil end
        end)
    end
end

ns.holdButtons = {}
-- b: the button you hold; key: its saved place; target: what moves (default b);
-- point(): the target's point it's placed by (default its middle)
function ns.HoldToMove(b, key, target, point)
    target = target or b
    target.bfiMoveKey, target.bfiMovePoint = key, point
    b.bfiMoveTarget = target
    if not holdDriver then
        holdDriver = CreateFrame("Frame")
        holdDriver:Hide()
        holdDriver:SetScript("OnUpdate", function() ns.Safe("MapControls hold to move", HoldUpdate) end)
    end
    b:HookScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or dragging then return end
        -- (the minimap's own buttons and the map-only one, Dock.lua: movable
        -- only while docked, the minimap's not on the big map)
        if self.bfiDockOnly and not (ns.DockButtonMovable and ns.DockButtonMovable(self)) then return end
        held, self.bfiDownAt = self, GetTime()
        self.bfiDownX, self.bfiDownY = GetCursorPosition()
        holdDriver:Show()
    end)
    -- (set after the button's own OnClick: a click that moved it does nothing;
    -- a plain frame has no OnClick)
    if not (b.HasScript and b:HasScript("OnClick")) then
        ns.holdButtons[#ns.holdButtons + 1] = b
        return
    end
    local click = b:GetScript("OnClick")
    b:SetScript("OnClick", function(self, ...)
        if self.bfiSwallow then return end
        if click then return click(self, ...) end
    end)
    ns.holdButtons[#ns.holdButtons + 1] = b
end

-- Setup -------------------------------------------------------------------

-- The map's own opacity (Blizzard keeps it in BattlefieldMapOptions and sets it
-- from the tab's menu). Ours starts from whatever it is now.
function ApplyOpacity(map)
    if not (BattlefieldMapOptions and map.RefreshAlpha) then return end
    local c = Cfg()
    if c.opacity == nil then c.opacity = 1 - (BattlefieldMapOptions.opacity or 0) end
    -- (clear view has its own; mapFrame.opacity is kept for when it's off. The world map is always whole)
    local op = ns.ClearView and ns.ClearView() and ns.db.clearView.opacity or c.opacity
    if ns.WorldMapUp() then op = 1 end
    local want = 1 - op
    if BattlefieldMapOptions.opacity ~= want then
        BattlefieldMapOptions.opacity = want
        pcall(map.RefreshAlpha, map)
    end
end

-- the map locked in place: no moving it by the header or the edge
function ns.ToggleMapLock()
    Cfg().locked = not Cfg().locked
    ns.OnSettingChanged("mapFrame", "locked")
end

-- group: the settings group that changed (nil = everything)
function ns.ApplyMapControls(group)
    local map = BattlefieldMapFrame
    if not map then return end
    if mover then mover:SetShown(Cfg().unlocked and not Cfg().locked) end
    ApplySizes(map)
    ns.Safe("MapControls ApplyOpacity", ApplyOpacity, map)
    -- the frame's opacity, and the unexplored areas fading with the map's (Style, Explore)
    if ns.ApplyFrameAlpha then ns.ApplyFrameAlpha() end
    if ns.UpdateExplore then ns.UpdateExplore() end
    PlaceTab(map)
    if map.ScrollContainer then
        pcall(AddZoomLevels, map.ScrollContainer)
        pcall(CenterZoneFit, map.ScrollContainer)
    end
    ns.Safe("MapControls UpdateShape", UpdateShape)
    RefreshBigButton()  -- (a loaded setup brings its own big / normal)
    EscapeWatch()
    if not group then RelayoutButtons() end  -- (and its own button places)
    -- auto-zoom settings changed: decide afresh (not for other map settings,
    -- or dragging e.g. the opacity slider would re-zoom you)
    if group == "zoom" then lastWant = nil end
end

function ns.SetupMapControls(map)
    defaultW, defaultH = map:GetSize()
    settleAt = GetTime() + 10
    SetupMover(map)
    RestorePosition(map)  -- (also puts the tab in its holder if hidden: PlaceTab)
    map:HookScript("OnShow", function()
        -- (on a new install the game's options aren't there yet at setup: its faint default stayed
        -- till a setting changed, clear view's toggle say)
        ns.Safe("MapControls ApplyOpacity", ApplyOpacity, map)
        RestorePosition(map)
        ApplySizes(map)
        ns.Safe("MapControls UpdateShape", UpdateShape, true)
        pauseUntil = 0
        heldAt = nil  -- (a freshly opened map follows you again)
        EscapeWatch()
    end)
    map:HookScript("OnHide", function()
        -- (the world map shut some other way, the game's own key: closed as its own close does, so the small map
        -- comes back small at its own place next time, not as the world map)
        -- (the game's own key hid the frame: only the world map closes, the small map that was up before comes
        -- back, a frame later, outside the hide. The user's pick, 2026-11-22: Shift-M closes only the world map)
        -- (map:IsShown() still true: its parent hid, Alt-Z or a cinematic; the world map stays as it was)
        if Cfg().big and ns.MapKind() == "world" and not (ns.Docked and ns.Docked()) and not map:IsShown() then
            local back = Cfg().worldBack
            WorldClose(map)
            if back and C_Timer then
                C_Timer.After(0, function()
                    -- (not against a "hide the map" profile, inside a dungeon, or in a fight: the critic, 2026-11-22)
                    if map:IsShown() or Cfg().big or not ToggleBattlefieldMap then return end
                    if (ns.MapHiddenByProfile and ns.MapHiddenByProfile()) or IsInInstance() or InCombatLockdown() then return end
                    pcall(ToggleBattlefieldMap)
                end)
            end
        end
        openedBig, keyGrew = nil, nil
        EscapeWatch()
    end)
    -- into a dungeon the map is small, however it was left (the user, 2026-11-03: it came back
    -- big after being closed big)
    local enter = CreateFrame("Frame")
    enter:RegisterEvent("PLAYER_ENTERING_WORLD")
    enter:SetScript("OnEvent", function()
        -- (the world map: closed its own way, so the small map keeps its place: fix 1 of the switch's report)
        if IsInInstance() and not (ns.Docked and ns.Docked()) then
            if ns.WorldMapUp() then WorldClose(map) else SmallNow() end
        end
    end)

    local sc = map.ScrollContainer
    if sc and not ns.FOREVER then
        -- (Classic Era: the cursor is measured in UIParent's scale, not the map's
        -- own, so with the map scaled the wheel zoomed at the wrong spot)
        function sc:GetCursorPosition()
            local x, y = GetCursorPosition()
            local s = self:GetEffectiveScale()
            return x / s, y / s
        end
    end
    if sc then
        -- you zoom or drag yourself: stop any auto-zoom animation, hold the
        -- view until you move
        local function Pause()
            Hold(map)
            -- (not a glide this very click started: Browse's handlers run first)
            if not (anim and anim.glide and anim.t0 == GetTime()) then StopAnim() end
        end
        sc:HookScript("OnMouseUp", Pause)
        sc:HookScript("OnMouseWheel", Pause)
        -- a new shape (yours, auto width, any other resize): new zoom steps
        sc:HookScript("OnSizeChanged", function() ns.Safe("MapControls RefitZoom", RefitZoom, map) end)
        sc:HookScript("OnMouseWheel", function(self, delta)
            if delta < 0 then
                pcall(CenterZoneFit, self)
                pcall(ZoomOutInZone, self)
            end
        end)
        if sc.CreateZoomLevels then
            hooksecurefunc(sc, "CreateZoomLevels", function(self)
                pcall(AddZoomLevels, self)
                if self.bfiReshaping then return end  -- (RefitZoom places the view)
                -- after the game's own reset to the art's middle (same frame);
                -- a new map may want a different width
                C_Timer.After(0, function()
                    pcall(CenterZoneFit, self)
                    ns.Safe("MapControls CarryZoom", CarryZoom, map)  -- (another zone: your zoom)
                    ns.Safe("MapControls UpdateShape", UpdateShape)
                end)
            end)
        end
        pcall(AddZoomLevels, sc)
    end
    map:HookScript("OnHide", function()
        pcall(SaveView, map)
    end)
    -- in the same frame, right after the game's own show code (which resets the
    -- zoom), so the reset view never gets drawn; then a check a moment later
    map:HookScript("OnShow", function()
        pcall(RestoreView, map)
        C_Timer.After(0.1, function() pcall(RecheckView, map) end)
    end)

    WrapGameGroupTooltip(map)
    SetupBigButton(map)
    local elapsed, sinceAuto, sinceTip = 0, 0, 0
    local ticker = ns.TimedFrame("MapControls tick")
    ticker:SetScript("OnUpdate", function(_, dt)
        if map:IsShown() then
            ns.Safe("MapControls UpdateFade", UpdateFade, map, dt)
            -- following you: every frame, so the game's own glide runs on
            -- smoothly (twice a second, it moved in starts and stops)
            -- (Keep centred alone decides: docked and in town it used to follow regardless, so the
            -- button did nothing there. On the minimap face Dock.lua keeps it on you itself, and
            -- the two pulling a little differently made it flicker)
            if (Cfg().center or ribbon) and not (ns.Browsing and ns.Browsing()) and not (ns.DockMinimapFace and ns.DockMinimapFace()) then
                ns.Safe("MapControls CenterOnPlayer", CenterOnPlayer, map)
            end
            sinceTip = sinceTip + dt
            if sinceTip >= 0.1 then
                sinceTip = 0
                ns.Safe("MapControls UpdateGroupTooltip", UpdateGroupTooltip, map)
            end
        end
        elapsed = elapsed + dt
        if elapsed < 0.5 then return end
        sinceAuto = sinceAuto + elapsed
        elapsed = 0
        if not map:IsVisible() then return end
        -- (entering or leaving a cave view changes the wanted width too)
        ns.Safe("MapControls UpdateShape", UpdateShape)
        ns.Safe("MapControls KeepZoom", KeepZoom, map)
        if sinceAuto >= 1 then
            sinceAuto = 0
            ns.Safe("MapControls AutoZoom", AutoZoom, map)
        end
    end)

    ns.ApplyMapControls()
end
