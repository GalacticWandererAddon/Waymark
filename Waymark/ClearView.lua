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
--   cities    the same on the six cities' maps (ns.CITY_MAPS), where they have an outline
--   dungeons  the same on our dungeon maps (Dungeon.lua), per floor; the black
--             behind the floor and the zone map under it go, the floor gets the opacity
--   bigUncut  none of the cuts while the map is big (MapControls' big map key)
--   view_<name>  an optional view (a second outline for a map, made in the editor,
--             ns.CutViews) shown in place of the map's own
-- The outlines are hand-adjusted with the dev tool in CutEdit.lua (/bfi cut): while
-- it's open the cut shows whatever clear view's settings say, its Peek shows the
-- cut-away map faintly round it.
-- By key (BFI_CLEARVIEW) or the check box on the Map frame page; kept over a
-- reload and in saved setups.

local FADE_RATE = 5   -- alpha per second

local function Cfg() return ns.db.clearView end

-- (not while docked: the docked map is the minimap, with its rim, Dock.lua)
function ns.ClearView() return ns.db and Cfg().on and not ns.Perf("effects") and not (ns.Docked and ns.Docked()) and true or false end

-- In town and city view, and on a continent (or the world), the border fades back in
-- (the user): edge, 0 to 1, gliding at FADE_RATE; the frame is hidden only while it's
-- all the way out
local edge = 0
local typeOf = {}  -- [uiMapID] = its map type (false: none)
local function OnContinent()
    local map = BattlefieldMapFrame
    local id = map and map.GetMapID and map:GetMapID()
    if not id then return false end
    local t = typeOf[id]
    if t == nil then
        local info = C_Map.GetMapInfo(id)
        t = info and info.mapType or false
        typeOf[id] = t
    end
    local T = Enum and Enum.UIMapType
    return t and T and t <= T.Continent or false
end
ns.MapOnContinent = OnContinent
local function EdgeTarget()
    if not (ns.ClearView() and Cfg().noFrame) then return 1 end
    if OnContinent() then return 1 end
    -- (town and city view: the frame back only when the map fills it. With the zone cut to its outline,
    -- a coast town's zoom shows the cut-away sea, and the frame came back round empty space, the user
    -- 2026-11-08: Auberdine)
    local town = (ns.InTownView and ns.InTownView()) or (ns.InCityView and ns.InCityView())
    if town and not (ns.ClearViewZoneCut and ns.ClearViewZoneCut()) then return 1 end
    return 0
end
function ns.ClearViewBorderAlpha() return edge end

-- the map frame's style while clear view hides it
function ns.ClearViewHidesFrame() return ns.ClearView() and Cfg().noFrame and edge <= 0 and EdgeTarget() == 0 end

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

-- an outline's file by its name in Data\ZoneCut.lua (a uiMapID, or "d<instance>_<floor>"
-- for a dungeon floor, ns.CutName); false: none for this client
local CUTS = ns.MEDIA .. "ZoneCut\\"
function ns.CutEdition() return ns.MapEdition() end
-- maps whose outline isn't used (the user: Stormwind's own map uncut)
local NO_CUT = { [1453] = true }
function ns.CutFile(name)
    if NO_CUT[name] then return false end
    local edition = ns.CutEdition()
    local list = ns.ZoneCut and ns.ZoneCut[edition]
    return name and list and list[name] and (CUTS .. edition .. "\\" .. name) or false
end

-- a map key (Ink's: "m<uiMapID>", "d<instance>:<floor>"; an optional view of one:
-- "<key>/v<n>") -> the outline's name ("1429_v1" for a view)
function ns.CutName(key)
    local base, view = key:match("^(.-)/(.+)$")
    if base then return ns.CutName(base) .. "_" .. view:gsub("[^%w]", "_") end
    if key:sub(1, 1) == "m" then return tonumber(key:sub(2)) end
    return (key:gsub("[^%w]", "_"))
end

