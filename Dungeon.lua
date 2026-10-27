local _, ns = ...

-- Caves and dungeons on the Battlefield Map.
--  followMaps: when the game puts you on a cave, dungeon or other small map
--              that has art, switch the Battlefield Map to it (and back out
--              to the zone when you leave). The game's own arrow and pins then
--              work there as far as the client allows.
--  fallback:   inside an instance whose map the game won't switch to, draw the
--              dungeon's map ourselves: Atlas's maps and boss positions when the
--              Atlas modules are installed (read from your install while the
--              game runs: Atlas is GPLv2, nothing is copied), else Blizzard's
--              art (tile data from OpenMap, MIT). No player arrow there: the
--              game doesn't tell addons where you are (see the minimap view).
--  showInside: open the Battlefield Map when you enter a dungeon.
-- /bfi probe prints what the client reports, to see what's possible.

local function Cfg() return ns.db.dungeon end

local SMALL_MAP_TYPES = {}  -- filled in Setup, from Enum.UIMapType
local switchedTo            -- mapID we switched the Battlefield Map to

local function MapType(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    return info and info.mapType, info
end

local function HasArt(mapID)
    return C_Map.GetMapArtID and C_Map.GetMapArtID(mapID) ~= nil
end

-- Follow caves/dungeons -------------------------------------------------------

local function Follow(map)
    if not Cfg().followMaps then return end
    if ns.Browsing and ns.Browsing() then return end  -- (another map you're looking at)
    local best = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not best then return end
    local current = map:GetMapID()
    if SMALL_MAP_TYPES[MapType(best) or -1] and HasArt(best) then
        if current ~= best then
            switchedTo = best
            map:SetMapID(best)
        end
    elseif switchedTo and current == switchedTo then
        -- left the cave: back to the zone the game puts you on
        switchedTo = nil
        local zone = MapUtil and MapUtil.GetMapParentInfo and MapUtil.GetMapParentInfo(best, Enum.UIMapType.Zone, true)
        map:SetMapID(zone and zone.mapID or best)
    end
end

-- Fallback dungeon map -------------------------------------------------------

local overlay, tiles, floorText, prevBtn, nextBtn
local floors, floorIndex, shownInstance
local preview  -- a dungeon you clicked on the zone map, shown from outside (further down)
local zoneView -- inside: right-clicked out to the dungeon's zone (instance ID), when browsing can't hold it
local manualFloor = false  -- you picked a floor with < >: stop auto-picking

-- the floor whose name (or wing) appears in what the game calls where you are:
-- SM's floors are its wings ("Graveyard"), others are areas inside
local function MatchFloor()
    -- Atlas lists each of its maps' sub-zones exactly: that wins
    local sub = GetSubZoneText and GetSubZoneText() or ""
    if sub ~= "" then
        for i, f in ipairs(floors) do
            for _, s in ipairs(f.subzones or {}) do
                if s == sub then return i end
            end
        end
    end
    local here = {}
    for _, fn in ipairs({ GetSubZoneText, GetMinimapZoneText, GetZoneText, GetRealZoneText }) do
        local ok, s = pcall(fn)
        if ok and s and s ~= "" then here[#here + 1] = s:lower() end
    end
    local lfgID = select(10, GetInstanceInfo())
    if lfgID and GetLFGDungeonInfo then
        local ok, s = pcall(GetLFGDungeonInfo, lfgID)
        if ok and type(s) == "string" then here[#here + 1] = s:lower() end
    end
    -- an exact name first: inside WC the zone is "Wailing Caverns", which is also
    -- part of Atlas's "Wailing Caverns (Entrance)"; the dungeon map must win
    for i, f in ipairs(floors) do
        for _, key in ipairs({ f.name, f.wing }) do
            if key then
                key = key:lower()
                for _, s in ipairs(here) do
                    if s == key then return i end
                end
            end
        end
    end
    for i, f in ipairs(floors) do
        for _, key in ipairs({ f.name, f.wing }) do
            if key then
                key = key:lower()
                for _, s in ipairs(here) do
                    if s:find(key, 1, true) or key:find(s, 1, true) then return i end
                end
            end
        end
    end
end

-- OpenMap's floors: 12 tiles each (4 x 3 of 256 px, the picture 1002 x 668 of it)
local function OpenMapFloors(instanceID)
    local data = ns.MapDungeonMaps and ns.MapDungeonMaps[instanceID]
    if not data then return end
    local out = {}
    for _, f in ipairs(data) do
        if f.tiles and #f.tiles == 12 then out[#out + 1] = { tiles = f.tiles, name = f.name } end
    end
    return #out > 0 and out or nil
end

-- Atlas's maps (its modules: Atlas_ClassicWoW and the like). Read from your
-- install while the game runs, never copied: Atlas is GPLv2. Each module keeps
-- module.db.AtlasMaps[key] (WorldMapID = the instance ID, PrevMap/NextMap for a
-- dungeon split over several maps, the list of numbered entries),
-- db.AtlasMaps_NPC_DB[key] = { { label, entryID, x, y }, ... } (pixels on its
-- 512 x 512 image) and db.SubZoneData[zone][key] = { sub-zones }. The image is
-- Interface\AddOns\<module>\Images\<key>.
local ATLAS_PX = 512

local function StripCodes(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function AtlasModules()
    local AceAddon = LibStub and LibStub("AceAddon-3.0", true)
    local atlas = AceAddon and AceAddon:GetAddon("Atlas", true)
    if not (atlas and atlas.IterateModules) then return function() end end
    local out = {}
    for _, mod in atlas:IterateModules() do
        if type(mod) == "table" and type(mod.db) == "table" and mod.db.AtlasMaps then out[#out + 1] = mod end
    end
    local i = 0
    return function() i = i + 1 return out[i] end
end

-- one Atlas map as a floor: its picture, its name, its sub-zones, its markers
local function AtlasFloor(db, key, entry)
    local f = {
        atlas = true, key = key,
        texture = "Interface\\AddOns\\" .. (entry.Module or "") .. "\\Images\\" .. key,
        name = entry.ZoneName and entry.ZoneName[1] and StripCodes(entry.ZoneName[1]) or key,
        subzones = {}, bosses = {},
    }
    for _, byKey in pairs(db.SubZoneData or {}) do
        if type(byKey) == "table" and type(byKey[key]) == "table" then
            for _, s in ipairs(byKey[key]) do f.subzones[#f.subzones + 1] = s end
        end
    end
    -- the numbered list: entry ID -> its label ("2) Lord Cobrahn (...)")
    local labels = {}
    for _, item in ipairs(entry) do
        if type(item) == "table" and type(item[1]) == "string" and item[2] then labels[item[2]] = item[1] end
    end
    for _, p in ipairs(db.AtlasMaps_NPC_DB and db.AtlasMaps_NPC_DB[key] or {}) do
        local label = labels[p[2]]
        if label and p[3] and p[4] then
            label = StripCodes(label)
            local text = label:gsub("^%w+%)%s*", "")       -- "2) Lord Cobrahn (Varies)" -> "Lord Cobrahn (Varies)"
            local name = text:gsub("%s*%(.*$", "")         -- -> "Lord Cobrahn", for matching kills
            f.bosses[#f.bosses + 1] = { name = name, label = label, x = p[3] / ATLAS_PX, y = p[4] / ATLAS_PX }
        end
    end
    return f
end

-- Is this Atlas map one of this instance's? Atlas's data files differ by client:
-- some give WorldMapID as the instance ID (43 for WC), some as the dungeon's map
-- ID (279). So: either ID, or failing both, the instance's name as the map's name
-- ("Wailing Caverns", "Wailing Caverns (Entrance)").
local function IsInstanceMap(entry, instanceID, instanceName)
    local id = entry.WorldMapID
    if id and id == instanceID then return true end
    if id and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(id)
        if info and instanceName and info.name == instanceName then return true end
    end
    local name = entry.ZoneName and entry.ZoneName[1] and StripCodes(entry.ZoneName[1])
    return name and instanceName and instanceName ~= ""
        and (name == instanceName or name:sub(1, #instanceName + 2) == instanceName .. " (") or false
end

-- every Atlas map of this instance, in the order its maps link up (Prev/Next)
local function AtlasFloors(instanceID)
    if not ns.db.dungeon.useAtlas then return end
    local instanceName = GetInstanceInfo()
    for mod in AtlasModules() do
        local maps, keys = mod.db.AtlasMaps, {}
        for key, entry in pairs(maps) do
            if type(entry) == "table" and IsInstanceMap(entry, instanceID, instanceName) then keys[key] = entry end
        end
        if next(keys) then
            -- start at a map whose previous map isn't one of these, then follow NextMap
            local first
            for key, entry in pairs(keys) do
                -- (keys are strings: the alphabetically first, so it's the same every time)
                if not (entry.PrevMap and keys[entry.PrevMap]) and (not first or key < first) then first = key end
            end
            local out, seen, key = {}, {}, first
            while key and keys[key] and not seen[key] do
                seen[key] = true
                out[#out + 1] = AtlasFloor(mod.db, key, keys[key])
                key = keys[key].NextMap
            end
            for k, entry in pairs(keys) do  -- (any not reached by the chain)
                if not seen[k] then out[#out + 1] = AtlasFloor(mod.db, k, entry) end
            end
            return out
        end
    end
end

-- Pan and zoom, like the cave view: the floor's picture sits on a canvas whose
-- units are the picture's own pixels; the canvas is scaled and moved inside the
-- clipping overlay. zoom 1 = the floor covers the whole view, as the zone maps
-- do (MapControls' CoverScale): no empty bands, the long side trimmed. Wheel:
-- zoom; left-drag: pan; right-click: out to the dungeon's zone (ns.DungeonZoneView;
-- from outside, back to the zone). Never panned past the picture's edges.
local canvas
local PW, PH = 1002, 668               -- the picture's size (Blizzard's dungeon maps)
local zoom = 1
local centerX, centerY = 0, 0          -- view centre, picture px from the picture's centre (y down)
local drag

local function ClampMid(v, lo, hi)
    if lo > hi then return (lo + hi) / 2 end
    return math.max(lo, math.min(hi, v))
end

local ResizeMarkers  -- (boss markers, further down: sized with the map)

local function Layout()
    local W, H = overlay:GetWidth(), overlay:GetHeight()
    if not (W and W > 0 and H and H > 0) then return end
    local k = math.max(W / PW, H / PH) * zoom
    local hw, hh = W / (2 * k), H / (2 * k)
    centerX = ClampMid(centerX, -PW / 2 + hw, PW / 2 - hw)
    centerY = ClampMid(centerY, -PH / 2 + hh, PH / 2 - hh)
    canvas:SetScale(k)
    canvas:ClearAllPoints()
    -- (canvas units; screen y points up, picture y down)
    canvas:SetPoint("CENTER", overlay, "CENTER", -centerX, centerY)
    if ResizeMarkers then ResizeMarkers(k) end
    return k
end

local function ShowFloor()
    local f = floors[floorIndex]
    for _, tex in ipairs(tiles) do tex:Hide() end
    if f.tiles then
        -- 12 tiles of 256 px (4 x 3); the picture is their top-left 1002 x 668,
        -- so the last column and row are trimmed to it
        PW, PH = 1002, 668
        for i = 1, 12 do
            local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
            local pw, ph = math.min(256, PW - col * 256), math.min(256, PH - row * 256)
            local tex = tiles[i]
            tex:SetTexture(f.tiles[i])
            tex:SetTexCoord(0, pw / 256, 0, ph / 256)
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", canvas, "TOPLEFT", col * 256, -row * 256)
            tex:SetSize(pw, ph)
            tex:Show()
        end
    else
        -- one picture: Atlas's 512 x 512 map
        PW, PH = ATLAS_PX, ATLAS_PX
        local tex = tiles[1]
        tex:SetTexture(f.texture)
        tex:SetTexCoord(0, 1, 0, 1)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", canvas, "TOPLEFT")
        tex:SetSize(PW, PH)
        tex:Show()
    end
    canvas:SetSize(PW, PH)
    Layout()
    local count = #floors
    local name = f.name or ("Floor " .. floorIndex)
    -- inside, the header already names where you are: no second copy of it here
    local sub = GetSubZoneText and GetSubZoneText() or ""
    local zone = GetZoneText and GetZoneText() or ""
    local said = not preview and ns.IsShown("zoneName")
        and (name:lower() == sub:lower() or name:lower() == zone:lower())
    local counter = count > 1 and ("(" .. floorIndex .. "/" .. count .. ")") or ""
    if count <= 1 and not (preview and f.name) then
        floorText:SetText("")  -- one floor: nothing to tell apart (a preview keeps the dungeon's name)
    else
        floorText:SetText(said and counter or (name .. (counter ~= "" and ("  " .. counter) or "")))
    end
    prevBtn:SetShown(count > 1)
    nextBtn:SetShown(count > 1)
end

-- Boss markers -----------------------------------------------------------------
-- Where the bosses are: Atlas's positions on its own map (AtlasFloor), so they
-- line up with the picture by construction. Atlas prints its numbers on the
-- map, so a living boss gets no icon of ours, just an invisible spot for the
-- tooltip; a killed one gets the game's red X, so the map shows where you've been.

local markerLayer
local bossMarkers = {}

-- this run's kills, kept in the saved variables so a /reload or a death and
-- run back keeps them; a new run (another dungeon, or an hour outside) clears them
local function Run() return ns.db.dungeonRun end
local function Kills() return Run().kills end

local function Marker(i)
    local m = bossMarkers[i]
    if m then return m end
    m = CreateFrame("Frame", nil, markerLayer)
    m:SetSize(20, 20)
    m.done = m:CreateTexture(nil, "OVERLAY")
    m.done:SetSize(22, 22)
    m.done:SetPoint("CENTER")
    m.done:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
    -- an invisible point on the canvas: the marker hangs on it, so it moves with
    -- the map but keeps its own size whatever the zoom
    m.anchor = canvas:CreateTexture(nil, "BACKGROUND")
    m.anchor:SetSize(1, 1)
    m:EnableMouse(true)
    m:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.bossName)
        if self.killed then GameTooltip:AddLine("Defeated", 0.3, 1, 0.3) end
        GameTooltip:Show()
    end)
    m:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bossMarkers[i] = m
    return m
end

-- sized in the picture's own pixels (about a printed number on Atlas's 512 px
-- map), so the X shrinks and grows with the map instead of staying one size
local MARKER_PX = 22
ResizeMarkers = function(k)
    for _, m in ipairs(bossMarkers) do
        local s = MARKER_PX * k
        m:SetSize(s, s)
        m.done:SetSize(s * 1.1, s * 1.1)
    end
end

local function DrawBosses()
    for _, m in ipairs(bossMarkers) do m:Hide() end
    if not Cfg().bosses then return end
    local f = floors and floors[floorIndex]
    if not (f and f.bosses) then return end  -- (Blizzard's art: no positions to go on)
    local kills, n = Kills(), 0
    for _, b in ipairs(f.bosses) do
        if b.name and b.x and b.y then
            n = n + 1
            local m = Marker(n)
            m.anchor:ClearAllPoints()
            m.anchor:SetPoint("CENTER", canvas, "TOPLEFT", b.x * PW, -b.y * PH)
            m:ClearAllPoints()
            m:SetPoint("CENTER", m.anchor, "CENTER")
            m.bossName = b.label or b.name
            m.killed = kills[b.name:lower()] and true or false
            m.done:SetShown(m.killed)
            m:Show()
        end
    end
    ResizeMarkers(canvas:GetScale())  -- (new markers: the current size straight away)
end

-- a death in the combat log counts if it's anyone on this dungeon's maps (any floor)
local function IsBossHere(name)
    if not (floors and name) then return false end
    local lname = name:lower()
    for _, f in ipairs(floors) do
        for _, b in ipairs(f.bosses or {}) do
            if b.name and b.name:lower() == lname then return true end
        end
    end
    return false
end

local function MarkKilled(name)
    if not name then return end
    Kills()[name:lower()] = true
    DrawBosses()
end

-- entering or leaving an instance: keep or start a run
local RUN_TIMEOUT = 3600  -- an hour outside: a new run
local function UpdateRun()
    local r = Run()
    local inInstance = IsInInstance()
    if inInstance then
        local instanceID = select(8, GetInstanceInfo())
        if r.id ~= instanceID or (r.leftAt > 0 and time() - r.leftAt > RUN_TIMEOUT) then
            r.id, r.kills = instanceID, {}
        end
        r.leftAt = 0
    elseif r.id and r.leftAt == 0 then
        r.leftAt = time()
    end
end

-- Minimap view ---------------------------------------------------------------------
-- Inside instances the game won't tell addons where you are, but the minimap knows
-- and draws it. So: borrow the real minimap and show it large in the map, with the
-- game's own arrow, party and detail. There's only one minimap, so while borrowed
-- it's missing from its usual place; it goes back when you switch view, leave, or
-- close the map. (Its buttons, other addons' too, are hidden meanwhile.)

-- Combat: the minimap holds protected parts (the queue button...), so moving it,
-- resizing it or hiding its children is blocked in combat ("blocked from an
-- action only available to the Blizzard UI"). Worse, a frame holding a protected
-- frame becomes protected itself, so while borrowed even our frames and the map
-- couldn't be shown or hidden in a fight. So the minimap goes back the moment
-- combat starts (PLAYER_REGEN_DISABLED comes just before the lock), the map
-- view shows during the fight, and the minimap view returns after it.
local function InCombat() return InCombatLockdown and InCombatLockdown() end

local holder, borrowed

local function FitMinimap()
    if not (borrowed and holder) or InCombat() then return end
    local s = math.min(holder:GetWidth(), holder:GetHeight())
    if s and s > 0 then Minimap:SetSize(s, s) end
end

local function Borrow()
    if borrowed or not Minimap or InCombat() then return end
    local mm = Minimap
    borrowed = { parent = mm:GetParent(), points = {}, w = mm:GetWidth(), h = mm:GetHeight(),
                 scale = mm:GetScale(), strata = mm:GetFrameStrata(), level = mm:GetFrameLevel(), hidden = {} }
    for i = 1, mm:GetNumPoints() do borrowed.points[i] = { mm:GetPoint(i) } end
    for _, child in ipairs({ mm:GetChildren() }) do
        if child:IsShown() then
            child:Hide()
            borrowed.hidden[#borrowed.hidden + 1] = child
        end
    end
    holder:Show()
    mm:SetParent(holder)
    mm:SetScale(1)
    mm:ClearAllPoints()
    mm:SetPoint("CENTER", holder, "CENTER")
    mm:SetFrameStrata(holder:GetFrameStrata())
    mm:SetFrameLevel(holder:GetFrameLevel() + 1)
    FitMinimap()
end

local function GiveBack()
    -- (in combat it can't; it already went back when combat started)
    if not borrowed or InCombat() then return end
    local mm, b = Minimap, borrowed
    borrowed = nil
    mm:SetParent(b.parent)
    mm:SetScale(b.scale)
    mm:ClearAllPoints()
    for _, p in ipairs(b.points) do mm:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
    mm:SetSize(b.w, b.h)
    mm:SetFrameStrata(b.strata)
    mm:SetFrameLevel(b.level)
    for _, child in ipairs(b.hidden) do child:Show() end
    if holder then holder:Hide() end
end
ns.GiveBackMinimap = GiveBack

local viewBtn

local function UpdateFallback(map)
    if not overlay then return end
    local inInstance = IsInInstance()
    -- looking at a dungeon from outside: left alone, until you go into one
    if preview and not inInstance then return end
    preview = nil
    local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    if zoneView ~= (inInstance and instanceID or nil) then zoneView = nil end
    -- only when the game didn't give us a real map of the place
    local best = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local native = best and SMALL_MAP_TYPES[MapType(best) or -1] and HasArt(best) and map:GetMapID() == best
    -- (looking at another map: the right-click out to the zone, or any browsing)
    local away = zoneView or (ns.Browsing and ns.Browsing())
    if not (Cfg().fallback and inInstance and not native and not away and map:IsVisible()) then
        GiveBack()
        overlay:Hide()
        shownInstance = nil
        return
    end
    if shownInstance ~= instanceID then
        shownInstance = instanceID
        -- Atlas first (its maps and boss positions match), Blizzard's art otherwise
        floors = AtlasFloors(instanceID) or OpenMapFloors(instanceID)
        floorIndex = 1
        manualFloor = false
    end

    -- (in combat the minimap stays in its own place: the map view meanwhile)
    local minimapView = Cfg().view == "minimap" and not InCombat()
    if not floors and not minimapView then overlay:Hide() return end  -- (no art: the minimap view still works)
    overlay:Show()
    viewBtn:SetText(minimapView and "Map" or "Minimap")
    viewBtn:SetShown(floors ~= nil)  -- nothing to switch to without art

    if minimapView then
        canvas:Hide()
        markerLayer:Hide()
        floorText:Hide()
        prevBtn:Hide()
        nextBtn:Hide()
        Borrow()
    else
        GiveBack()
        canvas:Show()
        markerLayer:Show()
        floorText:Show()
        if not manualFloor then floorIndex = MatchFloor() or floorIndex end
        ShowFloor()
        DrawBosses()
    end
end

-- the zone a dungeon is entered from: the map under its entrance, climbed to
-- the zone (Stockades: Stormwind City)
local function DungeonZone(instanceID)
    local e = ns.DungeonEntrances and ns.DungeonEntrances[instanceID]
    if not (e and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return end
    local ok, mapID = pcall(C_Map.GetMapPosFromWorldPos, e[3], CreateVector2D(e[4], e[5]))
    if not (ok and mapID) then return end
    local zone = MapUtil and MapUtil.GetMapParentInfo and MapUtil.GetMapParentInfo(mapID, Enum.UIMapType.Zone, true)
    return zone and zone.mapID or mapID
end

-- Right-click inside: out to the dungeon's zone map. As browsing (Browse.lua),
-- so its ways home bring the dungeon map back; where the zone is the map the
-- game calls yours, browsing can't hold it: then until you click the dungeon's
-- entrance, close the map or leave.
function ns.DungeonZoneView()
    local map = BattlefieldMapFrame
    local zone = shownInstance and DungeonZone(shownInstance)
    if not (map and zone) then return end
    GiveBack()
    overlay:Hide()
    if ns.BrowseTo then ns.BrowseTo(zone) end
    if not (ns.Browsing and ns.Browsing()) then
        zoneView = shownInstance
        map:SetMapID(zone)
    end
end

-- the dungeon map covers the map: its tooltips and hover marks stay off
function ns.DungeonMapShown() return overlay and overlay:IsShown() or false end

local function CursorInOverlay()
    local x, y = GetCursorPosition()
    local s = overlay:GetEffectiveScale()
    return x / s, y / s
end

-- above every map pin (they sit around 2000-2500): zone pins don't belong on
-- it. (The gear, town / city and toggle buttons go above this: Options.)
function ns.DungeonOverlayLevel(map)
    local area = map.ScrollContainer or map
    return math.min(area:GetFrameLevel() + 5000, 8990)
end

local function CreateOverlay(map)
    local area = map.ScrollContainer or map
    overlay = CreateFrame("Frame", nil, area)
    overlay:SetAllPoints(area)
    overlay:SetFrameLevel(ns.DungeonOverlayLevel(map))
    overlay.bfiCoversMap = true  -- (Explore's hover names: not through it)
    overlay:EnableMouse(true)  -- the zone map underneath isn't where you are
    overlay:EnableMouseWheel(true)
    overlay:SetClipsChildren(true)
    local bg = overlay:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 1)

    canvas = CreateFrame("Frame", nil, overlay)
    canvas:SetSize(PW, PH)
    tiles = {}
    for i = 1, 12 do tiles[i] = canvas:CreateTexture(nil, "ARTWORK") end

    -- boss markers: above the art, not scaled with it (they hang on canvas points)
    markerLayer = CreateFrame("Frame", nil, overlay)
    markerLayer:SetAllPoints(overlay)
    markerLayer:SetFrameLevel(canvas:GetFrameLevel() + 2)

    -- where the borrowed minimap goes
    holder = CreateFrame("Frame", nil, overlay)
    holder:SetAllPoints(overlay)
    holder:SetFrameLevel(canvas:GetFrameLevel() + 3)
    holder:SetScript("OnSizeChanged", FitMinimap)
    holder:Hide()

    overlay:SetScript("OnMouseWheel", function(_, delta)
        if borrowed then
            -- the minimap's own zoom levels (0 = furthest out)
            local z = Minimap:GetZoom() + (delta > 0 and 1 or -1)
            Minimap:SetZoom(math.max(0, math.min(Minimap:GetZoomLevels() - 1, z)))
            return
        end
        zoom = math.max(1, math.min(6, zoom * (delta > 0 and 1.25 or 0.8)))
        Layout()
    end)
    overlay:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            local mx, my = CursorInOverlay()
            drag = { mx = mx, my = my, cx = centerX, cy = centerY }
        elseif button == "RightButton" then
            if preview then
                ns.EndDungeonPreview()  -- looking from outside: back to the zone
                return
            end
            drag = nil
            ns.DungeonZoneView()
        end
    end)
    overlay:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then drag = nil end
    end)
    overlay:SetScript("OnUpdate", function()
        if not drag then return end
        local k = Layout() or 1
        local mx, my = CursorInOverlay()
        -- drag right: the picture moves right, so the view centre moves left
        centerX = drag.cx - (mx - drag.mx) / k
        centerY = drag.cy + (my - drag.my) / k
        Layout()
    end)

    -- the floor label and buttons on their own frame above the canvas (a child
    -- frame draws over its parent's textures, so on the overlay they'd be covered)
    local top = CreateFrame("Frame", nil, overlay)
    top:SetAllPoints(overlay)
    top:SetFrameLevel(canvas:GetFrameLevel() + 5)

    floorText = top:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    floorText:SetPoint("TOP", 0, -4)
    floorText:SetShadowOffset(1, -1)
    local function Step(d)
        manualFloor = true
        floorIndex = (floorIndex - 1 + d) % #floors + 1
        centerX, centerY = 0, 0
        ShowFloor()
        DrawBosses()
    end
    prevBtn = CreateFrame("Button", nil, top, "UIPanelButtonTemplate")
    prevBtn:SetSize(22, 18)
    prevBtn:SetText("<")
    prevBtn:SetPoint("RIGHT", floorText, "LEFT", -6, 0)
    prevBtn:SetScript("OnClick", function() Step(-1) end)
    nextBtn = CreateFrame("Button", nil, top, "UIPanelButtonTemplate")
    nextBtn:SetSize(22, 18)
    nextBtn:SetText(">")
    nextBtn:SetPoint("LEFT", floorText, "RIGHT", 6, 0)
    nextBtn:SetScript("OnClick", function() Step(1) end)

    -- Map / Minimap switch, top left (the gear and toggle buttons are top right)
    viewBtn = CreateFrame("Button", nil, top, "UIPanelButtonTemplate")
    viewBtn:SetSize(70, 18)
    viewBtn:SetPoint("TOPLEFT", 4, -4)
    viewBtn:SetScript("OnClick", function()
        local c = Cfg()
        c.view = c.view == "minimap" and "art" or "minimap"
        if ns.RefreshControls then ns.RefreshControls() end
        ns.UpdateDungeon()
    end)
    viewBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Switch view")
        GameTooltip:AddLine("Minimap: your arrow and the game's own detail (borrows your minimap).", 1, 1, 1, true)
        GameTooltip:AddLine("Map: the dungeon's map with boss markers.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    viewBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    overlay:SetScript("OnSizeChanged", function() if floors and overlay:IsShown() then Layout() end end)
    overlay:Hide()
end

-- Looking at a dungeon from outside -----------------------------------------------
-- Click a dungeon entrance on the zone map: its map opens in the same view as
-- inside (floors, boss markers); a right-click (or Back) returns to the zone.

-- (preview, declared above UpdateFallback: the instance shown because you clicked it)

local function EndPreview()
    if not preview then return end
    preview = nil
    shownInstance = nil
    overlay:Hide()
    ns.UpdateDungeon()
end
ns.EndDungeonPreview = EndPreview

function ns.PreviewDungeon(id)
    if not overlay then return end
    if IsInInstance() then
        -- the entrance of the dungeon you're in, from its zone: back inside
        if id ~= select(8, GetInstanceInfo()) then return end
        zoneView = nil
        if ns.Browsing and ns.Browsing() then ns.BrowseHome() else ns.UpdateDungeon() end
        return
    end
    local found = AtlasFloors(id) or OpenMapFloors(id)
    local e = ns.DungeonEntrances and ns.DungeonEntrances[id]
    if not found then
        ns.Log("no map of " .. (e and e[1] or ("instance " .. id)) .. " to show")
        return
    end
    GiveBack()
    preview, shownInstance = id, id
    floors, floorIndex, manualFloor = found, 1, true
    zoom, centerX, centerY, drag = 1, 0, 0, nil
    overlay:Show()
    canvas:Show()
    markerLayer:Show()
    floorText:Show()
    viewBtn:Hide()  -- (right-click returns to the zone)
    ShowFloor()
    DrawBosses()
end

-- Dungeon entrances on the zone map ---------------------------------------------

local ENTRANCE_TEMPLATE = "BFIDungeonPinTemplate"

local function EntranceCfg() return ns.db.dungeons end

-- where each entrance is on a map (cached per map): { id, x, y }
local entrancesOn = {}
local function EntrancesOn(mapID)
    if entrancesOn[mapID] then return entrancesOn[mapID] end
    local out = {}
    if ns.DungeonEntrances and C_Map.GetMapPosFromWorldPos and CreateVector2D then
        for id, e in pairs(ns.DungeonEntrances) do
            local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, e[3], CreateVector2D(e[4], e[5]), mapID)
            if ok and pos then
                local x, y = pos:GetXY()
                if x >= 0 and x <= 1 and y >= 0 and y <= 1 then out[#out + 1] = { id = id, x = x, y = y } end
            end
        end
    end
    -- entrances on one spot (Blackrock Mountain's four): side by side, so each can be clicked
    table.sort(out, function(a, b) return a.id < b.id end)
    for i, a in ipairs(out) do
        local n = 0
        for j = 1, i - 1 do
            local b = out[j]
            if math.abs(a.x - b.x) < 0.012 and math.abs(a.y - b.y) < 0.012 then n = n + 1 end
        end
        a.x = a.x + n * 0.014
    end
    entrancesOn[mapID] = out
    return out
end

-- The icon: the map's own dungeon entrance swirl (the `dungeon` atlas), the
-- same as the Dungeon entrances toggle button
local function EntranceIcon(pin)
    ns.SetArt(pin.Icon, "dungeon")
end

BFIDungeonPinMixin = CreateFromMixins(MapCanvasPinMixin)
BFIDungeonPinMixin.CheckMouseButtonPassthrough = ns.SafePassthrough  -- see Pin.lua

function BFIDungeonPinMixin:OnLoad()
    if self.UseFrameLevelType then pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_BFI_DUNGEONS") end
end

function BFIDungeonPinMixin:ApplyCurrentScale()
    local map = self:GetMap()
    local canvasScale = map and map.GetCanvasScale and map:GetCanvasScale() or 1
    if not canvasScale or canvasScale <= 0 then canvasScale = 1 end
    self:SetScale(ns.PinScale("dungeons", EntranceCfg().scale) / canvasScale)  -- (PinScale: town view, small map)
    ns.ReanchorPin(self, map)
end

function BFIDungeonPinMixin:ApplyCurrentAlpha() self:SetAlpha(ns.PinAlpha("dungeons")) end

function BFIDungeonPinMixin:OnAcquired(p)
    self.info = p
    EntranceIcon(self)
    self:ApplyCurrentScale()
    self:ApplyCurrentAlpha()
    self:SetPosition(p.x, p.y)
end

function BFIDungeonPinMixin:OnEnter()
    local e = ns.DungeonEntrances[self.info.id]
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(e[1])
    GameTooltip:AddLine(e[2] and "Raid" or "Dungeon", 1, 1, 1)
    local has = AtlasFloors(self.info.id) or OpenMapFloors(self.info.id)
    GameTooltip:AddLine(has and "Click: view its map" or "No map of it to show", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function BFIDungeonPinMixin:OnLeave() GameTooltip:Hide() end
-- the map wires a pin's mouse-over to these (see Pin.xml)
BFIDungeonPinMixin.OnMouseEnter = BFIDungeonPinMixin.OnEnter
BFIDungeonPinMixin.OnMouseLeave = BFIDungeonPinMixin.OnLeave

function BFIDungeonPinMixin:OnMouseUp(button)
    if button == "LeftButton" and not IsModifierKeyDown() then
        ns.PreviewDungeon(self.info.id)
    elseif ns.PinAltClick then
        ns.PinAltClick(self, button)  -- line target (Line.lua)
    end
end

BFIDungeonProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)

function BFIDungeonProviderMixin:RemoveAllData()
    local map = self:GetMap()
    pcall(map.RemoveAllPinsByTemplate, map, ENTRANCE_TEMPLATE)
end
function BFIDungeonProviderMixin:RefreshAllData() self:Draw() end
function BFIDungeonProviderMixin:OnMapChanged()
    EndPreview()  -- (another map: the preview was of this one's dungeon)
    self:Draw()
end

function BFIDungeonProviderMixin:Draw()
    self:RemoveAllData()
    local map = self:GetMap()
    local mapID = map:GetMapID()
    if not (mapID and ns.IsShown("dungeons")) then return end
    local info = C_Map.GetMapInfo(mapID)
    -- on zone maps (a continent would put every entrance on it)
    if not (info and Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.Zone) then return end
    for _, p in ipairs(EntrancesOn(mapID)) do
        pcall(map.AcquirePin, map, ENTRANCE_TEMPLATE, p)
    end
end

-- Probe ---------------------------------------------------------------------

function ns.Probe()
    local L = ns.Log
    local inInstance, kind = IsInInstance()
    local name, iType, _, _, _, _, _, instanceID = GetInstanceInfo()
    L("instance:", tostring(inInstance), tostring(kind), "|", tostring(name), tostring(iType), "id", tostring(instanceID))
    local best = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local mtype, info = MapType(best)
    L("best map:", tostring(best), info and info.name or "-", "type", tostring(mtype), "art", tostring(best and C_Map.GetMapArtID and C_Map.GetMapArtID(best)))
    local pos = best and C_Map.GetPlayerMapPosition(best, "player")
    L("position on it:", pos and string.format("%.3f, %.3f", pos.x, pos.y) or "none (the game won't say)")
    local map = BattlefieldMapFrame
    L("Battlefield Map shows:", tostring(map and map:GetMapID()), map and map:IsShown() and "(open)" or "(closed)")
    local atlasFloors = AtlasFloors(instanceID)
    if atlasFloors then
        local parts = {}
        for _, f in ipairs(atlasFloors) do parts[#parts + 1] = f.key .. " (" .. #f.bosses .. " markers)" end
        L("Atlas maps:", table.concat(parts, ", "))
    else
        L("Atlas maps: none for this instance (or Atlas off / not installed)")
    end
    -- what Atlas itself loaded, to see why
    local AceAddon = LibStub and LibStub("AceAddon-3.0", true)
    local atlas = AceAddon and AceAddon:GetAddon("Atlas", true)
    if not atlas then
        L("Atlas: not loaded (check its errors)")
    else
        local c = atlas.Client or {}
        L("Atlas client:", "forever=" .. tostring(c.isForever), "era=" .. tostring(c.isClassicEra),
          "progression=" .. tostring(c.isProgressionClassic), "tbc=" .. tostring(c.isTBCClassic), "retail=" .. tostring(c.isRetail))
        local n = 0
        if atlas.IterateModules then
            for name, mod in atlas:IterateModules() do
                n = n + 1
                local maps = type(mod) == "table" and type(mod.db) == "table" and mod.db.AtlasMaps
                local count = 0
                for _ in pairs(maps or {}) do count = count + 1 end
                L("  Atlas module:", tostring(name), maps and (count .. " maps") or "no map data")
            end
        end
        if n == 0 then L("  Atlas has no modules registered") end
    end
    L("Blizzard art (OpenMap data):", OpenMapFloors(instanceID) and "yes" or "no")

    -- What else the client gives inside, for finding your position another way.
    -- (pcall + type checks: some of these are blocked, or "secret", in instances)
    local function Show(v)
        if type(v) == "number" then return string.format("%.2f", v) end
        return tostring(v) .. " (" .. type(v) .. ")"
    end
    local ok, a, b, c, d = pcall(UnitPosition, "player")
    L("raw world position (UnitPosition):", ok and (Show(a) .. ", " .. Show(b) .. ", z " .. Show(c) .. ", map " .. Show(d)) or ("error: " .. tostring(a)))
    local okF, facing = pcall(GetPlayerFacing)
    local okS, speed, run = pcall(GetUnitSpeed, "player")
    L("facing:", okF and Show(facing) or "error", "| speed:", okS and (Show(speed) .. " (run " .. Show(run) .. ")") or "error",
      "| indoors:", tostring(IsIndoors and IsIndoors()))
    L("sub-zone:", tostring(GetSubZoneText and GetSubZoneText()), "| minimap zone:", tostring(GetMinimapZoneText and GetMinimapZoneText()),
      "| zone:", tostring(GetZoneText and GetZoneText()))
    L("Run this in two different spots inside: if the position numbers change, we have it.")
end

-- Setup ---------------------------------------------------------------------

function ns.UpdateDungeon()
    local map = BattlefieldMapFrame
    if not map then return end
    pcall(Follow, map)
    pcall(UpdateFallback, map)
end

-- The game's Battlefield Map is for battlegrounds and the open world only
-- (GetBattlefieldMapInstanceType is nil in a dungeon): there its Toggle just
-- closes it, and its zone and widget events close it again. In a dungeon or
-- raid: Toggle opens and closes it, the widget events leave it be, and on
-- entering it stays (or opens) with showInside; else the game closes it as before.
local KEEP_EVENTS = { PLAYER_ENTERING_WORLD = true, ZONE_CHANGED_NEW_AREA = true,
                      UPDATE_ALL_UI_WIDGETS = true, UPDATE_UI_WIDGET = true }

local function InDungeon()
    local inInstance, kind = IsInInstance()
    return inInstance and (kind == "party" or kind == "raid")
end

local function AllowInDungeons(map)
    local gameToggle = map.Toggle
    if gameToggle then
        function map:Toggle(...)
            if not InDungeon() then return gameToggle(self, ...) end
            if self:IsShown() then
                SetCVar("showBattlefieldMinimap", "0")
                self:Hide()
            else
                SetCVar("showBattlefieldMinimap", "2")
                self:Show()
            end
        end
    end
    local gameOnEvent = map:GetScript("OnEvent")
    if not (gameOnEvent and MapCanvasMixin and MapCanvasMixin.OnEvent) then return end
    map:SetScript("OnEvent", function(self, event, ...)
        if KEEP_EVENTS[event] and InDungeon() then
            local entering = event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA"
            if not entering or Cfg().showInside then
                MapCanvasMixin.OnEvent(self, event, ...)
                if entering then
                    local mapID = MapUtil.GetDisplayableMapForPlayer()
                    if mapID then self:SetMapID(mapID) end
                    self:Show()
                end
                return
            end
        end
        return gameOnEvent(self, event, ...)
    end)
end

function ns.SetupDungeon(map)
    local T = Enum and Enum.UIMapType or {}
    for _, k in ipairs({ "Dungeon", "Micro", "Orphan" }) do
        if T[k] then SMALL_MAP_TYPES[T[k]] = true end
    end
    CreateOverlay(map)
    pcall(AllowInDungeons, map)

    local events = CreateFrame("Frame")
    -- (no combat log: on this client it's off-limits to addons, and even
    -- registering or unregistering it is a forbidden action. Kills come from
    -- ENCOUNTER_END and BOSS_KILL.)
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
                         "ENCOUNTER_END", "BOSS_KILL", "PLAYER_LOGOUT", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        pcall(events.RegisterEvent, events, e)
    end
    events:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_LOGOUT" then
            GiveBack()  -- never log out with the minimap borrowed
            return
        end
        if event == "PLAYER_REGEN_DISABLED" then
            -- just before the combat lock: the last moment it may be moved
            GiveBack()
            pcall(UpdateFallback, map)
            return
        end
        if event == "PLAYER_REGEN_ENABLED" then
            pcall(UpdateFallback, map)  -- back to the minimap view, if that's the choice
            return
        end
        if event == "ENCOUNTER_END" then
            local _, encounterName, _, _, success = ...
            if success == 1 then MarkKilled(encounterName) end
            return
        end
        if event == "BOSS_KILL" then
            local _, encounterName = ...
            MarkKilled(encounterName)
            return
        end
        if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
            UpdateRun()
        end
        if event == "PLAYER_ENTERING_WORLD" and Cfg().showInside then
            local inInstance, kind = IsInInstance()
            if inInstance and (kind == "party" or kind == "raid") and not map:IsShown() then map:Show() end
        end
        -- the game also resets the map on these; act just after it
        C_Timer.After(0.2, ns.UpdateDungeon)
    end)
    -- closing the map gives the minimap back straight away (and ends a preview)
    map:HookScript("OnHide", function()
        GiveBack()
        zoneView = nil
        EndPreview()
    end)

    -- dungeon entrances on zone maps: click one to see its map
    local provider = CreateFromMixins(BFIDungeonProviderMixin)
    if pcall(map.AddDataProvider, map, provider) then
        function ns.RedrawDungeonEntrances()
            if map:IsShown() then ns.Safe("Dungeon entrances", provider.Draw, provider) end
        end
    end

    -- caves have no zone event at every entrance, so check now and then too
    local elapsed = 0
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 2 or not map:IsVisible() then return end
        elapsed = 0
        ns.UpdateDungeon()
    end)
end
