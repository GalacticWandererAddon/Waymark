local _, ns = ...

-- The game's quest objectives (the yellow numbered markers) and quest areas (the blue zones) on
-- our map, drawn by Waymark (Forever). Until 2026-11-10 these were the game's own
-- QuestDataProviderMixin and QuestBlobDataProviderMixin added to our map. Made by our code, they
-- ran under our taint, and the objective one filled the game's shared QuestCache with entries
-- that carried it (POIButtonUtil.GetStyle, QuestCache:Get). The world map's quest log read those
-- entries, and with the gamepad UI its bindings, focus and view were written tainted: blocked
-- SetPreferredGamepadInteractTarget and A no longer jumping until a reload (CurseForge players,
-- found with DevGamepad.lua and a second look from Fable 5.2). So these call only the game's C
-- data functions: no POIButton*, QuestCache, QuestUtil, QuestMapFrame_*, GetQuestsOnMapCached,
-- POIButtonHighlightManager, and nothing triggered on the game's EventRegistry.
-- The same look: the game's atlases, its sizes and frame levels. A click opens the quest's page
-- in Waymark's quest window, as our own quest pins do (the game's pin super-tracked the quest).

local OBJECTIVE = "BFIQuestPOIPinTemplate"
local AREA = "BFIQuestBlobPinTemplate"

local function QuestPOIOn() return GetCVarBool("questPOI") end

