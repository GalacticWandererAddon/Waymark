local _, ns = ...

-- A line from you to a target on the Battlefield Map, with the distance.
-- Its target: your target, if it's in your group (the game only gives positions of group members, so not
-- of NPCs or other players).
-- (pins don't pick it: no Alt-click or menu row, 2026-11-01; ns.LineTargetClick is still there for anything
-- that wants to set one)
-- (2026-11-15, the user: the line to "the nearest objective spot" is out of the addon, and with it the
-- "Line aims at" settings. line.groupTarget and line.nearestSpot are no longer read: the line shown is the
-- line to your group target.)

local function Cfg() return ns.db.line end

local host, line, dot, label, labelFrame
local locked  -- { mapID, x, y, name } from an Alt-click

function ns.LineTargetClick(pin)
    local map = pin:GetMap()
    if not (map and pin.normalizedX) then return false end
    local mapID = map:GetMapID()
    if locked and locked.mapID == mapID
       and math.abs(locked.x - pin.normalizedX) < 0.0005 and math.abs(locked.y - pin.normalizedY) < 0.0005 then
        locked = nil  -- same pin again: clear
    else
        local name = pin.questName or (pin.info and pin.info.name) or (pin.POI and pin.POI.name) or pin.nodeName
        locked = { mapID = mapID, x = pin.normalizedX, y = pin.normalizedY, name = name }
    end
    if ns.UpdateLine then ns.UpdateLine() end
    return true
end

local function FindTarget(map, mapID)
    if locked and locked.mapID == mapID then return locked.x, locked.y, locked.name end
    if UnitExists("target") and (UnitInParty("target") or UnitInRaid("target")) then
        local pos = C_Map.GetPlayerMapPosition(mapID, "target")
        if pos and pos.x and (pos.x > 0 or pos.y > 0) then return pos.x, pos.y, UnitName("target") end
    end
end

-- yards between two points on the map, from the game's world positions
local function Yards(mapID, ax, ay, bx, by)
    if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    local ok1, c1, p1 = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(ax, ay))
    local ok2, c2, p2 = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(bx, by))
    if not (ok1 and ok2 and p1 and p2 and c1 == c2) then return end
    local x1, y1 = p1:GetXY()
    local x2, y2 = p2:GetXY()
    return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
end

function ns.UpdateLine()
    local map = BattlefieldMapFrame
    if not (host and map) then return end
    if not (ns.IsShown("line") and map:IsVisible()) then host:Hide() return end

    local mapID = map:GetMapID()
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not (pos and pos.x) or (pos.x == 0 and pos.y == 0) then host:Hide() return end
    local tx, ty, name = FindTarget(map, mapID, pos.x, pos.y)
    if not tx then host:Hide() return end

    local canvas = map:GetCanvas()
    local W, H = canvas:GetWidth(), canvas:GetHeight()
    local scale = map:GetCanvasScale() or 1
    local c = Cfg()

    line:SetStartPoint("TOPLEFT", host, pos.x * W, -pos.y * H)
    line:SetEndPoint("TOPLEFT", host, tx * W, -ty * H)
    line:SetThickness(c.thickness / scale)  -- same on screen at any zoom
    dot:ClearAllPoints()
    dot:SetPoint("CENTER", host, "TOPLEFT", tx * W, -ty * H)
    dot:SetSize(10 / scale, 10 / scale)

    local yards = Yards(mapID, pos.x, pos.y, tx, ty)
    -- the label sits on its own frame, scaled back so the text stays readable
    labelFrame:SetScale(1 / scale)
    labelFrame:ClearAllPoints()
    labelFrame:SetPoint("BOTTOM", dot, "TOP", 0, 2)
    label:SetText((name and (name .. "  ") or "") .. (yards and string.format("%d yd", yards) or ""))

    host:SetAlpha(c.alpha)
    -- on top of the map art and every pin (the explored-area art is itself a
    -- pin around level 2000, which hid the line before)
    local _, top = ns.CanvasLevels(map)
    local want = math.min(top + 5, 9000)
    if host:GetFrameLevel() ~= want then host:SetFrameLevel(want) end
    host:Show()
end

function ns.SetupLine(map)
    local canvas = map:GetCanvas()
    host = CreateFrame("Frame", nil, canvas)
    host:SetAllPoints(canvas)
    host:SetFrameLevel(canvas:GetFrameLevel() + 1900)  -- over the map art, under the pins
    host:Hide()

    line = host:CreateLine(nil, "OVERLAY")
    line:SetColorTexture(1, 0.82, 0.2, 1)

    dot = host:CreateTexture(nil, "OVERLAY")
    dot:SetTexture("Interface\\Minimap\\UI-Minimap-Ping-Center")
    dot:SetVertexColor(1, 0.82, 0.2, 1)

    labelFrame = CreateFrame("Frame", nil, host)
    labelFrame:SetSize(1, 1)
    label = labelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOM")

    map:HookScript("OnHide", function() host:Hide() end)

    local elapsed = 0
    local ticker = ns.TimedFrame("Line tick")
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < ns.Tick(0.1) then return end
        elapsed = 0
        pcall(ns.UpdateLine)
    end)
end
