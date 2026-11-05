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

local function SavePosition(map)
    local x, y = TopLeftUI(map)
    Cfg().pos = { kind = "topleft", x = x, y = y }
end

local function RestorePosition(map)
    -- docked over the minimap (Dock.lua): its place, not yours
    if ns.DockPlace and ns.DockPlace(map) then PlaceTab(map) return end
    local pos = Cfg().pos
    -- (positions saved by the earlier tab-moving version are left alone)
    if pos and pos.kind == "topleft" then
        -- never off the screen: at least a corner's worth of it left on
        -- (undocking once pushed it thousands of units off the left edge)
        pos.x = Clamp(pos.x, 0, UIParent:GetWidth() - 40)
        pos.y = Clamp(pos.y, 40, UIParent:GetHeight())
        PinTopLeft(map, pos.x, pos.y)
    end
    PlaceTab(map)
end
function ns.RestoreMapPosition()
    if BattlefieldMapFrame then RestorePosition(BattlefieldMapFrame) end
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
        moving = true
    end
    function ns.MapMoveStop()
        if ns.DockSquareDragStop and ns.DockSquareDragStop() then return end
        if not moving then return end
        moving = false
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
    return Cfg().center and not IsWorld(sc.mapID)
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

-- three or more of our quest pins close to the player counts as a cluster
local CLUSTER_RADIUS, CLUSTER_COUNT = 0.06, 3
-- ... and so do two or more gathering nodes within 80 yards
local NODE_YARDS, NODE_MIN = 80, 2
local function NearCluster(map, px, py)
    local n = 0
    ns.EachPin(map, function(pin, template)
        if template == "BFIQuestiePinTemplate" and pin:IsShown() and pin.normalizedX then
            local dx, dy = pin.normalizedX - px, pin.normalizedY - py
            if dx * dx + dy * dy < CLUSTER_RADIUS * CLUSTER_RADIUS then n = n + 1 end
        end
    end)
    return n >= CLUSTER_COUNT
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

-- any of the three wants to zoom (and follow) for its reason
local function TownZoomOn()
    return ns.db.townView.enabled and ns.db.townView.zoom
end

local function AnyAutoZoom()
    return ns.db.zoom.autoZoom or TownZoomOn() or ns.db.cityView.zoom
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

    -- why to be zoomed in: "city", "town", "cluster" (quests or gathering
    -- nodes), or false. In a capital it's city view or nothing: never a town
    -- close-up, and no cluster zoom among its vendors either.
    local want = false
    local inCity = InCity()
    if inCity then
        want = cityZoom and "city" or false
    elseif townZoom and InTown() then
        want = "town"
    elseif z.autoZoom and ((z.nearSpots and NearCluster(map, pos.x, pos.y))
        or (z.nearNodes and ns.GatherNodesNear and ns.GatherNodesNear(mapID, pos.x, pos.y, NODE_YARDS) >= NODE_MIN)) then
        want = "cluster"
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
                    or want == "town" and z.townX or z.clusterX
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
        if pos and pos.x and (pos.x > 0 or pos.y > 0) then x, y = pos.x, pos.y end
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

-- every half second: how close you are now
local function KeepZoom(map)
    local sc = map.ScrollContainer
    local mapID = map:GetMapID()
    -- (not auto-zoom's town, city or cluster zoom: that's not yours)
    if anim or lastWant or not (sc and sc.zoomLevels and IsZoneMap(mapID)) then return end
    if ns.Browsing and ns.Browsing() then return end  -- (another zone's zoom isn't yours)
    if carry and carry.mapID == mapID and GetTime() < carry.untilT then return end  -- (still settling)
    kept = ZoomSpot(sc, sc.targetScale or sc:GetCanvasScale()) or kept
end

