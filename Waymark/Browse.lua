local _, ns = ...

-- Browsing: looking at another zone, the continent or the world on the
-- Battlefield Map. Right-click zoomed in goes all the way out (with the glow's
-- blink); fully out it goes one map up (zone, continent, world); left-click a zone on a
-- continent (or a continent on the world) opens it; the mouse wheel climbs:
-- fully zoomed out, a few more clicks out go up a map (the "friction": the
-- frame's inside glows on each but the last, so you feel where the zone's own
-- zoom ends). Going up starts the map above a click further out than the view
-- was, on the same spot; wheeling in on a continent zooms it toward the
-- cursor until the zone there is as big as its own map shows it, then
-- switches to that zone on the same view. While you browse, the game's own resets (zone changes,
-- UI widget updates, the map opening) are undone at once, and what follows you
-- waits (ns.Browsing: auto-zoom, town/city view, caves and dungeons).
-- Back to your map: middle-click, on the map or the header (ZoneName.lua), leave the mouse off the
-- map for browse.idle seconds, close the map (browse.onReopen), or walk into
-- another zone (browse.onZone).

local function Cfg() return ns.db.browse end

local browsed      -- the map you're looking at (nil: your own, the game's choice)
local ourSet       -- we're the ones calling SetMapID
local changedAt = 0  -- when the map last changed (the wheel's overshoot guard)

function ns.Browsing() return browsed ~= nil end
function ns.BrowsedMap() return browsed end
-- on a flight path a map you're looking at (the continent, another zone) stays (browse.taxi), and
-- your map again on landing; your own zone's map follows you as ever (the user, 2026-11-03)
function ns.HoldOnTaxi() return Cfg().taxi and browsed ~= nil and UnitOnTaxi("player") or false end

local T = Enum and Enum.UIMapType or {}

-- your own map: what the game shows when it puts the map back on you
local function HomeMap()
    if MapUtil and MapUtil.GetDisplayableMapForPlayer then
        local ok, id = pcall(MapUtil.GetDisplayableMapForPlayer)
        if ok and id then return id end
    end
    return C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
end

function ns.HomeMapName()
    local info = C_Map.GetMapInfo(HomeMap() or 0)
    return info and info.name or ""
end

local function Show(map, id)
    ourSet = true
    pcall(map.SetMapID, map, id)
    ourSet = false
end

local function Changed()
    if ns.UpdateZoneName then ns.UpdateZoneName() end
end

local idleSince  -- since when the mouse has been off the map

-- Your own map covered by a dungeon's or cave's view (Dungeon.lua, Cave.lua):
-- the map under it (in an instance the game's choice is the continent or the
-- world) is then just another map to browse. Climbing onto it doesn't bring
-- the dungeon or cave back; a right-click at the top does (OnCanvasClick).
function ns.HomeIsArt()
    return (ns.DungeonArtHome and ns.DungeonArtHome()) or (ns.CaveArtHome and ns.CaveArtHome()) or false
end

function ns.BrowseTo(id)
    local map = BattlefieldMapFrame
    if not (map and id) then return end
    if id == HomeMap() and not ns.HomeIsArt() then return ns.BrowseHome() end
    browsed, idleSince = id, nil
    Show(map, id)
    Changed()
end

function ns.BrowseHome()
    if not browsed then return end
    browsed = nil
    local map = BattlefieldMapFrame
    if map then Show(map, HomeMap()) end
    -- (a cave or dungeon map is theirs again: Cave.lua's ticker, and this)
    if ns.UpdateDungeon then ns.UpdateDungeon() end
    Changed()
end

-- the map above this one, down to the world (not the cosmic map)
local function Parent(id)
    local info = id and C_Map.GetMapInfo(id)
    local p = info and info.parentMapID
    local pinfo = p and p > 0 and C_Map.GetMapInfo(p)
    if pinfo and T.World and pinfo.mapType >= T.World then return p, pinfo end
end
ns.BrowseParent = Parent

-- Views that line up --------------------------------------------------------------

-- What the view shows: its centre and half its width and height, in the
-- map's 0..1 (the canvas is the art's size; at scale s the view shows w/s of it)
local function ViewRect(sc)
    local s = sc.targetScale or sc:GetCanvasScale()
    local cw, ch = sc.Child:GetWidth(), sc.Child:GetHeight()
    if not (s and s > 0 and cw > 0 and ch > 0) then return end
    local x = sc.targetScrollX or sc.currentScrollX or 0.5
    local y = sc.targetScrollY or sc.currentScrollY or 0.5
    return x, y, sc:GetWidth() / s / cw / 2, sc:GetHeight() / s / ch / 2
end

-- where a map sits on the one above it: left, right, top, bottom (0..1)
local function RectOn(child, parent)
    if not C_Map.GetMapRectOnMap then return end
    local ok, l, r, t, b = pcall(C_Map.GetMapRectOnMap, child, parent)
    if ok and l and r > l and b > t then return l, r, t, b end
end

-- Show this view on the map now: centre x, y and half width hw (0..1). The map
-- was just switched, so its zoom steps are already the new map's.
local putAt = -1
-- (just placed a view: MapControls' carried zoom mustn't replace it)
function ns.BrowsePlacedView() return GetTime() - putAt < 0.5 end

local function PutView(map, x, y, hw)
    local sc = map.ScrollContainer
    local cw = sc.Child:GetWidth()
    if not (hw and hw > 0 and cw > 0 and ns.ApplyMapView) then return end
    putAt = GetTime()
    local s = sc:GetWidth() / (hw * 2 * cw)
    local function Put()
        pcall(ns.ApplyMapView, sc, s, x, y)
        -- (the game's instant zoom only moves part way to a new centre and
        -- glides the rest: straight there instead, no slide)
        if sc.targetScrollX and sc.SetNormalizedHorizontalScroll then
            sc.currentScrollX, sc.currentScrollY = sc.targetScrollX, sc.targetScrollY
            pcall(sc.SetNormalizedHorizontalScroll, sc, sc.currentScrollX)
            pcall(sc.SetNormalizedVerticalScroll, sc, sc.currentScrollY)
        end
    end
    Put()
    -- (yours, as if you'd zoomed there: centering on you waits until you move)
    if ns.HoldMapView then ns.HoldMapView(map) end
    -- (on the next frame the game, or fully-out centering on the zone
    -- (MapControls), may have moved it: once more, straight there)
    local id, tx, ty = map:GetMapID(), sc.targetScrollX, sc.targetScrollY
    C_Timer.After(0, function()
        if map:GetMapID() ~= id then return end
        if math.abs(sc:GetCanvasScale() - s) > s * 0.01 or sc.targetScrollX ~= tx or sc.targetScrollY ~= ty then Put() end
    end)
end

-- Up a map, on the same spot: the map above starts a step further out than
-- the view was, so going up feels like zooming out (UP_STEP: about one
-- wheel click)
local UP_STEP = 1.22
local OpenFullyOut, CITY_ZONE  -- (below)
local function Up(map)
    local from = map:GetMapID()
    -- a capital: the zone round it, fully out (Stormwind: Elwynn Forest)
    if CITY_ZONE[from] then OpenFullyOut(map, CITY_ZONE[from]) return true end
    local p = Parent(from)
    if not p then return false end
    local sc = map.ScrollContainer
    local x, y, hw = ViewRect(sc)
    ns.BrowseTo(p)
    local l, r, t, b = RectOn(from, p)
    if x and l then
        PutView(map, l + x * (r - l), t + y * (b - t), hw * (r - l) * UP_STEP)
    end
    return true
end

-- a continent or the world: its zones (continents) open on a click
local function IsOverview(id)
    local info = id and C_Map.GetMapInfo(id)
    return info and T.Continent and info.mapType <= T.Continent or false
end

local function ChildAt(map, nx, ny)
    local id = map:GetMapID()
    if not (IsOverview(id) and nx and C_Map.GetMapInfoAtPosition) then return end
    local ok, info = pcall(C_Map.GetMapInfoAtPosition, id, nx, ny)
    if ok and info and info.mapID ~= id then return info.mapID end
end

-- capitals open as the zone round them (on a continent ZoneArt draws that
-- zone's map over them too; their own maps are close-ups)
CITY_ZONE = { [1453] = 1429, [1455] = 1426, [1458] = 1420,   -- Stormwind, Ironforge, Undercity
                    [1454] = 1411, [1456] = 1412, [1457] = 1438 }  -- Orgrimmar, Thunder Bluff, Darnassus

-- where a map sits on another of the same continent, through the continent
-- (GetMapRectOnMap wants a map above it: a capital's isn't its zone's)
local function RectAny(child, on)
    local l, r, t, b = RectOn(child, on)
    if l then return l, r, t, b end
    local info = MapUtil and MapUtil.GetMapParentInfo and T.Continent
        and MapUtil.GetMapParentInfo(on, T.Continent, true)
    if not (info and info.mapID) then return end
    local cl, cr, ct, cb = RectOn(child, info.mapID)
    local ol, orr, ot, ob = RectOn(on, info.mapID)
    if not (cl and ol) then return end
    local w, h = orr - ol, ob - ot
    return (cl - ol) / w, (cr - ol) / w, (ct - ot) / h, (cb - ot) / h
end

-- On a zone map: the capital at this spot (Stormwind on Elwynn Forest), asked
-- of the continent, which knows the city's outline
local function CityAt(map, nx, ny)
    local id = map:GetMapID()
    local has
    for city, zone in pairs(CITY_ZONE) do
        if zone == id then has = true break end
    end
    if not (has and nx and C_Map.GetMapInfoAtPosition) then return end
    local info = MapUtil and MapUtil.GetMapParentInfo and T.Continent
        and MapUtil.GetMapParentInfo(id, T.Continent, true)
    local cont = info and info.mapID
    local l, r, t, b
    if cont then l, r, t, b = RectOn(id, cont) end
    if not l then return end
    local ok, at = pcall(C_Map.GetMapInfoAtPosition, cont, l + nx * (r - l), t + ny * (b - t))
    if ok and at and CITY_ZONE[at.mapID] == id then return at.mapID end
end

-- The canvas scale a zone's map will have fully zoomed out in this view, as
-- MapControls' zoom steps make it: its art covering the view, and (zoom.fitZone
-- or auto width) the zone itself fitted (ns.ZoneBounds). nil if unknown.
-- (W, H: for a view of that size instead of the map's own)
function ns.ZoneLowestScale(sc, id, W, H)
    local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(id)
    local L = layers and layers[1]
    if not (L and L.layerWidth and L.layerWidth > 0 and L.layerHeight > 0) then return end
    W, H = W or sc:GetWidth(), H or sc:GetHeight()
    local lo = math.max(W / L.layerWidth, H / L.layerHeight)
    -- (not `x and f()`: that keeps only f's first value)
    local l, t, r, b
    if ns.ZoneBounds then l, t, r, b = ns.ZoneBounds(id) end
    if l and r > l and b > t and (ns.db.zoom.fitZone or ns.db.mapFrame.autoWidth) then
        lo = math.max(lo, math.min(W / (r - l), H / (b - t)))
    end
    return lo, L.layerWidth
end

-- The view a map opens on fully zoomed out: its centre (the zone fitted, or
-- the art's middle) and half width, in its own 0..1. nil if unknown.
local function FullyOut(sc, id)
    local lo, aw = ns.ZoneLowestScale(sc, id)
    if not lo then return end
    local zx, zy = 0.5, 0.5
    local l, t, r, b, w, h
    if ns.ZoneBounds then l, t, r, b, w, h = ns.ZoneBounds(id) end
    if l and (ns.db.zoom.fitZone or ns.db.mapFrame.autoWidth) then
        zx, zy = (l + r) / 2 / w, (t + b) / 2 / h
    end
    return zx, zy, sc:GetWidth() / (2 * lo * aw)
end

-- To a map, fully zoomed out on it: a zone or continent you click, a capital,
-- and its zone when you leave one
function OpenFullyOut(map, id)
    ns.BrowseTo(id)
    local x, y, hw = FullyOut(map.ScrollContainer, id)
    if x then PutView(map, x, y, hw) end
end

-- Wheeling in on a continent zooms it toward the cursor (the game's own zoom;
-- ZoneArt draws the zones' own maps on it, sharp). The map switches to the zone
-- in the middle of the view only once that zone's map can show this very view:
-- zoomed in a little past its own furthest zoom (fully out it can only show
-- itself centred: switching then jumped to the zone's middle), with the view
-- inside its art. Until then the continent zooms on. So the switch doesn't move
-- anything: the same view, now the zone's own map. On a zone map the same
-- into its capital (Elwynn Forest into Stormwind); the zone may not zoom that
-- close, so fully zoomed in over the city, the next click in opens it.
local INTO_MARGIN = 1.03  -- past the zone's furthest zoom (MapControls centres the zone within 1%)
local function IntoChild(map, sc, wasMax)
    local x, y, hw, hh = ViewRect(sc)
    if not x then return end
    local child = ChildAt(map, x, y)
    child = child and CITY_ZONE[child] or child
    local city
    if not child then
        child = CityAt(map, x, y)
        city = child ~= nil
    end
    if not child then return end
    local l, r, t, b = RectAny(child, map:GetMapID())
    if not l then return end
    if city then
        if wasMax then OpenFullyOut(map, child) end
        return
    end
    -- the view in the child's own 0..1, and the scale its map would need for it
    local zx, zy = (x - l) / (r - l), (y - t) / (b - t)
    local zhw, zhh = hw / (r - l), hh / (b - t)
    local lo, aw = ns.ZoneLowestScale(sc, child)
    if not lo then return end
    local s = sc:GetWidth() / (2 * zhw * aw)
    if s < lo * INTO_MARGIN then return end  -- not that close yet
    if zx - zhw < 0 or zx + zhw > 1 or zy - zhh < 0 or zy + zhh > 1 then return end  -- (past its art)
    ns.BrowseTo(child)
    PutView(map, zx, zy, zhw)
end

-- The wheel -------------------------------------------------------------------

-- Fully zoomed out, more clicks out push against the map's edge: each one but
-- the last makes the inside of the frame glow (a blink), the last goes up.
local glow, glowEdges = nil, {}
local push, pushAt = 0, 0  -- clicks out past fully zoomed out, and the last one's time
local PUSH_RESET = 1.0     -- seconds without a click: start again
local SETTLE = 0.4         -- seconds after a map change when clicks don't count
local GLOW_FADE = 0.45     -- seconds a blink takes to fade
local atMin = false        -- fully zoomed out before this frame's input
local atMax = false        -- fully zoomed in before it

local function AtMin(sc)
    local levels = sc.zoomLevels
    if not (levels and levels[1]) then return true end
    return (sc.targetScale or sc:GetCanvasScale()) <= levels[1].scale * 1.001
end

-- a blink, stronger the closer to going up
local function Blink(n, need)
    glow.peak = 0.5 + 0.5 * n / math.max(1, need - 1)
    glow.at = GetTime()
    glow:SetAlpha(glow.peak)
    glow:Show()
end

-- Clicks ----------------------------------------------------------------------

-- (the game calls these only for a click, not the end of a drag)
local function OnCanvasClick(map, button, nx, ny, menu)
    if not Cfg().enabled then return false end
    if button == "RightButton" then
        -- (never with a modifier, Controls.lua: Ctrl + right-click is TomTom's waypoint, Waypoints.lua;
        -- on an ink mark: its menu; the quill out (no tool: its catcher's off): the map's menu)
        if IsModifierKeyDown() and not menu then return true end
        if not menu then
            if ns.InkMenuAt and ns.InkMenuAt() then return true end
            if ns.QuestGroundMenuAt and ns.QuestGroundMenuAt() then return true end  -- (a quest's ground: its menu)
            if ns.QuillOut() then
                ns.MapMenu(ns.MapOut, "zoom out")
                return true
            end
        end
        -- zoomed in: all the way out first, with a blink; fully out: up a map
        local sc = map.ScrollContainer
        if sc and not AtMin(sc) and ns.MapZoomOutFully then
            push = 0
            ns.MapZoomOutFully()
            if glow then Blink(1, math.max(2, Cfg().friction or 3)) end
            return true
        end
        if Up(map) then return true end
        -- at the top, out of a dungeon or cave: back into it (not the wheel's)
        if ns.Browsing() and ns.HomeIsArt() then ns.BrowseHome() return true end
        return false
    end
    if button == "LeftButton" then
        local child = ChildAt(map, nx, ny) or CityAt(map, nx, ny)
        -- (fully out and centred: left to the game, the new map kept a view
        -- from the one before and opened off to one side)
        if child then OpenFullyOut(map, child) return true end
    end
    return false
end

-- out a level, as a right-click on empty map (the quill's map menu, Controls.lua)
function ns.MapOut()
    if BattlefieldMapFrame then OnCanvasClick(BattlefieldMapFrame, "RightButton", nil, nil, true) end
end

local function OnWheel(sc, delta, map)
    if not (Cfg().enabled and Cfg().wheel) then return end
    local now = GetTime()
    if delta > 0 then
        push = 0
        -- the big map stays on the continent: a left-click opens a zone
        if not (ns.MapIsBig and ns.MapIsBig()) then IntoChild(map, sc, atMax) end
        return
    end
    if now - changedAt < SETTLE then return end  -- (a fast wheel doesn't run on up)
    if not (atMin and Parent(map:GetMapID())) then return end
    if now - pushAt > PUSH_RESET then push = 0 end
    push, pushAt = push + 1, now
    local need = math.max(1, Cfg().friction or 3)
    -- the big map: out of a zone with no friction, the first click past fully out
    if ns.MapIsBig and ns.MapIsBig() and not IsOverview(map:GetMapID()) then need = 1 end
    if push >= need then
        push = 0
        glow:Hide()
        Up(map)
    else
        Blink(push, need)
    end
end

-- the glow: a soft gold band along each inside edge of the map area
local GLOW_SIZE = 18
local function GlowEdge(point, w, h, orient, fromEdge)
    local t = glow:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetBlendMode("ADD")
    t:SetPoint(point)
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
    -- gold at the edge to nothing inward (minColor: left / bottom)
    local edge, none = { 1, 0.78, 0.25, 0.9 }, { 1, 0.78, 0.25, 0 }
    local a, b = fromEdge and edge or none, fromEdge and none or edge
    if CreateColor and pcall(t.SetGradient, t, orient, CreateColor(unpack(a)), CreateColor(unpack(b))) then
        -- (the current API)
    elseif t.SetGradientAlpha then
        t:SetGradientAlpha(orient, a[1], a[2], a[3], a[4], b[1], b[2], b[3], b[4])
    end
    glowEdges[#glowEdges + 1] = t
    return t
end

local function CreateGlow(map)
    local area = map.ScrollContainer or map
    glow = CreateFrame("Frame", nil, area)
    glow:SetAllPoints(area)
    glow:SetFrameLevel(math.min(area:GetFrameLevel() + 5500, 9500))
    glow:EnableMouse(false)
    local l = GlowEdge("TOPLEFT", GLOW_SIZE, nil, "HORIZONTAL", true)
    l:SetPoint("BOTTOMLEFT")
    local r = GlowEdge("TOPRIGHT", GLOW_SIZE, nil, "HORIZONTAL", false)
    r:SetPoint("BOTTOMRIGHT")
    local tp = GlowEdge("TOPLEFT", nil, GLOW_SIZE, "VERTICAL", false)
    tp:SetPoint("TOPRIGHT")
    local bt = GlowEdge("BOTTOMLEFT", nil, GLOW_SIZE, "VERTICAL", true)
    bt:SetPoint("BOTTOMRIGHT")
    glow:Hide()
    ns.debugFrames.browseGlow = glow
end

-- Setup -----------------------------------------------------------------------

function ns.SetupBrowse(map)
    CreateGlow(map)

    -- the game puts the map back on you (zone change, UI widgets, opening
    -- it): straight back to what you were looking at, in the same frame
    hooksecurefunc(map, "SetMapID", function(self, id)
        if ourSet or not browsed or id == browsed then return end
        Show(self, browsed)
    end)
    -- (a real map change, anyone's: the wheel's overshoot guard)
    if map.OnMapChanged then
        hooksecurefunc(map, "OnMapChanged", function() changedAt = GetTime() end)
    end

    if map.AddCanvasClickHandler then
        map:AddCanvasClickHandler(OnCanvasClick, 10)
    end

    local sc = map.ScrollContainer
    if sc then
        sc:HookScript("OnMouseWheel", function(self, delta)
            ns.Safe("Browse wheel", OnWheel, self, delta, map)
        end)
        -- (the game hands only left and right clicks to the click handlers)
        sc:HookScript("OnMouseUp", function(_, button)
            if button == "MiddleButton" and Cfg().enabled then ns.BrowseHome() end
        end)
    end

    map:HookScript("OnHide", function()
        if glow then glow:Hide() end
        push = 0
        if browsed and Cfg().onReopen then
            browsed = nil  -- (the game shows your map when it opens again)
            Changed()
        end
    end)
    map:HookScript("OnShow", function() C_Timer.After(0, Changed) end)

    local events = CreateFrame("Frame")
    events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_CONTROL_GAINED")
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_CONTROL_GAINED" then
            -- landed (or a stun or fear ended): the zone we flew into, if the flight held the map
            if not (Cfg().taxi and map:IsShown()) or UnitOnTaxi("player") then return end
            if browsed then
                if Cfg().onZone then ns.BrowseHome() end
            else
                local mapID = MapUtil.GetDisplayableMapForPlayer()
                if mapID and mapID ~= map:GetMapID() then map:SetMapID(mapID) end
            end
            return
        end
        if not browsed then return end
        if ns.HoldOnTaxi() then return end
        -- into a dungeon (a loading screen): always back, so its map shows
        if event == "PLAYER_ENTERING_WORLD" then
            if IsInInstance() then ns.BrowseHome() end
        elseif Cfg().onZone then
            ns.BrowseHome()
        end
    end)

    local elapsed = 0
    local ticker = ns.TimedFrame("Browse tick")
    ticker:SetScript("OnUpdate", function(_, dt)
        -- (every frame: the wheel needs to know where the zoom stood before it)
        if sc then
            atMin = AtMin(sc)
            local levels = sc.zoomLevels
            atMax = levels and levels[1] and (sc.targetScale or sc:GetCanvasScale()) >= levels[#levels].scale * 0.999 or false
        end
        if glow:IsShown() then
            local a = glow.peak * (1 - (GetTime() - glow.at) / GLOW_FADE)
            if a <= 0 then glow:Hide() else glow:SetAlpha(a) end
        end
        elapsed = elapsed + dt
        if elapsed < 0.25 then return end
        elapsed = 0
        if not browsed then return end
        if not Cfg().enabled then ns.BrowseHome() return end
        -- you walked onto the map you're looking at: it's yours now (not the
        -- map under a dungeon's or cave's view: that's browsing still)
        if browsed == HomeMap() and not ns.HomeIsArt() then browsed = nil Changed() return end
        if not map:IsVisible() then return end
        local idle = Cfg().idle or 0
        if idle > 0 then
            if map:IsMouseOver()
               or (ns.ZoneHeader and ns.ZoneHeader:IsShown() and ns.ZoneHeader:IsMouseOver()) then
                idleSince = nil
            else
                idleSince = idleSince or GetTime()
                if GetTime() - idleSince >= idle then ns.BrowseHome() end
            end
        end
    end)
end

-- the key binding: up to the continent, or back if you're already browsing
function ns.BrowseKey()
    local map = BattlefieldMapFrame
    if not map then return end
    if browsed then ns.BrowseHome() return end
    if not map:IsShown() then map:Show() end
    local id = map:GetMapID()
    local info = MapUtil and MapUtil.GetMapParentInfo and T.Continent
        and MapUtil.GetMapParentInfo(id, T.Continent, true)
    if info then ns.BrowseTo(info.mapID) else Up(map) end
end