-- the optional views baked for this client (Data\ZoneCut.lua): { name =, base =, label = },
-- by label; each a check box on the Clear view page, clearView["view_" .. name]
local viewList
function ns.CutViews()
    if not viewList then
        viewList = {}
        for name, v in pairs(ns.ZoneCutViews and ns.ZoneCutViews[ns.CutEdition()] or {}) do
            viewList[#viewList + 1] = { name = name, base = v.base, label = v.label }
        end
        table.sort(viewList, function(a, b) return a.label < b.label end)
    end
    return viewList
end

local function Editing() return ns.CutEditing and ns.CutEditing() end
-- clear view's cut k (zoneOnly, dungeons) wanted: not on the big map with bigUncut
local function Cutting(k)
    return ns.ClearView() and Cfg()[k] and not (Cfg().bigUncut and ns.MapIsBig and ns.MapIsBig())
end
local function Revealing() return ns.CutRevealing and ns.CutRevealing() end
local function Peeking() return ns.CutPeeking and ns.CutPeeking() or Revealing() end

-- a map's outline file: an optional view of it that's ticked (while editing: the one
-- open in the editor, if it's baked yet), else its own
local function ViewFile(name)
    local view
    if Editing() then
        view = ns.CutEditView and ns.CutEditView(name)
    else
        for _, v in ipairs(ns.CutViews()) do
            if tostring(v.base) == tostring(name) and Cfg()["view_" .. v.name] then view = v.name break end
        end
    end
    return view and ns.CutFile(view) or ns.CutFile(name)
end

-- the map's outline file; false: one we cut but without an outline; nil: not cut
local function ZoneShape(id)
    local info = id and C_Map.GetMapInfo(id)
    if not info then return nil end
    if ns.CITY_MAPS and ns.CITY_MAPS[id] then
        if not (Cfg().cities or Editing()) then return nil end
    elseif not (Enum.UIMapType and info.mapType == Enum.UIMapType.Zone) then
        return nil
    end
    return ViewFile(id)
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

ns.EachMapArtFrame = EachArtFrame

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
    if Cutting("zoneOnly") or Editing() then shape = ZoneShape(id) end
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

-- Dungeon floors ---------------------------------------------------------------

local dMask             -- on Dungeon.lua's canvas (its tiles are that frame's textures)
local dMasked = {}      -- [tile] = true
local dShown            -- { canvas, bg, mapCanvas } while a floor is cut
ns.clearViewDungeonCut = nil

local function UncutDungeon()
    for t in pairs(dMasked) do t:RemoveMaskTexture(dMask) end
    wipe(dMasked)
    if dMask then dMask:Hide() end
    if dShown then
        dShown[1]:SetAlpha(1)
        dShown[2]:SetAlpha(1)
        dShown[3]:SetAlpha(1)
        dShown = nil
    end
end

local function CutDungeon(map)
    local canvas, key, tiles, bg
    if ns.DungeonCutTarget then canvas, key, tiles, bg = ns.DungeonCutTarget() end
    local file
    if canvas and (Cutting("dungeons") or Editing()) then
        file = ViewFile(ns.CutName(key))
    end
    if not file then
        if dShown or next(dMasked) then UncutDungeon() end
        ns.clearViewDungeonCut = canvas and file == false and (key .. ": no outline, not cut") or nil
        return
    end
    if not dMask then
        dMask = canvas:CreateMaskTexture()
        dMask:SetAllPoints(canvas)
    end
    if dMask.bfiFile ~= file then
        dMask:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        dMask.bfiFile = file
    end
    dMask:Show()
    for _, t in ipairs(tiles) do
        if not dMasked[t] then
            t:AddMaskTexture(dMask)
            dMasked[t] = true
        end
    end
    -- (round the cut floor: the world, not the black or the zone map under the overlay)
    dShown = { canvas, bg, map:GetCanvas() }
    bg:SetAlpha(0)
    map:GetCanvas():SetAlpha(0)
    canvas:SetAlpha(ns.ClearView() and Cfg().opacity or 1)
    ns.clearViewDungeonCut = key .. ": cut to its outline"
end

-- Peek (CutEdit.lua) ---------------------------------------------------------------
-- The cut-away map faintly round the cut, to trace along: under each cut texture a
-- copy of it, unmasked, at GHOST_ALPHA (a mask can't be turned inside out). Ctrl held
-- in the editor: the copies at full alpha, the whole map

local GHOST_ALPHA = 0.35
local ghosts = {}       -- [cut texture] = its copy
local ghostFrame        -- the zone map's copies, under its art frames

local function Ghost(r, parent)
    local g = ghosts[r]
    if not g then
        g = parent:CreateTexture(nil, "BACKGROUND", nil, -8)
        g:SetAllPoints(r)
        ghosts[r] = g
    end
    local atlas = r.GetAtlas and r:GetAtlas()
    if atlas then g:SetAtlas(atlas) else g:SetTexture(r:GetTexture()) end
    g:SetTexCoord(r:GetTexCoord())
    g:SetVertexColor(r:GetVertexColor())
    g:SetAlpha(r:GetAlpha() * (Revealing() and 1 or GHOST_ALPHA))
    g:SetShown(r:IsVisible())
end

local function UpdateGhosts(map)
    local on = Peeking()
    for r, g in pairs(ghosts) do
        if not (on and (masked[r] or dMasked[r])) then g:Hide() end
    end
    if not on then return end
    if next(masked) then
        local canvas = map:GetCanvas()
        if not ghostFrame then
            ghostFrame = CreateFrame("Frame", nil, canvas)
            ghostFrame:SetAllPoints(canvas)
        end
        local low
        for r in pairs(masked) do
            local lvl = r:GetParent():GetFrameLevel()
            if not low or lvl < low then low = lvl end
        end
        ghostFrame:SetFrameLevel(math.max(canvas:GetFrameLevel(), low - 1))
        for r in pairs(masked) do Ghost(r, ghostFrame) end
    end
    -- (a dungeon floor's tiles are its canvas's own: the copies go on it, a layer down)
    for t in pairs(dMasked) do Ghost(t, t:GetParent()) end
end

-- a zone map / a dungeon floor is cut to its outline right now (SoftEdges.lua)
function ns.ClearViewZoneCut() return next(masked) ~= nil end
function ns.ClearViewFloorCut() return dShown ~= nil end

local function CutAll(map)
    Cut(map)
    CutDungeon(map)
    UpdateGhosts(map)
end

-- (Ctrl pressed or let go in the editor)
function ns.CutUpdateGhosts()
    if BattlefieldMapFrame then ns.Safe("ClearView Peek", UpdateGhosts, BattlefieldMapFrame) end
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
    edge = EdgeTarget()
    shownAlpha = nil
    FadeOwn()
    if ns.UpdateStyle then ns.UpdateStyle() end           -- (the frame; it sets the header's alpha too)
    if ns.ApplyMapControls then ns.ApplyMapControls("clearView") end  -- (the map's opacity)
    ns.Safe("ClearView Cut", CutAll, map)
end

-- the key
function ns.ToggleClearView()
    Cfg().on = not Cfg().on
    ns.OnSettingChanged("clearView", "on")
end

function ns.SetupClearView(map)
    local sinceCut = 0
    local ticker = ns.TimedFrame("ClearView tick")
    ticker:SetScript("OnUpdate", function(_, dt)
        if not map:IsShown() then return end
        local want = HoverTarget(map)
        if hover ~= want then
            local step = FADE_RATE * dt
            hover = math.abs(want - hover) <= step and want or hover + (want > hover and step or -step)
            FadeOwn()
            if ns.ApplyFrameAlpha then ns.ApplyFrameAlpha() end  -- (a hover header)
        end
        -- the border into town / city view and out again
        local e = EdgeTarget()
        if edge ~= e then
            local was = edge
            local step = FADE_RATE * 0.5 * dt  -- (a slower glide than the buttons')
            edge = math.abs(e - edge) <= step and e or edge + (e > edge and step or -step)
            -- (drawn again as it starts to show and once it's all gone)
            if (was <= 0 or edge <= 0) and ns.UpdateStyle then ns.UpdateStyle()
            elseif ns.ApplyFrameAlpha then ns.ApplyFrameAlpha() end
        end
        -- the game swaps tiles as you zoom, move and change maps: cut new ones
        sinceCut = sinceCut + dt
        if sinceCut >= 0.5 then
            sinceCut = 0
            if ns.ClearView() or Editing() or next(masked) or dShown then ns.Safe("ClearView Cut", CutAll, map) end
        end
    end)
    map:HookScript("OnShow", function() ns.Safe("ClearView Cut", CutAll, map) end)
    -- (another map: cut it once its tiles are laid, not half a second later)
    if map.OnMapChanged then
        hooksecurefunc(map, "OnMapChanged", function()
            C_Timer.After(0, function() ns.Safe("ClearView Cut", CutAll, map) end)
        end)
    end
    ns.ApplyClearView()
end