local function PutZoom(map, spot)
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
            ns.Log("The zone map's arrow goes back to the game's own after a /reload.")
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
    -- (docked: one size at every zoom, the minimap's arrow's, so there's no jump between them)
    if ns.Docked and ns.Docked() then size = base * 1.12 end
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
function ns.DetailFade(map)
    local sc = map.ScrollContainer
    if not sc then return 1 end
    local lo, hi = ZoomRange(sc)
    if not lo then return 1 end
    return ns.DetailFadeAt(sc:GetCanvasScale() / lo, hi / lo)
end

-- the same for x times closer than fully out, on a map that goes reach times
-- (ZoneArt's ns.ContinentZoneZoom: a zone seen on the big map's continent)
function ns.DetailFadeAt(x, reach)
    local d = ns.db.detail
    local full = math.min(d.fullZoom or 5.5, reach)
    local from = math.min(d.fromZoom or 3.5, full)
    if full <= from * 1.001 then return x >= full * 0.999 and 1 or 0 end
    return Clamp(math.log(math.max(x, 1e-6) / from) / math.log(full / from), 0, 1)
end

-- auto shape's own sizes, per map, on (not in a cave, where the size is yours)
local function PerZone(map)
    return Cfg().autoWidth and ns.ZoneBounds and map:GetMapID() and not (ns.InCave and ns.InCave())
end

local function NormalSize(map)
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
    return UIParent:GetWidth() * k * 0.95, UIParent:GetHeight() * k * 0.95
end

local function FitScreen(map, w, h, most)
    local mw, mh = ScreenRoom(map)
    local k = math.min(most, mw / w, mh / h)
    return math.max(MIN_W, w * k), math.max(MIN_H, h * k)
end

ns.NormalMapSize = NormalSize

local function BigSize(map)
    local c = Cfg()
    if not c.bigWidth then
        local w, h = NormalSize(map)
        return FitScreen(map, w, h, BIG_DEFAULT)
    end
    return FitScreen(map, c.bigWidth, c.bigHeight, 1)
end

local function WantedSize(map)
    if ns.DockedSize then
        local w, h = ns.DockedSize(map)
        if w then return w, h end
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
        pcall(ApplyView, sc, s0 / lo0 * levels[1].scale, x0, y0)
    end
end

local growCorner  -- { right, bottom }: the edges kept still while the big map glides

-- a moved map in the right half of the screen keeps its right edge (gliding
-- to or from big: the edges in growCorner)
local function SetShape(map, w, h)
    local oldW, oldH = map:GetWidth(), map:GetHeight()
    if math.abs(oldW - w) < 0.5 and math.abs(oldH - h) < 0.5 then return end
    local pos = Cfg().pos
    local moved = pos and pos.kind == "topleft"
    local keepRight, keepBottom
    if growCorner then
        keepRight, keepBottom = growCorner[1], growCorner[2]
    else
        keepRight = moved
            and map:GetCenter() * map:GetEffectiveScale() > UIParent:GetWidth() * UIParent:GetEffectiveScale() / 2
    end
    map:SetSize(w, h)
    -- docked: centred on the minimap; undocking: your saved place as it was,
    -- not shifted by the square's size (Dock.lua)
    if ns.DockShaping and ns.DockShaping(map) then return end
    if moved and (keepRight or keepBottom) then
        local k = map:GetEffectiveScale() / UIParent:GetEffectiveScale()
        if keepRight then pos.x = pos.x + (oldW - w) * k end
        if keepBottom then pos.y = pos.y + (h - oldH) * k end
        RestorePosition(map)
    end
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
        if w then
            w, h = math.max(MIN_W, w), math.max(MIN_H, h)
            c.bigWidth, c.bigHeight = w, h
        else
            c.bigWidth, c.bigHeight = nil, nil
        end
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
        UpdateShape()
    end
end

local bigButton  -- the red arrow beside the X: shrink while the map is big, grow while small
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
    if not bigButton or bigButton.big == big then return end
    bigButton.big = big
    ns.SetArt(bigButton:GetNormalTexture(), big and "redbutton-condense-2x" or "redbutton-expand-2x")
    ns.SetArt(bigButton:GetPushedTexture(), big and "redbutton-condense-pressed-2x" or "redbutton-expand-pressed-2x")
    -- (the gear and the toggles line up left of it: Options)
    if ns.UpdateQuickButton then ns.UpdateQuickButton() end
    if ns.LayoutToggles then ns.LayoutToggles() end
end

-- the map closed: open it, and big (it may have closed big already); opened so, the next press
-- closes it again, back to small for next time (the user, 2026-11-03: M as a big map of its own).
-- Open already: big and small.
local openedBig  -- the big map key opened the map (cleared when the map closes any way)

-- back to small without the grow animation (the map closed, or about to show)
local function SmallNow()
    local c = Cfg()
    if not c.big then return end
    c.big = false
    StopGlide()
    ns.Safe("MapControls UpdateShape", UpdateShape, true, true)
    RefreshBigButton()
end

-- (fromKey: the key binding, Keys.lua; the arrow button and menus only grow and shrink, and a
-- grow or shrink by them keeps the map open on the next press)
function ns.ToggleBigMap(fromKey)
    -- (docked over the minimap, Dock.lua: its own big map, grown from the
    -- square's corner; saving the position below would keep the docked spot as yours)
    if ns.Docked and ns.Docked() then
        ns.DockToggleBig()
        RefreshBigButton()
        return
    end
    local map = BattlefieldMapFrame
    if map and map:IsShown() and openedBig and fromKey then
        openedBig = nil
        if ToggleBattlefieldMap then pcall(ToggleBattlefieldMap) end
        if not map:IsShown() then SmallNow() end
        return
    end
    openedBig = nil
    local opened  -- (opened now: straight to big, no grow; the user, 2026-11-03)
    if not (map and map:IsShown()) then
        if ToggleBattlefieldMap then pcall(ToggleBattlefieldMap) end
        map = BattlefieldMapFrame
        if not (map and map:IsShown()) then return end
        openedBig = fromKey or nil
        if Cfg().big then return end
        opened = true
    end
    if not defaultW then return end
    local c = Cfg()
    c.big = not c.big
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
end

function ns.MapIsBig() return IsBig() end
ns.RefreshBigButton = function() RefreshBigButton() end  -- (Dock.lua: docking changes what big means)

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
local function ApplyOpacity(map)
    if not (BattlefieldMapOptions and map.RefreshAlpha) then return end
    local c = Cfg()
    if c.opacity == nil then c.opacity = 1 - (BattlefieldMapOptions.opacity or 0) end
    -- (clear view has its own; mapFrame.opacity is kept for when it's off)
    local op = ns.ClearView and ns.ClearView() and ns.db.clearView.opacity or c.opacity
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
    if not group then RelayoutButtons() end  -- (and its own button places)
    -- auto-zoom settings changed: decide afresh (not for other map settings,
    -- or dragging e.g. the opacity slider would re-zoom you)
    if group == "zoom" then lastWant = nil end
end

function ns.SetupMapControls(map)
    defaultW, defaultH = map:GetSize()
    SetupMover(map)
    RestorePosition(map)  -- (also puts the tab in its holder if hidden: PlaceTab)
    map:HookScript("OnShow", function()
        RestorePosition(map)
        ApplySizes(map)
        ns.Safe("MapControls UpdateShape", UpdateShape, true)
        pauseUntil = 0
        heldAt = nil  -- (a freshly opened map follows you again)
    end)
    map:HookScript("OnHide", function() openedBig = nil end)
    -- into a dungeon the map is small, however it was left (the user, 2026-11-03: it came back
    -- big after being closed big)
    local enter = CreateFrame("Frame")
    enter:RegisterEvent("PLAYER_ENTERING_WORLD")
    enter:SetScript("OnEvent", function()
        if IsInInstance() and not (ns.Docked and ns.Docked()) then SmallNow() end
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
            -- (docked over the minimap it follows you as the minimap does; on
            -- the minimap face Dock.lua keeps it on you itself, and the two
            -- pulling a little differently made it flicker)
            if (Cfg().center or (ns.Docked and ns.Docked()) or (lastWant and AnyAutoZoom()))
               and not (ns.Browsing and ns.Browsing()) and not (ns.DockMinimapFace and ns.DockMinimapFace()) then
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
