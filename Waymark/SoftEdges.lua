local _, ns = ...

-- Soft edges: the map fades into the world at the edges of its window (softEdges: on, shape,
-- reach, pins). One mask per art frame, as clear view's cut, but on the window and not the zone:
-- the map slides under it. Media\SoftEdge\<shape><reach>.tga, made by tools\soft_edge_art.py;
-- Fade below follows the same shapes. The border goes while it's active.
-- Not on continents, and not docked over the minimap (the square lines up with it). With clear
-- view's cut on, the cut shapes the map: only once you've zoomed in and the window crops it.
-- A dungeon floor that clear view has cut stays as cut. Pins are frames, and the marks on a
-- floor or in a cave too (chests, doors, bosses): a mask can't reach their text, and pins fade
-- by setting, so their opacity follows the same fade. Layers on a floor go through the mask.

local REACH = { 0.10, 0.17, 0.26 }  -- of the window's height, as the masks are drawn
local PIN_RATE = 0.2                -- s between looks at the pins, when the map has moved
local PIN_ALWAYS = 1                -- s: looked at anyway (pins come and go)
local BIG_PIN = 80                  -- wider than this: a pin that's a whole layer, not a spot

local function Cfg() return ns.db.softEdges end

local active = false
local covered = false   -- the zone map under a dungeon floor or the cave view, put out of sight
local masks = {}        -- [frame] = our mask on it (a mask only masks its own frame's textures)
local masked = {}       -- [texture] = the mask on it
local faded = {}        -- [pin] = true: its opacity is ours for now

function ns.SoftEdgesOn() return active end

local function Reach() return REACH[Cfg().reach or 2] or REACH[2] end

local function Smooth(r, d)
    local t = d / r
    if t <= 0 then return 0 elseif t >= 1 then return 1 end
    return t * t * (3 - 2 * t)
end

-- how much shows at u, v in the window (0 to 1 across, from the top left)
local function Fade(u, v)
    local shape, r = Cfg().shape, Reach()
    local x, y = u * 1.5, v
    if shape == "oval" then
        local a, b = (x - 0.75) / 0.75, (y - 0.5) / 0.5
        return Smooth(r, (1 - math.sqrt(a * a + b * b)) * 0.5)
    elseif shape == "round" then
        local rad = 0.24
        local qx, qy = math.abs(x - 0.75) - (0.75 - rad), math.abs(y - 0.5) - (0.5 - rad)
        local ox, oy = math.max(qx, 0), math.max(qy, 0)
        return Smooth(r, -(math.sqrt(ox * ox + oy * oy) + math.min(math.max(qx, qy), 0) - rad))
    end
    local off = shape == "worn" and -0.4 * r or 0  -- (the worn masks' edge, on the whole)
    return Smooth(r, x + off) * Smooth(r, 1.5 - x + off) * Smooth(r, y + off) * Smooth(r, 1 - y + off)
end

-- how far in from the window's corners things on the map sit, clear of the fade (x, y)
function ns.SoftEdgeInset()
    local map = BattlefieldMapFrame
    if not (active and map) then return 0, 0 end
    local area = map.ScrollContainer or map
    local w, h = area:GetSize()
    local c, r = Cfg(), Reach()
    if c.shape == "oval" then return w * 0.19 + h * r * 0.3, h * 0.19 + h * r * 0.3 end
    if c.shape == "round" then return h * (0.07 + r * 0.5), h * (0.07 + r * 0.5) end
    local i = h * r * (c.shape == "worn" and 0.9 or 0.55)
    return i, i
end

local function Unmask()
    for r, m in pairs(masked) do r:RemoveMaskTexture(m) end
    wipe(masked)
    for _, m in pairs(masks) do m:Hide() end
end

-- a frame's own textures through the window's mask
local function MaskFrame(f, area, file)
    local m = masks[f]
    if not m then
        m = f:CreateMaskTexture()
        m:SetAllPoints(area)
        masks[f] = m
    end
    if m.bfiFile ~= file then
        m:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m.bfiFile = file
    end
    m:Show()
    for _, r in ipairs({ f:GetRegions() }) do
        if r:GetObjectType() == "Texture" and not masked[r] then
            r:AddMaskTexture(m)
            masked[r] = m
        end
    end
end

-- what covers the zone map: a dungeon floor (its canvas, the frame with its black) or the cave
-- view; then what holds the marks on it (two at most)
local function Cover()
    local canvas, bg, marks, _
    if ns.DungeonCutTarget then canvas, _, _, bg, marks = ns.DungeonCutTarget() end
    if canvas then return canvas, bg and bg:GetParent(), canvas, marks end
    local view = ns.caveView
    if view and view:IsShown() then
        local surface = ns.CavePinSurface and ns.CavePinSurface()
        return view, nil, surface and surface:GetParent()
    end
end

-- the layers on a floor: frames the size of the map, and the ones on them
local function MaskLayers(f, area, file, wide, depth)
    for _, child in ipairs({ f:GetChildren() }) do
        if child:GetWidth() >= wide then
            MaskFrame(child, area, file)
            if depth < 4 then MaskLayers(child, area, file, wide, depth + 1) end
        end
    end
end

local function Mask(map)
    local c = Cfg()
    local area = map.ScrollContainer or map
    local file = ns.MEDIA .. "SoftEdge\\" .. (c.shape or "square") .. (c.reach or 2)
    ns.EachMapArtFrame(map, function(f) MaskFrame(f, area, file) end)
    local top, under = Cover()
    if top then
        MaskFrame(top, area, file)
        if under and under ~= top then MaskFrame(under, area, file) end
        MaskLayers(top, area, file, area:GetWidth() * 0.5, 1)
    end
    -- (the zone map would show through the floor's fade)
    local hide = top ~= nil
    if hide ~= covered then
        covered = hide
        map:GetCanvas():SetAlpha(hide and 0 or 1)
    end
end

local function Wanted(map)
    if not Cfg().on or ns.Perf("effects") then return false end
    if ns.Docked and ns.Docked() then return false end
    if ns.CutEditing and ns.CutEditing() then return false end
    if ns.ClearViewFloorCut and ns.ClearViewFloorCut() then return false end
    if Cover() then return true end
    if ns.MapOnContinent and ns.MapOnContinent() then return false end
    if ns.ClearViewZoneCut and ns.ClearViewZoneCut() then return ns.ZoomFraction(map) > 0.01 end
    return true
end

-- Pins ---------------------------------------------------------------------------

local function ReleasePins()
    for pin in pairs(faded) do
        if pin.bfiEdgeBase then pin:SetAlpha(pin.bfiEdgeBase) end
        pin.bfiEdgeBase, pin.bfiEdgeSet = nil, nil
    end
    wipe(faded)
end

local function FadePin(pin, a)
    if a < 0.99 then
        -- (someone else set its opacity since: that's the one to fade from)
        local now = pin:GetAlpha()
        if not faded[pin] or math.abs(now - pin.bfiEdgeSet) > 0.01 then pin.bfiEdgeBase = now end
        pin.bfiEdgeSet = pin.bfiEdgeBase * a
        pin:SetAlpha(pin.bfiEdgeSet)
        faded[pin] = true
    elseif faded[pin] then
        pin:SetAlpha(pin.bfiEdgeBase)
        pin.bfiEdgeBase, pin.bfiEdgeSet = nil, nil
        faded[pin] = nil
    end
end

local function FadeAt(u, v)
    return (u <= 0 or u >= 1 or v <= 0 or v >= 1) and 0 or Fade(u, v)
end

-- the marks on a floor or in a cave, by where they are on screen: small frames, on the layers
local function FadeMarks(f, al, at, aw, ah, depth)
    for _, child in ipairs({ f:GetChildren() }) do
        if child:IsShown() and not child.bfiNoEdgeFade then
            if child:GetWidth() > BIG_PIN then
                if depth < 4 then FadeMarks(child, al, at, aw, ah, depth + 1) end
            else
                local x, y = child:GetCenter()
                if x then
                    local s = child:GetEffectiveScale()
                    FadePin(child, FadeAt((x * s - al) / aw, (at - y * s) / ah))
                end
            end
        end
    end
end

local seenL, seenT, seenS
local function UpdatePins(map, force)
    local holder, holder2, _
    if covered then _, _, holder, holder2 = Cover() end
    if not (active and Cfg().pins) or (covered and not holder) then
        if next(faded) then ReleasePins() end
        return
    end
    local canvas, area = holder or map:GetCanvas(), map.ScrollContainer or map
    local cl, ct = canvas:GetLeft(), canvas:GetTop()
    local al, at = area:GetLeft(), area:GetTop()
    if not (cl and al) then return end
    local cs, as = canvas:GetEffectiveScale(), area:GetEffectiveScale()
    if not force and cl == seenL and ct == seenT and cs == seenS then return end
    seenL, seenT, seenS = cl, ct, cs
    local cw, ch = canvas:GetSize()
    local aw, ah = area:GetSize()
    cl, ct, cw, ch = cl * cs, ct * cs, cw * cs, ch * cs
    al, at, aw, ah = al * as, at * as, aw * as, ah * as
    if holder then
        FadeMarks(holder, al, at, aw, ah, 1)
        if holder2 then FadeMarks(holder2, al, at, aw, ah, 1) end
        return
    end
    ns.EachPin(map, function(pin, template)
        local nx, ny = pin.normalizedX, pin.normalizedY
        if not nx or template == "MapExplorationPinTemplate" or not pin:IsShown() or pin:GetWidth() > BIG_PIN then return end
        local u, v = (cl + nx * cw - al) / aw, (at - (ct - ny * ch)) / ah
        FadePin(pin, FadeAt(u, v))
    end)
end

-- Applying -------------------------------------------------------------------------

-- what sits on the map keeps clear of the fade
local function MoveExtras()
    if ns.UpdateCoords then ns.UpdateCoords() end
    if ns.UpdateClock then ns.UpdateClock() end
    if ns.LayoutToggles then ns.LayoutToggles() end
end

local function Refresh(map)
    local want = Wanted(map)
    if want ~= active then
        active = want
        if not want then
            Unmask()
            if covered then
                covered = false
                if not (ns.ClearViewFloorCut and ns.ClearViewFloorCut()) then map:GetCanvas():SetAlpha(1) end
            end
        end
        if ns.UpdateStyle then ns.UpdateStyle() end  -- (the border)
        MoveExtras()
    end
    if want then Mask(map) end
    UpdatePins(map, true)
end

-- softEdges changed (or a setup was loaded)
function ns.UpdateSoftEdges()
    local map = BattlefieldMapFrame
    if not map then return end
    ns.Safe("SoftEdges", Refresh, map)
    if active then MoveExtras() end
end

function ns.SetupSoftEdges(map)
    local sinceLook, sincePins, sinceAll = 0, 0, 0
    local ticker = ns.TimedFrame("SoftEdges tick")
    ticker:SetScript("OnUpdate", function(_, dt)
        if not (Cfg().on or active) or not map:IsShown() then return end
        sinceLook, sincePins, sinceAll = sinceLook + dt, sincePins + dt, sinceAll + dt
        -- (the game swaps tiles as you zoom, move and change maps)
        if sinceLook >= 0.5 then
            sinceLook = 0
            ns.Safe("SoftEdges", Refresh, map)
            sinceAll, sincePins = 0, 0
        elseif sincePins >= PIN_RATE then
            sincePins = 0
            local all = sinceAll >= PIN_ALWAYS
            if all then sinceAll = 0 end
            ns.Safe("SoftEdges pins", UpdatePins, map, all)
        end
    end)
    -- (that sets every pin's opacity, once a second: faded again at once, or they blink)
    hooksecurefunc(ns, "ApplyGroups", function()
        if active then ns.Safe("SoftEdges pins", UpdatePins, map, true) end
    end)
    map:HookScript("OnShow", ns.UpdateSoftEdges)
    if map.OnMapChanged then
        hooksecurefunc(map, "OnMapChanged", function() C_Timer.After(0, ns.UpdateSoftEdges) end)
    end
    local area = map.ScrollContainer or map
    area:HookScript("OnSizeChanged", function() if active then MoveExtras() end end)
    ns.UpdateSoftEdges()
end
