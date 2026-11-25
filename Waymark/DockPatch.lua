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
local HOLD = 0.03   -- of the minimap's side: room to spare before a wider zoom is taken back (no flicker)
local STRATA_N = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

local held   -- how the minimap was
local under = false  -- inside the friction: the map itself lies under the minimap, its land off
local ArtWanted
local since = 0
local drawsYou = false
-- the patch as placed, for /waymark check and to see whether someone else moved it since:
-- ask = { x, y, side } (minimap units, last frame), strikes = frames in a row it had moved,
-- zoom / widest, why and whyAt (the last time it hid, and why)
local fit = { strikes = 0 }
local Beneath   -- (below, with Place)

-- (a minimap made protected, by another addon's secure button on it, can't be moved or have its mouse
-- switched in a fight: those calls wait till it ends)
local function Locked(f)
    return InCombatLockdown() and f.IsProtected and f:IsProtected() and true or false
end
local function Mouse(f, on)
    if not Locked(f) then f:EnableMouse(on and true or false) end
end
local function Wheel(f, on)
    if f.EnableMouseWheel and not Locked(f) then f:EnableMouseWheel(on and true or false) end
end

-- the minimap's own arrow is showing over the map: ours would be a second one (BattlefieldInfo.lua)
function ns.MinimapDrawsYou() return drawsYou end
-- Only when the minimap can really be seen. A UI addon that hides the minimap or its cluster, or fades it
-- out, left no arrow at all: ours was put away for one that was not there (two players, 11 and 19 Nov).
local function MinimapSeen()
    return Minimap:IsVisible() and Minimap:GetEffectiveAlpha() > 0.05
end
local function DrawsYou(on)
    on = on and MinimapSeen() or false
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
    if not held and Locked(Minimap) then return "minimap protected, in a fight" end
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
    local m = mm:GetEffectiveScale()
    local cx, cy = mm:GetCenter()
    local a = fit.ask
    return ("%s; under %s; minimap draws you %s, seen %s, parent %s; ratio %s; minimap %s/%d alpha %.2f size %.0f at %.0f,%.0f, map %s/%d; "
        .. "fit: zoom %s (widest %s), room %.2f of its side; asked %s, got %s; moved %d frames in a row; minimap %s; "
        .. "last hidden: %s"):format(
        held and "on" or ("off: " .. tostring(WhyNot(map))), tostring(under), tostring(drawsYou), tostring(MinimapSeen()),
        tostring(mm:GetParent() and mm:GetParent():GetName()), r and ("%.2f"):format(r) or "none",
        mm:GetFrameStrata(), mm:GetFrameLevel(), mm:GetEffectiveAlpha(), mm:GetWidth(), mm:GetLeft() or 0, mm:GetBottom() or 0,
        map and map:GetFrameStrata() or "?", map and map:GetFrameLevel() or 0,
        fit.zoom == math.huge and "none" or tostring(fit.zoom), tostring(fit.widest), fit.room or 0,
        a and ("%.1f,%.1f side %.1f px"):format(a[1] * m, a[2] * m, a[3] * m) or "nothing",
        cx and ("%.1f,%.1f side %.1f px"):format(cx * m, cy * m, mm:GetWidth() * m) or "nowhere",
        fit.strikes or 0, not held and "not compared, the patch off"
            or (map and map.ScrollContainer and Beneath(map)) and "beneath our map" or "above our map",
        fit.why and ("%s, %.0f s ago"):format(fit.why, GetTime() - (fit.whyAt or 0)) or "never")
end

local function Land(on)
    C_Minimap.SetDrawGroundTextures(on)
    if C_Minimap.SetIgnoreRotateMinimap then C_Minimap.SetIgnoreRotateMinimap(not on) end
end

