local _, ns = ...

-- As told (the Lab; the user's go-ahead 2026-11-11: "a new and immersive way to quest"). The map pencils in only
-- what a quest giver TOLD you: a place named in the quest's own words gets a pencil ring with those words by it,
-- "north-west of Sentinel Hill" an arrow from Sentinel Hill, "northern Westfall" a patch of hatching over the
-- north of Westfall, "to the south" an arrow from where you stood when it was said. A quest that names nothing
-- gets nothing: no dots, no coordinates, nothing the giver didn't say ([[bfi-design-direction]]: no hand-holding).
--
--   AsToldRead.lua reads the words (no game calls: luajit tools/as_told_test.lua). This file keeps what was said
--   (WaymarkCharDB.told, per character: the words as the giver said them, who, where you stood), draws it on the
--   Battlefield Map, and holds the note "What I've been told" (/told): every quest in the log with the sentences
--   that say where, and under a quest the ones handed in just before it, so a long chain reads as one telling.
--
--   Drawn once per change (map, size, zoom, what's told): a texture and a line of words a mark, 14 marks at most.
--   No mouse on the map: it stays yours. English clients only (the reader knows directions as English words).
--
--   Since 2026-11-12 the words live in the panel (AsToldPanel.lua), not on the map and not in a paper note: the
--   map keeps marks only, faint for every told place, full for the one quest that leads (ns.ToldLead).
--   /told           the panel, shown or hidden      /told map      the pencil on the map, on or off
--   /told story     the story so far of the leading quest's chain
--   /told next      a wheel notch on the panel: the list of quests, then the next one in it (for a macro or a key)
--   /told list      the list of quests, open or shut
--   /told look      pencil (the default), or round four's gold rings (the user, 2026-11-13: no)
--   /told faint     the other quests' places as faint rings too, on or off (off: only the panel's quest is drawn)
--   /told read      (dev) what was read from each quest in the log, in the chat

local MEDIA = ns.MEDIA .. "AsTold\\"
local FONT = ns.MEDIA .. "Fonts\\Felipa-Regular.ttf"
local PLAIN = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local PENCIL = { 0.17, 0.16, 0.17 }
local PAPER = { 0.93, 0.87, 0.72 }
local MAX_MARKS = 14
local KEEP_DONE = 200     -- handed-in quests kept for the chains, the oldest dropped first
-- A chain is only what the game itself says is one: handed in, and the giver's next quest opens by itself, in the
-- same breath. Picking up three quests in a minute is not a chain (the first edition went by the clock: wrong).
local CHAIN_GAP = 2
local RATE = 0.3

local DEFAULTS = { on = true, map = true, alpha = 90, size = 12, panel = true, backdrop = true, scale = 100 }
-- Out of the Lab for 1.3 on 2026-11-14 (the user: the panel and how it acts are done). Its settings are the
-- addon's own (ns.db.told; DEFAULTS in BattlefieldInfo.lua, the same as DEFAULTS here, which only stands in before
-- the settings are read), carried over once from the Lab's store where a dev copy had them there.
local function Cfg()
    local c = ns.db and ns.db.told
    if not c then return DEFAULTS end
    local old = WaymarkDB and WaymarkDB.lab and WaymarkDB.lab.told
    if old and not old.moved then
        for k, v in pairs(old) do c[k] = v end
        old.moved = true
    end
    return c
end
ns.ToldCfg = Cfg

local function Book()
    WaymarkCharDB = WaymarkCharDB or {}
    local t = WaymarkCharDB.told
    if not t then
        t = { quests = {} }
        WaymarkCharDB.told = t
    end
    return t
end

-- The places and the reading ---------------------------------------------------------------------------------

local index
local contOf = {}
local function Cont(mapID)
    if not mapID then return nil end
    if contOf[mapID] == nil then
        local info = C_Map.GetMapInfo(mapID)
        contOf[mapID] = info and info.parentMapID or false
    end
    return contOf[mapID] or nil
end

