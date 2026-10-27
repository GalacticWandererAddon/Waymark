local _, ns = ...

-- RareScanner rares, treasures and events on the Battlefield Map.
--
-- RareScanner keeps its data private, and its own pins read WorldMapFrame's zoom
-- directly, so they can't be added here as-is. Instead we run a copy of its world
-- map provider against a stand-in map that records every pin it asks for. That way
-- RareScanner does all its own filtering (hidden rares, looted treasures, zone
-- filters) and we draw the result with our own pins.

local TEMPLATE = "BFIRarePinTemplate"
local REFRESH_SECONDS = 10  -- rares come and go, but not every second

local function Cfg() return ns.db.rares end

-- An object that accepts any method call and returns itself, for the pin
-- methods RareScanner calls on what AcquirePin returns (animations, overlays)
local Null
Null = setmetatable({}, {
    __index = function() return Null end,
    __call = function() return Null end,
})

local hiddenFrame = { IsShown = function() return false end }

local capture = { mapID = nil, list = nil }

local proxyMap = setmetatable({
    GetMapID = function() return capture.mapID end,
    AcquirePin = function(_, template, POI)
        if capture.list and (template == "RSEntityPinTemplate" or template == "RSGroupPinTemplate") then
            capture.list[#capture.list + 1] = POI
        end
        return Null
    end,
    RemoveAllPinsByTemplate = function() end,
    EnumeratePinsByTemplate = function() return function() return nil end end,
    GetMapFrame = function() return hiddenFrame end,  -- "not shown": skips its animations
}, {
    -- anything else RareScanner might call on its map does nothing
    __index = function() return function() return Null end end,
})

local rsProvider

-- RareScanner stores coordinates as 0-1, or as whole numbers (4523 = 0.4523)
local function FixCoord(c)
    c = tonumber(c)
    if not c then return nil end
    if c > 1 then c = c / 10000 end
    return c
end

-- RareScanner reuses its result tables on the next call, so keep our own copies
local function CopyPOI(POI)
    local copy = {}
    for k, v in pairs(POI) do copy[k] = v end
    if POI.POIs then
        copy.POIs = {}
        for i, child in ipairs(POI.POIs) do copy.POIs[i] = child end
    end
    return copy
end

local function CollectPOIs(mapID)
    if not rsProvider then return {} end
    local list = {}
    capture.mapID, capture.list = mapID, list
    local ok, err = pcall(rsProvider.RefreshAllData, rsProvider)
    capture.mapID, capture.list = nil, nil
    if not ok then return nil, err end

    local out = {}
    for _, POI in ipairs(list) do
        local x, y = FixCoord(POI.x), FixCoord(POI.y)
        if x and y then
            out[#out + 1] = { POI = CopyPOI(POI), x = x, y = y }
        end
    end
    return out
end

-- Pin -------------------------------------------------------------------

BFIRarePinMixin = CreateFromMixins(MapCanvasPinMixin)
BFIRarePinMixin.CheckMouseButtonPassthrough = ns.SafePassthrough  -- see Pin.lua

function BFIRarePinMixin:OnLoad()
    if self.UseFrameLevelType then
        pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_BFI_RARES")
    end
end

-- fixed on-screen size, same approach as the Questie pins
function BFIRarePinMixin:ApplyCurrentScale()
    local map = self:GetMap()
    local canvasScale = map and map.GetCanvasScale and map:GetCanvasScale() or 1
    if not canvasScale or canvasScale <= 0 then canvasScale = 1 end
    self:SetScale(ns.PinScale("rares", Cfg().scale) / canvasScale)  -- (PinScale: town view, small map)
    ns.ReanchorPin(self, map)
end

function BFIRarePinMixin:ApplyCurrentAlpha()
    self:SetAlpha(ns.PinAlpha("rares"))
end

-- The game's own vignette markers (as on the world map and minimap), by kind.
-- Each has a fallback in case this client lacks the newer atlas name.
local BLIZZARD_ICONS = {
    npc       = { "VignetteKill", "vignettekill" },
    container = { "VignetteLoot", "vignetteloot" },
    event     = { "VignetteEvent", "vignetteevent" },
}

local function AtlasExists(name)
    if C_Texture and C_Texture.GetAtlasInfo then
        return C_Texture.GetAtlasInfo(name) ~= nil
    end
    return true  -- can't check; SetAtlas returns false on failure anyway
end

local function KindOf(POI)
    if POI.isGroup and POI.POIs and POI.POIs[1] then POI = POI.POIs[1] end
    if POI.isContainer then return "container" end
    if POI.isEvent then return "event" end
    return "npc"
end

-- true if a Blizzard icon was applied; false = use RareScanner's look
local function ApplyBlizzardIcon(pin, POI)
    for _, atlas in ipairs(BLIZZARD_ICONS[KindOf(POI)]) do
        if AtlasExists(atlas) and pin.Background:SetAtlas(atlas) ~= false then
            pin.Background:Show()
            pin.Icon:Hide()
            return true
        end
    end
    return false
end

function BFIRarePinMixin:OnAcquired(entry)
    local POI = entry.POI
    self.POI = POI
    self.Background:SetTexCoord(0, 1, 0, 1)  -- pooled pins may have had an atlas before

    self.Count:SetText(POI.isGroup and POI.POIs and #POI.POIs or "")
    if not Cfg().rsIcons and ApplyBlizzardIcon(self, POI) then
        self:ApplyCurrentScale()
        self:ApplyCurrentAlpha()
        self:SetPosition(entry.x, entry.y)
        return
    end

    -- RareScanner's own look. Groups (several rares close together) have no
    -- background of their own
    local bg = POI.Texture or (POI.POIs and POI.POIs[1] and POI.POIs[1].Texture)
    if bg then
        self.Background:SetTexture(bg)
        self.Background:Show()
    else
        self.Background:Hide()
    end

    if POI.iconAtlas then
        self.Icon:SetAtlas(POI.iconAtlas)
        self.Icon:Show()
    else
        self.Icon:Hide()
    end

    self:ApplyCurrentScale()
    self:ApplyCurrentAlpha()
    self:SetPosition(entry.x, entry.y)
end

-- RareScanner's own tooltip (state, last seen, loot, notes) only needs pin.POI
function BFIRarePinMixin:OnEnter()
    local mixin = self.POI.isGroup and RSGroupPinMixin or RSEntityPinMixin
    if mixin and mixin.OnMouseEnter and pcall(mixin.OnMouseEnter, self) then return end

    -- fallback: just the names
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.POI.isGroup and self.POI.POIs then
        for _, child in ipairs(self.POI.POIs) do GameTooltip:AddLine(child.name or "?") end
    else
        GameTooltip:AddLine(self.POI.name or "Rare")
    end
    GameTooltip:Show()
end

function BFIRarePinMixin:OnMouseUp(button)
    if ns.PinAltClick then ns.PinAltClick(self, button) end  -- line target (Line.lua)
end

function BFIRarePinMixin:OnLeave()
    local mixin = self.POI and (self.POI.isGroup and RSGroupPinMixin or RSEntityPinMixin)
    if mixin and mixin.OnMouseLeave then pcall(mixin.OnMouseLeave, self) end
    GameTooltip:Hide()
end
-- the map wires a pin's mouse-over to these (see Pin.xml)
BFIRarePinMixin.OnMouseEnter = BFIRarePinMixin.OnEnter
BFIRarePinMixin.OnMouseLeave = BFIRarePinMixin.OnLeave

-- Provider --------------------------------------------------------------

BFIRareProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)

function BFIRareProviderMixin:RemoveAllData()
    local map = self:GetMap()
    pcall(map.RemoveAllPinsByTemplate, map, TEMPLATE)
end

-- Blizzard refreshes only flag us; the ticker does the (heavier) collecting
function BFIRareProviderMixin:RefreshAllData()
    self.dirty = true
end

function BFIRareProviderMixin:OnMapChanged()
    self:RemoveAllData()
    self.dirty = true
end

local function Signature(entries)
    local parts = {}
    for _, e in ipairs(entries) do
        parts[#parts + 1] = tostring(e.POI.entityID) .. "@" .. string.format("%.3f,%.3f", e.x, e.y)
            .. tostring(e.POI.Texture) .. tostring(e.POI.isGroup and #e.POI.POIs or "")
            .. tostring(Cfg().rsIcons)  -- switching icon style redraws
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

function ns.SetupRares(map)
    if not RareScannerDataProviderMixin then return end  -- RareScanner not installed

    rsProvider = CreateFromMixins(RareScannerDataProviderMixin)
    rsProvider.GetMap = function() return proxyMap end

    local provider = CreateFromMixins(BFIRareProviderMixin)
    local ok, err = pcall(map.AddDataProvider, map, provider)
    if not ok then
        ns.Log("RareScanner layer failed:", err)
        return
    end

    local elapsed, sinceCollect, lastSig, errorShown = 0, 0, nil, false

    local function Draw(force)
        local mapID = map:GetMapID()
        if not mapID then return end
        if not ns.IsShown("rares") then
            provider:RemoveAllData()
            lastSig = nil
            return
        end
        local entries, cerr = CollectPOIs(mapID)
        if not entries then
            if not errorShown then
                errorShown = true
                ns.Log("RareScanner data error:", cerr)
            end
            return
        end
        local sig = mapID .. "#" .. Signature(entries)
        if force or sig ~= lastSig then
            lastSig = sig
            provider:RemoveAllData()
            for _, entry in ipairs(entries) do
                pcall(map.AcquirePin, map, TEMPLATE, entry)
            end
        end
    end

    function ns.RedrawRares()
        provider.dirty = true
        elapsed = 1
    end

    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 1 or not map:IsVisible() then return end
        sinceCollect = sinceCollect + elapsed
        elapsed = 0
        if provider.dirty or sinceCollect >= REFRESH_SECONDS then
            local force = provider.dirty
            provider.dirty = false
            sinceCollect = 0
            Draw(force)
        end
    end)
    ns.Log("RareScanner layer active")
end
