local _, ns = ...

-- GatherMate2 nodes (herbs, ore, fishing, treasure...) on the Battlefield Map,
-- read through GatherMate2's own functions, with its own icons and node filters.
-- With "follow" on, a type also has to be visible by GatherMate's own rules
-- (always / with the profession / while tracking), as on its world map.

local TEMPLATE = "BFIGatherPinTemplate"

ns.GATHER_TYPES = {
    { key = "Herb Gathering", label = "Herbs" },
    { key = "Mining",         label = "Mining" },
    { key = "Fishing",        label = "Fishing" },
    { key = "Treasure",       label = "Treasure" },
}  -- (gas clouds, archaeology and logging: not in this game, left out)

local function Cfg() return ns.db.gather end
local function GM() return _G.GatherMate2 end

-- Pin -----------------------------------------------------------------------

BFIGatherPinMixin = CreateFromMixins(MapCanvasPinMixin)
BFIGatherPinMixin.CheckMouseButtonPassthrough = ns.SafePassthrough  -- see Pin.lua

function BFIGatherPinMixin:OnLoad()
    if self.UseFrameLevelType then
        pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_BFI_GATHER")
    end
end

function BFIGatherPinMixin:ApplyCurrentScale()
    local map = self:GetMap()
    local canvasScale = map and map.GetCanvasScale and map:GetCanvasScale() or 1
    if not canvasScale or canvasScale <= 0 then canvasScale = 1 end
    self:SetScale(ns.PinScale("gather", Cfg().scale) / canvasScale)  -- (PinScale: town view, small map)
    ns.ReanchorPin(self, map)
end

function BFIGatherPinMixin:ApplyCurrentAlpha()
    self:SetAlpha(ns.PinAlpha("gather"))
end

function BFIGatherPinMixin:OnAcquired(x, y, nodeID, nodeType)
    local gm = GM()
    nodeID = gm.nodeIDReplacementMap and gm.nodeIDReplacementMap[nodeID] or nodeID
    self.nodeType = nodeType
    self.nodeName = gm:GetNameForNode(nodeType, nodeID)
    local tex = gm.nodeTextures and gm.nodeTextures[nodeType] and gm.nodeTextures[nodeType][nodeID]
    self.Icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
    self:ApplyCurrentScale()
    self:ApplyCurrentAlpha()
    self:SetPosition(x, y)
end

function BFIGatherPinMixin:OnEnter()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.nodeName or "?")
    GameTooltip:AddLine(self.nodeType, 1, 1, 1)
    ns.PinHints()
    GameTooltip:Show()
end

function BFIGatherPinMixin:OnLeave()
    GameTooltip:Hide()
end
-- the map wires a pin's mouse-over to these (see Pin.xml)
BFIGatherPinMixin.OnMouseEnter = BFIGatherPinMixin.OnEnter
BFIGatherPinMixin.OnMouseLeave = BFIGatherPinMixin.OnLeave

function BFIGatherPinMixin:OnMouseUp(button)
    if button == "RightButton" then ns.PinMenu(self, nil, self.nodeName) return end  -- (its menu: Controls.lua)
    if ns.PinAltClick then ns.PinAltClick(self, button) end  -- line target (Line.lua)
end

-- Provider ------------------------------------------------------------------

BFIGatherProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)

function BFIGatherProviderMixin:RemoveAllData()
    local map = self:GetMap()
    pcall(map.RemoveAllPinsByTemplate, map, TEMPLATE)
end

function BFIGatherProviderMixin:RefreshAllData()
    self:Draw()
end

function BFIGatherProviderMixin:OnMapChanged()
    self:Draw()
end

function BFIGatherProviderMixin:Draw()
    self:RemoveAllData()
    local gm = GM()
    local map = self:GetMap()
    local mapID = map:GetMapID()
    if not (gm and mapID and ns.IsShown("gather") and gm.GetNodesForZone) then return end
    if gm.phasing and gm.phasing[mapID] then mapID = gm.phasing[mapID] end

    local c = Cfg()
    if c.follow then
        -- GatherMate works out what's visible (professions, tracking) when its
        -- display updates; ask it to now so Visible is current
        local ok, display = pcall(gm.GetModule, gm, "Display", true)
        if ok and display and display.UpdateVisibility then pcall(display.UpdateVisibility, display) end
    end

    for _, t in ipairs(ns.GATHER_TYPES) do
        local wanted = c.types[t.key] and (not c.follow or (gm.Visible and gm.Visible[t.key]))
        if wanted and gm.gmdbs and gm.gmdbs[t.key] then
            for coord, nodeID in gm:GetNodesForZone(mapID, t.key) do
                local x, y = gm:DecodeLoc(coord)
                pcall(map.AcquirePin, map, TEMPLATE, x, y, nodeID, t.key)
            end
        end
    end
end

-- How many gathering nodes (types you've switched on, and GatherMate would show)
-- are within `yards` of a point. For auto-zoom and the Gathering profile; reads
-- GatherMate's data directly, so it works whether or not the layer is drawn.
function ns.GatherNodesNear(mapID, px, py, yards)
    local gm = GM()
    if not (gm and gm.GetNodesForZone and gm.gmdbs and px) then return 0 end
    local w, h = ns.MapYards(mapID)
    if not w then return 0 end
    local zone = gm.phasing and gm.phasing[mapID] or mapID
    local c, n, r2 = Cfg(), 0, yards * yards
    for _, t in ipairs(ns.GATHER_TYPES) do
        if c.types[t.key] and (not c.follow or (gm.Visible and gm.Visible[t.key])) and gm.gmdbs[t.key] then
            -- (run the iterator to the end: GatherMate recycles its state when it finishes)
            for coord in gm:GetNodesForZone(zone, t.key) do
                local x, y = gm:DecodeLoc(coord)
                local dx, dy = (x - px) * w, (y - py) * h
                if dx * dx + dy * dy <= r2 then n = n + 1 end
            end
        end
    end
    return n
end

function ns.SetupGather(map)
    if not GM() then return end
    local provider = CreateFromMixins(BFIGatherProviderMixin)
    local ok, err = pcall(map.AddDataProvider, map, provider)
    if not ok then
        ns.Log("GatherMate layer failed:", err)
        return
    end
    function ns.RedrawGather()
        if map:IsShown() then pcall(provider.Draw, provider) end
    end

    -- redraw when GatherMate's data or settings change (its AceEvent messages)
    local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
    if AceEvent then
        local listener = {}
        AceEvent:Embed(listener)
        local function Redraw() ns.RedrawGather() end
        for _, msg in ipairs({ "GatherMate2NodeAdded", "GatherMate2NodeDeleted", "GatherMate2Cleanup", "GatherMate2ConfigChanged" }) do
            listener:RegisterMessage(msg, Redraw)
        end
    end
end