local function MapShowsQuests(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    return info and MapUtil.ShouldMapTypeShowQuests(info.mapType), info
end

-- Objective pins -------------------------------------------------------------------------------

BFIQuestPOIPinMixin = CreateFromMixins(MapCanvasPinMixin)
BFIQuestPOIPinMixin.CheckMouseButtonPassthrough = ns.SafePassthrough  -- see Pin.lua

function BFIQuestPOIPinMixin:OnLoad()
    if self.SetDefaultMapPinScale then self:SetDefaultMapPinScale() end
end

local function SetAtlas(tex, atlas, w, h)
    if w then
        tex:SetAtlas(atlas, false)
        tex:SetSize(w, h)
    else
        tex:SetAtlas(atlas, true)
    end
end

-- info: { questID, x, y, waypoint, selected, level }
function BFIQuestPOIPinMixin:OnAcquired(info)
    self.questID, self.waypoint, self.selected = info.questID, info.waypoint, info.selected
    pcall(self.UseFrameLevelType, self, info.selected and "PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST"
        or "PIN_FRAME_LEVEL_ACTIVE_QUEST", info.level)
    local id = info.questID
    SetAtlas(self.Normal, info.selected and "UI-QuestPoi-QuestNumber-SuperTracked" or "UI-QuestPoi-QuestNumber")
    SetAtlas(self.Highlight, "UI-QuestPoi-InnerGlow")
    if info.waypoint then
        SetAtlas(self.Display, "poi-traveldirections-arrow", 13, 17)
    elseif C_QuestLog.IsComplete(id) then
        SetAtlas(self.Display, "UI-QuestIcon-TurnIn-Normal")
    elseif C_QuestLog.IsQuestDisabledForSession and C_QuestLog.IsQuestDisabledForSession(id) then
        SetAtlas(self.Display, "QuestSharing-QuestLog-Padlock", 24, 29)
    else
        SetAtlas(self.Display, info.selected and "Quest-In-Progress-Icon-Brown" or "Quest-In-Progress-Icon-yellow")
    end
    self:SetPosition(info.x, info.y)
end

function BFIQuestPOIPinMixin:OnReleased()
    self.questID = nil
    self:UnlockHighlight()
end

function BFIQuestPOIPinMixin:OnMouseEnter()
    local id = self.questID
    if not id then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(C_QuestLog.GetTitleForQuestID(id) or ("Quest " .. id))
    local index = C_QuestLog.GetLogIndexForQuestID(id)
    if index then
        if C_QuestLog.IsComplete(id) then
            GameTooltip:AddLine(QUEST_WATCH_QUEST_READY or "Ready for turn-in", 0.2, 1, 0.2, true)
        else
            for i = 1, GetNumQuestLeaderBoards(index) or 0 do
                local text, _, finished = GetQuestLogLeaderBoard(i, index)
                if text and not finished then GameTooltip:AddLine("- " .. text, 1, 1, 1, true) end
            end
        end
    end
    if self.waypoint then
        local wp = C_QuestLog.GetNextWaypointText and C_QuestLog.GetNextWaypointText(id)
        if wp then GameTooltip:AddLine(wp, 1, 0.82, 0, true) end
    end
    if ns.Hints then
        ns.Hints({ ns.OpenQuest and { "Click", "the quest's page" } or nil,
                   { "Right-click", "its menu" } })
    end
    GameTooltip:Show()
    if ns.HoverQuestGlow then ns.HoverQuestGlow(id) end
end

function BFIQuestPOIPinMixin:OnMouseLeave()
    GameTooltip:Hide()
    if ns.HoverQuestGlow then ns.HoverQuestGlow(nil) end
end

function BFIQuestPOIPinMixin:OnMouseUp(button)
    local id = self.questID
    if not id then return end
    if button == "LeftButton" then
        if ns.OpenQuest then ns.OpenQuest(id) end
    elseif button == "RightButton" and ns.QuillMenu then
        local items = {}
        if ns.OpenQuest then items[#items + 1] = { "quest details", function() ns.OpenQuest(id) end } end
        if ns.ToggleFocus then
            items[#items + 1] = { ns.IsFocused and ns.IsFocused(id) and "out of focus" or "focus quest", function() ns.ToggleFocus(id) end }
        end
        if ns.ToggleQuestGlow then items[#items + 1] = { "its spots lit (again: off)", function() ns.ToggleQuestGlow(id) end } end
        if #items > 0 then ns.QuillMenu(items) end
    end
end

BFIQuestPOIProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)

function BFIQuestPOIProviderMixin:OnAdded(map)
    MapCanvasDataProviderMixin.OnAdded(self, map)
    -- (the game's own pin spreader, an object of ours: pins close together are pushed apart)
    if WorldMapPOIQuantizerMixin and not self.quantizer then
        local q = CreateFromMixins(WorldMapPOIQuantizerMixin)
        q.size = 75
        q:OnLoad(q.size, q.size)
        self.quantizer = q
    end
end

function BFIQuestPOIProviderMixin:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(OBJECTIVE)
end

function BFIQuestPOIProviderMixin:OnCanvasSizeChanged()
    local q, map = self.quantizer, self:GetMap()
    if not q then return end
    local ratio = map:DenormalizeHorizontalSize(1.0) / map:DenormalizeVerticalSize(1.0)
    q:Resize(math.ceil(q.size * ratio), q.size)
end

function BFIQuestPOIProviderMixin:RefreshAllData()
    self:RemoveAllData()
    local map = self:GetMap()
    local mapID = map:GetMapID()
    if not (mapID and QuestPOIOn()) then return end
    local shows, info = MapShowsQuests(mapID)
    if not info then return end
    local super = C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
    if super == 0 then super = nil end
    local pins = {}
    local function Add(id, x, y, level, waypoint)
        if not (id and x and y) then return end
        -- (a continent shows only the super-tracked quest, as the game's does)
        if not (shows or (info.mapType == Enum.UIMapType.Continent and id == super)) then return end
        if not HaveQuestData(id) then return end
        pins[#pins + 1] = map:AcquirePin(OBJECTIVE, { questID = id, x = x, y = y, level = level,
            waypoint = waypoint, selected = id == super })
    end
    local list = C_QuestLog.GetQuestsOnMap(mapID) or {}
    for i, q in ipairs(list) do
        if not q.isMapIndicatorQuest then Add(q.questID, q.x, q.y, i) end
    end
    if super and C_QuestLog.GetNextWaypointForMap then
        local x, y = C_QuestLog.GetNextWaypointForMap(super, mapID)
        if x and y then Add(super, x, y, #list + 1, true) end
    end
    if self.quantizer and #pins > 0 then
        self.quantizer:ClearAndQuantize(pins)
        for _, pin in ipairs(pins) do pin:SetPosition(pin.quantizedX or pin.normalizedX, pin.quantizedY or pin.normalizedY) end
    end
end

function BFIQuestPOIProviderMixin:OnMapChanged() self:RefreshAllData() end

-- Quest areas ----------------------------------------------------------------------------------

-- One pin over the whole map; every quest on it drawn (the game's drew only the one in focus,
-- and Waymark drew the rest after it), plus the quest highlighted from the tracker.
BFIQuestBlobPinMixin = CreateFromMixins(MapCanvasPinMixin)

function BFIQuestBlobPinMixin:OnLoad()
    self:SetFillTexture("Interface\\WorldMap\\UI-QuestBlob-Inside")
    self:SetBorderTexture("Interface\\WorldMap\\UI-QuestBlob-Outside")
    self:SetFillAlpha(128)
    self:SetBorderAlpha(192)
    self:SetBorderScalar(1.0)
    self:SetIgnoreGlobalPinScale(true)
    pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_QUEST_BLOB")
end

function BFIQuestBlobPinMixin:OnCanvasSizeChanged()
    local map = self:GetMap()
    self:SetSize(map:DenormalizeHorizontalSize(1.0), map:DenormalizeVerticalSize(1.0))
end

function BFIQuestBlobPinMixin:OnCanvasScaleChanged() self.dirty = true end

function BFIQuestBlobPinMixin:OnUpdate()
    if self.dirty then
        self.dirty = nil
        self:Refresh()
    end
end

function BFIQuestBlobPinMixin:OnMapChanged()
    local mapID = self:GetMap():GetMapID()
    self.mapAllowsBlobs = MapShowsQuests(mapID) and true or false
    if mapID then self:SetMapID(mapID) end
    self:Refresh()
end

function BFIQuestBlobPinMixin:Refresh()
    self:DrawNone()
    local mapID = self:GetMap():GetMapID()
    if not (self.mapAllowsBlobs and mapID and QuestPOIOn()) then return end
    local drawn = {}
    for _, q in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or {}) do
        if q.questID and not drawn[q.questID] then
            drawn[q.questID] = true
            self:DrawBlob(q.questID, true)
        end
    end
    local h = self.highlightedQuestID
    if h and h > 0 and not drawn[h] then self:DrawBlob(h, true) end
end

BFIQuestBlobProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)

function BFIQuestBlobProviderMixin:OnAdded(map)
    MapCanvasDataProviderMixin.OnAdded(self, map)
    local pin = map:AcquirePin(AREA)
    pin:SetPosition(0.5, 0.5)
    self.pin = pin
    -- (Waymark's tracker lights a quest's areas with these, on our map only: Tracker.lua)
    map:RegisterCallback("SetHighlightedQuestID", function(_, id) pin.highlightedQuestID = id pin:Refresh() end, self)
    map:RegisterCallback("ClearHighlightedQuestID", function() pin.highlightedQuestID = nil pin:Refresh() end, self)
end

function BFIQuestBlobProviderMixin:RemoveAllData() end  -- (the one pin stays)
function BFIQuestBlobProviderMixin:RefreshAllData() if self.pin then self.pin:Refresh() end end
function BFIQuestBlobProviderMixin:OnMapChanged() if self.pin then self.pin:OnMapChanged() end end

-- Setup ----------------------------------------------------------------------------------------

-- add(mixin, label, group): BattlefieldInfo.lua's AddProvider (combat wait, pin groups)
function ns.SetupQuestPOI(map, add)
    map:SetPinTemplateType(AREA, "QuestPOIFrame")
    local objectives = add(map, BFIQuestPOIProviderMixin, "Quest objectives", "objectives")
    local areas = add(map, BFIQuestBlobProviderMixin, "Quest areas", "areas")
    -- (the game's events, on a frame of ours; one redraw a frame however many come)
    local queued
    local function Redraw()
        queued = nil
        if not map:IsShown() then return end
        if objectives then pcall(objectives.RefreshAllData, objectives) end
        if areas then pcall(areas.RefreshAllData, areas) end
    end
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_POI_UPDATE",
                         "SUPER_TRACKING_CHANGED", "CVAR_UPDATE" }) do
        f:RegisterEvent(e)
    end
    f:SetScript("OnEvent", function(_, event, cvar)
        if event == "CVAR_UPDATE" and cvar ~= "questPOI" then return end
        if not queued then
            queued = true
            C_Timer.After(0, Redraw)
        end
    end)
    map:HookScript("OnShow", function() C_Timer.After(0, Redraw) end)
end
