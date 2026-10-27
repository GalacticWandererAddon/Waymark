local _, ns = ...

-- Clear view: just the map, laid over the world. While clearView.on:
--   noFrame   the border goes (ns.MapBorderStyle says "none")
--   header    the zone name "shown", "hover" (with the mouse on the map) or "hidden"
--   buttons   "hover": the buttons, coordinates and resize grip show only with
--             the mouse on the map; "shown": as usual
--   opacity   the map picture's own opacity (MapControls ApplyOpacity uses it
--             in place of mapFrame.opacity); pins keep their layers' opacity
--   zoneOnly  on a zone's map, the neighbouring zones and the sea are cut away:
--             the map art (the game's tiles, the explored areas, our close-up
--             detail and fog) through the zone's tight outline (Media\ZoneCut\
--             <edition>\<id>.tga, over its map's canvas; listed in Data\ZoneCut.lua,
--             made by tools\zone_cut.py from the zone's own area art). A zone with
--             no outline for this client isn't cut
-- By key (BFI_CLEARVIEW) or the check box on the Map frame page; kept over a
-- reload and in saved setups.

local FADE_RATE = 5   -- alpha per second

local function Cfg() return ns.db.clearView end

function ns.ClearView() return ns.db and Cfg().on and true or false end

-- the map frame's style while clear view hides it
function ns.ClearViewHidesFrame() return ns.ClearView() and Cfg().noFrame end

local hover = 1   -- the buttons' (and a hover header's) opacity, gliding

-- the buttons' opacity from clear view (1 when it doesn't hide them)
function ns.ClearViewButtonAlpha() return hover end

function ns.ClearViewHeaderAlpha()
    if not ns.ClearView() then return 1 end
    local h = Cfg().header
    if h == "hidden" then return 0 end
    if h == "hover" then return hover end
    return 1
end

-- Only the zone ------------------------------------------------------------------

local masks = {}    -- [frame] = our mask on it (a mask only masks its own frame's textures)
local masked = {}   -- [texture] = the mask on it
ns.clearViewCut = nil  -- (what's done, for /bfi check)

-- the zone's outline file; false: a zone without one; nil: not a zone's map
local CUTS = "Interface\\AddOns\\BattlefieldInfo\\Media\\ZoneCut\\"
local function ZoneShape(id)
    local info = id and C_Map.GetMapInfo(id)
    if not (info and Enum.UIMapType and info.mapType == Enum.UIMapType.Zone) then return nil end
    local edition = ns.FOREVER and "Forever" or "Era"
    local list = ns.ZoneCut and ns.ZoneCut[edition]
    return list and list[id] and (CUTS .. edition .. "\\" .. id) or false
end

-- the map art's frames: the game's detail layers, the explored-area pieces, and
-- ours (Detail's close-up, Explore's fog: bfiOwn); each with its child frames. Not pins.
local function EachArtFrame(map, fn)
    for _, layer in ipairs({ map:GetCanvas():GetChildren() }) do
        if layer.layerIndex ~= nil or layer.bfiOwn or layer.pinTemplate == "MapExplorationPinTemplate" then
            fn(layer)
            for _, child in ipairs({ layer:GetChildren() }) do fn(child) end
        end
    end
end

local function EachTexture(f, fn)
    for _, r in ipairs({ f:GetRegions() }) do
        if r:GetObjectType() == "Texture" then fn(r) end
    end
end

local function Unmask()
    for r, m in pairs(masked) do r:RemoveMaskTexture(m) end
    wipe(masked)
    for _, m in pairs(masks) do m:Hide() end
end

local function Cut(map)
    local id = map:GetMapID()
    local shape
    if ns.ClearView() and Cfg().zoneOnly then shape = ZoneShape(id) end
    if not shape then
        if next(masked) then Unmask() end
        ns.clearViewCut = shape == false and (id .. ": no outline for this zone, not cut") or nil
        return
    end
    local canvas = map:GetCanvas()
    local n = 0
    EachArtFrame(map, function(f)
        local m = masks[f]
        if not m then
            m = f:CreateMaskTexture()
            m:SetAllPoints(canvas)
            masks[f] = m
        end
        if m.bfiFile ~= shape then
            m:SetTexture(shape, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m.bfiFile = shape
        end
        m:Show()
        EachTexture(f, function(r)
            if masked[r] ~= m then
                if masked[r] then r:RemoveMaskTexture(masked[r]) end
                r:AddMaskTexture(m)
                masked[r] = m
            end
            n = n + 1
        end)
    end)
    ns.clearViewCut = id .. ": cut to its outline, " .. n .. " textures"
end

-- Buttons ------------------------------------------------------------------------

local function HoverTarget(map)
    if not ns.ClearView() then return 1 end
    local c = Cfg()
    if c.buttons ~= "hover" and c.header ~= "hover" then return 1 end
    return (ns.MouseOnMap and ns.MouseOnMap(map) or map:IsMouseOver()) and 1 or 0
end

-- the coordinates and the resize grip (the others fade in Options' fader)
local shownAlpha
local function FadeOwn()
    local a = (ns.ClearView() and Cfg().buttons == "hover") and hover or 1
    if a == shownAlpha then return end
    shownAlpha = a
    local d = ns.debugFrames
    for _, k in ipairs({ "coords", "coordsCursor", "grip" }) do
        if d[k] then d[k]:SetAlpha(a) end
    end
end

-- Applying -----------------------------------------------------------------------

-- clearView changed (or a setup was loaded)
function ns.ApplyClearView()
    local map = BattlefieldMapFrame
    if not map then return end
    hover = HoverTarget(map)
    shownAlpha = nil
    FadeOwn()
    if ns.UpdateStyle then ns.UpdateStyle() end           -- (the frame; it sets the header's alpha too)
    if ns.ApplyMapControls then ns.ApplyMapControls("clearView") end  -- (the map's opacity)
    ns.Safe("ClearView Cut", Cut, map)
end

-- the key
function ns.ToggleClearView()
    Cfg().on = not Cfg().on
    ns.OnSettingChanged("clearView", "on")
end

function ns.SetupClearView(map)
    local sinceCut = 0
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, dt)
        if not map:IsShown() then return end
        local want = HoverTarget(map)
        if hover ~= want then
            local step = FADE_RATE * dt
            hover = math.abs(want - hover) <= step and want or hover + (want > hover and step or -step)
            FadeOwn()
            if ns.ApplyFrameAlpha then ns.ApplyFrameAlpha() end  -- (a hover header)
        end
        -- the game swaps tiles as you zoom, move and change maps: cut new ones
        sinceCut = sinceCut + dt
        if sinceCut >= 0.5 then
            sinceCut = 0
            if ns.ClearView() or next(masked) then ns.Safe("ClearView Cut", Cut, map) end
        end
    end)
    map:HookScript("OnShow", function() ns.Safe("ClearView Cut", Cut, map) end)
    -- (another map: cut it once its tiles are laid, not half a second later)
    if map.OnMapChanged then
        hooksecurefunc(map, "OnMapChanged", function()
            C_Timer.After(0, function() ns.Safe("ClearView Cut", Cut, map) end)
        end)
    end
    ns.ApplyClearView()
end
