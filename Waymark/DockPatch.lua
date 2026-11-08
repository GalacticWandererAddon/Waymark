local _, ns = ...

-- The patch of live blips (Forever): docked, on the map side, wheeled out past the minimap's
-- farthest zoom. The map is detailed out there and it's confusing if the blips simply stop, so the
-- real minimap, its land off, shrinks to the map's scale and lies over the map on you: blips for
-- the 233 yards it can see, and nothing past that. The whole map goes under it, to BACKGROUND, and
-- its frame's parts are put back: raising the minimap doesn't work (blips stayed behind even at
-- TOOLTIP), and lowering the scroll area or all that's in it doesn't either (live).
-- The dock measures its square from the minimap, so it's told to hold the square still first
-- (ns.DockHoldSquare). It works in a fight too: the minimap can be sized in combat with no block (live).

local RATE = 0.1
local MIN_R, MAX_R = 0.12, 1.02   -- the map's scale against the minimap's: past these, no patch

local held   -- how the minimap was
local under = false  -- inside the friction: the map itself lies under the minimap, its land off
local ArtWanted
local since = 0
local drawsYou = false

-- the minimap's own arrow is showing over the map: ours would be a second one (BattlefieldInfo.lua)
function ns.MinimapDrawsYou() return drawsYou end
local function DrawsYou(on)
    if on == drawsYou then return end
    drawsYou = on
    if ns.ApplyGroups then ns.ApplyGroups() end
end

local function Can()
    return C_Minimap and C_Minimap.SetDrawGroundTextures and ns.DockHoldSquare and ns.DockMinimapScale
end

-- The map's scale against the minimap's, and the minimap zoom it's measured at: the widest that
-- still reaches the map's scale, so the patch is as big as it can be and never bigger than the
-- square. Always from its farthest zoom, the map dragged open at a closer one had no patch at all.
local function Ratio(map)
    local sc = map.ScrollContainer
    if not sc then return nil end
    local s = sc:GetCanvasScale()
    local levels = Minimap.GetZoomLevels and Minimap:GetZoomLevels() or 1
    local r, zoom
    for z = 0, levels - 1 do
        local sz = ns.DockMinimapScale(sc, z)
        if not sz or sz <= 0 then return nil end
        r, zoom = s / sz, z
        if r <= 1.001 then break end
    end
    return r, zoom
end

local function PlayerPos(map)
    local id = map:GetMapID()
    local pos = id and C_Map.GetPlayerMapPosition(id, "player")
    if pos and pos.x then return pos end
end

-- nil when wanted, else why not (/bfi check says)
local function WhyNot(map)
    if not Can() then return "client can't" end
    if not (map and map:IsVisible()) then return "map not visible" end
    if not (ns.Docked and ns.Docked()) then return "not docked" end
    if not ns.db.dock.ourGround then return "switched off" end
    if ns.DockMinimapFace() then return "on the minimap side" end
    if ns.DockSquareMoving and ns.DockSquareMoving() then return "moving" end
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then return "Edit Mode" end
    if ns.db.dock.big then return "big map" end
    if IsInInstance() or IsIndoors() or (ns.InCave and ns.InCave()) then return "indoors" end
    if ns.Browsing and ns.Browsing() then return "browsing" end
    if not PlayerPos(map) then return "no position" end
    local r = Ratio(map)
    if not r then return "no scale" end
    if r < MIN_R or r > MAX_R then return ("scale %.2f out of bounds"):format(r) end
end

local function Wanted(map) return WhyNot(map) == nil end

function ns.DockPatchInfo()
    local map = BattlefieldMapFrame
    local mm = Minimap
    local r = map and map.ScrollContainer and Can() and Ratio(map)
    return ("%s; ratio %s; minimap %s/%d alpha %.2f size %.0f at %.0f,%.0f, map %s/%d"):format(
        held and "on" or ("off: " .. tostring(WhyNot(map))), r and ("%.2f"):format(r) or "none",
        mm:GetFrameStrata(), mm:GetFrameLevel(), mm:GetEffectiveAlpha(), mm:GetWidth(), mm:GetLeft() or 0, mm:GetBottom() or 0,
        map and map:GetFrameStrata() or "?", map and map:GetFrameLevel() or 0)
end

local function Land(on)
    C_Minimap.SetDrawGroundTextures(on)
    if C_Minimap.SetIgnoreRotateMinimap then C_Minimap.SetIgnoreRotateMinimap(not on) end
end