-- What's on the minimap takes the mouse too: its zoom area, and GatherMate's and Questie's pins, which
-- come and go as you move, so this runs all the time. A click here is for the map's pins.
local muted = {}
local function Off(f)
    if f.IsMouseEnabled and f:IsMouseEnabled() and not Locked(f) then
        muted[#muted + 1] = f
        f:EnableMouse(false)
    end
end
local function Unmute()
    local later   -- (protected ones in a fight: after it)
    for _, f in ipairs(muted) do
        if Locked(f) then
            later = later or {}
            later[#later + 1] = f
        else
            f:EnableMouse(true)
        end
    end
    wipe(muted)
    if later then for i, f in ipairs(later) do muted[i] = f end end
end
local function Quiet(keepWheel, keepMouse)
    -- (every time: the dock's drag and the rest give the minimap its mouse back, and it then pings
    -- on a click and takes the map's drag and the pins' hover)
    if not keepMouse then Mouse(Minimap, false) end
    if not keepWheel then Wheel(Minimap, false) end
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
    if up == PingOnClick or Locked(Minimap) then return end
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
    -- (icon: the blips' size as the player or another addon had it, put back after: it was always 1)
    held = { w = mm:GetWidth(), h = mm:GetHeight(), icon = mm.GetIconScale and mm:GetIconScale() or nil, zoom = mm:GetZoom(),
             mouse = mm:IsMouseEnabled(), wheel = mm.IsMouseWheelEnabled and mm:IsMouseWheelEnabled(), points = {} }
    for i = 1, mm:GetNumPoints() do held.points[i] = { mm:GetPoint(i) } end
    fit.ask, fit.zoom, fit.strikes, fit.changedAt, fit.groupAt = nil, nil, 0, nil, nil
    ns.DockHoldSquare(true)
    if ns.DockPatchMask then ns.DockPatchMask(true) end  -- (the docked shape: the patch is never cut, it fits inside)
    ns.DockMapUnder(true)
    Mouse(mm, false)
    Wheel(mm, false)
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
    if Locked(Minimap) then return end   -- (in a fight with a protected minimap: the ticker tries again after it)
    local mm, h = Minimap, held
    held = nil
    if mm.SetPropagateMouseClicks then
        Propagate(false)
        mm:SetScript("OnMouseUp", gameUp)
    end
    ns.dockOwnMove = true   -- (Dock.lua notes who else moves the minimap: not us)
    mm:ClearAllPoints()
    for _, p in ipairs(h.points) do mm:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
    -- (the game keeps drawing the picture at the patch's small size until a zoom change: the big map
    -- opened from the patch left a small minimap in the square's corner, the user 2026-11-08)
    -- (size, then the docked shape's mask, then the redraw, as the dock does when it squares the minimap.
    -- With the mask set after the redraw, a tall shape's picture stayed at the patch's size, a few
    -- percent small and off to one side in its frame beside the big map, the user 2026-11-14)
    local resized = math.abs(mm:GetWidth() - h.w) > 0.5
    mm:SetSize(h.w, h.h)
    ns.dockOwnMove = nil
    -- (its zoom as it was too: the fit picks closer ones, and the minimap stayed there beside the big map and
    -- after undocking. Before the redraw, which goes back to the zoom it finds)
    if h.zoom and mm:GetZoom() ~= h.zoom then mm:SetZoom(h.zoom) end
    if ns.DockPatchMask then ns.DockPatchMask(false) end
    if resized and ns.DockRedraw then ns.DockRedraw() end
    mm:Show()
    -- (going to the minimap side, the map stays under and the land off: put back and redone a moment
    -- later, the real minimap flashed up between)
    local keep = ArtWanted(BattlefieldMapFrame)
    if keep then under = true else ns.DockMapUnder(false) end
    Mouse(mm, h.mouse)
    Unmute()
    Wheel(mm, h.wheel)
    if mm.SetIconScale then mm:SetIconScale(h.icon or 1) end
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
        Mouse(Minimap, true)
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

-- the minimap drawn under the map's lowered picture, its blips and arrow covered (only read: never moved)
Beneath = function(map)
    local sc = map.ScrollContainer
    local m, s = STRATA_N[Minimap:GetFrameStrata()] or 1, STRATA_N[sc:GetFrameStrata()] or 1
    if m ~= s then return m < s end
    -- (select: "a and f()" keeps only f's first value, the critic's find)
    local top = ns.CanvasLevels and select(2, ns.CanvasLevels(map))
    return Minimap:GetFrameLevel() <= (top or sc:GetFrameLevel())
end

-- (hidden, not faded: the blips don't take the minimap's alpha, live)
local function Hide(why)
    if Minimap:IsShown() then Minimap:Hide() end
    if fit.why ~= why then fit.why, fit.whyAt = why, GetTime() end
    DrawsYou(false)
end

-- In a group, a member inside the square but past a patch smaller than the widest: the minimap draws group
-- members only within its own reach and our dots stand aside for it, so nothing would draw them. Before the
-- fit, the patch was simply hidden there and our dots showed everyone (the critic, 2026-11-25). Looked at five
-- times a second, not every frame.
local function GroupPastPatch(map, x, y, half, square, q, c, m)
    local now = GetTime()
    if fit.groupAt and now - fit.groupAt < 0.2 and fit.groupHalf == half then return fit.groupOut end
    fit.groupAt, fit.groupHalf, fit.groupOut = now, half, false
    if not (IsInGroup and IsInGroup()) then return false end
    local id = map:GetMapID()
    local canvas = map.ScrollContainer.Child
    local raid = IsInRaid and IsInRaid()
    local l, r, b, t = square:GetLeft() * q, square:GetRight() * q, square:GetBottom() * q, square:GetTop() * q
    for i = 1, raid and GetNumGroupMembers() or GetNumSubgroupMembers() do
        local unit = (raid and "raid" or "party") .. i
        if not UnitIsUnit(unit, "player") then
            local p = id and C_Map.GetPlayerMapPosition(id, unit)
            local px, py = p and ns.Known(p.x), p and ns.Known(p.y)
            if px and py then
                local ux = (canvas:GetLeft() + px * canvas:GetWidth()) * c / m
                local uy = (canvas:GetBottom() + (1 - py) * canvas:GetHeight()) * c / m
                if ux >= l and ux <= r and uy >= b and uy <= t and (math.abs(ux - x) > half or math.abs(uy - y) > half) then
                    fit.groupOut = true
                    return true
                end
            end
        end
    end
    return false
end

-- The patch round you, at the map's scale: the widest of the minimap's zooms that fits inside the square.
-- Centred on you it was the widest or nothing, so near a zone's edge (the view stops following there) or with a
-- wide or tall shape every blip went (the docked pass, 2026-11-24): a smaller patch now, the blips near you
-- kept, hidden only when none fits. It may reach SLACK past the picture, under the frame's border, and no
-- further: past the square its blips drew over the border and the world beside it. A wider zoom is taken back
-- only with HOLD to spare and WAIT after the last change (no flicker at the line; the followed view lags you a
-- yard or two).
local SLACK, WAIT = 0.02, 0.4
local function Place(map)
    local r0, widest = Ratio(map)
    local pos = PlayerPos(map)
    local sc = map.ScrollContainer
    local canvas = sc.Child
    local square = ns.DockSquareBox()
    if not (r0 and pos and canvas and canvas:GetLeft() and square and square:GetLeft()) then return end
    local mm = Minimap
    if Locked(mm) then return end   -- (protected, in a fight: it stays as it is till the fight ends)
    local m, c = mm:GetEffectiveScale(), canvas:GetEffectiveScale()
    -- someone else moved or sized it since the last frame (twice in a row: it isn't where its blips belong,
    -- and hidden below, our arrow stays: "my arrow marker doesn't appear", a player, 11 Nov)
    local a = fit.ask
    if a then
        local cx, cy = mm:GetCenter()
        local tol = 2 / m
        local off = not cx or math.abs(cx - a[1]) > tol or math.abs(cy - a[2]) > tol or math.abs(mm:GetWidth() - a[3]) > tol
        fit.strikes = off and fit.strikes + 1 or 0
    end
    -- (the minimap's whole side: a tall docked shape's box is narrower)
    local fw = ns.DockShapeFracs and ns.DockShapeFracs() or 1
    local full = square:GetWidth() / fw * square:GetEffectiveScale() / m
    local x = (canvas:GetLeft() + pos.x * canvas:GetWidth()) * c / m
    local y = (canvas:GetBottom() + (1 - pos.y) * canvas:GetHeight()) * c / m
    local q = square:GetEffectiveScale() / m
    -- (from you to the square's nearest edge, minimap units, and the overhang let under the border)
    local room = math.min(x - square:GetLeft() * q, square:GetRight() * q - x, y - square:GetBottom() * q, square:GetTop() * q - y)
    fit.widest, fit.room = widest, full > 0 and room / full or 0
    room = room + full * SLACK
    local now = GetTime()
    local wider = now - (fit.changedAt or 0) >= WAIT   -- (a wider zoom than now: only after WAIT)
    local s = sc:GetCanvasScale()
    local zoom, side, r
    for z = widest, (mm.GetZoomLevels and mm:GetZoomLevels() or 1) - 1 do
        local sz = ns.DockMinimapScale(sc, z)
        local rz = sz and sz > 0 and s / sz
        if not rz or rz < MIN_R then break end
        local up = fit.zoom and z < fit.zoom
        if (not up or wider) and full * rz / 2 + (up and full * HOLD or 0) <= room then
            zoom, side, r = z, full * rz, rz
            break
        end
    end
    -- (in a group, a smaller patch only while nobody is left between it and the square's edge)
    local why
    if zoom and zoom ~= widest and GroupPastPatch(map, x, y, side / 2, square, q, c, m) then
        zoom, why = nil, "your group past a smaller patch"
    end
    local was = fit.zoom
    if not zoom then
        if was ~= math.huge then fit.changedAt = now end
        fit.zoom = math.huge   -- (back only with room to spare)
        return Hide(why or "no room round you")
    end
    if was ~= zoom then fit.changedAt = now end
    fit.zoom = zoom
    if mm:GetZoom() ~= zoom then mm:SetZoom(zoom) end
    ns.dockOwnMove = true   -- (Dock.lua notes who else moves the minimap: not us, every frame)
    mm:SetSize(side, side)
    mm:ClearAllPoints()
    mm:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    ns.dockOwnMove = nil
    fit.ask = fit.ask or {}
    fit.ask[1], fit.ask[2], fit.ask[3] = x, y, side
    if mm.SetIconScale then mm:SetIconScale(math.max(0.85, math.sqrt(r))) end   -- (0.6 was tiny at mid zoom)
    if fit.strikes >= 2 then return Hide("moved by " .. (ns.DockLastMover and ns.DockLastMover() or "another addon")) end
    if Beneath(map) then return Hide("beneath our map") end
    if not mm:IsShown() then mm:Show() end
    DrawsYou(true)
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
                Mouse(Minimap, true)
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
            Mouse(Minimap, names)
            BackOnYou(map)
        elseif held then
            ns.DockPatchOff()
        end
    end
    if held then Place(map) end
end)
