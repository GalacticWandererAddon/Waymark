local _, ns = ...

-- Quest givers learned as you play: our own quest database, filled in over time.
-- Talking to an NPC (or using an object) that offers quests tells addons which
-- quests; where you stand is about where it stands. Handing a quest in tells who
-- takes it. Kept account-wide in WaymarkQuestDB, so every character adds
-- to it and uses it. The map shows a "!" where a learned giver has a quest you
-- can take, and a "?" where a quest you've finished is handed in.
--
-- WaymarkQuestDB = {
--   givers = { [key] = { name, kind = "npc"|"object",
--                        spots = { [uiMapID] = { x, y, n } },  -- n: visits averaged
--                        offers = { [questID] = true }, takes = { [questID] = true } } },
--   quests = { [questID] = { title, level, factions = { Alliance = true, ... },
--                            repeatable } },
-- }
-- key: "c<npcID>" for a creature, "o<objectID>" for an object.

local TEMPLATE = "BFILearnedPinTemplate"
local AVAILABLE_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local TURNIN_ICON = "Interface\\GossipFrame\\ActiveQuestIcon"
local MAX_N = 12  -- visits averaged into a spot (later ones still move it a little)

local function Cfg() return ns.db.learned end

local function DB()
    WaymarkQuestDB = WaymarkQuestDB or {}
    local db = WaymarkQuestDB
    db.givers = db.givers or {}
    db.quests = db.quests or {}
    db.mobs = db.mobs or {}  -- (monster spots, below)
    return db
end

-- Recording ------------------------------------------------------------------

-- who you're talking to: our key, its name and kind (nil for items, yourself...)
local function Giver()
    -- (inside a dungeon on live Forever names and GUIDs can be secret: then not learned)
    local guid = ns.Known(UnitGUID("questnpc")) or ns.Known(UnitGUID("npc"))
    if not guid then return end
    local kind, _, _, _, _, id = strsplit("-", guid)
    id = tonumber(id)
    if not id then return end
    if kind == "Creature" then
        return "c" .. id, ns.Known(UnitName("questnpc")) or ns.Known(UnitName("npc")), "npc"
    elseif kind == "GameObject" then
        return "o" .. id, ns.Known(UnitName("questnpc")) or ns.Known(UnitName("npc")), "object"
    end
end

-- where you stand, on your map and the zone above it (caves and towns have maps
-- of their own; the Battlefield Map mostly shows the zone)
local function Spots()
    local out = {}
    local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local seen = 0
    while mapID and seen < 4 do
        -- (zone and below: a continent or the world would get every giver in it)
        local info = C_Map.GetMapInfo(mapID)
        if not info or (Enum and Enum.UIMapType and info.mapType <= Enum.UIMapType.Continent) then break end
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if pos and pos.x and (pos.x > 0 or pos.y > 0) then out[mapID] = { pos.x, pos.y } end
        mapID, seen = info.parentMapID, seen + 1
    end
    return out
end
ns.PlayerSpots = Spots  -- (Townsfolk.lua learns its NPCs' spots the same way)

local function Remember(key, name, kind)
    local g = DB().givers[key]
    if not g then
        g = { name = name, kind = kind, spots = {}, offers = {}, takes = {} }
        DB().givers[key] = g
    end
    g.name = name or g.name
    for mapID, p in pairs(Spots()) do
        local s = g.spots[mapID]
        if not s then
            g.spots[mapID] = { p[1], p[2], 1 }
        else
            -- averaged in, so standing at different sides of it centres the pin
            local n = math.min(s[3], MAX_N)
            s[1] = (s[1] * n + p[1]) / (n + 1)
            s[2] = (s[2] * n + p[2]) / (n + 1)
            s[3] = s[3] + 1
        end
    end
    return g
end

local function NoteQuest(id, title, level, repeatable)
    if not id or id == 0 then return end
    local q = DB().quests[id] or { factions = {} }
    q.title = title or q.title
    if level and level > 0 then q.level = level end
    if repeatable ~= nil then q.repeatable = repeatable or nil end
    local faction = UnitFactionGroup("player")
    if faction then q.factions[faction] = true end
    DB().quests[id] = q
end

local changed = false

local function Offers(list)
    if not Cfg().record or #list == 0 then return end
    local key, name, kind = Giver()
    if not key then return end
    local g = Remember(key, name, kind)
    for _, q in ipairs(list) do
        if q.id and q.id > 0 then
            NoteQuest(q.id, q.title, q.level, q.repeatable)
            g.offers[q.id] = true
        end
    end
    changed = true
end

local function Takes(questID)
    if not Cfg().record or not questID or questID == 0 then return end
    local key, name, kind = Giver()
    if not key then return end
    local g = Remember(key, name, kind)
    g.takes[questID] = true
    NoteQuest(questID, GetTitleText and GetTitleText() or nil)
    changed = true
end

-- Monster spots ----------------------------------------------------------------
-- Where you met a quest's monster that the quest data has no place for (one an event
-- or a script brings, Murkdeep): where you stood as you looted it (a step away) or as
-- you or your group killed it (in reach). The game never says where a monster is,
-- only where you are. QuestData.lua's NpcSpawns falls back to these, so objective
-- spots, quest ground, the tracker and "find on map" use them as any spawn.
-- WaymarkQuestDB.mobs[npcID] = { name, spots = { [uiMapID] = { { x, y, n }, ... } } }
local MOB_NEAR = 25  -- yards: a sighting this close to a spot is averaged into it
local MOB_SPOTS = 8  -- at most this many spots a map (the least seen goes)

