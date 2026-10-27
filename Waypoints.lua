local _, ns = ...

-- TomTom waypoints on the Battlefield Map, plus Ctrl+Right-click to add one.
-- A TomTom waypoint is { mapID, x, y, title = ... } with 0-1 coordinates.

local function Cfg() return ns.db.waypoints end

BFIWaypointPinMixin = CreateFromMixins(MapCanvasPinMixin)
BFIWaypointPinMixin.CheckMouseButtonPassthrough = ns.SafePassthrough  -- see Pin.lua

function BFIWaypointPinMixin:OnLoad()
    if self.UseFrameLevelType then
        pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_BFI_QUESTIE")
    end
end

-- fixed on-screen size, same approach as the Questie pins
function BFIWaypointPinMixin:ApplyCurrentScale()
    local map = self:GetMap()
    local canvasScale = map and map.GetCanvasScale and map:GetCanvasScale() or 1
    if not canvasScale or canvasScale <= 0 then canvasScale = 1 end
    self:SetScale(ns.PinScale("waypoints", Cfg().scale) / canvasScale)  -- (PinScale: town view, small map)
    ns.ReanchorPin(self, map)
end

function BFIWaypointPinMixin:ApplyCurrentAlpha()
    self:SetAlpha(ns.PinAlpha("waypoints"))
end

function BFIWaypointPinMixin:OnAcquired(uid)
    self.uid = uid
    self:ApplyCurrentScale()
    self:ApplyCurrentAlpha()
    self:SetPosition(uid[2], uid[3])
end

function BFIWaypointPinMixin:OnEnter()
    local uid = self.uid
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(uid.title or "TomTom waypoint")
    GameTooltip:AddLine(string.format("%.1f, %.1f", uid[2] * 100, uid[3] * 100), 1, 1, 1)
    GameTooltip:AddLine("Left-click: point the arrow here", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click: remove", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function BFIWaypointPinMixin:OnLeave()
    GameTooltip:Hide()
end
-- the map wires a pin's mouse-over to these (see Pin.xml)
BFIWaypointPinMixin.OnMouseEnter = BFIWaypointPinMixin.OnEnter
BFIWaypointPinMixin.OnMouseLeave = BFIWaypointPinMixin.OnLeave

function BFIWaypointPinMixin:OnMouseUp(button)
    if not TomTom then return end
    local uid = self.uid
    if button == "RightButton" then
        pcall(TomTom.RemoveWaypoint, TomTom, uid)
        GameTooltip:Hide()
        if ns.RedrawWaypoints then ns.RedrawWaypoints() end
    elseif TomTom.SetCrazyArrow then
        local arrival = TomTom.profile and TomTom.profile.arrow and TomTom.profile.arrow.arrival or 15
        pcall(TomTom.SetCrazyArrow, TomTom, uid, arrival, uid.title)
    end
end

-- Provider --------------------------------------------------------------

BFIWaypointProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)

function BFIWaypointProviderMixin:RemoveAllData()
    local map = self:GetMap()
    pcall(map.RemoveAllPinsByTemplate, map, "BFIWaypointPinTemplate")
end

function BFIWaypointProviderMixin:RefreshAllData()
    self:RemoveAllData()
    local map = self:GetMap()
    local mapID = map:GetMapID()
    if not (mapID and ns.IsShown("waypoints") and TomTom and TomTom.waypoints) then return end
    for _, uid in pairs(TomTom.waypoints[mapID] or {}) do
        if type(uid) == "table" and uid[2] and uid[3] then
            pcall(map.AcquirePin, map, "BFIWaypointPinTemplate", uid)
        end
    end
end

function BFIWaypointProviderMixin:OnMapChanged()
    self:RefreshAllData()
end

-- TomTom has no "waypoints changed" callback for us, so compare once a second
local function Signature(mapID)
    local list = TomTom and TomTom.waypoints and TomTom.waypoints[mapID]
    if not list then return tostring(mapID) end
    local parts = { mapID }
    for key in pairs(list) do parts[#parts + 1] = key end
    table.sort(parts, function(a, b) return tostring(a) < tostring(b) end)
    return table.concat(parts, "|")
end

-- Ctrl+Right-click on the map adds a waypoint there
local function OnMapMouseUp(map, button)
    if button ~= "RightButton" or not IsControlKeyDown() then return end
    if not (Cfg().clickToAdd and TomTom and TomTom.AddWaypoint) then return end
    local mapID = map:GetMapID()
    local ok, x, y = pcall(map.GetNormalizedCursorPosition, map)
    if not (ok and mapID and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1) then return end
    pcall(TomTom.AddWaypoint, TomTom, mapID, x, y, { title = "Battlefield Map", from = "BattlefieldInfo" })
    if ns.RedrawWaypoints then ns.RedrawWaypoints() end
end

function ns.SetupWaypoints(map)
    if not TomTom then return end  -- the options still show, they just do nothing
    local provider = CreateFromMixins(BFIWaypointProviderMixin)
    local ok, err = pcall(map.AddDataProvider, map, provider)
    if not ok then
        ns.Log("TomTom layer failed:", err)
        return
    end
    function ns.RedrawWaypoints() pcall(provider.RefreshAllData, provider) end

    if map.ScrollContainer then
        map.ScrollContainer:HookScript("OnMouseUp", function(_, button) OnMapMouseUp(map, button) end)
    end

    local ticker, elapsed, lastSig = CreateFrame("Frame"), 0, nil
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 1 or not map:IsVisible() then return end
        elapsed = 0
        local sig = Signature(map:GetMapID()) .. tostring(ns.IsShown("waypoints"))
        if sig ~= lastSig then
            lastSig = sig
            ns.RedrawWaypoints()
        end
    end)
    ns.Log("TomTom layer active")
end
