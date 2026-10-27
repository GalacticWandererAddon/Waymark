local _, ns = ...

-- Caves (open world, not instances). Inside a cave the game's map system gives
-- up and the Battlefield Map falls back to the continent. We find the cave from
-- your world position (UnitPosition) against cave boxes in world yards, so the
-- map system doesn't need to know about it:
--  * caves with a Blizzard cave map (OpenMap's Caves.lua: Wailing Caverns,
--    Skull Rock...): the Battlefield Map is switched to that map, so zoom, pins
--    and detail keep working; if the game won't place your arrow on it, we
--    draw one from your world position; with cave.minimapStyleEverywhere, the
--    minimap-style view below instead, from Data\CaveMinimapExtra.lua (made by
--    tools\cave_minimap_extra.py from the game's files)
--  * every other cave (OpenMap's CaveMinimap.lua: 248 caves): our own
--    minimap-style view of the cave's minimap pictures, centred on you
-- Data: OpenMap (MIT, see LICENSES/OpenMap-LICENSE.txt).

local function Cfg() return ns.db.cave end

-- World position ----------------------------------------------------------------

-- UnitPosition gives two horizontal numbers; which is north-south (the data's X)
-- and which east-west (Y) is settled the first time one order lands in a cave
local swap  -- nil = not known yet

local function RawPos()
    if IsInInstance() then return end
    local ok, a, b, _, cont = pcall(UnitPosition, "player")
    if not (ok and type(a) == "number" and type(b) == "number" and type(cont) == "number") then return end
    return a, b, cont
end

local function Contains(c, cont, x, y, minX, minY, maxX, maxY)
    return c == cont and x >= minX and x <= maxX and y >= minY and y <= maxY
end

-- the Blizzard cave map containing (x, y): the smallest box wins (a floor or
-- inner part), then the lowest ID
local function BlizzardCaveAt(cont, x, y)
    local best, bestArea
    for id, c in pairs(ns.MapCaves or {}) do
        if Contains(c[2], cont, x, y, c[3], c[4], c[5], c[6]) then
            local area = (c[5] - c[3]) * (c[6] - c[4])
            if not best or area < bestArea or (area == bestArea and id < best) then best, bestArea = id, area end
        end
    end
    return best
end

local function MinimapCaveAt(cont, x, y)
    for i, c in ipairs(ns.MapCaveMinimap or {}) do
        if Contains(c[1], cont, x, y, c[2], c[3], c[4], c[5]) then return i end
    end
end

-- minimap pictures for the caves that have a Blizzard map (CaveMinimapExtra.lua,
-- named after the cave first, then smallest box first). Entries marked building
-- (c[7]: a house or tower that only lies in the cave's box) are never the cave.
local function ExtraCaveAt(cont, x, y)
    for i, c in ipairs(ns.MapCaveMinimapExtra or {}) do
        if not c[7] and Contains(c[1], cont, x, y, c[2], c[3], c[4], c[5]) then return i end
    end
end

-- inside one of those buildings (and none of the cave's own pictures): you're
-- in a house in the cave's box, not in the cave (the Grizzled Den's box takes
-- in part of Kharanos)
local function InBuilding(cont, x, y)
    local building = false
    for _, c in ipairs(ns.MapCaveMinimapExtra or {}) do
        if Contains(c[1], cont, x, y, c[2], c[3], c[4], c[5]) then
            if not c[7] then return false end
            building = true
        end
    end
    return building
end

local function AnyCaveAt(cont, x, y)
    local id = BlizzardCaveAt(cont, x, y)
    if id then return "blizzard", id end
    local i = MinimapCaveAt(cont, x, y)
    if i then return "minimap", i end
end

-- world X (north-south), Y (east-west), continent, or nil
local function WorldPos()
    local a, b, cont = RawPos()
    if not a then return end
    if swap == nil then
        -- not known yet: whichever order is in a cave settles it
        if AnyCaveAt(cont, a, b) then swap = false
        elseif AnyCaveAt(cont, b, a) then swap = true
        else return a, b, cont end  -- (no cave either way: order doesn't matter yet)
    end
    if swap then return b, a, cont end
    return a, b, cont
end

local function Facing()
    local ok, f = pcall(GetPlayerFacing)
    return ok and type(f) == "number" and f or nil
end

-- Our own arrow on a Blizzard cave map (when the game gives no position there) ---

local arrowHost, arrowTex

local function UpdateArrow(map, id, x, y)
    local c = ns.MapCaves[id]
    local pos = C_Map.GetPlayerMapPosition(id, "player")
    if pos and pos.x and (pos.x > 0 or pos.y > 0) then arrowHost:Hide() return end  -- the game's own arrow works
    -- the art covers its world box: left edge = max Y (west), top = max X (north)
    local nx = (c[6] - y) / (c[6] - c[4])
    local ny = (c[5] - x) / (c[5] - c[3])
    local canvas = map:GetCanvas()
    local scale = map:GetCanvasScale() or 1
    arrowTex:ClearAllPoints()
    arrowTex:SetPoint("CENTER", arrowHost, "TOPLEFT", nx * canvas:GetWidth(), -ny * canvas:GetHeight())
    arrowTex:SetSize(Cfg().arrowSize / scale, Cfg().arrowSize / scale)
    local f = Facing()
    if f then arrowTex:SetRotation(f) end
    arrowHost:SetFrameLevel(math.min(select(2, ns.CanvasLevels(map)) + 10, 9000))
    arrowHost:Show()
end

-- Minimap-style view (caves without a Blizzard map) --------------------------------

local view, viewCanvas, viewArrow
local viewTextures, viewPool = {}, {}
local viewFor          -- cave index the pictures were laid out for
local refX, refY       -- world point at the canvas's centre

local function ReleasePictures()
    for _, t in ipairs(viewTextures) do t:Hide() viewPool[#viewPool + 1] = t end
    wipe(viewTextures)
    viewFor = nil
end

local function NewTexture()
    local tex = table.remove(viewPool) or viewCanvas:CreateTexture(nil, "ARTWORK")
    tex:SetRotation(0)
    tex:ClearAllPoints()
    viewTextures[#viewTextures + 1] = tex
    return tex
end

-- Canvas units are yards: right = east (falling Y), up = north (rising X).

-- a minimap cave's pictures (file, centre X, Y, side in yards, rotation, u1, v0),
-- each a square turned about its centre, lowest floor first
-- Seams between pictures (thin dark lines), two causes:
--  1. A texture rotates inside its own unrotated frame, so a picture turned by
--     anything but a right angle (WC's are ~96 degrees) had its corners cut
--     off, leaving thin wedges between neighbours. Fix: a frame big enough for
--     the turned picture (f = |cos| + |sin| times the side), with the texture
--     range widened by the same f, so the picture keeps its size; the extra is
--     transparent (clamp to black).
--  2. Smoothing blends a picture's outermost pixels with that transparent
--     border, a faint see-through outline. Fix: each picture drawn about a pixel
--     larger, so neighbours overlap; and where a right-angled picture fills its
--     square, its edge pixels are extended (CLAMP) instead of fading.
-- texture range shrunk ~4 px of 256: the picture grows ~2 px each way (2 px left
-- faint seams on WC's plain floor; still well under a yard at the edges)
local OVERLAP = 1 - 4 / 256

local function RightAngle(r)
    local q = r / (math.pi / 2)
    return math.abs(q - math.floor(q + 0.5)) < 0.01
end

-- (list = ns.MapCaveMinimap or ns.MapCaveMinimapExtra: the same format)
local function LayOutMinimap(list, index)
    local c = list[index]
    refX, refY = (c[2] + c[4]) / 2, (c[3] + c[5]) / 2
    local p = c[6]
    local n = #p / 7
    for i = 1, n do
        local j = (i - 1) * 7
        local u1, v0, rot, side = p[j + 6], p[j + 7], p[j + 5], p[j + 4]
        local square = RightAngle(rot)
        local f = square and 1 or (math.abs(math.cos(rot)) + math.abs(math.sin(rot)))
        local wrapH = (square and u1 <= 1) and "CLAMP" or "CLAMPTOBLACKADDITIVE"
        local wrapV = (square and v0 >= 0) and "CLAMP" or "CLAMPTOBLACKADDITIVE"
        -- the texture range around its centre, widened by f, shrunk for the overlap
        local cu, hu = u1 / 2, u1 / 2 * f * OVERLAP
        local cv, hv = (v0 + 1) / 2, (1 - v0) / 2 * f * OVERLAP
        local tex = NewTexture()
        tex:SetDrawLayer("ARTWORK", math.max(-8, math.min(7, math.floor((i - 1) * 16 / n) - 8)))
        tex:SetTexture(p[j + 1], wrapH, wrapV, "TRILINEAR")
        tex:SetTexCoord(cu - hu, cu + hu, cv - hv, cv + hv)
        tex:SetRotation(rot)
        tex:SetSize(side * f, side * f)
        tex:SetPoint("CENTER", viewCanvas, "CENTER", refY - p[j + 3], p[j + 2] - refX)
        tex:Show()
    end
end

-- Blizzard's cave map art, for when this client doesn't know the map itself:
-- 12 tiles of 256 px (4 x 3), the picture the top-left 1002 x 668 of them,
-- covering the cave's world box (top-left corner = max X north, max Y west)
local function LayOutMicro(id)
    local c = ns.MapCaves[id]
    local minX, minY, maxX, maxY = c[3], c[4], c[5], c[6]
    refX, refY = (minX + maxX) / 2, (minY + maxY) / 2
    local W, H = maxY - minY, maxX - minX             -- yards across, yards down
    local tw, th = W * 256 / 1002, H * 256 / 668      -- one tile in yards
    local left, top = refY - maxY, maxX - refX        -- the picture's top-left on the canvas
    for n, fid in ipairs(c[11]) do
        local col, row = (n - 1) % 4, math.floor((n - 1) / 4)
        local pw, ph = math.min(256, 1002 - col * 256), math.min(256, 668 - row * 256)
        local tex = NewTexture()
        tex:SetDrawLayer("ARTWORK", 0)
        tex:SetTexture(fid, nil, nil, "TRILINEAR")
        tex:SetTexCoord(0, pw / 256, 0, ph / 256)
        tex:SetSize(tw * pw / 256, th * ph / 256)
        tex:SetPoint("TOPLEFT", viewCanvas, "CENTER", left + col * tw, top - row * th)
        tex:Show()
    end
end

-- half the cave's size in yards (east-west, north-south), around the canvas centre
local artHW, artHH = 1, 1
local coverZoom = 0.3  -- the least zoom that still fills the frame (no gaps)
local MAX_ZOOM = 8         -- px per yard: the closest the view goes (the wheel's limit too)
local MAX_FILL_ZOOM = 3    -- px per yard: filling the frame is forced only up to this
local MIN_ZOOM = 0.25      -- px per yard: the wheel's furthest out

local function LayOut(kind, id)
    ReleasePictures()
    if kind == "micro" then
        LayOutMicro(id)
        local c = ns.MapCaves[id]
        artHW, artHH = (c[6] - c[4]) / 2, (c[5] - c[3]) / 2
    else
        local list = kind == "extra" and ns.MapCaveMinimapExtra or ns.MapCaveMinimap
        LayOutMinimap(list, id)
        local c = list[id]
        artHW, artHH = (c[5] - c[3]) / 2, (c[4] - c[2]) / 2
    end
    viewFor = id
end

local function Clamp(v, lo, hi)
    if lo > hi then return (lo + hi) / 2 end
    return math.max(lo, math.min(hi, v))
end

-- Panning by hand: drag with the left button. While panned the view stays where
-- you put it; 5 s after you let go it glides back to you. Right-click: back now.
local PAN_HOLD, PAN_RETURN = 5, 0.15  -- seconds held after letting go; glide speed per frame
local pan         -- { x, y } view centre (canvas yards) while panned by hand, or nil
local panUntil = 0
local drag        -- { cursorX, cursorY, startX, startY } during a drag
local lastK, lastCx, lastCy = 1, 0, 0

local function CursorInView()
    local x, y = GetCursorPosition()
    local s = view:GetEffectiveScale()
    return x / s, y / s
end

-- The view follows you like the zone map does: the cave scrolls, but never past
-- its edges, so near an edge the arrow moves instead and the art always fills
-- the frame. "Keep the cave still": the whole cave fitted, only the arrow moves.
local function UpdateView(x, y)
    local c = Cfg()
    local vw, vh = view:GetWidth(), view:GetHeight()
    if not (vw and vw > 0 and vh and vh > 0) then return end
    local u, v = refY - y, x - refX  -- you, on the canvas (yards from its centre)

    local k, cx, cy
    if c.still then
        -- the whole cave fitted, but a small one isn't blown up past MAX_ZOOM
        k = math.min(vw / (2 * artHW), vh / (2 * artHH), MAX_ZOOM)
        cx, cy = 0, 0
        pan, drag = nil, nil
    else
        -- the frame is kept filled (no dark edges) only while that takes a sensible
        -- zoom: a small cave would need a huge one, so it gets edges instead and
        -- your own zoom
        coverZoom = math.max(vw / (2 * artHW), vh / (2 * artHH))
        -- (docked over the minimap, Dock.lua: the zoom scaled to the square's
        -- width against your map's, so it shows as much of the cave)
        local fit = ns.DockViewFactor and ns.DockViewFactor(vw) or 1
        k = math.max(c.zoom * fit, math.min(coverZoom, MAX_FILL_ZOOM))
        local hw, hh = vw / (2 * k), vh / (2 * k)  -- half the view, in yards

        if drag then
            -- dragging right moves the cave right, so the view centre goes left
            local mx, my = CursorInView()
            pan = { x = drag.startX - (mx - drag.cursorX) / k, y = drag.startY - (my - drag.cursorY) / k }
        elseif pan and GetTime() > panUntil then
            -- held long enough: glide back towards you, then follow again
            pan.x = pan.x + (u - pan.x) * PAN_RETURN
            pan.y = pan.y + (v - pan.y) * PAN_RETURN
            if math.abs(u - pan.x) < 0.5 and math.abs(v - pan.y) < 0.5 then pan = nil end
        end

        local tx, ty = u, v
        if pan then tx, ty = pan.x, pan.y end
        cx = Clamp(tx, -artHW + hw, artHW - hw)
        cy = Clamp(ty, -artHH + hh, artHH - hh)
        if pan then pan.x, pan.y = cx, cy end  -- (no dragging past the edges)
    end
    lastK, lastCx, lastCy = k, cx, cy

    -- yards -> pixels: the canvas is scaled by k, its centre moved off by the view centre
    viewCanvas:SetScale(k)
    viewCanvas:ClearAllPoints()
    viewCanvas:SetPoint("CENTER", view, "CENTER", -cx, -cy)
    viewArrow:ClearAllPoints()
    viewArrow:SetPoint("CENTER", view, "CENTER", (u - cx) * k, (v - cy) * k)
    viewArrow:SetSize(c.arrowSize, c.arrowSize)
    local f = Facing()
    if f then viewArrow:SetRotation(f) end
end

-- the player arrow: the classic world map arrow if you chose it (cave.classicArrow),
-- else the modern one where the client has it, else the classic one anyway
local CLASSIC_ARROW = "Interface\\WorldMap\\WorldMapArrow"
local function SetArrowTexture(tex)
    if not Cfg().classicArrow then
        local atlas = "UI-HUD-Minimap-Arrow-Player"
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) and tex:SetAtlas(atlas) ~= false then
            return
        end
    end
    tex:SetTexture(CLASSIC_ARROW)
    tex:SetTexCoord(0, 1, 0, 1)  -- (an atlas set before leaves its own coordinates)
end

-- re-apply when the setting changes (called from Update)
local arrowStyle
local function ApplyArrowStyle()
    local want = Cfg().classicArrow and true or false
    if want == arrowStyle then return end
    arrowStyle = want
    if viewArrow then SetArrowTexture(viewArrow) end
    if arrowTex then SetArrowTexture(arrowTex) end
end

local function CreateView(map)
    local area = map.ScrollContainer or map
    view = CreateFrame("Frame", nil, area)
    view:SetAllPoints(area)
    view:SetFrameLevel(math.min(area:GetFrameLevel() + 5000, 9000))  -- over the continent map and its pins
    ns.caveView = view  -- (Dock.lua: see-through on the minimap face, its double-click)
    view:SetClipsChildren(true)
    view:EnableMouse(true)
    view:EnableMouseWheel(true)
    view:SetScript("OnMouseWheel", function(_, delta)
        local c = Cfg()
        -- (no further out than filling the frame, where that's forced: past that it
        -- wouldn't change)
        local least = math.max(MIN_ZOOM, math.min(coverZoom, MAX_FILL_ZOOM))
        c.zoom = math.max(least, math.min(MAX_ZOOM, c.zoom * (delta > 0 and 1.25 or 0.8)))
        if pan then panUntil = GetTime() + PAN_HOLD end  -- zooming a panned view keeps it panned
        if ns.RefreshControls then ns.RefreshControls() end
    end)
    view:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and not Cfg().still then
            local mx, my = CursorInView()
            drag = { cursorX = mx, cursorY = my, startX = lastCx, startY = lastCy }
        elseif button == "RightButton" then
            pan, drag = nil, nil  -- back to following you
        end
    end)
    view:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and drag then
            drag = nil
            panUntil = GetTime() + PAN_HOLD
        end
    end)
    local bg = view:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.04, 0.03, 1)

    viewCanvas = CreateFrame("Frame", nil, view)
    viewCanvas:SetSize(1, 1)

    -- the arrow and label get their own frame above the canvas: a child frame
    -- always draws over its parent's textures, so on `view` itself the cave
    -- art covered them
    local top = CreateFrame("Frame", nil, view)
    top:SetAllPoints(view)
    top:SetFrameLevel(viewCanvas:GetFrameLevel() + 5)

    viewArrow = top:CreateTexture(nil, "OVERLAY")
    SetArrowTexture(viewArrow)
    viewArrow:SetSize(Cfg().arrowSize, Cfg().arrowSize)
    viewArrow:SetPoint("CENTER")

    -- (the sub-zone name is shown by ZoneName.lua, in caves and everywhere else)
    view:Hide()
end

-- The art-style button ---------------------------------------------------------------

-- In a cave that has both Blizzard's map art and minimap pictures, a small
-- button on the map switches between them (cave.minimapStyleEverywhere)
local styleButton

local function CreateStyleButton(map)
    local area = map.ScrollContainer or map
    local b = CreateFrame("Button", nil, area, "BackdropTemplate")
    b:SetSize(96, 18)
    b:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", 6, 6)
    b:SetFrameLevel(math.min(area:GetFrameLevel() + 5100, 9100))  -- over the cave view
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
                    insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    b:SetBackdropColor(0.08, 0.06, 0.04, 0.85)
    b:SetBackdropBorderColor(0.75, 0.6, 0.35)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b:SetScript("OnClick", function()
        local c = Cfg()
        c.minimapStyleEverywhere = not c.minimapStyleEverywhere
        ns.OnSettingChanged("cave", "minimapStyleEverywhere")
    end)
    b:SetScript("OnEnter", function()
        GameTooltip:SetOwner(b, "ANCHOR_TOP")
        GameTooltip:AddLine("Cave art")
        GameTooltip:AddLine(Cfg().minimapStyleEverywhere and "Showing the minimap pictures. Click for Blizzard's cave map."
                            or "Showing Blizzard's cave map. Click for the minimap pictures.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    styleButton = b
    ns.debugFrames.caveStyleButton = b
end

-- shown when this cave has both kinds of art (and you want the button)
local function UpdateStyleButton(map, kind, cont, x, y)
    if not styleButton then return end
    local both = kind == "extra" or ((kind == "blizzard" or kind == "micro") and ExtraCaveAt(cont, x, y) ~= nil)
    if not (both and Cfg().styleButton ~= false) then
        styleButton:Hide()
        return
    end
    styleButton:SetScale(1 / math.max(0.1, map:GetScale()))  -- (its size on screen, like the map's buttons)
    styleButton.text:SetText(kind == "extra" and "Map art" or "Minimap style")
    styleButton:Show()
end

-- The state machine ---------------------------------------------------------------

local state = { kind = nil, id = nil }

-- whether the map shows a cave now (our view or Blizzard's cave map): the zone
-- map's area names don't belong on it (Explore.lua)
function ns.InCave() return state.kind ~= nil end
local switchedFrom    -- the map shown before we switched to a Blizzard cave map
local ourSetMap = false

local function SetMap(map, id)
    ourSetMap = true
    pcall(map.SetMapID, map, id)
    ourSetMap = false
end

local function Leave(map)
    pan, drag = nil, nil  -- the next cave starts on you
    -- (not while you browse another map: that one stays)
    if state.kind == "blizzard" and switchedFrom and not (ns.Browsing and ns.Browsing()) then
        local best = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        SetMap(map, best or switchedFrom)
    end
    switchedFrom = nil
    state.kind, state.id = nil, nil
    view:Hide()
    arrowHost:Hide()
end

local function Update(map)
    ApplyArrowStyle()
    -- browsing another map (Browse.lua): no cave until you're back on yours
    if ns.Browsing and ns.Browsing() then
        UpdateStyleButton(map, nil)
        if state.kind then Leave(map) end
        return
    end
    local x, y, cont = WorldPos()
    local kind, id
    if Cfg().enabled and x and IsIndoors() and map:IsVisible() and not InBuilding(cont, x, y) then
        kind, id = AnyCaveAt(cont, x, y)
        -- in a cave with a Blizzard map: its minimap pictures instead, if you
        -- want the minimap style everywhere (or no Blizzard maps) and we have them
        if kind == "blizzard" and (Cfg().minimapStyleEverywhere or not Cfg().blizzardMaps) then
            local i = ExtraCaveAt(cont, x, y)
            if i then kind, id = "extra", i end
        end
        if kind == "blizzard" and not Cfg().blizzardMaps then
            kind, id = nil, nil
            local i = MinimapCaveAt(cont, x, y)
            if i then kind, id = "minimap", i end
        end
        -- a Blizzard cave map this client doesn't know (switching to it shows
        -- nothing): draw its art ourselves in the view instead
        if kind == "blizzard" and not C_Map.GetMapInfo(id) then kind = "micro" end
    end
    UpdateStyleButton(map, kind, cont, x, y)
    if not kind then
        if state.kind then Leave(map) end
        return
    end

    if kind ~= state.kind or id ~= state.id then
        if state.kind then Leave(map) end
        state.kind, state.id = kind, id
        if kind == "blizzard" then
            switchedFrom = map:GetMapID()
        else
            LayOut(kind, id)
            view:Show()
        end
    end

    if kind == "blizzard" then
        if map:GetMapID() ~= id then SetMap(map, id) end
        UpdateArrow(map, id, x, y)
        view:Hide()
    else
        UpdateView(x, y)
    end
end

-- /bfi cave: what the client gives, to see what's possible
function ns.CaveProbe()
    local L = ns.Log
    local a, b, cont = RawPos()
    L("UnitPosition:", a and string.format("%.1f, %.1f", a, b) or "none", "continent", tostring(cont),
      "| indoors:", tostring(IsIndoors()), "| order:", swap == nil and "not known yet" or (swap and "swapped" or "as given"))
    if a then
        for _, try in ipairs({ { a, b, "as given" }, { b, a, "swapped" } }) do
            local kind, id = AnyCaveAt(cont, try[1], try[2])
            local name = kind == "blizzard" and ns.MapCaves[id][1]
                or kind == "minimap" and ("minimap cave #" .. id) or "-"
            L("  " .. try[3] .. ":", kind or "no cave", name)
        end
    end
    L("now showing:", tostring(state.kind), tostring(state.id), "| map", tostring(BattlefieldMapFrame and BattlefieldMapFrame:GetMapID()))
    if state.kind == "blizzard" then
        local info = C_Map.GetMapInfo(state.id)
        local pos = C_Map.GetPlayerMapPosition(state.id, "player")
        L("  cave map:", info and info.name or "unknown to this client", "| game's position on it:",
          pos and string.format("%.3f, %.3f", pos.x, pos.y) or "none (we draw the arrow)")
    elseif state.kind == "micro" then
        L("  drawing Blizzard's cave art ourselves: this client doesn't know map " .. tostring(state.id)
          .. string.format(" | view zoom %.2f px/yd, %d textures", Cfg().zoom, #viewTextures))
    elseif state.kind == "minimap" or state.kind == "extra" then
        L(string.format("  minimap pictures%s: %d textures, view zoom %.2f px/yd",
          state.kind == "extra" and " (CaveMinimapExtra #" .. state.id .. ")" or "", #viewTextures, Cfg().zoom))
    end
end

function ns.SetupCave(map)
    CreateView(map)
    CreateStyleButton(map)

    local canvas = map:GetCanvas()
    arrowHost = CreateFrame("Frame", nil, canvas)
    arrowHost:SetAllPoints(canvas)
    arrowTex = arrowHost:CreateTexture(nil, "OVERLAY")
    SetArrowTexture(arrowTex)
    arrowHost:Hide()

    -- the game puts its own map back on zone events; follow up right away
    hooksecurefunc(map, "SetMapID", function(_, newID)
        if not ourSetMap and state.kind == "blizzard" and newID ~= state.id
           and not (ns.Browsing and ns.Browsing()) then
            C_Timer.After(0, function() if state.kind == "blizzard" then SetMap(map, state.id) end end)
        end
    end)

    local ticker = CreateFrame("Frame")
    local elapsed = 0
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        -- every frame while a view follows you, twice a second otherwise
        if state.kind == nil and elapsed < 0.5 then return end
        elapsed = 0
        local ok, err = pcall(Update, map)
        if not ok and not ns.caveErrorShown then
            ns.caveErrorShown = true
            ns.Log("cave view error:", err)
        end
    end)
end

function ns.UpdateCave()
    if BattlefieldMapFrame and view then pcall(Update, BattlefieldMapFrame) end
end