local function Near(mapID)
    local w = ns.MapYards and ns.MapYards(mapID)
    return w and w > 0 and MOB_NEAR / w or 0.02
end

-- a sighting (n of them) into a map's list: averaged into a spot near it, or a new
-- spot (true)
local function AddSpot(list, mapID, x, y, n)
    local r = Near(mapID)
    for _, s in ipairs(list) do
        if math.abs(s[1] - x) < r and math.abs(s[2] - y) < r then
            local m = math.min(s[3], MAX_N)
            s[1] = (s[1] * m + x * n) / (m + n)
            s[2] = (s[2] * m + y * n) / (m + n)
            s[3] = s[3] + n
            return false
        end
    end
    if #list >= MOB_SPOTS then
        table.sort(list, function(a, b) return a[3] > b[3] end)
        list[#list] = nil
    end
    list[#list + 1] = { x, y, n }
    return true
end

local function MobSeen(guid, name)
    if not (Cfg().record and guid) then return end
    local kind, _, _, _, _, id = strsplit("-", guid)
    id = tonumber(id)
    if kind ~= "Creature" or not id then return end
    if not (ns.QuestMobWanted and ns.QuestMobWanted(id)) then return end
    local mobs = DB().mobs
    local m = mobs[id] or { spots = {} }
    mobs[id] = m
    m.name = name or m.name
    local new = false
    for mapID, p in pairs(Spots()) do
        m.spots[mapID] = m.spots[mapID] or {}
        if AddSpot(m.spots[mapID], mapID, p[1], p[2], 1) then new = true end
    end
    if new and ns.LearnedMobsChanged then ns.LearnedMobsChanged() end
    if new and ns.RefreshLearnedWindow then ns.RefreshLearnedWindow() end
end

-- (quiet: nothing said in chat; the spot just shows up)
local mobEvents = CreateFrame("Frame")
pcall(mobEvents.RegisterEvent, mobEvents, "LOOT_OPENED")
-- (live Forever forbids the combat log to addons: asking brings the "blocked" popup, pcall or not)
if not ns.FOREVER then pcall(mobEvents.RegisterEvent, mobEvents, "COMBAT_LOG_EVENT_UNFILTERED") end
mobEvents:SetScript("OnEvent", function(_, event)
    if not ns.db then return end
    if event == "LOOT_OPENED" then
        -- (a loot source's GUID, the target's name and GUID: secret inside a dungeon on live Forever)
        local guid = GetLootSourceInfo and ns.Known((GetLootSourceInfo(1)))
        local name
        if not guid and ns.Known(UnitIsDead("target")) then guid, name = ns.Known(UnitGUID("target")), ns.Known(UnitName("target")) end
        if guid then ns.Safe("Learn loot", MobSeen, guid, name) end
        return
    end
    local _, sub, _, _, _, _, _, destGUID, destName = CombatLogGetCurrentEventInfo()
    if sub == "PARTY_KILL" then ns.Safe("Learn kill", MobSeen, destGUID, destName) end
end)

-- Sharing ------------------------------------------------------------------------
-- What's been learned (quest givers, their quests, monster spots) travels as a string
-- (Setups.lua writes and reads it); taking one in adds to yours, never replaces it.

function ns.LearnedShareData()
    local db = DB()
    return { givers = db.givers, quests = db.quests, mobs = db.mobs }
end

local function Num01(v) return type(v) == "number" and v >= 0 and v <= 1 end

-- t: a string's data, checked as it goes in (it came from someone else).
-- Returns how many new givers, quests and monsters.
function ns.MergeLearned(t)
    if type(t) ~= "table" then return 0, 0, 0 end
    local db = DB()
    local ng, nq, nm = 0, 0, 0
    for key, g in pairs(type(t.givers) == "table" and t.givers or {}) do
        if type(key) == "string" and key:match("^[co]%d+$") and type(g) == "table" then
            local mine = db.givers[key]
            if not mine then
                mine = { name = type(g.name) == "string" and g.name or nil,
                         kind = (g.kind == "npc" or g.kind == "object") and g.kind or nil,
                         spots = {}, offers = {}, takes = {} }
                db.givers[key] = mine
                ng = ng + 1
            end
            for mapID, s in pairs(type(g.spots) == "table" and g.spots or {}) do
                if type(mapID) == "number" and type(s) == "table" and Num01(s[1]) and Num01(s[2])
                   and not mine.spots[mapID] then
                    mine.spots[mapID] = { s[1], s[2], math.min(tonumber(s[3]) or 1, MAX_N) }
                end
            end
            for _, list in ipairs({ "offers", "takes" }) do
                for qid in pairs(type(g[list]) == "table" and g[list] or {}) do
                    if type(qid) == "number" then mine[list][qid] = true end
                end
            end
        end
    end
    for qid, q in pairs(type(t.quests) == "table" and t.quests or {}) do
        if type(qid) == "number" and type(q) == "table" then
            local mine = db.quests[qid]
            if not mine then
                mine = { title = type(q.title) == "string" and q.title or nil,
                         level = type(q.level) == "number" and q.level or nil,
                         repeatable = q.repeatable == true or nil, factions = {} }
                db.quests[qid] = mine
                nq = nq + 1
            end
            for f in pairs(type(q.factions) == "table" and q.factions or {}) do
                if f == "Alliance" or f == "Horde" then mine.factions[f] = true end
            end
        end
    end
    for id, m in pairs(type(t.mobs) == "table" and t.mobs or {}) do
        if type(id) == "number" and type(m) == "table" and type(m.spots) == "table" then
            local mine = db.mobs[id]
            if not mine then
                mine = { name = type(m.name) == "string" and m.name or nil, spots = {} }
                db.mobs[id] = mine
                nm = nm + 1
            end
            for mapID, list in pairs(m.spots) do
                if type(mapID) == "number" and type(list) == "table" then
                    mine.spots[mapID] = mine.spots[mapID] or {}
                    for _, s in ipairs(list) do
                        if type(s) == "table" and Num01(s[1]) and Num01(s[2]) then
                            AddSpot(mine.spots[mapID], mapID, s[1], s[2], math.min(tonumber(s[3]) or 1, MAX_N))
                        end
                    end
                end
            end
        end
    end
    changed = true
    if ns.RedrawLearned then ns.RedrawLearned() end
    if ns.LearnedMobsChanged then ns.LearnedMobsChanged() end
    if ns.RefreshLearnedWindow then ns.RefreshLearnedWindow() end
    return ng, nq, nm
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_COMPLETE",
                     "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED" }) do
    pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event)
    if not ns.db then return end
    if event == "GOSSIP_SHOW" and C_GossipInfo and C_GossipInfo.GetAvailableQuests then
        local list = {}
        for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
            list[#list + 1] = { id = q.questID, title = q.title, level = q.questLevel, repeatable = q.repeatable }
        end
        ns.Safe("Learn gossip", Offers, list)
    elseif event == "QUEST_GREETING" then
        local list = {}
        for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
            local id, repeatable
            if GetAvailableQuestInfo then
                local _, _, rep, _, qid = GetAvailableQuestInfo(i)
                id, repeatable = qid, rep
            end
            list[#list + 1] = { id = id, title = GetAvailableTitle(i), level = GetAvailableLevel(i), repeatable = repeatable }
        end
        ns.Safe("Learn greeting", Offers, list)
    elseif event == "QUEST_DETAIL" then
        local id = GetQuestID and GetQuestID()
        if id and id > 0 then
            ns.Safe("Learn detail", Offers, { { id = id, title = GetTitleText and GetTitleText() } })
        end
    elseif event == "QUEST_COMPLETE" then
        ns.Safe("Learn complete", Takes, GetQuestID and GetQuestID())
    end
    -- accepting, handing in or dropping a quest changes what the map shows
    if ns.RedrawLearned then C_Timer.After(0.5, ns.RedrawLearned) end
end)

-- Showing --------------------------------------------------------------------

-- QuestieDB knows this quest? (QuestData.lua caches it per quest)
local function QuestieKnows(id)
    return ns.QDBKnowsQuest and ns.QDBKnowsQuest(id) or false
end

local function Completed(id)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(id) end
    return false
end

-- in your log: nil, or true/false for finished
local function InLog(id)
    local index = C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)
    if not index and GetQuestLogIndexByID then
        index = GetQuestLogIndexByID(id)
        if index == 0 then index = nil end
    end
    if not index then return nil end
    if C_QuestLog and C_QuestLog.IsComplete then
        return ns.QuestReady(id, index, C_QuestLog.IsComplete(id),
            C_QuestLog.IsFailed and C_QuestLog.IsFailed(id))
    end
    if GetQuestLogTitle then
        local done = select(6, GetQuestLogTitle(index))
        return ns.QuestReady(id, index, done == 1, done == -1)
    end
    return false