-- What's on the minimap takes the mouse too: its zoom area, and GatherMate's and Questie's pins, which
-- come and go as you move, so this runs all the time. A click here is for the map's pins.
local muted = {}
local function Off(f)
    if f.IsMouseEnabled and f:IsMouseEnabled() then
        muted[#muted + 1] = f
        f:EnableMouse(false)
    end
end
local function Unmute()
    for _, f in ipairs(muted) do f:EnableMouse(true) end
    wipe(muted)
end
local function Quiet(keepWheel, keepMouse)
    -- (every time: the dock's drag and the rest give the minimap its mouse back, and it then pings
    -- on a click and takes the map's drag and the pins' hover)
    if not keepMouse then Minimap:EnableMouse(false) end
    if Minimap.EnableMouseWheel and not keepWheel then Minimap:EnableMouseWheel(false) end
    for _, c in ipairs({ Minimap:GetChildren() }) do Off(c) end
    -- (and what the minimap sits in: Edit Mode's box stays where the minimap was, over the map,
    -- and took the clicks there)
    local f = Minimap:GetParent()
    while f and f ~= UIParent do
        Off(f)
        for _, c in ipairs({ f:GetChildren() }) do
            if c ~= Minimap then Off(c) end
        end
        f = f:GetParent()
    end
end

-- (the game's mouse-up, kept once: the dock's drag lifts it and puts it back too, so what's there
-- when the patch starts may be nothing)
local pressX, pressY, gameUp
Minimap:HookScript("OnMouseDown", function() pressX, pressY = GetCursorPosition() end)
local function PingOnClick(self, button)
    local x, y = GetCursorPosition()
    if gameUp and pressX and math.abs(x - pressX) + math.abs(y - pressY) < 6 then gameUp(self, button) end
end
local function OurUp()
    local up = Minimap:GetScript("OnMouseUp")
    if up == PingOnClick then return end
    gameUp = up or gameUp
    Minimap:SetScript("OnMouseUp", PingOnClick)
end

-- (this one call is blocked in a fight, on live: put off till after it. Until then, no blip names)
local propagating = false
local function Propagate(on)
    if on == propagating or not Minimap.SetPropagateMouseClicks or InCombatLockdown() then return end
    Minimap:SetPropagateMouseClicks(on)
    propagating = on
end

local function On(map)
    local mm = Minimap
    held = { w = mm:GetWidth(), h = mm:GetHeight(),
             mouse = mm:IsMouseEnabled(), wheel = mm.IsMouseWheelEnabled and mm:IsMouseWheelEnabled(), points = {} }
    for i = 1, mm:GetNumPoints() do held.points[i] = { mm:GetPoint(i) } end
    ns.DockHoldSquare(true)
    if ns.DockPatchMask then ns.DockPatchMask(true) end  -- (the docked shape: the patch itself is never cut)
    ns.DockMapUnder(true)
    mm:EnableMouse(false)
    if mm.EnableMouseWheel then mm:EnableMouseWheel(false) end
    Quiet()
    -- (for the blips' names: hovering reaches the minimap, a click goes on through to the map. Its
    -- own mouse-up pings: kept for a real click, not for the end of a drag)
    if mm.SetPropagateMouseClicks then
        Propagate(true)
        OurUp()
    end
    Land(false)
end

-- also called by the dock, before it places or sizes the minimap, or turns to its minimap side
function ns.DockPatchOff()
    if not held then return end
    local mm, h = Minimap, held
    held = nil
    if mm.SetPropagateMouseClicks then
        Propagate(false)
        mm:SetScript("OnMouseUp", gameUp)
    end
    mm:ClearAllPoints()
    for _, p in ipairs(h.points) do mm:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
    -- (the game keeps drawing the picture at the patch's small size until a zoom change: the big map
    -- opened from the patch left a small minimap in the square's corner, the user 2026-11-08)
    local resized = math.abs(mm:GetWidth() - h.w) > 0.5
    mm:SetSize(h.w, h.h)
    if resized and ns.DockRedraw then ns.DockRedraw() end
    if ns.DockPatchMask then ns.DockPatchMask(false) end
    mm:Show()
    -- (going to the minimap side, the map stays under and the land off: put back and redone a moment
    -- later, the real minimap flashed up between)
    local keep = ArtWanted(BattlefieldMapFrame)
    if keep then under = true else ns.DockMapUnder(false) end
    mm:EnableMouse(h.mouse and true or false)
    Unmute()
    if mm.EnableMouseWheel then mm:EnableMouseWheel(h.wheel and true or false) end
    if mm.SetIconScale then mm:SetIconScale(1) end
    ns.DockHoldSquare(false)
    if not keep then
        Land(true)
        DrawsYou(false)
    end
    if ns.MinimapGroundSync then ns.MinimapGroundSync() end
end

-- Inside the friction the minimap stays where it is and the dock already keeps the map on you at its
-- zoom, so the map only has to go under it: your detailed art under the blips, at every zoom.
-- Not in caves and the like: the map has no tunnels, the game's land comes back.
function ns.DockOurArt() return under end

ArtWanted = function(map)
    if not (Can() and map and map:IsVisible() and ns.Docked and ns.Docked() and ns.db.dock.ourGround) then return false end
    if not ns.DockMinimapFace() or IsInInstance() or IsIndoors() or (ns.InCave and ns.InCave()) then return false end
    return PlayerPos(map) ~= nil
end

local function ArtUnder(on)
    if on == under then return end
    under = on
    ns.DockMapUnder(on)
    Land(not on)
    if not on then
        Unmute()
        Minimap:EnableMouse(true)
    end
    ns.DockRefreshFace()
end

-- Inside the friction the pins lie under the minimap: it stands aside while the mouse is on one, with
-- all that's on it and round it (/fstack: its children and cluster took the hover otherwise), and
-- keeps its mouse the rest of the time, for the blips' names and its wheel and drag.
local OUR_BUTTONS = { "toggleStrip", "gear", "townButton", "cityButton", "dockButton", "bigMap", "close", "header" }
local function PinUnderMouse(map)
    if not Minimap:IsMouseOver() then return false end
    if ns.QuestGroundUnderMouse and ns.QuestGroundUnderMouse() then return true end   -- (ground counts as a pin)
    -- (the map's buttons too: /run GetMouseFoci named a child of the minimap over them)
    for _, key in ipairs(OUR_BUTTONS) do
        local f = ns.debugFrames[key]
        if f and f:IsVisible() and f:IsMouseOver() then return true end
    end
    local found = false
    ns.EachPin(map, function(pin, template)
        if not found and template ~= "GroupMembersPinTemplate" and (pin.bfiGroup or (template and template:find("^BFI")))
           and pin:IsVisible() and pin:IsMouseOver() then
            found = true
        end
    end)
    return found
end

-- Dragged away at one of the minimap's own zooms and back on you: that's the minimap side in all but
-- name, so go there, for the blips' names. Only after a drag: wheeling out past the friction
-- starts the same way, on you at the same scale, and has to stay out.
local dragged
local function BackOnYou(map)
    local r, zoom = Ratio(map)
    local pos, sc = PlayerPos(map), map.ScrollContainer
    if not (r and pos and r > 0.99 and r < 1.01) then
        dragged = nil
        return
    end
    local off = math.max(math.abs((sc.currentScrollX or pos.x) - pos.x), math.abs((sc.currentScrollY or pos.y) - pos.y))
    if off > 0.01 then
        dragged = true
    elseif dragged and off < 0.001 and not IsMouseButtonDown("LeftButton") then
        dragged = nil
        ns.DockShowMinimap(zoom)
    end
end

local function Place(map)
    local r, zoom = Ratio(map)
    local pos = PlayerPos(map)
    local canvas = map.ScrollContainer.Child
    local square = ns.DockSquareBox()
    if not (r and pos and canvas and canvas:GetLeft() and square) then return end
    local mm = Minimap
    if mm:GetZoom() ~= zoom then mm:SetZoom(zoom) end
    local m, c = mm:GetEffectiveScale(), canvas:GetEffectiveScale()
    -- (the minimap's whole side: a tall docked shape's box is narrower)
    local fw = ns.DockShapeFracs and ns.DockShapeFracs() or 1
    local side = square:GetWidth() / fw * square:GetEffectiveScale() * r / m
    local x = (canvas:GetLeft() + pos.x * canvas:GetWidth()) * c / m
    local y = (canvas:GetBottom() + (1 - pos.y) * canvas:GetHeight()) * c / m
    mm:SetSize(side, side)
    mm:ClearAllPoints()
    mm:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    -- (it can't be clipped: dragged off, or by a zone's edge, blips would float out over the world)
    local q = square:GetEffectiveScale() / m
    -- (blips only reach about half way to the minimap's edge, 122 of its 233 yards on Era, so its outer
    -- part is empty and can hang over)
    local half, slack = side / 2, side * 0.22
    local fits = x - half >= square:GetLeft() * q - slack and x + half <= square:GetRight() * q + slack
        and y - half >= square:GetBottom() * q - slack and y + half <= square:GetTop() * q + slack
    -- (hidden, not faded: the blips don't take the minimap's alpha, live)
    if mm:IsShown() ~= fits then mm:SetShown(fits) end
    DrawsYou(fits)
    if mm.SetIconScale then mm:SetIconScale(math.max(0.85, math.sqrt(r))) end   -- (0.6 was tiny at mid zoom)
end

local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, elapsed)
    if not ns.db or not (ns.db.dock.on or under or held) then return end
    local map = BattlefieldMapFrame
    since = since + elapsed
    if since >= RATE then
        since = 0
        Propagate(held and true or false)  -- (what a fight put off)
        ArtUnder(ArtWanted(map) and true or false)
        if under then
            Land(false)
            DrawsYou(true)
            if PinUnderMouse(map) then
                Quiet(true)
            else
                Unmute()
                Minimap:EnableMouse(true)
            end
        elseif not held then
            DrawsYou(false)
        end
        if Wanted(map) then
            if not held then On(map) end
            Land(false)  -- (the game turns its land back on leaving a hybrid area)
            -- (the minimap's mouse on over open map, for the blips' names; off over a pin)
            local names = propagating and Minimap:IsShown() and Minimap:IsMouseOver()
                and not PinUnderMouse(map)
            Quiet(false, names)
            if Minimap.SetPropagateMouseClicks then OurUp() end
            Minimap:EnableMouse(names and true or false)
            BackOnYou(map)
        elseif held then
            ns.DockPatchOff()
        end
    end
    if held then Place(map) end
end)