local function Index()
    if index then return index end
    local all = (ns.MapEdition and ns.MapEdition() == "Era" and ns.MapOverlaysEra) or ns.MapOverlays or {}
    local places = ns.AsToldPlaces(all, function(id)
        return C_Map.GetAreaInfo and C_Map.GetAreaInfo(id)
    end, function(id)
        local info = C_Map.GetMapInfo(id)
        if info then return info.name, info.parentMapID end
    end)
    -- (the gazetteer, where it exists: every named area at its real place, mines and towers the overlays don't
    -- name. A place the overlays also know keeps the gazetteer's spot: it is the place, not its art's box.)
    local rows = ns.Places
    if type(rows) == "function" then local ok, v = pcall(rows) rows = ok and v or nil end
    if type(rows) == "table" then
        local at = {}
        for i, p in ipairs(places) do at[(p.map or 0) .. ":" .. p.name] = i end
        for _, r in ipairs(rows) do
            if r.name and r.map and r.x and r.y then
                local key = r.map .. ":" .. r.name
                local row = { name = r.name, map = r.map, cont = Cont(r.map), x = r.x, y = r.y,
                              rx = math.min(r.rx or 0.02, 0.12), ry = math.min(r.ry or 0.02, 0.12) }
                if at[key] then
                    if not places[at[key]].zone then places[at[key]] = row end
                else
                    places[#places + 1] = row
                    at[key] = #places
                end
            end
        end
    end
    index = ns.AsToldIndex(places)
    return index
end

local read = {}   -- [questID] = tellings, until its words change
local stamp = 0
local function Tellings(id, q)
    local list = read[id]
    if not list then
        -- (a city or a cave's own map: the zone it lies in is the home that picks between two places of a name)
        local home = q.map
        local info = home and C_Map.GetMapInfo(home)
        if info and Enum and Enum.UIMapType and info.mapType and info.mapType > Enum.UIMapType.Zone then home = info.parentMapID end
        local all = ns.AsToldRead(Index(), (q.text or "") .. "\n" .. (q.obj or ""), home, Cont(home))
        -- (the place the quest was given in is where you bring it back, not where it sends you: "report back to
        -- Marshal Dughan in Goldshire" rings nothing, and Goldshire's quests don't all "share this ground")
        list = {}
        -- (by its name, and by the ground: Stormwind's Trade District is in "Stormwind City", and the giver who
        -- says "in Stormwind" stands in it. The checker, 2026-11-15: 118 quests ringed the place they were given in.)
        for _, t in ipairs(all) do
            local p = t.kind == "place" and t.place
            local stoodIn = p and ((q.where and p.name == q.where) or
                (q.x and p.map == q.map and not p.zone and p.x and math.abs(q.x - p.x) <= (p.rx or 0) and math.abs(q.y - p.y) <= (p.ry or 0)))
            if not stoodIn then list[#list + 1] = t end
        end
        read[id] = list
    end
    return list
end

-- Keeping what was said --------------------------------------------------------------------------------------

local pending          -- the quest on offer in the giver's window
local lastDone, lastDoneAt

local function Here()
    local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not (pos and pos.x) or (pos.x == 0 and pos.y == 0) then return mapID end
    return mapID, pos.x, pos.y
end

local function Changed(kind, id)
    stamp = stamp + 1
    if ns.ToldEvent then ns.ToldEvent(kind or "changed", id) end
end

local function Prune(book)
    local done = {}
    for id, q in pairs(book.quests) do
        if q.done then done[#done + 1] = { id, q.done } end
    end
    if #done <= KEEP_DONE then return end
    table.sort(done, function(a, b) return a[2] < b[2] end)
    for i = 1, #done - KEEP_DONE do book.quests[done[i][1]] = nil end
end

local function Offered()
    local id = GetQuestID and GetQuestID()
    if not id or id == 0 then return end
    local mapID, x, y = Here()
    pending = {
        id = id,
        title = GetTitleText and GetTitleText() or nil,
        text = GetQuestText and GetQuestText() or nil,
        obj = GetObjectiveText and GetObjectiveText() or nil,
        who = UnitName("questnpc") or UnitName("npc") or nil,
        where = GetMinimapZoneText and GetMinimapZoneText() or nil,
        map = mapID, x = x, y = y,
    }
    if lastDone and lastDone ~= id and GetTime() - (lastDoneAt or 0) < CHAIN_GAP then pending.after = lastDone end
    lastDone = nil   -- (one follow-up a hand-in: whatever is opened after this one is its own story)
end

local function Taken(id)
    local book = Book()
    local q = book.quests[id]
    if pending and pending.id == id and pending.text and pending.text ~= "" then
        q = pending
        q.id = nil
        pending = nil
    elseif not q then
        return false   -- (taken without the giver's window, or shared: the log scan below reads it)
    end
    q.done = nil
    q.t = time()
    if q.after and not book.quests[q.after] then q.after = nil end
    book.quests[id] = q
    read[id] = nil
    Changed("taken", id)
    return true
end

-- the quests already in the log that nobody was heard giving (taken before this was on, or shared): their words
-- from the log itself. The log's selection is put back; not while the game's own log is open.
local function LogQuests()
    local out = {}
    local n = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries()) or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
    for i = 1, n do
        local id, title, header
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            if info then id, title, header = info.questID, info.title, info.isHeader end
        elseif GetQuestLogTitle then
            local t, _, _, h, _, _, _, qid = GetQuestLogTitle(i)
            id, title, header = qid, t, h
        end
        if id and id > 0 and not header then out[#out + 1] = { id = id, title = title, index = i } end
    end
    return out
end

-- A quest read from the log was never heard given, so it did not know who gave it or where, and "the place it
-- was given in is never ringed" did nothing for it (the checker, 2026-11-15: 452 quests ringed their home town
-- read from the log, 118 taken). The quest data knows the giver and where they stand: asked once a quest.
local function Given(id, q)
    if q.who or q.where or not ns.QuestEnds then q.gv = true return false end
    local ok, e = pcall(ns.QuestEnds, id)
    if not (ok and e) then return false end   -- (the data isn't in yet: asked again at the next scan)
    q.gv = true
    local f = e.from
    if not (f and f.name and f.map and f.x) then return false end
    q.who, q.map, q.x, q.y = f.name, f.map, f.x, f.y
    -- (the smallest named area of the places list that holds the spot: the game's own name for it)
    local best
    for _, p in ipairs(ns.PlacesOn and ns.PlacesOn(f.map) or {}) do
        if p.source == "area" and p.name and math.abs(f.x - p.x) <= p.rx and math.abs(f.y - p.y) <= p.ry
           and (not best or p.rx * p.ry < best.rx * best.ry) then best = p end
    end
    q.where = best and best.name or nil
    return true
end

local logTries = {}
local removed = {}     -- quests the game itself said were removed (QUEST_REMOVED), until the next scan
local function ScanLog()
    local book = Book()
    local log = LogQuests()
    local inLog, missing = {}, {}
    for _, e in ipairs(log) do
        inLog[e.id] = true
        local q = book.quests[e.id]
        -- (three tries a quest, no more: selecting a quest to read it makes the log say "changed", which brings
        -- us back here; a quest whose words never come would have us turning the log's page every second)
        if (not q or q.done) and (logTries[e.id] or 0) < 3 then
            logTries[e.id] = (logTries[e.id] or 0) + 1
            missing[#missing + 1] = e
        end
    end
    local changed = false
    -- (gone from the log and never handed in: abandoned. Its words go with it. Not when the log reads empty
    -- and the game named no quest as removed: across a loading screen the log is empty for a moment, and every
    -- quest's words, giver and place went with it. The user, 2026-11-15, in another zone with twelve quests:
    -- "the As told panel is shown. Nobody has told you anything yet.")
    for id, q in pairs(book.quests) do
        if not q.done and not inLog[id] and (#log > 0 or removed[id]) then
            book.quests[id] = nil
            read[id] = nil
            changed = true
        end
    end
    local logFrame = QuestLogFrame or QuestMapFrame
    if #missing > 0 and not (logFrame and logFrame:IsVisible()) and not (InCombatLockdown and InCombatLockdown()) then
        local modern = C_QuestLog and C_QuestLog.GetSelectedQuest and C_QuestLog.SetSelectedQuest
        local was = modern and C_QuestLog.GetSelectedQuest() or (GetQuestLogSelection and GetQuestLogSelection())
        for _, e in ipairs(missing) do
            local ok, text, obj
            if modern then
                ok = pcall(C_QuestLog.SetSelectedQuest, e.id)
            elseif SelectQuestLogEntry then
                ok = pcall(SelectQuestLogEntry, e.index)
            end
            if ok then ok, text, obj = pcall(GetQuestLogQuestText, e.index) end
            if ok and text and text ~= "" then
                book.quests[e.id] = { title = e.title, text = text, obj = obj, t = time(), fromLog = true }
                read[e.id] = nil
                changed = true
            end
        end
        if modern then
            pcall(C_QuestLog.SetSelectedQuest, was or 0)
        elseif SelectQuestLogEntry and was then
            pcall(SelectQuestLogEntry, was)
        end
    end
    for id, q in pairs(book.quests) do
        if q.fromLog and not q.done and not q.gv and Given(id, q) then
            read[id] = nil
            changed = true
        end
    end
    removed = {}
    if changed then Changed() end
end

local events = CreateFrame("Frame")
local waiting
for _, e in ipairs({ "PLAYER_LOGIN", "QUEST_DETAIL", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE",
                     "QUEST_COMPLETE", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
                     "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    events:RegisterEvent(e)
end
events:SetScript("OnEvent", function(_, event, a, b)
    if not (WaymarkDB and Cfg().on) then return end
    if event == "QUEST_DETAIL" then
        pcall(Offered)
    elseif event == "QUEST_ACCEPTED" then
        local id = b or a   -- (Era sends the log index first, Forever the quest alone)
        C_Timer.After(0.2, function() pcall(Taken, id) end)
    elseif event == "QUEST_TURNED_IN" then
        local q = Book().quests[a]
        lastDone, lastDoneAt = a, GetTime()
        if q then
            q.done = time()
            Prune(Book())
            Changed("done", a)
        end
    elseif event == "QUEST_COMPLETE" then
        -- (the giver's words as you hand in: the game's log never keeps them; the story so far does)
        local id = GetQuestID and GetQuestID()
        local q = id and Book().quests[id]
        local said = GetRewardText and GetRewardText()
        if q and said and said ~= "" then q.last = said end
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then
        if ns.ToldEvent then pcall(ns.ToldEvent, "zone") end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        if ns.ToldPanelEvent then ns.ToldPanelEvent(event == "PLAYER_REGEN_DISABLED" and "fight" or "calm") end
    elseif event == "PLAYER_LOGIN" or event == "QUEST_LOG_UPDATE" or event == "QUEST_REMOVED" or event == "PLAYER_ENTERING_WORLD" then
        if event == "QUEST_REMOVED" and a then removed[a] = true end
        -- (after a loading screen every quest may be asked for its words again)
        if event == "PLAYER_ENTERING_WORLD" then logTries = {} end
        if waiting then return end
        waiting = true
        local login = event == "PLAYER_LOGIN"
        if login then index, read = nil, {} end   -- (every file is in now: the places list is whole)
        C_Timer.After(login and 4 or 1, function()
            waiting = nil
            pcall(ScanLog)
            if login and ns.ToldEvent then pcall(ns.ToldEvent, "login") end
        end)
    end
end)

-- every quest in the log with what it tells, the newest first: { id, q, tellings }
function ns.ToldNow()
    local out = {}
    for id, q in pairs(Book().quests) do
        if not q.done then out[#out + 1] = { id = id, q = q, tellings = Tellings(id, q) } end
    end
    table.sort(out, function(x, y)
        if (x.q.t or 0) ~= (y.q.t or 0) then return (x.q.t or 0) > (y.q.t or 0) end
        return x.id < y.id
    end)
    return out
end

-- Which quest leads ------------------------------------------------------------------------------------------
-- One story at a time (the user, 2026-11-11: a map filled with text gets switched off). The leading quest is the
-- one the panel tells and the map inks; every other told place is a faint ring. It changes only when something
-- happens (a quest taken, handed in or dropped, a new place entered, the wheel on the panel), never while walking.

local leadId
-- (a quest with nothing to count, "deliver this message to Onu", is called complete by the game from the moment
-- it is taken: seen in game 2026-11-13 as "Done." on a letter not yet carried. Only a quest that had something
-- to do can be done; where the client can't say how many objectives there are, the game's word stands.)
local function Counted(id)
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, list = pcall(C_QuestLog.GetQuestObjectives, id)
        if ok and type(list) == "table" then
            -- (Forever gives a delivery one objective that repeats the quest's summary, already ticked: seen
            -- 2026-11-13, "done" on Grove of the Ancients after the first fix. That is nothing to count either;
            -- nor is a "log" or "event" line. An escort then never reads "Done.": the lesser fault.)
            local q = WaymarkCharDB and WaymarkCharDB.told and WaymarkCharDB.told.quests[id]
            local sum = q and q.obj and q.obj:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
            for _, o in ipairs(list) do
                local text = type(o) == "table" and o.text and o.text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "") or ""
                local kind = type(o) == "table" and o.type
                if kind ~= "log" and kind ~= "event" and not (sum and text ~= "" and text == sum) then return true end
            end
            return false
        end
    end
    if GetQuestLogIndexByID and GetNumQuestLeaderBoards then
        local i = GetQuestLogIndexByID(id)
        if i and i > 0 then
            local ok, n = pcall(GetNumQuestLeaderBoards, i)
            if ok and type(n) == "number" then return n > 0 end
        end
    end
    return true
end
local function Complete(id)
    if not Counted(id) then return false end
    if C_QuestLog and C_QuestLog.IsComplete then
        local ok, v = pcall(C_QuestLog.IsComplete, id)
        if ok then return v and true or false end
    end
    if GetQuestLogIndexByID and GetQuestLogTitle then
        local i = GetQuestLogIndexByID(id)
        if i and i > 0 then
            local _, _, _, _, _, c = GetQuestLogTitle(i)
            return c == 1 or c == true
        end
    end
    return false
end
ns.ToldComplete = Complete

-- the place you stand in, "" in the open: the zone's own name is not a place (seen 2026-11-13: "HERE · DARKSHORE"
-- gathered every quest that says Darkshore, and the rest read as if they were somewhere else)
local function HereName()
    local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or nil
    local s = GetSubZoneText and GetSubZoneText()
    if s and s ~= "" and s ~= zone then return s end
    s = GetMinimapZoneText and GetMinimapZoneText() or ""
    if s == zone then return "" end
    return s
end
ns.ToldHereName = HereName

local function Names(it, name)
    for _, t in ipairs(it.tellings) do
        if t.place and t.place.name == name then return true end
    end
    return false
end

-- the quests that tell of the place you stand in, the newest first
function ns.ToldHere()
    local out, here = {}, HereName()
    if here == "" then return out end
    for _, it in ipairs(ns.ToldNow()) do
        if Names(it, here) then out[#out + 1] = it end
    end
    return out
end

-- the quests that came before this one in its chain and whose words we kept, the nearest first (four at most).
-- The chain is the quest data's own (ns.QuestChain, as the quest window shows it); where that knows nothing of the
-- quest, the one follow-up the game opened by itself after a hand-in (q.after).
local function Before(id, q, book)
    local out = {}
    local ok, chain = pcall(function() return ns.QuestChain and ns.QuestChain(id) end)
    if ok and chain and chain.steps and (chain.index or 1) > 1 then
        for i = chain.index - 1, 1, -1 do
            local s = chain.steps[i]
            if s and book.quests[s.id] and #out < 4 then out[#out + 1] = s.id end
        end
        return out
    end
    local back = q.after
    while back and book.quests[back] and #out < 4 do
        out[#out + 1] = back
        back = book.quests[back].after
    end
    return out
end
function ns.ToldBefore(id)
    local book = Book()
    local q = book.quests[id]
    return q and Before(id, q, book) or {}
end
-- how many steps of its chain lie ahead of this quest (their names stay unsaid), and which step this is;
-- nil when the data is silent
function ns.ToldAhead(id)
    local ok, chain = pcall(function() return ns.QuestChain and ns.QuestChain(id) end)
    if ok and chain and chain.steps and chain.index then return #chain.steps - chain.index, chain.index end
end
function ns.ToldQuest(id) return Book().quests[id] end

-- the sentences a quest says where in, each once, in the order said: { said, place }
function ns.ToldSaid(id)
    local q = Book().quests[id]
    local out, seen = {}, {}
    if not q then return out end
    for _, t in ipairs(Tellings(id, q)) do
        if not seen[t.said] then
            seen[t.said] = true
            out[#out + 1] = { said = t.said, place = t.place and t.place.name }
        end
    end
    return out
end

local function PickLead()
    local now = ns.ToldNow()
    local c = Cfg()
    local byId = {}
    for _, it in ipairs(now) do byId[it.id] = it end
    if c.hold and not byId[c.hold] then
        -- (held and handed in: with "hold this chain" the hold moves on to the step that follows it)
        local nextId
        if c.holdChain then
            for _, it in ipairs(now) do
                for _, b in ipairs(Before(it.id, it.q, Book())) do
                    if b == c.hold then nextId = it.id end
                end
            end
        end
        c.hold = nextId
        if not nextId then c.holdChain = nil end
    end
    if c.hold then leadId = c.hold return end
    local here, best = HereName(), nil
    if here ~= "" then
        for _, it in ipairs(now) do
            if Names(it, here) and (not best or (Complete(best.id) and not Complete(it.id))) then best = it end
        end
    end
    if best then leadId = best.id return end
    if leadId and byId[leadId] then return end
    leadId = now[1] and now[1].id or nil
end

function ns.ToldLead()
    if not leadId then return nil end
    for _, it in ipairs(ns.ToldNow()) do
        if it.id == leadId then return it end
    end
end
-- the panel's wheel and menu: lead with this quest now (hold = keep it until handed in; chain = and then its next)
function ns.ToldSetLead(id, hold, chain)
    local c = Cfg()
    if hold ~= nil then
        c.hold = hold and id or nil
        c.holdChain = (hold and chain) and true or nil
    end
    if id then leadId = id end
    -- (let go from the menu: nothing switches there and then. The quest stays until you come to a place another
    -- quest names: the user, 2026-11-13, "When unheld from menu, it does not switch right away, and it doesnt
    -- switch if not at the location of another quest.")
    stamp = stamp + 1
end

-- something happened: who leads now, and the panel hears of it
local zoneWaits
function ns.ToldEvent(kind, id)
    -- (the pointer is on the panel: a place walked into or out of changes nothing under it. It counts when the
    -- pointer leaves, ns.ToldSettle. The user, 2026-11-15: "the quest in focus while hovering tries to fade out
    -- of focus, or even switches".)
    if kind == "zone" and ns.ToldPanelBusy and ns.ToldPanelBusy() then
        zoneWaits = true
        return
    end
    zoneWaits = nil
    local was = leadId
    if kind == "taken" and id and not Cfg().hold then leadId = id else PickLead() end
    stamp = stamp + 1
    if ns.ToldPanelEvent then ns.ToldPanelEvent(kind, id, was ~= leadId) end
end
-- the pointer left the panel: a place entered meanwhile counts now. True when there was one.
function ns.ToldSettle()
    if not zoneWaits then return false end
    ns.ToldEvent("zone")
    return true
end

-- The map ----------------------------------------------------------------------------------------------------
-- Marks, no sentences. One place, one mark, eight faint ones at most.
--
-- The look (mockups\joint\look.md, 2026-11-12, after the first picture of all the pieces on the real painted
-- map: graphite rings and arrows could not be seen on it, and handwritten names three times the map's own
-- labels read as laid over it):
--   pencil  (the default again since 2026-11-13) the first edition's graphite ring, handwritten name, arrows
--           and hatching. The user on the gold: "the golden rings look like a ubisoft map asset (this is
--           bad)"; pencil is the look. Known from the renders: graphite is hard to see on the painted map's
--           greens at 300 to 420 px; it reads well on the pencilled sheet (Pencil.lua).
--   gold    (/told look gold) round four's small hollow gold ring with a dark edge and the name in small
--           pale-gold capitals; no arrows, no hatching. Overturned by the user; kept until they say remove.

local host, holder
local marks = {}
local shownKey
local FAINT, FULL = 0.3, 0.9
local MAX_FAINT = 8

local function Mark(i)
    local m = marks[i]
    if not m then
        m = { tex = host:CreateTexture(nil, "ARTWORK"), text = holder:CreateFontString(nil, "OVERLAY") }
        m.text:SetJustifyH("CENTER")
        m.text:SetWordWrap(true)
        if m.text.SetMaxLines then m.text:SetMaxLines(2) end
        m.text:SetTextColor(PENCIL[1], PENCIL[2], PENCIL[3])
        -- (a breath of paper under the letters, so the pencil reads over a map's darker ground)
        m.text:SetShadowColor(PAPER[1], PAPER[2], PAPER[3], 0.75)
        m.text:SetShadowOffset(1, -1)
        marks[i] = m
    end
    return m
end

-- where a place lies on the map shown: its middle and half sizes (0..1 of that map), or nil when it isn't on it
local function Box(p, mapID)
    if p.map == mapID then return p.x, p.y, p.rx, p.ry end
    if p.zone and p.cont == mapID then
        local ok, l, r, t, b = pcall(ns.MapRectOnMap, p.map, mapID)
        if ok and l and r and r > l then return (l + r) / 2, (t + b) / 2, (r - l) / 2, (b - t) / 2 end
    end
end

-- what to draw on this map: { kind, x, y (0..1), rx, ry, dx, dy, lead, label }
local function Collect(mapID)
    local list, byKey, faint = {}, {}, 0
    local pencil = Cfg().look ~= "gold"
    local function Put(key, m, lead, label)
        local e = byKey[key]
        if not e then
            if not lead then
                if faint >= MAX_FAINT then return end
                faint = faint + 1
            end
            e = m
            byKey[key] = e
            list[#list + 1] = e
        end
        if lead then e.lead, e.label = true, label end
    end
    -- (the leading quest first, so its marks are never the ones the cap leaves out)
    local now, ordered = ns.ToldNow(), {}
    for _, it in ipairs(now) do if it.id == leadId then ordered[#ordered + 1] = it end end
    for _, it in ipairs(now) do if it.id ~= leadId then ordered[#ordered + 1] = it end end
    -- (only the quest the panel tells is drawn: the user, 2026-11-13, "lets try only the quest currently being
    -- held on the panel gets a circle". /told faint brings the other quests' faint rings back.)
    local faintToo = Cfg().faint
    for _, it in ipairs(ordered) do
        local lead = it.id == leadId
        -- (what the words make of each telling: ns.AsToldMarks in AsToldRead.lua, the checker's rule too)
        local what = (lead or faintToo) and ns.AsToldMarks(it.tellings, it.q.text, it.q.obj, it.id) or {}
        for i, t in ipairs(it.tellings) do
            local p = t.place
            local x, y, rx, ry
            if p and (lead or faintToo) then x, y, rx, ry = Box(p, mapID) end
            local whole = p and p.zone and p.map == mapID
            if not (lead or faintToo) then
                -- (not the panel's quest: nothing of it on the map)
            elseif t.kind == "place" and not what[i] then
                -- (a town to go back to, or to measure from, in any sentence of the quest: no ring)
            elseif t.kind == "place" and x and not whole then
                Put("p" .. p.name, { kind = "ring", x = x, y = y, rx = rx, ry = ry }, lead and what[i] ~= "plain", p.name)
            elseif not pencil then
                -- (the gold look: places only)
            elseif lead and t.kind == "part" and x then
                local dx, dy = ns.AsToldVec(t.dir)
                Put("h" .. p.name .. t.dir, { kind = "part", x = x + dx * rx * 0.55, y = y + dy * ry * 0.55,
                                              rx = math.min(rx * 0.5, 0.2), ry = math.min(ry * 0.5, 0.2) }, true, nil)
            elseif lead and t.kind == "dir" then
                local dx, dy = ns.AsToldVec(t.dir)
                if p and x and not whole then
                    Put("d" .. p.name .. t.dir, { kind = "arrow", x = x, y = y, rx = rx, ry = ry, dx = dx, dy = dy }, true, nil)
                elseif not p and it.q.map == mapID and it.q.x then
                    Put("d" .. it.id .. t.dir, { kind = "arrow", x = it.q.x, y = it.q.y, rx = 0, ry = 0, dx = dx, dy = dy }, true, nil)
                end
            end
        end
    end
    -- An arrow toward where a ring of the same quest already lies says nothing the ring doesn't, and says it
    -- worse: "north" is drawn due north, and north of Auberdine is open sea while the river it means runs into
    -- the Mist's Edge, north-east, which is ringed (the user, 2026-11-15: "an arrow out to sea ... is not what
    -- we want"). Within 60 degrees of the arrow counts; the place the arrow starts at does not.
    local out = {}
    for _, e in ipairs(list) do
        local keep = true
        if e.kind == "arrow" then
            for _, r in ipairs(list) do
                if r.kind == "ring" and r.lead then
                    local vx, vy = (r.x - e.x) * 1.5, r.y - e.y   -- (a map is half again as wide as it is high)
                    if vx * vx + vy * vy > 0.0004 and ns.AsToldToward(e.dx, e.dy, vx, vy) then keep = false break end
                end
            end
        end
        if keep then out[#out + 1] = e end
    end
    return out
end

-- the gold look: rings and one name, sized for the screen (6 px on a map 420 px wide, 5 on 300; the leading
-- quest's 9 and 7), whatever the zoom
local golds = {}
local GOLD_NAME = { 0.96, 0.89, 0.72 }
local UMBER = { 0.20, 0.13, 0.07 }
local function DrawGold(map, list, scale)
    local canvas = map:GetCanvas()
    local W, H = canvas:GetWidth(), canvas:GetHeight()
    holder:SetScale(1 / scale)
    local wide = (map.GetWidth and map:GetWidth()) or 420
    if not wide or wide < 50 then wide = 420 end
    local small = math.max(5, math.min(8, wide * 0.0143))
    local big = math.max(7, math.min(12, wide * 0.0214))
    local close = ns.IsShown and ns.IsShown("detail") and ns.DetailFade and ns.DetailFade(map) or 0
    -- (close up, on the terrain itself, the ring is drawn round the place, not beside it: up to twice and a bit)
    small, big = small * (1 + 1.2 * close), big * (1 + 1.2 * close)
    for i, e in ipairs(list) do
        local g = golds[i]
        if not g then
            g = { ring = holder:CreateTexture(nil, "ARTWORK"), name = holder:CreateFontString(nil, "OVERLAY") }
            g.ring:SetTexture(MEDIA .. "ToldGold")
            g.name:SetFont(PLAIN, 8, "OUTLINE")
            g.name:SetTextColor(GOLD_NAME[1], GOLD_NAME[2], GOLD_NAME[3])
            g.name:SetShadowColor(UMBER[1], UMBER[2], UMBER[3], 1)
            g.name:SetShadowOffset(1, -1)
            g.name:SetJustifyH("CENTER")
            golds[i] = g
        end
        local size = e.lead and big or small
        local px, py = e.x * W * scale, e.y * H * scale
        g.ring:ClearAllPoints()
        g.ring:SetSize(size, size)
        g.ring:SetPoint("CENTER", holder, "TOPLEFT", px, -py)
        g.ring:SetAlpha(e.lead and 1 or 0.85)
        g.ring:Show()
        if e.lead and e.label and close < 0.5 then
            local above = e.y > 0.85
            g.name:SetText(e.label:upper())
            g.name:ClearAllPoints()
            -- (kept on the map: a name by its edge leans inward)
            local nx = math.max(40, math.min(W * scale - 40, px))
            g.name:SetPoint(above and "BOTTOM" or "TOP", holder, "TOPLEFT", nx, -py + (above and (size / 2 + 2) or -(size / 2 + 2)))
            g.name:Show()
        else
            g.name:Hide()
        end
    end
    for i = #list + 1, #golds do golds[i].ring:Hide() golds[i].name:Hide() end
    for _, m in ipairs(marks) do m.tex:Hide() m.text:Hide() end
end

local function Draw(map, mapID, scale)
    local c = Cfg()
    local list = (c.on and c.map) and Collect(mapID) or {}
    if #list == 0 then
        for _, m in ipairs(marks) do m.tex:Hide() m.text:Hide() end
        for _, g in ipairs(golds) do g.ring:Hide() g.name:Hide() end
        host:Hide()
        return
    end
    if c.look == "gold" then
        DrawGold(map, list, scale)
        host:SetAlpha(1)
        local want
        if ns.ArtLevel and ns.ART_LEVELS and ns.ART_LEVELS.marks then
            local ok, v = pcall(ns.ArtLevel, map, "marks")
            if ok then want = v end
        end
        if not want then
            local _, top = ns.CanvasLevels(map)
            want = math.min((top or 0) + 3, 9000)
        end
        if host:GetFrameLevel() ~= want then host:SetFrameLevel(want) end
        host:Show()
        return
    end
    for _, g in ipairs(golds) do g.ring:Hide() g.name:Hide() end
    local canvas = map:GetCanvas()
    local W, H = canvas:GetWidth(), canvas:GetHeight()
    holder:SetScale(1 / scale)
    local size = c.size or 12
    for i, e in ipairs(list) do
        local m = Mark(i)
        local cx, cy = e.x * W, e.y * H
        local tx, ty, above
        local alpha = e.lead and FULL or FAINT
        m.tex:ClearAllPoints()
        m.tex:SetRotation(0)
        if e.kind == "ring" or e.kind == "part" then
            -- (round enough to read as a ring: a long thin place gets a wider one, a speck a ring you can see)
            local w, h = math.max(e.rx * 2 * W * 1.15, W * 0.055), math.max(e.ry * 2 * H * 1.15, W * 0.055)
            if w > h * 1.45 then h = w / 1.45 elseif h > w * 1.45 then w = h / 1.45 end
            -- (a ring says "here", not "this fifth of the zone": a place's art box can be far wider than the place)
            if e.kind == "ring" then
                local cap = W * 0.11
                if w > cap then h = h * cap / w w = cap end
                if h > cap then w = w * cap / h h = cap end
            end
            m.tex:SetTexture(MEDIA .. (e.kind == "ring" and "ToldRing" or "ToldPart"))
            m.tex:SetSize(w, h)
            m.tex:SetPoint("CENTER", host, "TOPLEFT", cx, -cy)
            m.tex:SetVertexColor(PENCIL[1], PENCIL[2], PENCIL[3], e.kind == "ring" and alpha or alpha * 0.66)
            above = e.y > 0.8
            tx, ty = cx, above and (cy - h / 2) or (cy + h / 2)
        else
            local len = W * 0.085
            local gap = e.rx > 0 and math.min(math.max(e.rx * W, e.ry * H, W * 0.0275) * 1.2, W * 0.07) or W * 0.012
            local mx, my = cx + e.dx * (gap + len / 2), cy + e.dy * (gap + len / 2)
            m.tex:SetTexture(MEDIA .. "ToldArrow")
            m.tex:SetSize(len, len)   -- (a square picture, the arrow across its middle: it turns whole)
            m.tex:SetPoint("CENTER", host, "TOPLEFT", mx, -my)
            m.tex:SetRotation(math.atan2(-e.dy, e.dx))
            m.tex:SetVertexColor(PENCIL[1], PENCIL[2], PENCIL[3], alpha)
        end
        m.tex:Show()
        -- (told.names = false: the marks alone, no lettering; the settings' "Name the places", 2026-11-15)
        if e.lead and e.label and tx and c.names ~= false then
            if not pcall(m.text.SetFont, m.text, FONT, size, "") or not m.text:GetFont() then m.text:SetFont(PLAIN, size - 2, "") end
            m.text:SetWidth(130)
            m.text:SetText(e.label)
            m.text:ClearAllPoints()
            -- (kept on the map: a name by its edge leans inward)
            local px = math.max(70, math.min(W * scale - 70, tx * scale))
            m.text:SetPoint(above and "BOTTOM" or "TOP", holder, "TOPLEFT", px, -(ty * scale) + (above and 3 or -3))
            m.text:Show()
        else
            m.text:Hide()
        end
    end
    for i = #list + 1, #marks do marks[i].tex:Hide() marks[i].text:Hide() end
    host:SetAlpha((c.alpha or 90) / 100)
    -- (marks have a named level of their own once the shared list exists; until then, over the pins)
    local want
    if ns.ArtLevel and ns.ART_LEVELS and ns.ART_LEVELS.marks then
        local ok, v = pcall(ns.ArtLevel, map, "marks")
        if ok then want = v end
    end
    if not want then
        local _, top = ns.CanvasLevels(map)
        want = math.min((top or 0) + 3, 9000)
    end
    if host:GetFrameLevel() ~= want then host:SetFrameLevel(want) end
    host:Show()
end

local function Tick()
    local map = BattlefieldMapFrame
    if not map then return end
    if not host then
        local canvas = map:GetCanvas()
        host = CreateFrame("Frame", nil, canvas)
        host:SetAllPoints(canvas)
        holder = CreateFrame("Frame", nil, host)
        holder:SetSize(1, 1)
        holder:SetPoint("TOPLEFT")
        host:Hide()
    end
    local c = Cfg()
    if not (map:IsVisible() and c.on and c.map) then
        if host:IsShown() then host:Hide() end
        shownKey = nil
        return
    end
    local mapID, scale = map:GetMapID(), map:GetCanvasScale() or 1
    local close = math.floor((ns.IsShown and ns.IsShown("detail") and ns.DetailFade and ns.DetailFade(map) or 0) * 8 + 0.5)
    local key = table.concat({ mapID or 0, stamp, scale, map:GetCanvas():GetWidth(), c.alpha or 0, c.size or 0, leadId or 0, c.faint and 1 or 0, c.names == false and 0 or 1,
                               c.look or "pencil", (map.GetWidth and map:GetWidth()) or 0, close }, ":")
    if key == shownKey then return end
    shownKey = key
    Draw(map, mapID, scale)
end

local ticker = CreateFrame("Frame")
local since, lastScale = 0, nil
ticker:SetScript("OnUpdate", function(_, e)
    since = since + e
    -- (while the map zooms, every frame: the names keep their size by the canvas's scale)
    local map = BattlefieldMapFrame
    local scale = map and map:IsVisible() and map:GetCanvasScale()
    if scale and scale ~= lastScale then
        lastScale = scale
        if WaymarkDB then pcall(Tick) end
        return
    end
    if since < RATE then return end
    since = 0
    if WaymarkDB then pcall(Tick) end
end)

-- (a row on the settings page changed: Options.lua through ns.OnSettingChanged)
function ns.ToldSettingChanged()
    shownKey = nil
    if ns.ToldPanelEvent then ns.ToldPanelEvent("changed") end
end

SLASH_WAYMARKTOLD1 = "/told"
SLASH_WAYMARKTOLD2 = "/astold"
SlashCmdList.WAYMARKTOLD = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local c = Cfg()
    if msg == "map" then
        c.map = not c.map
        shownKey = nil
        print("|cffc8a86eWaymark|r: What you've been told is " .. (c.map and "pencilled on the map." or "off the map."))
    elseif msg == "off" or msg == "on" then
        c.on = msg == "on"
        shownKey = nil
        if ns.ToldPanelEvent then ns.ToldPanelEvent("changed") end
        print("|cffc8a86eWaymark|r: As told is " .. msg .. ".")
    elseif msg == "read" then
        for _, it in ipairs(ns.ToldNow()) do
            print("|cffc8a86e" .. (it.q.title or it.id) .. "|r" .. (it.q.fromLog and " (from the log)" or "") .. (it.id == leadId and "  [leads]" or ""))
            for _, t in ipairs(it.tellings) do
                print("   " .. t.kind .. " " .. (t.dir or "") .. " " .. (t.place and t.place.name or "(where it was said)") .. ": " .. t.words)
            end
            -- (what the game counts for it: the evidence for "Done.")
            if C_QuestLog and C_QuestLog.GetQuestObjectives then
                local ok, list = pcall(C_QuestLog.GetQuestObjectives, it.id)
                for _, o in ipairs(ok and type(list) == "table" and list or {}) do
                    print("   counts: " .. tostring(o.type) .. " " .. tostring(o.finished) .. " " .. tostring(o.text))
                end
                print("   done: " .. tostring(Complete(it.id)))
            end
        end
    elseif msg == "look pencil" or msg == "look gold" or msg == "look" then
        -- (nil is the pencil; a saved "pencil" from the days gold was the default means the same)
        c.look = (msg == "look gold" or (msg == "look" and c.look ~= "gold")) and "gold" or nil
        shownKey = nil
        print("|cffc8a86eWaymark|r: Told places are drawn " .. (c.look == "gold" and "as gold rings." or "in pencil, with their arrows."))
    elseif msg == "next" or msg == "prev" then
        if ns.ToldPanelNext then ns.ToldPanelNext(msg == "prev" and 1 or -1) end
    elseif msg == "list" then
        if ns.ToldPanelList then ns.ToldPanelList() end
    elseif msg == "faint" then
        c.faint = not c.faint or nil
        shownKey = nil
        print("|cffc8a86eWaymark|r: " .. (c.faint and "Every told place is on the map, the other quests' faintly." or "Only the panel's quest is on the map."))
    elseif msg == "story" then
        if ns.ToldPanelStory then ns.ToldPanelStory() end
    else
        if ns.ToldPanelToggle then ns.ToldPanelToggle() end
    end
end