end

local function Trivial(level)
    if not level then return false end
    local green = GetQuestGreenRange and GetQuestGreenRange() or 8
    return UnitLevel("player") - level > green
end

local function Show(id, q)
    local c = Cfg()
    if not q then return false end
    local faction = UnitFactionGroup("player")
    if faction and next(q.factions or {}) and not q.factions[faction] then return false end
    if c.mode == "gaps" and QuestieKnows(id) then return false end
    -- (grey ones by the givers' own Low-level box: a second box here went unseen, the user, 2026-11-07)
    if not (ns.GetTrivialQuests and ns.GetTrivialQuests()) and Trivial(q.level) then return false end
    return true
end

-- the pins for a map: { x, y, giver, available = { ids }, turnins = { ids } }
local function PinsFor(mapID)
    local db, out = DB(), {}
    local c = Cfg()
    for key, g in pairs(db.givers) do
        local s = g.spots[mapID]
        if s then
            local available, turnins = {}, {}
            for id in pairs(g.offers) do
                local q = db.quests[id]
                if Show(id, q) and not Completed(id) and InLog(id) == nil then   -- (repeatables too, as other givers)
                    available[#available + 1] = id
                end
            end
            if ns.IsShown("turnins") then   -- (turn-ins by the main Turn-ins box)
                for id in pairs(g.takes) do
                    if InLog(id) == true and Show(id, db.quests[id]) then turnins[#turnins + 1] = id end
                end
            end
            if #available > 0 or #turnins > 0 then
                out[#out + 1] = { x = s[1], y = s[2], key = key, giver = g, available = available, turnins = turnins }
            end
        end
    end
    return out
end

-- colour of a quest level for you (yellow left as the icon's own gold)
local function LevelColor(level)
    if not level or not GetQuestDifficultyColor then return end
    local ok, col = pcall(GetQuestDifficultyColor, level)
    if not (ok and col and col.r) then return end
    return ns.SoftQuestColor(col.r, col.g, col.b)  -- (Pin.lua: the same tones as Questie's pins)
end

BFILearnedPinMixin = CreateFromMixins(MapCanvasPinMixin)
BFILearnedPinMixin.CheckMouseButtonPassthrough = ns.SafePassthrough  -- see Pin.lua

function BFILearnedPinMixin:OnLoad()
    if self.UseFrameLevelType then pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_BFI_LEARNED") end
end

function BFILearnedPinMixin:ApplyCurrentScale()
    local map = self:GetMap()
    local canvasScale = map and map.GetCanvasScale and map:GetCanvasScale() or 1
    if not canvasScale or canvasScale <= 0 then canvasScale = 1 end
    self:SetScale(ns.PinScale("learned", Cfg().scale) / canvasScale)  -- (PinScale: town view, small map)
    ns.ReanchorPin(self, map)
end

function BFILearnedPinMixin:ApplyCurrentAlpha()
    self:SetAlpha(ns.PinAlpha("learned"))
end

function BFILearnedPinMixin:OnAcquired(p)
    self.info = p
    local tex = self.Icon
    -- a "?" wins: something to hand in here
    local turnin = #p.turnins > 0
    tex:SetTexture(turnin and TURNIN_ICON or AVAILABLE_ICON)
    tex:SetDesaturated(false)
    tex:SetVertexColor(1, 1, 1)
    if not turnin and ns.db.questie.color then
        -- the easiest quest it offers sets the colour
        local low
        for _, id in ipairs(p.available) do
            local q = DB().quests[id]
            if q and q.level and (not low or q.level < low) then low = q.level end
        end
        local r, g, b = LevelColor(low)
        if r then
            tex:SetDesaturated(true)
            tex:SetVertexColor(r, g, b)
        end
    end
    self:ApplyCurrentScale()
    self:ApplyCurrentAlpha()
    self:SetPosition(p.x, p.y)
end

-- the quest pins' tooltip (Pin.lua ns.QuestTooltip), from what we learned.
-- Questie's own only when QuestieDB knows every quest here; else ours, which
-- adds QuestieDB's extras (Shift) for the quests it knows.
function BFILearnedPinMixin:OnEnter()
    local p, db = self.info, DB()
    local npc = { name = p.giver.name or "?", quests = {} }
    local allKnown = true
    local function Add(id, turnin)
        local q = db.quests[id] or {}
        npc.quests[#npc.quests + 1] = { id = id, turnin = turnin, title = q.title, level = q.level, repeatable = q.repeatable }
        allKnown = allKnown and QuestieKnows(id)
    end
    for _, id in ipairs(p.turnins) do Add(id, true) end
    for _, id in ipairs(p.available) do Add(id, false) end
    local spot = p.giver.spots and p.giver.spots[self:GetMap():GetMapID()]
    local visits = spot and spot[3] or 1
    ns.QuestTooltip(self, { npc }, {}, allKnown, {
        string.format("Learned by Waymark (%d visit%s)", visits, visits == 1 and "" or "s"),
    })
    ns.PinHints()
    GameTooltip:Show()
end

function BFILearnedPinMixin:OnLeave() ns.QuestTooltipLeave() end
-- the map wires a pin's mouse-over to these (see Pin.xml)
BFILearnedPinMixin.OnMouseEnter = BFILearnedPinMixin.OnEnter
BFILearnedPinMixin.OnMouseLeave = BFILearnedPinMixin.OnLeave

function BFILearnedPinMixin:OnMouseUp(button)
    if button == "RightButton" then ns.PinMenu(self, nil, self.info.giver and self.info.giver.name) return end  -- (its menu: Controls.lua)
    if ns.PinAltClick then ns.PinAltClick(self, button) end  -- line target (Line.lua)
end

BFILearnedProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)

function BFILearnedProviderMixin:RemoveAllData()
    local map = self:GetMap()
    pcall(map.RemoveAllPinsByTemplate, map, TEMPLATE)
end

function BFILearnedProviderMixin:RefreshAllData() self:Draw() end
function BFILearnedProviderMixin:OnMapChanged() self:Draw() end

function BFILearnedProviderMixin:Draw()
    self:RemoveAllData()
    local map = self:GetMap()
    local mapID = map:GetMapID()
    if not (mapID and ns.IsShown("learned")) then return end
    for _, p in ipairs(PinsFor(mapID)) do
        pcall(map.AcquirePin, map, TEMPLATE, p)
    end
end

function ns.SetupLearned(map)
    -- what players learned and sent in, shipped with the addon (Data\LearnedShipped.lua,
    -- toolsake_learned.lua): added to yours once per version, as an import is
    local db, ship = DB(), ns.LearnedShipped
    if ship and (db.shipped or 0) < (ship.version or 0) then
        ns.Safe("Learn shipped", ns.MergeLearned, ship)
        db.shipped = ship.version
    end
    local provider = CreateFromMixins(BFILearnedProviderMixin)
    local ok, err = pcall(map.AddDataProvider, map, provider)
    if not ok then
        ns.Log("Learned quests layer failed:", err)
        return
    end
    function ns.RedrawLearned()
        if map:IsShown() then ns.Safe("Learn draw", provider.Draw, provider) end
    end
    -- (the givers' Turn-ins box now decides learned turn-ins too: drawn again when it changes)
    if ns.OnSettingChanged then
        hooksecurefunc(ns, "OnSettingChanged", function(group)
            if group == "turnins" then ns.RedrawLearned() end
        end)
    end
    -- what you learn shows up while the map is open
    local elapsed = 0
    local ticker = ns.TimedFrame("Learn tick")
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 2 then return end
        elapsed = 0
        if changed and map:IsVisible() then
            changed = false
            ns.RedrawLearned()
        end
    end)
end

-- for the options page: how much we know
function ns.LearnedStats()
    local db = DB()
    local givers, quests, here = 0, 0, 0
    local mapID = BattlefieldMapFrame and BattlefieldMapFrame:GetMapID()
    for _, g in pairs(db.givers) do
        givers = givers + 1
        if mapID and g.spots[mapID] then here = here + 1 end
    end
    for _ in pairs(db.quests) do quests = quests + 1 end
    local mobs = 0
    for _ in pairs(db.mobs) do mobs = mobs + 1 end
    return givers, quests, here, mobs
end

function ns.ForgetLearned()
    -- (the learned townsfolk stay: they have their own button, Townsfolk.lua)
    WaymarkQuestDB = { givers = {}, quests = {}, townsfolk = WaymarkQuestDB and WaymarkQuestDB.townsfolk }
    wipe(questieKnows)
    if ns.RedrawLearned then ns.RedrawLearned() end
    if ns.LearnedMobsChanged then ns.LearnedMobsChanged() end  -- (the monster spots went too)
end

-- Probe: the game's quest details page, piece by piece -------------------------------

-- /bfi questart: every texture and text of the game's quest log detail page
-- (QuestMapFrame.DetailsFrame on Forever): its art, sizes, fonts and anchors,
-- saved in WaymarkDB.diag.questart for Claude to read, so our own
-- quest window can be built from the same art.
function ns.QuestArtProbe()
    local root = QuestMapFrame and QuestMapFrame.DetailsFrame
    if not root then
        ns.Log("questart: this client has no QuestMapFrame.DetailsFrame")
        return
    end
    local out = {}
    -- an object's name in its parent (parentKey), or its own name, or its type
    local function KeyOf(obj, parent)
        for k, v in pairs(parent or {}) do
            if v == obj and type(k) == "string" then return k end
        end
        return obj:GetName() or obj:GetObjectType()
    end
    local function Point(r)
        local ok, p, rel, rp, x, y = pcall(r.GetPoint, r, 1)
        if not (ok and p) then return end
        local relName = rel and (rel.GetDebugName and rel:GetDebugName() or rel:GetName()) or "-"
        return string.format("%s %s %s %.1f %.1f", p, tostring(relName), tostring(rp), x or 0, y or 0)
    end
    local function Walk(frame, path, depth)
        if depth > 6 or #out > 500 then return end
        for _, r in ipairs({ frame:GetRegions() }) do
            local e = { key = path .. "." .. KeyOf(r, frame), kind = r:GetObjectType(), shown = r:IsShown(),
                        point = Point(r) }
            e.w, e.h = r:GetSize()
            if r:IsObjectType("Texture") then
                e.atlas = r.GetAtlas and r:GetAtlas() or nil
                e.file = r:GetTexture()
                e.layer = (r:GetDrawLayer())
                e.coords = table.concat({ r:GetTexCoord() }, ",")
                e.color = table.concat({ r:GetVertexColor() }, ",")
            elseif r:IsObjectType("FontString") then
                local file, size, flags = r:GetFont()
                e.font, e.size, e.flags = file, size, flags
                e.text = (r:GetText() or ""):sub(1, 60)
                e.color = table.concat({ r:GetTextColor() }, ",")
                e.shadow = table.concat({ r:GetShadowOffset() }, ",")
            end
            out[#out + 1] = e
        end
        for _, ch in ipairs({ frame:GetChildren() }) do
            local key = path .. "." .. KeyOf(ch, frame)
            out[#out + 1] = { key = key, kind = ch:GetObjectType(), shown = ch:IsShown(), point = Point(ch),
                              w = ch:GetWidth(), h = ch:GetHeight(), level = ch:GetFrameLevel() }
            Walk(ch, key, depth + 1)
        end
    end
    local ok, err = pcall(Walk, root, "DetailsFrame", 0)
    if not ok then ns.Log("questart error: " .. tostring(err)) end
    -- and the quest text itself (the game's QuestInfo pieces, shown in the page)
    if QuestInfoFrame then pcall(Walk, QuestInfoFrame, "QuestInfoFrame", 0) end
    ns.db.diag = ns.db.diag or {}
    ns.db.diag.questart = { at = date("%Y-%m-%d %H:%M:%S"), pieces = out }
    ns.Log(string.format("questart: %d pieces saved. /reload to write them to disk.", #out))
end

-- Probe: does the game itself have quest markers? -------------------------------------

-- /bfi questprobe: asks every quest-marker source this client might have, prints
-- and saves the answers (WaymarkDB.diag.questprobe) for Claude to read
function ns.QuestProbe()
    local L = ns.Log
    local mapID = (BattlefieldMapFrame and BattlefieldMapFrame:GetMapID())
        or (C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    local r = { mapID = mapID, at = date("%Y-%m-%d %H:%M:%S") }
    local function Try(name, fn)
        local ok, a, b = pcall(fn)
        local v
        if not ok then v = "error: " .. tostring(a)
        elseif type(a) == "table" then v = #a .. " entries" .. (a[1] and type(a[1]) == "table" and (" (first: " .. tostring(a[1].questName or a[1].name or a[1].questID or "?") .. ")") or "")
        else v = tostring(a) .. (b ~= nil and (", " .. tostring(b)) or "") end
        r[name] = v
        L(name .. ": " .. v)
    end
    L("quest marker probe, map " .. tostring(mapID) .. ":")
    Try("C_QuestLine exists", function() return C_QuestLine ~= nil end)
    if C_QuestLine and C_QuestLine.RequestQuestLinesForMap then pcall(C_QuestLine.RequestQuestLinesForMap, mapID) end
    Try("C_QuestLine.GetAvailableQuestLines", function() return C_QuestLine.GetAvailableQuestLines(mapID) end)
    Try("C_QuestLine.GetForceVisibleQuests", function() return C_QuestLine.GetForceVisibleQuests(mapID) end)
    Try("C_TaskQuest.GetQuestsOnMap", function() return C_TaskQuest.GetQuestsOnMap(mapID) end)
    Try("C_TaskQuest.GetQuestsForPlayerByMapID", function() return C_TaskQuest.GetQuestsForPlayerByMapID(mapID) end)
    Try("C_QuestLog.GetQuestsOnMap (your log)", function() return C_QuestLog.GetQuestsOnMap(mapID) end)
    Try("C_AreaPoiInfo.GetAreaPOIForMap", function() return C_AreaPoiInfo.GetAreaPOIForMap(mapID) end)
    Try("C_GossipInfo.GetAvailableQuests exists", function() return C_GossipInfo and C_GossipInfo.GetAvailableQuests ~= nil end)
    Try("tracking types", function()
        local n = C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetNumTrackingTypes() or (GetNumTrackingTypes and GetNumTrackingTypes())
        local names = {}
        for i = 1, n or 0 do
            local info = C_Minimap and C_Minimap.GetTrackingInfo and C_Minimap.GetTrackingInfo(i)
            names[#names + 1] = type(info) == "table" and info.name or (GetTrackingInfo and GetTrackingInfo(i)) or "?"
        end
        return table.concat(names, ", ")
    end)
    -- the map's own pin kinds right now (a quest-offer pin would be one)
    local kinds = {}
    if BattlefieldMapFrame and ns.EachPin then
        ns.EachPin(BattlefieldMapFrame, function(_, template) kinds[template] = (kinds[template] or 0) + 1 end)
    end
    local list = {}
    for k, n in pairs(kinds) do list[#list + 1] = k .. " " .. n end
    table.sort(list)
    r.pinKinds = table.concat(list, ", ")
    L("pins on the map: " .. r.pinKinds)
    local givers, quests = ns.LearnedStats()
    r.learned = givers .. " givers, " .. quests .. " quests"
    L("learned so far: " .. r.learned)
    ns.db.diag = ns.db.diag or {}
    ns.db.diag.questprobe = r
    L("saved: /reload to write it to disk.")
end
