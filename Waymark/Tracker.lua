local _, ns = ...
local GetCoinTextureString = GetCoinTextureString or ns.GetCoinTextureString
local GetItemInfo = GetItemInfo or ns.GetItemInfo
local GetItemIcon = GetItemIcon or ns.GetItemIcon
local GetItemQualityColor = GetItemQualityColor or ns.GetItemQualityColor

-- Quest tracker: the quests you track with something to do in the zone you're
-- in, with their objectives, nearest first, under their sub-zone's name. Like
-- the game's own tracker (and Questie's), but for this zone only. Attached to
-- a side of the Battlefield Map, or free.
--
-- "Something to do here": an objective spot or the turn-in on this zone's map
-- (from QuestieDB, else the game's own quest markers), or the quest log
-- files the quest under this zone. Distance: to the nearest objective spot,
-- for a finished quest to its turn-in.
--
-- tracker settings (ns.db.tracker): attach "below" / "above" / "left" /
-- "right"; detached (on its own, at pos: top-left, UIParent units); width
-- (left, right, detached); sort "distance" / "level" / "log"; finished "show" / "hide" /
-- "only"; hideGrey, hideElite, hideDungeon, hideGroup, onlyTracked; objectives
-- (show them), hideDoneObjectives; folded[questID]; groupByArea; maxHeight
-- (taller scrolls); collapsed. Look: titleFont, textFont (Fonts.lua keys),
-- fontSize, objSize, outline, shadow, icons, headerArt, levelColors, lineGap,
-- questGap, bgAlpha, border* (the map border's styles); fadeOut to fadeAlpha %.
-- otherZones ("always" / "continent" / "off"): your tracked quests in other
-- zones too, after this zone's, under their zone's name. turninName (a
-- finished quest names its turn-in), countColumn (objective counts at the
-- right), levelColumn (levels in a column of their own; goldTitles),
-- quietHeadings, flashProgress. locked: on its own, it can't be moved or resized
-- (the header's right-click menu, or the settings).

-- ("free" was a fourth attach before detached was its own switch: old
-- settings and profiles still carry it)
local function Cfg()
    local c = ns.db.tracker
    if c.attach == "free" then c.detached, c.attach = true, "below" end
    return c
end

local frame          -- the tracker
local rows = {}      -- its lines, reused
local list = {}      -- the quests shown, in order (Collect)
local untracked = {} -- with onlyTracked: the ones here you don't track (to track from the list)
local lastOrder = {} -- [questID] = place last time, so near-equal distances don't swap
local zoneName = ""
local curZone        -- its map ID
local hereCount = 0  -- the quests in `list` before other zones' (in focus too)
local zoneCount = 0  -- of those, the ones from this zone (the header's count)
local dirty = true
local seen = {}      -- [questID] = { [objective] = how many done, complete }: to see progress
local flashAt = {}   -- ["questID:objective"] / ["questID:done"] = when it counted up

local PAD = 6
local DIST_BUCKET = 25  -- yards: closer than this counts as the same distance

-- Quest log (the modern C_QuestLog on Forever, the old globals elsewhere) -----

local function NumEntries()
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then return (C_QuestLog.GetNumQuestLogEntries()) end
    return GetNumQuestLogEntries and (GetNumQuestLogEntries()) or 0
end

local function Entry(i)
    if C_QuestLog and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(i)
        if not info then return end
        local e = { title = info.title, level = info.level, isHeader = info.isHeader,
                    id = info.questID, group = info.suggestedGroup }
        if not info.isHeader and info.questID then
            e.complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID) or false
            e.failed = C_QuestLog.IsFailed and C_QuestLog.IsFailed(info.questID) or false
            e.complete = ns.QuestReady(info.questID, i, e.complete, e.failed)
        end
        return e
    end
    if not GetQuestLogTitle then return end
    local title, level, group, isHeader, _, complete, _, id = GetQuestLogTitle(i)
    if not title then return end
    return { title = title, level = level, isHeader = isHeader, id = id, group = group,
             complete = not isHeader and id and ns.QuestReady(id, i, complete == 1, complete == -1) or false,
             failed = complete == -1 }
end

local function LogIndex(id)
    local i
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then i = C_QuestLog.GetLogIndexForQuestID(id)
    else i = GetQuestLogIndexByID and GetQuestLogIndexByID(id) end
    return i and i > 0 and i or nil
end

-- the quest's tag: elite, dungeon, raid, group (by name and the game's IDs)
local TAG_GROUP, TAG_RAID, TAG_DUNGEON = 1, 62, 81
local function Tags(id, group)
    local tagID, name
    if C_QuestLog and C_QuestLog.GetQuestTagInfo then
        local ok, t = pcall(C_QuestLog.GetQuestTagInfo, id)
        if ok and t then tagID, name = t.tagID, t.tagName end
    elseif GetQuestTagInfo then
        local ok, a, b = pcall(GetQuestTagInfo, id)
        if ok then tagID, name = a, b end
    end
    -- (the log's suggested group: a number, but Era gives some quests a word
    -- there, "Elite" and the like: read as a tag then. Compared as a number it
    -- broke the whole tracker on a character with such a quest, 2026-11-03)
    local size = tonumber(group)
    if not size and type(group) == "string" then name = (name or "") .. " " .. group end
    local n = (name or ""):lower()
    return {
        elite = n:find("elite", 1, true) ~= nil,
        dungeon = tagID == TAG_DUNGEON or n:find("dungeon", 1, true) ~= nil,
        raid = tagID == TAG_RAID or n:find("raid", 1, true) ~= nil,
        group = tagID == TAG_GROUP or n:find("group", 1, true) ~= nil or (size or 0) > 0,
    }
end

local function Objectives(id, index)
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, objs = pcall(C_QuestLog.GetQuestObjectives, id)
        if ok and objs then return objs end
    end
    local out = {}
    if index and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        for j = 1, GetNumQuestLeaderBoards(index) or 0 do
            local text, objType, finished = GetQuestLogLeaderBoard(j, index)
            out[#out + 1] = { text = text, type = objType, finished = finished }
        end
    end
    return out
end

-- Tracking: the game's own watch list (with Questie on Classic this is
-- Questie's own tracking, which is what its tracker shows), plus our own, per
-- character, for the quests the game won't watch: ones with nothing to do but
-- hand in ("Report to Goldshire"), and any past the game's limit (5 on Classic)
local function OwnWatched()
    WaymarkCharDB = WaymarkCharDB or {}
    local c = WaymarkCharDB
    c.watched = c.watched or {}
    return c.watched
end

-- Quests in focus, per character too: always listed, at the top under "In
-- focus", their objective spots and turn-in glowing. [questID] = true
local function Focus()
    WaymarkCharDB = WaymarkCharDB or {}
    local c = WaymarkCharDB
    c.focus = c.focus or {}
    return c.focus
end

local function GameWatched(id, index)
    if C_QuestLog and C_QuestLog.GetQuestWatchType then return C_QuestLog.GetQuestWatchType(id) ~= nil end
    if IsQuestWatched and index then return IsQuestWatched(index) and true or false end
    return false
end

local function IsWatched(id, index)
    return OwnWatched()[id] == true or GameWatched(id, index)
end

-- the game's watch list is full
local function GameWatchFull()
    local max = MAX_WATCHABLE_QUESTS
    if not max then return false end
    local n = (C_QuestLog and C_QuestLog.GetNumQuestWatches and C_QuestLog.GetNumQuestWatches())
        or (GetNumQuestWatches and GetNumQuestWatches()) or 0
    return n >= max
end

local function Watch(id)
    local index = LogIndex(id)
    if not index or IsWatched(id, index) then return end
    if not GameWatchFull() then
        if C_QuestLog and C_QuestLog.AddQuestWatch then pcall(C_QuestLog.AddQuestWatch, id)
        elseif AddQuestWatch then pcall(AddQuestWatch, index) end
    end
    -- the game didn't take it: ours
    if not GameWatched(id, index) then OwnWatched()[id] = true end
    dirty = true
end

local function ToggleWatch(id)
    local index = LogIndex(id)
    if IsWatched(id, index) then
        OwnWatched()[id] = nil
        if GameWatched(id, index) then
            if C_QuestLog and C_QuestLog.RemoveQuestWatch then C_QuestLog.RemoveQuestWatch(id)
            elseif RemoveQuestWatch and index then RemoveQuestWatch(index) end
        end
        dirty = true
    else
        Watch(id)
    end
end

-- the quests you track, [questID] = true (the map's "tracked quests only" filter)
function ns.TrackedQuests()
    local out = {}
    for i = 1, NumEntries() do
        local id, header
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            if info then id, header = info.questID, info.isHeader end
        elseif GetQuestLogTitle then
            local _, _, _, isHeader, _, _, _, qid = GetQuestLogTitle(i)
            id, header = qid, isHeader
        end
        if id and id > 0 and not header and IsWatched(id, i) then out[id] = true end
    end
    return out
end

-- Shift-click in the game's quest log on a quest the game won't watch (no
-- objectives, or 5 watched already): it refuses with a red message, and the
-- quest goes on our list instead (or comes off it, if it's there). Hooked
-- after the game's own click (hooksecurefunc: nothing of the game's replaced).
local refusedAt
local function WatchRefusal(msg)
    if type(msg) ~= "string" then return false end
    if QUEST_WATCH_NO_OBJECTIVES and msg == QUEST_WATCH_NO_OBJECTIVES then return true end
    if QUEST_WATCH_TOO_MANY and MAX_WATCHABLE_QUESTS
       and msg == string.format(QUEST_WATCH_TOO_MANY, MAX_WATCHABLE_QUESTS) then return true end
    return false
end

-- the log line a title button stands for (its ID, plus the scroll offset on
-- older clients): the one whose title is the button's text
local function TitleIndex(button)
    local id = button:GetID()
    local offset = (FauxScrollFrame_GetOffset and QuestLogListScrollFrame)
        and FauxScrollFrame_GetOffset(QuestLogListScrollFrame) or 0
    local text = button.GetText and button:GetText() or ""
    text = text:gsub("^%s+", "")
    for _, i in ipairs({ id + offset, id }) do
        local title = GetQuestLogTitle and GetQuestLogTitle(i)
        if title and (text == "" or text:find(title, 1, true)) then return i end
    end
end

local function HookQuestLog()
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        hooksecurefunc(UIErrorsFrame, "AddMessage", function(_, msg)
            if WatchRefusal(msg) then refusedAt = GetTime() end
        end)
    end
    if not QuestLogTitleButton_OnClick then return end  -- (the modern quest log: C_QuestLog only)
    hooksecurefunc("QuestLogTitleButton_OnClick", function(self)
        if not (self and IsShiftKeyDown()) or refusedAt ~= GetTime() then return end
        if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then return end
        refusedAt = nil
        local index = TitleIndex(self)
        local id = index and (C_QuestLog.GetQuestIDForLogIndex and C_QuestLog.GetQuestIDForLogIndex(index) or GetQuestLogTitle and select(8, GetQuestLogTitle(index)))
        if not id or id == 0 then return end
        local own = OwnWatched()
        own[id] = not own[id] or nil
        if UIErrorsFrame and UIErrorsFrame.Clear then UIErrorsFrame:Clear() end  -- (it's tracked after all)
        dirty = true
    end)
end

-- a newly accepted quest is tracked (tracker.autoTrack); one that leaves the
-- log leaves our list. (QUEST_ACCEPTED: (logIndex, questID) on Classic, (questID) on newer clients)
local function OnQuestEvent(event, a, b)
    if event == "QUEST_ACCEPTED" then
        local id = b or a
        if Cfg().autoTrack and id then
            C_Timer.After(0.3, function() Watch(id) end)  -- (once the log has it)
        end
    elseif (event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN") and a then
        OwnWatched()[a] = nil
        Focus()[a] = nil
    end
end

-- Opening the quest log at a quest. (On Forever, opening it from addon code
-- with the gamepad UI on taints its bindings, which crashes: Questie warns too.)
local function OpenLog(id)
    if InCombatLockdown() then ns.Log("can't open the quest log in combat") return end
    if InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() then
        ns.Log("opening the quest log from the tracker is off in controller mode")
        return
    end
    local logFrame = QuestLogExFrame or ClassicQuestLog or QuestLogFrame
    -- (Forever: the small page with Show Map on it; the same quest again closes it. A method of the
    -- frame there, read from its UI code: there's no QuestLogPopupDetailFrame_Show)
    local popup = QuestLogPopupDetailFrame
    if not logFrame and id and LogIndex(id) and popup and popup.ShowQuest then
        popup:ShowQuest(id)
        return
    end
    if not logFrame and QuestMapFrame_OpenToQuestDetails then
        QuestMapFrame_OpenToQuestDetails(id)
        return
    end
    if not logFrame then return end
    local index = id and LogIndex(id)  -- (no quest: just open it)
    if index then
        if C_QuestLog and C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(id)
        elseif SelectQuestLogEntry then SelectQuestLogEntry(index) end
    end
    if not logFrame:IsShown() then ShowUIPanel(logFrame) end
    if QuestLog_Update then pcall(QuestLog_Update) end
    if QuestLog_UpdateQuestDetails then pcall(QuestLog_UpdateQuestDetails) end
end

-- Where -------------------------------------------------------------------------

-- the zone you're in: your map, or the zone above a cave or town map
local function ZoneMap()
    local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local T = Enum and Enum.UIMapType
    local n = 0
    while mapID and T and n < 5 do
        local info = C_Map.GetMapInfo(mapID)
        if not info or info.mapType <= T.Zone then break end
        mapID, n = info.parentMapID, n + 1
    end
    return mapID
end

-- [questID] = { spots = { {x, y} }, turnin = { {x, y} } } on this map (0..1).
-- Each quest's objective spots and turn-in from QuestieDB (QuestData.lua); the
-- game's own quest markers for quests it has nothing for here.
local function Points(mapID)
    -- (a copy: QuestData keeps its table)
    local out = {}
    for id, p in pairs(ns.QuestPoints and ns.QuestPoints(mapID) or {}) do out[id] = p end
    if C_QuestLog and C_QuestLog.GetQuestsOnMap then
        local ok2, game = pcall(C_QuestLog.GetQuestsOnMap, mapID)
        for _, g in ipairs(ok2 and game or {}) do
            if g.questID and g.x and not out[g.questID] then
                out[g.questID] = { spots = { { g.x, g.y } }, turnin = { { g.x, g.y } } }
            end
        end
    end
    return out
end

local function Trivial(level)
    if not level or level <= 0 then return false end
    local green = GetQuestGreenRange and GetQuestGreenRange() or 8
    return UnitLevel("player") - level > green
end

-- The list ------------------------------------------------------------------------

local FOCUS_HEAD = "In focus"  -- (the heading over the quests in focus)

-- the map shows a continent (or the world)
local function ContinentView()
    local map = BattlefieldMapFrame
    local id = map and map.GetMapID and map:GetMapID()
    local info = id and C_Map.GetMapInfo(id)
    local T = Enum and Enum.UIMapType
    return (info and T and info.mapType <= T.Continent) and true or false
end

-- tracked quests from other zones listed too (otherZones)
local function OtherZones()
    local m = Cfg().otherZones or "off"
    return m == "always" or (m == "continent" and ContinentView())
end

-- how much of an objective is done: its count, or 1 / 0
local function DoneCount(o)
    if o.numFulfilled then return o.numFulfilled end
    local n = o.text and o.text:match("(%d+)%s*/%s*%d+")
    return tonumber(n) or (o.finished and 1 or 0)
end

-- each quest's objectives (q.objs), and what counted up since last time:
-- that line flashes (flashProgress)
local function Progress(quests)
    local now, flash = GetTime(), Cfg().flashProgress ~= false
    for _, q in ipairs(quests) do
        local objs = (not q.complete and not q.failed) and Objectives(q.id, q.index) or {}
        q.objs = objs
        local was, is = seen[q.id], { complete = q.complete }
        for j, o in ipairs(objs) do
            is[j] = DoneCount(o)
            if flash and was and was[j] and is[j] > was[j] then flashAt[q.id .. ":" .. j] = now end
        end
        if flash and was and q.complete and not was.complete then flashAt[q.id .. ":done"] = now end
        seen[q.id] = is
    end
end

local function Collect()
    local c = Cfg()
    wipe(untracked)
    local zone = ZoneMap()
    curZone = zone
    local others = OtherZones()
    local info = zone and C_Map.GetMapInfo(zone)
    zoneName = info and info.name or (GetRealZoneText and GetRealZoneText()) or ""
    local real = GetRealZoneText and GetRealZoneText() or ""
    local points = zone and Points(zone) or {}
    local pos = zone and C_Map.GetPlayerMapPosition(zone, "player")
    local px, py = pos and pos.x, pos and pos.y
    if px and px == 0 and py == 0 then px = nil end
    local w, h  -- (not `zone and MapYards(zone)`: that keeps only the first value)
    if zone and ns.MapYards then w, h = ns.MapYards(zone) end

    local out, header = {}, nil
    for i = 1, NumEntries() do
        local e = Entry(i)
        if e and e.isHeader then
            header = e.title
        elseif e and e.id and e.id > 0 then
            local p = points[e.id]
            local here = (p and (#p.spots > 0 or #p.turnin > 0)) or header == zoneName or header == real
            local focused = Focus()[e.id]
            -- (from another zone: filed under it in the quest log)
            local elsewhere = not (here or focused) and others and header and header ~= "" and header
            if here or focused or elsewhere then
                local q = e
                q.index = i
                q.header = header
                q.otherZone = elsewhere or nil
                q.here = here and true or nil  -- (a quest in focus may be from anywhere)
                q.tags = Tags(e.id, e.group)
                q.watched = IsWatched(e.id, i)
                -- the nearest thing to do: a spot, or the turn-in once it's finished
                local spots = p and (e.complete and p.turnin or p.spots)
                if spots and px and w then
                    for _, s in ipairs(spots) do
                        local d = math.sqrt(((s[1] - px) * w) ^ 2 + ((s[2] - py) * h) ^ 2)
                        if not q.dist or d < q.dist then q.dist, q.spot = d, s end
                    end
                end
                -- the area (sub-zone) it's in: where its nearest spot is
                if q.spot and ns.AreaNameAt then q.area = ns.AreaNameAt(zone, q.spot[1], q.spot[2]) end
                local show = true
                if c.finished == "hide" and e.complete then show = false end
                if c.finished == "only" and not e.complete then show = false end
                if c.hideGrey and Trivial(e.level) then show = false end
                if c.hideElite and q.tags.elite then show = false end
                if c.hideDungeon and (q.tags.dungeon or q.tags.raid) then show = false end
                if c.hideGroup and q.tags.group then show = false end
                if focused then show = true end  -- (in focus: always listed)
                if show and q.otherZone and not q.watched then
                    show = false  -- (another zone's: only the ones you track)
                elseif show and c.onlyTracked and not q.watched then
                    show = false  -- (no "Not tracked (x)" list of them any more, the user: track from the log)
                end
                if show then out[#out + 1] = q end
            end
        end
    end

    -- The order: sort "distance" (nearest first), "alpha" (by title), "area"
    -- (by sub-zone name, nearest first within each), "level" or "log" (as in
    -- the quest log). Distances count in 25-yard steps, so two quests about as
    -- near keep their places instead of swapping as you walk; unknown last.
    -- (the Lab's quest routes: by the stop each comes up at)
    local sort = ns.RouteSort and ns.RouteSort() or c.sort or "distance"
    for i, q in ipairs(out) do
        q.logPlace = i
        q.areaName = q.area or (q.spot and zoneName) or nil  -- (nil: nothing to do here)
    end
    local function Nearer(a, b)
        local da = a.dist and math.floor(a.dist / DIST_BUCKET) or math.huge
        local db = b.dist and math.floor(b.dist / DIST_BUCKET) or math.huge
        if da ~= db then return da < db end
        local pa, pb = lastOrder[a.id] or math.huge, lastOrder[b.id] or math.huge
        if pa ~= pb then return pa < pb end
    end
    -- (finished quests last in their list, whatever the order, a route's too)
    local doneLast = c.finishedLast ~= false
    table.sort(out, function(a, b)
        if doneLast and (a.complete and true or false) ~= (b.complete and true or false) then return b.complete and true or false end
        if sort == "distance" then
            local n = Nearer(a, b)
            if n ~= nil then return n end
        elseif sort == "alpha" then
            local ta, tb = (a.title or ""):lower(), (b.title or ""):lower()
            if ta ~= tb then return ta < tb end
        elseif sort == "area" then
            -- "~": after every name, so quests with nothing here come last
            local na, nb = (a.areaName or "~"):lower(), (b.areaName or "~"):lower()
            if na ~= nb then return na < nb end
            local n = Nearer(a, b)
            if n ~= nil then return n end
        elseif sort == "level" then
            if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
        elseif sort == "route" then
            local ra, rb = ns.RouteStepOf(a.id) or math.huge, ns.RouteStepOf(b.id) or math.huge
            if ra ~= rb then return ra < rb end
            local n = Nearer(a, b)
            if n ~= nil then return n end
        end
        return a.logPlace < b.logPlace
    end)
    wipe(lastOrder)
    for i, q in ipairs(out) do lastOrder[q.id] = i end

    -- In focus (Focus()): those first, under an "In focus" heading, in
    -- the order above. The rest then always get a heading of their own, so
    -- they don't read as in focus too. Other zones' quests go apart, to
    -- the end.
    local focused, rest, away = {}, {}, {}
    for _, q in ipairs(out) do
        q.areaHead, q.zoneHead = nil, nil
        if Focus()[q.id] then focused[#focused + 1] = q
        elseif q.otherZone then away[#away + 1] = q
        else rest[#rest + 1] = q end
    end
    out = rest

    -- by area (sub-zone): each area under its own heading. The areas come in
    -- the order of their first quest in the order above: nearest first, the
    -- first title A-Z, or by name. So nearest first, an area's quests stay
    -- together: a third-nearest quest in the nearest area comes before the
    -- second-nearest in another area. A spot outside any named area (a
    -- capital's own map has none) goes under the zone's name; quests with no
    -- spot here under "Elsewhere" at the end. A single heading is left out:
    -- the zone name above says it already.
    if c.groupByArea ~= false then
        local groups, byName, rest = {}, {}, nil
        for _, q in ipairs(out) do
            local name = q.areaName
            local g = name and byName[name]
            if not name then
                rest = rest or { name = "Elsewhere", quests = {} }
                g = rest
            elseif not g then
                g = { name = name, quests = {} }
                byName[name] = g
                groups[#groups + 1] = g
            end
            g.quests[#g.quests + 1] = q
        end
        if rest then groups[#groups + 1] = rest end
        local headed = #groups > 1 or (#focused > 0 and #groups > 0)
        out = {}
        for _, g in ipairs(groups) do
            for i, q in ipairs(g.quests) do
                q.areaHead = headed and i == 1 and g.name or nil
                out[#out + 1] = q
            end
        end
    elseif #focused > 0 and out[1] then
        out[1].areaHead = zoneName  -- (not by area: the rest under the zone's name)
    end
    if #focused > 0 then
        focused[1].areaHead = FOCUS_HEAD
        for i = #focused, 1, -1 do table.insert(out, 1, focused[i]) end
    end
    hereCount = #out
    zoneCount = #rest
    for _, q in ipairs(focused) do
        if q.here then zoneCount = zoneCount + 1 end
    end

    -- other zones (otherZones): after this zone's, each zone under its name
    -- (A-Z), its quests in the order above
    if #away > 0 then
        local zones, byZone = {}, {}
        for _, q in ipairs(away) do
            local g = byZone[q.otherZone]
            if not g then
                g = { name = q.otherZone, quests = {} }
                byZone[q.otherZone] = g
                zones[#zones + 1] = g
            end
            g.quests[#g.quests + 1] = q
        end
        table.sort(zones, function(a, b) return a.name < b.name end)
        for _, g in ipairs(zones) do
            for i, q in ipairs(g.quests) do
                q.areaHead = i == 1 and g.name or nil
                q.zoneHead = i == 1 or nil
                out[#out + 1] = q
            end
        end
    end
    Progress(out)
    list = out
end

-- Drawing --------------------------------------------------------------------------

-- Styled after the game's own objective tracker: the zone name over a gold
-- rule with a fold button, then the quests (under their area's name), each
-- with a round icon and "[level] Title", its objectives in smaller lines
-- under the title. The header stays put; the list scrolls with the mouse
-- wheel when it's taller than the tracker may be (maxHeight). Fonts, sizes,
-- outline, spacing, background, border and fading are settings.

local GOLD = { 1, 0.82, 0 }
local AREA_GOLD = { 0.85, 0.7, 0.45 }
local AREA_DIM = { 0.7, 0.6, 0.43 }  -- (quietHeadings)
local OUTLINES = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE" }

-- Icons: Questie's round quest icons where Questie is installed (the same the
-- map pins use: crossed swords to kill, a bag to collect, a cog to use, a star
-- for an event, the gold "?" to hand in), else the game's own.
local QUESTIE_ICONS = "Interface\\AddOns\\Questie\\Icons\\"
local TYPE_ICONS = { monster = "slay", player = "slay", item = "loot", object = "object", event = "event" }
local GAME_ICONS = {
    complete = "Interface\\GossipFrame\\ActiveQuestIcon",
    progress = "Interface\\GossipFrame\\IncompleteQuestIcon",
}
local FAILED_ICON = "Interface\\RaidFrame\\ReadyCheck-NotReady"
-- the finished "?": the map's sharp turn-in atlas where the client has it (the
-- gossip icon is a tiny texture that blurs at this size)
local TURNIN_ATLAS = "QuestTurnin"
local hasTurninAtlas
local function TurninAtlas()
    if hasTurninAtlas == nil then
        hasTurninAtlas = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(TURNIN_ATLAS)) and true or false
    end
    return hasTurninAtlas and TURNIN_ATLAS or nil
end

-- a texture path, { atlas = name }, or the game's cursor art: { path, crop =
-- { l, r, t, b }, mask = its pointer tip hidden } (QuestData.lua's specs)
local function Icon(q, objType)
    if q.failed then return FAILED_ICON end
    if ns.QuestieArt and ns.QuestieArt() then
        return QUESTIE_ICONS .. (q.complete and "complete" or TYPE_ICONS[objType] or "event")
    end
    if q.complete then
        local atlas = TurninAtlas()
        return atlas and { atlas = atlas } or GAME_ICONS.complete
    end
    -- in progress: what kind of objective it is (kill, collect, use, event)
    local byType = ns.GAME_OBJECTIVE_ICONS
    local spec = byType and byType[TYPE_ICONS[objType] or "event"]
    if spec then return spec end
    return GAME_ICONS.progress
end

-- (flags: a text part's own outline; nil: the tracker's Outline setting)
local function Font(fs, key, size, flags)
    ns.SetFontSafe(fs, key, size, flags or OUTLINES[Cfg().outline or "none"] or "")
    -- the game's tracker text has a soft drop shadow
    if Cfg().shadow ~= false then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

-- "[12+] " before the title, or (bare, for the level column) "12+"
local function LevelTag(q, bare)
    local t = q.tags
    local suffix = t.raid and "R" or t.dungeon and "D" or (t.elite or t.group) and "+" or ""
    if bare then return (q.level or "?") .. suffix end
    return "[" .. (q.level or "?") .. suffix .. "] "
end

-- An objective split for the count column: "Harvest Watcher slain: 13/20"
-- (and the newer "13/20 Harvest Watcher slain") into "Harvest Watcher" and
-- "13/20". " slain" goes on English clients only. No count: the text, nil.
local ENGLISH = (GetLocale and GetLocale() or "enUS"):sub(1, 2) == "en"
local function SplitObjective(text)
    local name, n = text:match("^(.-):%s*(%d+%s*/%s*%d+)%s*$")
    if not name then n, name = text:match("^(%d+%s*/%s*%d+)%s+(.+)$") end
    if not name then return text, nil end
    if ENGLISH then name = (name:gsub(" slain$", "")) end
    return name, (n:gsub("%s", ""))
end
local TICK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"

-- who gives the quest and who takes it in (QuestieDB), with a spot each
local function Ends(q)
    local ok, e = pcall(ns.QuestEnds or error, q.id, curZone)
    return ok and e or nil
end

-- where one of them stands: the sub-zone in this zone, else the zone (or city)
local function PlaceOf(e)
    if not (e and e.map) then return nil end
    if e.map == curZone then
        local area = ns.AreaNameAt and ns.AreaNameAt(e.map, e.x, e.y)
        if area then return area end
    end
    local info = C_Map.GetMapInfo(e.map)
    return info and info.name
end

-- a finished quest's line: who takes it in, and where (turninName). where: for the count column at the right,
-- when the tracker has one (the place lines up there, readable at a glance, the user 2026-11-08 by the Relay)
local function TurninText(q, column)
    local c = Cfg()
    local to = c.turninName ~= false and Ends(q)
    to = to and to.to
    if not (to and to.name) then return "Ready for turn-in" end
    if c.turninStyle == "prefix" then return "Turn in: " .. to.name end
    local where = PlaceOf(to)
    -- (only the place, to try: the user, 2026-11-09; without a place, the name)
    if c.turninStyle == "where" then return where or to.name end
    if column then return to.name, where end
    return where and (to.name .. ", " .. where) or to.name
end

local function QuestColor(q)
    if q.failed then return 1, 0.2, 0.2 end
    if Cfg().levelColors ~= false and GetQuestDifficultyColor and q.level then
        local ok, col = pcall(GetQuestDifficultyColor, q.level)
        if ok and col and col.r then return col.r, col.g, col.b end
    end
    return GOLD[1], GOLD[2], GOLD[3]
end

-- (and pinned by its top-left again: after a drag the game anchors it by the
-- nearest screen corner, and on the right half a wider tracker then grows left)
local function SavePosition()
    local l, t = frame:GetLeft(), frame:GetTop()
    if not (l and t) then return end
    local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    Cfg().pos = { x = l * s, y = t * s }
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
end

local header, scroll, content, edge
local measure  -- (sizes the level column)
local scrollY, contentH = 0, 0

-- A quest's objective areas lit up on the map (the blue "Quest areas"), as the
-- game's quest log does on hover: the map's own "highlighted quest" event,
-- which its quest area layer listens to. nil: back off. Not in combat: the
-- game's quest pins set themselves up in ways it blocks then with an addon
-- on the path (see ns.SafePassthrough).
-- ... and the game's own objective markers of that quest light up as they do
-- under the mouse: their own hover highlight, held on (LockHighlight)
-- ... and behind them, and behind our objective spots and turn-ins of that quest, a faint
-- golden glow (ns.PinGlow, Pin.lua)
local lit = {}  -- markers we're holding lit: [pin] = true
local function HoldHighlight(pin, on)
    ns.PinGlow(pin, on)
    local target = pin.LockHighlight and pin or pin.Button or pin.Display
    if not (target and target.LockHighlight) then return end
    if on then target:LockHighlight() else target:UnlockHighlight() end
end
-- (held: the quest whose glow a click on one of its spots keeps on, ns.ToggleQuestGlow;
-- pointed: the quest of the spot under the mouse, ns.HoverQuestGlow;
-- focus: the quests in focus, glowing for as long as they are, ns.ToggleFocus;
-- paged: the quest whose page is open in the quest window, with questlog.glow)
local held, pointed, paged
local function GlowPins(questID)
    local map = BattlefieldMapFrame
    if not (map and ns.EachPin) then return end
    for pin in pairs(lit) do pcall(HoldHighlight, pin, false) end
    wipe(lit)
    local focus = Focus()
    -- the same on quest ground (QuestGround.lua): each lit quest and why
    if ns.QuestGroundLight then
        local s = {}
        local function St(id, k)
            if not id then return end
            s[id] = s[id] or {}
            s[id][k] = true
        end
        St(questID, "hover")
        St(pointed, "hover")
        St(held, "map")
        St(paged, "page")
        for id in pairs(focus) do St(id, "focus") end
        ns.QuestGroundLight(s)
    end
    if not (questID or held or pointed or paged or next(focus)) then return end
    ns.EachPin(map, function(pin, template)
        local id = ((template == "QuestPinTemplate" or template == "BFIQuestPOIPinTemplate") and pin.questID)
            or (template == "BFIQuestiePinTemplate" and (pin.bfiGroup == "spots" or pin.bfiGroup == "turnins")
                and pin.questId)
        if id and (id == questID or id == held or id == pointed or id == paged or focus[id]) then
            if pcall(HoldHighlight, pin, true) then lit[pin] = true end
        end
    end)
end

local highlighted
local function HighlightOnMap(questID)
    highlighted = questID
    pcall(GlowPins, questID)
    local map = BattlefieldMapFrame
    if not (map and map.TriggerEvent) or InCombatLockdown() then return end
    questID = questID or paged  -- (the open page's areas stay lit after a hover)
    if questID then
        pcall(map.TriggerEvent, map, "SetHighlightedQuestID", questID)
    else
        pcall(map.TriggerEvent, map, "ClearHighlightedQuestID")
    end
end
-- (pins drawn again while you hover: they glow too)
function ns.TrackerRefreshGlow()
    if highlighted or held or pointed or paged or next(Focus()) then pcall(GlowPins, highlighted) end
end
-- a quest in focus, or out of it again (the quest window's Focus button);
-- into focus tracks it too, out of focus leaves it tracked
function ns.ToggleFocus(questID)
    local focus = Focus()
    focus[questID] = not focus[questID] or nil
    if focus[questID] then Watch(questID) end
    ns.UpdateTracker(true)
    pcall(GlowPins, highlighted)  -- (out of focus: its glow goes too)
end
function ns.IsFocused(questID)
    return questID and Focus()[questID] and true or false
end
-- a quest kept lit (held: "find on map", a spot's click) lets go on a click on open
-- map, not a drag (hooked once, on the first)
local function HookOpenClick()
    local sc = BattlefieldMapFrame and BattlefieldMapFrame.ScrollContainer
    if not sc or sc.bfiHeldHooked then return end
    sc.bfiHeldHooked = true
    local downX, downY
    sc:HookScript("OnMouseDown", function() downX, downY = GetCursorPosition() end)
    sc:HookScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" or not held or not downX then return end
        local x, y = GetCursorPosition()
        if math.abs(x - downX) + math.abs(y - downY) > 6 * UIParent:GetEffectiveScale() then return end
        held = nil
        pcall(GlowPins, highlighted)
    end)
end

-- "find on map" (the log's menu): the Battlefield Map opened on the quest's map,
-- its spots glowing until a spot's click or another find
-- (grown: the big map's been asked for already, docked)
function ns.FindQuestOnMap(id, grown)
    local m = ns.QuestFindMap and ns.QuestFindMap(id)
    local map = BattlefieldMapFrame
    if not (m and map) then
        UIErrorsFrame:AddMessage("No place on the map known for this quest", 1, 0.3, 0.1)
        return
    end
    -- docked over the minimap: the big map, beside the square, to find it on
    -- (then a moment for it to grow before it browses there)
    if not grown and ns.Docked and ns.Docked() and not (ns.MapIsBig and ns.MapIsBig()) and ns.ToggleBigMap then
        ns.ToggleBigMap()
        C_Timer.After(0.2, function() ns.Safe("Find on map", ns.FindQuestOnMap, id, true) end)
        return
    end
    if not map:IsShown() and ToggleBattlefieldMap then ToggleBattlefieldMap() end
    if not map:IsShown() then return end
    if ns.BrowseTo then ns.BrowseTo(m) else map:SetMapID(m) end
    held = id
    pcall(GlowPins, highlighted)
    HookOpenClick()
    -- (not in your log: no pins of its own to light, so its giver glows)
    if ns.NotebookPingGiver and not LogIndex(id) then
        ns.NotebookPingGiver(id)
    end
end
-- a click on a quest's objective spot: its glow on until clicked again
-- (another quest's spot: the glow moves to that one)
function ns.ToggleQuestGlow(questID)
    held = held ~= questID and questID or nil
    pcall(GlowPins, highlighted)
    HookOpenClick()
end
-- the mouse on a quest's objective spot: all its spots glow (nil: off again)
function ns.HoverQuestGlow(questID)
    if pointed == questID then return end
    pointed = questID
    pcall(GlowPins, highlighted)
end

-- the list's lines (on the scrolling content)
local function Row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Button", nil, content)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(true)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    -- the level column (levelColumn), the count at the right (countColumn),
    -- the thin rule after a quiet heading (quietHeadings)
    r.lvl = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.lvl:SetJustifyH("LEFT")
    r.lvl:SetWordWrap(false)
    r.count = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.count:SetJustifyH("RIGHT")
    r.count:SetWordWrap(false)
    r.rule = r:CreateTexture(nil, "ARTWORK")
    r.rule:SetHeight(1)
    r.bands = {}   -- (tracker.textShade: Band)
    r:SetScript("OnClick", function(self, button)
        -- a route line (the Lab's): what's to do at that stop, on a click, not on hover
        if self.routeStop then
            if button == "LeftButton" and ns.RouteStepTip then ns.RouteStepTip(self, self.routeStop) end
            if button == "RightButton" and ns.RouteStepMenu then ns.RouteStepMenu(self.routeStop) end
            return
        end
        -- a sub-zone heading: its quests folded away under it, or shown again
        if self.kind == "area" and self.area then
            local c = Cfg()
            c.foldedAreas = c.foldedAreas or {}
            c.foldedAreas[self.area] = not c.foldedAreas[self.area] or nil
            ns.UpdateTracker(true)
            return
        end
        -- "Not tracked (3)": the quests you don't track, shown or folded away
        if self.kind == "untracked" then
            Cfg().showUntracked = not Cfg().showUntracked
            ns.UpdateTracker(true)
            return
        end
        local q = self.quest
        if not q then return end
        if button == "RightButton" then
            -- its menu (Controls' quill menu): its page in the quest log (the quest
            -- window, or the game's when that's off), and find it on the map
            local id = q.id
            local items = {
                { "view details", function()
                    if ns.db.questlog.shown then ns.ShowQuestWindow(id) else OpenLog(id) end
                end },
            }
            if ns.FindQuestOnMap then items[#items + 1] = { "find on map", function() ns.FindQuestOnMap(id) end } end
            items[#items + 1] = { ns.IsFocused(id) and "out of focus" or "focus quest", function() ns.ToggleFocus(id) end }
            -- (a quest the found notes name: its dungeon's "before we go" page)
            local page = ns.NotebookQuestPage and ns.NotebookQuestPage(id)
            if page then items[#items + 1] = { "in the found notes", function() ns.OpenNotebook(page, nil, true) end } end
            if ns.QuillMenu then ns.QuillMenu(items) end
        elseif q.untracked then
            Watch(q.id)  -- (an untracked one: a click tracks it)
            ns.UpdateTracker(true)
        elseif IsShiftKeyDown() then
            ToggleWatch(q.id)  -- (untracked, it leaves the list)
            ns.UpdateTracker(true)
        else
            Cfg().folded[q.id] = not Cfg().folded[q.id] or nil
            ns.UpdateTracker(true)
        end
    end)
    -- a quest's title lights up under the mouse, as in the game's tracker,
    -- and its objective areas light up on the map
    r:SetScript("OnEnter", function(self)
        if self.routeStop or (self.kind == "area" and not self.area) then return end
        if self.kind == "area" or self.kind == "untracked" then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(self.text:GetText() or "")
            ns.Hints({ { "Click", self.kind == "area" and "fold its quests away, or show them again"
                or "show or hide the quests here you don't track; click one of them to track it" } })
            GameTooltip:Show()
            return
        end
        if self.kind ~= "quest" then return end
        self.text:SetTextColor(1, 1, 1)
        HighlightOnMap(self.quest and self.quest.id)
    end)
    r:SetScript("OnLeave", function(self)
        if self.kind == "quest" and self.color then self.text:SetTextColor(unpack(self.color)) end
        if self.kind == "quest" then HighlightOnMap(nil) end
        GameTooltip:Hide()
    end)
    rows[i] = r
    return r
end

-- The tracker's text by kind ("header", "area" / "untracked", "quest",
-- "objective" / "none"): font key, size, outline flags. Sub-zone headings
-- are their own text part (textSub*). With textAsLog the rest follow the
-- quest log's parts (Zone names, Quest names in the list, Quest details);
-- else the tracker's own fonts and sizes, with its Outline setting.
local function TextFor(kind)
    local c = Cfg()
    if kind == "area" or kind == "untracked" then
        return c.textSubFont, c.textSubSize or 11, c.textSubOutline and "OUTLINE" or ""
    end
    local q = ns.db.questlog
    if c.textAsLog and q then
        local part = kind == "header" and "Zone" or (kind == "objective" or kind == "none") and "Detail" or "Quest"
        return q["text" .. part .. "Font"], q["text" .. part .. "Size"] or 12,
            q["text" .. part .. "Outline"] and "OUTLINE" or ""
    end
    if kind == "header" then return c.titleFont, c.headerSize or (c.fontSize or 12) + 1 end
    if kind == "objective" or kind == "none" then return c.textFont, c.objSize or 11 end
    return c.titleFont, c.fontSize or 12
end

-- One line of the list: kind "area", "quest", "objective" or "none"; icon: a
-- texture path; indent: from the left. extra (optional): level, levelColor,
-- levelW (the level column), count, countColor (at the right), rule (a thin
-- rule after the text), flashKey (its key in flashAt). Returns the y below it.
-- a soft dark band under some words (tracker.textShade, tools/text_shade_art.py): a stretched middle with
-- feathered ends of a fixed width, so a long line's ends are as soft as a short one's
local CAP = 12
local function Band(row, i, x, w, h, a)
    local b = row.bands[i]
    if not b then
        b = {}
        for k, l in ipairs({ 0, 0.25, 0.75 }) do
            b[k] = row:CreateTexture(nil, "BACKGROUND")
            b[k]:SetTexture(ns.MEDIA .. "TextShade")
            b[k]:SetTexCoord(l, k == 2 and 0.75 or l + 0.25, 0, 1)
        end
        b[1]:SetPoint("TOPRIGHT", b[2], "TOPLEFT")
        b[3]:SetPoint("TOPLEFT", b[2], "TOPRIGHT")
        row.bands[i] = b
    end
    b[2]:ClearAllPoints()
    b[2]:SetPoint("TOPLEFT", row, "TOPLEFT", x, 5)
    b[2]:SetSize(math.max(1, w), h + 10)
    for k = 1, 3 do
        if k ~= 2 then b[k]:SetSize(CAP, h + 10) end
        b[k]:SetVertexColor(0, 0, 0, a)
        b[k]:Show()
    end
end
local function NoBand(row, i)
    for _, t in ipairs(row.bands[i] or {}) do t:Hide() end
end

local function Line(i, y, width, kind, text, color, quest, icon, indent, extra)
    local row = Row(i)
    extra = extra or {}
    row.kind, row.quest, row.color = kind, quest, color
    row.area, row.routeStop = nil, extra and extra.route
    row.flashKey, row.countColor = extra.flashKey, extra.countColor or color
    local c = Cfg()
    local font, size, flags = TextFor(kind)
    Font(row.text, font, size, flags)
    indent = indent or 0

    -- the level in a column of its own, the title after it
    local x = indent
    if extra.level then
        Font(row.lvl, font, size, flags)
        row.lvl:ClearAllPoints()
        row.lvl:SetPoint("TOPLEFT", indent, 0)
        row.lvl:SetWidth(0)
        row.lvl:SetText(extra.level)
        -- (wider than the column, a tagged one: this line's title moves along)
        local w = math.max(extra.levelW, math.ceil(row.lvl:GetStringWidth()) + 3)
        row.lvl:SetWidth(w)
        local lc = extra.levelColor or color
        row.lvl:SetTextColor(lc[1], lc[2], lc[3])
        row.lvl:Show()
        x = indent + w
    else
        row.lvl:Hide()
    end
    -- the count at the right, the text kept clear of it
    local right = 0
    if extra.count then
        Font(row.count, font, size, flags)
        row.count:ClearAllPoints()
        row.count:SetPoint("TOPRIGHT", 0, 0)
        row.count:SetText(extra.count)
        local cc = row.countColor
        row.count:SetTextColor(cc[1], cc[2], cc[3])
        row.count:Show()
        right = row.count:GetStringWidth() + 8
    else
        row.count:Hide()
    end

    -- the icon, in the gutter left of the title (square, never stretched)
    if icon and c.icons ~= false then
        local s = size + 6
        row.icon:SetSize(s, s)
        local masked, e = false, nil
        if type(icon) == "table" and icon.atlas then
            row.icon:SetAtlas(icon.atlas)
        elseif type(icon) == "table" then
            e = icon.crop or { 0, 1, 0, 1 }
            row.icon:SetTexture(icon.path)
            row.icon:SetTexCoord(e[1], e[2], e[3], e[4])
            masked = icon.mask and true or false
        else
            row.icon:SetTexture(icon)
            row.icon:SetTexCoord(0, 1, 0, 1)
        end
        ns.CursorMask(row, row.icon, masked, e and e[2], e and e[4])
        row.icon:ClearAllPoints()
        -- centred on the first line's letters: a line is a little taller than
        -- the font size, the letters sit low in it
        row.icon:SetPoint("RIGHT", extra.level and row.lvl or row.text, "TOPLEFT", -3,
            -size / 2 - math.floor(size * 0.2 + 0.5))
        row.icon:Show()
    else
        row.icon:Hide()
    end

    row.text:ClearAllPoints()
    row.text:SetPoint("TOPLEFT", x, 0)
    row.text:SetWidth(math.max(20, width - x - right))
    row.text:SetText(text)
    -- the thin rule from the end of the text to the right edge
    if extra.rule then
        local tw = math.min(row.text:GetStringWidth(), row.text:GetWidth())
        row.rule:ClearAllPoints()
        row.rule:SetPoint("LEFT", row.text, "LEFT", tw + 6, 0)
        row.rule:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.rule:SetColorTexture(color[1], color[2], color[3], 0.35)
        row.rule:SetShown(tw + 12 < width - x)
    else
        row.rule:Hide()
    end
    if kind == "quest" and row:IsMouseOver() then
        row.text:SetTextColor(1, 1, 1)  -- (still under the mouse: still lit)
    else
        row.text:SetTextColor(color[1], color[2], color[3])
    end
    local hgt = math.max(row.text:GetStringHeight(), size) + 1
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", content, "TOPLEFT", CAP, -y)  -- (CAP: room for a band's soft left end)
    row:SetSize(width, hgt)
    row.top, row.bottom = y, y + hgt  -- (ScrollTo: what fits whole)
    -- a soft band under the words, so they read with no background: the text, and the count on its own,
    -- nothing under the icons or the gap between (the level column counts as text)
    local shade = c.textShade or 0
    if shade > 0 and text ~= "" then
        local from = extra.level and indent or x
        Band(row, 1, from, x - from + math.min(row.text:GetStringWidth(), row.text:GetWidth()), hgt, shade)
    else
        NoBand(row, 1)
    end
    if shade > 0 and extra.count then
        local cw = row.count:GetStringWidth()
        Band(row, 2, width - cw, cw, hgt, shade)
    else
        NoBand(row, 2)
    end
    -- only the text itself answers the mouse (the tooltip, the clicks): a
    -- quest's title, a sub-zone heading
    local live = kind == "quest" or kind == "area" or row.routeStop ~= nil
    row:EnableMouse(live)
    if live then
        local tw = math.min(row.text:GetStringWidth(), row.text:GetWidth())
        row:SetHitRectInsets(indent, math.max(0, width - x - tw), 0, 0)
    end
    row:Show()
    return y + hgt + (c.lineGap or 1)
end

-- The tracker's border: its own settings, or ("map", the default) exactly the
-- map's, so the two line up. (The map's "game" border is the game's own art,
-- which only the map has: then none.)
local function BorderSpec()
    local c = Cfg()
    if (c.borderStyle or "map") == "map" then
        local b, style = ns.db.border, ns.MapBorderStyle(true)
        return style == "game" and "none" or style, b.size, b.gap, b.color
    end
    return c.borderStyle, c.borderSize, c.borderGap, c.borderColor
end

-- how far that border reaches out past the tracker, and in over it (as
-- ns.DressBorder draws it)
local function BorderReach()
    local style, size, gap = BorderSpec()
    local def = ns.BORDER_STYLES and ns.BORDER_STYLES[style]
    if not def then return 0, 0 end
    local px = math.max(1, math.floor(def.size * (size or 1) + 0.5))
    local out = math.max(0, math.floor(px * (1 - def.overlap) + 0.5) + (gap or 0))
    return out, math.max(0, px - out)
end

-- Attached and both bordered: joined to the map. The tracker's border loses
-- the side facing the map, and the tracker hangs straight off the map's
-- border, so the two read as one frame. (Not with the game's own map border:
-- that sits on the map frame's edge, ours can't meet it.)
local FACING = {  -- the side of the tracker that faces the map, and its corners
    below = { "TopEdge", "TopLeftCorner", "TopRightCorner" },
    above = { "BottomEdge", "BottomLeftCorner", "BottomRightCorner" },
    left  = { "RightEdge", "TopRightCorner", "BottomRightCorner" },
    right = { "LeftEdge", "TopLeftCorner", "BottomLeftCorner" },
}
local function Joined()
    local c = Cfg()
    local style = BorderSpec()
    return c.joinBorders ~= false and not c.detached and FACING[c.attach or "below"] ~= nil
        and ns.BorderOutset and ns.BorderOutset() ~= nil
        and ns.BORDER_STYLES and ns.BORDER_STYLES[style] ~= nil
end

local function Place()
    local map = BattlefieldMapFrame
    local c = Cfg()
    frame:ClearAllPoints()
    -- attached: edge to edge with the map picture (the map's border is drawn
    -- round it). Joined: against the map border's outer edge; else the two
    -- borders clear of each other. With the game's own border (it sits on the
    -- map frame's edge): against the map frame.
    local mapOut = ns.BorderOutset and ns.BorderOutset()
    -- (collapsed, Collapse.lua: the strip that's left of the map, and the game's
    -- border round it)
    local area = mapOut and ns.MapFace(map) or map.BorderFrame or map
    local apart = Joined() and mapOut or (mapOut or 0) + BorderReach() + 2
    if c.detached then
        frame:SetParent(UIParent)
        frame:SetFrameStrata(map:GetFrameStrata())
        frame:SetScale(ns.MapScale())  -- (as big as the map's own text)
        frame:SetWidth(c.width or 220)
        local p = c.pos
        if p then
            local s = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x * s, p.y * s)
        elseif c.startAt == "minimap" and Minimap:GetRight() then
            -- no spot yet, and not to hang off the map (Creator's): where the game's tracker is. By
            -- numbers, not anchored to the minimap: a frame hanging off a protected one can't move in a fight
            local k = Minimap:GetEffectiveScale() / frame:GetEffectiveScale()
            frame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", Minimap:GetRight() * k, Minimap:GetBottom() * k - 24)
        else
            -- no spot yet: under the map, on its screen side (docked in the corner: wider than the square)
            local mr = map:GetRight()
            if mr and mr * map:GetEffectiveScale() > UIParent:GetRight() * UIParent:GetEffectiveScale() / 2 then
                frame:SetPoint("TOPRIGHT", map, "BOTTOMRIGHT", 0, -4)
            else
                frame:SetPoint("TOPLEFT", map, "BOTTOMLEFT", 0, -4)
            end
        end
    else
        frame:SetParent(map)
        frame:SetScale(1)
        if c.attach == "above" then
            frame:SetPoint("BOTTOMLEFT", area, "TOPLEFT", 0, apart)
            frame:SetPoint("BOTTOMRIGHT", area, "TOPRIGHT", 0, apart)
        elseif c.attach == "left" then
            frame:SetPoint("TOPRIGHT", area, "TOPLEFT", -apart, 0)
            frame:SetWidth(c.width or 220)
        elseif c.attach == "right" then
            frame:SetPoint("TOPLEFT", area, "TOPRIGHT", apart, 0)
            frame:SetWidth(c.width or 220)
        else  -- below
            frame:SetPoint("TOPLEFT", area, "BOTTOMLEFT", 0, -apart)
            frame:SetPoint("TOPRIGHT", area, "BOTTOMRIGHT", 0, -apart)
        end
    end
    frame:SetFrameLevel(map:GetFrameLevel() + 5)  -- (a new parent resets it)
    frame:SetMovable(c.detached)
    frame:SetResizable(c.detached)
    -- (not the game's clamping: with the list's full height it threw the tracker
    -- up and to the left; dragging keeps it on the screen itself)
    frame:SetClampedToScreen(false)
    -- on its own: moved by dragging its edges (and the zone name), resized
    -- by the corner grip
    frame:EnableMouse(c.detached)
    if frame.grip then frame.grip:SetShown(c.detached and not c.locked) end
end

-- the zone name over its gold rule, and the fold button: fixed at the top
local function DrawHeader(width)
    local c = Cfg()
    local font, size, flags = TextFor("header")
    Font(header.text, font, size, flags)
    header.text:SetText(zoneName .. "  |cffaaaaaa" .. zoneCount .. "|r")
    header.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    Font(header.fold, font, size + 2, flags)
    header.fold:SetText(c.collapsed and "+" or "-")
    header.fold:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    local h = math.max(header.text:GetStringHeight(), size) + 5
    header:SetSize(width, h)
    header.rule:SetShown(c.headerArt ~= false)
    return h
end

local function ScrollTo(y)
    scrollY = math.max(0, math.min(y, math.max(0, contentH - scroll:GetHeight())))
    scroll:SetVerticalScroll(scrollY)
    -- a line the window would cut through isn't drawn, at either edge (height 0: not placed yet)
    local viewH = scroll:GetHeight()
    for _, r in ipairs(rows) do
        if r:IsShown() and r.top then
            local whole = viewH <= 1 or (r.top >= scrollY - 0.5 and r.bottom <= scrollY + viewH + 0.5)
            r:SetAlpha(whole and 1 or 0)
        end
    end
end

-- The game's own quest tracker, hidden while ours shows (tracker.hideGameTracker).
-- QuestWatchFrame on Classic, WatchFrame on Wrath-style clients,
-- ObjectiveTrackerFrame on modern ones. Only what we hid is shown again. A
-- protected tracker can't be hidden or shown in combat: that waits until after.
local gameHidden = false
local GAME_TRACKERS = { "QuestWatchFrame", "WatchFrame", "ObjectiveTrackerFrame" }
local hooked = {}

local function WantGameHidden()
    local h = ns.db and Cfg().hideGameTracker
    if h == "always" then return true end  -- (even with the map closed or never opened)
    return h and frame and frame:IsShown() and true or false
end

-- ObjectiveTrackerFrame is never hidden from our code: Hide runs the tracker's own
-- scripts under our taint, on every quest update (an OnShow hook did it again each
-- time). With the gamepad UI, closing the map then runs tainted: blocked
-- SetPreferredGamepadInteractTarget (a player's report), and the game's
-- SmartNavigation refuses to give the face buttons back (EnsureIsSecure), so A no
-- longer jumps (Caetras, 2026-11-08). See-through and tiny instead, for mouse
-- players too: Forever switches between mouse and controller mode while playing,
-- so checking the mode once at login left the hook on for anyone who began on the
-- mouse. No scripts run from us, and it can't catch a click.
local faded = {}
local function Fade(f, on)
    if on and not faded[f] then
        faded[f] = f:GetScale()
        f:SetAlpha(0)
        f:SetScale(0.001)
    elseif not on and faded[f] then
        f:SetScale(faded[f])
        f:SetAlpha(1)
        faded[f] = nil
    end
end

local function ApplyGameTracker()
    local want = WantGameHidden()
    if want == gameHidden then return end
    for _, name in ipairs(GAME_TRACKERS) do
        local f = _G[name]
        if f and InCombatLockdown() and f.IsProtected and f:IsProtected() then
            ns.trackerAfterCombat = true  -- (PLAYER_REGEN_ENABLED applies it)
            return
        end
    end
    gameHidden = want
    for _, name in ipairs(GAME_TRACKERS) do
        local f = _G[name]
        if f and name == "ObjectiveTrackerFrame" then
            Fade(f, want)
        elseif f then
            if not hooked[name] then
                hooked[name] = true
                -- the game shows its tracker again on every quest update
                f:HookScript("OnShow", function(self)
                    if gameHidden and not (InCombatLockdown() and self:IsProtected()) then self:Hide() end
                end)
            end
            if want then
                f:Hide()
            else
                f:Show()
                -- (the game hides an empty tracker itself on its next update)
                if name == "QuestWatchFrame" and QuestWatch_Update then pcall(QuestWatch_Update) end
                if name == "WatchFrame" and WatchFrame_Update then pcall(WatchFrame_Update) end
                if name == "ObjectiveTrackerFrame" and f.Update then pcall(f.Update, f) end
            end
        end
    end
end
ns.ApplyGameTracker = ApplyGameTracker
-- "always": from login on, before the map (and our tracker) is ever loaded
do
    local login = CreateFrame("Frame")
    login:RegisterEvent("PLAYER_ENTERING_WORLD")
    login:RegisterEvent("PLAYER_REGEN_ENABLED")  -- (a reload in combat: after the fight)
    login:SetScript("OnEvent", function() if ns.db then pcall(ApplyGameTracker) end end)
end

local function Draw()
    local c = Cfg()
    local map = BattlefieldMapFrame
    -- (detached: with the map closed too)
    local want = map and (map:IsShown() or c.detached) and ns.IsShown("tracker") and (#list > 0 or #untracked > 0 or not c.hideEmpty)
    frame:SetShown(want and true or false)
    ns.trackerDraws = (ns.trackerDraws or 0) + 1  -- (the quest item buttons follow at once)
    ApplyGameTracker()
    if not want then return end

    -- background and border (the map's own, or the map border's styles)
    frame:SetBackdropColor(0, 0, 0, c.bgAlpha or 0)
    if ns.DressBorder then ns.DressBorder(edge, frame, BorderSpec()) end
    -- (the pieces a join hid, back: the same backdrop set again doesn't remake
    -- them, so detached it stayed open until a /reload)
    for _, keys in pairs(FACING) do
        for _, key in ipairs(keys) do
            if edge[key] then edge[key]:Show() end
        end
    end
    -- joined to the map: no border on the side facing it, and the side edges
    -- reach on into the map border's own edge, so the two frames meet
    if Joined() and edge:IsShown() then
        local out, inside = BorderReach()
        local px = out + inside
        for _, key in ipairs(FACING[c.attach or "below"]) do
            if edge[key] then edge[key]:Hide() end
        end
        local reach = out + px * 1.5
        local a = c.attach or "below"
        if a == "below" then edge:SetPoint("TOPLEFT", frame, "TOPLEFT", -out, reach)
        elseif a == "above" then edge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", out, -reach)
        elseif a == "left" then edge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", reach, -out)
        else edge:SetPoint("TOPLEFT", frame, "TOPLEFT", -reach, out) end
    end
    -- the text keeps clear of the border: past what of it lies over the
    -- tracker, and a few pixels more
    local _, inside = BorderReach()
    local pad = math.max(PAD, inside + 4)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", pad, -pad)
    -- (the list reaches a band's end cap past its rows on both sides, so the shade fades
    -- out before a heading and past the counts, not cut off by the scroll; the rows sit
    -- CAP in from the content's left, where they always were on screen)
    scroll:SetPoint("BOTTOMRIGHT", -pad + CAP, pad)

    local width = math.max(60, frame:GetWidth() - pad * 2)
    local headH = DrawHeader(width)

    -- the list
    local gutter = c.icons ~= false and ((c.fontSize or 12) + 10) or 0
    local WHITE, GREY, GREEN = { 1, 1, 1 }, { 0.6, 0.6, 0.6 }, { 0.3, 1, 0.3 }
    content:SetWidth(width + CAP)
    local n = 0  -- (lines used)
    -- the level column (levelColumn): as wide as the widest level shown, its tag left
    -- out: a tagged level (25D) pushes its own title along, the others keep no gap for it
    local lvlW
    if c.levelColumn ~= false then
        measure = measure or content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        measure:Hide()
        local font, size, flags = TextFor("quest")
        Font(measure, font, size, flags)
        local widest = 0
        for _, l in ipairs({ list, untracked }) do
            for _, q in ipairs(l) do
                measure:SetText(q.level or "?")
                widest = math.max(widest, measure:GetStringWidth())
            end
        end
        measure:SetText("88")
        lvlW = math.ceil(math.max(widest, measure:GetStringWidth())) + 3
    end
    -- a quest's title line: "[12+] Title", or the level in its column
    local function QuestLine(y, q, color, icon)
        n = n + 1
        if not lvlW then return Line(n, y, width, "quest", LevelTag(q) .. q.title, color, q, icon, gutter) end
        local title = (c.goldTitles and not q.failed and not q.untracked) and GOLD or color
        return Line(n, y, width, "quest", q.title, title, q, icon, gutter,
            { level = LevelTag(q, true), levelColor = color, levelW = lvlW })
    end
    -- headings: quiet (small capitals, dimmer, a thin rule after) or as before;
    -- other zones' names in gold
    local quiet = c.quietHeadings ~= false
    local function Heading(y, kind, text, zone)
        n = n + 1
        local color = zone and GOLD or quiet and AREA_DIM or AREA_GOLD
        return Line(n, y, width, kind, quiet and text:upper() or text, color, nil, nil, 0, { rule = quiet })
    end
    -- the quests here you don't track: one folded line, "Not tracked (3)";
    -- unfolded, greyed titles to click and track (tracker.showUntracked).
    -- After this zone's quests, before other zones'.
    local function Untracked(y)
        if #untracked == 0 then return y end
        if n > 0 then y = y + (c.questGap or 6) end
        y = Heading(y, "untracked", string.format("Not tracked (%d)", #untracked))
        if c.showUntracked then
            for _, q in ipairs(untracked) do
                q.untracked = true
                y = QuestLine(y, q, GREY, nil)
            end
        end
        return y
    end
    local y = 0
    if not c.collapsed then
        -- (the Lab's quest routes: the next stops, over the quests)
        for _, l in ipairs(ns.RouteLines and ns.RouteLines() or {}) do
            n = n + 1
            y = Line(n, y, width, l.kind, l.text, l.color, nil, nil, l.indent or 0, { route = l.stop })
        end
        if n > 0 then y = y + (c.questGap or 6) + 8 end   -- (a clear gap under the route, the user 2026-11-08)
        if hereCount == 0 then
            n = n + 1
            y = Line(n, y, width, "none", "No tracked quests here", GREY, nil, nil, 0)
        end
        -- each heading's quest count (shown on a folded heading); foldedAreas:
        -- headings folded away, their quests hidden under them
        local counts, cur = {}, nil
        for _, q in ipairs(list) do
            if q.areaHead then cur = q.areaHead counts[cur] = 0 end
            if cur then counts[cur] = counts[cur] + 1 end
        end
        -- (headings: by area, or "In focus" and the zone's name under it)
        local foldedAreas = c.foldedAreas or {}
        local area  -- the heading the quests below fall under
        local untrackedDone = false
        for i, q in ipairs(list) do
            if q.otherZone and not untrackedDone then
                y, untrackedDone = Untracked(y), true
            end
            if q.areaHead then area = q.areaHead end
            local away = area and foldedAreas[area]
            if q.areaHead then
                if n > 0 then y = y + (c.questGap or 6) end
                local text = away and string.format("%s (%d)", q.areaHead, counts[q.areaHead]) or q.areaHead
                y = Heading(y, "area", text, q.zoneHead)
                rows[n].area = q.areaHead
            elseif i > 1 and not away then
                y = y + (c.questGap or 6)
            end
            if not away then
                local objs = q.objs or {}
                -- the icon goes by the first objective still to do
                local objType
                for _, o in ipairs(objs) do
                    if not o.finished then objType = o.type break end
                end
                local r, g, b = QuestColor(q)
                y = QuestLine(y, q, { r, g, b }, Icon(q, objType))
                if not c.folded[q.id] then
                    if q.complete then
                        n = n + 1
                        local who, where = TurninText(q, c.countColumn ~= false)
                        y = Line(n, y, width, "objective", who, GREEN, q, nil, gutter + 4,
                            { flashKey = q.id .. ":done", count = where, countColor = GREEN })
                    elseif q.failed then
                        n = n + 1
                        y = Line(n, y, width, "objective", "Failed", { 1, 0.2, 0.2 }, q, nil, gutter + 4)
                    elseif c.objectives ~= false then
                        for j, o in ipairs(objs) do
                            if not (o.finished and c.hideDoneObjectives) then
                                n = n + 1
                                local color, key = o.finished and GREY or WHITE, q.id .. ":" .. j
                                if c.countColumn ~= false then
                                    -- the name at the left, its count (or a tick) at the right
                                    local name, count = SplitObjective(o.text or "")
                                    if o.finished and c.doneCount == "tick" then count = TICK end
                                    y = Line(n, y, width, "objective", name, color, q, nil, gutter + 4,
                                        { count = count, flashKey = key })
                                else
                                    y = Line(n, y, width, "objective", "- " .. (o.text or ""), color, q, nil,
                                        gutter + 4, { flashKey = key })
                                end
                            end
                        end
                    end
                end
            end
        end
        if not untrackedDone then y = Untracked(y) end
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    contentH = y
    content:SetHeight(math.max(1, y))

    -- as tall as it needs, up to maxHeight; past that the list scrolls. On
    -- its own: the height you gave it with the corner grip (freeHeight)
    local listH = c.collapsed and 0 or y
    local full = pad + headH + (listH > 0 and 4 or 0) + listH + pad
    local cap = c.detached and (c.freeHeight or 260) or (c.maxHeight or 260)
    local height = math.min(full, math.max(headH + pad * 2 + 20, cap))
    if c.detached and not c.collapsed then height = math.max(headH + pad * 2 + 20, cap) end
    frame:SetHeight(height)
    scroll:SetShown(listH > 0)
    ScrollTo(scrollY)
end

-- Fading: to fadeAlpha (%) while the mouse isn't on it (and, attached, with
-- the map's own fading, which it shares)
local alpha = 1
local function UpdateFade(dt)
    local c = Cfg()
    local want = 1
    if c.fadeOut and not frame:IsMouseOver() then want = (c.fadeAlpha or 30) / 100 end
    if alpha ~= want then
        local step = dt * 3
        alpha = math.abs(want - alpha) <= step and want or alpha + (want > alpha and step or -step)
        frame:SetAlpha(alpha)
    end
end

-- An objective that counted up (flashProgress): its line gold, back to
-- its own colour over a second (gold: objectives still to do are white already)
local FLASH = 1.1
local function Mix(fs, col, a)
    fs:SetTextColor(col[1] + (GOLD[1] - col[1]) * a, col[2] + (GOLD[2] - col[2]) * a,
        col[3] + (GOLD[3] - col[3]) * a)
end
local function UpdateFlash()
    local now = GetTime()
    for key, t in pairs(flashAt) do
        if now - t > FLASH then flashAt[key] = nil end
    end
    for _, r in ipairs(rows) do
        local t = r.flashKey and r:IsShown() and r.color and flashAt[r.flashKey]
        if t or r.flashing then
            local a = t and math.max(0, 1 - (now - t) / FLASH) or 0
            Mix(r.text, r.color, a)
            if r.count:IsShown() then Mix(r.count, r.countColor, a) end
            r.flashing = a > 0 or nil
        end
    end
end

-- the fixed header, the scrolling list under it, and the border
local function Build(map)
    frame = CreateFrame("Frame", "WaymarkTracker", map, "BackdropTemplate")
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    frame:SetFrameLevel(map:GetFrameLevel() + 5)
    frame:Hide()
    ns.debugFrames.tracker = frame

    edge = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    edge:SetFrameLevel(frame:GetFrameLevel() + 3)
    edge:EnableMouse(false)
    edge:Hide()

    header = CreateFrame("Button", nil, frame)
    header:SetPoint("TOPLEFT", PAD, -PAD)
    header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    header:RegisterForDrag("LeftButton")
    header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.text:SetPoint("TOPLEFT")
    header.text:SetJustifyH("LEFT")
    header.fold = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.fold:SetPoint("TOPRIGHT", -2, 1)
    -- the gold rule under the zone name, fading out to the right
    header.rule = header:CreateTexture(nil, "ARTWORK")
    header.rule:SetPoint("BOTTOMLEFT", 0, 0)
    header.rule:SetPoint("BOTTOMRIGHT", 0, 0)
    header.rule:SetHeight(1)
    header.rule:SetColorTexture(1, 1, 1, 1)
    if not pcall(header.rule.SetGradient, header.rule, "HORIZONTAL",
                 CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.9), CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.1)) then
        header.rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.7)  -- (older SetGradient)
    end
    header:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            -- its menu (Controls' quill menu): the quest log first, then lock in
            -- place (on its own only), hide
            local c = Cfg()
            local items = {}
            if ns.QuestLogFromMenu then
                items[1] = { ns.QuestWindowShown() and "close the quest log" or "open the quest log", ns.QuestLogFromMenu }
            end
            if c.detached then
                items[#items + 1] = { c.locked and "unlock" or "lock in place", function()
                    c.locked = not c.locked
                    ns.OnSettingChanged("tracker", "locked")
                end }
            end
            items[#items + 1] = { "hide", function() ns.ToggleLayer("tracker", "shown") end }
            if ns.QuillMenu then ns.QuillMenu(items) end
            return
        end
        Cfg().collapsed = not Cfg().collapsed
        ns.UpdateTracker(true)
    end)
    header:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Quest tracker: " .. zoneName)
        ns.Hints({ { "Click", Cfg().collapsed and "show the quests" or "hide the quests" },
                   Cfg().detached and not Cfg().locked and { "Drag", "move it" } or nil, { "Right-click", "menu" } })
        GameTooltip:Show()
    end)
    header:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Detached: dragged by its header or its edges. Moved by our own hand, the
    -- cursor's travel added to where it was: the game's StartMoving, with the
    -- frame clamped to the screen, threw it up and to the left on the grab.
    local mover = CreateFrame("Frame")
    mover:Hide()
    local function DragStart()
        if not (Cfg().detached and not Cfg().locked) then return end
        local l, t = frame:GetLeft(), frame:GetTop()
        if not (l and t) then return end
        local cx, cy = GetCursorPosition()
        local s = frame:GetEffectiveScale()
        frame.bfiMoving = true
        -- (kept on the screen by hand: its top and some of it always in reach)
        local k = UIParent:GetEffectiveScale() / s
        local sw, sh = UIParent:GetWidth() * k, UIParent:GetHeight() * k
        local w = frame:GetWidth()
        mover:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local nl = math.max(40 - w, math.min(sw - 40, l + (x - cx) / s))
            local nt = math.max(24, math.min(sh, t + (y - cy) / s))
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", nl, nt)
        end)
        mover:Show()
    end
    local function DragStop()
        if not frame.bfiMoving then return end
        mover:Hide()
        mover:SetScript("OnUpdate", nil)
        frame.bfiMoving = nil
        if Cfg().detached then SavePosition() end
    end
    header:SetScript("OnDragStart", DragStart)
    header:SetScript("OnDragStop", DragStop)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", DragStart)
    frame:SetScript("OnDragStop", DragStop)

    -- ... and its bottom-right corner to resize it (width, and the height the
    -- list scrolls in)
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(edge:GetFrameLevel() + 1)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:Hide()
    frame.grip = grip
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or not Cfg().detached or Cfg().locked then return end
        SavePosition()  -- (grows right and down from where it is)
        local x0, y0 = GetCursorPosition()
        local w0, h0 = frame:GetWidth(), frame:GetHeight()
        grip:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local s = frame:GetEffectiveScale()
            local c = Cfg()
            c.width = math.max(140, math.min(800, w0 + (x - x0) / s))
            c.freeHeight = math.max(60, math.min(1000, h0 + (y0 - y) / s))
            frame:SetWidth(c.width)
            ns.Safe("Tracker Draw", Draw)
        end)
    end)
    grip:SetScript("OnMouseUp", function()
        grip:SetScript("OnUpdate", nil)
        ns.UpdateTracker(true)
    end)
    grip:SetScript("OnEnter", function()
        GameTooltip:SetOwner(grip, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine("Resize")
        ns.Hints({ { "Drag", "width and height" }, { "Drag an edge", "move it" } })
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- the list: scrolls with the mouse wheel, no scroll bar
    scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -CAP, -4)
    scroll:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        ScrollTo(scrollY - delta * ((Cfg().fontSize or 12) + (Cfg().lineGap or 1)) * 3)
    end)
end

local placedScale
function ns.UpdateTracker(now)
    if not frame then pcall(ApplyGameTracker) return end  -- (map not loaded: "always" still applies)
    if now then dirty = true end
    -- placed again on a settings change or a new map scale; not every second
    -- (that would fight a drag)
    -- (attached, or on its own with no spot yet: every time, so it follows the map)
    if (now or placedScale ~= ns.MapScale() or not Cfg().detached or not Cfg().pos) and not frame.bfiMoving then
        placedScale = ns.MapScale()
        ns.Safe("Tracker Place", Place)
    end
    ns.Safe("Tracker Collect", Collect)
    ns.Safe("Tracker Draw", Draw)
    ns.TrackerRefreshGlow()
    -- the quest window reaches down to the tracker's bottom: follows its height
    if ns.PlaceQuestWindow then ns.PlaceQuestWindow() end
    dirty = false
end

-- for /bfi check
function ns.TrackerInfo()
    if not frame then return "not set up" end
    local c = Cfg()
    return string.format("%s, %s, %d quests in %s, sort %s, %dx%d", frame:IsShown() and "shown" or "hidden",
        c.detached and "detached" or c.attach or "?", #list, zoneName ~= "" and zoneName or "?", c.sort or "?", frame:GetWidth(), frame:GetHeight())
end

-- Quest window ---------------------------------------------------------------------

-- A quest's page beside the map, built from the same art and fonts as the
-- game's own quest log page on Forever (QuestMapFrame.DetailsFrame, read with
-- /bfi questart): the parchment in its frame, the title, objectives and
-- description, the Rewards panel, and Abandon / Share / Track / Focus along the
-- bottom. Opened by right-clicking a quest in the tracker (and, by its
-- settings, a quest's spot or turn-in on the map, or the quest log key).
-- Its settings: ns.db.questlog (the Quest log page; BattlefieldInfo.lua lists
-- them). Attached beside the map, or detached: dragged by its top bar, scaled
-- by its corner grip, its height by its bottom edge.

local FRIZ, MORPHEUS, ARIALN = "Fonts\\FRIZQT__.TTF", "Fonts\\MORPHEUS.ttf", "Fonts\\ARIALN.TTF"
local INK = { 0.18, 0.12, 0.06 }          -- the page's text
local BLACK = { 0, 0, 0 }                 -- its headings
local TAN = { 0.9, 0.79, 0.67 }           -- the Rewards panel's text
local QW_W, QW_H = 307, 558  -- the window, as wide as its parchment page (its height: joined to the map)
local SCROLL_R = 283  -- the scrolling area's right edge; the 17 px scroll bar just past it, on the parchment
local TEXT_W = 270    -- the page's text, clear of the scroll bar
local BTN_BAR = 26  -- the strip along the bottom the buttons sit in

local qw          -- the window
local qwQuest     -- the quest it shows
local lastQuest   -- the one last shown (the quest log key opens it again)

local function QCfg() return ns.db.questlog end

-- the page's colours (questlog.paper): text, headings, finished objectives,
-- small print
local PAPERS = {
    -- text, titles, small print, sections; 5: a soft warning ("Not in your log")
    parchment = { INK, BLACK, { 0.4, 0.35, 0.3 }, { 0.36, 0.25, 0.12 }, { 0.66, 0.27, 0.13 } },
    dark = { { 0.92, 0.9, 0.85 }, { 1, 0.82, 0 }, { 0.55, 0.55, 0.55 }, { 0.75, 0.7, 0.6 }, { 0.95, 0.55, 0.38 } },
}

local function PageFont(fs, file, size, color, width, flags)
    fs:SetFont(file, size, flags or "")
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetShadowOffset(0, 0)
    fs:SetJustifyH("LEFT")
    if width then fs:SetWidth(width) end
end

-- The quest window's text parts (questlog.text<Part>Font / Size / Outline,
-- the Quest log text settings): Head (the log's heading), Zone, Quest (names
-- in the log), Title, Sect (section headings), Detail, Small (small print),
-- Chain (its steps). Returns its file, size and outline flag.
local function Part(name)
    local c = QCfg()
    return ns.FontFile(c["text" .. name .. "Font"]), c["text" .. name .. "Size"] or 13,
        c["text" .. name .. "Outline"] and "OUTLINE" or nil
end
-- a page string in a part (d: that much smaller, for its lesser lines)
local function PartFont(fs, name, color, width, d)
    local file, size, flags = Part(name)
    PageFont(fs, file, size - (d or 0), color, width, flags)
    return size
end

-- the quest's entry selected in the game's quest log (the reward and text
-- calls read the selected one)
local function SelectQuest(id)
    local index = LogIndex(id)
    if not index then return end
    if C_QuestLog and C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(id)
    elseif SelectQuestLogEntry then SelectQuestLogEntry(index) end
    return index
end

-- a count from the game, asked by quest ID (Forever) or of the selected quest
local function Count(fn, id)
    if not fn then return 0 end
    local ok, n = pcall(fn, id)
    if ok and type(n) == "number" then return n end
    ok, n = pcall(fn)
    return ok and type(n) == "number" and n or 0
end

local function QualityColor(q)
    if C_Item and C_Item.GetItemQualityColor then
        local ok, r, g, b = pcall(C_Item.GetItemQualityColor, q)
        if ok and r then return r, g, b end
    end
    if GetItemQualityColor then return GetItemQualityColor(q) end
    return 1, 1, 1
end

-- one reward slot: icon, the name box, its count
local function RewardSlot(i)
    qw.slots = qw.slots or {}
    if qw.slots[i] then return qw.slots[i] end
    local b = CreateFrame("Button", nil, qw.rewards.items)
    b:SetSize(134, 30)
    b.icon = b:CreateTexture(nil, "BACKGROUND")
    b.icon:SetSize(30, 30)
    b.icon:SetPoint("TOPLEFT")
    b.nameFrame = b:CreateTexture(nil, "BACKGROUND")
    b.nameFrame:SetSize(102, 30)
    b.nameFrame:SetPoint("LEFT", b.icon, "RIGHT", 2, 0)
    ns.SetArt(b.nameFrame, "QuestItemBorder")
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetSize(30, 30)
    b.border:SetPoint("TOPLEFT", b.icon)
    ns.SetArt(b.border, 651080)  -- (the quality border round the icon)
    b.name = b:CreateFontString(nil, "ARTWORK")
    b.name:SetPoint("LEFT", b.nameFrame, "LEFT", 4, 0)
    b.name:SetHeight(36)
    b.count = b:CreateFontString(nil, "OVERLAY")
    b.count:SetFont(ARIALN, 12, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 0, 1)
    b:SetScript("OnEnter", function(self)
        if not self.kind then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.kind == "item" then  -- (a preview's, from our data: the item itself)
            ns.ItemTip(self.index, self.name and self.name:GetText())
        else
            if qwQuest then SelectQuest(qwQuest) end
            pcall(GameTooltip.SetQuestLogItem, GameTooltip, self.kind, self.index)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- as the game's reward buttons: Shift-click links it in chat, Ctrl-click tries it on
    b:SetScript("OnClick", function(self)
        if not self.kind then return end
        local link
        if self.kind == "item" then
            link = select(2, GetItemInfo(self.index))
            if not link and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, self.index) end
        else
            if qwQuest then SelectQuest(qwQuest) end
            local ok, l = pcall(GetQuestLogItemLink, self.kind, self.index)
            link = ok and l or nil
        end
        if not link then return end
        if HandleModifiedItemClick then
            HandleModifiedItemClick(link)
        elseif IsShiftKeyDown() and ChatEdit_InsertLink then
            ChatEdit_InsertLink(link)
        end
    end)
    qw.slots[i] = b
    return b
end

-- the button strip along the bottom: kept for a log quest's buttons; a preview has none,
-- so its page and Rewards panel reach the bottom (the panel's foot the window's edge)
local function ButtonBar(on)
    local bar = on and BTN_BAR or 0
    qw.page:SetPoint("BOTTOMLEFT", 0, bar)
    qw.rewards:SetPoint("BOTTOMLEFT", 0, bar)
    return bar
end

-- the Rewards panel's contents; returns its height (0: no rewards). own: a quest not
-- in your log (the preview): its rewards from our data (ns.QuestRewards), not the log's
local function FillRewards(id, own)
    local items = qw.rewards.items
    for _, s in ipairs(qw.slots or {}) do s:Hide() end
    qw.chooseText:Hide()
    qw.receiveText:Hide()
    local n, y = 0, 0
    local function Grid(fill)
        local col = 0
        local rowY = y
        for _, f in ipairs(fill) do
            n = n + 1
            local s = RewardSlot(n)
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", items, "TOPLEFT", col * (134 + 8), -rowY)
            f(s)
            s:Show()
            col = col + 1
            if col == 2 then col, rowY = 0, rowY + 35 end
        end
        y = rowY + (col > 0 and 35 or 0)
    end
    local function Item(kind, index, name, texture, count, quality, usable)
        return function(s)
            s.kind, s.index = kind, index
            s.icon:SetTexture(texture)
            local red = usable == false
            s.icon:SetVertexColor(1, red and 0 or 1, red and 0 or 1)
            s.nameFrame:SetVertexColor(red and 0.9 or 1, red and 0 or 1, red and 0 or 1)
            if quality and quality >= 2 then
                s.border:SetVertexColor(QualityColor(quality))
                s.border:Show()
            else
                s.border:Hide()
            end
            PageFont(s.name, FRIZ, 10, { 1, 1, 1 }, 92)
            s.name:SetText(name or "")
            s.count:SetText((count or 0) > 1 and count or "")
        end
    end

    -- our data's { itemID, name, count } as the log's slot fill
    local function Own(e)
        local _, _, quality, _, _, _, _, _, _, texture = GetItemInfo(e[1])
        if not quality and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, e[1]) end
        return Item("item", e[1], GetItemInfo(e[1]) or e[2], texture or (GetItemIcon and GetItemIcon(e[1])), e[3], quality)
    end
    local choices = own and #own.choice or Count(GetNumQuestLogChoices, id)
    if own and choices > 0 then
        qw.chooseText:SetPoint("TOPLEFT", items, "TOPLEFT", 0, -y)
        qw.chooseText:Show()
        y = y + 15
        local fill = {}
        for _, e in ipairs(own.choice) do fill[#fill + 1] = Own(e) end
        Grid(fill)
    elseif choices > 0 then
        qw.chooseText:SetPoint("TOPLEFT", items, "TOPLEFT", 0, -y)
        qw.chooseText:Show()
        y = y + 15
        local fill = {}
        for i = 1, choices do
            local name, texture, count, quality, usable = GetQuestLogChoiceInfo(i)
            fill[#fill + 1] = Item("choice", i, name, texture, count, quality, usable)
        end
        Grid(fill)
    end
    local fill = {}
    for _, e in ipairs(own and own.fixed or {}) do fill[#fill + 1] = Own(e) end
    for i = 1, own and 0 or Count(GetNumQuestLogRewards, id) do
        local ok, name, texture, count, quality, usable = pcall(GetQuestLogRewardInfo, i, id)
        if not (ok and name) then ok, name, texture, count, quality, usable = pcall(GetQuestLogRewardInfo, i) end
        if ok and name then fill[#fill + 1] = Item("reward", i, name, texture, count, quality, usable) end
    end
    local xp = own and (ns.QuestXP and ns.QuestXP(own.id) or 0) or Count(GetQuestLogRewardXP, id)
    if xp > 0 then
        fill[#fill + 1] = function(s)
            s.kind = nil
            ns.SetArt(s.icon, 894556)
            s.icon:SetVertexColor(1, 1, 1)
            s.nameFrame:SetVertexColor(1, 1, 1)
            s.border:Hide()
            PageFont(s.name, ARIALN, 14, { 1, 1, 1 }, 92)
            s.name:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or xp)
            s.count:SetText("")
        end
    end
    local money = own and (own.copper or 0) or Count(GetQuestLogRewardMoney, id)
    if money > 0 then
        fill[#fill + 1] = function(s)
            s.kind = nil
            ns.SetArt(s.icon, 133784)
            s.icon:SetVertexColor(1, 1, 1)
            s.nameFrame:SetVertexColor(1, 1, 1)
            s.border:Hide()
            PageFont(s.name, FRIZ, 12, { 1, 1, 1 }, 92)
            s.name:SetText(GetCoinTextureString and GetCoinTextureString(money) or tostring(money))
            s.count:SetText("")
        end
    end
    if #fill > 0 then
        qw.receiveText:SetText(choices > 0 and "You will also receive:" or "You will receive:")
        qw.receiveText:SetPoint("TOPLEFT", items, "TOPLEFT", 0, -y)
        qw.receiveText:Show()
        y = y + 15
        Grid(fill)
    end
    if n == 0 then return 0 end
    return math.max(120, 52 + y + 20)
end

local function UpdateScrollBar()
    local sc, bar = qw.scroll, qw.bar
    local range = math.max(0, qw.contentH - sc:GetHeight())
    bar:SetShown(range > 0)
    if range <= 0 then return end
    local trackH = bar.track:GetHeight()
    local thumbH = math.max(24, trackH * sc:GetHeight() / qw.contentH)
    bar.thumb:SetHeight(thumbH)
    bar.thumb:ClearAllPoints()
    bar.thumb:SetPoint("TOP", bar.track, "TOP", 0, -(trackH - thumbH) * (qw.scrollY / range))
end

local function ScrollPage(y)
    qw.scrollY = math.max(0, math.min(y, math.max(0, qw.contentH - qw.scroll:GetHeight())))
    qw.scroll:SetVerticalScroll(qw.scrollY)
    UpdateScrollBar()
end

local FillQuestWindow

-- The window is split (always since 2026-11-03; questlog.list was its switch): the log at the
-- top (listShare of the room under the top bar, its own scroll, a darker
-- parchment), the selected quest's page below, a faint line between them
-- that drags to share the room. The page can show a quest's chain
-- (questlog.chain, QuestieDB); a step not in your log shows there as a
-- preview (qwPreview) instead of the quest's own page.
local qwPreview   -- a chain step not in your log, shown on the page
local revealSel   -- scroll the log to the selected quest (opened from outside)
local LOG_TOP = 43  -- under the top bar
local DIVIDER = 6
local LOG_W = 283   -- the log's lines (its thin scroll mark just right of them)

-- a quest's page (from the tracker, a pin, the key, the log or its chain);
-- reveal: scroll the log to it
local function ShowQuest(id, reveal)
    qwQuest, lastQuest, qw.scrollY, qwPreview = id, id, 0, nil
    revealSel = reveal
    paged = QCfg().glow and id or nil  -- (its spots and areas lit while it's open)
    pcall(HighlightOnMap, highlighted)
    ns.Safe("Quest window", FillQuestWindow)
end

-- a chain step that isn't in your log
local function ShowPreview(id)
    qwPreview, qw.scrollY = id, 0
    revealSel = true  -- (the log to its top: the quest's own section, FillList)
    ns.Safe("Quest window", FillQuestWindow)
end

-- the first quest in the log (none chosen yet, or the chosen one gone)
local function FirstQuest()
    for i = 1, NumEntries() do
        local e = Entry(i)
        if e and not e.isHeader and e.id then return e.id end
    end
end

-- the log's scroll, and its thin mark at the right
local function LogScroll(y)
    local sc = qw.logScroll
    local h = sc:GetHeight()
    local range = math.max(0, (qw.logH or 0) - h)
    qw.logY = math.max(0, math.min(y or 0, range))
    sc:SetVerticalScroll(qw.logY)
    local mark = qw.logMark
    mark:SetShown(range > 0)
    if range > 0 then
        local mh = math.max(12, h * h / qw.logH)
        mark:SetHeight(mh)
        mark:ClearAllPoints()
        mark:SetPoint("TOPLEFT", sc, "TOPRIGHT", 6, -(h - mh) * qw.logY / range)
    end
end

-- the log's height (listShare of the room) and the page under it
local function LayoutPanes()
    local c = QCfg()
    local on = true  -- (the log always there)
    qw.logPane:SetShown(on)
    qw.divider:SetShown(on)
    local top = LOG_TOP
    if on then
        local room = qw:GetHeight() - LOG_TOP - BTN_BAR
        local h = math.floor(room * math.max(0.15, math.min(0.6, c.listShare or 0.27)))
        qw.logPane:SetHeight(h)
        top = LOG_TOP + h + DIVIDER
    end
    qw.scroll:SetPoint("TOPLEFT", 5, -top)
end

-- The log's looks (questlog.logStyle): its pane's tint, and the colours of
-- its heading (head), small print (small), zone headings (zone), quest
-- titles (text, selText when selected), (Complete) / (Failed), the bands
-- for the mouse (hover) and the selected quest (sel). levels: the colours by
-- difficulty (grey, green, yellow, orange, red; "game": the game's own).
-- shadow: a dark shadow under its text. (Fonts and sizes: the text parts.)
local LOG_STYLES = {
    parchment = {
        tint = { 0.3, 0.18, 0.06, 0.13 }, head = BLACK, small = { 0.36, 0.25, 0.12 }, zone = { 0.23, 0.13, 0.03 },
        text = INK, done = { 0.93, 0.68, 0.05 }, failed = { 0.61, 0.11, 0.07 },
        hover = { 1, 1, 1, 0.15 }, sel = { 1, 1, 1, 0.25 },
        levels = { { 0.44, 0.42, 0.38 }, { 0.18, 0.42, 0.12 }, { 0.54, 0.42, 0 }, { 0.64, 0.3, 0.05 }, { 0.61, 0.11, 0.07 } },
    },
    classic = {
        -- (solid: at 0.9 the Parchment page came through brown; on the Dark page it looked right)
        tint = { 0.05, 0.04, 0.03, 1 }, head = { 1, 0.82, 0 }, small = { 0.66, 0.6, 0.5 }, zone = { 0.79, 0.76, 0.7 },
        text = { 1, 0.82, 0 }, selText = { 1, 1, 1 }, done = { 1, 0.82, 0 }, failed = { 1, 0.25, 0.25 },
        hover = { 1, 1, 1, 0.08 }, sel = { 1, 0.82, 0, 0.2 },
        levels = "game", shadow = true,
    },
    leather = {
        tint = { 0.2, 0.13, 0.07, 0.95 }, head = { 0.94, 0.85, 0.66 }, small = { 0.7, 0.6, 0.45 }, zone = { 0.91, 0.78, 0.48 },
        text = { 0.95, 0.9, 0.78 }, selText = { 1, 1, 1 }, done = { 1, 0.81, 0.23 }, failed = { 1, 0.35, 0.27 },
        hover = { 1, 1, 1, 0.07 }, sel = { 0.94, 0.85, 0.66, 0.15 },
        levels = { { 0.65, 0.62, 0.56 }, { 0.5, 0.81, 0.35 }, { 0.95, 0.83, 0.29 }, { 0.94, 0.53, 0.29 }, { 1, 0.35, 0.27 } },
        shadow = true,
    },
}
-- (on the dark page, the parchment look takes the dark page's colours)
local DARK_LOG = {
    tint = { 0, 0, 0, 0.25 }, head = { 1, 0.82, 0 }, small = { 0.75, 0.7, 0.6 }, zone = { 1, 0.82, 0 },
    text = { 0.92, 0.9, 0.85 }, done = { 1, 0.82, 0 }, failed = { 1, 0.3, 0.25 },
    hover = { 1, 1, 1, 0.1 }, sel = { 1, 1, 1, 0.18 }, levels = "game",
}
-- (and with listGoldTitles, its quest titles in the game's gold, white when selected)
local DARK_GOLD = setmetatable({ text = { 1, 0.82, 0 }, selText = { 1, 1, 1 } }, { __index = DARK_LOG })
local function LogStyle()
    local c = QCfg()
    if not LOG_STYLES[c.logStyle] then c.logStyle = "leather" end  -- (the ink look is gone)
    local st = LOG_STYLES[c.logStyle]
    if st == LOG_STYLES.parchment and c.paper == "dark" then
        return c.listGoldTitles and DARK_GOLD or DARK_LOG
    end
    return st
end

-- difficulty colours for levels (levels: a look's own five, or "game")
local function LevelColor(level, levels)
    level = level or 0
    if levels == "game" and GetQuestDifficultyColor then
        local ok, col = pcall(GetQuestDifficultyColor, level)
        if ok and col then return { col.r, col.g, col.b } end
    end
    local five = type(levels) == "table" and levels or LOG_STYLES.parchment.levels
    local d = level - UnitLevel("player")
    if d >= 5 then return five[5] elseif d >= 3 then return five[4] elseif d >= -2 then return five[3]
    elseif not Trivial(level) then return five[2] end
    return five[1]
end

-- a line with a mark or level before it, text, a tag at its right end; a
-- band when selected (sel) with a bar at its left; a rule under it (zones).
-- Used by the log and the chain.
local function LineButton(parent, onClick)
    local r = CreateFrame("Button", nil, parent)
    r.level = r:CreateFontString(nil, "ARTWORK")
    r.level:SetPoint("LEFT")
    r.level:SetWidth(22)
    r.mark = r:CreateTexture(nil, "ARTWORK")
    r.mark:SetSize(12, 12)
    r.mark:SetPoint("LEFT", 2, 0)
    r.text = r:CreateFontString(nil, "ARTWORK")
    r.tag = r:CreateFontString(nil, "ARTWORK")
    r.tag:SetPoint("RIGHT", -3, 0)
    r.rule = r:CreateTexture(nil, "BACKGROUND")
    r.rule:SetHeight(1)
    r.rule:SetPoint("BOTTOMLEFT")
    r.rule:SetPoint("BOTTOMRIGHT")
    r.sel = r:CreateTexture(nil, "BACKGROUND")
    r.sel:SetAllPoints()
    r.sel:SetColorTexture(1, 1, 1, 0.25)
    r.bar = r:CreateTexture(nil, "ARTWORK")
    r.bar:SetWidth(2)
    r.bar:SetPoint("TOPLEFT")
    r.bar:SetPoint("BOTTOMLEFT")
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.15)
    -- (a font from the start: SetText on a string without one is an error)
    for _, fs in ipairs({ r.level, r.text, r.tag }) do PageFont(fs, FRIZ, 12, INK) end
    r:SetScript("OnClick", onClick)
    return r
end
-- set one up for a fresh use: kind, where (x, y in its parent), width, height,
-- text starting at textX
local function LineSetup(r, kind, x, y, w, h, textX)
    r.kind = kind
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", x, -y)
    r:SetSize(w, h)
    r.rule:Hide()
    r.sel:Hide()
    r.bar:Hide()
    r.level:Hide()
    r.mark:Hide()
    r.tag:SetText("")
    r.hl:SetColorTexture(1, 1, 1, 0.15)
    r.text:ClearAllPoints()
    r.text:SetPoint("LEFT", textX, 0)
    r.text:SetPoint("RIGHT", r.tag, "LEFT", -4, 0)
    r.text:SetWordWrap(false)
    r:Show()
end
-- (band: its colour, { r, g, b, a }; default a light one)
local function Selected(r, ink, band)
    band = band or { 1, 1, 1, 0.25 }
    r.sel:SetColorTexture(band[1], band[2], band[3], band[4])
    r.sel:Show()
    r.bar:SetColorTexture(ink[1], ink[2], ink[3], 1)
    r.bar:Show()
end

-- the log's lines: its heading, a zone (click: fold it), a quest (click: its page)
local function ListRow(i)
    qw.listRows = qw.listRows or {}
    local r = qw.listRows[i]
    if r then return r end
    r = LineButton(qw.logContent, function(self, button)
        if self.kind == "quest" and button == "RightButton" then
            -- its menu (Controls' quill menu)
            local id = self.questID
            local items = { { "find on map", function() ns.FindQuestOnMap(id) end } }
            local page = ns.NotebookQuestPage and ns.NotebookQuestPage(id)
            if page then items[#items + 1] = { "in the found notes", function() ns.OpenNotebook(page, nil, true) end } end
            items[#items + 1] = { IsWatched(id, LogIndex(id)) and "untrack" or "track", function()
                ToggleWatch(id)
                ns.UpdateTracker(true)
                ns.Safe("Quest window", FillQuestWindow)
            end }
            if ns.QuillMenu then ns.QuillMenu(items) end
            return
        end
        -- (the quest being looked at, not in your log: find it, its giver's map)
        if self.kind == "look" and button == "RightButton" and self.previewID then
            local id = self.previewID
            local items = { { "find on map", function() ns.FindQuestOnMap(id) end } }
            local page = ns.NotebookQuestPage and ns.NotebookQuestPage(id)
            if page then items[#items + 1] = { "in the found notes", function() ns.OpenNotebook(page, nil, true) end } end
            if ns.QuillMenu then ns.QuillMenu(items) end
            return
        end
        if button == "RightButton" then return end
        if self.kind == "quest" and IsShiftKeyDown() then
            ToggleWatch(self.questID)  -- (shift-click: track, as in the game's log)
            ns.UpdateTracker(true)
            ns.Safe("Quest window", FillQuestWindow)
        elseif self.kind == "quest" then
            ShowQuest(self.questID)
        elseif self.kind == "zone" and IsShiftKeyDown() then
            -- shift-click a zone: track every quest in it; all tracked already:
            -- untrack them all (3 of 10 tracked: 10, then 0)
            local all = true
            for _, e in ipairs(self.quests or {}) do
                if e.id and not IsWatched(e.id, LogIndex(e.id)) then all = false end
            end
            for _, e in ipairs(self.quests or {}) do
                if e.id and (IsWatched(e.id, LogIndex(e.id)) and true or false) == all then ToggleWatch(e.id) end
            end
            ns.UpdateTracker(true)
            ns.Safe("Quest window", FillQuestWindow)
        elseif self.kind == "zone" then
            QCfg().zoneOpen[self.zone] = not self.open
            ns.Safe("Quest window", FillQuestWindow)
        elseif self.kind == "head" then
            -- the heading: any zone open folds them all, else opens them all
            local open, anyOpen = QCfg().zoneOpen, false
            for _, isOpen in pairs(qw.logZones or {}) do anyOpen = anyOpen or isOpen end
            for z in pairs(qw.logZones or {}) do open[z] = not anyOpen end
            ns.Safe("Quest window", FillQuestWindow)
        end
    end)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- tracked: a tick at its left (shift-click the quest to track it)
    local w = r:CreateTexture(nil, "OVERLAY")
    w:SetSize(16, 16)
    w:SetPoint("LEFT", -1, 0)
    w:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    r.watch = w
    qw.listRows[i] = r
    return r
end

-- the log pane in the current look (tint, its scroll mark)
local function ApplyLogStyle()
    local st = LogStyle()
    local t = st.tint
    qw.logPane.tint:SetColorTexture(t[1], t[2], t[3], t[4])
    local z = st.zone
    qw.logMark:SetColorTexture(z[1], z[2], z[3], 0.45)
end

-- the whole log: under each zone (yours first, the others folded at first,
-- by the settings), the level before each quest in difficulty colours,
-- (Complete) / (Failed) at the end, all in the look chosen
-- (questlog.logStyle). Returns its height, and where the selected quest is
-- (to scroll to)
local function FillList(colors, dark)
    local c = QCfg()
    local st = LogStyle()
    ApplyLogStyle()
    local here = GetRealZoneText and GetRealZoneText() or ""
    local groups, group, count = {}, nil, 0
    for i = 1, NumEntries() do
        local e = Entry(i)
        if e and e.isHeader then
            group = { zone = e.title or "", quests = {} }
            groups[#groups + 1] = group
        elseif e and e.id then
            if not group then
                group = { zone = "", quests = {} }
                groups[#groups + 1] = group
            end
            group.quests[#group.quests + 1] = e
            if e.id == qwQuest and revealSel and not qwPreview then c.zoneOpen[group.zone] = true end  -- (shown, to scroll to)
            count = count + 1
        end
    end
    if c.listHereFirst then
        for i, g in ipairs(groups) do
            if g.zone == here and i > 1 then
                table.remove(groups, i)
                table.insert(groups, 1, g)
                break
            end
        end
    end
    -- the log's text in its parts: their outline (never plain parchment on
    -- the parchment page, where it smudged the ink), a shadow as the look has
    -- it. d: that much smaller; file: another font at the part's size.
    local inked = st == LOG_STYLES.parchment
    local function Face(fs, part, color, shadow, d, file)
        local pf, size, flags = Part(part)
        PageFont(fs, file or pf, size - (d or 0), color, nil, not inked and flags or nil)
        if shadow then
            fs:SetShadowColor(0, 0, 0, 0.9)
            fs:SetShadowOffset(1, -1)
        end
    end
    local y, n, selY = 2, 0, nil
    local function Line(kind, indent, h, textX)
        n = n + 1
        local r = ListRow(n)
        LineSetup(r, kind, indent, y, LOG_W - indent, h, textX)
        local hv = st.hover
        r.hl:SetColorTexture(hv[1], hv[2], hv[3], hv[4])
        r.watch:Hide()
        y = y + h
        return r
    end
    local _, hs = Part("Head")
    local _, zs = Part("Zone")
    local _, qs = Part("Quest")
    -- (each zone open or not, for the heading's click: fold or open them all)
    qw.logZones = {}
    local anyOpen = false
    for _, g in ipairs(groups) do
        local open = c.zoneOpen[g.zone]
        if open == nil then open = not (c.listFoldOthers and g.zone ~= here) end
        g.open = open
        qw.logZones[g.zone] = open
        anyOpen = anyOpen or open
    end
    local r = Line("head", 0, hs + 5, 0)
    Face(r.text, "Head", st.head, st.shadow)
    r.text:SetText((anyOpen and "- " or "+ ") .. (QUEST_LOG or "Quest Log"))
    Face(r.tag, "Head", st.small, nil, 4, FRIZ)
    r.tag:SetText(count .. " quests")
    -- a quest not in your log on the page: for as long as it's there, its own
    -- section at the top, it selected (none in the log is)
    if qwPreview then
        local okP, pv = pcall(ns.QuestPreview, qwPreview)
        pv = okP and pv or {}
        y = y + 4
        r = Line("look", 0, zs + 5, 0)
        r.previewID = nil
        Face(r.text, "Zone", st.zone, st.shadow)
        r.text:SetText("Looking at")
        Face(r.tag, "Zone", st.small, nil, 3, FRIZ)
        r.tag:SetText("not in your log")
        r.rule:SetColorTexture(st.zone[1], st.zone[2], st.zone[3], 0.4)
        r.rule:Show()
        y = y + 1
        selY = y
        r = Line("look", 2, qs + 5, 38)
        r.previewID = qwPreview
        r.level:ClearAllPoints()
        r.level:SetPoint("LEFT", 12, 0)
        local lc = c.listLevelColors and LevelColor(pv.level, st.levels) or st.text
        Face(r.level, "Quest", lc, st.shadow)
        r.level:SetJustifyH("RIGHT")
        r.level:SetText(pv.level or "")
        r.level:Show()
        Face(r.text, "Quest", st.selText, st.shadow)
        r.text:SetText(pv.name or ("Quest " .. qwPreview))
        Selected(r, st.zone, st.sel)
    end
    for _, g in ipairs(groups) do
        local open = g.open
        y = y + 4
        r = Line("zone", 0, zs + 5, 0)
        r.zone, r.open, r.quests = g.zone, open, g.quests
        Face(r.text, "Zone", st.zone, st.shadow)
        r.text:SetText((open and "- " or "+ ") .. g.zone)
        Face(r.tag, "Zone", st.small, nil, 3, FRIZ)
        r.tag:SetText(#g.quests)
        r.rule:SetColorTexture(st.zone[1], st.zone[2], st.zone[3], 0.4)
        r.rule:Show()
        y = y + 1
        if open then
            for _, e in ipairs(g.quests) do
                local sel = e.id == qwQuest and not qwPreview
                if sel then selY = y end
                r = Line("quest", 2, qs + 5, 38)
                r.questID = e.id
                r.watch:SetShown(IsWatched(e.id, LogIndex(e.id)))
                r.level:ClearAllPoints()
                r.level:SetPoint("LEFT", 12, 0)
                local lc = c.listLevelColors and LevelColor(e.level, st.levels) or st.text
                Face(r.level, "Quest", lc, st.shadow)
                r.level:SetJustifyH("RIGHT")
                r.level:SetText(e.level or "")
                r.level:Show()
                Face(r.text, "Quest", sel and st.selText or st.text, st.shadow)
                r.text:SetText(e.title or "")
                if e.failed or e.complete then
                    -- (as the game's log: gold, a little bigger, a dark shadow under it)
                    -- (its own dark-brown shadow)
                    Face(r.tag, "Quest", e.failed and st.failed or st.done, true)
                    r.tag:SetShadowColor(0.2, 0.1, 0, 0.9)
                    r.tag:SetText("(" .. (e.failed and (FAILED or "Failed") or (COMPLETE or "Complete")) .. ")")
                end
                if sel then Selected(r, st.zone, st.sel) end
            end
        end
    end
    for i = n + 1, #(qw.listRows or {}) do qw.listRows[i]:Hide() end
    return y + 6, selY
end

-- The chain on the page: a heading, each step (done: a tick, faded; this
-- quest: ">" and the heading colour; to come: its number and its level in
-- difficulty colours), then what leads here. Click a step in your log: its
-- page; one not in your log: a preview; this quest while previewing: back.
local function ChainRow(i)
    qw.chainRows = qw.chainRows or {}
    local r = qw.chainRows[i]
    if r then return r end
    r = LineButton(qw.content, function(self)
        if not self.questID then return end
        if self.questID == qwQuest then
            if qwPreview then ShowQuest(qwQuest) end
        elseif self.inLog then
            ShowQuest(self.questID, true)
        else
            ShowPreview(self.questID)
        end
    end)
    qw.chainRows[i] = r
    return r
end

local function FillChain(chain, y, colors, dark)
    local n = 0
    if chain then
        qw.chainHeader:Show()
        PartFont(qw.chainHeader, "Sect", colors[2], TEXT_W)
        qw.chainHeader:SetText("Quest chain")
        qw.chainHeader:SetPoint("TOPLEFT", 5, -y)
        y = y + qw.chainHeader:GetStringHeight() + 5
        local ink = dark and { 1, 0.82, 0 } or { 0.23, 0.13, 0.03 }
        local _, size = Part("Chain")
        local function Step(s, number, crumb)
            n = n + 1
            local r = ChainRow(n)
            LineSetup(r, "step", 5, y, TEXT_W, size + 5, 40)
            r.questID, r.inLog = s.id, s.inLog
            r:EnableMouse(s.id ~= qwQuest or qwPreview ~= nil)
            local here = s.id == qwQuest
            if s.done and not here then
                r.mark:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                r.mark:Show()
            end
            -- (the number or ">" in the level's slot's left part)
            r.level:ClearAllPoints()
            r.level:SetPoint("LEFT", 14, 0)
            PartFont(r.level, "Chain", (s.done and not here) and colors[3] or LevelColor(s.level, dark and "game"), nil, 1)
            r.level:SetJustifyH("RIGHT")
            r.level:SetText(s.level or "")
            r.level:Show()
            if not (s.done and not here) then
                r.num = r.num or r:CreateFontString(nil, "ARTWORK")
                r.num:SetPoint("LEFT", 2, 0)
                PartFont(r.num, "Chain", here and colors[2] or colors[4], nil, 1)
                r.num:SetText(here and ">" or crumb and "" or tostring(number))
                r.num:Show()
            elseif r.num then
                r.num:Hide()
            end
            local color = here and colors[2] or (s.done and colors[3]) or colors[1]
            PartFont(r.text, "Chain", color)
            r.text:SetText(s.name or "")
            if crumb then
                PartFont(r.tag, "Chain", colors[4], nil, 2)
                r.tag:SetText(s.inLog and "in your log" or s.done and "done"
                    or crumb == "all" and "needed first" or crumb == "any" and "one of these first" or "leads here")
            elseif s.inLog and not here then
                PartFont(r.tag, "Chain", colors[4], nil, 2)
                r.tag:SetText("in your log")
            end
            if s.id == qwPreview then Selected(r, ink) end
            y = y + size + 5
        end
        for i, s in ipairs(chain.steps) do Step(s, i) end
        if #chain.crumbs > 0 then y = y + 4 end
        for _, s in ipairs(chain.crumbs) do Step(s, nil, true) end
        if chain.needs then y = y + 4 end
        for _, s in ipairs(chain.needs or {}) do Step(s, nil, s.all and "all" or "any") end
        y = y + 12
    elseif qw.chainHeader then
        qw.chainHeader:Hide()
    end
    for i = n + 1, #(qw.chainRows or {}) do
        qw.chainRows[i]:Hide()
        if qw.chainRows[i].num then qw.chainRows[i].num:Hide() end
    end
    return y
end

-- the quest's chain, when the page shows it (nil: none, or off)
local function ChainOf(id)
    if not (QCfg().chain and ns.QuestChain) then return nil end
    local ok, chain = pcall(ns.QuestChain, id)
    return ok and chain or nil
end

-- parchment, or dark as the tracker
local function ApplyPaper()
    local dark = QCfg().paper == "dark"
    qw.page:SetShown(not dark)
    if dark then qw.base:SetColorTexture(0.02, 0.02, 0.02, 0.88) else qw.base:SetColorTexture(0.08, 0.06, 0.05, 1) end
end

function FillQuestWindow()
    local c = QCfg()
    local index = qwQuest and SelectQuest(qwQuest)
    if not index then
        -- (none chosen, or it's gone from the log: its first)
        local first = FirstQuest()
        index = first and SelectQuest(first)
        -- (an empty log: nothing to show, but for a quest being read that isn't in it)
        if not index and not qwPreview then qw:Hide() return end
        if index then qwQuest, qwPreview = first, nil end
    end
    local id = qwQuest
    local colors = PAPERS[c.paper] or PAPERS.parchment
    local dark = c.paper == "dark"
    ApplyPaper()
    LayoutPanes()

    -- the log at the top
    local h, selY = FillList(colors, dark)
    qw.logH = h
    qw.logContent:SetHeight(h)
    if revealSel and selY then
        LogScroll(selY - qw.logScroll:GetHeight() / 3)
    else
        LogScroll(qw.logY or 0)
    end
    revealSel = nil
    local chain = id and ChainOf(id)

    -- a quest not in your log (a chain step, or opened from a pin, the book, a door):
    -- what QuestieDB knows of it, and under its objectives its own chain and what it
    -- needs done first, so a quest you can't take yet says what's missing (whether the
    -- page shows chains or not)
    if qwPreview then
        local okP, pv = pcall(ns.QuestPreview, qwPreview)
        pv = okP and pv or { name = "Quest " .. qwPreview }
        local inChain = false
        for _, s in ipairs(chain and chain.steps or {}) do
            if s.id == qwPreview then inChain = true end
        end
        if not inChain then
            local okC, own = pcall(ns.QuestChain or function() end, qwPreview)
            chain = okC and own or nil
        end
        local okN, needs = pcall(ns.QuestNeeds or function() end, qwPreview)
        if okN and needs then
            local shown, rest = {}, {}
            for _, s in ipairs(chain and chain.steps or {}) do shown[s.id] = true end
            for _, s in ipairs(chain and chain.crumbs or {}) do shown[s.id] = true end
            for _, s in ipairs(needs) do
                if not shown[s.id] then rest[#rest + 1] = s end
            end
            if #rest > 0 then
                chain = chain or { index = 0, steps = {}, crumbs = {} }
                chain.needs = rest
            end
        end
        local y = 10
        local note = qw.previewNote
        if not note then
            note = CreateFrame("Button", nil, qw.content)
            note.text = note:CreateFontString(nil, "ARTWORK")
            note.text:SetPoint("TOPLEFT")
            local hl = note:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.15)
            note:SetScript("OnClick", function() ShowQuest(qwQuest) end)
            qw.previewNote = note
        end
        local part
        for i, s in ipairs(chain and chain.steps or {}) do
            if s.id == qwPreview then part = i end
        end
        PartFont(note.text, "Small", colors[4], TEXT_W)
        local warn = colors[5]
        note.text:SetText(string.format("|cff%02x%02x%02xNot in your log|r", warn[1] * 255, warn[2] * 255, warn[3] * 255) .. (part and (", part " .. part .. " of " .. #chain.steps) or "")
            .. ". Back to " .. ((Entry(index) or {}).title or "your quest"))
        note:SetPoint("TOPLEFT", 5, -y)
        note:SetSize(TEXT_W, note.text:GetStringHeight() + 2)
        note:Show()
        y = y + note:GetHeight() + 6
        PartFont(qw.title, "Title", colors[2], TEXT_W - 10)
        qw.title:SetText(pv.name or "")
        qw.title:SetPoint("TOPLEFT", 5, -y)
        qw.title:Show()
        y = y + qw.title:GetStringHeight() + 5
        local meta = { (LEVEL or "Level") .. " " .. (pv.level or "?")
            .. ((pv.minLevel or 0) > 0 and (", from level " .. pv.minLevel) or "") }
        local people = pv.people
        if people and #people.from > 0 then meta[#meta + 1] = "From: " .. table.concat(people.from, ", ") end
        if people and #people.to > 0 then meta[#meta + 1] = "To: " .. table.concat(people.to, ", ") end
        PartFont(qw.meta, "Small", colors[4], TEXT_W)
        qw.meta:SetText(table.concat(meta, "\n"))
        qw.meta:SetPoint("TOPLEFT", 5, -y)
        qw.meta:Show()
        y = y + qw.meta:GetStringHeight() + 8
        for _, l in ipairs(qw.objLines or {}) do l:Hide() end
        qw.desc:Hide()
        qw.descHeader:SetShown(pv.text ~= nil)
        qw.summary:SetShown(pv.text ~= nil)
        if pv.text then
            PartFont(qw.descHeader, "Sect", colors[2], TEXT_W)
            qw.descHeader:SetText(QUEST_OBJECTIVES or "Quest Objectives")
            qw.descHeader:SetPoint("TOPLEFT", 5, -y)
            y = y + qw.descHeader:GetStringHeight() + 5
            PartFont(qw.summary, "Detail", colors[1], TEXT_W)
            qw.summary:SetText(pv.text)
            qw.summary:SetPoint("TOPLEFT", 5, -y)
            y = y + qw.summary:GetStringHeight() + 18
        end
        y = FillChain(chain, y, colors, dark)
        qw.contentH = y
        qw.content:SetHeight(y)
        -- its rewards from our data, in the same panel as a log quest's
        local okR, own = pcall(ns.QuestRewards, qwPreview)
        own = okR and own or nil
        if own then own.id = qwPreview end
        local rh = (QCfg().rewards and own) and FillRewards(qwPreview, own) or 0
        qw.rewards:SetShown(rh > 0)
        qw.rewards:SetHeight(math.max(rh, 1))
        for _, b in ipairs({ qw.abandon, qw.share, qw.track, qw.focus }) do b:Hide() end
        local bar = ButtonBar(false)
        qw.scroll:SetPoint("BOTTOMRIGHT", qw, "BOTTOMLEFT", SCROLL_R, rh > 0 and (bar + rh) or 8)
        ScrollPage(qw.scrollY or 0)
        return
    end
    if qw.previewNote then qw.previewNote:Hide() end
    qw.descHeader:SetText(QUEST_DESCRIPTION or "Description")
    qw.title:Show()
    local e = Entry(index) or {}

    -- the page: title, small print, objectives, description
    local ok, desc, objText = pcall(GetQuestLogQuestText, index)
    if not ok then desc, objText = nil, nil end
    local y = 10
    PartFont(qw.title, "Title", colors[2], TEXT_W - 10)
    qw.title:SetText(e.title or "")
    qw.title:SetPoint("TOPLEFT", 5, -y)
    y = y + qw.title:GetStringHeight() + 5

    -- under the title: level and type, giver and turn-in, quest ID
    local meta = {}
    if c.levelTag then
        local tags = Tags(id, e.group)
        local parts = { (LEVEL or "Level") .. " " .. (e.level or "?") }
        if chain and chain.index and #chain.steps > 1 then
            parts[#parts + 1] = "part " .. chain.index .. " of " .. #chain.steps
        end
        if tags.elite then parts[#parts + 1] = ELITE or "Elite" end
        if tags.dungeon then parts[#parts + 1] = "Dungeon" end
        if tags.raid then parts[#parts + 1] = RAID or "Raid" end
        if tags.group and not (tags.dungeon or tags.raid) then parts[#parts + 1] = GROUP or "Group" end
        meta[#meta + 1] = table.concat(parts, ", ")
    end
    if c.people and ns.QuestPeople then
        local okP, people = pcall(ns.QuestPeople, id)
        if okP and people then
            if #people.from > 0 then meta[#meta + 1] = "From: " .. table.concat(people.from, ", ") end
            if #people.to > 0 then meta[#meta + 1] = "To: " .. table.concat(people.to, ", ") end
        end
    end
    if c.questID then meta[#meta + 1] = "Quest ID " .. id end
    PartFont(qw.meta, "Small", colors[4], TEXT_W)
    qw.meta:SetText(table.concat(meta, "\n"))
    qw.meta:SetShown(#meta > 0)
    if #meta > 0 then
        qw.meta:SetPoint("TOPLEFT", 5, -y)
        y = y + qw.meta:GetStringHeight() + 8
    end

    qw.objLines = qw.objLines or {}
    for _, l in ipairs(qw.objLines) do l:Hide() end
    qw.summary:SetShown(c.objectives and true or false)
    if c.objectives then
        PartFont(qw.summary, "Detail", colors[1], TEXT_W)
        qw.summary:SetText(objText or "")
        qw.summary:SetPoint("TOPLEFT", 5, -y)
        y = y + (objText and objText ~= "" and qw.summary:GetStringHeight() + 10 or 0)
        for i, o in ipairs(Objectives(id, index)) do
            local l = qw.objLines[i]
            if not l then
                l = qw.content:CreateFontString(nil, "ARTWORK")
                qw.objLines[i] = l
            end
            PartFont(l, "Detail", o.finished and colors[3] or colors[1], TEXT_W)
            l:SetText(o.text or "")
            l:SetPoint("TOPLEFT", 5, -y)
            l:Show()
            y = y + l:GetStringHeight() + 2
        end
        y = y + 18
    end
    qw.descHeader:SetShown(c.description and true or false)
    qw.desc:SetShown(c.description and true or false)
    if c.description then
        PartFont(qw.descHeader, "Sect", colors[2], TEXT_W)
        qw.descHeader:SetPoint("TOPLEFT", 5, -y)
        y = y + qw.descHeader:GetStringHeight() + 5
        PartFont(qw.desc, "Detail", colors[1], TEXT_W)
        qw.desc:SetText(desc or "")
        qw.desc:SetPoint("TOPLEFT", 5, -y)
        y = y + qw.desc:GetStringHeight() + 12
    end
    y = FillChain(chain, y + 6, colors, dark)
    qw.contentH = y
    qw.content:SetHeight(y)

    -- the Rewards panel, and the page scrolling above it
    local rh = c.rewards and FillRewards(id) or 0
    ButtonBar(true)
    qw.rewards:SetShown(rh > 0)
    qw.rewards:SetHeight(math.max(rh, 1))
    qw.scroll:SetPoint("BOTTOMRIGHT", qw, "BOTTOMLEFT", SCROLL_R, rh > 0 and (BTN_BAR + rh) or (BTN_BAR + 2))
    ScrollPage(qw.scrollY or 0)

    -- the buttons: the ones ticked, side by side from the left
    local prev
    for _, b in ipairs({ { qw.abandon, c.abandon }, { qw.share, c.share }, { qw.track, c.track }, { qw.focus, c.focus } }) do
        local btn, on = b[1], b[2] and true or false
        btn:SetShown(on)
        if on then
            btn:ClearAllPoints()
            if prev then btn:SetPoint("LEFT", prev, "RIGHT") else btn:SetPoint("BOTTOMLEFT", 3, 2) end
            prev = btn
        end
    end
    local watched = IsWatched(id, index)
    qw.track:SetText(watched and "Untrack" or "Track")
    qw.focus:SetText(ns.IsFocused(id) and "Unfocus" or "Focus")
    local pushable = (C_QuestLog and C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(id))
        or (not (C_QuestLog and C_QuestLog.IsPushableQuest) and GetQuestLogPushable and GetQuestLogPushable())
    qw.share:SetEnabled((pushable and IsInGroup and IsInGroup()) and true or false)
end

-- the grips: the corner (scale) while detached, the bottom edge (height) while
-- it has its own height; neither when locked
local function UpdateGrips()
    local c = QCfg()
    qw.corner:SetShown(c.detached and not c.locked)
    qw.edge:SetShown((c.detached or not c.matchHeight) and not c.locked)
end

-- Where it goes (questlog.scale for both):
-- Attached: against the map border's outer edge, on the chosen side (auto:
-- whichever has room, right first), clear of its border and the toggle
-- buttons beside it. With matchHeight from the top of the map's border down
-- to its bottom, or with pastTracker the tracker's when it hangs below the
-- map; else its own height, hanging from the map's top. Anchored to the map,
-- so it moves with it; placed again when the map or tracker changes size.
-- Detached: at its saved spot (pos, top-left in UIParent units), its own
-- height. Detached with no spot yet: where it would be attached, kept there.
local function PlaceQuestWindow()
    if qw.moving then return end  -- (being dragged by its top bar)
    local c = QCfg()
    local k = (c.scale or 1) * ns.AddonScale()
    qw:SetScale(k)
    UpdateGrips()
    if c.detached and c.pos then
        qw.seam:Hide()
        qw:ClearAllPoints()
        qw:SetHeight(c.height or 570)
        qw:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", c.pos[1] / k, c.pos[2] / k)
        return
    end
    local map = BattlefieldMapFrame
    -- the map hidden (opened as the game's quest log, questlog.replaceGame):
    -- at its detached spot if it has one, else where the game's quest log opens
    if not (map and map:IsShown() and map:GetTop()) then
        qw.seam:Hide()
        qw:ClearAllPoints()
        qw:SetHeight(c.height or 570)
        if c.pos then
            qw:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", c.pos[1] / k, c.pos[2] / k)
        else
            qw:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16 / k, -104 / k)
        end
        return
    end
    -- everything in UIParent units first
    local ui = UIParent:GetEffectiveScale()
    local function Edges(f)
        local e = f:GetEffectiveScale() / ui
        return f:GetLeft() * e, f:GetRight() * e, f:GetTop() * e, f:GetBottom() * e
    end
    local mapOut = ns.BorderOutset and ns.BorderOutset()
    local o = (mapOut or 0) * map:GetEffectiveScale() / ui
    local l, r, t, b = Edges(mapOut and ns.MapFace(map) or map.BorderFrame or map)
    l, r, t, b = l - o, r + o, t + o, b - o  -- (the map border's outer edge)
    if c.pastTracker and frame and frame:IsShown() and not Cfg().detached and Cfg().attach == "below" and frame:GetBottom() then
        local _, _, _, fb = Edges(frame)
        b = math.min(b, fb - BorderReach() * frame:GetEffectiveScale() / ui)
    end
    local ml, mr, mt = Edges(map)
    qw:ClearAllPoints()
    if c.matchHeight and not c.detached then
        qw:SetHeight(math.max(260 * k, t - b) / k)
    else
        qw:SetHeight(c.height or 570)
    end
    -- (offsets in the window's own scale)
    local onRight
    if c.side == "right" then onRight = true
    elseif c.side == "left" then onRight = false
    else onRight = r + QW_W * k + 8 < UIParent:GetWidth() end
    local gap = c.gap or 0
    if onRight then
        qw:SetPoint("TOPLEFT", map, "TOPRIGHT", (r - mr) / k + gap, (t - mt) / k)
    else
        qw:SetPoint("TOPRIGHT", map, "TOPLEFT", (l - ml) / k - gap, (t - mt) / k)
    end
    if c.detached then
        -- (just detached: from here on it keeps this spot)
        local left, top = qw:GetLeft(), qw:GetTop()
        if left and top then
            c.pos = { left * k, top * k }
            qw:ClearAllPoints()
            qw:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        qw.seam:Hide()
        return
    end
    -- the shadow in the seam: on the map's side of the window, a little under
    -- it, darkest by the window
    local seam = qw.seam
    seam:SetShown(c.seam and true or false)
    if c.seam then
        local dark, light = CreateColor(0.05, 0.035, 0.02, 0.85), CreateColor(0.05, 0.035, 0.02, 0.45)
        seam:ClearAllPoints()
        -- (a few pixels under the window; inside its top and bottom edges)
        if onRight then
            seam:SetPoint("TOPRIGHT", qw, "TOPLEFT", 4, -4)
            seam:SetPoint("BOTTOMRIGHT", qw, "BOTTOMLEFT", 4, 4)
        else
            seam:SetPoint("TOPLEFT", qw, "TOPRIGHT", -4, -4)
            seam:SetPoint("BOTTOMLEFT", qw, "BOTTOMRIGHT", -4, 4)
        end
        if not pcall(seam.tex.SetGradient, seam.tex, "HORIZONTAL",
                     onRight and light or dark, onRight and dark or light) then
            seam.tex:SetColorTexture(0.05, 0.035, 0.02, 0.7)  -- (older SetGradient)
        end
    end
end
-- (the map or tracker changed: while it's open, at once)
function ns.PlaceQuestWindow()
    if qw and qw:IsShown() then PlaceQuestWindow() end
end

-- Escape closes it (always; questlog.escape was its switch)
local function ApplyEscape()
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == "WaymarkQuestWindow" then table.remove(UISpecialFrames, i) end
    end
    tinsert(UISpecialFrames, "WaymarkQuestWindow")
end

-- Its frame (questlog.borderStyle): its own art ("own"), or one of the map's
-- border styles with its own thickness, distance and colour; "map": the map
-- border's style and settings (the game's own map border, which only the map
-- has: its own art)
local function ApplyQuestFrame()
    local c = QCfg()
    local style, size, gap, color = c.borderStyle or "own", c.borderSize, c.borderGap, c.borderColor
    if style == "map" then
        local b = ns.db.border
        style, size, gap, color = ns.MapBorderStyle(true), b.size, b.gap, b.color
        if style == "game" then style = "own" end
    end
    qw.frameArt:SetShown(style == "own")
    if style == "own" or not ns.DressBorder then
        qw.border:Hide()
    else
        ns.DressBorder(qw.border, qw, style, size, gap, color)  -- (hides it for "none")
    end
end
-- (the map's border changed)
function ns.ApplyQuestFrame()
    if qw then ApplyQuestFrame() end
end

local function BuildQuestWindow()
    -- (Era's substitute top bar is dark down to its foot: the log starts under it)
    if ns.UsingSubstitutes() then LOG_TOP = 51 end
    qw = CreateFrame("Frame", "WaymarkQuestWindow", UIParent)
    qw:SetSize(QW_W, QW_H)
    qw:SetFrameStrata("HIGH")
    qw:SetToplevel(true)
    qw:EnableMouse(true)
    qw:SetClampedToScreen(true)
    qw:Hide()
    qw.scrollY, qw.contentH = 0, 0

    -- the dark behind it all, the parchment page, the frame round it
    local base = qw:CreateTexture(nil, "BACKGROUND", nil, -2)
    base:SetAllPoints()
    base:SetColorTexture(0.08, 0.06, 0.05, 1)
    local page = qw:CreateTexture(nil, "BACKGROUND", nil, -1)
    page:SetPoint("TOPLEFT")
    page:SetPoint("BOTTOMLEFT", 0, BTN_BAR)
    page:SetPoint("RIGHT")
    ns.SetArt(page, "QuestDetailsBackgrounds", "Interface\\QuestFrame\\QuestBG")
    qw.base, qw.page = base, page
    local frameArt = CreateFrame("Frame", nil, qw)
    frameArt:SetPoint("TOPLEFT", -3, 4)
    frameArt:SetPoint("BOTTOMRIGHT", 3, -3)
    frameArt:SetFrameLevel(qw:GetFrameLevel() + 20)
    -- (a 107 px picture cut 53 px in from each side: Forever's SetAtlas does
    -- that itself from the atlas's slice data; the stand-ins' dev copy is a
    -- plain picture, which stretched whole came out blurred with huge corners)
    if ns.FOREVER then
        local border = frameArt:CreateTexture(nil, "BORDER")
        border:SetAllPoints()
        ns.SetArt(border, "QuestLog-frame")
    elseif ns.UsingSubstitutes() then
        -- (Era's dark metal frame instead, Art.lua ART_SUBSTITUTE: 72 px, its
        -- corners 24 px, drawn at 2/3 so the line is thinner; its line is 6 px
        -- in, past a soft shadow, so it's moved out to sit on the window's edge)
        frameArt:ClearAllPoints()
        frameArt:SetPoint("TOPLEFT", -4, 4)
        frameArt:SetPoint("BOTTOMRIGHT", 4, -4)
        local cut = 24 / 72
        ns.SliceArt(frameArt, "QuestLog-frame", cut, cut, cut, cut, 16, 16, 16, 16, "BORDER")
    else
        local cut = 53 / 107
        ns.SliceArt(frameArt, "QuestLog-frame", cut, cut, cut, cut, 53, 53, 53, 53, "BORDER")
    end
    local crest = frameArt:CreateTexture(nil, "ARTWORK")
    crest:SetSize(48, 19)
    crest:SetPoint("TOP", 0, 1)
    ns.SetArt(crest, "QuestLog-frame-filigree")
    -- or the map's border styles instead (ApplyQuestFrame)
    -- (qw.edge is its bottom-edge grip)
    local styled = CreateFrame("Frame", nil, qw, "BackdropTemplate")
    styled:SetFrameLevel(qw:GetFrameLevel() + 20)
    styled:Hide()
    qw.frameArt, qw.border = frameArt, styled
    ApplyQuestFrame()

    -- the seam between the map (and tracker) and the window: a soft dark
    -- shadow behind both, so it shows only in the gap between their borders.
    -- Darker by the window, lighter toward the map. (Placed by PlaceQuestWindow.)
    local seam = CreateFrame("Frame", nil, qw)
    seam:SetFrameStrata("BACKGROUND")
    seam:SetWidth(9)  -- (just the gap: 24 spread far over the map)
    seam.tex = seam:CreateTexture(nil, "BACKGROUND")
    seam.tex:SetAllPoints()
    seam.tex:SetColorTexture(1, 1, 1, 1)
    qw.seam = seam

    -- the top bar, with the button that closes it (the game's has "Back")
    local top = CreateFrame("Frame", nil, qw)
    top:SetSize(307, 51)
    top:SetPoint("TOPLEFT")
    top:SetFrameLevel(qw:GetFrameLevel() + 5)
    local topArt = top:CreateTexture(nil, "BORDER")
    topArt:SetAllPoints()
    ns.SetArt(topArt, "QuestLog-reward-top-frame")
    -- Era's art: the old "Close" button, top left of the bar. Forever: its red X (the
    -- map's own close X art, MapControls; dev art gives it on Era too), on the window's
    -- top-right corner, over its frame, as Forever's windows have it (inside the top
    -- bar it looked off, the user); the button a little bigger than its art
    local close
    if ns.UsingSubstitutes and ns.UsingSubstitutes() then
        close = CreateFrame("Button", nil, top, "UIPanelButtonTemplate")
        close:SetSize(90, 22)
        close:SetPoint("LEFT", 11, 4)
        close:SetText(CLOSE or "Close")
    else
        close = CreateFrame("Button", nil, top)
        close:SetSize(28, 28)
        close:SetPoint("CENTER", qw, "TOPRIGHT", -10, -10)
        close:SetFrameLevel(qw:GetFrameLevel() + 25)  -- (over the frame's art, at + 20)
        for _, s in ipairs({ { "Normal", "redbutton-exit-2x" }, { "Pushed", "redbutton-exit-pressed-2x" },
                             { "Highlight", "redbutton-highlight-2x" } }) do
            local tex = close:CreateTexture(nil, s[1] == "Highlight" and "HIGHLIGHT" or "ARTWORK")
            ns.SetArt(tex, s[2])
            close["Set" .. s[1] .. "Texture"](close, tex)
            -- (sized after: setting it can stretch it over the button)
            tex:ClearAllPoints()
            tex:SetSize(21, 21)
            tex:SetPoint("CENTER")
        end
    end
    close:SetScript("OnClick", function() qw:Hide() end)
    qw.close = close
    -- detached: drag the top bar to move it
    top:EnableMouse(true)
    top:RegisterForDrag("LeftButton")
    top:SetScript("OnDragStart", function()
        local c = QCfg()
        if not c.detached or c.locked then return end
        qw:SetMovable(true)
        qw:StartMoving()
        qw.moving = true
    end)
    top:SetScript("OnDragStop", function()
        if not qw.moving then return end
        qw.moving = nil
        qw:StopMovingOrSizing()
        local k = (QCfg().scale or 1) * ns.AddonScale()
        QCfg().pos = { qw:GetLeft() * k, qw:GetTop() * k }
        PlaceQuestWindow()
    end)

    -- the page: scrolls with the wheel, with the game's slim scroll bar
    local scroll = CreateFrame("ScrollFrame", nil, qw)
    scroll:SetPoint("TOPLEFT", 5, -LOG_TOP)
    scroll:SetPoint("BOTTOMRIGHT", qw, "BOTTOMLEFT", SCROLL_R, BTN_BAR + 2)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(SCROLL_R - 5, 10)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, d) ScrollPage(qw.scrollY - d * 40) end)
    qw.scroll, qw.content = scroll, content
    qw.chainHeader = content:CreateFontString(nil, "ARTWORK")  -- (font and text: FillChain)

    -- the log at the top: a darker parchment, its own scroll
    -- with a thin mark at the right, a soft shade along its foot
    local pane = CreateFrame("Frame", nil, qw)
    pane:SetPoint("TOPLEFT", 0, -LOG_TOP)
    pane:SetPoint("TOPRIGHT", 0, -LOG_TOP)
    pane:SetHeight(120)
    local tint = pane:CreateTexture(nil, "BACKGROUND")
    -- (edge to edge: 4 px in, the parchment showed in strips beside a dark list)
    tint:SetPoint("TOPLEFT")
    tint:SetPoint("BOTTOMRIGHT")
    tint:SetColorTexture(0.3, 0.18, 0.06, 0.13)
    pane.tint = tint
    local shade = pane:CreateTexture(nil, "BORDER")
    shade:SetPoint("BOTTOMLEFT")
    shade:SetPoint("BOTTOMRIGHT")
    shade:SetHeight(6)
    shade:SetColorTexture(1, 1, 1, 1)
    pcall(shade.SetGradient, shade, "VERTICAL", CreateColor(0.2, 0.12, 0.04, 0.18), CreateColor(0.2, 0.12, 0.04, 0))
    local logScroll = CreateFrame("ScrollFrame", nil, pane)
    logScroll:SetPoint("TOPLEFT", 5, -2)
    logScroll:SetPoint("BOTTOMRIGHT", -(307 - 5 - LOG_W), 2)
    local logContent = CreateFrame("Frame", nil, logScroll)
    logContent:SetSize(LOG_W, 10)
    logScroll:SetScrollChild(logContent)
    logScroll:EnableMouseWheel(true)
    logScroll:SetScript("OnMouseWheel", function(_, d) LogScroll((qw.logY or 0) - d * 30) end)
    local mark = pane:CreateTexture(nil, "ARTWORK")
    mark:SetWidth(3)
    mark:SetColorTexture(0.35, 0.22, 0.08, 0.45)
    qw.logPane, qw.logScroll, qw.logContent, qw.logMark = pane, logScroll, logContent, mark
    qw.logY, qw.logH = 0, 0

    -- between the log and the page: a faint line; drag it to share the room
    local divider = CreateFrame("Frame", nil, qw)
    divider:SetPoint("TOPLEFT", pane, "BOTTOMLEFT")
    divider:SetPoint("TOPRIGHT", pane, "BOTTOMRIGHT")
    divider:SetHeight(DIVIDER)
    divider:SetFrameLevel(qw:GetFrameLevel() + 7)
    divider:EnableMouse(true)
    local dline = divider:CreateTexture(nil, "ARTWORK")
    dline:SetPoint("LEFT", 14, 0)
    dline:SetPoint("RIGHT", -14, 0)
    dline:SetHeight(1)
    dline:SetColorTexture(0.3, 0.19, 0.07, 0.3)
    divider.line = dline
    divider:SetScript("OnEnter", function()
        dline:SetColorTexture(0.3, 0.19, 0.07, 0.7)
    end)
    divider:SetScript("OnLeave", function()
        if not divider.dragging then dline:SetColorTexture(0.3, 0.19, 0.07, 0.3) end
    end)
    divider:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local _, y0 = GetCursorPosition()
        local h0 = pane:GetHeight()
        divider.dragging = true
        divider:SetScript("OnUpdate", function()
            local _, y = GetCursorPosition()
            local room = qw:GetHeight() - LOG_TOP - BTN_BAR
            QCfg().listShare = math.max(0.15, math.min(0.6, (h0 + (y0 - y) / qw:GetEffectiveScale()) / room))
            LayoutPanes()
            LogScroll(qw.logY)
            ScrollPage(qw.scrollY or 0)
        end)
    end)
    divider:SetScript("OnMouseUp", function()
        divider:SetScript("OnUpdate", nil)
        divider.dragging = nil
        if not divider:IsMouseOver() then dline:SetColorTexture(0.3, 0.19, 0.07, 0.3) end
        local c = QCfg()
        c.listShare = math.floor((c.listShare or 0.27) * 100 + 0.5) / 100
        if ns.RefreshControls then ns.RefreshControls() end
    end)
    qw.divider = divider
    -- (its height changes: the log keeps its share)
    qw:SetScript("OnSizeChanged", function()
        LayoutPanes()
        LogScroll(qw.logY)
        ScrollPage(qw.scrollY or 0)
    end)

    qw.title = content:CreateFontString(nil, "ARTWORK")
    PageFont(qw.title, MORPHEUS, 18, BLACK, TEXT_W - 10)
    qw.summary = content:CreateFontString(nil, "ARTWORK")
    PageFont(qw.summary, FRIZ, 13, INK, TEXT_W)
    qw.descHeader = content:CreateFontString(nil, "ARTWORK")
    PageFont(qw.descHeader, MORPHEUS, 18, BLACK, TEXT_W)
    qw.descHeader:SetText(QUEST_DESCRIPTION or "Description")
    qw.meta = content:CreateFontString(nil, "ARTWORK")  -- (level, giver, turn-in, ID)
    qw.desc = content:CreateFontString(nil, "ARTWORK")
    PageFont(qw.desc, FRIZ, 13, INK, TEXT_W)

    local bar = CreateFrame("Frame", nil, qw)
    bar:SetWidth(17)
    -- (on the parchment by its right edge, beside the scrolling text: from
    -- under the top bar down to the Rewards panel, or the buttons without one)
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 1, -10)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 1, 2)
    bar:SetFrameLevel(qw:GetFrameLevel() + 6)
    local up = CreateFrame("Button", nil, bar)
    up:SetSize(17, 11)
    up:SetPoint("TOP")
    local upArt = up:CreateTexture(nil, "BACKGROUND")
    ns.SetArt(upArt, "minimal-scrollbar-arrow-top")
    upArt:SetAllPoints()
    up:SetScript("OnClick", function() ScrollPage(qw.scrollY - 40) end)
    local down = CreateFrame("Button", nil, bar)
    down:SetSize(17, 11)
    down:SetPoint("BOTTOM")
    local downArt = down:CreateTexture(nil, "BACKGROUND")
    ns.SetArt(downArt, "minimal-scrollbar-arrow-bottom")
    downArt:SetAllPoints()
    down:SetScript("OnClick", function() ScrollPage(qw.scrollY + 40) end)
    local track = CreateFrame("Frame", nil, bar)
    track:SetWidth(8)
    track:SetPoint("TOP", up, "BOTTOM", 0, -8)
    track:SetPoint("BOTTOM", down, "TOP", 0, 8)
    local function Piece(parent, atlas, a, b, h)
        local t = parent:CreateTexture(nil, "ARTWORK")
        ns.SetArt(t, atlas)  -- (names in Art.lua ns.ART)
        t:SetWidth(8)
        if h then t:SetHeight(h) end
        t:SetPoint(a[1], a[2] or parent, a[3] or a[1], 0, 0)
        if b then t:SetPoint(b[1], b[2], b[3], 0, 0) end
        return t
    end
    local tb = Piece(track, "minimal-scrollbar-track-top", { "TOPLEFT" }, nil, 8)
    local te = Piece(track, "minimal-scrollbar-track-bottom", { "BOTTOMLEFT" }, nil, 8)
    Piece(track, "!minimal-scrollbar-track-middle", { "TOPLEFT", tb, "BOTTOMLEFT" }, { "BOTTOMLEFT", te, "TOPLEFT" })
    local thumb = CreateFrame("Frame", nil, track)
    thumb:SetWidth(8)
    thumb:SetFrameLevel(track:GetFrameLevel() + 1)
    local hb = Piece(thumb, "minimal-scrollbar-small-thumb-top", { "TOPLEFT" }, nil, 8)
    local he = Piece(thumb, "minimal-scrollbar-small-thumb-bottom", { "BOTTOMLEFT" }, nil, 8)
    Piece(thumb, "minimal-scrollbar-small-thumb-middle", { "TOPLEFT", hb, "BOTTOMLEFT" }, { "BOTTOMLEFT", he, "TOPLEFT" })
    bar.track, bar.thumb = track, thumb
    qw.bar = bar

    -- the Rewards panel: its header, a tiled middle, its foot
    local rw = CreateFrame("Frame", nil, qw)
    rw:SetWidth(307)
    rw:SetPoint("BOTTOMLEFT", 0, BTN_BAR)
    rw:SetFrameLevel(qw:GetFrameLevel() + 6)
    local rTop = rw:CreateTexture(nil, "BORDER")
    rTop:SetSize(307, 56)
    rTop:SetPoint("TOPLEFT")
    ns.SetArt(rTop, "QuestLog-reward-header-top")
    local rBottom = rw:CreateTexture(nil, "BORDER")
    rBottom:SetSize(307, 87)
    rBottom:SetPoint("BOTTOMLEFT")
    ns.SetArt(rBottom, "QuestLog-reward-bottom")
    local rTile = rw:CreateTexture(nil, "BACKGROUND")
    rTile:SetPoint("TOPLEFT", rTop, "BOTTOMLEFT")
    rTile:SetPoint("BOTTOMRIGHT", rw, "BOTTOMRIGHT")
    ns.SetArt(rTile, "QuestLog-reward-tile-vertical")
    local label = rw:CreateFontString(nil, "OVERLAY")
    PageFont(label, MORPHEUS, 18, TAN)
    label:SetJustifyH("CENTER")
    label:SetPoint("TOP", 0, -22)
    label:SetText(REWARDS or "Rewards")
    rw.items = CreateFrame("Frame", nil, rw)
    rw.items:SetPoint("TOPLEFT", 12, -52)
    rw.items:SetSize(285, 10)
    qw.rewards = rw
    qw.chooseText = rw.items:CreateFontString(nil, "OVERLAY")
    PageFont(qw.chooseText, FRIZ, 10, TAN, 265)
    qw.chooseText:SetText(REWARD_CHOICES or "You will be able to choose one of these rewards:")
    qw.receiveText = rw.items:CreateFontString(nil, "OVERLAY")
    PageFont(qw.receiveText, FRIZ, 10, TAN, 265)

    -- Abandon, Share, Track, Focus along the bottom, with the game's dividers
    local function Btn(text, width, onClick)
        local b = CreateFrame("Button", nil, qw, "UIPanelButtonTemplate")
        b:SetSize(width, 22)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
        b:SetFrameLevel(qw:GetFrameLevel() + 21)
        return b
    end
    qw.abandon = Btn(ABANDON_QUEST_ABBREV or "Abandon", 77, function()
        local id = qwQuest
        if not (id and SelectQuest(id)) then return end
        local name = (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)) or qw.title:GetText() or ""
        -- (Waymark's own ask box, Ask.lua: the game's ABANDON_QUEST popup opened from here broke a
        -- controller's buttons. The quest is chosen again on Yes, in case the log moved meanwhile.)
        ns.Ask({ text = "Abandon " .. name .. "?", ok = ABANDON_QUEST_ABBREV or "Abandon", cancel = "Keep it",
                 onAccept = function()
                     if not SelectQuest(id) then return end
                     if C_QuestLog and C_QuestLog.SetAbandonQuest then C_QuestLog.SetAbandonQuest() elseif SetAbandonQuest then SetAbandonQuest() end
                     if C_QuestLog and C_QuestLog.AbandonQuest then C_QuestLog.AbandonQuest() elseif AbandonQuest then AbandonQuest() end
                 end })
    end)
    qw.abandon:SetPoint("BOTTOMLEFT", 3, 2)  -- (inside the frame, not over its edge)
    qw.share = Btn(SHARE_QUEST_ABBREV or "Share", 72, function()
        if qwQuest and SelectQuest(qwQuest) and QuestLogPushQuest then QuestLogPushQuest() end
    end)
    qw.share:SetPoint("LEFT", qw.abandon, "RIGHT")
    qw.track = Btn("Untrack", 76, function()
        if not qwQuest then return end
        ToggleWatch(qwQuest)
        ns.UpdateTracker(true)
        FillQuestWindow()
    end)
    qw.track:SetPoint("LEFT", qw.share, "RIGHT")
    -- in focus: at the top of the tracker, its objectives and turn-in glowing
    qw.focus = Btn("Focus", 76, function()
        if not qwQuest then return end
        ns.ToggleFocus(qwQuest)
        FillQuestWindow()
    end)
    qw.focus:SetPoint("LEFT", qw.track, "RIGHT")
    -- (smaller than the game's 13 x 25, so they stay within the buttons' height)
    for _, side in ipairs({ { "RIGHT", "LEFT", 5 }, { "LEFT", "RIGHT", -5 } }) do
        local d = qw.share:CreateTexture(nil, "OVERLAY")
        d:SetSize(9, 20)
        d:SetPoint(side[1], qw.share, side[2], side[3], 0)
        ns.SetArt(d, "UI-Frame-BtnDivMiddle")
    end
    local d = qw.focus:CreateTexture(nil, "OVERLAY")
    d:SetSize(9, 20)
    d:SetPoint("RIGHT", qw.focus, "LEFT", 5, 0)
    ns.SetArt(d, "UI-Frame-BtnDivMiddle")

    -- detached: its bottom-right corner follows the mouse. Sideways scales it (the
    -- page is cut from fixed art 307 across, so it scales rather than stretches);
    -- what's left of the drag goes to its height
    local corner = CreateFrame("Button", nil, qw)
    corner:SetSize(16, 16)
    corner:SetPoint("BOTTOMRIGHT", 2, -2)
    corner:SetFrameLevel(qw:GetFrameLevel() + 25)
    corner:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    corner:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    corner:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    corner:SetScript("OnMouseDown", function(_, button)
        local c = QCfg()
        if button ~= "LeftButton" or not c.detached or c.locked or not c.pos then return end
        local x0, y0 = GetCursorPosition()
        local k0 = c.scale or 1
        local ui = UIParent:GetEffectiveScale()
        local g = ns.AddonScale()
        local w0 = QW_W * k0 * g  -- (UIParent units; the top-left stays put)
        local h0 = qw:GetHeight() * k0 * g
        corner:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            c.scale = math.max(0.6, math.min(2, k0 * (w0 + (x - x0) / ui) / w0))
            c.height = math.max(260, math.min(900, (h0 + (y0 - y) / ui) / (c.scale * g)))
            PlaceQuestWindow()
        end)
    end)
    corner:SetScript("OnMouseUp", function()
        corner:SetScript("OnUpdate", nil)
        local c = QCfg()
        c.scale = math.floor((c.scale or 1) * 20 + 0.5) / 20  -- (the slider's steps)
        c.height = math.floor((c.height or 570) + 0.5)
        PlaceQuestWindow()
        if ns.RefreshControls then ns.RefreshControls() end
    end)
    corner:SetScript("OnEnter", function()
        GameTooltip:SetOwner(corner, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine("Size")
        ns.Hints({ { "Drag", "sideways its scale, up and down its height" }, { "Drag the top bar", "move it" } })
        GameTooltip:Show()
    end)
    corner:SetScript("OnLeave", function() GameTooltip:Hide() end)
    qw.corner = corner

    -- its own height (detached, or not matching the map's): drag its bottom edge
    local edge = CreateFrame("Frame", nil, qw)
    edge:SetHeight(8)
    edge:SetPoint("BOTTOMLEFT", 80, -6)
    edge:SetPoint("BOTTOMRIGHT", -80, -6)
    edge:SetFrameLevel(qw:GetFrameLevel() + 25)
    edge:EnableMouse(true)
    local line = edge:CreateTexture(nil, "OVERLAY")
    line:SetPoint("LEFT")
    line:SetPoint("RIGHT")
    line:SetHeight(2)
    line:SetColorTexture(1, 0.82, 0, 0.8)
    line:Hide()
    edge:SetScript("OnEnter", function()
        line:Show()
        GameTooltip:SetOwner(edge, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Height")
        GameTooltip:AddLine("Drag: its height", 1, 1, 1)
        GameTooltip:Show()
    end)
    edge:SetScript("OnLeave", function()
        if not edge.dragging then line:Hide() end
        GameTooltip:Hide()
    end)
    edge:SetScript("OnMouseDown", function(_, button)
        local c = QCfg()
        if button ~= "LeftButton" or c.locked then return end
        local _, y0 = GetCursorPosition()
        local h0 = qw:GetHeight()
        edge.dragging = true
        edge:SetScript("OnUpdate", function()
            local _, y = GetCursorPosition()
            c.height = math.max(260, math.min(900, h0 + (y0 - y) / qw:GetEffectiveScale()))
            qw:SetHeight(c.height)
            ScrollPage(qw.scrollY or 0)
        end)
    end)
    edge:SetScript("OnMouseUp", function()
        edge:SetScript("OnUpdate", nil)
        edge.dragging = nil
        if not edge:IsMouseOver() then line:Hide() end
        local c = QCfg()
        c.height = math.floor((c.height or 570) + 0.5)
        PlaceQuestWindow()
        if ns.RefreshControls then ns.RefreshControls() end
    end)
    qw.edge = edge

    -- its opacity, and fading while the mouse is away (questlog.fadeOut)
    qw:SetScript("OnUpdate", function(self, dt)
        local c = QCfg()
        local want = c.alpha or 1
        if c.fadeOut and not self:IsMouseOver() then want = math.min(want, (c.fadeAlpha or 30) / 100) end
        local a = self:GetAlpha()
        if math.abs(a - want) < 0.01 then
            if a ~= want then self:SetAlpha(want) end
            return
        end
        self:SetAlpha(a + (want - a) * math.min(1, dt * 8))
    end)
    qw:SetScript("OnHide", function()
        if paged then
            paged = nil
            pcall(HighlightOnMap, highlighted)
        end
    end)

    -- keeps up with the quest; closes with the map (detached and not only
    -- while the map shows: stays) or when the quest is gone
    qw:RegisterEvent("QUEST_LOG_UPDATE")
    qw:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
    qw:RegisterEvent("GROUP_ROSTER_UPDATE")
    qw:SetScript("OnEvent", function()
        if qw:IsShown() then ns.Safe("Quest window", FillQuestWindow) end
    end)
    if BattlefieldMapFrame then
        BattlefieldMapFrame:HookScript("OnHide", function()
            local c = QCfg()
            if not (c.detached and not c.onlyWithMap) then qw:Hide() end
        end)
    end
    ApplyEscape()
end

-- a quest that isn't in your log, read on the window's page (the notebook's "who asked us"). With
-- the quest log off too: the game has no page for such a quest, and "quest details" did nothing
function ns.ShowQuestPreview(id)
    if not id then return end
    if not qw then BuildQuestWindow() end
    PlaceQuestWindow()
    qw:Show()
    if not (qwQuest and LogIndex(qwQuest)) then qwQuest = FirstQuest() end
    ShowPreview(id)
end

-- a quest from a pin's menu (Controls.lua): in your log, its page (the quest window off: the
-- game's log); else read on the window's page
function ns.OpenQuest(id)
    if not id then return end
    if LogIndex(id) then
        if QCfg().shown then ns.ShowQuestWindow(id) else OpenLog(id) end
    else
        ns.ShowQuestPreview(id)
    end
end

-- open a quest's page (again on the same quest: close it)
function ns.ShowQuestWindow(id)
    if not id or not QCfg().shown then return end
    if not qw then BuildQuestWindow() end
    if qw:IsShown() and qwQuest == id and not qwPreview then qw:Hide() return end
    if not LogIndex(id) then return end
    PlaceQuestWindow()
    qw:Show()
    ShowQuest(id, true)
end

-- The window needs the Battlefield Map's addon (our setup runs when it
-- loads): with the map never opened yet, load it (it stays hidden).
local function MapLoaded()
    if BattlefieldMapFrame then return true end
    if InCombatLockdown() then
        ns.Log("the quest window can't load in combat the first time: after the fight")
        return false
    end
    pcall(C_AddOns and C_AddOns.LoadAddOn or LoadAddOn, "Blizzard_BattlefieldMap")
    return BattlefieldMapFrame ~= nil
end

-- The quest log key (questlog.keyL): while the map shows, an override binding
-- on the keys bound to the quest log clicks a hidden button, which opens the
-- window on the quest last shown (else the first in the log), or closes it.
-- questlog.replaceGame: always, from login, map or not. Bindings can't
-- change in a fight: then once it's over.
-- id: that quest's page (from the game's quest log opening: its selection)
local keyButton, keyPending
local function OpenFromKey(id)
    if not MapLoaded() then return end
    if id and LogIndex(id) then ns.ShowQuestWindow(id) return end
    if qw and qw:IsShown() then qw:Hide() return end
    id = lastQuest and LogIndex(lastQuest) and lastQuest
    if not id then
        for i = 1, NumEntries() do
            local e = Entry(i)
            if e and not e.isHeader and e.id then id = e.id break end
        end
    end
    if id then ns.ShowQuestWindow(id) end
end

-- the tracker header's menu (above in this file): the quest log as its key opens
-- it, our window when it's in use (on the quest last shown), else the game's
function ns.QuestWindowShown() return qw and qw:IsShown() and true or false end
function ns.QuestLogFromMenu()
    if QCfg().shown then OpenFromKey() else OpenLog() end
end
local function ApplyQuestKey()
    if not keyButton then
        keyButton = CreateFrame("Button", "WaymarkQuestLogKey", UIParent)
        keyButton:SetScript("OnClick", function() ns.Safe("Quest log key", OpenFromKey) end)
        keyButton:RegisterEvent("PLAYER_REGEN_ENABLED")
        keyButton:SetScript("OnEvent", function()
            if keyPending then ApplyQuestKey() end
        end)
    end
    if InCombatLockdown() then keyPending = true return end
    keyPending = nil
    ClearOverrideBindings(keyButton)
    local c, map = QCfg(), BattlefieldMapFrame
    if not (c.shown and (c.replaceGame or (c.keyL and map and map:IsShown()))) then return end
    for _, key in ipairs({ GetBindingKey("TOGGLEQUESTLOG") }) do
        SetOverrideBindingClick(keyButton, false, key, "WaymarkQuestLogKey")
    end
end

-- questlog.replaceGame: the game's quest log closes as it opens (its micro
-- button, a click in its tracker), and this window opens on the quest it
-- would have shown (the same quest again: closes it)
local gameLogHooked
local function HookGameLog()
    if gameLogHooked or not QuestLogFrame then return end
    gameLogHooked = true
    QuestLogFrame:HookScript("OnShow", function(self)
        local c = QCfg()
        if not (c.shown and c.replaceGame) then return end
        HideUIPanel(self)
        ns.Safe("Quest log", function()
            local index = GetQuestLogSelection and GetQuestLogSelection()
            local id = index and index > 0 and GetQuestLogTitle and select(8, GetQuestLogTitle(index))
            OpenFromKey(id ~= 0 and id or nil)
        end)
    end)
end
-- from login, before the map is ever loaded
do
    local login = CreateFrame("Frame")
    login:RegisterEvent("PLAYER_ENTERING_WORLD")
    login:RegisterEvent("PLAYER_REGEN_ENABLED")  -- (a reload in combat)
    login:SetScript("OnEvent", function()
        if not ns.db then return end
        pcall(HookGameLog)
        ApplyQuestKey()
        -- a detached tracker shows without the map: its addon loaded (the map
        -- stays closed; not in combat, so after the fight)
        local t = ns.db.tracker
        if t.shown and (t.detached or t.attach == "free") and not BattlefieldMapFrame and not InCombatLockdown() then
            pcall(C_AddOns and C_AddOns.LoadAddOn or LoadAddOn, "Blizzard_BattlefieldMap")
        end
    end)
end

-- a Quest log page setting changed
function ns.ApplyQuestWindow(key)
    if key == "shown" or key == "keyL" or key == "replaceGame" then
        ApplyQuestKey()
        pcall(HookGameLog)
    end
    if (key == "shown" or key == "fromPins") and ns.RedrawQuestie then ns.RedrawQuestie() end  -- (pins' right-click)
    if not qw then return end
    ApplyEscape()
    ApplyQuestFrame()
    if not QCfg().shown then qw:Hide() return end
    if key == "listFoldOthers" then wipe(QCfg().zoneOpen) end  -- (folded afresh by the new rule)
    if key == "glow" then
        paged = QCfg().glow and qw:IsShown() and qwQuest or nil
        pcall(HighlightOnMap, highlighted)
    end
    if qw:IsShown() then
        PlaceQuestWindow()
        ns.Safe("Quest window", FillQuestWindow)
    else
        UpdateGrips()
    end
end

-- for /bfi check
function ns.QuestWindowInfo()
    local c = QCfg()
    local where = c.detached and "detached" or ("attached " .. (c.side or "?") .. (c.matchHeight and ", map's height" or ""))
    if c.replaceGame then where = where .. ", replaces the game's quest log" end
    if not qw then return "not built yet, " .. where end
    return string.format("%s, %s, quest %s, %dx%d at %.2fx", qw:IsShown() and "shown" or "hidden", where,
        tostring(qwQuest), qw:GetWidth(), qw:GetHeight(), qw:GetScale())
end

function ns.SetupTracker(map)
    Build(map)
    pcall(HookQuestLog)

    local events = ns.TimedFrame("Tracker")
    for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED",
                         "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS",
                         "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED", "QUEST_TURNED_IN" }) do
        pcall(events.RegisterEvent, events, e)
    end
    events:SetScript("OnEvent", function(_, event, a, b)
        dirty = true
        OnQuestEvent(event, a, b)
        if event == "PLAYER_REGEN_ENABLED" and ns.trackerAfterCombat then
            ns.trackerAfterCombat = nil
            ApplyGameTracker()
        end
    end)
    map:HookScript("OnShow", function()
        ns.UpdateTracker(true)
        ApplyQuestKey()
        ns.PlaceQuestWindow()  -- (open on its own: now by the map)
    end)
    map:HookScript("OnHide", function()
        if frame and not Cfg().detached then frame:Hide() end
        ApplyQuestKey()
        ApplyGameTracker()  -- (the game's tracker back while ours is gone)
    end)
    map:HookScript("OnSizeChanged", function() dirty = true end)
    -- another map shown: other zones' quests may come or go (otherZones "continent")
    if map.OnMapChanged then pcall(hooksecurefunc, map, "OnMapChanged", function() dirty = true end) end
    ApplyQuestKey()  -- (the map may be open already)

    -- distances change as you move: once a second; at once after an event
    local elapsed = 0
    local ticker = ns.TimedFrame("Tracker tick")
    ticker:SetScript("OnUpdate", function(_, dt)
        if frame:IsShown() then
            UpdateFade(dt)
            UpdateFlash()
        end
        elapsed = elapsed + dt
        if not (dirty and elapsed >= 0.2) and elapsed < 1 then return end
        elapsed = 0
        if not (map:IsShown() or Cfg().detached) then return end
        ns.UpdateTracker()
    end)
    ns.UpdateTracker(true)
end

-- The quest window's art takes a second to arrive the first time it's drawn after a
-- reload (the user), so a dot nobody sees draws it soon after login. It has its own
-- frame: the window itself is still built when it's first opened.
local QUEST_ART = { "QuestDetailsBackgrounds", "QuestLog-frame", "QuestLog-frame-filigree",
    "QuestLog-reward-bottom", "QuestLog-reward-header-top", "QuestLog-reward-tile-vertical",
    "QuestLog-reward-top-frame", "UI-Frame-BtnDivMiddle",
    "minimal-scrollbar-arrow-bottom", "minimal-scrollbar-arrow-top" }
local warm = CreateFrame("Frame", nil, UIParent)
warm:SetSize(1, 1)
warm:SetPoint("BOTTOMLEFT")
warm:SetAlpha(0.01)
warm:RegisterEvent("PLAYER_ENTERING_WORLD")
warm:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    C_Timer.After(3, function()
        ns.Safe("Tracker warm art", function()
            if not (ns.db and ns.db.questlog and ns.db.questlog.shown) then return end
            for _, name in ipairs(QUEST_ART) do
                local t = self:CreateTexture(nil, "BACKGROUND")
                t:SetAllPoints()
                ns.SetArt(t, name)
            end
            C_Timer.After(5, function() self:Hide() end)
        end)
    end)
end)

-- Quest items: a button left of the quest's line for the item you use for it (tracker.itemButtons),
-- a thin bronze edge, a cooldown sweep, the count, red out of range. (On the quest's icon was tried:
-- bigger than a line, it ran into the headings with the objectives folded.) Not on a quest folded to
-- its title. Secure buttons can't move in a fight, or hang off
-- anything that does: they sit on UIParent, placed from the rows out of combat, twice a second,
-- which also covers scrolling, bags and a moved tracker.
do
    local SIZE = 24
    local buttons = {}
    local Cooldown = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    local InRange = (C_Item and C_Item.IsItemInRange) or IsItemInRange
    local Count = (C_Item and C_Item.GetItemCount) or GetItemCount

    local function Button(i)
        local b = buttons[i]
        if b then return b end
        b = CreateFrame("Button", "WaymarkTrackerItem" .. i, UIParent, "SecureActionButtonTemplate")
        b:SetSize(SIZE, SIZE)
        b:SetFrameStrata("MEDIUM")
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetAttribute("type", "item")
        -- a thin edge: dark bronze, a pixel of black inside it
        local edge = b:CreateTexture(nil, "BACKGROUND")
        edge:SetAllPoints()
        edge:SetColorTexture(0.55, 0.43, 0.22, 0.9)
        local inner = b:CreateTexture(nil, "BORDER")
        inner:SetPoint("TOPLEFT", 1, -1)
        inner:SetPoint("BOTTOMRIGHT", -1, 1)
        inner:SetColorTexture(0, 0, 0, 1)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 2, -2)
        b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local lit = b:CreateTexture(nil, "HIGHLIGHT")
        lit:SetAllPoints(b.icon)
        lit:SetColorTexture(1, 1, 1, 0.2)
        b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        b.cd:SetAllPoints(b.icon)
        b.cd:SetDrawEdge(false)
        b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        b.count:SetPoint("BOTTOMRIGHT", 2, -1)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetItemByID(self.item)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        buttons[i] = b
        return b
    end

    -- what changes in a fight too: the sweep, the count, red out of reach of a foe you target
    -- (item range on a friend in a fight may bring "Interface action failed": foes only)
    local function Refresh(b)
        local start, dur = Cooldown(b.item)
        if start and dur and dur > 1.5 then b.cd:SetCooldown(start, dur) else b.cd:Clear() end
        local n = Count(b.item) or 0
        b.count:SetText(n > 1 and n or "")
        local far = false
        if UnitExists("target") and UnitCanAttack("player", "target") and InRange then
            local ok, r = pcall(InRange, b.item, "target")
            far = ok and r == false
        end
        if far then b.icon:SetVertexColor(1, 0.3, 0.3) else b.icon:SetVertexColor(1, 1, 1) end
    end

    -- which item a quest uses, asked on the slow tick only: placing runs every frame something moves
    local itemFor = {}
    local function Place(fresh)
        if InCombatLockdown() then return end
        if fresh then wipe(itemFor) end
        local c, used = Cfg(), 0
        local left = frame and frame:IsVisible() and c.itemButtons ~= false and not c.collapsed and frame:GetLeft()
        if left then
            local u = UIParent:GetEffectiveScale()
            local x = left * frame:GetEffectiveScale() / u - 3
            for _, r in ipairs(rows) do
                local q = r.kind == "quest" and r.quest
                -- (a quest folded to its title: its item goes too)
                if q and r:IsVisible() and r:GetAlpha() > 0 and not q.complete and not q.untracked
                   and not (c.folded and c.folded[q.id]) then
                    local item = itemFor[q.id]
                    if item == nil then
                        local ok, found = pcall(ns.QuestUseItem, q.id, q.index)
                        item = ok and found or false
                        itemFor[q.id] = item
                    end
                    local _, mid = r:GetCenter()
                    if item and mid then
                        used = used + 1
                        local b = Button(used)
                        if b.item ~= item then
                            b.item = item
                            b:SetAttribute("item", "item:" .. item)
                            b.icon:SetTexture(GetItemIcon and GetItemIcon(item) or 134400)
                        end
                        local y = mid * r:GetEffectiveScale() / u
                        if b.x ~= x or b.y ~= y then
                            b.x, b.y = x, y
                            b:ClearAllPoints()
                            b:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", x, y)
                        end
                        b:Show()
                    end
                end
            end
        end
        for i = used + 1, #buttons do buttons[i]:Hide() end
    end

    -- twice a second: items asked again (bags, quests), sweeps and red. Every frame, cheaply: placed
    -- again the moment the tracker moves, scrolls, folds, hides or draws anew
    local ticker, since, last = CreateFrame("Frame"), 0, ""
    ticker:SetScript("OnUpdate", function(_, e)
        if not ns.db then return end
        since = since + e
        if since >= 0.5 then
            since = 0
            Place(true)
            for _, b in ipairs(buttons) do
                if b:IsShown() and b.item then Refresh(b) end
            end
            return
        end
        if not frame then return end
        local vis = frame:IsVisible()
        local sig = vis and string.format("%.1f %.1f %.1f %d %s", frame:GetLeft() or 0, frame:GetTop() or 0,
            scrollY or 0, ns.trackerDraws or 0, tostring(Cfg().collapsed)) or "hidden"
        if sig ~= last then
            last = sig
            Place()
        end
    end)
end
