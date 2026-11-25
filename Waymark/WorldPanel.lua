local _, ns = ...

-- The world map of our own, level 3: the panel that makes Waymark's big map a world map. Lab only; /worldlog, or
-- its tab in the test bench. What it knows comes from Lab\WorldLog.lua (ns.WorldLog). The full notes, with every
-- choice made here and why, and what is left for the polish: mockups\world-map-level3-notes.md.
--
-- What it is: a column on the big map's side, as tall as the map. From the top:
--   the head       the zone on view in the game's own quest gold, how many quests you hold of 25, Held / Done
--   the search     one line: your log, what you were told, the whole book (shut until opened); three ready asks
--   the list       the zone on view: ready to hand in, then BY GROUND (place by place, nearest first), then
--                  "Left undone here". A quest's line: its name in the colour of its level, how far along,
--                  beads for its chain. (The little world and the dust on old quests scrapped, 2026-11-22.)
--   a quest's page in the list's place, with Back, as the game's own log does it: who gave it, the chain as
--                  beads and by name, what was said, what is asked, what it gives, and for a quest you do not
--                  hold what stands in the way.
-- The look: dark slate glass with thin brass rules, the game's quest font and quest colours. Enough of the
-- game's world map that it reads as one (the gold zone title, the count of 25, list then page with Back, the
-- difficulty colours), and none of the found notes' paper (the user: "Dont use the found journal parchment").
-- Controls, as Controls.lua has them everywhere: click = the main thing, right-click = its menu, Shift-click a
-- quest = track it (a link while the chat box is open), the wheel scrolls. Pointing at a quest lights its ground on the map (ns.HoverQuestGlow).
-- A controller (only in the game's controller mode, only while the panel is up): up and down walk the lines,
-- A opens, B goes back (then closes), X tracks, Y flips Held and Done, the bumpers step through your zones.
-- Cost: built only while shown; drawn again when the log, the map on view or a choice changes, never per frame.

local W = ns.WorldLog
local FRIZ = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local WHITE8 = "Interface\\Buttons\\WHITE8X8"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GOLD, BRASS = { 1, 0.82, 0 }, { 0.73, 0.55, 0.32 }
local TEXT, SOFT, DIM = { 0.92, 0.90, 0.85 }, { 0.70, 0.68, 0.62 }, { 0.48, 0.47, 0.44 }
local LOOSE = { 0.62, 0.70, 0.80 }
local SLATE = { 0.050, 0.055, 0.066 }
local PAD_L, PAD_T = 12, 10
local ROW_H = 18
-- the window round the map and the log: its edge beyond them, the bar on top, the folded log's rail, the seam.
-- (No edge: the frame set holds the map as the map's own border does, tight on its art. The user, 2026-11-20,
-- of an edge of 8: "Mapart sits over frame, doesnt fill it either".)
-- (RAIL 44, was 36: folded, the X stands over the rail's top, beside the frame's corner. 2026-11-21)
local EDGE, BAR, RAIL, GAP = 0, 26, 58, 6   -- (RAIL 58: the marks with their rings and counts, 2026-11-22)
local COG_ART = ns.MEDIA .. "World\\WorldCog"     -- (a brass cog in the chevron's make, tools/world_top_art.py)
-- The close and the frame sets (2026-11-21). boss: a set whose top-right corner has a round boss gets the boss with
-- an X cut in it as the close (its art; the boss's middle and radius in the corner's 128 units, for the click).
-- at: where the game's red X stands in a set without one, as a share of the corner piece across and down (on the
-- mitre), measured from the sets' art. scale: the sets drawn bigger on the window than on the small map: Sun gold
-- and Moonlit silver were "tiiiiny" there (the user: "Try them bigger. Give them the same treatment as engravers on
-- the X. Make it custom to their corner"). The Engraver's is already drawn at 1.6 by its own set.
local CLOSE_ART = {
    boss = { engraver = { ns.MEDIA .. "World\\WorldClose", 107.3, 21.3, 13.5 },
 },
    at = { bronze = { 0.90, 0.10 }, leather = { 0.90, 0.10 }, other = { 0.88, 0.12 } },
    scale = {},   -- (a set drawn bigger on the window than on the small map; gold and silver were, then went out)
}
W.CLOSE_ART = CLOSE_ART   -- (the log alone wears the same close: Lab/WorldAlone.lua)
-- a quest's sign, from pictures the game has (its own cursors: what your pointer turns into over such a thing)
local SIGNS = { monster = "Interface\\CURSOR\\Attack", item = "Interface\\CURSOR\\Pickup", object = "Interface\\CURSOR\\Interact",
                other = "Interface\\CURSOR\\Speak", ready = "Interface\\GossipFrame\\ActiveQuestIcon" }
local T = Enum and Enum.UIMapType or {}

local panel, head, tools, scroll, content, padHint
local slot, win, bar, rail
local rows = {}
local S = { page = nil, search = "", book = false, filter = nil, sel = nil, looseAll = false, lines = {} }
local shownFor, dirty = nil, true
local Refresh, Refit, Fold, Options, opts, ActButtons, ClampHold

-- A controller's buttons this has a use for; every other one goes on to the game (its own binding), so the
-- menu button, the triggers and the rest are not dead while this is up. Folded, the rail uses fewer.
local PAD_OPEN = { PADDUP = true, PADDDOWN = true, PAD1 = true, PAD2 = true, PAD3 = true, PAD4 = true, PADLSHOULDER = true, PADRSHOULDER = true }
local PAD_FOLDED = { PADDUP = true, PADDDOWN = true, PAD1 = true, PAD2 = true, PAD4 = true }
local function PassOn(frame, button)
    if not frame.SetPropagateKeyboardInput or InCombatLockdown() then return end
    local c = W.Cfg()
    local mine = c.fold and not (W.Alone and W.Alone()) and PAD_FOLDED or PAD_OPEN   -- (the log alone: never folded)
    local take = mine[button]
    if (button == "PADDLEFT" or button == "PADDRIGHT") and mine == PAD_OPEN then
        local l = S.sel and S.lines and S.lines[S.sel]
        take = l and (l.acts or l.fold) and true or false   -- (a quest line folds with them: never passed on to the game too)
    end
    pcall(frame.SetPropagateKeyboardInput, frame, not take)
end

local function Cfg() return W.Cfg() end
local function Map() return BattlefieldMapFrame end
local function MapID()
    -- (the log alone: the zone you stand in, no map up. Lab/WorldAlone.lua)
    local alone = W.AloneMap and W.AloneMap()
    if alone then return alone end
    return Map() and Map().GetMapID and Map():GetMapID() or nil
end
local function PadMode() return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() or false end

local function Colour(fs, c, a) fs:SetTextColor(c[1], c[2], c[3], a or 1) end
local function LevelColour(level)
    if GetQuestDifficultyColor then
        local ok, c = pcall(GetQuestDifficultyColor, level)
        if ok and c and c.r then return { c.r, c.g, c.b } end
    end
    return GOLD
end
local function MapName(id)
    local info = id and C_Map.GetMapInfo(id)
    return info and info.name or "?"
end

-- Quest actions ---------------------------------------------------------------------------

-- (the tracked set asked once a frame, not three times a quest line: it walks the whole log each time)
local function Watched(id)
    local now = GetTime and GetTime() or 0
    if W.trackedAt ~= now then W.trackedAt, W.trackedSet = now, ns.TrackedQuests and ns.TrackedQuests() end
    local set = W.trackedSet
    if set and set[id] then return true end
    if C_QuestLog and C_QuestLog.GetQuestWatchType then
        local ok, t = pcall(C_QuestLog.GetQuestWatchType, id)
        return ok and t ~= nil
    end
    return false
end
local function ToggleTrack(id)
    W.trackedAt = nil
    if not W.IsHeld(id) then return end
    if Watched(id) then
        if C_QuestLog and C_QuestLog.RemoveQuestWatch then pcall(C_QuestLog.RemoveQuestWatch, id) end
    elseif C_QuestLog and C_QuestLog.AddQuestWatch then
        pcall(C_QuestLog.AddQuestWatch, id)
    end
    if ns.UpdateTracker then pcall(ns.UpdateTracker, true) end
    W.Bump()
end
local function Select(id)
    if C_QuestLog and C_QuestLog.SetSelectedQuest then return pcall(C_QuestLog.SetSelectedQuest, id) end
    return false
end
local function Share(id)
    if Select(id) and QuestLogPushQuest then pcall(QuestLogPushQuest) end
end
local function Abandon(id)
    if not (ns.Ask and W.IsHeld(id)) then return end
    ns.Ask({ text = "Abandon " .. W.Title(id) .. "?", ok = ABANDON_QUEST_ABBREV or "Abandon", cancel = "Keep it",
             onAccept = function()
                 if not Select(id) then return end
                 if C_QuestLog and C_QuestLog.SetAbandonQuest then C_QuestLog.SetAbandonQuest() elseif SetAbandonQuest then SetAbandonQuest() end
                 if C_QuestLog and C_QuestLog.AbandonQuest then C_QuestLog.AbandonQuest() elseif AbandonQuest then AbandonQuest() end
                 S.page = nil
             end })
end
local function Link(id)
    local link = GetQuestLink and GetQuestLink(id)
    if not link then return end
    if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() and ChatEdit_InsertLink then
        ChatEdit_InsertLink(link)
    elseif ChatFrame_OpenChat then
        ChatFrame_OpenChat(link)
    end
end
local function Find(id)
    -- (the log alone: the world map opens beside it first, then finds it there. Lab/WorldAlone.lua)
    if W.Alone and W.Alone() and W.AloneOpenMap then
        if W.AloneFind then W.AloneFind(id) else W.AloneOpenMap() end
        return
    end
    if ns.FindQuestOnMap then ns.Safe("World log find", ns.FindQuestOnMap, id) end
end
local function GoTo(map)
    local c = Cfg()
    -- (the log alone: there is no map to move; the log goes there, as a right-click on its title does)
    if W.Alone and W.Alone() then
        c.logAt = map
        if ns.WorldPanelChanged then ns.WorldPanelChanged() end
        return
    end
    -- (the log follows the map again: Cfg().logAt, set by a right-click on the log's title, lets go)
    if c and c.logAt then c.logAt = nil dirty = true end
    if map and ns.BrowseTo then ns.Safe("World log zone", ns.BrowseTo, map) end
end

-- a quest's words read on in As told's panel, held there (AsToldPanel.lua): true if it could. The user, 2026-11-22:
-- "how about an option to open the quest from the log into as:told, to continue reading the description etc", "Maybe
-- just clicking the header \"description\""
function W.ReadTold(id)
    if not (id and ns.ToldQuest and ns.ToldQuest(id) and ns.ToldPanelPick) then return false end
    -- (flipped to it, as a pick in its own list: not held open: "Clicking this holds the quest open along time in
    -- astold. Im thinking maybe just flip to it", the user)
    ns.ToldPanelPick(id, false)
    return true
end
local function QuestMenu(id)
    if not ns.QuillMenu then return end
    local items = {}
    if W.IsHeld(id) then
        items[#items + 1] = { Watched(id) and "stop tracking" or "track", function() ToggleTrack(id) end }
        if ns.ToldQuest and ns.ToldQuest(id) then items[#items + 1] = { "read in As told", function() W.ReadTold(id) end } end
        items[#items + 1] = { "show on the map", function() Find(id) end }
        items[#items + 1] = { "share", function() Share(id) end }
        items[#items + 1] = { "link in chat", function() Link(id) end }
        items[#items + 1] = { "abandon", function() Abandon(id) end }
    else
        items[#items + 1] = { "show quest giver on the map", function() Find(id) end }
        local s = W.Store()
        if s.aside[id] or s.offered[id] then
            items[#items + 1] = { "remove from loose ends", function()
                s.aside[id], s.offered[id] = nil, nil
                W.Bump()
            end }
        end
    end
    ns.QuillMenu(items)
end

-- (the column's right-click: the world map's own panel, as the bar's and the cog's; the old menu of sorts, dust and
-- sides is gone with them. The user, 2026-11-22: "Rightclick dropdown is the same in worldmap as when looking at the
-- docked frame. Idunno, even i got confused")
local function PanelMenu()
    -- (the log alone: under its own plaque; the cog is on the window, which is not up. The user, 2026-11-22: "right
    -- click settings menu opens way the fuck away from it". Lab/WorldAlone.lua)
    if Options and W.Alone and W.Alone() and head then
        Options(head)
        -- (beside the log, on the side with the room, not over its lines: "Small settings opens in the middle of it
        -- now tho", the user, 2026-11-22)
        if opts and panel then
            local l, r = panel:GetLeft(), panel:GetRight()
            local mid = l and r and (l + r) / 2 * panel:GetEffectiveScale() / UIParent:GetEffectiveScale()
            opts:ClearAllPoints()
            if mid and mid > UIParent:GetWidth() / 2 then
                opts:SetPoint("TOPRIGHT", panel, "TOPLEFT", -6, 0)
            else
                opts:SetPoint("TOPLEFT", panel, "TOPRIGHT", 6, 0)
            end
        end
        return
    end
    if Options and bar and bar.opts then Options(bar.opts) end
end

-- Lines -----------------------------------------------------------------------------------
-- A line: { text, right, sub, colour, alpha, size, head, indent, beads, bar, id, click(button), enter, leave, tip }


-- a quest's sign (what its first open task is: kill, gather, use, or go and talk) and how far along it is, 0..1
local function Sign(h)
    if h.complete then return SIGNS.ready, nil, "ready" end
    local ok, objs = pcall(function() return C_QuestLog.GetQuestObjectives(h.id) end)
    local kind, have, need = nil, 0, 0
    for _, o in ipairs(ok and objs or {}) do
        if not o.finished and not kind then kind = o.type end
        local n, m = tonumber(o.numFulfilled), tonumber(o.numRequired)
        if m and m > 0 then
            have, need = have + math.min(n or 0, m), need + m
        else
            have, need = have + (o.finished and 1 or 0), need + 1
        end
    end
    kind = SIGNS[kind or "other"] and kind or "other"
    return SIGNS[kind], need > 0 and have / need or nil, kind
end

-- A rail sign's picture, as our map draws the same quest (the user, 2026-11-21, of the rail: "our icons for \"?\"",
-- "Centering of all icons"): a ready one wears the turn-in "?" our pins wear (Pin.lua's DressQuestIcon, the
-- player's icon set); the rest the spot icons of our map, Questie's where the map uses Questie's, else the game's
-- cursors cut to the picture with the pointer's tip hidden (QuestData's GAME_OBJECTIVE_ICONS: centred, no arrow)
local RAIL_KIND = { monster = "slay", item = "loot", object = "object", other = "object" }
local RAIL_MID = { ["Interface\\Cursor\\Interact"] = { 16.5, 16.5 }, ["Interface\\CURSOR\\Interact"] = { 16.5, 16.5 },
                   ["Interface\\Cursor\\Buy"] = { 15.5, 13 } }
local function RailIcon(b, h)
    local tex = b.icon
    if tex.SetDesaturated then tex:SetDesaturated(false) end
    tex:SetVertexColor(1, 1, 1)
    tex:SetTexCoord(0, 1, 0, 1)
    local _, _, kind = Sign(h)
    if kind == "ready" then
        -- (Forever's own turn-in "?", the modern pins' QuestTurnin, alone in our ring, not the old gossip one: "I think you used the old
        -- \"?\"", the user)
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("QuestTurnin") then
            tex:SetTexCoord(0, 1, 0, 1)
            tex:SetAtlas("QuestTurnin")
        else
            tex:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
        end
        return
    end
    local spot = kind == "other" and nil or RAIL_KIND[kind]
    if spot and ns.SpotsQuestieArt and ns.SpotsQuestieArt() and Questie then
        local key = ({ slay = "ICON_TYPE_SLAY", loot = "ICON_TYPE_LOOT", object = "ICON_TYPE_OBJECT" })[spot]
        local used = key and Questie[key] and Questie.usedIcons and Questie.usedIcons[Questie[key]]
        tex:SetTexture(used or ("Interface\\AddOns\\Questie\\Icons\\" .. spot .. ".blp"))
        if ns.CursorMask then ns.CursorMask(b, tex, false) end
        return
    end
    local spec = spot and ns.GAME_OBJECTIVE_ICONS and ns.GAME_OBJECTIVE_ICONS[spot]
    local path = spec and spec.path or SIGNS.other
    local crop = spec and spec.crop or { 0, 0.875, 0, 0.875 }
    tex:SetTexture(path)
    tex:SetTexCoord(crop[1], crop[2], crop[3], crop[4])
    if ns.CursorMask then ns.CursorMask(b, tex, (not spec or spec.mask) and true or false, crop[2], crop[4]) end
    -- (the cursor's picture is not in the middle of its cut: the gear and the bag sit low right of it, the pointer's
    -- tip taking the top left. Set back by measure so the picture's own middle is the sign's: "Cogwheel off center",
    -- the user, 2026-11-23. Middles in the 32 px art, measured from the game's Interact and Buy)
    local mid = RAIL_MID[path]
    if mid then
        local w, h = tex:GetWidth() or 0, tex:GetHeight() or 0
        local cw, ch = (crop[2] - crop[1]) * 32, (crop[4] - crop[3]) * 32
        local dx = (mid[1] - crop[1] * 32 - cw / 2) / cw * w
        local dy = (mid[2] - crop[3] * 32 - ch / 2) / ch * h
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", b, "CENTER", -dx, dy)
    end
end

-- (the list's look "As before", a sign, a bar, the beads and a small line under each, was pruned by the user,
-- 2026-11-21: one look only, the game's log in ours)

-- A quest's kind behind its title, "(Group)", "(Dungeon)", "(Raid)", "(PvP)", as the game's log has always
-- written it and our quest tooltip colours it (Pin.lua: orange, a raid green, PvP red). It replaces the filter
-- "Wants a group": the user, 2026-11-21, "Quests dont want anything, they are concepts ... there is already a
-- great system for this, and that is writing (Group) behind their title."
local KIND_TAG = { [1] = "|cffff9a40(Group)|r", [81] = "|cffff9a40(Dungeon)|r", [62] = "|cff2e9a3c(Raid)|r", [41] = "|cffb8352a(PvP)|r" }
-- and a class quest "(Warrior)" in the class's colour, as the game's log files them under the class (the user,
-- 2026-11-22: "Qlog shows \"warrior\" quests. Which uknow, is good", then "Yes" to the tag)
-- a ready quest's mark at a line's right: the game's own gold "?" of a quest to hand in, in place of "(Complete)"
-- (the user, 2026-11-22: "Only room for 1 word x) What if complete moves down? or something else?", then "A, small marks")
-- (Forever's own turn-in "?", the atlas the modern pins wear; the old gossip one only where the client lacks it:
-- "I think you used the old \"?\"", the user)
W.DONE_MARK = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("QuestTurnin")) and "|A:QuestTurnin:16:16:0:-1|a"
    or "|TInterface\\GossipFrame\\ActiveQuestIcon:15:15:0:-1|t"
-- (small, in a list's line: the class's round icon, not its name, so a long name keeps its room: "Only room for 1
-- word x)", the user, 2026-11-22, then "A, small marks". The page's title keeps the word)
function W.Tag(id, small)
    local kind = W.TypeOf and KIND_TAG[W.TypeOf(id) or 0] or nil
    local cls
    if ns.QuestForClass and ns.QuestForClass(id) and UnitClass then
        local name, file = UnitClass("player")
        local c = file and RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
        local tc = small and file and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[file]
        if tc then
            cls = ("|TInterface\\TargetingFrame\\UI-Classes-Circles:14:14:0:-1:256:256:%d:%d:%d:%d|t"):format(
                tc[1] * 256, tc[2] * 256, tc[3] * 256, tc[4] * 256)
        else
            cls = name and ("|c" .. (c and c.colorStr or "ffffffff") .. "(" .. name .. ")|r") or nil
        end
    end
    if kind and cls then return cls .. " " .. kind end
    return cls or kind
end

local function QuestLine(h, right)
    local id = h.id
    local tag = W.Tag(id, true)   -- (the class as its icon in a line)
    local function Click(button)
        if button == "RightButton" then return QuestMenu(id) end
        -- (Shift-click tracks, as the game's own log does; with the chat box open it links instead. The user,
        -- 2026-11-22: "shift+leftclick should track a quest, and there should be an indicator in the log its tracked")
        if IsShiftKeyDown and IsShiftKeyDown() then
            if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then return Link(id) end
            return ToggleTrack(id)
        end
        S.page, S.sel = id, nil
    end
    local function Enter() if ns.HoverQuestGlow then pcall(ns.HoverQuestGlow, id) end end
    local function Leave() if ns.HoverQuestGlow then pcall(ns.HoverQuestGlow, nil) end end
    -- (one line: the level first in the quest's colour, then the name, how far along at the right. The user, in
    -- game, 2026-11-21: "The number 2 after the quest makes it look like i have two of that quest. Place it
    -- before, make it difficulity colored". No sign, no bar, no beads: those are on its page)
    -- (tracked: the game's own check after the name, as its quest log marks a watched quest)
    -- (the check rides after the name as `after`, kept when a long name is shortened: "tracked checkmark gone when
    -- text too long", the user, 2026-11-22)
    local name = h.name
    return { under = W.Lead() == id or nil, stroke = id, text = name, after = Watched(id) and "  |TInterface\\Buttons\\UI-CheckBox-Check:14:14:0:-1|t" or nil, tag = tag, level = h.level, levelColour = LevelColour(h.level), right = right or (h.complete and "ready" or h.progress),
             colour = h.complete and GOLD or LevelColour(h.level), id = id, indent = 6,
             click = Click, enter = Enter, leave = Leave }
end

-- (a head engraved, as the cog's legend: spaced small capitals after a brass diamond, a rule fading out after them.
-- The user, 2026-11-22, of the quest page's mock-up: "I like the blue ones")
local function Head(text, right)
    local spaced = text:upper():gsub("([%z\1-\127\194-\244][\128-\191]*)", function(ch) return ch == " " and "   " or ch .. " " end)
    return { text = spaced:gsub("%s+$", ""), right = right, head = true, plain = text:upper() }
end
-- (fold + and -: Forever's own red buttons, like the map's grow and close, 2026-11-22, "our red button is
-- different style"; a client without them keeps the classic button)
local function FoldIcon(line, open)
    line.open = open and true or false
    -- (then our own engraved ring with a + or a -, in brass: the game's red tracker buttons "so out of place now on
    -- continent side", the user, 2026-11-22. tools/world_top/fold_art.py)
    line.atlas = nil
    line.icon = open and (ns.MEDIA .. "World\\WorldFoldMinus") or (ns.MEDIA .. "World\\WorldFoldPlus")
    line.tint = BRASS
    return line
end
local function Note(text, colour) return { text = text, colour = colour or SOFT, size = 12, wrap = true, indent = 6 } end

-- The Lab's "one log" (Lab/OneLog.lua, the Quests session's switch; no build has that file, and then every piece
-- here is off and the log is as it shipped). The user, 2026-11-24, of the log, As told's panel and the tracker:
-- "Could it all feel like one? Could it really just be the questlog, in different forms, adapting?", then "A with F,
-- lets try it". The log's part: the quest you are on is marked (W.Lead), a finished objective is struck in pencil
-- with your own line under it (W.DoneAims, key "page"), a chain reads as one scroll (W.ChainLines, key "chain").
function W.One(key)
    if not ns.OneLog then return false end
    local ok, on = pcall(ns.OneLog, key)
    return ok and on and true or false
end
-- the quest you are on: As told's lead, the one its panel tells
-- (asked once a frame: every line of the list and every sign asks)
function W.Lead()
    if not ns.OneLog then return nil end
    local now = GetTime and GetTime() or 0
    if W.leadAt ~= now then
        W.leadAt, W.leadId = now, nil
        if W.One() then
            local ok, it = pcall(function() return ns.ToldLead and ns.ToldLead() end)
            W.leadId = ok and it and it.id or nil
        end
    end
    return W.leadId
end

-- A quest folded out on the continent's list opens its objectives when the pointer rests on it (W.peekWait), and
-- they stay open until the pointer leaves the log: nothing folds under the pointer, so no line jumps away from it.
-- A controller: right on the d-pad opens, left folds (a line's `fold`, no button drawn: it has no icon)
W.peekWait = 0.3
-- (open by itself: a tracked quest, or every quest with the cog's "Objectives always shown". The user, 2026-11-22,
-- "how to make them stay open?", then "try it" to: tracked stays open, the rest on a rest of the pointer, both pages)
function W.AimsOpen(id)
    if Cfg().aimsOpen == true or Watched(id) then return true end
    return (S.peek and S.peek[id]) and true or false
end
function W.Peek(l, id)
    local enter, leave = l.enter, l.leave
    l.with = id
    l.open = W.AimsOpen(id)
    l.fold = function()
        S.peek = S.peek or {}
        S.peek[id] = not S.peek[id] or nil
    end
    l.enter = function()
        if enter then enter() end
        C_Timer.After(W.peekWait, function()
            -- (a tracked one too: in a resting place of the zone page its objectives are hidden like the rest, and
            -- the pointer must open them there. "Tracked quests dont unfold", the user, 2026-11-22)
            if S.hoverWith ~= id or (S.peek and S.peek[id]) then return end
            S.peek = S.peek or {}
            S.peek[id] = true
            dirty = true
            if Refresh then Refresh() end
        end)
    end
    l.leave = function()
        if leave then leave() end
        W.PeekWatch()
    end
end
function W.PeekWatch()
    if W.peekWatching then return end
    W.peekWatching = true
    -- (a quest folds again as soon as the pointer is off it, not only off the log: "details not hiding because i am
    -- hovering untill i hover the map. It might feel off", the user, 2026-11-22. The quest line under the pointer is
    -- held where it is on screen, so lines folding above it do not move it)
    local function Check()
        if not (S.peek and next(S.peek)) then W.peekWatching = nil return end
        local inLog = scroll and scroll:IsVisible() and scroll:IsMouseOver()
        local gone = {}
        for id in pairs(S.peek) do
            if not inLog or S.hoverWith ~= id then gone[#gone + 1] = id end
        end
        if #gone == 0 then C_Timer.After(0.25, Check) return end
        if inLog and S.hoverWith then
            for _, r in ipairs(rows) do
                if r:IsShown() and r.line and r.line.id == S.hoverWith and r.y then
                    S.anchor = { page = S.page, id = S.hoverWith, off = r.y - scroll:GetVerticalScroll() }
                    break
                end
            end
        end
        for _, id in ipairs(gone) do S.peek[id] = nil end
        dirty = true
        if Refresh then Refresh() end
        if next(S.peek) then C_Timer.After(0.25, Check) else W.peekWatching = nil end
    end
    C_Timer.After(0.25, Check)
end

-- A held quest's objectives as the game's log writes them: "0/8 Blackwood Pathfinder slain" (the game's API says
-- "Blackwood Pathfinder slain: 0/8"); none with counts: the quest's one line of what to do. A ready quest: who
-- takes it in. { { text, done, ready } }
local function Aims(id, zone)
    local out = {}
    local ready = false
    for _, h in ipairs(W.Held()) do if h.id == id then ready = h.complete break end end
    local ok, objs = pcall(function() return C_QuestLog.GetQuestObjectives(id) end)
    local counted = false
    for _, o in ipairs(ok and objs or {}) do if o.text and o.text ~= "" then counted = true end end
    -- (a quest with nothing to count says what the game and As told say, "Find Iverron by the cave to the
    -- north.": the user, 2026-11-22, "Its uknow, not really a 'turn in to' situation". Only a quest whose
    -- counts are done says who takes it in)
    if ready and counted then
        local okE, ends = pcall(ns.QuestEnds, id, zone)
        local to = okE and ends and ends.to
        out[1] = { text = to and to.name and ("Turn in to " .. to.name .. (to.map and to.map ~= zone and (", " .. MapName(to.map)) or "") .. ".")
                   or "Ready to turn in.", ready = true }
        return out
    end
    if not counted then
        local told = ns.ToldQuest and ns.ToldQuest(id)
        local line = told and told.obj
        if not (line and line ~= "") then
            local okD, d = pcall(ns.QuestDetails, id)
            line = okD and d and d.text
        end
        if line and line ~= "" then out[1] = { text = line } end
        return out
    end
    for _, o in ipairs(ok and objs or {}) do
        if o.text and o.text ~= "" then
            local what, have, need = o.text:match("^(.-):%s*(%d+)%s*/%s*(%d+)%s*$")
            out[#out + 1] = { text = what and (have .. "/" .. need .. " " .. what) or o.text, done = o.finished }
        end
    end
    return out
end

-- The Lab's one log, on a quest's page: "what you were told is print, what you did is your pencil". A counted
-- quest's objectives, each on its own line with its tally, the finished ones struck in pencil (the words, not the
-- tally); all of it done: your own line in your hand (Lab/DoneLine.lua) and the way back, the game's "?" after it.
-- The user, 2026-11-24: "The ticks, then striking the objective when done. Needs less text like that even", and of
-- the "?": "does it have to be either or. \"?\" after \"bring x-ting to soand so\" Is an option maybe."
-- true when it laid them; a quest with nothing to count keeps the page's own lines (false).
function W.DoneAims(id, lines, indent)
    local ok, objs = pcall(function() return C_QuestLog.GetQuestObjectives(id) end)
    local n = 0
    for i, o in ipairs(ok and objs or {}) do
        if o.text and o.text ~= "" then
            local what, have, need = o.text:match("^(.-):%s*(%d+)%s*/%s*(%d+)%s*$")
            local text = what and (have .. "/" .. need .. " " .. what) or o.text
            if ns.QuestPageMore then text = ns.QuestPageMore("tally", text, o.finished) or text end
            n = n + 1
            lines[#lines + 1] = { text = text, colour = o.finished and DIM or TEXT, size = 12, wrap = true, indent = indent or 6,
                                  strike = o.finished and (text:match("^(.-)%s*|T") or text) or nil, stroke = id + i }
        end
    end
    if n == 0 then return false end
    local ready = false
    for _, h in ipairs(W.Held()) do if h.id == id then ready = h.complete break end end
    if not ready then return true end
    local okD, d = pcall(function() return ns.ToldDone and ns.ToldDone(id, ns.ToldQuest and ns.ToldQuest(id)) end)
    d = okD and type(d) == "table" and d or nil
    if d and d.line and d.line ~= "" then
        lines[#lines + 1] = { text = d.line, font = d.font, colour = d.colour or SOFT, size = d.font and 18 or 12, wrap = true, indent = indent or 6 }
    end
    local back = d and d.back
    if not (back and back ~= "") then
        local a = Aims(id, W.ZoneOf(id))[1]
        back = a and a.ready and a.text or nil
    end
    if back then
        lines[#lines + 1] = { text = back .. "  |A:QuestTurnin:13:13:0:0|a", colour = TEXT, size = 12, wrap = true, indent = indent or 6 }
    end
    return true
end

local function LooseLines(zone, lines)
    if not Cfg().loose then return end
    local loose = W.LooseOn(zone)
    if #loose == 0 then return end
    lines[#lines + 1] = Head("Loose ends", tostring(#loose))
    local shown = S.looseAll and #loose or math.min(3, #loose)
    for i = 1, shown do
        local e = loose[i]
        local text = W.LooseLine(e)
        if e.tooHigh then text = text .. " Your level is too low." elseif e.grey then text = text .. " Grey." end
        local id = e.id
        lines[#lines + 1] = { text = text, colour = LOOSE, alpha = e.tooHigh and 0.6 or 1, size = 12, wrap = true, indent = 6, id = id,
                              click = function(button)
                                  if button == "RightButton" then return QuestMenu(id) end
                                  S.page, S.sel = id, nil
                              end,
                              tip = "Click: its page. Shift-click: track. Right-click: its menu." }
    end
    if #loose > shown or S.looseAll and #loose > 3 then
        lines[#lines + 1] = { text = S.looseAll and "show fewer" or ("and %d more"):format(#loose - shown), colour = BRASS, size = 12, indent = 6,
                              click = function() S.looseAll = not S.looseAll end }
    end
end

local function ByZoneLines(lines, title, skip)   -- (skip: the zone on view, listed above already)
    local counts = W.Counts()
    local list = {}
    for map, c in pairs(counts) do
        if (c.held > 0 or c.loose > 0) and map ~= skip then list[#list + 1] = { map = map, c = c, name = MapName(map) } end
    end
    table.sort(list, function(a, b)
        if a.c.held ~= b.c.held then return a.c.held > b.c.held end
        return a.name < b.name
    end)
    if #list == 0 then return end
    if title then lines[#lines + 1] = Head(title) end
    for _, z in ipairs(list) do
        local map = z.map
        local right = (z.c.held > 0 and tostring(z.c.held) or "") .. (z.c.loose > 0 and ("  +" .. z.c.loose) or "")
        lines[#lines + 1] = { text = z.name, right = right, colour = TEXT, indent = 6, click = function() GoTo(map) end,
                              tip = "Click: show it on the map." }
    end
end

-- The quests the little world has no count for, so they are never lost from sight: those inside a dungeon (a
-- line a dungeon, a click and the map goes in), and those no map of ours can place (the quests themselves).
local function IsZone(map)
    local info = map and C_Map.GetMapInfo(map)
    return info and T.Zone and info.mapType == T.Zone or false
end
-- The continent's list (the setting `zones`; the user, 2026-11-21, "We need 3 options of this btw. 2 different
-- artchoices. Pencil vs painted, and something abit more standard questlog looking", then "All 3 as a setting";
-- mockups/quest-head.html). Zones first, then dungeons, no level ranges ("Skip the levelranged on this list").
--   pencil   each zone a pencilled strip round where your quests are; a dungeon is the book's "before we go"
--            drawing of it, its ink pale on the glass at the strip's end (Media/Lab/WorldBook.tga)
--   painted  the zone's painting under the glass; the book's drawing on a patch of paper
--   log      the game's quest log manner: each zone a heading with the game's + and -, opening to its quests
local function ContinentLines(lines)
    -- (painted zones, the one way: "Remove option. Painted zones, default and only", the user, 2026-11-22; pencil and
    -- the game's quest log manner pruned)
    local style = "painted"
    local zones, dgs = {}, {}
    for map, c in pairs(W.Counts()) do
        if c.held > 0 or c.loose > 0 then
            local z = { map = map, c = c, name = MapName(map) }
            if IsZone(map) then zones[#zones + 1] = z else dgs[#dgs + 1] = z end
        end
    end
    local function Order(a, b)
        if a.c.held ~= b.c.held then return a.c.held > b.c.held end
        return a.name < b.name
    end
    table.sort(zones, Order)
    table.sort(dgs, Order)
    -- (in words, never bare numbers: the user, 2026-11-21, of "2 11 +1", "What do the numbers mean". "11 quests,
    -- 2 completed", the completed in gold; loose ends have their own heading, so not here)
    -- (then taken off: the user, 2026-11-22, of "4 quests, 1 completed" on the strip, "Take this off too")
    local function Right() return nil end
    local function Go(map) return function(button) if button ~= "RightButton" then GoTo(map) end end end
    -- (the + and - alone folds; a click on the zone opens it, as everywhere else: the user, 2026-11-22, "Right
    -- click to open those is breaking with our control scheme. Let the button be the collapse")
    local function Fold(map) return function() S.open[map] = not S.open[map] or nil end end
    if not S.open then
        S.open = {}
        local here = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        here = here and W.ZoneMap(here) or here
        if here then S.open[here] = true end
    end
    -- (a zone's quests folded out: names alone, no counts at the right, the completed last marked "(Complete)" as
    -- the zone's page marks them. Rest the pointer on one and its objectives open under it: W.Peek. The user,
    -- 2026-11-22: "Sort completed to the bottom. Replace name of giver with Complete. Figure out how to unfold
    -- details without using leftclick or making an ugly or clunky button for it")
    local function Under(map)
        local list = {}
        for _, h in ipairs(W.Held()) do if h.map == map then list[#list + 1] = h end end
        table.sort(list, function(a, b)
            if (a.complete and true or false) ~= (b.complete and true or false) then return not a.complete end
            if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
            return (a.name or "") < (b.name or "")
        end)
        for _, h in ipairs(list) do
            local l = QuestLine(h, h.complete and W.DONE_MARK or "")
            l.indent = 22
            W.Peek(l, h.id)
            lines[#lines + 1] = l
            if W.AimsOpen(h.id) then
                for _, a in ipairs(Aims(h.id, map)) do
                    lines[#lines + 1] = { text = a.text, colour = a.done and DIM or SOFT, size = 11.5, wrap = true, indent = 44,
                                          click = l.click, enter = l.enter, leave = l.leave, with = h.id }
                end
            end
        end
    end
    local paint = style == "painted"
    for _, z in ipairs(zones) do
        local okG, g = pcall(W.Groups, z.map)
        local spot = okG and g and g.groups and g.groups[1]
        local x, y = spot and spot.x or 0.5, spot and spot.y or 0.5
        -- (folds out its quests under it, as the log's headings do: the user, 2026-11-22, "Maybe option to fold out
        -- the list with quests under continentview?" The + and - in the margin left of the strip)
        local map, open = z.map, S.open[z.map]
        lines[#lines + 1] = FoldIcon({ text = "", strip = { map = z.map, x = x, y = y, name = z.name, right = Right(z.c), zone = true, paint = paint, inset = 0, endRoom = 22 },
                                       click = Go(map), fold = Fold(map),
                                       tip = "Click: open the zone. The + beside it: its quests here." }, open)
        if open then Under(map) end
    end
    for _, z in ipairs(dgs) do
        lines[#lines + 1] = { text = "", book = { name = z.name, right = Right(z.c), paint = paint },
                              click = Go(z.map), tip = "Click: show it on the map." }
    end
end

local function ElsewhereLines(lines, onView, dungeons)
    local by, list, lost = {}, {}, {}
    for _, h in ipairs(W.Held()) do
        if not h.map then
            lost[#lost + 1] = h
        elseif h.map ~= onView and not IsZone(h.map) then
            if not by[h.map] then
                by[h.map] = { map = h.map, name = MapName(h.map), n = 0, ready = 0 }
                list[#list + 1] = by[h.map]
            end
            by[h.map].n = by[h.map].n + 1
            if h.complete then by[h.map].ready = by[h.map].ready + 1 end
        end
    end
    if dungeons and #list > 0 then
        table.sort(list, function(a, b) return a.name < b.name end)
        lines[#lines + 1] = Head("In dungeons")
        for _, d in ipairs(list) do
            local map = d.map
            lines[#lines + 1] = { text = d.name, right = d.n .. (d.ready > 0 and (", " .. d.ready .. " ready") or ""), colour = TEXT, indent = 6,
                                  click = function() GoTo(map) end, tip = "Click: show it on the map." }
        end
    end
    if #lost > 0 then
        lines[#lines + 1] = Head("Not on the map", tostring(#lost))
        for _, h in ipairs(lost) do lines[#lines + 1] = QuestLine(h) end
    end
end

local function HeldLines(zone)
    local lines = {}
    if not zone then
        ContinentLines(lines)   -- (no heading: "I think we all know its the log and the zones x)", 2026-11-21)
        ElsewhereLines(lines, nil, false)
        if #lines == 0 then lines[1] = Note("Your log is empty.") end
        return lines
    end
    local g = W.Groups(zone)
    do
        -- A zone reads as the game's log, in our look (the user, 2026-11-21, of the strips: "maybe the zonepage is
        -- too hard to read. Usually quests are sorted by zone then level. And this is the amount of info one is use
        -- to have", the game's log beside it; then "A"). One list by level, each quest's objectives under it as
        -- the game writes them ("0/8 Blackwood Pathfinder slain"), a ready one says who takes it in. The strips
        -- stay on the continent's list.
        -- (under the places of the zone, the nearest first: the window is the zone alone, so its places fit as heads.
        -- The user, 2026-11-22: "This window is only the zone. We can probably fit subzone headers tbh. It makes more
        -- sense". A ready quest stands under the place it is handed in; in each place by level, the ready ones last)
        local places, byName = {}, {}
        local function Place(name)
            local p = byName[name]
            if not p then
                p = { name = name, quests = {} }
                byName[name] = p
                places[#places + 1] = p
            end
            return p
        end
        local seen = {}
        for _, group in ipairs(g.groups) do
            for _, h in ipairs(group.quests) do
                if not seen[h.id] then seen[h.id] = true table.insert(Place(group.name).quests, h) end
            end
        end
        for _, h in ipairs(g.ready) do
            if not seen[h.id] then
                seen[h.id] = true
                local okE, ends = pcall(ns.QuestEnds, h.id, zone)
                local to = okE and ends and ends.to
                local area = to and to.map == zone and to.x and ns.AreaNameAt and ns.AreaNameAt(zone, to.x, to.y) or nil
                table.insert(Place(area or "Somewhere here").quests, h)
            end
        end
        local qs, placeOpen = {}, false
        for _, p in ipairs(places) do
            -- (the completed ones at the bottom of their place, each by level, marked as the game's log marks them:
            -- the user, 2026-11-21, "Sort completed to the bottom, by level")
            table.sort(p.quests, function(a, b)
                if (a.complete and true or false) ~= (b.complete and true or false) then return not a.complete end
                if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
                return (a.name or "") < (b.name or "")
            end)
            qs[#qs + 1] = { head = p.name }
            for _, h in ipairs(p.quests) do qs[#qs + 1] = h end
        end
        for _, h in ipairs(qs) do
          if h.head then
            -- (a click on a place's head shows every quest's objectives there, or hides them again: "the subzone
            -- headers can have a small dash or + to show/hide details", then "Or just clicking the subzone headers to
            -- hide/show details tbh", the user, 2026-11-22. Its quests stay; tracked ones keep theirs open)
            local name = h.head
            local hd = Head(name)
            -- (open by default, as the zone page always was; the place's fold wins over tracked and over the cog's
            -- switch, which is the continent list's: "Details were always shown on zonepage ... Maybe the folding by
            -- subzone wins?", the user, 2026-11-22. Resting the pointer on one quest still opens it)
            hd.click = function(button)
                if button == "RightButton" then return end
                S.placeShut = S.placeShut or {}
                S.placeShut[name] = not S.placeShut[name] or nil
            end
            placeOpen = not (S.placeShut and S.placeShut[name])
            -- (its engraved diamond while the objectives show, a dash while they rest: "Engravers diamons can change
            -- from diamond when shown to - when hidden", the user)
            hd.dash = not placeOpen
            lines[#lines + 1] = hd
          else
            local q = QuestLine(h, h.complete and W.DONE_MARK or "")
            W.Peek(q, h.id)
            lines[#lines + 1] = q
            local function Aim(text, colour)
                lines[#lines + 1] = { text = text, colour = colour or SOFT, size = 11.5, wrap = true, indent = 28,
                                      click = q.click, enter = q.enter, leave = q.leave, tip = q.tip, with = h.id }
                q.with = h.id
            end
            -- (objectives under each quest, or the names alone: the cog's "Objectives under each quest", 2026-11-22)
            if placeOpen or (S.peek and S.peek[h.id]) then
                for _, a in ipairs(Aims(h.id, zone)) do Aim(a.text, a.done and DIM or nil) end
            end
          end
        end
        if g.count == 0 then lines[#lines + 1] = Note("No quests in " .. MapName(zone) .. ".") end
        LooseLines(zone, lines)
        ByZoneLines(lines, "Elsewhere", zone)
        ElsewhereLines(lines, zone, false)
        return lines
    end
end

local function DoneLines(zone, cont)
    local lines = {}
    if not zone then
        -- (on a continent: its zones where you turned something in, as the Held list's painted strips, how many of
        -- how many at the right; a click opens that zone's page. The user, 2026-11-22: "List of zones, or nah?")
        local rows = {}
        for map in pairs(W.Index()) do
            if (W.Continent(map) == cont or cont == nil) and IsZone(map) then
                local t = W.Tally(map)
                if t.done > 0 then rows[#rows + 1] = { map = map, t = t, name = MapName(map) } end
            end
        end
        table.sort(rows, function(a, b)
            if a.t.done ~= b.t.done then return a.t.done > b.t.done end
            return a.name < b.name
        end)
        for _, z in ipairs(rows) do
            local map = z.map
            lines[#lines + 1] = { text = "", strip = { map = map, x = 0.5, y = 0.5, name = z.name, right = ("%d of %d"):format(z.t.done, z.t.all),
                                                     zone = true, paint = true },
                                  click = function(button) if button ~= "RightButton" then GoTo(map) end end }
        end
        if #rows == 0 then lines[1] = Note("Nothing turned in on " .. (cont and MapName(cont) or "this map") .. " yet.") end
        return lines
    end
    local t = W.Tally(zone)
    -- ("Done" read like "Completed", the user, 2026-11-21: the game's own words, "turn in", throughout this page)
    -- (the count once, in the sentence: it stood in the head and the fold too, the player critic, 2026-11-23)
    lines[#lines + 1] = Head("Turned in here")
    -- (no bar under it: it said no more than the count, the user, 2026-11-22)
    if t.done > 0 and t.low then
        lines[#lines + 1] = Note(("%d of %d completed, at level %d to %d."):format(t.done, t.all, t.low, t.high))   -- ("7 of 64 completed*", the user, 2026-11-22)
    else
        lines[#lines + 1] = Note("No quests turned in here yet.")
    end
    if t.open > 0 then lines[#lines + 1] = Note(("%d more quests available."):format(t.open)) end
    -- (the two lists fold: the user's mark, 2026-11-21; the game's own + and - buttons, kept in the settings)
    local shut = Cfg().shut
    if type(shut) ~= "table" then shut = {} Cfg().shut = shut end
    local function Fold(text, right, key)
        local h = Head(text, right)
        FoldIcon(h, not shut[key])
        h.click = function(button) if button ~= "RightButton" then shut[key] = not shut[key] or nil end end
        lines[#lines + 1] = h
        return not shut[key]
    end
    -- (the quest givers' list with its counts in words read as a lot of text that did nothing: "They are not
    -- clickable, they dont really give any info", the user, 2026-11-22, then "both?" to A and B. A giver's name is
    -- clicked to find them on the map)
    local people = W.People(zone)
    local function Giver(p, ids, right)
        local first = ids[1]
        lines[#lines + 1] = { text = p.name, right = right, colour = TEXT, indent = 6,
                              -- (clicked again: their glow out, "Click giver again to not show", the user, 2026-11-22)
                              click = function(button)
                                  if button == "RightButton" or not first then return end
                                  if S.foundGiver == p.name then
                                      S.foundGiver = nil
                                      if ns.NotebookPingStop then ns.NotebookPingStop() end
                                  else
                                      S.foundGiver = p.name
                                      Find(first)
                                  end
                              end }
    end
    -- B: who still has work for you here, the most first
    local work = {}
    for _, p in ipairs(people) do if p.open > 0 then work[#work + 1] = p end end
    table.sort(work, function(a, b) if a.open ~= b.open then return a.open > b.open end return a.name < b.name end)
    if #work > 0 and Fold("Has work for you", nil, "work") then
        for _, p in ipairs(work) do Giver(p, p.openIds, p.open == 1 and "1 quest" or (p.open .. " quests")) end
    end
    -- A: what you turned in, under who gave it
    local done = W.DoneHere(zone)
    if #done > 0 and Fold("Turned in", nil, "done") then
        local seen = {}
        local function Quest(id, name)
            seen[id] = true
            lines[#lines + 1] = { text = name, colour = SOFT, alpha = 0.85, indent = 22, id = id,
                                  click = function(button) if button == "RightButton" then return end S.page, S.sel = id, nil end }
        end
        local names = {}
        for _, q in ipairs(done) do names[q.id] = q.name end
        for _, p in ipairs(people) do
            if p.done > 0 then
                Giver(p, p.doneIds)
                for _, id in ipairs(p.doneIds) do if names[id] then Quest(id, names[id]) end end
            end
        end
        for _, q in ipairs(done) do if not seen[q.id] then Quest(q.id, q.name) end end
    end
    return lines
end

local function SearchLines()
    local lines = {}
    local r = W.Search(S.search, S.book)
    lines[#lines + 1] = Head("In your log", tostring(#r.log))
    for _, h in ipairs(r.log) do lines[#lines + 1] = QuestLine(h, h.map and MapName(h.map) or nil) end
    lines[#lines + 1] = Head("As told", tostring(#r.told))
    for _, t in ipairs(r.told) do
        local id = t.id
        lines[#lines + 1] = { text = "\"" .. (t.said or "") .. "\"", colour = TEXT, size = 12, wrap = true, indent = 6,
                              sub = (t.who and (t.who .. ", ") or "") .. t.name .. (t.done and " (turned in)" or ""), id = id,
                              click = function() S.page, S.sel = id, nil end }
    end
    -- (one search box on the world map, the user, 2026-11-22: "Make it only 1". What the map's magnifier finds,
    -- trainers, services, vendors, items, zones, places: a click rings it on the map as the magnifier does)
    for _, g in ipairs(ns.MapSearchFind and ns.MapSearchFind(S.search) or {}) do
        lines[#lines + 1] = Head(g.name, tostring(#g.list))
        for _, e in ipairs(g.list) do
            lines[#lines + 1] = { text = e.label, colour = TEXT, indent = 6, icon = e.icon or 134400, alpha = 1,
                                  click = function(button)
                                      if button == "RightButton" then return end
                                      if ns.MapSearchPick then ns.Safe("World map search pick", ns.MapSearchPick, e) end
                                  end }
        end
    end
    lines[#lines + 1] = Head("All quests", tostring(r.bookCount))
    if r.bookCount > 0 and not S.book then
        lines[#lines + 1] = { text = "Quests you haven't seen. Click to show them.", colour = BRASS, size = 12, wrap = true, indent = 6,
                              click = function() S.book = true end }
    end
    for _, q in ipairs(r.book) do
        local id = q.id
        lines[#lines + 1] = { text = q.name, right = q.map and MapName(q.map) or nil, colour = q.done and DIM or LevelColour(q.level), indent = 6,
                              sub = q.done and "turned in" or nil, id = id, click = function() S.page, S.sel = id, nil end }
    end
    return lines
end

local function Action(text, fn) return { text = ">  " .. text, colour = BRASS, indent = 6, click = fn } end
-- (the page's actions as one row of buttons: the user, 2026-11-21, of the four "> track" lines, "this list looks
-- like a reading list". A controller's A on the row opens the quest's menu, which has the same four)

-- The ground ribbon ---------------------------------------------------------------------------
-- A quest's page opens with a picture of where its work is (the user, 2026-11-19, of the mock-up's painted
-- one: "What if this little ribbon-image uses our pencil mapart, instead of painted"). A band of the quest's
-- zone map round its ground, drawn as the pencilled map draws a zone (Pencil.lua's first two steps: the art
-- grey, then added to itself through the zone's gain mask, so paper goes pale and the painter's lines stay),
-- and the ground itself left in colour through the pencil's own soft blot: pencil all round, paint where the
-- work is. No ring (gold rings were turned down for As told). The zone's whole art, walked or not.
-- Cost: only the tiles and area pieces the band shows are laid, five textures each (about 30 to 60 in all),
-- once when the page opens; nothing runs after.
local RIB = { pool = {}, used = 0, src = {} }
local PENCIL = { 0.843 * 0.8, 0.748 * 0.8, 0.523 * 0.8 }   -- (the pencil's paper, a little under full tone)
local RIB_H, RIB_SPAN, RIB_COPIES = 92, 0.36, 3
local ribbon

local function RibTex(layer, sub, blend, grey, mask)
    RIB.used = RIB.used + 1
    local t = RIB.pool[RIB.used]
    if not t then
        t = ribbon.sheet:CreateTexture()
        RIB.pool[RIB.used] = t
    end
    t:SetDrawLayer(layer, sub)
    t:SetBlendMode(blend)
    if t.SetDesaturation then t:SetDesaturation(grey and 1 or 0) end
    if grey then t:SetVertexColor(PENCIL[1], PENCIL[2], PENCIL[3]) else t:SetVertexColor(1, 1, 1) end
    if t.mask ~= mask then
        if t.mask then t:RemoveMaskTexture(t.mask) end
        if mask then t:AddMaskTexture(mask) end
        t.mask = mask
    end
    return t
end

-- a zone's art as pieces to lay: its base tiles (k = 0), then each area piece's tiles (k = its place in the
-- zone's list), in art pixels; fw, fh: the file's own size (the last tile of a row or column is cut short)
local function RibSources(map)
    if RIB.src[map] then return RIB.src[map] end
    local out = {}
    local function Pow2(n)
        local p2 = 16
        while p2 < n do p2 = p2 * 2 end
        return p2
    end
    local layer, files = ns.MapArtLayer(map)
    if layer and files then
        local lw, lh = layer.layerWidth, layer.layerHeight
        local cols = math.ceil(lw / 256)
        for i, fid in ipairs(files) do
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            local pw, ph = math.min(256, lw - 256 * col), math.min(256, lh - 256 * row)
            if pw > 0 and ph > 0 then
                out[#out + 1] = { x = 256 * col, y = 256 * row, w = pw, h = ph, fw = 256, fh = 256, fid = fid, k = 0 }
            end
        end
    end
    for k, o in ipairs(ns.ZoneOverlays(map) or {}) do
        local across, down = math.ceil(o.w / 256), math.ceil(o.h / 256)
        for row = 1, down do
            local ph = row < down and 256 or (o.h - 256 * (down - 1))
            for col = 1, across do
                local fid = o.files[(row - 1) * across + col]
                if fid then
                    local pw = col < across and 256 or (o.w - 256 * (across - 1))
                    out[#out + 1] = { x = o.x + 256 * (col - 1), y = o.y + 256 * (row - 1), w = pw, h = ph,
                                      fw = col < across and 256 or Pow2(pw), fh = row < down and 256 or Pow2(ph), fid = fid, k = k }
                end
            end
        end
    end
    RIB.src[map] = out
    return out
end

-- where a held quest's work is on its zone's map: the spot of its first open task nearest the middle of
-- them all, how far the spots lie from it on the whole, and the place's name
local FindSpot
local function QuestSpot(id)
    -- (kept until the log changes: QuestData keeps one map's ground, and the map's own ground layer asks for
    -- its map ten times a second, so asking here for another map on every redraw summed both again each time)
    if RIB.spotV ~= W.version then RIB.spotV, RIB.spots = W.version, {} end
    local s = RIB.spots[id]
    if s == nil then
        s = FindSpot(id) or false
        if not s then
            -- (no ground to show: a talk-to quest, a ready one, one not in your log. The person you go to instead,
            -- or where you get it: the user, 2026-11-21, "the penciled drawing with the higlighted questground on
            -- the top of the quest details page" on every page)
            local map = W.ZoneOf(id)
            local okE, ends = pcall(ns.QuestEnds, id, map)
            local held, done = W.IsHeld(id), W.IsDone(id)
            local e = okE and ends and ((held or done) and (ends.to and ends.to.x and ends.to or ends.from) or (ends.from and ends.from.x and ends.from or ends.to))
            if not (e and e.map and e.x) then
                -- (our data has no ends: a Forever quest with QuestieDB off. The game's own marker for a held
                -- quest on its map, else the giver Waymark learned as you played. The user, 2026-11-22, of
                -- Nature's Call: "No area data ... I have completed it before even")
                e = held and W.GameMarker(id, map) or W.LearnedEnd(id, held or done)
            end
            if e and e.map and e.x and ns.MapArtLayer and ns.MapArtSize and ns.ZoneOverlays then
                s = { map = e.map, x = e.x, y = e.y, spread = e.spread or 0.02, npc = true,
                      name = ns.AreaNameAt and ns.AreaNameAt(e.map, e.x, e.y) or nil }
            end
        end
        RIB.spots[id] = s
    end
    return s or nil
end
function FindSpot(id)
    local map = W.ZoneOf(id)
    if not (map and ns.MapArtLayer and ns.MapArtSize and ns.ZoneOverlays) then return nil end
    local ok, ground = pcall(ns.QuestGround, map)
    for _, q in ipairs(ok and ground or {}) do
        if q.id == id then
            local pts = q.parts and q.parts[1] and q.parts[1].points
            if not (pts and pts[1]) then return nil end
            local mx, my = 0, 0
            for _, pt in ipairs(pts) do mx, my = mx + pt[1], my + pt[2] end
            mx, my = mx / #pts, my / #pts
            local best, bd
            for _, pt in ipairs(pts) do
                local d = (pt[1] - mx) ^ 2 + (pt[2] - my) ^ 2
                if not bd or d < bd then best, bd = pt, d end
            end
            local far = 0
            for _, pt in ipairs(pts) do far = far + math.sqrt((pt[1] - best[1]) ^ 2 + (pt[2] - best[2]) ^ 2) end
            return { map = map, x = best[1], y = best[2], spread = math.min(0.09, far / #pts),
                     name = ns.AreaNameAt and ns.AreaNameAt(map, best[1], best[2]) or nil }
        end
    end
    return nil
end

local function LayRibbon(rb, row, width)
    if not ribbon then
        ribbon = CreateFrame("Frame", nil, content)
        if ribbon.SetClipsChildren then ribbon:SetClipsChildren(true) end
        local back = ribbon:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints()
        back:SetColorTexture(PENCIL[1], PENCIL[2], PENCIL[3], 1)
        ribbon.sheet = CreateFrame("Frame", nil, ribbon)
        ribbon.gain = ribbon.sheet:CreateMaskTexture()
        ribbon.gain:SetAllPoints(ribbon.sheet)
        ribbon.blot = ribbon.sheet:CreateMaskTexture()
        ribbon.blot:SetTexture(ns.MEDIA .. "Pencil\\Blot.blp", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        ribbon.over = CreateFrame("Frame", nil, ribbon)
        ribbon.over:SetAllPoints()
        for i, e in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
            local line = ribbon.over:CreateTexture(nil, "ARTWORK")
            line:SetColorTexture(BRASS[1], BRASS[2], BRASS[3], 0.6)
            line:SetPoint(e[1])
            line:SetPoint(e[2])
            if i <= 2 then line:SetHeight(1) else line:SetWidth(1) end
        end
        ribbon.name = ribbon.over:CreateFontString(nil, "OVERLAY")
        ribbon.name:SetFont(FRIZ, 11, "OUTLINE")
        ribbon.name:SetPoint("BOTTOMLEFT", 5, 4)
        ribbon.name:SetTextColor(0.96, 0.92, 0.80)
    end
    ribbon:ClearAllPoints()
    ribbon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -3)
    ribbon:SetSize(width, RIB_H)
    ribbon:SetFrameLevel(row:GetFrameLevel() + 1)
    ribbon.over:SetFrameLevel(row:GetFrameLevel() + 4)
    ribbon:Show()
    local key = rb.map .. ":" .. rb.x .. ":" .. rb.y .. ":" .. width
    if RIB.key == key then return end
    RIB.key = key
    local aw, ah = ns.MapArtSize(rb.map)
    if not (aw and ah and aw > 0) then
        RIB.key = nil
        ribbon:Hide()
        return
    end
    -- the whole map at the band's scale, slid so the ground is in the middle, kept on the sheet
    local s = width / (RIB_SPAN * aw)
    local sw, sh = aw * s, ah * s
    local left = math.max(0, math.min(sw - width, rb.x * sw - width / 2))
    local top = math.max(0, math.min(sh - RIB_H, rb.y * sh - RIB_H / 2))
    local sheet = ribbon.sheet
    sheet:ClearAllPoints()
    sheet:SetPoint("TOPLEFT", ribbon, "TOPLEFT", -left, top)
    sheet:SetSize(sw, sh)
    -- (the pencil has a gain mask only for its own zones, Data\PencilZones.lua: elsewhere the band is the
    -- art in grey with the ground in colour, no added copies, which a missing mask might blank or blow white)
    local gain = ns.PencilZones and ns.PencilZones[rb.map] and true or false
    if gain and ribbon.gainFor ~= rb.map then
        ribbon.gain:SetTexture(ns.MEDIA .. "Pencil\\" .. rb.map .. ".tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        ribbon.gainFor = rb.map
    end
    local reach = math.max(30, math.min(RIB_H * 0.62, rb.spread * sw + 22))
    ribbon.blot:ClearAllPoints()
    ribbon.blot:SetPoint("CENTER", sheet, "TOPLEFT", rb.x * sw, -rb.y * sh)
    ribbon.blot:SetSize(reach * 2, reach * 2)
    RIB.used = 0
    local order, laid = {}, 0   -- (a piece's place among the pieces this band shows)
    local x0, x1, y0, y1 = left / s, (left + width) / s, top / s, (top + RIB_H) / s
    for _, src in ipairs(RibSources(rb.map)) do
        if src.x < x1 and src.x + src.w > x0 and src.y < y1 and src.y + src.h > y0 then
            local function Lay(tex)
                if tex.SetSnapToPixelGrid then
                    tex:SetSnapToPixelGrid(false)
                    tex:SetTexelSnappingBias(0)
                end
                local file = ns.MapArtFile and ns.MapArtFile(src.fid) or src.fid
                if tex.artFile ~= file then
                    tex:SetTexture(file, nil, nil, "LINEAR")
                    tex.artFile = file
                end
                tex:SetTexCoord(0, src.w / src.fw, 0, src.h / src.fh)
                tex:ClearAllPoints()
                tex:SetPoint("TOPLEFT", sheet, "TOPLEFT", src.x * s, -src.y * s)
                tex:SetSize(src.w * s, src.h * s)
                tex:Show()
            end
            -- (a piece's added copies lie right over its own grey and under the next piece's grey: pieces
            -- overlap, and laid on one level the overlaps are added twice and the lines go pale, Pencil.lua.
            -- Two sublevels a piece, through BORDER and then ARTWORK: sixteen pieces a band; past that the
            -- last slot is shared)
            local layer, sub, top = "BACKGROUND", -8, -8
            if src.k > 0 then
                if not order[src.k] then
                    laid = laid + 1
                    order[src.k] = laid
                end
                local slot = math.min(order[src.k], 16) - 1
                layer, sub = slot < 8 and "BORDER" or "ARTWORK", -8 + 2 * (slot % 8)
                top = math.min(7, -7 + math.min(order[src.k], 14))
            end
            Lay(RibTex(layer, sub, "BLEND", true))
            if gain then
                for _ = 1, RIB_COPIES do Lay(RibTex(layer, sub + 1, "ADD", true, ribbon.gain)) end
            end
            Lay(RibTex("OVERLAY", top, "BLEND", false, ribbon.blot))
        end
    end
    for i = RIB.used + 1, #RIB.pool do RIB.pool[i]:Hide() end
    ribbon.name:SetText("")   -- (no place name on it: the map's own lettering says it; "Remove subzone name", the user, 2026-11-22)
end

-- Pencilled places: the list's place headings (the setting `list`, "places"; mockups\quest-panel.html, A. The user,
-- 2026-11-21: "Lets try A, but scrap the progessbar. te 7/10 is enough"). Each place is a slim strip of that place
-- from the zone's pencilled art, darkened for the glass and feathered all round, its name lettered on it and how
-- far it was on foot (taken off: "Remove the 'half a min'"). Drawn as the page's band is (the art in grey, then added to itself through the
-- zone's gain mask) but with no colour blot and darker. Cost: about three textures a piece of art the strip
-- crosses (some 15 to 30 a strip), laid once when the log changes; a strip a place the list shows.
local STRIP = { h = 46, span = 0.34, tone = 0.52, copies = 2, bands = {}, books = {}, cellOf = {},
    -- the book's drawings in Media/Lab/WorldBook.tga (tools/world_top/book_atlas.py): 5 x 5 cells of 204 x 96 in 1024 x 512
    cells = { deadmines = 0, wailing = 1, ragefire = 2, thanes = 3, ruins = 4, shadowfang = 5, blackfathom = 6, stockade = 7, excavation = 8,
              gnomeregan = 9, dalaran = 10, kraul = 11, monastery = 12, downs = 13, uldaman = 14, zulfarrak = 15, maraudon = 16, temple = 17,
              depths = 18, spire = 19, diremaul = 20, scholomance = 21, stratholme = 22 } }   -- (one table: the file is at Lua's 200 locals)
local function StripTex(band, layer, sub, blend, gain)
    band.used = band.used + 1
    local t = band.pool[band.used]
    if not t then
        t = band.sheet:CreateTexture()
        t:AddMaskTexture(band.fade)
        band.pool[band.used] = t
    end
    t:SetDrawLayer(layer, sub)
    t:SetBlendMode(blend)
    if band.paint then
        -- (the painted continent list: the zone's own painting, a little greyed and dimmed for the glass)
        if t.SetDesaturation then t:SetDesaturation(0.25) end
        t:SetVertexColor(0.5, 0.5, 0.5)
    else
        if t.SetDesaturation then t:SetDesaturation(1) end
        t:SetVertexColor(PENCIL[1] * STRIP.tone, PENCIL[2] * STRIP.tone, PENCIL[3] * STRIP.tone)
    end
    if t.gmask ~= gain then
        if t.gmask then t:RemoveMaskTexture(t.gmask) end
        if gain then t:AddMaskTexture(gain) end
        t.gmask = gain
    end
    return t
end

local function LayStrip(i, st, row, width)
    local band = STRIP.bands[i]
    if not band then
        band = CreateFrame("Frame", nil, content)
        if band.SetClipsChildren then band:SetClipsChildren(true) end
        band.sheet = CreateFrame("Frame", nil, band)
        band.fade = band.sheet:CreateMaskTexture()
        band.fade:SetTexture(ns.MEDIA .. "World\\WorldHeadFade", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        band.fade:SetAllPoints(band)
        band.gain = band.sheet:CreateMaskTexture()
        band.gain:SetAllPoints(band.sheet)
        -- (hover: the strip itself lifts, in its own feathered shape; a straight box was "too straight", 2026-11-21)
        band.glow = band.sheet:CreateTexture(nil, "OVERLAY", nil, 7)
        band.glow:SetAllPoints(band)
        band.glow:SetColorTexture(1, 0.86, 0.62, 0.11)
        band.glow:SetBlendMode("ADD")
        band.glow:AddMaskTexture(band.fade)
        band.glow:Hide()
        band.over = CreateFrame("Frame", nil, band)
        band.over:SetAllPoints()
        -- (lettered as the map's own: pale gold with an umber edge, Lab\Minutes.lua's manner)
        band.name = band.over:CreateFontString(nil, "OVERLAY")
        band.name:SetFont(FRIZ, 9.5, "")
        band.name:SetPoint("BOTTOMLEFT", 8, 5)
        band.name:SetTextColor(0.96, 0.89, 0.72)
        band.name:SetShadowColor(0.20, 0.13, 0.07, 1)
        band.name:SetShadowOffset(1, -1)
        band.right = band.over:CreateFontString(nil, "OVERLAY")
        band.right:SetPoint("RIGHT", -10, 0)
        band.right:SetShadowColor(0, 0, 0, 1)
        band.right:SetShadowOffset(1, -1)
        band.pool, band.used = {}, 0
        STRIP.bands[i] = band
    end
    band:ClearAllPoints()
    local inset = st.inset or 0
    width = width - inset - (st.endRoom or 0)   -- (room at the right for its fold mark)
    band:SetPoint("TOPLEFT", row, "TOPLEFT", inset, -6)
    band:SetSize(width, STRIP.h)
    band:SetFrameLevel(row:GetFrameLevel() + 1)
    band.over:SetFrameLevel(row:GetFrameLevel() + 4)
    band.name:ClearAllPoints()
    if st.zone then
        -- (a zone on the continent's list: its name large; painted, in the game's zone-title face and gold)
        if st.paint then
            band.name:SetFont(ns.FONT_MORPHEUS or "Fonts\\MORPHEUS.ttf", 16, "")
            band.name:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
            band.name:SetShadowColor(0, 0, 0, 1)
        else
            band.name:SetFont(FRIZ, 14, "")
            band.name:SetTextColor(0.96, 0.89, 0.72)
            band.name:SetShadowColor(0.20, 0.13, 0.07, 1)
        end
        band.name:SetPoint("LEFT", 12, 1)
        band.name:SetText(st.name or "")
    else
        band.name:SetFont(FRIZ, 9.5, "")
        band.name:SetTextColor(0.96, 0.89, 0.72)
        band.name:SetShadowColor(0.20, 0.13, 0.07, 1)
        band.name:SetPoint("BOTTOMLEFT", 8, 5)
        band.name:SetText((st.name or ""):upper())
    end
    band.right:SetFont(FRIZ, 12, "")
    band.right:SetTextColor(0.96, 0.89, 0.72)
    band.right:SetText(st.right or "")
    band:Show()
    band.paint = st.paint and true or nil
    local key = st.map .. ":" .. st.x .. ":" .. st.y .. ":" .. width .. (st.paint and ":p" or "")
    if band.key == key then return end
    band.key = key
    local aw, ah   -- (split: `local a, b = x and f()` keeps one answer, the notes' pitfall five)
    if ns.MapArtSize then aw, ah = ns.MapArtSize(st.map) end
    if not (aw and ah and aw > 0) then
        band.key = nil
        band:Hide()
        return
    end
    local s = width / (STRIP.span * aw)
    local sw, sh = aw * s, ah * s
    local left = math.max(0, math.min(sw - width, st.x * sw - width / 2))
    local top = math.max(0, math.min(sh - STRIP.h, st.y * sh - STRIP.h / 2))
    local sheet = band.sheet
    sheet:ClearAllPoints()
    sheet:SetPoint("TOPLEFT", band, "TOPLEFT", -left, top)
    sheet:SetSize(sw, sh)
    local gain = ns.PencilZones and ns.PencilZones[st.map] and true or false
    if gain and band.gainFor ~= st.map then
        band.gain:SetTexture(ns.MEDIA .. "Pencil\\" .. st.map .. ".tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        band.gainFor = st.map
    end
    band.used = 0
    local order, laid = {}, 0
    local x0, x1, y0, y1 = left / s, (left + width) / s, top / s, (top + STRIP.h) / s
    for _, src in ipairs(RibSources(st.map)) do
        if src.x < x1 and src.x + src.w > x0 and src.y < y1 and src.y + src.h > y0 then
            local function Lay(tex)
                if tex.SetSnapToPixelGrid then
                    tex:SetSnapToPixelGrid(false)
                    tex:SetTexelSnappingBias(0)
                end
                local file = ns.MapArtFile and ns.MapArtFile(src.fid) or src.fid
                if tex.artFile ~= file then
                    tex:SetTexture(file, nil, nil, "LINEAR")
                    tex.artFile = file
                end
                tex:SetTexCoord(0, src.w / src.fw, 0, src.h / src.fh)
                tex:ClearAllPoints()
                tex:SetPoint("TOPLEFT", sheet, "TOPLEFT", src.x * s, -src.y * s)
                tex:SetSize(src.w * s, src.h * s)
                tex:Show()
            end
            -- (the same sublevels as the page's band: a piece's copies over its own grey, under the next piece's)
            local layer, sub = "BACKGROUND", -8
            if src.k > 0 then
                if not order[src.k] then
                    laid = laid + 1
                    order[src.k] = laid
                end
                local slot = math.min(order[src.k], 16) - 1
                layer, sub = slot < 8 and "BORDER" or "ARTWORK", -8 + 2 * (slot % 8)
            end
            Lay(StripTex(band, layer, sub, "BLEND", nil))
            if gain and not band.paint then
                for _ = 1, STRIP.copies do Lay(StripTex(band, layer, sub + 1, "ADD", band.gain)) end
            end
        end
    end
    for j = band.used + 1, #band.pool do band.pool[j]:Hide() end
end

-- A dungeon on the continent's list: its name, "(Dungeon)" as the game writes it, and the book's drawing of it
-- small at the strip's end (pale ink on the glass; painted: umber ink on a patch of paper). A dungeon the book has
-- not drawn has no picture.
local function BookCell(name)
    local function Norm(s) return (s or ""):lower():gsub("^the ", ""):gsub("[^%a]", "") end
    local n = Norm(name)
    if STRIP.cellOf[n] ~= nil then return STRIP.cellOf[n] or nil end
    local found = false
    local function Try(p)
        if type(p) == "table" and p.id and STRIP.cells[p.id] and (Norm(p.title) == n or Norm(p.tab) == n) then found = STRIP.cells[p.id] end
    end
    for _, p in pairs(ns.FoundNotes or {}) do
        if type(p) == "table" then
            Try(p)
            for _, q in ipairs(p) do Try(q) end
        end
    end
    STRIP.cellOf[n] = found
    return found or nil
end

local function LayBook(i, bk, row, width)
    local f = STRIP.books[i]
    if not f then
        f = CreateFrame("Frame", nil, content)
        f.paper = f:CreateTexture(nil, "BACKGROUND")
        f.paper:SetColorTexture(0.55, 0.43, 0.27, 0.85)
        f.fade = f:CreateMaskTexture()
        f.fade:SetTexture(ns.MEDIA .. "World\\WorldHeadFade", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        f.fade:SetAllPoints(f.paper)
        f.paper:AddMaskTexture(f.fade)
        f.ink = f:CreateTexture(nil, "ARTWORK")
        f.ink:SetTexture(ns.MEDIA .. "World\\WorldBook")
        f.glowFade = f:CreateMaskTexture()
        f.glowFade:SetTexture(ns.MEDIA .. "World\\WorldHeadFade", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        f.glowFade:SetAllPoints(f)
        f.glow = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        f.glow:SetAllPoints(f)
        f.glow:SetColorTexture(1, 0.86, 0.62, 0.11)
        f.glow:SetBlendMode("ADD")
        f.glow:AddMaskTexture(f.glowFade)
        f.glow:Hide()
        f.name = f:CreateFontString(nil, "OVERLAY")
        f.name:SetShadowOffset(1, -1)
        f.tag = f:CreateFontString(nil, "OVERLAY")
        f.tag:SetFont(FRIZ, 10.5, "")
        f.tag:SetShadowColor(0, 0, 0, 1)
        f.tag:SetShadowOffset(1, -1)
        f.right = f:CreateFontString(nil, "OVERLAY")
        f.right:SetFont(FRIZ, 12, "")
        f.right:SetTextColor(0.96, 0.89, 0.72)
        f.right:SetShadowColor(0, 0, 0, 1)
        f.right:SetShadowOffset(1, -1)
        STRIP.books[i] = f
    end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -6)
    f:SetSize(width, STRIP.h)
    f:SetFrameLevel(row:GetFrameLevel() + 1)
    local vh = STRIP.h - 4
    local vw = math.floor(vh * 204 / 96 + 0.5)
    local cell = BookCell(bk.name)
    f.ink:ClearAllPoints()
    f.ink:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    f.ink:SetSize(vw, vh)
    f.paper:ClearAllPoints()
    f.paper:SetPoint("TOPLEFT", f.ink, "TOPLEFT", -8, 2)
    f.paper:SetPoint("BOTTOMRIGHT", f.ink, "BOTTOMRIGHT", 6, -2)
    if cell then
        local cx, cy = cell % 5, math.floor(cell / 5)
        f.ink:SetTexCoord(cx * 204 / 1024, (cx + 1) * 204 / 1024, cy * 96 / 512, (cy + 1) * 96 / 512)
        if bk.paint then f.ink:SetVertexColor(0.20, 0.13, 0.07, 0.95) else f.ink:SetVertexColor(0.96, 0.89, 0.72, 0.85) end
    end
    f.ink:SetShown(cell and true or false)
    f.paper:SetShown(cell and bk.paint and true or false)
    f.name:ClearAllPoints()
    f.tag:ClearAllPoints()
    if bk.paint then
        f.name:SetFont(ns.FONT_MORPHEUS or "Fonts\\MORPHEUS.ttf", 16, "")
        f.name:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        f.name:SetShadowColor(0, 0, 0, 1)
        f.name:SetPoint("TOPLEFT", 12, -8)
        f.tag:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -1)   -- (under the name: the gold face is wide)
    else
        f.name:SetFont(FRIZ, 14, "")
        f.name:SetTextColor(0.96, 0.89, 0.72)
        f.name:SetShadowColor(0.20, 0.13, 0.07, 1)
        f.name:SetPoint("LEFT", 12, 1)
        f.tag:SetPoint("LEFT", f.name, "RIGHT", 6, 0)
    end
    f.name:SetText(bk.name or "")
    f.tag:SetText("|cffff9a40(Dungeon)|r")
    f.right:ClearAllPoints()
    f.right:SetPoint("RIGHT", cell and f.ink or f, cell and "LEFT" or "RIGHT", cell and -8 or -10, 0)
    f.right:SetText(bk.right or "")
    f:Show()
end

local function PageLines(id)
    local lines = {}
    local held = W.IsHeld(id)
    -- (no "Back" line: the Held tab over it goes back to the list, as do B on a controller and the place's name in the
    -- bar; "Dont think we need this \"back\"", the user, 2026-11-22)
    local spot = QuestSpot(id)
    -- (a right-click on the picture: back to the list, out a level as a right-click is on the map. No light on it.
    -- The user, 2026-11-22: "What about a rightclick on the art to go \"Back\" to list?")
    if spot then
        lines[#lines + 1] = { text = "", ribbon = spot, quiet = true,
                              click = function(button) if button == "RightButton" then S.page, S.sel, S.anchor = nil, nil, nil end end }
    end
    -- The page in the game's log's order (the user, 2026-11-21, marks on the page: "Restructure the info shown on
    -- the quest details"): the level before the title in its colour, as the list writes it; who gave it; what to
    -- do; the words; the rewards; the chain last, as a list (no "Step 1 of 5", no beads, no "here", no days).
    local level = ns.QuestLevelOf(id)
    local tag = W.Tag(id)
    local first = #lines + 1   -- (from the title down: the page's own text size, W.PageZoom)
    lines[#lines + 1] = { text = W.Title(id), tag = tag, colour = GOLD, size = 16, wrap = true, level = level, levelColour = LevelColour(level), bracket = true }
    local who, map = W.Giver(id)
    if who then lines[#lines + 1] = Note("From " .. who .. (map and (", " .. MapName(map)) or "") .. ".") end
    if held then
        lines[#lines + 1] = Head("Objectives")
        -- (the Lab's one log: finished ones struck, then your own line; W.DoneAims. No build has it.)
        if not (W.One("page") and W.DoneAims(id, lines)) then
            for _, a in ipairs(Aims(id, W.ZoneOf(id))) do
                -- (the Lab, Lab/QuestPage.lua: a count as tally strokes. No build has it; the line is the game's then.)
                local text = ns.QuestPageMore and ns.QuestPageMore("tally", a.text, a.done) or a.text
                lines[#lines + 1] = { text = text, colour = a.done and DIM or TEXT, size = 12, wrap = true, indent = 6 }
            end
        end
    else
        lines[#lines + 1] = Head("Not in your log")
        for _, why in ipairs(W.WhyNot(id)) do lines[#lines + 1] = Note(why, TEXT) end
        local ok, pre = pcall(ns.QuestPreview, id)
        if ok and pre and pre.text and pre.text ~= "" then
            lines[#lines + 1] = Head("Objectives")
            lines[#lines + 1] = Note(pre.text, TEXT)
        end
    end
    local told = ns.ToldQuest and ns.ToldQuest(id)
    -- (the Lab: a quest you have turned in keeps its words too; and under them what was said before it was done
    -- and at the turn-in, where that was caught. Lab/QuestPage.lua; no build has it.)
    local kept = not held and ns.QuestPageMore and ns.QuestPageMore("kept", id)
    local words = (held or kept) and (told and told.text or (ns.QuestWords and ns.QuestWords(id))) or nil
    if words and words ~= "" then
        -- (told: the head opens the quest in As told's panel, "read in As told" at its end says so)
        local h = Head("Description", told and "read in As told" or nil)
        if told then h.click = function() W.ReadTold(id) end end
        lines[#lines + 1] = h
        lines[#lines + 1] = { text = words:gsub("%$[Bb]", "\n"), colour = TEXT, size = 12, wrap = true, indent = 6 }
    end
    if ns.QuestPageMore then pcall(ns.QuestPageMore, "tenses", id, held, lines, Head, TEXT) end
    local okR, rew = pcall(ns.QuestRewards, id)
    local xp = ns.QuestXP and ns.QuestXP(id) or 0
    if (okR and rew) or xp > 0 then
        lines[#lines + 1] = Head("Rewards")
        if xp > 0 then lines[#lines + 1] = Note(xp .. " experience", TEXT) end
        if okR and rew then
            if rew.copper and rew.copper > 0 and GetCoinTextureString then lines[#lines + 1] = Note(GetCoinTextureString(rew.copper), TEXT) end
            -- (the game's order: the choice first, then what comes with it; tiles, ITEMS.Lay)
            local choice, fixed = rew.choice or {}, rew.fixed or {}
            if #choice > 0 then
                local l = Note(#choice > 1 and "Choose one:" or "You get:", TEXT)
                l.items = choice
                lines[#lines + 1] = l
            end
            if #fixed > 0 then
                local l = Note(#choice > 0 and "You also get:" or "", TEXT)
                l.items = fixed
                lines[#lines + 1] = l
            end
        end
    end
    local b = W.Beads(id)
    if b and b.steps then
        -- (no "2 of 3": the list under it says it, the user, 2026-11-22, "Redundant")
        -- (the Lab's one log: the head opens the chain as one scroll, "the story so far" at its end says so)
        local hc = Head("The chain", W.One("chain") and "the story so far" or nil)
        if hc.right then hc.click = function(button) if button ~= "RightButton" then W.ChainOpen(id) end end end
        lines[#lines + 1] = hc
        for i, st in ipairs(b.steps) do
            local sid = st.id
            lines[#lines + 1] = { text = i .. ".  " .. st.name, right = st.done and "turned in" or nil,
                                  colour = st.now and GOLD or st.done and DIM or SOFT, size = 12, indent = 6, id = sid,
                                  click = sid ~= id and function() W.ChainGo(sid) end or nil }
        end
    end
    if held then
        lines[#lines + 1] = { text = "", foot = true, acts = {
            { Watched(id) and "Untrack" or "Track", function() ToggleTrack(id) end },
            { "Find", function() Find(id) end },   -- (no tooltip: one click shows what it does, "Remove \"find\"s tooltip", the user)
            { "Share", function() Share(id) end },
            { "Abandon", function() Abandon(id) end, true },
        }, click = function() QuestMenu(id) end }
    else
        -- (a quest you have done: no "Find on map", it only lights the giver: "Dont need it", the user, 2026-11-22)
        if not W.IsDone(id) then
            lines[#lines + 1] = { text = "", foot = true, acts = { { "Find on map", function() Find(id) end } }, click = function() Find(id) end }
        end
    end
    for i = first, #lines do lines[i].zoom = true end
    return lines
end

-- The chain as one scroll (the Lab's one log, key "chain"; the user, 2026-11-24, of the long unfold in As told's
-- panel: "Or in the questlog, gathered as a chain in a scrolling window?"). A second view of a quest's page, not in
-- its place: every step up to where you are, as it was told, your own remark, what was said when you turned it in;
-- the step in your log in gold with what it asks; what lies ahead as its shape only (W.BeadsLine: no names). It opens
-- with the step asked for in view (S.anchor): yours, or an earlier one. A click on a step: its ordinary page.
function W.ChainLines(id)
    local b = W.Beads(id)
    if not (b and b.steps) then return nil end
    local lines = {}
    local level = ns.QuestLevelOf(id)
    lines[#lines + 1] = { text = W.Title(id), colour = GOLD, size = 16, wrap = true, level = level, levelColour = LevelColour(level), bracket = true }
    lines[#lines + 1] = Head("The chain")
    local last = b.index or 1
    for i, st in ipairs(b.steps) do if st.done or st.inLog then last = math.max(last, i) end end
    local seen = WaymarkQuestDB and WaymarkQuestDB.seen
    local Fill = ns.QuestWordsFill or function(s) return s end
    local function Words(text, colour)
        if type(text) ~= "string" or text == "" then return end
        lines[#lines + 1] = { text = Fill(text):gsub("%$[Bb]", "\n"), colour = colour, size = 12, wrap = true, indent = 18 }
    end
    -- (asked for an earlier step, one turned in: As told's panel reads a chain back a step a page, and each page's
    -- foot opens the log at that step. The scroll comes to the step asked for; the gold stays where you are, the step
    -- in your log. With none in your log, the step asked for has it.)
    local anyHeld = false
    for i = 1, last do if W.IsHeld(b.steps[i].id) then anyHeld = true end end
    for i = 1, last do
        local st = b.steps[i]
        local sid = st.id
        local now = W.IsHeld(sid) or (sid == id and not anyHeld)
        lines[#lines + 1] = { text = st.name, icon = ns.MEDIA .. "World\\WorldDiamond", tint = now and GOLD or BRASS,
                              colour = now and GOLD or SOFT, size = 13, wrap = true, id = sid, right = st.done and "turned in" or nil,
                              click = function(button)
                                  if button == "RightButton" then return end
                                  S.chain = nil
                                  -- (this quest's own step: its page from the top; another: as a page's chain goes)
                                  if sid == S.page then
                                      S.anchor = nil
                                      scroll:SetVerticalScroll(0)
                                  else
                                      W.ChainGo(sid)
                                  end
                              end }
        local told = ns.ToldQuest and ns.ToldQuest(sid)
        Words(told and told.text or (ns.QuestWords and ns.QuestWords(sid)), (now or sid == id) and TEXT or SOFT)
        if W.IsHeld(sid) then
            if not (W.One("page") and W.DoneAims(sid, lines, 18)) then
                for _, a in ipairs(Aims(sid, W.ZoneOf(sid))) do
                    lines[#lines + 1] = { text = a.text, colour = a.done and DIM or TEXT, size = 12, wrap = true, indent = 18 }
                end
            end
        end
        -- (your character's own remark on it, in your hand: Lab/Remarks.lua)
        local okR, remark = pcall(function() return ns.ToldRemark and ns.ToldRemark(sid) end)
        if okR and type(remark) == "string" and remark ~= "" then
            lines[#lines + 1] = { text = remark, font = ns.MEDIA .. "Fonts\\ReenieBeanie.ttf", colour = { 0.80, 0.80, 0.78 }, size = 18, wrap = true, indent = 18 }
        end
        if st.done then
            local w = seen and seen.whole and seen.whole[sid]
            Words((told and told.last) or (w and w.done), SOFT)
        end
        lines[#lines + 1] = { text = "", size = 5 }
    end
    if b.n > last then
        local left = b.n - last
        lines[#lines + 1] = Note(last == b.index and W.BeadsLine(b) or (left == 1 and "One more step." or (left .. " more steps.")), DIM)
    end
    for _, l in ipairs(lines) do l.zoom = true end
    return lines
end
-- the scroll on this quest, from its page's "The chain" (a row's click: the log draws again by itself)
function W.ChainOpen(id)
    if not (id and W.One("chain") and W.Beads(id)) then return false end
    S.page, S.sel, S.chain = id, nil, id
    S.anchor = { page = id, id = id, off = 56 }
    return true
end

-- A pencil stroke on a line (Media/Lab/Strike.tga, the Quests session's art: four strokes, 16 px each, in a 256 by
-- 64 sheet, white on clear): through a finished objective's words (l.strike, the words to strike; its tally after
-- them stays clear), or under the name of the quest you are on (l.under; `measure` = what to underline). l.stroke
-- picks the stroke, so one line keeps its own. Only the Lab's one log sets either.
function W.LayPencil(r, l, x, size, measure)
    if not (l.strike or l.under) then
        if r.pencil then r.pencil:Hide() end
        return
    end
    if not r.pencil then
        r.pencil = r:CreateTexture(nil, "OVERLAY", nil, 2)
        r.pencil:SetTexture((ns.LAB_MEDIA or (ns.MEDIA .. "Lab\\")) .. "Strike")
    end
    local k = (tonumber(l.stroke) or 0) % 4
    r.pencil:SetTexCoord(0, 1, k / 4, (k + 1) / 4)
    local words = type(l.strike) == "string" and l.strike or measure
    local w
    if words then
        local full = r.left:GetText()
        r.left:SetText(words)
        w = r.left:GetStringWidth()
        r.left:SetText(full or "")
    else
        w = r.left:GetStringWidth()
    end
    w = math.max(8, math.min(w or 0, r.left:GetWidth() or 0))
    -- (through the letters' middle, or just under them; the text's top is 2 down)
    local mid = l.under and (2 + size * 1.10) or (2 + size * 0.58)
    r.pencil:ClearAllPoints()
    r.pencil:SetPoint("TOPLEFT", r, "TOPLEFT", x - 3, -(mid - 8))
    r.pencil:SetSize(w + 6, 16)
    r.pencil:SetVertexColor(0.80, 0.80, 0.78, l.under and 0.55 or 0.9)
    r.pencil:Show()
end

-- The quest page's text size, from its title down (the cog's "Quest page text", 80 to 150 in hundredths; the list, the
-- picture, the reward tiles and the buttons keep theirs). The user, 2026-11-23: "How about a scaleslider for text
-- from the questitle and down?"
W.ZOOM_MIN, W.ZOOM_MAX, W.ZOOM_STEP = 80, 150, 5
function W.PageZoom()
    local v = tonumber(Cfg().pageText) or 100
    return math.max(W.ZOOM_MIN, math.min(W.ZOOM_MAX, v)) / 100
end
function W.SetPageZoom(v)
    v = math.floor((tonumber(v) or 100) / W.ZOOM_STEP + 0.5) * W.ZOOM_STEP
    v = math.max(W.ZOOM_MIN, math.min(W.ZOOM_MAX, v))
    local c = Cfg()
    if c.pageText == v then return false end
    c.pageText = v
    dirty = true
    if ns.WorldPanelChanged then ns.WorldPanelChanged() end
    return true
end

-- to a step of the chain from a page: remembers where on screen the clicked step stood (Render keeps it there)
function W.ChainGo(sid)
    for _, r in ipairs(rows) do
        if r:IsShown() and r.line and r.line.id == sid and r.y then
            S.anchor = { page = sid, id = sid, off = r.y - scroll:GetVerticalScroll() }
            break
        end
    end
    S.page, S.sel, S.chain = sid, nil, nil
end

-- Rows ------------------------------------------------------------------------------------

-- A soft band behind a line: warm light coming in from the left and fading out to the right, no box edges (the user,
-- 2026-11-22, of the flat boxes: "boxy and abit low effort looking. I like the backdrops smooth"). Three pieces:
-- a short rise, the body, a long fall. Show / Hide / SetShown as a texture's.
local function SoftBand(r, sub, c, a)
    local band = { parts = {} }
    local function Piece(from, to, a1, a2)
        local tx = r:CreateTexture(nil, "BACKGROUND", nil, sub)
        tx:SetTexture(WHITE8)
        local c1 = CreateColor and CreateColor(c[1], c[2], c[3], a1)
        local c2 = CreateColor and CreateColor(c[1], c[2], c[3], a2)
        if not (c1 and tx.SetGradient and pcall(tx.SetGradient, tx, "HORIZONTAL", c1, c2)) then tx:SetVertexColor(c[1], c[2], c[3], (a1 + a2) / 2) end
        tx.from, tx.to = from, to
        tx:Hide()
        band.parts[#band.parts + 1] = tx
    end
    Piece(0, 0.1, 0, a)
    Piece(0.1, 0.55, a, a)
    Piece(0.55, 1, a, 0)
    function band:Lay(w)
        for _, tx in ipairs(self.parts) do
            tx:ClearAllPoints()
            tx:SetPoint("TOPLEFT", r, "TOPLEFT", w * tx.from, 0)
            tx:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT", w * tx.to, 0)
        end
    end
    function band:SetShown(on) for _, tx in ipairs(self.parts) do tx:SetShown(on and true or false) end end
    function band:Show() self:SetShown(true) end
    function band:Hide() self:SetShown(false) end
    function band:IsShown() return self.parts[1]:IsShown() end
    return band
end

local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, content)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.hl = SoftBand(r, 0, { 1, 0.93, 0.78 }, 0.08)
    r.sel = SoftBand(r, 1, GOLD, 0.15)
    r.rule = r:CreateTexture(nil, "ARTWORK")
    r.rule:SetColorTexture(BRASS[1], BRASS[2], BRASS[3], 0.45)
    r.rule:SetHeight(1)
    r.left = r:CreateFontString(nil, "OVERLAY")
    r.left:SetJustifyH("LEFT")
    r.left:SetJustifyV("TOP")
    r.right = r:CreateFontString(nil, "OVERLAY")
    r.right:SetJustifyH("RIGHT")
    r.sub = r:CreateFontString(nil, "OVERLAY")
    r.sub:SetJustifyH("LEFT")
    r.barBack = r:CreateTexture(nil, "ARTWORK")
    r.barBack:SetColorTexture(1, 1, 1, 0.08)
    r.bar = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.85)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.progBack = r:CreateTexture(nil, "ARTWORK")
    r.progBack:SetColorTexture(1, 1, 1, 0.09)
    r.prog = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.prog:SetColorTexture(0.79, 0.64, 0.36, 0.9)
    r.beads = {}
    r:SetScript("OnEnter", function(self)
        local l = self.line
        if not l then return end
        if self.glow then self.glow:Show() elseif l.click and not l.quiet then self.hl:Show() end
        -- (a quest and its objectives are one thing: one hover lights them all, the user, 2026-11-22, "Two
        -- seperate hoves, same link")
        if l.with then
            for _, o in ipairs(rows) do if o:IsShown() and o.line and o.line.with == l.with then o.hl:Show() end end
            -- (moving from the title to its objectives stays one hover: the map's light and the tooltip are not
            -- put out and lit again: the user, 2026-11-22, "the lights turn down and relight on the map. this gets
            -- busy and messy")
            if S.hoverWith == l.with then return end
            S.hoverWith = l.with
        end
        if l.enter then l.enter() end
        if l.tip and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(l.tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function(self)
        self.hl:Hide()
        if self.glow and S.sel ~= self.idx then self.glow:Hide() end
        local l = self.line
        local w = l and l.with
        if w then
            -- (the leave waits a frame: if the pointer went on to a line of the same quest, nothing goes out)
            C_Timer.After(0, function()
                for _, o in ipairs(rows) do
                    if o:IsShown() and o.line and o.line.with == w and o:IsMouseOver() then return end
                end
                -- (its lines' light goes out whatever came next: moving straight to another quest left it lit)
                for _, o in ipairs(rows) do if o.line and o.line.with == w then o.hl:Hide() end end
                if S.hoverWith ~= w then return end
                S.hoverWith = nil
                if l.leave then l.leave() end
                if GameTooltip and GameTooltip:IsShown() then
                    local owner = GameTooltip:GetOwner()
                    for _, o in ipairs(rows) do if owner == o then GameTooltip:Hide() break end end
                end
            end)
            return
        end
        if l and l.leave then l.leave() end
        if GameTooltip and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)
    r:SetScript("OnClick", function(self, button)
        local l = self.line
        if l and l.click then
            l.click(button)
            dirty = true
            Refresh()
        end
    end)
    -- (a line's + and -: a button of its own with its own light, so the zone's glow and the button's never show
    -- together: the user, 2026-11-22, "Same hoverglow for button and bar. Not same action. Need 2 different visuals")
    r.foldBtn = CreateFrame("Button", nil, r)
    r.foldBtn:RegisterForClicks("LeftButtonUp")
    r.foldBtn.lit = r.foldBtn:CreateTexture(nil, "HIGHLIGHT")
    r.foldBtn.lit:SetBlendMode("ADD")
    r.foldBtn.lit:SetAlpha(0.45)
    r.foldBtn:SetScript("OnClick", function(self)
        local l = self:GetParent().line
        if l and l.fold then
            l.fold()
            dirty = true
            Refresh()
        end
    end)
    r.foldBtn:Hide()
    rows[i] = r
    return r
end

local function Bead(r, i)
    local b = r.beads[i]
    if b then return b end
    b = { tex = r:CreateTexture(nil, "OVERLAY"), ring = r:CreateTexture(nil, "ARTWORK", nil, 2) }
    b.tex:SetTexture(WHITE8)
    b.ring:SetTexture(WHITE8)
    b.mask = r:CreateMaskTexture()
    b.mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    b.mask:SetAllPoints(b.tex)
    b.ringMask = r:CreateMaskTexture()
    b.ringMask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    b.ringMask:SetAllPoints(b.ring)
    b.ring:AddMaskTexture(b.ringMask)
    b.masked = false
    r.beads[i] = b
    return b
end

-- A page's reward items as the game's log shows them: a tile each, two to a row, the icon, the count on it, the
-- name in its quality's colour; the pointer on one gives the item's own tooltip, Shift-click links it, Ctrl-click
-- tries it on (the user, 2026-11-22, of "Choose one: Thistlewood Maul, ...": "Need icons in there and tooltips on
-- them, for the items"). One table, not locals: the chunk is at Lua's 200-local cap.
local ITEMS = { h = 48, wait = {} }
function ITEMS.Tile(r, j)
    r.tiles = r.tiles or {}
    local t = r.tiles[j]
    if t then return t end
    t = CreateFrame("Button", nil, r)
    t:RegisterForClicks("LeftButtonUp")
    t.hl = SoftBand(t, 0, { 1, 0.93, 0.78 }, 0.08)
    -- (an engraved plate round each, the user, 2026-11-22: "Can we engrave a border for these?": a double hairline,
    -- the outer brass, the inner faint, a small brass diamond at each corner; the icon in a brass rule)
    t.plate = {}
    for k, e in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local o = t:CreateTexture(nil, "BORDER")
        o:SetColorTexture(BRASS[1], BRASS[2], BRASS[3], 0.28)
        o:SetPoint(e[1])
        o:SetPoint(e[2])
        local i = t:CreateTexture(nil, "BORDER")
        i:SetColorTexture(BRASS[1], BRASS[2], BRASS[3], 0)   -- (the inner line off: "a little too much", the user)
        if k <= 2 then
            o:SetHeight(1)
            i:SetHeight(1)
            i:SetPoint(e[1], 3, k == 1 and -3 or 3)
            i:SetPoint(e[2], -3, k == 1 and -3 or 3)
        else
            o:SetWidth(1)
            i:SetWidth(1)
            i:SetPoint(e[1], k == 3 and 3 or -3, -3)
            i:SetPoint(e[2], k == 3 and 3 or -3, 3)
        end
    end
    -- (no corner marks: the plain box alone. The diamonds, then the Engraver's curls, were tried; "im not loving the
    -- curls. Just leave the simple box frame without them", the user, 2026-11-22)
    t.ring = t:CreateTexture(nil, "ARTWORK", nil, -1)
    t.ring:SetColorTexture(0.84, 0.66, 0.38, 0.85)
    t.edge = t:CreateTexture(nil, "ARTWORK")
    t.edge:SetPoint("LEFT", 6, 0)
    t.edge:SetSize(34, 34)
    t.edge:SetColorTexture(0, 0, 0, 0.9)
    t.ring:SetPoint("TOPLEFT", t.edge, "TOPLEFT", -1, 1)
    t.ring:SetPoint("BOTTOMRIGHT", t.edge, "BOTTOMRIGHT", 1, -1)
    t.icon = t:CreateTexture(nil, "ARTWORK", nil, 1)
    t.icon:SetPoint("TOPLEFT", t.edge, "TOPLEFT", 1, -1)
    t.icon:SetSize(32, 32)
    t.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    t.count = t:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    t.count:SetPoint("BOTTOMRIGHT", t.icon, "BOTTOMRIGHT", -1, 1)
    t.name = t:CreateFontString(nil, "OVERLAY")
    t.name:SetFont(FRIZ, 11.5, "")
    t.name:SetJustifyH("LEFT")
    t.name:SetJustifyV("MIDDLE")
    t.name:SetWordWrap(true)
    t.name:SetPoint("LEFT", t.edge, "RIGHT", 6, 0)
    t:SetScript("OnEnter", function(self)
        self.hl:Show()
        if GameTooltip and self.id then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.id)
            GameTooltip:Show()
        end
    end)
    t:SetScript("OnLeave", function(self)
        self.hl:Hide()
        if GameTooltip and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)
    t:SetScript("OnClick", function(self)
        local link = self.id and C_Item and C_Item.GetItemInfo and select(2, C_Item.GetItemInfo(self.id))
        if not link then return end
        if IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(link)
        elseif IsModifiedClick and IsModifiedClick("DRESSUP") and DressUpItemLink then DressUpItemLink(link) end
    end)
    r.tiles[j] = t
    return t
end
-- lays the tiles under a line from y down; gives the height used (0: none)
function ITEMS.Lay(r, items, width, top)
    local n = items and #items or 0
    for j = n + 1, #(r.tiles or {}) do r.tiles[j]:Hide() end
    if n == 0 then return 0 end
    local tw = math.floor((width - 12) / 2)
    for j, it in ipairs(items) do
        local t = ITEMS.Tile(r, j)
        local id = it[1]
        t.id = id
        local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))
        t.icon:SetTexture(icon or 134400)
        t.count:SetText((it[3] or 1) > 1 and it[3] or "")
        local q = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
        if not q then
            ITEMS.wait[id] = true
            if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        end
        local qc = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or it[2]
        t.name:SetText(name or "")
        if qc then t.name:SetTextColor(qc.r, qc.g, qc.b) else Colour(t.name, TEXT) end
        t.name:SetWidth(tw - 56)
        t.name:SetHeight(34)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", r, "TOPLEFT", 6 + ((j - 1) % 2) * tw, top - math.floor((j - 1) / 2) * ITEMS.h)
        t:SetSize(tw - 6, ITEMS.h - 6)
        t.hl:Lay(tw - 6)
        t.hl:Hide()
        t:Show()
    end
    -- (an item the client has not seen yet comes in later: the page is drawn again with its colour)
    if next(ITEMS.wait) and not ITEMS.ev then
        ITEMS.ev = CreateFrame("Frame")
        ITEMS.ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        ITEMS.ev:SetScript("OnEvent", function(_, _, id)
            if id and ITEMS.wait[id] then
                ITEMS.wait[id] = nil
                dirty = true
                if Refresh then Refresh() end
            end
        end)
    end
    return math.ceil(n / 2) * ITEMS.h + 4
end

-- the chain's beads under a line: done filled, the one you are on gold, what is ahead hollow and shaped
-- (a diamond: far from here; a square: a dungeon; a ringed bead: wants a group)
local function LayBeads(r, beads, x, y)
    local n = beads and math.min(#beads.steps, 16) or 0
    for i = 1, n do
        local s, b = beads.steps[i], Bead(r, i)
        local round = not (s.far or s.dungeon) or s.done or s.now
        if round ~= b.masked then
            if round then b.tex:AddMaskTexture(b.mask) else b.tex:RemoveMaskTexture(b.mask) end
            b.masked = round
        end
        local size = s.now and 9 or 7
        b.tex:ClearAllPoints()
        b.tex:SetSize(size, size)
        b.tex:SetPoint("CENTER", r, "TOPLEFT", x + (i - 1) * 13 + 4, y - 5)
        b.tex:SetRotation((s.far and not s.done and not s.now) and math.rad(45) or 0)
        if s.now then b.tex:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
        elseif s.done then b.tex:SetVertexColor(BRASS[1], BRASS[2], BRASS[3], 0.95)
        else b.tex:SetVertexColor(0.62, 0.60, 0.55, 0.5) end
        b.tex:Show()
        local ring = s.group and not s.done
        b.ring:SetShown(ring and true or false)
        if ring then
            b.ring:ClearAllPoints()
            b.ring:SetSize(size + 5, size + 5)
            b.ring:SetPoint("CENTER", b.tex, "CENTER")
            b.ring:SetVertexColor(0.62, 0.60, 0.55, 0.28)
        end
    end
    for i = n + 1, #r.beads do
        r.beads[i].tex:Hide()
        r.beads[i].ring:Hide()
    end
end

-- a row of small glass buttons with a brass rim (the page's actions); hidden where a line has none
-- (the game's own panel buttons, as the game's quest log and our quest page in Tracker.lua have them: the user,
-- 2026-11-22, of our flat brass boxes, "Buttons need some serious work". { label, fn, _, tip })
-- (then plain words under the foot's own rule, a soft light behind the one under the pointer, Abandon in a muted red:
-- the user, 2026-11-22, of the game's red buttons, "Buttons dont fit in anymore tbh. Its the frames and the brightness
-- of the red", then "Words on a rule" from mockups/world-page-buttons.png)
local ACT_TEXT, ACT_LIT, ACT_DANGER = { 0.84, 0.66, 0.38 }, { 1, 0.82, 0 }, { 0.80, 0.43, 0.35 }
function ActButtons(r, acts, width, padAt)
    r.acts = r.acts or {}
    local n = acts and #acts or 0
    local gap = 2
    local bw = n > 0 and math.floor((width - 6 - gap * (n - 1)) / n) or 0
    local function Paint(b)
        local lit = b:IsMouseOver() or b.padLit
        local c = lit and (b.danger and { 0.95, 0.52, 0.42 } or ACT_LIT) or (b.danger and ACT_DANGER or ACT_TEXT)
        b.label:SetTextColor(c[1], c[2], c[3])
        b.glow:SetShown(lit and true or false)
        -- (SetGradient carries the colour itself: a vertex colour after it would undo the fade)
        local a = lit and 0.9 or 0.5
        for k, u in ipairs(b.under) do
            local on, off = CreateColor and CreateColor(c[1], c[2], c[3], a), CreateColor and CreateColor(c[1], c[2], c[3], 0)
            if not (on and u.SetGradient and pcall(u.SetGradient, u, "HORIZONTAL", k == 1 and off or on, k == 1 and on or off)) then
                u:SetVertexColor(c[1], c[2], c[3], a * 0.6)
            end
        end
    end
    for i = 1, math.max(n, #r.acts) do
        local a, b = acts and acts[i], r.acts[i]
        if a and not b then
            b = CreateFrame("Button", nil, r)
            b:RegisterForClicks("LeftButtonUp")
            b.glow = b:CreateTexture(nil, "BACKGROUND")
            b.glow:SetTexture(ns.MEDIA .. "World\\WorldPool")
            b.glow:SetBlendMode("ADD")
            b.glow:SetVertexColor(1, 0.85, 0.55, 0.22)
            b.glow:SetPoint("TOPLEFT", -4, 2)
            b.glow:SetPoint("BOTTOMRIGHT", 4, -2)
            b.glow:Hide()
            b.label = b:CreateFontString(nil, "OVERLAY")
            b.label:SetFont(FRIZ, 12, "")
            b.label:SetShadowColor(0, 0, 0, 1)
            b.label:SetShadowOffset(1, -1)
            b.label:SetPoint("CENTER", 0, 1)
            -- (a hairline under the word, pointed at both ends: two halves fading out from the middle. The user,
            -- 2026-11-22: "Roule dobels. How about 1 rule over, and one like pic 2 under each, pointed both ends")
            b.under = {}
            for k = 1, 2 do
                local u = b:CreateTexture(nil, "ARTWORK")
                u:SetTexture(WHITE8)
                u:SetHeight(1)
                u:SetPoint(k == 1 and "RIGHT" or "LEFT", b.label, "BOTTOM", 0, -4)
                b.under[k] = u
            end
            b:SetScript("OnClick", function(self)
                if self.fn then self.fn() end
                dirty = true
                Refresh()
            end)
            b:SetScript("OnEnter", function(self)
                Paint(self)
                if self.tip and GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
                    GameTooltip:Show()
                end
            end)
            b:SetScript("OnLeave", function(self)
                C_Timer.After(0, function() Paint(self) end)
                if GameTooltip and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
            end)
            r.acts[i] = b
        end
        if a then
            b.fn, b.tip, b.danger = a[2], a[4], a[3] and true or false
            b.label:SetText(a[1])
            local uw = math.min(bw - 4, (b.label:GetStringWidth() or 40) + 18) / 2
            for _, u in ipairs(b.under) do u:SetWidth(uw) end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", r, "TOPLEFT", 3 + (i - 1) * (bw + gap), -5)
            b:SetSize(bw, 22)
            b:SetFrameLevel(r:GetFrameLevel() + 2)
            b.padLit = padAt == i
            Paint(b)
            b:Show()
        elseif b then
            b:Hide()
        end
    end
end

local function Render(lines)
    local width = content:GetWidth()
    local y = 0
    local ribUp, nStrip, nBook, footUp = false, 0, 0, false
    S.lines = lines
    for i, l in ipairs(lines) do
        local r = Row(i)
        r.line = l
        r:ClearAllPoints()
        local z = l.zoom and W.PageZoom() or 1
        local size = (l.size or (l.head and 10.5 or 13)) * z
        local indent = l.indent or 0
        local textAt = indent + (l.icon and (l.head and 15 or 18) or 0) + (l.head and l.text ~= "" and not l.icon and 11 or 0)
        r.icon:SetShown(l.icon and true or false)
        if l.icon then
            local info = l.atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(l.atlas)
            if info then
                r.icon:SetAtlas(l.atlas)
            else
                r.icon:SetTexture(l.icon)
                r.icon:SetTexCoord(0, 1, 0, 1)
            end
            r.icon:ClearAllPoints()
            -- (on an engraved head smaller, centred on its small capitals: "Sitting too high, too big too?", the user)
            if l.head then
                r.icon:SetPoint("TOPLEFT", indent, -6)
                r.icon:SetSize(11, 11)
            else
                r.icon:SetPoint("TOPLEFT", indent, -2)
                r.icon:SetSize(14, 14)
            end
            local tc = l.tint or { 1, 1, 1 }
            r.icon:SetVertexColor(tc[1], tc[2], tc[3], l.alpha or 1)
        end
        r.left:SetFont(l.font or FRIZ, size, "")
        r.left:SetWordWrap(l.wrap and true or false)
        r.left:ClearAllPoints()
        r.left:SetPoint("TOPLEFT", textAt, l.head and -7 or -2)
        r.right:SetFont(FRIZ, (l.head and 10.5 or 11.5) * z, "")
        r.right:SetText(l.right or "")
        r.right:ClearAllPoints()
        r.right:SetPoint("TOPRIGHT", -2, l.head and -7 or -3)
        local rw = l.right and r.right:GetStringWidth() + 8 or 0
        r.left:SetWidth(math.max(40, width - textAt - rw))
        -- (the level before the name in the quest's own colour, "|cff..": the rest takes the line's colour)
        local lc = l.levelColour
        local tail = (l.after or "") .. (l.tag and ("  " .. l.tag) or "")
        local text = (l.text or "") .. tail
        -- (the page's title, out of the list: the level muted in brackets, "[3]": the user, 2026-11-22, "The
        -- levelnumber before looks strange when not in the list, maybe we add [ ] muted?")
        local fmt = l.bracket and "|cff%02x%02x%02x[%d]|r  " or "|cff%02x%02x%02x%d|r  "
        local mute = l.bracket and 0.55 or 1
        local head = l.level and lc and fmt:format((lc[1] * mute + 0.42 * (1 - mute)) * 255, (lc[2] * mute + 0.42 * (1 - mute)) * 255,
            (lc[3] * mute + 0.42 * (1 - mute)) * 255, l.level) or ""
        r.left:SetText(head .. text)
        -- (one line too long: the name gives way, "...", and the check and the tag after it stay whole)
        if not l.wrap and tail ~= "" and l.text and (r.left.GetUnboundedStringWidth and r.left:GetUnboundedStringWidth() or r.left:GetStringWidth()) > r.left:GetWidth() + 0.5 then
            local name = l.text
            for _ = 1, 80 do
                name = name:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")
                if name == "" then break end
                r.left:SetText(head .. name:gsub("%s+$", "") .. "..." .. tail)
                if (r.left.GetUnboundedStringWidth and r.left:GetUnboundedStringWidth() or r.left:GetStringWidth()) <= r.left:GetWidth() + 0.5 then break end
            end
        end
        local c = l.head and BRASS or l.colour or TEXT
        Colour(r.left, c, l.alpha)
        W.LayPencil(r, l, textAt, size, l.under and (head .. (l.text or "")) or nil)
        -- (a heading of the continent's quest log: a brass hairline from the name to the count, the ledger's leader)
        if l.ledger then
            if not r.lead then
                r.lead = r:CreateTexture(nil, "ARTWORK")
                r.lead:SetColorTexture(BRASS[1], BRASS[2], BRASS[3], 0.3)
                r.lead:SetHeight(1)
            end
            local tw = r.left:GetStringWidth() or 0
            r.lead:ClearAllPoints()
            r.lead:SetPoint("TOPLEFT", textAt + tw + 6, -(size * 0.8))
            r.lead:SetPoint("TOPRIGHT", -rw, -(size * 0.8))
            r.lead:Show()
        elseif r.lead then
            r.lead:Hide()
        end
        Colour(r.right, l.head and BRASS or SOFT, l.alpha)
        local h
        if l.bar then
            h = 8
            r.barBack:ClearAllPoints()
            r.barBack:SetPoint("TOPLEFT", 6, -2)
            r.barBack:SetSize(width - 12, 3)
            r.bar:ClearAllPoints()
            r.bar:SetPoint("TOPLEFT", 6, -2)
            r.bar:SetSize(math.max(1, (width - 12) * l.bar), 3)
        elseif l.ribbon then
            h = RIB_H + 8
        elseif l.strip or l.book then
            h = STRIP.h + 8
        elseif l.acts then
            h = l.foot and panel.foot and 0 or 30
        elseif l.items and (l.text or "") == "" then
            h = 2
        elseif l.head then
            h = (l.text == "" and 8 or math.floor(22 + 10.5 * (z - 1) + 0.5))
        else
            h = math.max(ROW_H * z, (l.wrap and r.left:GetStringHeight() or size) + 5)
        end
        r.barBack:SetShown(l.bar and true or false)
        r.bar:SetShown(l.bar and true or false)
        -- how far along, as a thin bar under the name
        local frac = not l.head and not l.bar and l.frac or nil
        r.progBack:SetShown(frac and true or false)
        r.prog:SetShown(frac and frac > 0 and true or false)
        if frac then
            local bw = math.max(10, width - textAt - 2)
            r.progBack:ClearAllPoints()
            r.progBack:SetPoint("TOPLEFT", textAt, -h + 1)
            r.progBack:SetSize(bw, 2)
            r.progBack:SetAlpha(l.alpha or 1)
            r.prog:ClearAllPoints()
            r.prog:SetPoint("TOPLEFT", textAt, -h + 1)
            r.prog:SetSize(math.max(1, bw * math.min(1, frac)), 2)
            r.prog:SetAlpha(l.alpha or 1)
            h = h + 3
        end
        local engraved = l.head and l.text ~= ""
        r.rule:SetShown(engraved and true or false)
        if not r.hdia then
            r.hdia = r:CreateTexture(nil, "ARTWORK")
            r.hdia:SetTexture(ns.MEDIA .. "World\\WorldDiamond")
            r.hdia:SetSize(5, 5)
            r.hdia:SetVertexColor(BRASS[1], BRASS[2], BRASS[3], 0.95)
        end
        r.hdia:SetShown(engraved and not l.icon and true or false)   -- (a fold mark stands where the diamond would)
        if engraved and r.hdia.dash ~= (l.dash and true or false) then
            r.hdia.dash = l.dash and true or false
            if l.dash then
                r.hdia:SetTexture(WHITE8)
                r.hdia:SetSize(6, 1.5)
            else
                r.hdia:SetTexture(ns.MEDIA .. "World\\WorldDiamond")
                r.hdia:SetSize(5, 5)
            end
        end
        if engraved then
            r.hdia:ClearAllPoints()
            r.hdia:SetPoint("RIGHT", r.left, "LEFT", -5, 0)
            local sw = r.left:GetStringWidth() or 0
            local room = width - textAt - sw - 10 - rw
            r.rule:ClearAllPoints()
            r.rule:SetPoint("LEFT", r.left, "LEFT", sw + 8, 0)
            r.rule:SetSize(math.max(1, room), 1)
            r.rule:SetTexture(WHITE8)
            local c1 = CreateColor and CreateColor(BRASS[1], BRASS[2], BRASS[3], 0.6)
            local c2 = CreateColor and CreateColor(BRASS[1], BRASS[2], BRASS[3], 0)
            if not (c1 and r.rule.SetGradient and pcall(r.rule.SetGradient, r.rule, "HORIZONTAL", c1, c2)) then r.rule:SetVertexColor(BRASS[1], BRASS[2], BRASS[3], 0.35) end
        end
        -- (the page's title: a gold hairline under it, brightest in the middle, fading out to both ends: the user,
        -- 2026-11-22, of one fading out from the left, "maybe that one starts from middle")
        if l.bracket then
            if not r.trule then
                r.trule = {}
                for k = 1, 2 do
                    local tx = r:CreateTexture(nil, "ARTWORK")
                    tx:SetTexture(WHITE8)
                    tx:SetHeight(1)
                    local a1, a2 = k == 1 and 0 or 0.55, k == 1 and 0.55 or 0
                    local c1 = CreateColor and CreateColor(GOLD[1], GOLD[2], GOLD[3], a1)
                    local c2 = CreateColor and CreateColor(GOLD[1], GOLD[2], GOLD[3], a2)
                    if not (c1 and tx.SetGradient and pcall(tx.SetGradient, tx, "HORIZONTAL", c1, c2)) then tx:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.3) end
                    r.trule[k] = tx
                end
            end
            for k, tx in ipairs(r.trule) do
                tx:ClearAllPoints()
                tx:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", k == 1 and 4 or width / 2, 1)
                tx:SetWidth(math.max(1, width / 2 - 4))
                tx:Show()
            end
        elseif r.trule then
            for _, tx in ipairs(r.trule) do tx:Hide() end
        end
        if l.beads then
            LayBeads(r, l.beads, textAt, -h)
            h = h + 11
        else
            LayBeads(r, nil)
        end
        if l.sub then
            r.sub:SetFont(FRIZ, 10.5, "")
            r.sub:SetText(l.sub)
            Colour(r.sub, DIM, l.alpha)
            r.sub:ClearAllPoints()
            r.sub:SetPoint("TOPLEFT", textAt, -h + 1)
            r.sub:SetWidth(width - textAt)
            r.sub:Show()
            h = h + 13
        else
            r.sub:Hide()
        end
        h = h + ITEMS.Lay(r, l.items, width, -h)
        r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        r:SetSize(width, h)
        if l.ribbon then
            LayRibbon(l.ribbon, r, width)
            ribUp = true
        end
        r.glow, r.idx = nil, i
        if l.strip then
            nStrip = nStrip + 1
            LayStrip(nStrip, l.strip, r, width)
            r.glow = STRIP.bands[nStrip].glow
            -- (its fold mark at the strip's right end, past the painting: "Icon right i think", the user, 2026-11-22)
            if l.icon then
                r.icon:ClearAllPoints()
                r.icon:SetPoint("RIGHT", r, "TOPRIGHT", -2, -6 - STRIP.h / 2)
            end
        end
        if l.book then
            nBook = nBook + 1
            LayBook(nBook, l.book, r, width)
            r.glow = STRIP.books[nBook].glow
        end
        -- (a page's buttons stand in the column's foot, never in the flow: the user, 2026-11-21, "the buttons to
        -- track find share and abandon is placed so that they will shift position if the objective is shorter or
        -- longer". The line keeps its place in the list, at no height, so the controller still walks to it)
        local foot = l.foot and l.acts and panel.foot
        ActButtons(r, not foot and l.acts or nil, width, not foot and S.sel == i and l.acts and math.min(S.act or 1, #l.acts) or nil)
        if foot then
            ActButtons(foot, l.acts, width, S.sel == i and math.min(S.act or 1, #l.acts) or nil)
            footUp = true
        end
        r:EnableMouse((l.click or l.enter or l.tip) and true or false)
        local fb = r.foldBtn
        if l.fold and l.icon then
            fb:ClearAllPoints()
            fb:SetPoint("CENTER", r.icon, "CENTER")
            fb:SetSize(20, 20)
            fb:SetFrameLevel(r:GetFrameLevel() + 3)
            local info = l.atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(l.atlas)
            if info then fb.lit:SetAtlas(l.atlas) else fb.lit:SetTexture(l.icon) end
            fb.lit:ClearAllPoints()
            fb.lit:SetAllPoints(r.icon)
            fb:Show()
        else
            fb:Hide()
        end
        -- (a strip is lit in its own shape, never boxed: hover and the controller's pick alike)
        -- (the soft bands laid to this line's width; the hover's light only where the pointer is, or on its quest's
        -- lines: a redraw never leaves one lit on a line that came into its place, the user's shot, 2026-11-22)
        r.hl:Lay(width)
        r.sel:Lay(width)
        local hovered = l.click and r:IsMouseOver() or (l.with and S.hoverWith == l.with)
        r.hl:SetShown(hovered and not r.glow and true or false)
        r.sel:SetShown(S.sel == i and not r.glow)
        if r.glow then r.glow:SetShown(S.sel == i or (r:IsMouseOver() and not (fb:IsShown() and fb:IsMouseOver()) and true or false)) end
        r.y, r.h = y, h
        r:Show()
        y = y + h
    end
    for i = #lines + 1, #rows do rows[i]:Hide() rows[i].line = nil end
    for j = nStrip + 1, #STRIP.bands do STRIP.bands[j]:Hide() end
    for j = nBook + 1, #STRIP.books do STRIP.books[j]:Hide() end
    if panel.foot then panel.foot:SetShown(footUp) end
    if ribbon and not ribUp and RIB.key then
        ribbon:Hide()
        ribbon.name:SetText("")
        RIB.key = nil   -- (laid afresh the next time a page opens)
    end
    -- (a step of the chain clicked: the new page laid so the chain stays where it was under the pointer, room added
    -- below if the page is short, so the way back is where the hand already is. The user, 2026-11-22: "Clicking to one
    -- quest in chain then back jumps the window up", "to click abck you gotta scroll", "Decision")
    local an = S.anchor
    if an and an.page ~= S.page then S.anchor, an = nil, nil end
    local want
    if an then
        for i = 1, #lines do
            if lines[i].id == an.id and rows[i] and rows[i].y then want = math.max(0, rows[i].y - an.off) break end
        end
        if want then y = math.max(y, want + scroll:GetHeight()) end
    end
    content:SetHeight(math.max(1, y))
    local range = math.max(0, y - scroll:GetHeight())
    if want and not an.done then
        -- (once: later redraws keep the room below but leave the scroll to the wheel)
        -- (the scroll frame learns the new page's height a frame late and holds the scroll inside the old one, which
        -- left a longer page at its top: set it now and again next frame. "Clicking to a step with enough text to
        -- scoll, skips to the top of that page", the user)
        local to = math.min(range, want)
        if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
        scroll:SetVerticalScroll(to)
        C_Timer.After(0, function()
            if S.anchor == an then
                if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
                scroll:SetVerticalScroll(math.min(scroll.range or to, to))
                an.done = true
            end
        end)
    elseif scroll:GetVerticalScroll() > range then scroll:SetVerticalScroll(range) end
    scroll.range = range
end

-- a round texture: a white disc masked round (signs, the rail's ring)
local function Round(parent, layer, sub)
    local t, m = parent:CreateTexture(nil, layer, nil, sub), parent:CreateMaskTexture()
    t:SetTexture(WHITE8)
    m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(t)
    t:AddMaskTexture(m)
    return t
end

-- Making the panel ----------------------------------------------------------------------------

local function TextButton(parent, text, onClick)
    local b = CreateFrame("Button", nil, parent)
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetFont(FRIZ, 11.5, "")
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    b:SetSize(b.text:GetStringWidth() + 12, 18)
    b.under = b:CreateTexture(nil, "ARTWORK")
    b.under:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
    b.under:SetHeight(1)
    b.under:SetPoint("BOTTOMLEFT", 4, 1)
    b.under:SetPoint("BOTTOMRIGHT", -4, 1)
    b.under:Hide()
    function b:Mark(on)
        self.on = on
        self.under:SetShown(on and true or false)
        Colour(self.text, on and GOLD or self.rest or SOFT)
    end
    b:Mark(false)
    b:SetScript("OnEnter", function(self) Colour(self.text, TEXT) end)
    b:SetScript("OnLeave", function(self) Colour(self.text, self.on and GOLD or self.rest or SOFT) end)
    b:SetScript("OnClick", function(self)
        onClick(self)
        dirty = true
        Refresh()
    end)
    return b
end

local function Make()
    -- where the column (or, folded, the rail) stands: placed against the map, the panel and the window follow it
    slot = CreateFrame("Frame", nil, UIParent)
    panel = CreateFrame("Frame", "WaymarkWorldPanel", UIParent)
    panel:SetFrameStrata("MEDIUM")
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    panel:Hide()
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(SLATE[1], SLATE[2], SLATE[3], 0.93)
    panel.own = { bg }   -- (its own ground and rules: the window's glass stands in for them, Place)
    panel.bg = bg
    -- (the glass not flat: a fine grain and a soft light from its middle. The user, 2026-11-22: "a fine grain and a
    -- light in the glass ... I want to see this too". tools/world_top/ghost_bake.py makes the grain)
    local LABG = ns.MEDIA .. "World\\"
    panel.grain = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
    panel.grain:SetAllPoints()
    panel.grain:SetTexture(LABG .. "WorldGrain", "REPEAT", "REPEAT")
    if panel.grain.SetHorizTile then panel.grain:SetHorizTile(true) panel.grain:SetVertTile(true) end
    panel.grain:Hide()   -- (out: "Backdrop still looking busy with clouds", the user, 2026-11-22; the light stays)
    -- (a very faint sweep of light in the zone's own colour, slanting down from the top right: the user, 2026-11-22,
    -- "very very muted faint gradient, matched in the zones colors". tools/world_top/sweep_art.py; tinted in Refresh)
    panel.sweep = panel:CreateTexture(nil, "BACKGROUND", nil, 4)
    -- (over the gutter too, to the seam's brass line: it lifted the column a shade and left the gutter a dark sliver
    -- beside it, the user's shot, 2026-11-22, "Vertical leaves a teeeny sliver down the middle")
    panel.sweep:SetPoint("TOPLEFT", panel, "TOPLEFT", -(GAP - 1), 0)
    panel.sweep:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    panel.sweep:SetTexture(LABG .. "WorldSweep")
    panel.sweep:Hide()   -- (soft clouds, faint: per-pixel grain read as "static behind the glass")
    panel.light = panel:CreateTexture(nil, "BACKGROUND", nil, 4)
    panel.light:SetTexture(LABG .. "WorldPool")
    panel.light:SetBlendMode("ADD")
    panel.light:SetVertexColor(1, 0.92, 0.78, 0.05)
    panel.light:SetPoint("TOPLEFT", panel, "TOPLEFT", -40, -60)
    panel.light:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 40, 80)
    -- (the zone's drawing taken out again, the user, 2026-11-22: "Nah, no drawing in this form. Take it out, show me
    -- the other one": one engraved emblem low in the column instead, faint brass, the compass rose)
    -- (the place's own outline, the game's: its shape in brass, the same shape a little smaller in the glass's own
    -- slate over it, so a line is left; both under the light and the sweep, so the inside is the glass itself.
    -- The user, 2026-11-22: "Zones outline would be REALLY cool", "kalim outline and Ek outline could work")
    panel.outline = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
    panel.outlineIn = panel:CreateTexture(nil, "BACKGROUND", nil, 2)
    panel.outline:Hide()
    panel.outlineIn:Hide()
    panel.emblem = panel:CreateTexture(nil, "BACKGROUND", nil, 5)
    panel.emblem:SetVertexColor(0.84, 0.66, 0.38, 0.035)   -- (fainter: "Abit too prominent and obvious", the user)
    panel.emblem:SetSize(180, 180)
    panel.emblem:SetPoint("CENTER", panel, "BOTTOM", 0, 190)
    for _, edge in ipairs({ "TOP", "BOTTOM" }) do
        local rule = panel:CreateTexture(nil, "BORDER")
        rule:SetColorTexture(BRASS[1], BRASS[2], BRASS[3], 0.95)
        rule:SetHeight(1)
        rule:SetPoint(edge .. "LEFT")
        rule:SetPoint(edge .. "RIGHT")
        panel.own[#panel.own + 1] = rule
    end
    local side = panel:CreateTexture(nil, "BORDER")
    panel.own[#panel.own + 1] = side
    side:SetColorTexture(BRASS[1], BRASS[2], BRASS[3], 0.25)
    side:SetWidth(1)
    side:SetPoint("TOPLEFT")
    side:SetPoint("BOTTOMLEFT")
    panel:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then PanelMenu() end end)

    head = CreateFrame("Frame", nil, panel)
    head:SetPoint("TOPLEFT", PAD_L, -PAD_T)
    head:SetPoint("TOPRIGHT", -PAD_L, -PAD_T)
    head:SetHeight(22)
    -- (right-click: the log out to the continent, the map stays; the panel's own menu is everywhere else)
    head:EnableMouse(true)
    head:SetScript("OnMouseUp", function(_, button)
        -- (the log alone dragged by its plaque: that let-go is no click. Lab/WorldAlone.lua)
        if W.AloneJustDragged and W.AloneJustDragged() then return end
        -- (a left-click: the log back on the zone you stand in, the map stays as the right-click leaves it. The user,
        -- 2026-11-22: "We have rightclick on zonetitle to go to continent. What about left click to return to the zone
        -- ur in")
        if button == "LeftButton" then
            local here = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
            local zone = here and (W.ZoneMap(here) or here)
            if not zone then return end
            local c = Cfg()
            local mapZone = W.ZoneMap(MapID() or 0)
            c.logAt = zone ~= mapZone and zone or nil
            S.page, S.sel, S.anchor = nil, nil, nil
            dirty = true
            Refresh()
            return
        end
        if button ~= "RightButton" then return end
        local c = Cfg()
        local from = c.logAt or MapID()
        local cont = W.Continent(from)
        if not cont or cont == from then return end
        c.logAt = cont
        S.page, S.sel = nil, nil
        dirty = true
        Refresh()
    end)
    head.title = head:CreateFontString(nil, "OVERLAY")
    head.title:SetFont(FRIZ, 16, "")
    head.title:SetPoint("LEFT")
    head.title:SetJustifyH("LEFT")
    head.title:SetWordWrap(false)
    Colour(head.title, GOLD)
    -- (the lit lip under a name cut into the glass, style "felipa"; the levels line and the fading rule, "caps")
    head.lip = head:CreateFontString(nil, "ARTWORK")
    head.lip:SetPoint("TOPLEFT", head.title, "TOPLEFT", 0, -1)
    head.lip:SetJustifyH("LEFT")
    head.lip:SetWordWrap(false)
    head.lip:Hide()
    head.levels = head:CreateFontString(nil, "OVERLAY")
    head.levels:SetFont(FRIZ, 10.5, "")
    head.levels:SetPoint("TOPLEFT", head.title, "BOTTOMLEFT", 0, -3)
    Colour(head.levels, DIM)
    head.levels:Hide()
    head.rule = {}
    for i = 1, 2 do
        local t = head:CreateTexture(nil, "ARTWORK")
        t:SetTexture(WHITE8)
        t:SetHeight(1)
        head.rule[i] = t
    end
    head.rule[1]:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, -2)
    head.rule[1]:SetPoint("BOTTOMRIGHT", head, "BOTTOM", 0, -2)
    head.rule[2]:SetPoint("BOTTOMLEFT", head, "BOTTOM", 0, -2)
    head.rule[2]:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, -2)
    for i, t in ipairs(head.rule) do
        -- (fading out at both ends; a client without colour gradients gets a plain brass line)
        local a, b = CreateColor and CreateColor(BRASS[1], BRASS[2], BRASS[3], i == 1 and 0 or 0.85),
                     CreateColor and CreateColor(BRASS[1], BRASS[2], BRASS[3], i == 1 and 0.85 or 0)
        if not (a and t.SetGradient and pcall(t.SetGradient, t, "HORIZONTAL", a, b)) then t:SetVertexColor(BRASS[1], BRASS[2], BRASS[3], 0.6) end
        t:Hide()
    end
    head.count = head:CreateFontString(nil, "OVERLAY")
    head.count:SetFont(FRIZ, 11.5, "")
    head.count:SetPoint("RIGHT")
    Colour(head.count, SOFT)

    tools = CreateFrame("Frame", nil, panel)
    tools:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
    tools:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, -4)
    -- (two rows: the tabs and the count, then the search across the column's width: the user, 2026-11-22,
    -- "Searchbar needs to be bigger")
    tools:SetHeight(50)
    -- The row engraved, no boxes (the user, 2026-11-21: "The rectangular searchbar, hard edges, surgical", and
    -- picked A on mockups/quest-head.html): the tabs in spaced capitals with a brass diamond between, the one on
    -- view gold over a brass hairline fading at both ends; the search a brass glass and a ruled line to write on.
    local function Fade(t, from, to, a)   -- (a brass line fading; a client without gradients gets it plain)
        local c1 = CreateColor and CreateColor(BRASS[1], BRASS[2], BRASS[3], from)
        local c2 = CreateColor and CreateColor(BRASS[1], BRASS[2], BRASS[3], to)
        if not (c1 and t.SetGradient and pcall(t.SetGradient, t, "HORIZONTAL", c1, c2)) then t:SetVertexColor(BRASS[1], BRASS[2], BRASS[3], a) end
    end
    local function Diamond(at, x, y)
        local d = tools:CreateTexture(nil, "ARTWORK")
        d:SetColorTexture(BRASS[1], BRASS[2], BRASS[3], 0.6)
        d:SetSize(4, 4)
        if d.SetRotation then d:SetRotation(math.pi / 4) end
        d:SetPoint("LEFT", at, "RIGHT", x, y or 0)
        return d
    end
    local function Engrave(b, word)
        b.text:SetFont(FRIZ, 10, "")
        b.text:SetText((word:upper():gsub(".", "%0 ")):sub(1, -2))
        b:SetSize(b.text:GetStringWidth() + 12, 18)
        b.under:SetTexture("Interface\\Buttons\\WHITE8X8")
        b.under:ClearAllPoints()
        b.under:SetPoint("BOTTOMLEFT", 0, 1)
        b.under:SetPoint("BOTTOMRIGHT", b, "BOTTOM", 0, 1)
        b.under2 = b:CreateTexture(nil, "ARTWORK")
        b.under2:SetTexture("Interface\\Buttons\\WHITE8X8")
        b.under2:SetHeight(1)
        b.under2:SetPoint("BOTTOMLEFT", b, "BOTTOM", 0, 1)
        b.under2:SetPoint("BOTTOMRIGHT", 0, 1)
        Fade(b.under, 0, 0.9, 0.7)
        Fade(b.under2, 0.9, 0, 0.7)
        local mark = b.Mark
        function b:Mark(on)
            mark(self, on)
            self.under2:SetShown(on and true or false)
        end
        b:Mark(false)
    end
    tools.held = TextButton(tools, "Held", function() Cfg().mode = "held" S.page, S.filter = nil, nil end)
    tools.held:SetPoint("TOPLEFT", -4, 0)
    Engrave(tools.held, "Held")
    tools.done = TextButton(tools, "Turned in", function() Cfg().mode = "done" S.page, S.filter = nil, nil end)
    tools.done:SetPoint("LEFT", tools.held, "RIGHT", 10, 0)
    Engrave(tools.done, "Turned in")
    Diamond(tools.held, 3, 1)
    -- (the little world scrapped, the user, 2026-11-22. In its tab's place: how many you hold, small and dim)
    tools.count = tools:CreateFontString(nil, "OVERLAY")
    tools.count:SetFont(FRIZ, 10.5, "")
    tools.count:SetPoint("RIGHT", tools, "TOPRIGHT", 0, -9)
    Colour(tools.count, DIM)
    local e = CreateFrame("EditBox", nil, tools)
    e:SetAutoFocus(false)
    e:SetFont(FRIZ, 13, "")
    e:SetTextColor(TEXT[1], TEXT[2], TEXT[3])
    e:SetHeight(22)
    e:SetPoint("TOPLEFT", tools, "TOPLEFT", 0, -26)
    e:SetPoint("TOPRIGHT", tools, "TOPRIGHT", 0, -26)
    e:SetTextInsets(21, 20, 0, 0)
    -- (a clear X at the box's end, the game's search box's own: the user, 2026-11-22, "no x at the end i need to
    -- backspace it all away". Shown only while there is something to clear)
    e.clear = CreateFrame("Button", nil, e)
    e.clear:SetSize(14, 14)
    e.clear:SetPoint("RIGHT", -2, 0)
    e.clear.tex = e.clear:CreateTexture(nil, "ARTWORK")
    e.clear.tex:SetAllPoints()
    e.clear.tex:SetTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
    e.clear.tex:SetAlpha(0.6)
    e.clear:SetScript("OnEnter", function(self) self.tex:SetAlpha(1) end)
    e.clear:SetScript("OnLeave", function(self) self.tex:SetAlpha(0.6) end)
    e.clear:SetScript("OnClick", function() e:SetText("") e:ClearFocus() end)
    e.clear:Hide()
    e.glass = e:CreateTexture(nil, "ARTWORK")
    e.glass:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    e.glass:SetSize(14, 14)
    e.glass:SetPoint("LEFT", 1, 0)
    e.glass:SetVertexColor(BRASS[1], BRASS[2], BRASS[3], 0.95)
    e.rule = {}
    for i = 1, 2 do
        local t = e:CreateTexture(nil, "ARTWORK")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetHeight(1)
        e.rule[i] = t
    end
    e.rule[1]:SetPoint("BOTTOMLEFT", 0, 0)
    e.rule[1]:SetPoint("BOTTOMRIGHT", e, "BOTTOM", 0, 0)
    e.rule[2]:SetPoint("BOTTOMLEFT", e, "BOTTOM", 0, 0)
    e.rule[2]:SetPoint("BOTTOMRIGHT", 0, 0)
    Fade(e.rule[1], 0.1, 0.55, 0.4)
    Fade(e.rule[2], 0.55, 0, 0.4)
    e.hint = e:CreateFontString(nil, "OVERLAY")
    e.hint:SetFont(FRIZ, 12, "")
    e.hint:SetPoint("LEFT", 21, 0)
    e.hint:SetText("Search")
    Colour(e.hint, DIM)
    e:SetScript("OnTextChanged", function(self)
        local t = self:GetText() or ""
        self.hint:SetShown(t == "")
        self.clear:SetShown(t ~= "")
        if t ~= S.search then
            S.search, S.book, S.page, S.sel = t, false, nil, nil
            dirty = true
            Refresh()
        end
    end)
    e:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    -- (a click anywhere else leaves the box, the search kept: until then every key went into it, the user
    -- 2026-11-22, "traps me in search after i search for something")
    e:SetScript("OnEditFocusGained", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    e:SetScript("OnEditFocusLost", function(self) pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    e:SetScript("OnEvent", function(self) if not self:IsMouseOver() then self:ClearFocus() end end)
    tools.edit = e
    tools.chips = {}
    -- (no filters: "Going grey" scrapped, "Scrap it. I can tell by them being green and lower level than me", then
    -- "Completed" removed, the user, 2026-11-21: a zone's list ends with its completed quests marked (Complete))

    scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("BOTTOMRIGHT", -PAD_L, 22)
    scroll:EnableMouseWheel(true)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(100, 1)
    scroll:SetScrollChild(content)
    scroll.range = 0
    scroll:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(math.max(0, math.min(self.range or 0, self:GetVerticalScroll() - delta * 44)))
    end)

    -- the page's buttons, fixed at the column's foot under a brass rule (Render lays them)
    panel.foot = CreateFrame("Frame", nil, panel)
    panel.foot:SetPoint("BOTTOMLEFT", PAD_L, 22)
    panel.foot:SetPoint("BOTTOMRIGHT", -PAD_L, 22)
    panel.foot:SetHeight(30)
    panel.foot:SetFrameLevel(scroll:GetFrameLevel() + 6)
    panel.foot.rule = panel.foot:CreateTexture(nil, "ARTWORK")
    panel.foot.rule:SetPoint("TOPLEFT", 0, 0)
    panel.foot.rule:SetPoint("TOPRIGHT", 0, 0)
    panel.foot.rule:SetHeight(1)
    panel.foot.rule:SetColorTexture(BRASS[1], BRASS[2], BRASS[3], 0.3)
    panel.foot:Hide()

    padHint = panel:CreateFontString(nil, "OVERLAY")
    padHint:SetFont(FRIZ, 10.5, "")
    padHint:SetPoint("BOTTOMLEFT", PAD_L, 6)
    Colour(padHint, DIM)

    -- a controller: only in the game's controller mode, only while this is up (enabled in Tick)
    panel:SetScript("OnGamePadButtonDown", function(self, button)
        PassOn(self, button)
        if ns.WorldPanelPad then ns.Safe("World log pad", ns.WorldPanelPad, button) end
    end)
    panel:SetScript("OnGamePadButtonUp", function(_, button)
        if ns.WorldPanelPadUp then ns.Safe("World log pad", ns.WorldPanelPadUp, button) end
    end)
end

-- The window ------------------------------------------------------------------------------------
-- (2026-11-19, the user, on the mock-up mockups\world-frame.html: "This is the direction! Lets try your pick,
-- glass, rail, frames from waymark. Espexially engravers.") One frame round the map and the log:
--   the glass   dark slate in STRIP.bands round the map (a bar on top, a thin edge, the log's side), never under
--               the map, so the map's own opacity is untouched. It lies below the map in the frame order, so
--               the map's own header still shows, on the bar
--   the frame   the frame set of the map's border (FrameSets.lua: Engraver's corners, Moonlit silver, Sun
--               gold) carried round the whole window; with no set chosen, a thin brass line. The map's own
--               border rests while the window is up (BorderHold), or there would be two
--   the bar     where you are in the world, each step a click; the count of 25 while folded; fold; close
--   folded      the log goes and the window closes round the map and a narrow rail: one round sign a quest
--               of the zone on view, ready ones in gold. Point for its name, click for its page
-- Settings (W.Cfg): window (on), fold, frame ("map": as the map's border; "glass": none; or a set's key).

local function Windowed() return true end   -- (always: the user, 2026-11-22, "default for worldmap, no setting")
local function Folded()
    local c = Cfg()
    if W.Alone and W.Alone() then return false end   -- (the log alone is never folded: Lab/WorldAlone.lua)
    return c.fold and true or false
end
local function Face()
    local m = Map()
    return m and ns.MapFace and ns.MapFace(m) or m
end

function Fold(to)
    local c = Cfg()
    if to == nil then to = not c.fold end
    c.fold = to and true or false
    S.railSel = nil
    if ns.HoverQuestGlow then pcall(ns.HoverQuestGlow, nil) end
    Refit()
    dirty = true
end

-- the frame set the window wears, nil for the plain brass line
local function FrameKey()
    local key = Cfg().frame or "engraver"
    if key == "glass" then return nil end
    if key == "map" or key == "parchment" then key = key == "map" and "engraver" or nil end   -- ("As the map's border" pruned, 2026-11-21)
    if not key then return nil end
    if not (key and ns.LabSet and ns.LabFrame and ns.LabSet(key)) then return nil end
    if ns.FrameSetOpen and not ns.FrameSetOpen(key) then return nil end
    -- (Sun gold and Moonlit silver are out of the window: "Silver and gold frames are out", the user, 2026-11-21,
    -- after they were drawn bigger. The small map keeps them; the window wears the Dark look's frame then)
    if key == "silver" or key == "gold" then return nil end
    return key
end
-- (the log alone, Lab/WorldAlone.lua: the parts it stands and dresses, and the window's own frame and fold)
W.FrameKey = FrameKey
function W.Parts() return panel, slot, head, win, bar end
function W.Fold(to) Fold(to) end
W.SLATE, W.BRASS, W.GAP = SLATE, BRASS, GAP

-- The map's border drawn as Style.lua draws it, round the whole window: the ready-made look "Parchment and bronze"
-- (the game's dialog edge, tinted bronze) and the other bordered looks (the user, 2026-11-21: "Please add
-- 'parchment and bronze' look, the one we already have, but let it show for worldmap"). The window's frame
-- "parchment" wears it always; "map" wears whatever bordered style the map has, when it has no frame set.
-- { style, size, colour } or nil
-- Plain glass, and every window with no frame set of its own, wears the ready-made look "Dark"'s frame: the game's
-- tooltip edge, dark (the user, 2026-11-21: "try the readymade look dark's framing on 'plain glass' option. Dark
-- tooltip color dark"). The thin brass line it replaces lay under the map's art along the map's edges ("Frame
-- missing a bit"). { style, size, colour, gap }
local function DressOf()
    local c = Cfg()
    if c.frame == "parchment" then return { "dialog", 0.75, "bronze", -2 } end   -- (as the look: PlaceLooks.lua, gap -2)
    return { "tooltip", 0.6, "dark", -2 }
end
W.DressOf = DressOf   -- (the log alone wears it too)

-- The map's own border rests while the window is up. Nothing of the map's is changed for good: its style
-- answers "none" through the same question clear view asks (ns.MapBorderStyle), and a frame set's border,
-- which answers to nobody, is made see-through each time the map's style is laid.
local held = false
local function BorderHold()
    if not held then
        if not (win and win:IsShown()) then return end
        held = true
        local style = ns.MapBorderStyle
        if style then
            ns.MapBorderStyle = function(own)
                if not own and win and win:IsShown() then return "none" end
                return style(own)
            end
        end
        if ns.ApplyFrameAlpha and hooksecurefunc then
            local function Rest()
                local edge = ns.debugFrames and ns.debugFrames.labBorder
                if edge and win and win:IsShown() then edge:SetAlpha(0) end
            end
            hooksecurefunc(ns, "ApplyFrameAlpha", Rest)
            -- (the map's own opacity change calls the function Style.lua hooked at its setup, not ours)
            local map = Map()
            if map and map.RefreshAlpha then hooksecurefunc(map, "RefreshAlpha", Rest) end
        end
    end
    if ns.UpdateStyle then ns.Safe("World window border", ns.UpdateStyle) end
end

local function Glass(parent)
    local t = parent:CreateTexture(nil, "BACKGROUND")
    t:SetColorTexture(SLATE[1], SLATE[2], SLATE[3], 0.93)
    return t
end

-- A mark on the folded rail (the user, 2026-11-22, of the round signs: "the questmarkers themselves just dont give
-- any info", "you dont know which quest it is"; of mockups/world-rail-marks.html, 1, "try this"): the quest's own
-- objective in the middle (the item you gather, round; a kill or a talk, the map's own spot icon), the count under it,
-- its rim gold when it is ready to hand in; nearest first. Quests apart by the log's engraved rule. Pointing lights
-- its ground with the quest pin's own tooltip; a click, its page.
local function RailSign(i)
    local b = rail.signs[i]
    if b then return b end
    b = CreateFrame("Button", nil, rail)
    b:SetSize(40, 40)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.face = Round(b, "BORDER", 0)
    b.face:SetPoint("CENTER")
    b.face:SetSize(31, 31)
    b.face:SetVertexColor(0.04, 0.045, 0.055, 1)
    b.rim = Round(b, "BACKGROUND", 0)
    b.rim:SetPoint("CENTER")
    b.rim:SetSize(33, 33)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(20, 20)
    b.icon:SetPoint("CENTER", 0, 0)
    b.item = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.item:SetSize(28, 28)
    b.item:SetTexCoord(0.1, 0.9, 0.1, 0.9)   -- (the icon's own square frame cut off: "no straight line from icon frame shows")
    b.item:SetPoint("CENTER")
    b.itemMask = b:CreateMaskTexture()
    b.itemMask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    b.itemMask:SetPoint("CENTER", b.item, "CENTER")
    b.itemMask:SetSize(25, 25)
    b.item:AddMaskTexture(b.itemMask)
    -- (engraved: a second hairline ring outside the rim with a gap of the rail's own slate between; a ready one a
    -- soft gold light behind, not a flat disc. "Polish the circles", the user, 2026-11-22)
    b.ring2 = Round(b, "BACKGROUND", -2)
    b.ring2:SetPoint("CENTER")
    b.ring2:SetSize(38, 38)
    b.gap = Round(b, "BACKGROUND", -1)
    b.gap:SetPoint("CENTER")
    b.gap:SetSize(36, 36)
    b.gap:SetVertexColor(SLATE[1], SLATE[2], SLATE[3], 1)
    b.halo = b:CreateTexture(nil, "BACKGROUND", nil, -4)
    b.halo:SetTexture(ns.MEDIA .. "World\\WorldGlow")   -- (round, soft to nothing at its rim: the pool is a wide oval)
    b.halo:SetBlendMode("ADD")
    b.halo:SetPoint("CENTER")
    b.halo:SetSize(58, 58)
    b.halo:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.22)
    b.halo:Hide()
    -- (the hover's light soft and faint, a pool, never a hard disc: "hoverglow is a hard circle. Make it fainter,
    -- blend it", the user, 2026-11-22)
    b.lit = b:CreateTexture(nil, "HIGHLIGHT")
    b.lit:SetTexture(ns.MEDIA .. "World\\WorldGlow")
    b.lit:SetBlendMode("ADD")
    b.lit:SetPoint("CENTER")
    b.lit:SetSize(46, 46)
    b.lit:SetVertexColor(BRASS[1], BRASS[2], BRASS[3], 0.14)
    b.count = b:CreateFontString(nil, "OVERLAY")
    b.count:SetFont(FRIZ, 10, "")
    b.count:SetPoint("TOP", b, "BOTTOM", 0, 0)
    -- the engraved rule under it, between it and the next: a diamond, a hairline fading out both ways
    b.sep = {}
    for k = 1, 2 do
        local tx = b:CreateTexture(nil, "ARTWORK")
        tx:SetTexture(WHITE8)
        tx:SetSize(16, 1)
        local c1 = CreateColor and CreateColor(BRASS[1], BRASS[2], BRASS[3], k == 1 and 0 or 0.6)
        local c2 = CreateColor and CreateColor(BRASS[1], BRASS[2], BRASS[3], k == 1 and 0.6 or 0)
        if not (c1 and tx.SetGradient and pcall(tx.SetGradient, tx, "HORIZONTAL", c1, c2)) then tx:SetVertexColor(BRASS[1], BRASS[2], BRASS[3], 0.35) end
        b.sep[k] = tx
    end
    b.sepDia = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.sepDia:SetTexture(ns.MEDIA .. "World\\WorldDiamond")
    b.sepDia:SetSize(5, 5)
    b.sepDia:SetVertexColor(BRASS[1], BRASS[2], BRASS[3], 0.9)
    -- (from the sign itself, a whole number down, never from the count: a ready sign has no count, and the empty
    -- line's odd height put its diamond on half a pixel, drawn taller than the rest. "Blue diamond is different from
    -- red one", the user, 2026-11-23)
    b.sepDia:SetPoint("TOP", b, "BOTTOM", 0, -16)
    b.sep[1]:SetPoint("RIGHT", b.sepDia, "LEFT", -2, 0)
    b.sep[2]:SetPoint("LEFT", b.sepDia, "RIGHT", 2, 0)
    -- (the same tooltip as the quest's pin on the map: its title, level, what is left, Shift for more. The user,
    -- 2026-11-22: "icons can get the same tooltip as hovering the questpin on map")
    b:SetScript("OnEnter", function(self)
        if self.zone then return W.ZoneSignTip(self) end
        local h = self.h
        if not h then return end
        if ns.HoverQuestGlow then pcall(ns.HoverQuestGlow, h.id) end
        if ns.QuestTooltip then
            -- (its lines what the log writes under it, "2/7 Hyacinth Mushroom", "Turn in to Alyissia.": an empty line
            -- came out as a bare "?", the user's shot, 2026-11-22, "tooltip issue")
            local lines = {}
            for _, a in ipairs(Aims(h.id, W.ZoneOf and W.ZoneOf(h.id))) do lines[#lines + 1] = { who = a.text } end
            if #lines == 0 then lines[1] = { who = h.complete and "Ready to turn in." or (h.name or "") } end
            ns.Safe("Rail mark tooltip", ns.QuestTooltip, self, {}, { { id = h.id, lines = lines } }, true)
        end
    end)
    -- (the pin tooltip's Shift redraw calls the owner's OnEnter as a method, Pin.lua ns.ShiftRefresh)
    function b:OnEnter() local f = self:GetScript("OnEnter") if f then f(self) end end
    b:SetScript("OnLeave", function(self)
        if self.zone then if GameTooltip then GameTooltip:Hide() end return end
        if ns.HoverQuestGlow then pcall(ns.HoverQuestGlow, nil) end
        if ns.QuestTooltipLeave then ns.QuestTooltipLeave() elseif GameTooltip then GameTooltip:Hide() end
    end)
    b:SetScript("OnClick", function(self, button)
        if self.zone then
            if button ~= "RightButton" then GoTo(self.zone) end
            return
        end
        local h = self.h
        if not h then return end
        if button == "RightButton" then return QuestMenu(h.id) end
        S.page, S.sel = h.id, nil
        Fold(false)
    end)
    rail.signs[i] = b
    return b
end

-- A zone's sign on a continent's rail: the crest of who holds it in brass in the ring (the log's foot wears the same
-- crest, W.crestOf), the banner's compass where none is; under it how many quests you hold there, and the turn-in
-- "?" if one is ready. The user, 2026-11-23: "On continent this bar doesnt show anything. What can we place there on
-- cont?", then "A: zones as crests"
local function ZoneSign(b, z)
    b.h, b.zone = nil, z.map
    b.item:Hide()
    b.halo:Hide()
    for _, t in ipairs({ b.rim, b.ring2, b.gap, b.face }) do t:Show() end
    local ready = z.ready > 0
    b.rim:SetVertexColor(ready and GOLD[1] or BRASS[1], ready and GOLD[2] or BRASS[2], ready and GOLD[3] or BRASS[3], ready and 0.85 or 0.5)
    b.ring2:SetVertexColor(BRASS[1], BRASS[2], BRASS[3], 0.28)
    if not b.crest then
        b.crest = {}
        for k = 1, 4 do
            local t = b:CreateTexture(nil, "ARTWORK", nil, 2)
            t:AddMaskTexture(b.itemMask)
            b.crest[k] = t
        end
    end
    for _, t in ipairs(b.crest) do t:Hide() end
    local crest = W.crestOf and W.crestOf[z.map] and W.crests[W.crestOf[z.map]]
    if crest then
        b.icon:Hide()
        W.PutCrest(b, b.crest, crest, 0, 0, 24, "CENTER", 1)
        -- (brighter brass than the foot's faint one: small, the dark crests went to mud)
        for _, t in ipairs(b.crest) do t:SetVertexColor(1, 0.84, 0.55, 1) end
    else
        if ns.CursorMask then ns.CursorMask(b, b.icon, false) end
        b.icon:SetTexture(ns.MEDIA .. "World\\EmblemCompass")
        b.icon:SetTexCoord(0, 1, 0, 1)
        b.icon:SetDesaturated(true)
        b.icon:SetVertexColor(0.84, 0.66, 0.38, 0.9)
        b.icon:ClearAllPoints()
        b.icon:SetPoint("CENTER")
        b.icon:SetSize(24, 24)
        b.icon:Show()
    end
    local mark = W.DONE_MARK and "|A:QuestTurnin:12:12:0:0|a" or ""
    b.count:SetText(z.held .. (ready and ("  " .. mark) or ""))
    Colour(b.count, TEXT)
end
-- its tooltip: the zone, then the quests you hold there, the ready ones with the "?"
function W.ZoneSignTip(b)
    if not GameTooltip then return end
    GameTooltip:SetOwner(b, "ANCHOR_LEFT")
    GameTooltip:SetText(MapName(b.zone) or "", GOLD[1], GOLD[2], GOLD[3])
    local list = {}
    for _, h in ipairs(W.Held()) do if h.map == b.zone then list[#list + 1] = h end end
    table.sort(list, function(x, y)
        if (x.complete and true or false) ~= (y.complete and true or false) then return not x.complete end
        return (x.name or "") < (y.name or "")
    end)
    for _, h in ipairs(list) do
        GameTooltip:AddLine((h.name or "") .. (h.complete and ("  " .. (W.DONE_MARK or "")) or ""), TEXT[1], TEXT[2], TEXT[3])
    end
    GameTooltip:Show()
end

-- a mark's face and ring for its quest
local function RailMark(b, h)
    b.zone = nil
    if b.crest then for _, t in ipairs(b.crest) do t:Hide() end end
    b.icon:SetDesaturated(false)
    local _, frac = Sign(h)
    local have, need = 0, 0
    local ok, objs = pcall(function() return C_QuestLog.GetQuestObjectives(h.id) end)
    for _, o in ipairs(ok and objs or {}) do
        local n, m = tonumber(o.numFulfilled), tonumber(o.numRequired)
        if m and m > 0 then have, need = have + math.min(n or 0, m), need + m end
    end
    local ready = h.complete and true or false   -- (no ring of beads: "count is enough", the user)
    b.rim:SetVertexColor(ready and GOLD[1] or BRASS[1], ready and GOLD[2] or BRASS[2], ready and GOLD[3] or BRASS[3], ready and 0.85 or 0.5)
    b.ring2:SetVertexColor(BRASS[1], BRASS[2], BRASS[3], 0.28)
    -- (a ready one: the "?" alone, larger, on a faint gold light, no rings and no disc: "Does it really need a ring at
    -- all when its a complete", the user, 2026-11-22)
    for _, t in ipairs({ b.rim, b.ring2, b.gap, b.face }) do t:SetShown(not ready) end
    b.halo:SetShown(ready)
    b.icon:SetSize(20, 20)   -- (30 was "Too big, loses resolution and gets some weird lines", the user)
    -- (the turn-in "?" stands 1.5 of its 32 to the right in Forever's own art (QuestTurnin, measured): set back so it
    -- sits in the middle, "Im sure it still sits off-center", the user)
    b.icon:ClearAllPoints()
    b.icon:SetPoint("CENTER")
    -- the face: the item it asks for, else the map's own spot icon (a kill, a talk, the hand-in's "?")
    local item = not ready and ns.QuestObjectiveItem and ns.QuestObjectiveItem(h.id)
    local icon = item and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item)
    if icon then
        b.item:SetTexture(icon)
        b.item:Show()
        b.icon:Hide()
    else
        b.item:Hide()
        RailIcon(b, h)
        -- (a ready one: the "?" cut to its own glyph out of Forever's atlas (QuestTurnin: file 1121272, its cell at
        -- 923, 514; the glyph at 9-26 across, 2-30 down, measured), so the glyph's own middle is the sign's: "Still
        -- misses", the user. After RailIcon, which lays the whole square atlas: cut before it, the square was drawn
        -- into the glyph's 16 by 25, "These seem squeezed", the user, 2026-11-23)
        if ready and pcall(b.icon.SetTexture, b.icon, 1121272) then
            -- (its own shape, 19 by 30 with the dark rim, at near its own size: 13 by 21 read squished, "Oh no! you
            -- squishe dit", the user)
            b.icon:SetTexCoord(931 / 1024, 950 / 1024, 515 / 1024, 545 / 1024)
            b.icon:SetSize(16, 25)
        end
        b.icon:Show()
    end
    -- (the Lab's one log: the quest you are on, its outer ring lit; a ready one has no rings)
    if not ready and W.Lead() == h.id then b.ring2:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.85) end
    b.count:SetText(ready and "" or (need > 0 and (have .. "/" .. need)) or "")   -- (no "ready" under the "?": it says so)
    Colour(b.count, ready and GOLD or TEXT)
end

local function MakeWin()
    win = CreateFrame("Frame", "WaymarkWorldWindow", UIParent)
    win:EnableMouse(false)   -- (it spans the map: a click the map lets through must still reach the world)
    win:Hide()
    -- (the frame set is the map's child, Place: it goes with the window, not with the map)
    win:SetScript("OnHide", function()
        if win.set then win.set:Hide() end
        if win.dress then win.dress:Hide() end
    end)
    if ns.debugFrames then ns.debugFrames.worldWindow = win end
    win.top, win.bottom, win.thin, win.side = Glass(win), Glass(win), Glass(win), Glass(win)
    win.top:SetPoint("TOPLEFT")
    win.top:SetPoint("BOTTOMRIGHT", win, "TOPRIGHT", 0, -BAR)
    win.bottom:SetPoint("BOTTOMLEFT")
    win.bottom:SetPoint("TOPRIGHT", win, "BOTTOMRIGHT", 0, EDGE)
    win.lines = {}
    for i, e in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = win:CreateTexture(nil, "BORDER")
        t:SetColorTexture(BRASS[1], BRASS[2], BRASS[3], i == 1 and 0.95 or 0.55)
        t:SetPoint(e[1])
        t:SetPoint(e[2])
        if i <= 2 then t:SetHeight(1) else t:SetWidth(1) end
        win.lines[i] = t
    end
    win.seam = win:CreateTexture(nil, "BORDER")
    win.seam:SetColorTexture(BRASS[1], BRASS[2], BRASS[3], 0.28)
    win.seam:SetWidth(1)

    bar = CreateFrame("Frame", nil, win)
    -- The bar is the window's handle (the user, 2026-11-21: "I can't drag it by its frame ... Worldmap moved by
    -- frame, right click frame"): a drag moves the map (and the window with it), a right-click opens the map's
    -- menu, as the map's own header did. Its buttons lie over it and keep their own clicks.
    bar:EnableMouse(true)
    bar:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and ns.MapMoveStart then ns.Safe("World window move", ns.MapMoveStart) end
    end)
    bar:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            if ns.MapMoveStop then ns.Safe("World window move", ns.MapMoveStop) end
        elseif button == "RightButton" and Options then
            Options(bar.opts)   -- (the world map's own panel, not the small map's menu)
        end
    end)
    bar.ground = bar:CreateTexture(nil, "BACKGROUND")   -- (its own glass, only where it has come in over the map: Place)
    bar.ground:SetColorTexture(SLATE[1], SLATE[2], SLATE[3], 0.93)
    bar.ground:Hide()
    bar:SetPoint("TOPLEFT", 8, 0)
    bar:SetPoint("TOPRIGHT", -6, 0)
    bar:SetHeight(BAR)
    bar.crumbs = {}
    for i = 1, 3 do
        bar.crumbs[i] = TextButton(bar, "", function(self)
            if self.map then
                S.page, S.sel = nil, nil
                GoTo(self.map)
            end
        end)
    end
    -- (2026-11-20, the user in game: "X is tiny and.. functional", and of the word "fold >": "Arrow in the
    -- opposite direction than the questlog would fold".) The close is the map's own red X, the same art and
    -- size; the map's X inside its art rests while the window is up (Tick), so there is one. The fold is a
    -- brass chevron pointing the way the log goes: toward the map to fold, away from it to come back.
    -- (2026-11-21, the user: "The X to close is sitting badly in this frame": it filled the bar's height and
    -- leaned on the frame's corner. Now the fold chevron's size, centred in the bar, clear of the corner: Place)
    bar.close = CreateFrame("Button", nil, bar)
    bar.close:SetSize(20, 20)
    for _, s in ipairs({ { "Normal", "redbutton-exit-2x" }, { "Pushed", "redbutton-exit-pressed-2x" }, { "Highlight", "redbutton-highlight-2x" } }) do
        bar.close["Set" .. s[1] .. "Texture"](bar.close, WHITE8)
        local tex = bar.close["Get" .. s[1] .. "Texture"](bar.close)
        if tex and ns.SetArt then
            ns.SetArt(tex, s[2])
            tex:ClearAllPoints()
            tex:SetPoint("CENTER")
            tex:SetSize(16, 16)
        end
    end
    bar.close:SetScript("OnClick", function() if ns.ToggleBigMap then ns.Safe("World window close", ns.ToggleBigMap) end end)
    -- (2026-11-21, the user: "Can we work the red X into the engravers frame, or nah? Its currently just plotted
    -- there, needs to look like a complete package". Of mockups\world-window-3.html: "X1 and X2"; then of the seal:
    -- "Take the wax seal out". The setting `close`: "boss", the Engraver's own top-right corner with its star cut as
    -- an X, lacquer red when pointed at (laid exactly over the frame's corner piece: Place); "game", the game's red
    -- X. With a frame set that is not the Engraver's, the boss falls back to the game's X.)
    local function Close() if ns.ToggleBigMap then ns.Safe("World window close", ns.ToggleBigMap) end end
    bar.boss = CreateFrame("Button", nil, bar)   -- (its art is the set's own, laid in Place)
    bar.boss:SetScript("OnClick", Close)
    bar.boss:Hide()

    bar.fold = CreateFrame("Button", nil, bar)
    bar.fold:SetSize(22, 22)   -- (placed in Place: at the seam, where it stays whether the log is out or folded)
    -- (a book in the cog's brass: open while the log is out, shut when it is folded. The user, 2026-11-21, of the
    -- chevron: "ive clicked it for back many times now"; 2026-11-22, of the panel glyph that replaced it, "kinda
    -- microsoft corporate style", then of mockups/world-bar.html: "Sure do the book". Art: tools/world_top/bar_sheet.py)
    bar.fold.art = bar.fold:CreateTexture(nil, "ARTWORK")
    bar.fold.art:SetSize(17, 17)
    bar.fold.art:SetPoint("CENTER")
    bar.fold.lit = bar.fold:CreateTexture(nil, "HIGHLIGHT")
    bar.fold.lit:SetAllPoints(bar.fold.art)
    bar.fold.lit:SetBlendMode("ADD")
    bar.fold.lit:SetAlpha(0.45)
    bar.fold:SetScript("OnClick", function()
        Fold()
        if Refresh then Refresh() end
    end)
    bar.fold:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(Folded() and "Unfold the quest log" or "Fold the quest log", 1, 1, 1)
        GameTooltip:Show()
    end)
    bar.fold:SetScript("OnLeave", function(self) if GameTooltip and GameTooltip:GetOwner() == self then GameTooltip:Hide() end end)
    bar.count = bar:CreateFontString(nil, "OVERLAY")
    bar.count:SetFont(FRIZ, 11.5, "")
    Colour(bar.count, SOFT)
    -- the cog: the world map's own options, in place of the map's gear and toggles (Options)
    bar.opts = CreateFrame("Button", nil, bar)
    bar.opts:SetSize(20, 20)
    bar.opts:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bar.opts.art = bar.opts:CreateTexture(nil, "ARTWORK")
    bar.opts.art:SetTexture(COG_ART, nil, nil, "TRILINEAR")   -- (smoothed: the user, "a tiny bit pixely")
    bar.opts.art:SetSize(15, 15)
    bar.opts.art:SetPoint("CENTER")
    bar.opts.lit = bar.opts:CreateTexture(nil, "HIGHLIGHT")
    bar.opts.lit:SetTexture(COG_ART, nil, nil, "TRILINEAR")
    bar.opts.lit:SetBlendMode("ADD")
    bar.opts.lit:SetAllPoints(bar.opts.art)
    bar.opts.lit:SetAlpha(0.45)
    bar.opts:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if ns.OpenOptionsPage then ns.Safe("World window settings", ns.OpenOptionsPage, "bigworld") elseif ns.ToggleOptions then ns.Safe("World window settings", ns.ToggleOptions) end
            return
        end
        if Options then Options(self) end
    end)
    bar.opts:SetScript("OnEnter", function(self)
        if not GameTooltip or (opts and opts:IsShown()) then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("World map", 1, 1, 1)
        if ns.Hints then ns.Hints({ { "Click", "its settings" }, { "Right-click", "all of Waymark's settings" } }) end
        GameTooltip:Show()
    end)
    bar.opts:SetScript("OnLeave", function(self) if GameTooltip and GameTooltip:GetOwner() == self then GameTooltip:Hide() end end)

    rail = CreateFrame("Frame", nil, win)
    rail.signs = {}
    rail.more = rail:CreateFontString(nil, "OVERLAY")
    rail.more:SetFont(FRIZ, 10.5, "")
    rail.more:SetPoint("BOTTOM", 0, 6)
    Colour(rail.more, SOFT)
    rail.ring = Round(rail, "BACKGROUND", -1)
    rail.ring:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
    rail.ring:SetSize(32, 32)
    rail.ring:Hide()

    -- a controller: the window is up folded or not, so its buttons come here (enabled in Tick)
    win:SetScript("OnGamePadButtonDown", function(self, button)
        PassOn(self, button)
        if ns.WorldPanelPad then ns.Safe("World log pad", ns.WorldPanelPad, button) end
    end)
    win:SetScript("OnGamePadButtonUp", function(_, button)
        if ns.WorldPanelPadUp then ns.Safe("World log pad", ns.WorldPanelPadUp, button) end
    end)
end

-- The zone's name, and the top of the window ----------------------------------------------------
-- (2026-11-20, the user in game: "Zone names look uninspiring", the bar and the list's title. Five faces were
-- drawn, mockups\world-titles.html; the user: "Try more than one imo. All except D.") The setting `title`, the
-- face the name is set in:
--   morpheus   the game's quest title face, bigger, in quest gold with a soft shadow (A, the default)
--   caps       spaced capitals in brass; with no top, over a hairline that fades at both ends, the levels under (B)
--   felipa     Waymark's own face in pale parchment, cut into the glass: dark above, a lit lip below (C)
--   plain      as first built: Friz in gold
-- Then the user asked for fun with the whole top ("This is where we get to have fun uknow"): five ways,
-- mockups\world-top.html. "I think we should try many and prune down to the best." The setting `top`:
--   glass      the zone's own land through the glass under the name (was the face "land", E): in pencil, and
--              in paint where you have explored, so it colours in as you go; the map's hour tint; a sheen; the
--              name in a shadow pool; an engraved rule closed by a diamond that fills as the zone's quests are
--              done, gold when all are (the default)
--   neat       the bar as a chart's neatline, ticks along it and the steps in plates cut into it; the name
--              in capitals between two ruled lines
--   cartouche  the name in an engraved cartouche: scrolls, leaves, a shell crest, a drop (the user: "the
--              weakest atm, but we can make it more ornamental and fancy")
--   (horizon, the zone's skyline under the name, was tried and taken out, 2026-11-21: "The horizon view
--              unfortunately just aint it. The ridgelines just doesnt give anything, and I've decided we're not
--              doing the ridgelines like this.")
--   none       the name alone, in its face
-- The bar's last step, the zone you look at, wears the name's face.
-- Cost: fonts and a few textures, laid when the zone, the width or a choice changes, nothing per frame.
-- "glass" lays the land's tiles once a zone (about 6 to 24 textures).
local TITLE_STYLES = { "morpheus", "caps", "felipa", "plain" }
local TOPS = { "glass", "neat", "cartouche" }   -- ("none" scrapped 2026-11-22)   -- ("Title block" pruned by the user, 2026-11-21)
local PARCH = { 0.91, 0.86, 0.75 }
local CAPS_GOLD = { 0.84, 0.70, 0.41 }
local LAB = ns.MEDIA .. "World\\"
-- (the small map's arrow with the world map picked, MapControls' RefreshBigButton: the game's red button with a globe,
-- tools/world_top/red_world_art.py. Named here so its path stays in the Lab: a release build's file check)
ns.WORLD_ARROW_ART = { up = LAB .. "RedWorld", down = LAB .. "RedWorldDown", glyph = LAB .. "MapGlyph" }
-- lettering on the map's own paper (Lab/Minutes.lua's manner): pale gold, an umber edge; and a texture shaded
-- black from one side to the other, `from` at its bottom or left, `to` at its top or right
local INK = { pale = { 0.96, 0.89, 0.72 }, umber = { 0.20, 0.13, 0.07 } }
local function Shade(t, dir, from, to)
    t:SetColorTexture(1, 1, 1, 1)
    if t.SetGradient and CreateColor and pcall(t.SetGradient, t, dir, CreateColor(0, 0, 0, from), CreateColor(0, 0, 0, to)) then return end
    t:SetColorTexture(0, 0, 0, (from + to) / 2)
end
local function Morpheus() return ns.FONT_MORPHEUS or "Fonts\\MORPHEUS.ttf" end
local function Felipa() return ns.MEDIA .. "Fonts\\Felipa-Regular.ttf" end
local function TitleStyle()
    local s = Cfg().title or "morpheus"
    for _, k in ipairs(TITLE_STYLES) do if k == s then return s end end
    return "morpheus"
end
local function TopStyle()
    local s = Cfg().top or "glass"
    for _, k in ipairs(TOPS) do if k == s then return s end end
    return "glass"
end
-- The placepath (the bar's Azeroth, Eastern Kingdoms, zone), the setting `path`. Of mockups\world-window-3.html the
-- user, 2026-11-21: "A B D are nice", then "D is not nice on the wheel and the arrow. But its nice with the text on
-- the map in the corner". So, each with the map shaded where it slips under the bar and along the seam:
--   neat   the neatline: a ruled foot with its ticks, and the seam graduated in minutes on foot (B)
--   map    the path lettered on the map's own paper in its corner, pale gold with an umber edge, the zone's name
--          under it, over a soft darkening (D). No bar: the map runs up to the frame, the cog and the fold sit on
--          a small plate in the frame's top edge at the seam (L1 of mockups/world-bar.html, the user, 2026-11-22)
-- ("rule", the double rule under the bar, scrapped by the user, 2026-11-22: "Scrap the golden rule option")
-- Every path wears one face now: small capitals, the diamond between, the last step in the name's face.
-- (lettered on the map, the one way: the bar "On the frame" dropped, the user, 2026-11-22, "Lettered only"; its
-- neatline parts are left asleep below, never shown)
local function PathStyle() return "map" end
-- the bar's height: none with the path lettered on the map
local function BarH() return PathStyle() == "map" and 0 or BAR end
-- "Burning Steppes" as "B U R N I N G   S T E P P E S" (the font has no letter spacing of its own)
local function Spaced(s)
    local out = {}
    for ch in s:upper():gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch == " " and "  " or ch end
    return table.concat(out, " ")
end

-- the pieces of the tops: made once, each hidden on every draw and shown by its own top
local deco, land
local LAND = { pool = {}, used = 0 }
local LAND_H, LAND_SPAN = 64, 0.55
local function Brass(parent, layer, a)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetColorTexture(BRASS[1], BRASS[2], BRASS[3], a or 0.8)
    return t
end
local function Fade(t, a, leftToRight)
    local c1 = CreateColor and CreateColor(BRASS[1], BRASS[2], BRASS[3], leftToRight and 0 or a)
    local c2 = CreateColor and CreateColor(BRASS[1], BRASS[2], BRASS[3], leftToRight and a or 0)
    t:SetTexture(WHITE8)
    if not (c1 and t.SetGradient and pcall(t.SetGradient, t, "HORIZONTAL", c1, c2)) then t:SetVertexColor(BRASS[1], BRASS[2], BRASS[3], a * 0.7) end
end
local function MakeDeco()
    deco = CreateFrame("Frame", nil, panel)
    deco:SetAllPoints(panel)
    deco.parts = {}
    local function Keep(t)
        deco.parts[#deco.parts + 1] = t
        return t
    end
    -- glass: the land (laid by LayLand), its sheen and the name's shadow pool; the rule and the diamond
    land = CreateFrame("Frame", nil, panel)
    land:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    land:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    land:SetHeight(LAND_H)
    if land.SetClipsChildren then land:SetClipsChildren(true) end
    land.sheet = CreateFrame("Frame", nil, land)
    land.fade = land.sheet:CreateMaskTexture()
    land.fade:SetTexture(LAB .. "WorldHeadFade", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    land.fade:SetAllPoints(land)
    land.gain = land.sheet:CreateMaskTexture()
    land.gain:SetAllPoints(land.sheet)
    land.sheen = land.sheet:CreateTexture(nil, "OVERLAY", nil, 1)
    land.sheen:SetTexture(LAB .. "WorldSheen")
    land.sheen:SetBlendMode("ADD")
    land.sheen:SetAlpha(0.09)
    land.sheen:SetAllPoints(land)
    land.sheen:AddMaskTexture(land.fade)
    land.pool = land.sheet:CreateTexture(nil, "OVERLAY", nil, 0)
    land.pool:SetTexture(LAB .. "WorldPool")
    land.pool:SetVertexColor(0, 0, 0, 0.6)
    land:Hide()
    deco.rule = { Keep(deco:CreateTexture(nil, "ARTWORK")), Keep(deco:CreateTexture(nil, "ARTWORK")) }
    Fade(deco.rule[1], 0.85, true)
    Fade(deco.rule[2], 0.85, false)
    -- the engraver's diamond: a dark ring, the brass, the hollow, and what fills it from the bottom
    deco.dia = {}
    for i, spec in ipairs({ { 13, SLATE[1], SLATE[2], SLATE[3], 1 }, { 9, BRASS[1], BRASS[2], BRASS[3], 1 },
                            { 6, SLATE[1], SLATE[2], SLATE[3], 1 }, { 6, BRASS[1], BRASS[2], BRASS[3], 1 } }) do
        local t = Keep(deco:CreateTexture(nil, "OVERLAY", nil, i))
        t:SetTexture(LAB .. "WorldDiamond")
        t:SetVertexColor(spec[2], spec[3], spec[4], spec[5])
        t:SetSize(spec[1], spec[1])
        deco.dia[i] = t
    end
    -- neat: the two ruled lines either side of the name, each closed by a short upright
    deco.neat = {}
    for i = 1, 4 do deco.neat[i] = Keep(Brass(deco, "ARTWORK", 0.75)) end
    -- cartouche: the plaque's inside, then the engraving
    deco.cartIn = Keep(deco:CreateTexture(nil, "BORDER"))
    deco.cartIn:SetTexture(LAB .. "WorldCartoucheIn")
    deco.cartIn:SetVertexColor(0.02, 0.022, 0.028, 0.72)
    deco.cart = Keep(deco:CreateTexture(nil, "ARTWORK"))
    deco.cart:SetTexture(LAB .. "WorldCartouche")
end

-- the land under the name ("glass"): the zone's own art, darkened, through a soft mask. The base and the parts
-- you have not explored in pencil (the pencilled map's way: the art grey, added to itself through the zone's
-- gain mask where it has one), the parts you have explored in paint: it colours in as you go.
local function LandTex(sub)
    LAND.used = LAND.used + 1
    local t = LAND.pool[LAND.used]
    if not t then
        t = land.sheet:CreateTexture()
        t:AddMaskTexture(land.fade)
        if t.SetSnapToPixelGrid then
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
        end
        LAND.pool[LAND.used] = t
    end
    return t
end
-- (the pencil darker than the paint: its paper is pale, and at 0.62 a mock-up showed the gold name lost on it)
local LAND_PAINT, LAND_PENCIL = { 0.58, 0.55, 0.50 }, { PENCIL[1] * 0.40, PENCIL[2] * 0.40, PENCIL[3] * 0.40 }
local function TintLand()
    local r, g, b = 1, 1, 1
    if ns.MapHourTint then
        local ok, hr, hg, hb = pcall(ns.MapHourTint)
        if ok and type(hr) == "number" then r, g, b = hr, hg, hb end
    end
    for i = 1, LAND.used do
        local t, c = LAND.pool[i], LAND.pool[i].tone
        if c then t:SetVertexColor(c[1] * r, c[2] * g, c[3] * b) end
    end
    LAND.hour = math.floor((ns.MapHourNow and ns.MapHourNow() or 12) * 4)
end
-- A continent's or the world's plaque: a figure from its own map, at (x, y) on the 1002 x 668 art, the art's width
-- across the plaque a share of it, the figure that far across the plaque (0.7 if not given), from another map's art
-- if a fifth is given. The user, 2026-11-22, of the bare plaques on Azeroth, Kalimdor and the Eastern
-- Kingdoms: "Motives here", "Something from the map?", and the ship on Azeroth's map, cropped
W.cartMotif = {
    [947] = { 592, 548, 0.30 },    -- Azeroth: the ship south of the Maelstrom
    [1414] = { 100, 188, 0.30, 0.30, 947 },   -- Kalimdor: the sea serpent west of it, on Azeroth's map
    [1415] = { 775, 68, 0.30, 0.74, 947 },    -- the Eastern Kingdoms: the kraken north of them, on Azeroth's map
    -- (0.30 of the art across, not less: the art is 1002 wide and the client has no sharper copy; closer was blurred,
    -- "Kinda oof on the resolution here", the user)
    -- (the user, 2026-11-22, with the two cropped: "kalim, kingdom"; the turtle, the sea dragon (cut by the plaque)
    -- and the coast with its rose stood here before)
}
local function LayLand(map)
    land:SetFrameLevel(panel:GetFrameLevel() + 1)
    -- (the land's own size: the strip under the name ("glass"), or the cartouche's plaque)
    local width = math.floor((land.inCart and land.cw or slot:GetWidth() or 300) + 0.5)
    local LAND_H = math.floor((land.inCart and land.ch or LAND_H) + 0.5)
    local explored = ns.ExploredOverlayKeys and map and ns.ExploredOverlayKeys(map) or {}
    local seen = 0
    for _ in pairs(explored) do seen = seen + 1 end
    local key = (map or 0) .. ":" .. width .. ":" .. LAND_H .. ":" .. seen
    land:SetShown(map ~= nil)
    if LAND.key == key then
        TintLand()
        return
    end
    LAND.key = key
    local aw, ah
    -- (a plaque's figure may come from another map's art: Kalimdor's serpent swims on Azeroth's map, motif[5])
    local motif = land.inCart and map and W.cartMotif[map]
    local art = motif and motif[5] or map
    if map and ns.MapArtSize then aw, ah = ns.MapArtSize(art) end   -- (not "a and f()": that keeps one answer)
    if not (map and aw and ah and aw > 0 and ns.MapArtLayer and ns.ZoneOverlays) then
        for i = 1, #LAND.pool do LAND.pool[i]:Hide() end
        land:Hide()
        return
    end
    -- the zone's heart: where you stand when it is your zone, else its middle a little high (its name's place)
    local px, py = 0.5, 0.42
    local here = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if here == map and C_Map.GetPlayerMapPosition then
        local pos = C_Map.GetPlayerMapPosition(map, "player")
        local x, y
        if pos and pos.GetXY then x, y = pos:GetXY() end
        if x and y and x > 0 then px, py = x, y end
    end
    -- (in the cartouche the whole zone across the plaque, more of the map: "the map gets too little space", the user)
    local s = width / ((land.inCart and 1.0 or LAND_SPAN) * aw)   -- (1.0: the whole zone across, the furthest out that still fills the plaque; 1.5 left it bare: "maybe we went too far", the user)
    if motif then s = width / (motif[3] * aw) end
    local sw, sh = aw * s, ah * s
    local left = math.max(0, math.min(sw - width, px * sw - width / 2))
    local top = math.max(0, math.min(sh - LAND_H, py * sh - LAND_H / 2))
    if motif then
        -- (the figure right of the middle, the name beside it, as the user's own crop of the ship)
        left = motif[1] / 1002 * sw - (motif[4] or 0.7) * width
        top = motif[2] / 668 * sh - LAND_H / 2
    end
    land.sheet:ClearAllPoints()
    land.sheet:SetPoint("TOPLEFT", land, "TOPLEFT", -left, top)
    land.sheet:SetSize(sw, sh)
    local gain = ns.PencilZones and ns.PencilZones[map] and true or false
    if gain and land.gainFor ~= map then
        land.gain:SetTexture(ns.MEDIA .. "Pencil\\" .. map .. ".tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        land.gainFor = map
    end
    local overlays = ns.ZoneOverlays(art) or {}
    LAND.used = 0
    local order, laid = {}, 0
    local x0, x1, y0, y1 = left / s, (left + width) / s, top / s, (top + LAND_H) / s
    for _, src in ipairs(RibSources(art)) do
        if src.x < x1 and src.x + src.w > x0 and src.y < y1 and src.y + src.h > y0 then
            local painted = motif and true or (src.k > 0 and overlays[src.k] and explored[overlays[src.k].key] or false)
            -- (two sublevels a piece, as the ribbon: its grey, then its added copies over it, under the next)
            local layer, sub = "BACKGROUND", -8
            if src.k > 0 then
                if not order[src.k] then
                    laid = laid + 1
                    order[src.k] = laid
                end
                local o = math.min(order[src.k], 15) - 1
                layer, sub = o < 8 and "BORDER" or "ARTWORK", -8 + 2 * (o % 8)
            end
            local copies = (painted or not gain) and 0 or 2
            for c = 0, copies do
                local t = LandTex()
                t:SetDrawLayer(layer, c == 0 and sub or sub + 1)
                t:SetBlendMode(c == 0 and "BLEND" or "ADD")
                if c > 0 and not t.gained then
                    t:AddMaskTexture(land.gain)
                    t.gained = true
                elseif c == 0 and t.gained then
                    t:RemoveMaskTexture(land.gain)
                    t.gained = nil
                end
                if t.SetDesaturation then t:SetDesaturation(painted and 0.15 or 1) end
                t.tone = painted and LAND_PAINT or LAND_PENCIL
                t:SetTexture(ns.MapArtFile and ns.MapArtFile(src.fid) or src.fid, nil, nil, "LINEAR")
                t:SetTexCoord(0, src.w / src.fw, 0, src.h / src.fh)
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", land.sheet, "TOPLEFT", src.x * s, -src.y * s)
                t:SetSize(src.w * s, src.h * s)
                t:Show()
            end
        end
    end
    for i = LAND.used + 1, #LAND.pool do LAND.pool[i]:Hide() end
    TintLand()
end

-- the face the name is set in (the setting `title`); returns how high its line is
local function SetFace(t, name, style, forced)
    style = forced or style
    t:SetShadowColor(0, 0, 0, 1)
    head.lip:Hide()
    if style == "caps" then
        t:SetFont(FRIZ, 14, "")
        t:SetText(Spaced(name))
        local room = (slot:GetWidth() or 300) - 2 * PAD_L - 50
        if t:GetStringWidth() > room then t:SetFont(FRIZ, 12, "") end
        if t:GetStringWidth() > room then t:SetText(name:upper()) end
        Colour(t, CAPS_GOLD)
        t:SetShadowOffset(0, -1)
        return 18
    elseif style == "felipa" then
        t:SetFont(Felipa(), 21, "")
        t:SetText(name)
        Colour(t, PARCH)
        t:SetShadowOffset(0, 1)   -- (dark above: cut into the glass)
        head.lip:SetFont(Felipa(), 21, "")
        head.lip:SetText(name)
        head.lip:SetTextColor(1, 0.93, 0.75, 0.22)
        head.lip:SetShadowOffset(0, 0)
        head.lip:Show()
        return 26
    elseif style == "plain" then
        t:SetFont(FRIZ, 16, "")
        t:SetText(name)
        Colour(t, GOLD)
        t:SetShadowOffset(1, -1)
        return 22
    end
    t:SetFont(Morpheus(), 21, "")
    t:SetText(name)
    Colour(t, GOLD)
    t:SetShadowOffset(1, -1)
    return 26
end
-- a name too long for its room: a size smaller, as far as it must go
local function Shrink(t, room)
    local w = t:GetStringWidth() or 0
    if w <= room or w <= 0 then return end
    local f, size = t:GetFont()
    t:SetFont(f, math.max(11, math.floor((size or 16) * room / w)), "")
    if head.lip:IsShown() then head.lip:SetFont(f, math.max(11, math.floor((size or 16) * room / w)), "") end
end

local function Levels(map)
    local lv = map and ns.ZoneLevels and ns.ZoneLevels[map]
    return lv and ("Levels %d to %d"):format(lv[1], lv[2]) or nil
end
-- how much of the zone's quests are done, 0 to 1, for the diamond (nil: nothing known)
local function DoneShare(map)
    if not (map and W.Tally) then return nil end
    local ok, t = pcall(W.Tally, map)
    if not (ok and t and t.all and t.all > 0) then return nil end
    return math.min(1, t.done / t.all)
end

local function DrawHead(name, map, count)
    if not deco then MakeDeco() end
    local style, top = TitleStyle(), TopStyle()
    local t = head.title
    for _, p in ipairs(deco.parts) do p:Hide() end
    for _, r in ipairs(head.rule) do r:Hide() end
    head.levels:Hide()
    head.count:Hide()   -- (the count lives in the tabs row now, small: "this isn't assasins creed", 2026-11-21)
    head.count:SetText(count or "")
    if tools.count then tools.count:SetText(count or "") end
    head.count:SetShadowColor(0, 0, 0, top == "glass" and 1 or 0)
    head.count:SetShadowOffset(1, -1)
    deco:SetFrameLevel(panel:GetFrameLevel() + 2)
    head:SetFrameLevel(panel:GetFrameLevel() + 4)
    tools:SetFrameLevel(panel:GetFrameLevel() + 4)
    t:ClearAllPoints()
    head.count:ClearAllPoints()
    head.levels:ClearAllPoints()
    head.levels:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -3)
    head.levels:SetJustifyH("LEFT")
    local width = (slot:GetWidth() or 300) - 2 * PAD_L
    local lv = Levels(map)
    if top ~= "glass" and top ~= "cartouche" then land:Hide() end
    -- (the land's place and shape: a strip under the name, or the cartouche's plaque, its inside as the mask)
    local inCart = top == "cartouche"
    if land.inCart ~= inCart then
        land.inCart = inCart
        land:ClearAllPoints()
        if inCart then
            land:SetAllPoints(deco.cart)
            land.fade:SetTexture(LAB .. "WorldCartoucheIn", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        else
            land:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
            land:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
            land:SetHeight(LAND_H)
            land.fade:SetTexture(LAB .. "WorldHeadFade", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        LAND.key = nil
    end

    if top == "glass" then
        local tall = SetFace(t, name, style)
        head:SetHeight(LAND_H - PAD_T - 4)
        t:SetPoint("TOPLEFT", head, "TOPLEFT", 2, -(LAND_H - PAD_T - 4 - tall) / 2 + 3)
        Shrink(t, width - 50)
        head.count:SetPoint("RIGHT", head, "RIGHT", 0, 2)
        LayLand(map)
        if land:IsShown() then
            land.pool:ClearAllPoints()
            land.pool:SetPoint("CENTER", t, "CENTER", 0, -1)
            land.pool:SetSize((t:GetStringWidth() or 120) + 70, tall + 22)
            land.pool:Show()
        end
        -- the rule across the land's foot, closed in its middle by the diamond
        local y = -(LAND_H - 3)
        deco.rule[1]:ClearAllPoints()
        deco.rule[1]:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD_L - 4, y)
        deco.rule[1]:SetPoint("TOPRIGHT", panel, "TOP", -8, y)
        deco.rule[1]:SetHeight(1)
        deco.rule[2]:ClearAllPoints()
        deco.rule[2]:SetPoint("TOPLEFT", panel, "TOP", 8, y)
        deco.rule[2]:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD_L + 4, y)
        deco.rule[2]:SetHeight(1)
        deco.rule[1]:Show()
        deco.rule[2]:Show()
        for i = 1, 3 do
            deco.dia[i]:ClearAllPoints()
            deco.dia[i]:SetPoint("CENTER", panel, "TOP", 0, y - 0.5)
            deco.dia[i]:Show()
        end
        -- (it fills from the bottom as the zone's quests are done, gold when all are)
        local share = DoneShare(map)
        local fill = deco.dia[4]
        if share and share > 0 then
            local c = share >= 1 and GOLD or BRASS
            fill:SetVertexColor(c[1], c[2], c[3], 1)
            fill:ClearAllPoints()
            fill:SetPoint("BOTTOM", deco.dia[3], "BOTTOM", 0, 0)
            fill:SetSize(6, 6 * share)
            fill:SetTexCoord(0, 1, 1 - share, 1)
            fill:Show()
        end

    elseif top == "neat" then
        local tall = SetFace(t, name, style)   -- (the name's own face: it was always the capitals, "font not changing")
        head:SetHeight(tall + (lv and 16 or 2))
        t:SetPoint("TOP", head, "TOP", 0, -3)
        Shrink(t, width - 70)
        local tw = t:GetStringWidth() or 100
        local mid = -math.floor(3 + tall / 2)   -- (the rules meet the name at its middle, whatever its face)
        deco.neat[1]:ClearAllPoints()
        deco.neat[1]:SetPoint("TOPLEFT", head, "TOPLEFT", 0, mid)
        deco.neat[1]:SetPoint("TOPRIGHT", head, "TOP", -tw / 2 - 10, mid)
        deco.neat[1]:SetHeight(1)
        deco.neat[2]:ClearAllPoints()
        deco.neat[2]:SetPoint("TOPLEFT", head, "TOP", tw / 2 + 10, mid)
        deco.neat[2]:SetPoint("TOPRIGHT", head, "TOPRIGHT", 0, mid)
        deco.neat[2]:SetHeight(1)
        deco.neat[3]:ClearAllPoints()
        deco.neat[3]:SetPoint("TOPLEFT", head, "TOPLEFT", 0, mid + 3)
        deco.neat[3]:SetSize(1, 7)
        deco.neat[4]:ClearAllPoints()
        deco.neat[4]:SetPoint("TOPRIGHT", head, "TOPRIGHT", 0, mid + 3)
        deco.neat[4]:SetSize(1, 7)
        for i = 1, 4 do deco.neat[i]:Show() end
        if lv then
            head.levels:ClearAllPoints()
            head.levels:SetPoint("TOP", t, "BOTTOM", 0, -5)
            head.levels:SetText(lv)
            head.levels:Show()
        end
        head.count:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, 0)

    elseif top == "cartouche" then
        local cw = math.min(width + 18, 340)
        -- (taller was tried and taken back, 2026-11-22: "cartoug size back, this one is not good")
        local ch = cw * 144 / 512
        deco.cart:ClearAllPoints()
        deco.cart:SetPoint("TOP", head, "TOP", 0, PAD_T - 2)
        deco.cart:SetSize(cw, ch)
        deco.cartIn:SetAllPoints(deco.cart)
        -- (its inside: the zone's painted land, darkened so the name reads (the user, 2026-11-22, "Try the painted
        -- land inside cartouge"); it was deep black, smoked bronze, the column's glass and clear tried and pruned)
        deco.cartIn:SetVertexColor(0.02, 0.022, 0.028, 0.5)
        land.cw, land.ch = cw, ch
        deco.cart:Show()
        deco.cartIn:Show()
        LayLand(map)
        if land:IsShown() then land.pool:Hide() end
        head:SetHeight(ch - PAD_T + 4)
        SetFace(t, name, style)
        local f, size = t:GetFont()
        t:SetFont(f, math.min(size or 19, 19), "")
        if head.lip:IsShown() then head.lip:SetFont(f, math.min(size or 19, 19), "") end
        -- (the plaque's middle is at 72 of the art's 144; the name sits a little above it, the levels under)
        local cy = -(ch * 0.5) + PAD_T - 2
        t:SetPoint("CENTER", head, "TOP", 0, cy)   -- (the name alone: "Remove the level range thing", the user)
        Shrink(t, cw * 330 / 512 - 16)
        -- (the count inside the plaque at its right, on the levels' line: below it lies the Held row's "World")
        head.count:SetPoint("RIGHT", deco.cart, "RIGHT", -cw * 92 / 512, -ch * 0.16)

    else   -- none: the name alone, in its face (the caps face brings its levels and fading rule)
        local tall = SetFace(t, name, style)
        t:SetPoint("LEFT", head, "LEFT", 0, 0)
        Shrink(t, width - 50)
        head.count:SetPoint("RIGHT")
        head:SetHeight(tall)
        if style == "caps" then
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
            if lv then
                head.levels:SetText(lv)
                head.levels:Show()
            end
            head:SetHeight(lv and 36 or 24)
            head.count:ClearAllPoints()
            head.count:SetPoint("TOPRIGHT", 0, -2)
            for _, r in ipairs(head.rule) do r:Show() end
        end
    end
end

-- the face the bar's last step wears, by the name's face
local function CrumbFace(b, last)
    local style = TitleStyle()
    if not last or style == "plain" then
        b.text:SetFont(FRIZ, 11.5, "")
    elseif style == "caps" then
        b.text:SetFont(FRIZ, 10.5, "")
    elseif style == "felipa" then
        b.text:SetFont(Felipa(), 14, "")
    else
        b.text:SetFont(Morpheus(), 14, "")
    end
end

-- a step's dress by the top: a small diamond after it ("glass"), a plate cut into the bar ("neat")
local function CrumbDress(b)
    if b.dress then return end
    b.dress = true
    b.sep = b:CreateTexture(nil, "ARTWORK")
    b.sep:SetTexture(LAB .. "WorldDiamond")
    b.sep:SetVertexColor(BRASS[1], BRASS[2], BRASS[3], 0.9)
    b.sep:SetSize(5, 5)
    b.sep:SetPoint("RIGHT", -5, 0)
    b.plate = b:CreateTexture(nil, "BACKGROUND")
    b.plate:SetColorTexture(0, 0, 0, 0.55)
    b.plate:SetPoint("TOPLEFT", 1, -2)
    b.plate:SetPoint("BOTTOMRIGHT", -1, 2)
    b.shade = b:CreateTexture(nil, "BORDER")
    b.shade:SetColorTexture(0, 0, 0, 0.9)
    b.shade:SetPoint("TOPLEFT", b.plate, "TOPLEFT")
    b.shade:SetPoint("TOPRIGHT", b.plate, "TOPRIGHT")
    b.shade:SetHeight(1)
    b.lip = b:CreateTexture(nil, "BORDER")
    b.lip:SetColorTexture(1, 0.92, 0.75, 0.12)
    b.lip:SetPoint("TOPLEFT", b.plate, "BOTTOMLEFT")
    b.lip:SetPoint("TOPRIGHT", b.plate, "BOTTOMRIGHT")
    b.lip:SetHeight(1)
end

-- the bar: World > Eastern Kingdoms > Duskwood, each step but the last a click
local function DrawBar(id, count)
    local top, path = TopStyle(), PathStyle()
    local chain, at = {}, id
    for _ = 1, 5 do
        local info = at and C_Map.GetMapInfo(at)
        if not info then break end
        table.insert(chain, 1, { at, info.name })
        at = info.parentMapID
        if not at or at == 0 then break end
    end
    while #chain > 3 do table.remove(chain, 1) end
    local folded = Folded()
    -- (the cartouche holds the zone's name: with the log open the bar stops at the continent)
    -- (and then the continent is NOT dressed as the last step: in the name's face and in capitals, Felipa and the
    -- game's title face went wild, "EASTERN KINGDOMS" in big italic capitals. The user, in game, 2026-11-21)
    local dropped = top == "cartouche" and not folded and #chain > 1
    if dropped then table.remove(chain) end
    local last, first
    for i, b in ipairs(bar.crumbs) do
        local cr = chain[i]
        b:SetShown(cr ~= nil)
        CrumbDress(b)
        b.sep:Hide()
        b.plate:Hide()
        b.shade:Hide()
        b.lip:Hide()
        if cr then
            local final = i == #chain and not dropped
            b.map = not final and cr[1] or nil
            local word = cr[2]
            -- (the neatline's steps had dark plates and one face: "Top bar dark boxes, font not changing", the user
            -- in game, 2026-11-21. Now every top's: small capitals, the diamond between, the last in the name's face)
            local lettered = path == "map"
            b.rest = lettered and INK.pale or nil
            if final then
                if lettered then
                    local f, size = Morpheus(), 22
                    local style = TitleStyle()
                    if style == "felipa" then f, size = Felipa(), 24 elseif style == "plain" then f, size = FRIZ, 18 elseif style == "caps" then f, size = FRIZ, 15 end
                    b.text:SetFont(f, size, "")
                    if style == "caps" then word = Spaced(word) end
                else
                    CrumbFace(b, true)
                    if TitleStyle() == "caps" then word = word:upper() end
                end
                b.text:SetText(word)
                b:SetSize(b.text:GetStringWidth() + 10, lettered and 28 or 18)
            else
                b.text:SetFont(FRIZ, lettered and 9 or 10, "")
                b.text:SetText(lettered and Spaced(word) or word:upper())
                b:SetSize(b.text:GetStringWidth() + 26, lettered and 14 or 18)
                -- (the diamond after every step that has another after it on its line)
                b.sep:SetShown(i < #chain and not (lettered and i == #chain - 1 and not dropped))
                local sc = lettered and INK.pale or BRASS
                b.sep:SetVertexColor(sc[1], sc[2], sc[3], 0.9)
            end
            if lettered then
                b.text:SetShadowColor(INK.umber[1], INK.umber[2], INK.umber[3], 1)
            else
                b.text:SetShadowColor(0, 0, 0, final and 1 or 0)
            end
            b.text:SetShadowOffset(1, -1)
            b.text:ClearAllPoints()
            b.text:SetPoint("LEFT", 5, 0)
            b:Mark(final and top ~= "cartouche" and not lettered)
            b.under:Hide()
            b:ClearAllPoints()
            if lettered then
                -- (on the map's corner: the steps on a line, the zone's name under them)
                local face = Face()
                if final and first then
                    b:SetPoint("TOPLEFT", first, "BOTTOMLEFT", -2, 1)
                elseif last then
                    b:SetPoint("LEFT", last, "RIGHT", 0, 0)
                elseif slot.side == "left" then
                    -- (the log on the left: the book and the cog stand in this corner by the seam. Lab/WorldAlone.lua)
                    b:SetPoint("TOPLEFT", face, "TOPLEFT", 66, -12)
                else
                    b:SetPoint("TOPLEFT", face, "TOPLEFT", 30, -12)   -- (clear of the frame's corner ornament)
                end
                if not final then first = first or b end
            elseif last then
                b:SetPoint("LEFT", last, "RIGHT", 0, 0)
            elseif slot.side == "left" then
                b:SetPoint("LEFT", bar.count, "RIGHT", 10, 0)   -- (the log on the left: the path starts over the map, after the fold, the cog and the count)
            else
                b:SetPoint("LEFT", 0, 0)
            end
            if not (lettered and final) then last = b end
        end
    end
    -- the bar's foot and the map slipping under it (every path): a shade down from the bar and in from the seam
    local face = Face()
    if not bar.shade then
        bar.shade = bar:CreateTexture(nil, "BACKGROUND")
        bar.shadeSeam = bar:CreateTexture(nil, "BACKGROUND")
        bar.vig = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
        bar.vig:SetTexture(LAB .. "WorldPool")
        bar.vig:SetVertexColor(0.03, 0.025, 0.02, 0.78)
        bar.rule1 = bar:CreateTexture(nil, "BORDER")
        bar.rule1:SetColorTexture(0.84, 0.66, 0.38, 0.95)
        bar.rule2 = bar:CreateTexture(nil, "BORDER")
        bar.rule2:SetColorTexture(BRASS[1], BRASS[2], BRASS[3], 0.5)
        bar.rule1:SetHeight(1)
        bar.rule2:SetHeight(1)
    end
    Shade(bar.shade, "VERTICAL", 0, 0.62)
    bar.shade:SetShown(path ~= "map")   -- (no bar to slip under)
    bar.shade:ClearAllPoints()
    bar.shade:SetPoint("TOPLEFT", face, "TOPLEFT", 0, 0)
    bar.shade:SetPoint("TOPRIGHT", face, "TOPRIGHT", 0, 0)
    bar.shade:SetHeight(18)
    bar.shadeSeam:ClearAllPoints()
    bar.shadeSeam:SetWidth(22)
    if slot.side == "left" then
        Shade(bar.shadeSeam, "HORIZONTAL", 0.5, 0)
        bar.shadeSeam:SetPoint("TOPLEFT", face, "TOPLEFT", 0, 0)
        bar.shadeSeam:SetPoint("BOTTOMLEFT", face, "BOTTOMLEFT", 0, 0)
    else
        Shade(bar.shadeSeam, "HORIZONTAL", 0, 0.5)
        bar.shadeSeam:SetPoint("TOPRIGHT", face, "TOPRIGHT", 0, 0)
        bar.shadeSeam:SetPoint("BOTTOMRIGHT", face, "BOTTOMRIGHT", 0, 0)
    end
    bar.vig:SetShown(path == "map")
    if path == "map" then
        bar.vig:ClearAllPoints()
        local w = math.min(420, (face:GetWidth() or 600) * 0.6)
        bar.vig:SetSize(w, 150)
        bar.vig:SetPoint("CENTER", face, "TOPLEFT", w * 0.28, -26)
    end
    for i, t in ipairs({ bar.rule1, bar.rule2 }) do
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", win, "TOPLEFT", 1, -(BAR - 5 + 3 * (i - 1)))
        t:SetPoint("TOPRIGHT", win, "TOPRIGHT", -1, -(BAR - 5 + 3 * (i - 1)))
        t:SetShown(false)   -- (the "rule" path scrapped; kept for the bar's code to stay one shape)
    end
    -- the neatline: a brass rule along the bar's foot with ticks standing on it, a long one every 128 pixels
    if not bar.neat then
        bar.neat = bar:CreateTexture(nil, "BORDER")
        bar.neat:SetColorTexture(BRASS[1], BRASS[2], BRASS[3], 0.85)
        bar.neat:SetHeight(1)
        bar.neat:SetPoint("BOTTOMLEFT", win, "TOPLEFT", 1, -BAR)
        bar.neat:SetPoint("BOTTOMRIGHT", win, "TOPRIGHT", -1, -BAR)
        bar.ticks = bar:CreateTexture(nil, "BORDER")
        bar.ticks:SetTexture(LAB .. "WorldTicks", "REPEAT", "CLAMP")
        if bar.ticks.SetHorizTile then bar.ticks:SetHorizTile(true) end
        bar.ticks:SetVertexColor(BRASS[1], BRASS[2], BRASS[3], 0.75)
        bar.ticks:SetHeight(8)
        bar.ticks:SetPoint("BOTTOMLEFT", bar.neat, "TOPLEFT", 0, 0)
        bar.ticks:SetPoint("BOTTOMRIGHT", bar.neat, "TOPRIGHT", 0, 0)
    end
    bar.neat:SetShown(path == "neat")
    bar.ticks:SetShown(path == "neat")
    bar.count:SetText("")   -- (no count on the bar: it is in the tabs row, small)
    -- (the book: open while the log is out, shut when folded)
    local f = bar.fold
    local art = LAB .. (folded and "WorldBookShut" or "WorldBookOpen")
    if f.artFor ~= art then
        f.artFor = art
        f.art:SetTexture(art, nil, nil, "TRILINEAR")
        if f.shadow then f.shadow:SetTexture(art .. "Shadow", nil, nil, "TRILINEAR") end
        f.lit:SetTexture(art, nil, nil, "TRILINEAR")
    end
    f.open = not folded
end

-- The margin (2026-11-22, the user: "Can you get them ingame?"). Folded, the rail is the zone's drawing: one pen
-- scene, far at the top, near at the foot, the land inked and each main questline's part in pencil until all its
-- quests are turned in, then inked and washed. Art only: no hovers, no marks. Drawn by tools/world_top/margin_zone.py,
-- baked by tools/world_top/margin_bake.py into Media/Lab/Margin/<Zone>.blp (the strip on the left, each part's inked
-- patch on the right) and the table below. A zone without a drawing keeps the round signs. Notes:
-- mockups/world-map-level3-notes.md (the margin).
-- MARGIN DATA (tools/world_top/margin_bake.py writes this block)
-- The outline of a zone (on its continent) or a continent (on Azeroth): the shape the game itself lights when you
-- point at it on the map above (C_Map.GetMapHighlightInfoAtPosition), asked once a map. nil: none to be had
W.outlines = {}
-- (our own, from the zone map's land, where the game's leaves things out: tools/world_top/outline_art.py. The user,
-- 2026-11-22: "hoverglow doesnt highlight teldrassils roots ... just mark inside the blue")
-- (Teldrassil's: the user's own line, drawn by hand on its zone map, 2026-11-22: "There you go"; two colour masks
-- before it failed, "Roots are flat". false here: none, the compass instead)
W.ownOutline = { [1438] = { 512, 341 } }
-- (off: the outline in the log's foot, the game's shapes and Teldrassil's drawn line alike, "Falls kinda flat, i think
-- the idea just isnt really gonna work x)", the user, 2026-11-22. The compass and the rose stand there again)
W.outlineOn = false
-- A zone's emblem: the crest of the people who hold it, the game's own art (the archaeology race crests, in the
-- client). The user, 2026-11-22: "back to emblems!", "Who runs teldrassil? night elves", "Find some nelf shit".
-- Then "YES! Whoever controls the zone gets the crest, or simmilar. Whoever is central", and "your pick!" to the plan
-- in mockups/world-crests-found.png. A crest: one file (`file`, its art `size`) or the credits' 2 x 2 tiles
-- (`tiles`, 512 x 512), `box` the crest's part of it in pixels; `add`: an opaque one, drawn added so its dark
-- ground goes; `soft`: an oval fade round it (the lion's banner cloth). A zone with none keeps the banner's compass
local ARCH, CRED = "Interface\\ARCHEOLOGY\\Arch-Race-", "Interface\\Glues\\CREDITS\\"
W.crests = {
    nightelf = { file = ARCH .. "NightElfBIG", size = { 256, 512 }, box = { 5, 28, 235, 265 } },
    dwarf = { file = ARCH .. "DwarfBIG", size = { 256, 512 }, box = { 6, 19, 232, 285 } },
    troll = { file = ARCH .. "TrollBIG", size = { 256, 512 }, box = { 4, 37, 234, 261 } },
    blackrock = { file = ARCH .. "DraenorOrcBIG", size = { 256, 512 }, box = { 4, 68, 234, 232 } },
    demons = { file = ARCH .. "DemonsBIG", size = { 256, 512 }, box = { 4, 47, 236, 253 } },
    fossil = { file = ARCH .. "FossilBIG", size = { 256, 512 }, box = { 29, 34, 217, 263 } },
    scarab = { file = ARCH .. "NerubianBIG", size = { 256, 512 }, box = { 4, 27, 234, 272 } },
    ogre = { file = ARCH .. "OgreBIG", size = { 256, 512 }, box = { 32, 13, 208, 286 } },
    highborne = { file = ARCH .. "HighborneNightElvesBIG", size = { 256, 512 }, box = { 28, 43, 212, 257 } },
    explorer = { file = ARCH .. "MiscBIG", size = { 256, 512 }, box = { 12, 4, 250, 280 } },
    tauren = { tiles = CRED .. "Taurencrest", box = { 59, 23, 464, 506 } },
    forsaken = { tiles = CRED .. "ForsakenCrest", box = { 75, 30, 426, 462 }, add = true },
    scourge = { tiles = CRED .. "undeadcrest", box = { 52, 16, 464, 496 } },
    horde = { tiles = CRED .. "HordeBanner", box = { 17, 30, 402, 511 } },
    alliance = { tiles = CRED .. "Acrest", box = { 27, 10, 480, 509 } },   -- (the lion shield, the gryphons, the hammer: "Crest anywhere there is this lion", the user)
}
W.crests.stormpike = W.crests.dwarf   -- (the Stormpike Guard are Alterac's dwarves; their own banner was not found)
W.crestOf = {}
for crest, maps in pairs({
    nightelf = { 1438, 1457, 1439, 1440, 1450 },               -- Teldrassil, Darnassus, Darkshore, Ashenvale, Moonglade
    dwarf = { 1426, 1455, 1432, 1437, 1425, 1427 },            -- Dun Morogh, Ironforge, Loch Modan, Wetlands, Hinterlands, Searing Gorge
    alliance = { 1429, 1453, 1436, 1433, 1431, 1417, 1424, 1445 },   -- Elwynn, Stormwind, Westfall, Redridge, Duskwood, Arathi, Hillsbrad, Dustwallow
    forsaken = { 1420, 1458, 1421 },                           -- Tirisfal, Undercity, Silverpine
    scourge = { 1422, 1423 },                                  -- the Plaguelands
    horde = { 1411, 1454, 1413, 1435 },                        -- Durotar, Orgrimmar, the Barrens, Swamp of Sorrows
    tauren = { 1412, 1456, 1441, 1442 },                       -- Mulgore, Thunder Bluff, Thousand Needles, Stonetalon
    troll = { 1434 },                                          -- Stranglethorn
    blackrock = { 1428 },                                      -- Burning Steppes
    demons = { 1448, 1419 },                                   -- Felwood, the Blasted Lands
    fossil = { 1449 },                                         -- Un'Goro
    scarab = { 1451 },                                         -- Silithus
    highborne = { 1447, 1444 },                                -- Azshara, Feralas
    ogre = { 1416 },                                           -- Alterac
    explorer = { 1418 },                                       -- the Badlands
}) do
    for _, m in ipairs(maps) do W.crestOf[m] = crest end
end
-- (the compass stays, "For now!": Tanaris, Winterspring, Desolace, Deadwind)
W.crestAlpha = 0.16
W.crestH = 200
-- A quarrel: two sides' motifs, cut from their banners without cloth or colour (tools/world_top/motif_art.py), the first
-- high on the left, the second low on the right, a crack through the glass between them (crack_art.py). A continent
-- its main one, a contested zone its own. The user, 2026-11-22: "Crests on kalimdor get the main disputes? (warsong
-- gulch)", "We want only the motive. And not the colors either", "diagonal and a slice/crack in the glass between would
-- be so sick", "Hillsbrad is famously contested between the alliance and the plagueloving forsaken"
W.quarrels = {
    [1414] = { "nightelf", "horde", crack = 1 },                   -- Kalimdor: crests; the maw "better used for ashenvale", the user
    [1415] = { "stormpike", "forsaken", crack = 3, mirror = true },  -- the Eastern Kingdoms: "Stormpike vs forsaken", the user
    [947] = { "alliance", "horde", crack = 2 },                      -- Azeroth: "crests on azeroth"
    [1440] = { "Silverwing", "Warsong", crack = 4, mirror = true },  -- Ashenvale: the gulch's own forest
    [1424] = { "alliance", "forsaken", crack = 2, mirror = true },   -- Hillsbrad: Southshore and Tarren Mill
    [1417] = { "alliance", "horde", crack = 3 },                     -- Arathi: Refuge Pointe and Hammerfall
}
-- (each its own break, WorldCrack1-4: a struck corner, a clean slice, a shatter, another corner; mirrored, the blow
-- comes from the other corner and the sides swap halves. "we need different glassbreaks", the user)
-- (a side in lower case is a crest from W.crests, else a cut motif: the Alliance's and the Horde's motifs were flat
-- beside Silverwing's tree and the Warsong maw, so their crests stand there, "this one pales in comparison. Because of
-- the emblems", the user, 2026-11-22)
W.motifSize = { Silverwing = { 303, 380 }, Warsong = { 373, 360 }, Alliance = { 352, 300 }, Forsaken = { 303, 310 }, Horde = { 352, 173 } }
W.motifAlpha, W.motifBox, W.crackAlpha, W.sideCrestH = 0.16, 130, 0.2, 150   -- (the crack 10% down: "tone down the brights ... Like 10%")
-- one crest into a set of four textures, its middle at (x, y) above the panel's bottom, h high; returns its width
-- (point: the frame's point it is measured from, "BOTTOM" when not given; alpha: W.crestAlpha when not given)
function W.PutCrest(panel, set, crest, x, y, h, point, alpha)
    point = point or "BOTTOM"
    local b = crest.box
    local k = h / (b[4] - b[2])
    local function Tint(t)
        t:SetDesaturated(true)
        t:SetBlendMode(crest.add and "ADD" or "BLEND")
        t:SetVertexColor(0.84, 0.66, 0.38, alpha or W.crestAlpha)
        t:Show()
    end
    if crest.tiles then
        -- (the 512 x 512 picture's four tiles, laid so the crest's middle is at x, y)
        local cx, cy = (b[1] + b[3]) / 2, (b[2] + b[4]) / 2
        for i = 1, 4 do
            local t = set[i]
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            local ok, has = pcall(t.SetTexture, t, crest.tiles .. i)
            if ok and has ~= false then   -- (a tile the client lacks stays hidden, not an old picture)
                t:SetTexCoord(0, 1, 0, 1)
                t:SetSize(256 * k, 256 * k)
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", panel, point, x + (col * 256 - cx) * k, y - (row * 256 - cy) * k)
                Tint(t)
            end
        end
    else
        local t = set[1]
        t:SetTexture(crest.file)
        t:SetTexCoord(b[1] / crest.size[1], b[3] / crest.size[1], b[2] / crest.size[2], b[4] / crest.size[2])
        t:SetSize((b[3] - b[1]) * k, h)
        t:ClearAllPoints()
        t:SetPoint("CENTER", panel, point, x, y)
        Tint(t)
    end
    return (b[3] - b[1]) * k
end
-- lays the emblem: a quarrel, a crest, or nothing (false: the caller lays its own)
function W.LayEmblem(panel, zone, at)
    local function Set()
        local t = {}
        for i = 1, 4 do t[i] = panel:CreateTexture(nil, "BACKGROUND", nil, 5) end
        return t
    end
    if not panel.crestSet then
        panel.crestSet, panel.sideSets = Set(), { Set(), Set() }
        panel.crack = panel:CreateTexture(nil, "BACKGROUND", nil, 5)
    end
    for _, set in ipairs({ panel.crestSet, panel.sideSets[1], panel.sideSets[2] }) do
        for _, t in ipairs(set) do t:Hide() end
    end
    panel.crack:Hide()
    local pair = W.quarrels[zone or at or 0]
    local crest = not pair and zone and W.crestOf[zone] and W.crests[W.crestOf[zone]]
    if not (pair or crest) then return false end
    panel.emblem:Hide()
    panel.emblemFor = nil
    if crest then
        W.PutCrest(panel, panel.crestSet, crest, 0, 190, W.crestH)
        return true
    end
    -- (each side in its own half of the crack, kept inside the column however narrow)
    local half = (panel:GetWidth() or 440) / 2
    local flip = pair.mirror and -1 or 1
    for i, name in ipairs(pair) do
        local x, y = (i == 1 and -1 or 1) * flip, i == 1 and 268 or 104
        local side = W.crests[name]
        if side then
            local b = side.box
            local w = (b[3] - b[1]) * W.sideCrestH / (b[4] - b[2])
            W.PutCrest(panel, panel.sideSets[i], side, x * math.min(100, half - w / 2 - 12), y, W.sideCrestH)
        else
            local t, sz = panel.sideSets[i][1], W.motifSize[name] or { 1, 1 }
            local k = W.motifBox / math.max(sz[1], sz[2])
            t:SetTexture(LAB .. "Motif" .. name)
            t:SetTexCoord(0, 1, 0, 1)
            t:SetDesaturated(false)
            t:SetBlendMode("BLEND")
            t:SetSize(sz[1] * k, sz[2] * k)
            t:ClearAllPoints()
            t:SetPoint("CENTER", panel, "BOTTOM", x * math.min(100, half - sz[1] * k / 2 - 12), y)
            t:SetVertexColor(0.84, 0.66, 0.38, W.motifAlpha)
            t:Show()
        end
    end
    -- (across the column, from its right edge where the glass took the blow, to a point short of the left)
    local c = panel.crack
    c:SetTexture(LAB .. "WorldCrack" .. (pair.crack or 1))
    if pair.mirror then c:SetTexCoord(1, 0, 0, 1) else c:SetTexCoord(0, 1, 0, 1) end
    c:SetBlendMode("ADD")
    c:SetSize(half * 2, half * 2 * 320 / 512)
    c:ClearAllPoints()
    c:SetPoint("CENTER", panel, "BOTTOM", 0, 190)
    c:SetVertexColor(0.92, 0.9, 0.84, W.crackAlpha)
    c:Show()
    return true
end
function W.OutlineOf(map)
    if not (map and W.outlineOn) then return nil end
    local own = W.ownOutline[map]
    if own == false then return nil end
    -- (a zone's own baked line, Teldrassil's, stays in the Lab with the outline itself (off): no path to it here, so
    -- a release names no art it does not ship. The release session's build check, 2026-11-22)
    if own then return nil end
    local known = W.outlines[map]
    if known ~= nil then return known or nil end
    W.outlines[map] = false
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    local parent = info and info.parentMapID
    if not (parent and parent > 0 and C_Map.GetMapRectOnMap and C_Map.GetMapHighlightInfoAtPosition) then return nil end
    local ok, l, r, t, b = pcall(C_Map.GetMapRectOnMap, map, parent)
    if not (ok and l and r and t and b) then return nil end
    for _, f in ipairs({ { 0.5, 0.5 }, { 0.4, 0.5 }, { 0.6, 0.5 }, { 0.5, 0.4 }, { 0.5, 0.6 }, { 0.35, 0.4 }, { 0.65, 0.6 } }) do
        local x, y = l + (r - l) * f[1], t + (b - t) * f[2]
        local at = C_Map.GetMapInfoAtPosition and C_Map.GetMapInfoAtPosition(parent, x, y)
        if not at or at.mapID == map then
            local ok2, file, atlas, tpx, tpy, tw, th = pcall(C_Map.GetMapHighlightInfoAtPosition, parent, x, y)
            if ok2 and ((file and file ~= 0) or (atlas and atlas ~= "")) and tw and th and tw > 0 and th > 0 then
                W.outlines[map] = { file = file, atlas = atlas, tpx = tpx or 1, tpy = tpy or 1, w = tw, h = th }
                return W.outlines[map]
            end
        end
    end
    return nil
end
-- lays it low in the column: true if it could. (The game's highlight art is a white shape on black, drawn added,
-- not a shape with alpha: a copy laid over it to leave a line showed as a dark square, the user's shot, 2026-11-22.
-- So the shape itself, added in a faint brass: a silhouette lit into the glass)
function W.LayOutline(panel, s)
    local box = 200
    local k = math.min(box / s.w, box / s.h)
    local w, h = s.w * k, s.h * k
    local tex = panel.outline
    local ok
    if s.own then
        ok = pcall(tex.SetTexture, tex, s.own)
        if ok then
            tex:SetTexCoord(0, 1, 0, 1)
            tex:SetBlendMode("BLEND")
            -- (bigger and fainter, near the column's width: the user, 2026-11-22, "Bigger and fainter maybe?")
            local ow = math.min((panel:GetWidth() or 400) - 40, 440)
            local oh = ow * s.h / s.w
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", panel, "BOTTOM", 0, oh / 2 + 40)
            tex:SetSize(ow, oh)
            tex:SetVertexColor(0.84, 0.66, 0.38, 0.12)
            tex:Show()
            panel.outlineIn:Hide()
            return true
        end
    elseif s.atlas and type(s.atlas) == "string" and s.atlas ~= "" then
        ok = pcall(tex.SetAtlas, tex, s.atlas)
    elseif s.file and s.file ~= 0 then
        ok = pcall(tex.SetTexture, tex, s.file)
        if ok then tex:SetTexCoord(0, s.tpx, 0, s.tpy) end
    end
    panel.outlineIn:Hide()
    if not ok then tex:Hide() return false end
    tex:SetBlendMode("ADD")
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", panel, "BOTTOM", 0, 200)
    tex:SetSize(w, h)
    tex:SetVertexColor(0.84, 0.66, 0.38, 0.10)
    tex:Show()
    return true
end

-- each zone's colour, its feel by hand (for the log's sweep of light): forests a deep green, deserts sand, the dead grey
local ZONE_TINT = {
    [1429] = { 0.18, 0.42, 0.16 }, [1436] = { 0.78, 0.66, 0.30 }, [1433] = { 0.72, 0.40, 0.25 }, [1431] = { 0.25, 0.45, 0.50 },
    [1434] = { 0.12, 0.40, 0.18 }, [1426] = { 0.55, 0.70, 0.85 }, [1432] = { 0.22, 0.40, 0.20 }, [1437] = { 0.18, 0.32, 0.18 },
    [1417] = { 0.65, 0.62, 0.35 }, [1424] = { 0.20, 0.40, 0.18 }, [1416] = { 0.60, 0.70, 0.80 }, [1421] = { 0.35, 0.45, 0.40 },
    [1420] = { 0.45, 0.55, 0.30 }, [1422] = { 0.55, 0.55, 0.35 }, [1423] = { 0.55, 0.40, 0.55 }, [1425] = { 0.18, 0.40, 0.16 },
    [1418] = { 0.70, 0.45, 0.30 }, [1427] = { 0.80, 0.35, 0.20 }, [1428] = { 0.70, 0.30, 0.20 }, [1435] = { 0.30, 0.50, 0.40 },
    [1419] = { 0.75, 0.30, 0.25 }, [1430] = { 0.40, 0.40, 0.45 },
    [1411] = { 0.80, 0.40, 0.22 }, [1412] = { 0.26, 0.46, 0.20 }, [1413] = { 0.78, 0.62, 0.35 }, [1438] = { 0.14, 0.38, 0.18 },
    [1439] = { 0.35, 0.45, 0.55 }, [1440] = { 0.12, 0.34, 0.20 }, [1441] = { 0.75, 0.55, 0.40 }, [1442] = { 0.55, 0.55, 0.45 },
    [1443] = { 0.65, 0.58, 0.45 }, [1444] = { 0.14, 0.40, 0.16 }, [1445] = { 0.40, 0.50, 0.40 }, [1446] = { 0.85, 0.70, 0.40 },
    [1447] = { 0.40, 0.45, 0.65 }, [1448] = { 0.22, 0.34, 0.12 }, [1449] = { 0.18, 0.44, 0.14 }, [1450] = { 0.45, 0.60, 0.55 },
    [1451] = { 0.80, 0.65, 0.35 }, [1452] = { 0.65, 0.78, 0.90 },
    [1414] = { 0.75, 0.62, 0.40 }, [1415] = { 0.40, 0.60, 0.40 },   -- (Kalimdor, the Eastern Kingdoms)
    [947] = { 0.26, 0.42, 0.52 },   -- (Azeroth: its sea's blue-grey, most of its map; "Azeroth herself has no colortint")
}

local MG = { strip = { 0, 0.48047, 0, 1 }, data = {
    [1429] = { tex = "Elwynn", parts = {
        { key = "northshire", x = 0.3902, y = 0.0391, w = 0.4715, h = 0.1328, tc = { 0.48438, 0.71094, 0.00000, 0.13281 }, ids = { { 783 }, { 7 }, { 33 }, { 18 } } },
        { key = "goldshire", x = 0.0976, y = 0.2285, w = 0.4228, h = 0.1289, tc = { 0.71484, 0.91797, 0.00000, 0.12891 }, ids = { { 2158 }, { 85 }, { 86 } } },
        { key = "mines", x = 0.5935, y = 0.2637, w = 0.4065, h = 0.1387, tc = { 0.48438, 0.67969, 0.13477, 0.27344 }, ids = { { 62 }, { 76 }, { 60 }, { 47 } } },
        { key = "farms", x = 0.5650, y = 0.7334, w = 0.4350, h = 0.1348, tc = { 0.68359, 0.89258, 0.13477, 0.26953 }, ids = { { 106 }, { 88 }, { 114 } } },
        { key = "westbrook", x = 0.0976, y = 0.8682, w = 0.3455, h = 0.1289, tc = { 0.48438, 0.65039, 0.27539, 0.40430 }, ids = { { 176 }, { 11 }, { 239 } } },
    } },
    [1426] = { tex = "DunMorogh", parts = {
        { key = "pilot", x = 0.1179, y = 0.2959, w = 0.3699, h = 0.0859, tc = { 0.48438, 0.66211, 0.00000, 0.08594 }, ids = { { 419 } } },
        { key = "kharanos", x = 0.5447, y = 0.4141, w = 0.4553, h = 0.1289, tc = { 0.66602, 0.88477, 0.00000, 0.12891 }, ids = { { 413 }, { 318 }, { 310 }, { 2160 } } },
        { key = "troggs", x = 0.0813, y = 0.6035, w = 0.3699, h = 0.1143, tc = { 0.48438, 0.66211, 0.13086, 0.24512 }, ids = { { 432 } } },
        { key = "rams", x = 0.5569, y = 0.6982, w = 0.4309, h = 0.0742, tc = { 0.66602, 0.87305, 0.13086, 0.20508 }, ids = { { 314 } } },
        { key = "frostmane", x = 0.5569, y = 0.7939, w = 0.3293, h = 0.1641, tc = { 0.48438, 0.64258, 0.24707, 0.41113 }, ids = { { 287 } } },
        { key = "coldridge", x = 0.0691, y = 0.8438, w = 0.5488, h = 0.1562, tc = { 0.64648, 0.91016, 0.24707, 0.40332 }, ids = { { 179 }, { 170 }, { 182 }, { 218 } } },
    } },
    [1438] = { tex = "Teldrassil", parts = {
        { key = "crown", x = 0.1585, y = 0.3906, w = 0.7236, h = 0.1377, tc = { 0.48438, 0.83203, 0.00000, 0.13770 }, ids = { { 457 }, { 459 }, { 928 } } },
        { key = "dolanaar", x = 0.1382, y = 0.3340, w = 0.8008, h = 0.1953, tc = { 0.48438, 0.86914, 0.13965, 0.33496 }, ids = { { 2159 }, { 488 }, { 487 } } },
        { key = "gnarlpine", x = 0.5976, y = 0.6934, w = 0.3699, h = 0.1035, tc = { 0.48438, 0.66211, 0.33691, 0.44043 }, ids = { { 476 }, { 486 } } },
        { key = "timberling", x = 0.1016, y = 0.5283, w = 0.3821, h = 0.1133, tc = { 0.66602, 0.84961, 0.33691, 0.45020 }, ids = { { 918 }, { 919 }, { 927 } } },
        { key = "relics", x = 0.5041, y = 0.8281, w = 0.3821, h = 0.1094, tc = { 0.48438, 0.66797, 0.45215, 0.56152 }, ids = { { 483 } } },
    } },
    [1411] = { tex = "Durotar", parts = {
        { key = "tiragarde", x = 0.6179, y = 0.0000, w = 0.3821, h = 0.0918, tc = { 0.48438, 0.66797, 0.00000, 0.09180 }, ids = { { 831 }, { 784 } } },
        { key = "senjin", x = 0.0203, y = 0.0078, w = 0.6626, h = 0.2793, tc = { 0.67188, 0.99023, 0.00000, 0.27930 }, ids = { { 826 }, { 808 } } },
        { key = "skullrock", x = 0.0813, y = 0.6133, w = 0.5122, h = 0.1240, tc = { 0.48438, 0.73047, 0.28125, 0.40527 }, ids = { { 827 }, { 832 }, { 828 } } },
        { key = "scorpids", x = 0.3089, y = 0.7285, w = 0.4512, h = 0.0889, tc = { 0.73438, 0.95117, 0.28125, 0.37012 }, ids = { { 812 } } },
        { key = "trials", x = 0.1667, y = 0.7939, w = 0.8333, h = 0.2061, tc = { 0.48438, 0.88477, 0.40723, 0.61328 }, ids = { { 4641 }, { 788 }, { 804 }, { 792, 1485, 1499 } } },
    } },
    [1412] = { tex = "Mulgore", parts = {
        { key = "venture", x = 0.5976, y = 0.3037, w = 0.4024, h = 0.1084, tc = { 0.48438, 0.67773, 0.00000, 0.10840 }, ids = { { 764 }, { 765 } } },
        { key = "windfury", x = 0.0976, y = 0.2939, w = 0.3496, h = 0.1035, tc = { 0.68164, 0.84961, 0.00000, 0.10352 }, ids = { { 743 } } },
        { key = "rites", x = 0.1179, y = 0.4336, w = 0.5366, h = 0.1543, tc = { 0.48438, 0.74219, 0.11035, 0.26465 }, ids = { { 776 }, { 772 }, { 773 } } },
        { key = "wells", x = 0.6382, y = 0.6484, w = 0.3496, h = 0.1084, tc = { 0.74609, 0.91406, 0.11035, 0.21875 }, ids = { { 754 }, { 758 }, { 760 } } },
        { key = "caravan", x = 0.1179, y = 0.8086, w = 0.4553, h = 0.0840, tc = { 0.48438, 0.70312, 0.26660, 0.35059 }, ids = { { 751 } } },
        { key = "narache", x = 0.4715, y = 0.8486, w = 0.5285, h = 0.1514, tc = { 0.70703, 0.96094, 0.26660, 0.41797 }, ids = { { 747 }, { 750 }, { 3376 }, { 757 } } },
    } },
    [1420] = { tex = "Tirisfal", parts = {
        { key = "brill", x = 0.1098, y = 0.4424, w = 0.8374, h = 0.1025, tc = { 0.48438, 0.88672, 0.00000, 0.10254 }, ids = { { 358 }, { 5482 }, { 5481 } } },
        { key = "mills", x = 0.6992, y = 0.2588, w = 0.3008, h = 0.1230, tc = { 0.48438, 0.62891, 0.10449, 0.22754 }, ids = { { 362 }, { 426 } } },
        { key = "scarlet", x = 0.5569, y = 0.6484, w = 0.4431, h = 0.1084, tc = { 0.63281, 0.84570, 0.10449, 0.21289 }, ids = { { 372 }, { 374 } } },
        { key = "family", x = 0.0894, y = 0.5840, w = 0.3821, h = 0.1094, tc = { 0.48438, 0.66797, 0.22949, 0.33887 }, ids = { { 408 }, { 354 }, { 405 } } },
        { key = "plague", x = 0.2033, y = 0.7432, w = 0.7967, h = 0.1689, tc = { 0.48438, 0.86719, 0.34082, 0.50977 }, ids = { { 369, 492 } } },
        { key = "deathknell", x = 0.0772, y = 0.8584, w = 0.4756, h = 0.1416, tc = { 0.48438, 0.71289, 0.51172, 0.65332 }, ids = { { 363 }, { 364 }, { 6395 }, { 381 } } },
    } },
} }
-- MARGIN DATA END
MG.aspect = 96 / 400
-- (off for now: the user, 2026-11-22, of the drawing in the folded rail, "isnt really fitting in like this in this
-- form. Maybe behind the glass will be better^^ In that case, maybe we have another use for the tab, or we just dont
-- use at all yet". The drawing now lies behind the log's glass (panel.ghost); the rail is its round quest signs again.
-- The code and art stay for another use)
function MG.On() return false end
MG.questDone = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted or IsQuestFlaggedCompleted
function MG.PartDone(part)
    for _, group in ipairs(part.ids) do
        local any = false
        for _, id in ipairs(group) do
            if MG.questDone and MG.questDone(id) then any = true break end
        end
        if not any then return false end
    end
    return true
end
-- the rail's width: folded with the margin on, the drawing's own shape at the map's height
function MG.Width()
    if not MG.On() then return RAIL end
    local face, s = Face(), slot and slot:GetEffectiveScale()
    local h = face and face:GetHeight()
    if not (h and h > 0 and s and s > 0) then return S.railW or 96 end
    S.railW = math.max(RAIL, math.floor(h * face:GetEffectiveScale() / s * MG.aspect + 0.5))
    return S.railW
end
ns.WorldMarginZones = function() local t = {} for map in pairs(MG.data) do t[#t + 1] = map end return t end

function MG.Draw(list)
    local m = MG.On() and list and MG.data[list]
    if not rail.art then
        rail.art = rail:CreateTexture(nil, "ARTWORK", nil, 0)
        rail.patches = {}
        -- (laid out before the rail has its height: draw again when it gets it)
        rail:HookScript("OnSizeChanged", function() if rail.marginList and rail:IsShown() then MG.Draw(rail.marginList) end end)
    end
    rail.marginList = list
    if not m then
        rail.art:Hide()
        for _, t in ipairs(rail.patches) do t:Hide() end
        return false
    end
    local tex = ns.MEDIA .. "World\\Margin\\" .. m.tex
    local H = rail:GetHeight() or 0
    local Wd = H * MG.aspect
    rail.art:SetTexture(tex)
    rail.art:SetTexCoord(MG.strip[1], MG.strip[2], MG.strip[3], MG.strip[4])
    rail.art:ClearAllPoints()
    rail.art:SetPoint("TOP", rail, "TOP")
    rail.art:SetSize(Wd, H)
    rail.art:Show()
    -- (the test bench can show it as if nothing or everything were done: Cfg().marginShow "none" / "all")
    local show = Cfg().marginShow
    for i, part in ipairs(m.parts) do
        local t = rail.patches[i]
        if not t then
            t = rail:CreateTexture(nil, "ARTWORK", nil, 1)
            rail.patches[i] = t
        end
        local done = show == "all" or (show ~= "none" and MG.PartDone(part))
        if done then
            t:SetTexture(tex)
            t:SetTexCoord(part.tc[1], part.tc[2], part.tc[3], part.tc[4])
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", rail.art, "TOPLEFT", part.x * Wd, -part.y * H)
            t:SetSize(part.w * Wd, part.h * H)
            t:Show()
        else
            t:Hide()
        end
    end
    for i = #m.parts + 1, #rail.patches do rail.patches[i]:Hide() end
    return true
end

-- the rail: the quests of the map on view as round signs, the ready ones first and in gold
local function DrawRail(list)
    local folded = Folded()
    rail:SetShown(folded)
    S.rail = {}
    if not folded then return end
    if MG.Draw(list) then
        for i = 1, #rail.signs do rail.signs[i]:Hide() end
        rail.ring:Hide()
        rail.more:SetText("")
        return
    end
    if not list then return W.RailZones() end   -- (a continent or the world: ListMap gives none)
    local mine = {}
    for _, h in ipairs(W.Held()) do
        if list and h.map == list then mine[#mine + 1] = h end
    end
    -- (nearest first: the user, 2026-11-22, "sort them by proximity". Straight across the zone map to the quest's
    -- ground, or the one you hand it to; one with nowhere known last)
    local far = {}
    for _, h in ipairs(mine) do
        local s = QuestSpot(h.id)
        local pos = s and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(s.map, "player")
        far[h] = pos and pos.x and ((pos.x - s.x) ^ 2 + (pos.y - s.y) ^ 2) or math.huge
    end
    -- (the ready ones last: "complete moves to the bottom, i think", the user, 2026-11-22)
    table.sort(mine, function(a, b)
        if (a.complete and true or false) ~= (b.complete and true or false) then return not a.complete end
        if far[a] ~= far[b] then return far[a] < far[b] end
        return a.name < b.name
    end)
    local STEP = 62   -- (the mark 40, its count, the rule between)
    local room = math.max(0, math.floor(((rail:GetHeight() or 0) - 28) / STEP))
    local n = math.min(#mine, room)
    rail.ring:Hide()
    for i = 1, n do
        local h, b = mine[i], RailSign(i)
        b.h = h
        RailMark(b, h)
        local last = i == n
        b.sepDia:SetShown(not last)
        b.sep[1]:SetShown(not last)
        b.sep[2]:SetShown(not last)
        b:ClearAllPoints()
        b:SetPoint("TOP", rail, "TOP", 0, -10 - (i - 1) * STEP)
        b:Show()
        S.rail[i] = h
        if S.railSel == i then
            rail.ring:ClearAllPoints()
            rail.ring:SetPoint("CENTER", b, "CENTER")
            rail.ring:Show()
        end
    end
    for i = n + 1, #rail.signs do rail.signs[i]:Hide() end
    rail.more:SetText(#mine > n and ("+" .. (#mine - n)) or "")
end

-- on a continent or the world: the zones you hold quests in, one sign each (ZoneSign), the one you stand in first, then
-- the nearest across the continent you are on, then the rest by name (dungeons stay on the list, not here)
function W.RailZones()
    local zones, by = {}, {}
    for _, h in ipairs(W.Held()) do
        if h.map and IsZone(h.map) then
            local z = by[h.map]
            if not z then
                z = { map = h.map, held = 0, ready = 0, name = MapName(h.map) or "" }
                by[h.map] = z
                zones[#zones + 1] = z
            end
            z.held = z.held + 1
            if h.complete then z.ready = z.ready + 1 end
        end
    end
    local here = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    here = here and W.ZoneMap and W.ZoneMap(here) or here
    for _, z in ipairs(zones) do
        z.far = math.huge
        if z.map == here then
            z.far = -1
        else
            local info = C_Map.GetMapInfo and C_Map.GetMapInfo(z.map)
            local cont = info and info.parentMapID
            local pos = cont and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(cont, "player")
            local ok, l, r, t, b = false
            if pos and pos.x and C_Map.GetMapRectOnMap then ok, l, r, t, b = pcall(C_Map.GetMapRectOnMap, z.map, cont) end
            if ok and l and r and t and b then z.far = (pos.x - (l + r) / 2) ^ 2 + (pos.y - (t + b) / 2) ^ 2 end
        end
    end
    table.sort(zones, function(a, b)
        if a.far ~= b.far then return a.far < b.far end
        return a.name < b.name
    end)
    local STEP = 62
    local room = math.max(0, math.floor(((rail:GetHeight() or 0) - 28) / STEP))
    local n = math.min(#zones, room)
    rail.ring:Hide()
    for i = 1, n do
        local b = RailSign(i)
        ZoneSign(b, zones[i])
        local last = i == n
        b.sepDia:SetShown(not last)
        b.sep[1]:SetShown(not last)
        b.sep[2]:SetShown(not last)
        b:ClearAllPoints()
        b:SetPoint("TOP", rail, "TOP", 0, -10 - (i - 1) * STEP)
        b:Show()
        S.rail[i] = { zone = zones[i].map }
        if S.railSel == i then
            rail.ring:ClearAllPoints()
            rail.ring:SetPoint("CENTER", b, "CENTER")
            rail.ring:Show()
        end
    end
    for i = n + 1, #rail.signs do rail.signs[i]:Hide() end
    rail.more:SetText(#zones > n and ("+" .. (#zones - n)) or "")
end

-- Placing and drawing ---------------------------------------------------------------------------

-- The map's corner grip stands in the window's own corner while the window is up (the user, 2026-11-20:
-- "Covers SO with no way to resize"; the grip was left in the map's corner, inside the window, by the log).
-- It is the map's grip itself, so a drag sizes the map as ever and the window follows. Put back on every way
-- out (PlaceMapGrip, BattlefieldInfo.lua).
local gripMoved = false
local GRIP_AT = { BR = { "BOTTOMRIGHT", -2, 2 }, BL = { "BOTTOMLEFT", 2, 2 }, TR = { "TOPRIGHT", -2, -2 }, TL = { "TOPLEFT", 2, -2 } }
local function GripHold(on)
    local grip = ns.debugFrames and ns.debugFrames.grip
    if not grip then return end
    if on and win then
        local p = GRIP_AT[ns.GripCorner and ns.GripCorner() or "BR"] or GRIP_AT.BR
        -- (a top corner: under the bar, not on its close button)
        local y = p[1]:find("^TOP") and p[3] - (win.lift or BAR) or p[3]
        grip:ClearAllPoints()
        grip:SetPoint(p[1], win, p[1], p[2], y)
        gripMoved = true
    elseif gripMoved then
        gripMoved = false
        if ns.PlaceMapGrip then ns.Safe("World window grip", ns.PlaceMapGrip) end
    end
end

-- What of the map's own rests while the window is up, so nothing is there twice and nothing of the small map's
-- lies over the window:
--   the red X              the bar has its own (one close button, not two)
--   the zone header        ZoneName.lua's name in a tab: the bar names the zone. (The user, 2026-11-21, in game:
--                          "The header from battlefieldmap still appearing", the name again over the bar's middle)
--   the gear, the toggles  Options.lua's quick options and its strip of layer buttons: the bar's cog has them,
--                          in a small "World map" panel (Options). The user, 2026-11-21: "Togglebuttons,
--   the red arrow          quicksettings, arrowbutton. I think they just hide when worldmap tbh. redArrow does the
--                          same as the x, the M bind and the esc key." (MapControls.lua's grow button)
-- Each is hidden, kept hidden if something shows it, and given back by its own code on the way out.
local function Rest(f, on, back)
    if not f then return end
    if not f.wmHooked then
        f.wmHooked = true
        f:HookScript("OnShow", function(self)
            if win and win:IsShown() then
                self.wmWinHid = true
                self:Hide()
            end
        end)
    end
    if on then
        if f:IsShown() then
            f.wmWinHid = true
            f:Hide()
        end
    elseif f.wmWinHid then
        f.wmWinHid = nil
        back(f)
    end
end
local function ShowBack(f) f:Show() end   -- (the X and the arrow: a "hide the red buttons" setting hides them again, MapControls)
local function QuickBack()
    if ns.UpdateQuickButton then ns.Safe("World window buttons", ns.UpdateQuickButton) end
end

-- The cog's panel: a legend (the user, 2026-11-22, of mockups/world-cog-panel.html: "A. A legend"). What you flip
-- while looking at the map, and nothing else (agreed with Settings small fixes: the look picks and Before you go
-- live on the settings page "World map" only, one home each):
--   On the map      the strip's layer buttons you keep, in your order, by the strip's own names (the strip rests
--                   while the window is up): a click is the button's own click, a right-click its own settings
--   The quest log   Objectives always shown, Loose ends
--   the foot        All settings... (that page)
-- Each line: its icon, its name, a brass diamond at the end, filled when on. Off is told three ways, never by
-- alpha alone (the settings session: off must not read as "can't"): the diamond hollow, the icon greyed, the name
-- dim. Engraved small-caps heads between fading rules; a double brass rule round it, the Engraver's neatline; the
-- hover a soft band (SoftBand), no box.
local OPT_W, OPT_ROW, OPT_PAD = 246, 23, 14
local function OptRow(i)
    local r = opts.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, opts)
    r:SetHeight(OPT_ROW)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", 2, 0)
    r.text = r:CreateFontString(nil, "OVERLAY")
    r.text:SetFont(FRIZ, 12, "")
    r.text:SetPoint("RIGHT", -16, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    -- the diamond: brass, and a slate one inside it when off (hollow)
    r.dia = r:CreateTexture(nil, "ARTWORK")
    r.dia:SetTexture(LAB .. "WorldDiamond")
    r.dia:SetSize(9, 9)
    r.dia:SetPoint("RIGHT", -3, 0)
    r.dia:SetVertexColor(BRASS[1], BRASS[2], BRASS[3], 1)
    r.hole = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.hole:SetTexture(LAB .. "WorldDiamond")
    r.hole:SetSize(5, 5)
    r.hole:SetPoint("CENTER", r.dia, "CENTER")
    r.hole:SetVertexColor(SLATE[1], SLATE[2], SLATE[3], 1)
    -- a head's rules either side of its words
    r.ruleL = r:CreateTexture(nil, "ARTWORK")
    r.ruleR = r:CreateTexture(nil, "ARTWORK")
    for k, t in ipairs({ r.ruleL, r.ruleR }) do
        t:SetTexture(WHITE8)
        t:SetHeight(1)
        local a, b = k == 1 and 0 or 0.6, k == 1 and 0.6 or 0
        local c1 = CreateColor and CreateColor(BRASS[1], BRASS[2], BRASS[3], a)
        local c2 = CreateColor and CreateColor(BRASS[1], BRASS[2], BRASS[3], b)
        if not (c1 and t.SetGradient and pcall(t.SetGradient, t, "HORIZONTAL", c1, c2)) then t:SetVertexColor(BRASS[1], BRASS[2], BRASS[3], 0.4) end
    end
    r.band = SoftBand(r, 0, { 1, 0.93, 0.78 }, 0.08)
    r:SetScript("OnEnter", function(self) if self.act then self.band:Show() end end)
    r:SetScript("OnLeave", function(self) self.band:Hide() end)
    r:SetScript("OnClick", function(self, button)
        if self.act then self.act(self, button) end
    end)
    opts.rows[i] = r
    return r
end


local function StripButtons()
    local strip = ns.debugFrames and ns.debugFrames.toggleStrip
    if not strip then return {} end
    local byId, out = {}, {}
    for _, b in ipairs({ strip:GetChildren() }) do
        if b.id then byId[b.id] = b end
    end
    for _, id in ipairs(ns.ToggleOrder and ns.ToggleOrder() or {}) do
        local b = byId[id]
        -- (the ones you keep on the strip: shown there before the window rested it; its own flag, not its parent's)
        if b and b:IsShown() and b.def then out[#out + 1] = b end
    end
    return out
end

local function FillOptions()
    local y, n = -36, 0
    local w = OPT_W - 2 * OPT_PAD
    local function Place(r, h)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", OPT_PAD, y)
        r:SetPoint("TOPRIGHT", -OPT_PAD, y)
        r:SetHeight(h)
        r.band:Lay(w)
        r.band:Hide()
        r:Show()
        y = y - h
    end
    -- an entry: icon (or none), name, the diamond; on == nil: a plain line (the foot)
    local function Entry(text, on, act, icon, b)
        n = n + 1
        local r = OptRow(n)
        r.act = act
        r.ruleL:Hide()
        r.ruleR:Hide()
        r.icon:SetShown(icon ~= nil)
        if icon and r.iconFor ~= icon then
            r.iconFor = icon
            if b and b.iconPath and ns.SetIconArt then
                local cut = ns.SetIconArt(r, r.icon, b.iconPath)
                if cut then r.icon:SetTexCoord(cut[1], cut[2], cut[3], cut[4]) end
            else
                r.icon:SetTexture(icon)
                r.icon:SetTexCoord(0, 1, 0, 1)
            end
        end
        r.icon:SetDesaturated(on == false)
        r.icon:SetAlpha(on == false and 0.5 or 1)
        r.text:ClearAllPoints()
        r.text:SetPoint("LEFT", icon and 27 or 4, 0)
        r.text:SetPoint("RIGHT", -16, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetFont(FRIZ, 12, "")
        r.text:SetText(text)
        Colour(r.text, on == false and DIM or TEXT)
        r.dia:SetShown(on ~= nil)
        r.hole:SetShown(on == false)
        Place(r, OPT_ROW)
        return r
    end
    local function Head(text)
        y = y - 5
        n = n + 1
        local r = OptRow(n)
        r.act = nil
        r.icon:Hide()
        r.dia:Hide()
        r.hole:Hide()
        r.text:ClearAllPoints()
        r.text:SetPoint("CENTER", 0, 0)
        r.text:SetJustifyH("CENTER")
        r.text:SetFont(FRIZ, 9, "")
        r.text:SetText(Spaced(text:upper()))
        Colour(r.text, BRASS)
        r.ruleL:ClearAllPoints()
        r.ruleL:SetPoint("LEFT", 0, 0)
        r.ruleL:SetPoint("RIGHT", r.text, "LEFT", -8, 0)
        r.ruleR:ClearAllPoints()
        r.ruleR:SetPoint("LEFT", r.text, "RIGHT", 8, 0)
        r.ruleR:SetPoint("RIGHT", 0, 0)
        r.ruleL:Show()
        r.ruleR:Show()
        Place(r, 16)
        y = y - 2
    end
    local function Switch(text, key, off)
        local c = Cfg()
        local on
        if off then on = c[key] == true else on = c[key] ~= false end
        Entry(text, on, function()
            if off then c[key] = not on else c[key] = c[key] == false end
            FillOptions()
            dirty = true
            if ns.WorldPanelChanged then ns.WorldPanelChanged() end
        end)
    end
    opts.title:SetText("World map")
    local list = StripButtons()
    if #list > 0 then Head("On the map") end
    for _, b in ipairs(list) do
        Entry(b.def[4] or b.id, not b.icon:IsDesaturated(), function(_, button)
            if button == "RightButton" then
                opts:Hide()
                b:Click("RightButton")
                return
            end
            b:Click("LeftButton")
            FillOptions()
        end, b.iconPath, b)
    end
    -- (the log's rows only while the log is beside the map: off, they would do nothing. Settings small fixes' find,
    -- 2026-11-22)
    local logUp = not (ns.WorldSidebarOff and ns.WorldSidebarOff())
    if logUp then
    Head("The quest log")   -- ("the quest log", the user, 2026-11-22)
    Switch("Objectives always shown", "aimsOpen", true)   -- ("objectives always shown", the user)
    Switch("Loose ends", "loose")
    -- the quest page's text size: a brass hairline with a diamond on it, the size in words at the right; a drag, a
    -- click on the line or the wheel, steps of 5%. The page beside it changes as it moves (W.PageZoom)
    do
        local s = opts.slide
        if not s then
            s = CreateFrame("Button", nil, opts)
            s:EnableMouseWheel(true)
            s.text = s:CreateFontString(nil, "OVERLAY")
            s.text:SetFont(FRIZ, 12, "")
            s.text:SetPoint("TOPLEFT", 4, -3)
            s.value = s:CreateFontString(nil, "OVERLAY")
            s.value:SetFont(FRIZ, 11.5, "")
            s.value:SetPoint("TOPRIGHT", -2, -3)
            s.track = s:CreateTexture(nil, "ARTWORK")
            s.track:SetColorTexture(BRASS[1], BRASS[2], BRASS[3], 0.5)
            s.track:SetHeight(1)
            s.track:SetPoint("BOTTOMLEFT", 8, 7)
            s.track:SetPoint("BOTTOMRIGHT", -8, 7)
            s.fill = s:CreateTexture(nil, "ARTWORK", nil, 1)
            s.fill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.75)
            s.fill:SetHeight(1)
            s.knob = s:CreateTexture(nil, "ARTWORK", nil, 2)
            s.knob:SetTexture(LAB .. "WorldDiamond")
            s.knob:SetSize(9, 9)
            s.knob:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
            s.band = SoftBand(s, 0, { 1, 0.93, 0.78 }, 0.08)
            function s:Show_()
                local v = W.PageZoom() * 100
                local f = (v - W.ZOOM_MIN) / (W.ZOOM_MAX - W.ZOOM_MIN)
                local tw = math.max(1, (self.track:GetWidth() or 0))
                if tw <= 1 then tw = OPT_W - 2 * OPT_PAD - 16 end
                self.knob:ClearAllPoints()
                self.knob:SetPoint("CENTER", self.track, "LEFT", tw * f, 0)
                self.fill:ClearAllPoints()
                self.fill:SetPoint("LEFT", self.track, "LEFT")
                self.fill:SetWidth(math.max(1, tw * f))
                self.value:SetText(math.floor(v + 0.5) .. "%")
            end
            local function At(self)
                local l, r = self.track:GetLeft(), self.track:GetRight()
                local x = GetCursorPosition() / self:GetEffectiveScale()
                if not (l and r and r > l) then return end
                local f = math.max(0, math.min(1, (x - l) / (r - l)))
                if W.SetPageZoom(W.ZOOM_MIN + f * (W.ZOOM_MAX - W.ZOOM_MIN)) then self:Show_() end
            end
            s:SetScript("OnMouseDown", function(self, button)
                if button ~= "LeftButton" then return end
                At(self)
                self:SetScript("OnUpdate", function(me)
                    if not IsMouseButtonDown("LeftButton") then me:SetScript("OnUpdate", nil) return end
                    At(me)
                end)
            end)
            s:SetScript("OnMouseWheel", function(self, d)
                if W.SetPageZoom(W.PageZoom() * 100 + (d > 0 and W.ZOOM_STEP or -W.ZOOM_STEP)) then self:Show_() end
            end)
            s:SetScript("OnEnter", function(self) self.band:Show() end)
            s:SetScript("OnLeave", function(self) self.band:Hide() end)
            s:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
            opts.slide = s
        end
        s.text:SetText("Quest page text")
        Colour(s.text, TEXT)
        Colour(s.value, SOFT)
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", OPT_PAD, y)
        s:SetPoint("TOPRIGHT", -OPT_PAD, y)
        s:SetHeight(34)
        s.band:Lay(w)
        s.band:Hide()
        s:Show()
        s:Show_()
        y = y - 34
    end
    -- (the new log takes the quest log key only when ticked, and the tick is here, in the log itself: the user,
    -- 2026-11-22, "we dont hijack bindings, but we make them VERY easy to find". Its words say what the key will do.
    -- Lab/WorldAlone.lua W.AloneTakesL; with the classic log picked, or no key bound, there is nothing to tick)
    local key = W.QuestKeyName and W.QuestKeyName()
    if key and W.AloneTakesL and ns.QuestLogKind and ns.QuestLogKind() == "new" then
        local on = W.AloneTakesL()
        Entry(key .. " opens this log", on, function()
            W.SetAloneTakesL(not on)
            FillOptions()
        end)
    end
    elseif opts.slide then
        opts.slide:Hide()
    end
    -- the foot: a hairline, then the way to the settings page
    y = y - 6
    opts.footRule:ClearAllPoints()
    opts.footRule:SetPoint("TOPLEFT", OPT_PAD, y)
    opts.footRule:SetPoint("TOPRIGHT", -OPT_PAD, y)
    y = y - 4
    Entry("All settings...", nil, function()
        opts:Hide()
        if ns.OpenOptionsPage then ns.Safe("World window settings", ns.OpenOptionsPage, "bigworld") elseif ns.ToggleOptions then ns.Safe("World window settings", ns.ToggleOptions) end
    end, COG_ART)
    Colour(opts.rows[n].text, SOFT)
    for i = n + 1, #opts.rows do opts.rows[i]:Hide() end
    opts:SetHeight(-y + 10)
end

function Options(owner)
    if opts and opts:IsShown() then opts:Hide() return end
    if not opts then
        opts = CreateFrame("Frame", "WaymarkWorldOptions", UIParent)
        opts:SetFrameStrata("DIALOG")
        opts:SetWidth(OPT_W)
        opts:EnableMouse(true)
        opts.rows = {}
        local g = opts:CreateTexture(nil, "BACKGROUND")
        g:SetAllPoints()
        g:SetColorTexture(SLATE[1], SLATE[2], SLATE[3], 0.97)
        -- (a double brass rule, the Engraver's neatline: the outer line bright, the inner one faint, 3 in)
        for i, e in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
            local t = opts:CreateTexture(nil, "BORDER")
            t:SetColorTexture(0.84, 0.66, 0.38, 0.85)
            t:SetPoint(e[1])
            t:SetPoint(e[2])
            if i <= 2 then t:SetHeight(1) else t:SetWidth(1) end
            local inner = opts:CreateTexture(nil, "BORDER", nil, 1)
            inner:SetColorTexture(BRASS[1], BRASS[2], BRASS[3], 0.4)
            if i <= 2 then
                inner:SetHeight(1)
                inner:SetPoint(e[1], 3, i == 1 and -3 or 3)
                inner:SetPoint(e[2], -3, i == 1 and -3 or 3)
            else
                inner:SetWidth(1)
                inner:SetPoint(e[1], i == 3 and 3 or -3, -3)
                inner:SetPoint(e[2], i == 3 and 3 or -3, 3)
            end
        end
        opts.title = opts:CreateFontString(nil, "OVERLAY")
        opts.title:SetFont(Morpheus(), 17, "")
        opts.title:SetPoint("TOPLEFT", OPT_PAD, -11)
        opts.title:SetShadowColor(0, 0, 0, 1)
        opts.title:SetShadowOffset(1, -1)
        Colour(opts.title, GOLD)
        opts.footRule = opts:CreateTexture(nil, "ARTWORK")
        opts.footRule:SetColorTexture(BRASS[1], BRASS[2], BRASS[3], 0.3)
        opts.footRule:SetHeight(1)
        -- (shut by a click anywhere else, as the quill's menus are)
        if pcall(opts.RegisterEvent, opts, "GLOBAL_MOUSE_DOWN") then
            opts:SetScript("OnEvent", function(self)
                if self:IsShown() and not self:IsMouseOver() and not (bar and bar.opts:IsMouseOver()) then self:Hide() end
            end)
        end
    end
    opts:SetScale((win or panel) and (win or panel):GetEffectiveScale() / UIParent:GetEffectiveScale() or 1)   -- (panel: the log alone before the window was ever made)
    opts:ClearAllPoints()
    if slot and slot.side == "left" then
        opts:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", -6, -4)
    else
        opts:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 6, -4)
    end
    if GameTooltip and GameTooltip:GetOwner() == owner then GameTooltip:Hide() end
    FillOptions()
    opts:Show()
end

local SeamRule
local function CloseRest(on)
    if not on and opts then opts:Hide() end
    if not on and ClampHold then ClampHold(Map(), false) end
    if not on and SeamRule then SeamRule() end   -- (Minutes' own bar back in the map's corner)
    local map = Map()
    local d = ns.debugFrames or {}
    Rest(ns.ZoneHeader, on, function() if ns.UpdateZoneName then ns.Safe("World window header", ns.UpdateZoneName) end end)
    Rest(d.gear, on, QuickBack)
    Rest(d.toggleStrip, on, QuickBack)
    Rest(d.bigMap, on, ShowBack)
    if on and ns.HideQuickPanel then ns.HideQuickPanel() end
    Rest(map and map.BorderFrame and map.BorderFrame.CloseButton, on, ShowBack)
    -- (the user, 2026-11-21: "clicking the red x on the worldmap shrinks it to small map, but no X visible on
    -- smallmap". Something during the shrink can hide the map's X after it was given back: looked at again a
    -- moment later, and shown if the window is gone, the map is up and the "hide the red buttons" switch is off)
    if not on and C_Timer and C_Timer.After then
        C_Timer.After(0.3, function()
            local m = Map()
            local x = m and m.BorderFrame and m.BorderFrame.CloseButton
            local hideRed = ns.db and ns.db.toggles and ns.db.toggles.hideRed
            if x and m:IsShown() and not (win and win:IsShown()) and not hideRed and not x:IsShown() then x:Show() end
        end)
    end
end

-- The seam's ruler, with the neatline top. The user, 2026-11-21, of the bar's ticks: "I actually like the old mapbar
-- styles, can we draw them down the vertical between map and log too? I think at the bottom of that vertical is
-- where our 'minutes on foot' lives." So an old chart's graduated border down the seam, in true minutes on foot: a
-- long tick a step (Lab/Minutes.lua's own step for the map's zoom: half a minute, 1, 2, 5...), a middle one and two
-- short ones between, and at its foot the step in words, in Minutes' lettering. Minutes' own bar in the map's corner
-- rests meanwhile and comes back after. One texture, tiled; drawn again only when the zoom, the zone or the size
-- changes (a look each tick, a few numbers).
local RULE_ART = ns.MEDIA .. "World\\WorldTicksV"
local minutesBar
local function MinutesBarFrame(map)
    if minutesBar then return minutesBar end
    local sc = map and map.ScrollContainer
    if not (sc and sc.GetChildren) then return end
    for _, f in ipairs({ sc:GetChildren() }) do
        if type(f) == "table" and f.parts and f.words then minutesBar = f end
    end
    return minutesBar
end
local function RuleOn()
    return win and win:IsShown() and PathStyle() == "neat" and ns.MinutesYards and ns.MinutesPick and true or false
end
function SeamRule()
    local map, face = Map(), Face()
    local on = RuleOn() and map and face
    local mb = map and MinutesBarFrame(map)
    if mb and not mb.wmRuleHooked then
        mb.wmRuleHooked = true
        mb:HookScript("OnShow", function(self)
            if RuleOn() then
                self.wmRuleHid = true
                self:Hide()
            end
        end)
    end
    local minutes, px, view
    if on then
        view = map.ScrollContainer or map
        local ui = map.GetMapID and map:GetMapID()
        local yards = ui and ns.MinutesYards(ui)
        local canvas = map.GetCanvas and map:GetCanvas()
        local cs = view.targetScale
        if type(cs) ~= "number" then cs = view.GetCanvasScale and view:GetCanvasScale() end
        if type(cs) ~= "number" or cs <= 0 then cs = 1 end
        local cw, vw = canvas and canvas:GetWidth(), view:GetWidth()
        if yards and type(cw) == "number" and type(vw) == "number" and vw > 60 then
            minutes, px = ns.MinutesPick(yards, cw * cs, vw, 7)
        end
    end
    if win then win.seam:SetColorTexture(BRASS[1], BRASS[2], BRASS[3], on and 0.8 or 0.7) end   -- (the seam in brass, every path)
    if not minutes then
        if bar and bar.rule then
            bar.rule:Hide()
            bar.ruleWords:Hide()
            bar.ruleAt = nil
        end
        if mb and mb.wmRuleHid and not on then
            mb.wmRuleHid = nil
            if ns.MinutesRefresh then ns.MinutesRefresh(true) end
        end
        return
    end
    if mb and mb:IsShown() then
        mb.wmRuleHid = true
        mb:Hide()
    end
    local be = bar:GetEffectiveScale()
    local tile = px * view:GetEffectiveScale() / be
    local top, bottom = face:GetTop(), face:GetBottom()
    if not (top and bottom and tile > 4) then return end
    local h = (top - bottom) * face:GetEffectiveScale() / be
    local sig = minutes .. ":" .. math.floor(tile * 10) .. ":" .. math.floor(h) .. ":" .. tostring(slot.side)
    if sig == bar.ruleAt and bar.rule:IsShown() then return end
    bar.ruleAt = sig
    if not bar.rule then
        -- (on a frame of its own in the map's strata, laid in Place: see the rail)
        bar.seamF = CreateFrame("Frame", nil, win)
        bar.seamF:SetAllPoints(win)
        if win.artStrata then bar.seamF:SetFrameStrata(win.artStrata) end
        if win.artLevel then bar.seamF:SetFrameLevel(win.artLevel) end
        bar.rule = bar.seamF:CreateTexture(nil, "ARTWORK")
        bar.rule:SetTexture(RULE_ART, "CLAMP", "REPEAT")
        bar.rule:SetVertexColor(BRASS[1], BRASS[2], BRASS[3], 0.85)
        bar.ruleWords = bar.seamF:CreateFontString(nil, "OVERLAY")
        bar.ruleWords:SetFont(FRIZ, 8, "")
        bar.ruleWords:SetTextColor(0.96, 0.89, 0.72)      -- (Minutes' lettering: pale gold with an umber shade)
        bar.ruleWords:SetShadowColor(0.20, 0.13, 0.07, 1)
        bar.ruleWords:SetShadowOffset(1, -1)
    end
    bar.rule:ClearAllPoints()
    bar.ruleWords:ClearAllPoints()
    bar.rule:SetSize(16, h)
    local reps = h / tile
    if slot.side == "left" then
        bar.rule:SetPoint("TOPLEFT", slot, "TOPRIGHT", GAP, 0)   -- (on the map's edge: "Gap between vertical line and mapart", 2026-11-21)
        bar.rule:SetTexCoord(1, 0, 0, reps)
        bar.ruleWords:SetPoint("BOTTOMLEFT", slot, "BOTTOMRIGHT", GAP + 18, 4)
    else
        bar.rule:SetPoint("TOPRIGHT", slot, "TOPLEFT", -GAP, 0)
        bar.rule:SetTexCoord(0, 1, 0, reps)
        bar.ruleWords:SetPoint("BOTTOMRIGHT", slot, "BOTTOMLEFT", -GAP - 18, 4)
    end
    bar.ruleWords:SetText((minutes == 0.5 and "HALF A MIN" or (minutes .. " MIN")) .. " ON FOOT")
    bar.rule:Show()
    bar.ruleWords:Show()
end

-- The map's clamp grown by the window's bar (top) and log (right), and put back to the map's own when the window goes.
-- (Set on the map, Waymark's own frame: MapControls clamps it to the screen and sets no insets of its own.)
function ClampHold(map, on, top, right, left)
    if not (map and map.SetClampRectInsets) then return end
    if on then
        map:SetClampRectInsets(-(left or 0), right or 0, top or 0, 0)   -- (left: the log on the map's left, Lab/WorldAlone.lua)
        map.wmClamp = true
    elseif map.wmClamp then
        map.wmClamp = nil
        map:SetClampRectInsets(0, 0, 0, 0)
    end
end

local function Place()
    -- (the log alone: its own place, no map round it. Lab/WorldAlone.lua)
    if W.Alone and W.Alone() then
        if panel and W.AlonePlace then W.AlonePlace() end
        return
    end
    local map, face = Map(), Face()
    if not (panel and map and face) then return end
    local c = Cfg()
    local windowed, folded = Windowed(), Folded()
    local scale = (c.scale or 100) / 100 * (ns.AddonScale and ns.AddonScale() or 1)
    slot:SetScale(scale)
    local width = folded and MG.Width() or (c.width or 300)
    slot:SetWidth(width)
    panel:SetScale(scale)
    local edge = windowed and EDGE or 0
    local ps, ms = slot:GetEffectiveScale(), face:GetEffectiveScale()
    local l, r = face:GetLeft(), face:GetRight()
    local screen = UIParent:GetWidth() * UIParent:GetEffectiveScale()
    local need = (width + GAP + edge) * ps
    local side = "right"   -- (the log stands right: the side setting scrapped, the user, 2026-11-22)
    -- (the window: the log stays on the right. The user, 2026-11-21: "bumping into the screen edges tossing the
    -- questlog around is terrible ... Log stays right". The map is held on the screen with the log's room instead)
    -- (the log alone, B: the log stays where you put it, and a log kept on the left half of the screen has the map
    -- open on its right. The user, 2026-11-22: "B, but what if i have the log on the left side?" W.LogSide, only
    -- where the log was last dragged decides; never flipped at a screen edge. Lab/WorldAlone.lua)
    if windowed then side = W.LogSide and W.LogSide() or "right" end
    if side ~= "left" and side ~= "right" then
        side = (r and screen - r * ms or 0) >= need and "right" or "left"
    end
    -- No room on that side (a map as wide as the screen, or one dragged to an edge): the column never hangs off
    -- the screen, it comes in over the map's own edge by what is missing. (Two anchors to the map give it the
    -- map's height, so the game's own clamping is not leaned on.)
    local over = 0
    if l and r and ps > 0 then
        if side == "right" then
            over = math.max(0, r * ms + need - screen) / ps
        else
            over = math.max(0, need - l * ms) / ps
        end
    end
    slot.side = side
    -- (the gutter and the seam reach the map frame's own foot, below its picture's, where the world showed through
    -- (the user's shot, 2026-11-22); the column and the window's glass stay at the picture's foot, so the frame's
    -- band under the map is as thin as over it: "Black bar at the bottom edge of frame is slightly bigger than at top")
    local foot = 0
    local fb, mb = face:GetBottom(), map:GetBottom()
    if fb and mb and ps > 0 then foot = math.min(30, math.max(0, (fb - mb) * ms / ps)) end
    slot.foot = 0   -- (set below, once the frame set's reach is known: no further than its band)
    slot:ClearAllPoints()
    if side == "right" then
        slot:SetPoint("TOPLEFT", face, "TOPRIGHT", GAP - over, 0)
        slot:SetPoint("BOTTOMLEFT", face, "BOTTOMRIGHT", GAP - over, 0)
    else
        slot:SetPoint("TOPRIGHT", face, "TOPLEFT", -GAP + over, 0)
        slot:SetPoint("BOTTOMRIGHT", face, "BOTTOMLEFT", -GAP + over, 0)
    end
    panel:ClearAllPoints()
    panel:SetAllPoints(slot)
    -- (in the map's strata; and come in over the map, it lies over the map's art, which is some 5000 levels
    -- above the map's own, and just under the frame set's corners, ns.MapBorderLevel. The user, 2026-11-20, a
    -- map as wide as the screen: the column came in over its edge and the art covered it.)
    if map.GetFrameStrata and panel:GetFrameStrata() ~= map:GetFrameStrata() then panel:SetFrameStrata(map:GetFrameStrata()) end
    -- (always at the map's art's level, not only when it has come in over the map: the user, 2026-11-21,
    -- "renderlayer issues", the game's quest log and the talents between the map's art and the column. A window
    -- of the map's strata with a level between the map's own and its art's drew over the column and under the map)
    local high = math.max(1, map:GetFrameLevel() + 20)
    if ns.MapBorderLevel then high = math.max(high, ns.MapBorderLevel(map) - 2) end
    panel:SetFrameLevel(high)
    -- (the window's glass is the column's ground; the column keeps its own only with no window, or where it
    -- has come in over the map, since the glass lies under the map)
    for _, tex in ipairs(panel.own) do tex:SetShown(not windowed or over > 0) end
    -- The column's glass is solid (2026-11-21: a unit frame showed through the log; shown both, the user: "might
    -- aswell just make it solid tbh"). The window's glass lies under the map, so a frame of a higher level in the
    -- same layer drew over it, under the text: the column and the rail have their own ground on their own level.
    local solid = windowed
    panel.bg:SetColorTexture(SLATE[1], SLATE[2], SLATE[3], solid and 1 or 0.93)
    if solid then panel.bg:Show() end
    if rail then
        if not rail.bg then
            rail.bg = rail:CreateTexture(nil, "BACKGROUND", nil, -8)
            rail.bg:SetAllPoints()
            rail.bg:SetColorTexture(SLATE[1], SLATE[2], SLATE[3], 1)
        end
        rail.bg:SetShown(solid)
    end
    -- (the gutter between the map's edge and the column or rail has the same ground on their level: the user,
    -- 2026-11-21, "Action bars showing through" there. It stops a pixel short of the seam's brass line)
    for _, owner in ipairs({ panel, rail }) do
        if owner then
            if not owner.gut then
                owner.gut = owner:CreateTexture(nil, "BACKGROUND", nil, -8)
                owner.gut:SetColorTexture(SLATE[1], SLATE[2], SLATE[3], 1)
            end
            local g = owner.gut
            g:ClearAllPoints()
            if slot and slot.side == "left" then
                g:SetPoint("TOPLEFT", owner, "TOPRIGHT", 0, 0)
                g:SetPoint("BOTTOMLEFT", owner, "BOTTOMRIGHT", 0, 0)
            else
                g:SetPoint("TOPRIGHT", owner, "TOPLEFT", 0, 0)
                g:SetPoint("BOTTOMRIGHT", owner, "BOTTOMLEFT", 0, -(slot.foot or 0))
            end
            g:SetWidth(GAP - 1)
            g:SetShown(solid)
        end
    end
    if not (win and windowed) then
        GripHold(false)
        ClampHold(map, false)
        return
    end
    win:SetScale(scale)
    if map.GetFrameStrata and win.SetFrameStrata then win:SetFrameStrata(map:GetFrameStrata()) end
    win:SetFrameLevel(math.max(0, map:GetFrameLevel() - 1))
    -- (the map's art and layers lie far above the map's own level, Style.lua's ns.MapBorderLevel: what of ours
    -- may reach over the map's face, the bar, the rail and the frame set's corners, goes over the art too)
    local above = ns.MapBorderLevel and (ns.MapBorderLevel(map) + 4) or high
    -- (the map's BorderFrame lies a strata higher than the map, HIGH, and takes the mouse out a little over the
    -- map's edge: the lower half of the fold chevron could not be clicked, the user's /fstack, 2026-11-21. As
    -- Dock.lua's rim STRIP.bands: the bar and the rail in the border's strata, just over it)
    local bf, strata = map.BorderFrame, map.GetFrameStrata and map:GetFrameStrata()
    if bf and bf.GetFrameStrata and strata and bf:GetFrameStrata() ~= strata then
        strata, above = bf:GetFrameStrata(), bf:GetFrameLevel() + 10
    end
    if strata and bar:GetFrameStrata() ~= strata then bar:SetFrameStrata(strata) end
    bar:SetFrameLevel(above)
    -- (the rail and the seam's ruler run the window's whole height: in the map's own strata at its art's level, so
    -- another window over the map is over them too; in the border's strata they drew over the talents, 2026-11-21.
    -- Only the bar, above the map, keeps the border's strata for its clicks)
    local mapStrata = map.GetFrameStrata and map:GetFrameStrata()
    win.artStrata, win.artLevel = mapStrata, ns.MapBorderLevel and (ns.MapBorderLevel(map) + 4) or high
    for _, f in ipairs({ rail, bar.seamF }) do
        if f then
            if mapStrata and f:GetFrameStrata() ~= mapStrata then f:SetFrameStrata(mapStrata) end
            f:SetFrameLevel(win.artLevel)
        end
    end
    -- No room over the map (a map as tall as the screen): the bar never leaves the screen, it comes in over the
    -- map's top by what is missing, on its own glass
    local barH = BarH()
    local lift = barH
    local ftop = face:GetTop()
    if ftop and ps > 0 then
        local room = (UIParent:GetHeight() * UIParent:GetEffectiveScale() - ftop * ms) / ps - 2
        lift = math.max(0, math.min(barH, room))
    end
    win.lift = lift
    win.top:SetShown(barH > 0)
    win.top:ClearAllPoints()
    win.top:SetPoint("TOPLEFT")
    win.top:SetPoint("BOTTOMRIGHT", win, "TOPRIGHT", 0, -math.max(1, barH))
    -- the whole window held on the screen while it is up (the user, 2026-11-21: "Top bar gets all bouncy and buggy
    -- when i hit the top frame of my pc screen"): the map's own clamp is grown by the bar above it and the log on
    -- its right, so a drag stops there and the bar never has to come down over the map
    if side == "left" then
        ClampHold(map, true, (barH + 4) * ps / ms, 0, (width + GAP + 6) * ps / ms)
    else
        ClampHold(map, true, (barH + 4) * ps / ms, (width + GAP + 6) * ps / ms)
    end
    bar.ground:SetShown(lift < barH)
    bar.ground:ClearAllPoints()
    bar.ground:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
    bar.ground:SetPoint("BOTTOMRIGHT", win, "TOPRIGHT", 0, -math.max(1, barH))
    win:ClearAllPoints()
    win.thin:ClearAllPoints()
    win.side:ClearAllPoints()
    win.seam:ClearAllPoints()
    if side == "right" then
        win:SetPoint("TOPLEFT", face, "TOPLEFT", -EDGE, lift)
        win:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", EDGE, -EDGE)
        win.thin:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -barH)
        win.thin:SetPoint("BOTTOMRIGHT", face, "BOTTOMLEFT", 0, 0)
        win.side:SetPoint("TOPLEFT", slot, "TOPLEFT", -GAP, 0)
        win.side:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, EDGE)
        win.seam:SetPoint("TOPLEFT", slot, "TOPLEFT", -GAP, 0)   -- (the seam on the map's edge, no glass between)
        win.seam:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", -GAP, 0)
    else
        win:SetPoint("TOPLEFT", slot, "TOPLEFT", -EDGE, lift)
        win:SetPoint("BOTTOMRIGHT", face, "BOTTOMRIGHT", EDGE, -EDGE)
        win.thin:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, -barH)
        win.thin:SetPoint("BOTTOMLEFT", face, "BOTTOMRIGHT", 0, 0)
        win.side:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -barH)
        win.side:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", GAP, 0)
        win.seam:SetPoint("TOPRIGHT", slot, "TOPRIGHT", GAP, 0)
        win.seam:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", GAP, 0)
    end
    rail:ClearAllPoints()
    rail:SetAllPoints(slot)
    local key = FrameKey()
    local dress = not key and DressOf()
    for _, line in ipairs(win.lines) do line:SetShown(not key and not dress) end
    -- (a frame set's corner ornaments stand in the window's corners: the bar's first word and its buttons
    -- keep clear of them. Seen when the window was drawn out from this code, 2026-11-20. 32: a corner's units)
    local clear = key and math.floor(32 * (ns.LabSetScale and ns.LabSetScale(key) or 1) * (CLOSE_ART.scale[key] or 1) * 0.45 + 0.5) or dress and 14 or 8
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", win, "TOPLEFT", clear, 0)
    bar:SetPoint("TOPRIGHT", win, "TOPRIGHT", 2 - clear, 0)
    -- (no bar: a sliver along the frame's top keeps the bar's frame (its path steps, its buttons) without taking
    -- the map's clicks; the plate at the seam is the handle then)
    bar:SetHeight(barH > 0 and BAR or 1)
    bar:EnableMouse(barH > 0)
    -- The fold chevron stands still: on the map's side of the seam between map and log, which does not move when
    -- the log folds (the user, 2026-11-21: "the folding > moves, which means to get a quick peek at quests i need
    -- to chase the <"). The cog and the count beside it, away from the seam. The X stands in the window's
    -- top-right corner (below, after the frame set).
    local y = barH > 0 and (lift - BAR / 2 + 2) or 1   -- (+2: the bar's middle, the user's shot; no bar: on the frame's top edge)
    bar.fold:ClearAllPoints()
    bar.opts:ClearAllPoints()
    bar.count:ClearAllPoints()
    -- (no bar: the cog and the fold on a small plate set into the frame's top edge at the seam, L1 of
    -- mockups/world-bar.html; the plate is the window's handle then, as the bar is: drag moves, right-click the panel)
    -- (no bar: the cog and the book in the map's own top-right corner, inside, on a soft shadow with no edges. The
    -- user, 2026-11-22, of the brass square: "not really loving the square", then "Top right corner, inside, on the
    -- map. Soft shadow". The corner stays put when the log folds, so the book never moves. The shadow is the
    -- window's handle then, as the bar is: drag moves, right-click the World map panel)
    if not bar.plate then
        local pl = CreateFrame("Frame", nil, bar)
        pl:EnableMouse(true)
        pl:SetScript("OnMouseDown", bar:GetScript("OnMouseDown"))
        pl:SetScript("OnMouseUp", bar:GetScript("OnMouseUp"))
        -- (no shadow of its own: each button has one in its own shape, the user, 2026-11-22, of one under both,
        -- "looks like a smudge. One shadow each, shaped". tools/world_top/shadow_art.py)
        for _, b in ipairs({ bar.opts, bar.fold }) do
            b.shadow = b:CreateTexture(nil, "BACKGROUND")
            b.shadow:SetPoint("CENTER", b.art, "CENTER", 1, -1)
            b.shadow:SetVertexColor(1, 1, 1, 0.9)
        end
        bar.opts.shadow:SetTexture(LAB .. "WorldCogShadow", nil, nil, "TRILINEAR")
        bar.plate = pl
    end
    bar.plate:SetShown(barH == 0)
    for _, b in ipairs({ bar.opts, bar.fold }) do
        local w = b.art:GetWidth() or 16
        b.shadow:SetSize(w * 64 / 48, w * 64 / 48)
        b.shadow:SetShown(barH == 0)
        if b == bar.fold and b.artFor and b.shadowFor ~= b.artFor then
            b.shadowFor = b.artFor
            b.shadow:SetTexture(b.artFor .. "Shadow", nil, nil, "TRILINEAR")
        end
    end
    if side == "right" then
        if barH == 0 then
            bar.fold:SetPoint("CENTER", face, "TOPRIGHT", -18, -16)
        else
            bar.fold:SetPoint("CENTER", slot, "TOPLEFT", -(GAP / 2 + 15), y)
        end
        bar.opts:SetPoint("RIGHT", bar.fold, "LEFT", -3, 0)
        bar.count:SetPoint("RIGHT", bar.opts, "LEFT", -4, 0)
        bar.plate:ClearAllPoints()
        bar.plate:SetPoint("TOPLEFT", bar.opts, "TOPLEFT", -6, 4)
        bar.plate:SetPoint("BOTTOMRIGHT", bar.fold, "BOTTOMRIGHT", 6, -4)
        bar.plate:SetFrameLevel(math.max(0, bar.opts:GetFrameLevel() - 1))
    else
        -- (the log on the left, Lab/WorldAlone.lua: the same, mirrored; no bar, in the map's top-left corner by the seam)
        if barH == 0 then
            bar.fold:SetPoint("CENTER", face, "TOPLEFT", 18, -16)
        else
            bar.fold:SetPoint("CENTER", slot, "TOPRIGHT", GAP / 2 + 15, y)
        end
        bar.opts:SetPoint("LEFT", bar.fold, "RIGHT", 3, 0)
        bar.count:SetPoint("LEFT", bar.opts, "RIGHT", 4, 0)
        bar.plate:ClearAllPoints()
        bar.plate:SetPoint("TOPLEFT", bar.fold, "TOPLEFT", -6, 4)
        bar.plate:SetPoint("BOTTOMRIGHT", bar.opts, "BOTTOMRIGHT", 6, -4)
        bar.plate:SetFrameLevel(math.max(0, bar.opts:GetFrameLevel() - 1))
    end
    if key then
        -- (the map's own child, as the map's own border is (Frames.lua), so it lies over the map's art; as a
        -- child of the window, at the same level, its corners over the map lay under the art: the user's shots,
        -- 2026-11-21. It keeps the window's scale and its own opacity, not the map's)
        if not win.set then
            win.set = ns.LabFrame(map)
            if win.set.SetIgnoreParentAlpha then win.set:SetIgnoreParentAlpha(true) end
            if win.set.SetIgnoreParentScale then win.set:SetIgnoreParentScale(true) end
            if ns.debugFrames then ns.debugFrames.worldSet = win.set end   -- (/bfi check: its level against the art's)
        end
        local ws = win:GetEffectiveScale()
        win.set:SetScale(win.set.SetIgnoreParentScale and ws or ws / map:GetEffectiveScale())
        local sc = (ns.LabSetScale and ns.LabSetScale(key) or 1) * (CLOSE_ART.scale[key] or 1)
        local out = ns.LabSetOut and ns.LabSetOut(key, sc) or 0
        -- (the gutter and the seam down into the frame's band, no further: past it they stuck out under the frame,
        -- the user's shot, 2026-11-22, "Vertical part where map meets questpanel sticks out under frame")
        local reach = math.min(foot, out)
        if reach ~= slot.foot then
            slot.foot = reach
            win.seam:ClearAllPoints()
            if side == "right" then
                win.seam:SetPoint("TOPLEFT", slot, "TOPLEFT", -GAP, 0)
                win.seam:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", -GAP, -reach)
            else   -- (the log on the left: Lab/WorldAlone.lua)
                win.seam:SetPoint("TOPRIGHT", slot, "TOPRIGHT", GAP, 0)
                win.seam:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", GAP, -reach)
            end
            for _, owner in ipairs({ panel, rail }) do
                local g = owner and owner.gut
                if g then
                    g:ClearAllPoints()
                    if side == "right" then
                        g:SetPoint("TOPRIGHT", owner, "TOPLEFT", 0, 0)
                        g:SetPoint("BOTTOMRIGHT", owner, "BOTTOMLEFT", 0, -reach)
                    else
                        g:SetPoint("TOPLEFT", owner, "TOPRIGHT", 0, 0)
                        g:SetPoint("BOTTOMLEFT", owner, "BOTTOMRIGHT", 0, -reach)
                    end
                end
            end
        end
        win.set:ClearAllPoints()
        win.set:SetPoint("TOPLEFT", win, "TOPLEFT", -out, out)
        win.set:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", out, -out)
        win.set:SetLook(key, sc)
        win.set:Show()
        -- (over the map's art, and kept there: the levels move with no word to us, Style.lua)
        if ns.MapBorderLevel then win.set:SetFrameLevel(ns.MapBorderLevel(map)) end
        if ns.KeepBorderLevel and not win.set.kept then
            win.set.kept = true
            ns.KeepBorderLevel(win.set)
        end
    elseif win.set then
        win.set:Hide()
    end
    -- (the parchment bar was tried and taken out, 2026-11-21: "Remove the parchment it looks bad")
    if dress then
        -- (the map's own child, as the frame set is: over the map's art, with the window's scale and its own opacity)
        if not win.dress then
            win.dress = CreateFrame("Frame", nil, map, "BackdropTemplate")
            win.dress:EnableMouse(false)
            if win.dress.SetIgnoreParentAlpha then win.dress:SetIgnoreParentAlpha(true) end
            if win.dress.SetIgnoreParentScale then win.dress:SetIgnoreParentScale(true) end
            if ns.debugFrames then ns.debugFrames.worldDress = win.dress end
        end
        local ws = win:GetEffectiveScale()
        win.dress:SetScale(win.dress.SetIgnoreParentScale and ws or ws / map:GetEffectiveScale())
        local out = ns.DressBorder and ns.DressBorder(win.dress, win, dress[1], dress[2], dress[4] or 0, dress[3]) or 0
        -- (the edge art is see-through on its inner part and the window's glass stopped at the window's edge, so
        -- the world showed in a thin strip between the bronze and the glass: "GAP", the user's shot, 2026-11-21.
        -- The glass now reaches one pixel out under the border's line, no further: out to the border's outer edge it
        -- showed outside the bronze ("Its showing outside now", the next shot: the line sits further in than the
        -- edge art's outer edge). The look's own inward pull (gap -2) closes the rest. Under the map it is hidden)
        if not win.halo then
            win.halo = win:CreateTexture(nil, "BACKGROUND", nil, -8)
            win.halo:SetColorTexture(SLATE[1], SLATE[2], SLATE[3], 0.93)
        end
        local o = math.min(1, math.max(0, out))
        win.halo:ClearAllPoints()
        win.halo:SetPoint("TOPLEFT", win, "TOPLEFT", -o, o)
        win.halo:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", o, -o)
        win.halo:Show()
        if ns.MapBorderLevel then win.dress:SetFrameLevel(ns.MapBorderLevel(map)) end
        if ns.KeepBorderLevel and not win.dress.kept then
            win.dress.kept = true
            ns.KeepBorderLevel(win.dress)
        end
    elseif win.dress then
        win.dress:Hide()
        if win.halo then win.halo:Hide() end
    end
    -- the close: the corner's own boss cut as an X (the Engraver's, Sun gold's, Moonlit silver's), or the game's X
    local spec = key and CLOSE_ART.boss[key]
    -- (the close follows the frame, the user, 2026-11-21: "Plain glass gets red X, so does parchment and bronze.
    -- Engravers gets the one we made")
    local close = key == "engraver" and "boss" or "game"
    if close == "boss" and not (spec and win.set and win.set.pieces and win.set.pieces[2]) then close = "game" end
    bar.close:SetShown(close == "game")
    bar.boss:SetShown(close == "boss")
    if close == "boss" then
        local piece = win.set.pieces[2]
        if bar.boss.art ~= spec[1] then
            bar.boss.art = spec[1]
            bar.boss:SetNormalTexture(spec[1])
            bar.boss:SetHighlightTexture(spec[1] .. "Lit", "BLEND")
            bar.boss:SetPushedTexture(spec[1] .. "Lit")
            local pushed = bar.boss:GetPushedTexture()
            if pushed then pushed:SetVertexColor(0.8, 0.8, 0.8) end
        end
        bar.boss:ClearAllPoints()
        bar.boss:SetAllPoints(piece)
        -- (only the boss takes the click: its middle and radius in the corner's 128 units)
        local w, h = piece:GetWidth() or 0, piece:GetHeight() or 0
        local cx, cy, r = spec[2], spec[3], spec[4]
        bar.boss:SetHitRectInsets(w * (cx - r) / 128, w * (128 - cx - r) / 128, h * (cy - r) / 128, h * (128 - cy - r) / 128)
    else
        -- The game's red X fixed in the corner (the user, 2026-11-21: "Make the red x fix the corner on plain glass
        -- border, and the others that are not engreaves"): on the mitre (Forever bronze, Book cover), on the boss's
        -- middle if the game's X is chosen on a set with one, where the brass lines meet on plain glass.
        bar.close:ClearAllPoints()
        local piece = key and win.set and win.set.pieces and win.set.pieces[2]
        if piece then
            local at = spec and { spec[2] / 128, spec[3] / 128 } or CLOSE_ART.at[key] or CLOSE_ART.at.other
            bar.close:SetPoint("CENTER", piece, "TOPLEFT", (piece:GetWidth() or 0) * at[1], -(piece:GetHeight() or 0) * at[2])
        else
            bar.close:SetPoint("CENTER", win, "TOPRIGHT", -7, -7)
        end
    end
    GripHold(win:IsShown())
end
ns.WorldPanelPlace = Place

-- the map whose quests the list shows: the zone on view; or a dungeon, a cave or any other map of its own
-- (so a dungeon's quests have a home: its own map); nil on a continent and the world
local function ListMap(id)
    local zone = W.ZoneMap(id)
    if zone then return zone end
    local info = id and C_Map.GetMapInfo(id)
    if info and T.Zone and info.mapType and info.mapType > T.Zone then return id end
end

-- the big map asked to fit itself again: its room changed (this switched on or off, the column's width or size)
function Refit()
    if ns.UpdateMapShape and ns.MapIsBig and ns.MapIsBig() and not (ns.Docked and ns.Docked()) then
        ns.Safe("World log refit", ns.UpdateMapShape, false, true)
    end
end
function ns.WorldPanelResized()
    Refit()
    if panel and (panel:IsShown() or win and win:IsShown()) then Place() end
    dirty = true
end

function Refresh()
    if not (panel and W.Ready()) then return end
    local winUp = win and win:IsShown()
    if not (panel:IsShown() or winUp) or not dirty then return end
    dirty = false
    local c = Cfg()
    local id = MapID()
    -- (the log can stand on its own place: a right-click on its title takes it out to the continent, and it stays
    -- there while the map moves, until a zone is picked: the user, 2026-11-22, "Allow rightclick on titlebar to
    -- take questlog out to continentveiw. Log stays where you last put it. This way we dont have to move maps")
    local at = c.logAt or id
    -- (a quest's page wears its own zone: name, crest, colour, plaque, whatever the map shows. The user, 2026-11-22:
    -- "Quest page switches to azeroth backing when q is in tel")
    local pageZone = S.page and W.ZoneOf and W.ZoneOf(S.page)
    if pageZone then at = pageZone end
    local zone = W.ZoneMap(at)
    local list = ListMap(at)
    local n = #W.Held()
    local max = C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept() or MAX_QUESTS or 25
    if winUp then
        DrawBar(id, n .. " / " .. max)
        DrawRail(ListMap(id))
    end
    if not panel:IsShown() then return end
    if Cfg().newNote and W.NewLogNote then W.NewLogNote() end
    -- (a continent or the world has no list map: its plaque's figure comes from its own map, W.cartMotif)
    DrawHead(list and MapName(list) or at and MapName(at) or "", list or (TopStyle() == "cartouche" and at and W.cartMotif[at] and at) or nil, n .. " / " .. max)
    -- (the emblem: on a zone the banner's compass, on a continent Waymark's own mark: the user, 2026-11-22, "one on
    -- cont and one on zone perhaps". tools/world_top/emblem_art.py)
    if panel.emblem then
        -- (a zone or a continent: its own outline, the game's; a continent the rhumb rose over it too, as a chart has
        -- its rose on the sea. No outline to be had: the banner's compass on a zone)
        local shape = W.OutlineOf(zone or list)
        local drawn = shape and panel.outline and W.LayOutline(panel, shape)
        if not drawn and panel.outline then panel.outline:Hide() panel.outlineIn:Hide() end
        local em = (not zone) and "EmblemRose" or (not drawn) and "EmblemCompass" or nil
        -- (the people who hold the zone: their crest, the game's own, grey and tinted brass, as if engraved; a
        -- continent its quarrel's two banners: W.LayEmblem)
        if W.LayEmblem(panel, zone, (not zone) and (list or at) or nil) then
            -- (laid)
        elseif em then
            em = LAB .. em
            if panel.emblemFor ~= em then
                panel.emblemFor = em
                panel.emblem:SetTexture(em)
                panel.emblem:SetTexCoord(0, 1, 0, 1)
                panel.emblem:SetDesaturated(false)
                panel.emblem:SetBlendMode("BLEND")
                panel.emblem:SetVertexColor(0.84, 0.66, 0.38, 0.035)
            end
            panel.emblem:SetSize(zone and 180 or 150, zone and 180 or 150)
            panel.emblem:Show()
        else
            panel.emblem:Hide()
        end
    end
    -- (the sweep in the zone's own colour: ZONE_TINT, each zone's feel, by hand; the continent washes were all ochre,
    -- and Teldrassil had none: "Cant see the color", the user, 2026-11-22)
    local rgb = ZONE_TINT[zone or 0] or ZONE_TINT[list or 0] or ZONE_TINT[W.Continent and W.Continent(at) or 0]
    if rgb and panel.sweep then
        -- (quieter: "tone down the brights and intensity quite abit", the user, 2026-11-22; forests a deeper green)
        panel.sweep:SetVertexColor(rgb[1] * 0.8, rgb[2] * 0.8, rgb[3] * 0.8, 0.38)
        panel.sweep:Show()
    elseif panel.sweep then
        panel.sweep:Hide()
    end
    tools.held:Mark(c.mode ~= "done")
    tools.done:Mark(c.mode == "done")
    for key, b in pairs(tools.chips) do b:Mark(S.filter == key) end
    scroll:ClearAllPoints()
    scroll:SetPoint("BOTTOMRIGHT", -PAD_L, 22)
    scroll:SetPoint("TOPLEFT", tools, "BOTTOMLEFT", 0, -6)
    content:SetWidth(slot:GetWidth() - 2 * PAD_L)
    local lines
    if not S.page then S.chain = nil end
    if S.page then lines = (S.chain == S.page and W.One("chain") and W.ChainLines(S.page)) or PageLines(S.page)
    elseif S.search ~= "" and #S.search >= 2 then lines = SearchLines()
    elseif c.mode == "done" then lines = DoneLines(zone, list or at)
    else lines = HeldLines(list) end
    -- (the log alone with L on it, and no key yet for the world map: one quiet line to where it is set. The player
    -- critic's idea, 2026-11-23: M promised where it is the game's)
    if not S.page and W.Alone and W.Alone() and W.AloneTakesL and W.AloneTakesL() and GetBindingKey and not GetBindingKey("BFI_BIGMAP") then
        lines[#lines + 1] = { text = "World map: no key yet", colour = DIM, size = 11.5, indent = 6,
                              click = function(button)
                                  if button == "RightButton" then return end
                                  if ns.OpenOptionsPage then ns.Safe("World map key", ns.OpenOptionsPage, "bigworld") end
                              end }
    end
    local footed = false
    for _, l in ipairs(lines) do if l.foot then footed = true end end
    -- (a controller's hint inside the window, over the page's buttons: under the frame's foot it hung out on the
    -- game's ground. The user's shot, 2026-11-22, "on controller")
    local base = footed and 22 + 34 or 22
    local hintH = panel.pad and 16 or 0
    scroll:SetPoint("BOTTOMRIGHT", -PAD_L, base + hintH)
    padHint:ClearAllPoints()
    padHint:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD_L, base + 2)
    padHint:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD_L, base + 2)
    padHint:SetJustifyH("LEFT")
    padHint:SetWordWrap(false)
    Render(lines)
    -- (the Lab's one log: when the log comes up on its list, the quest you are on is in view. Once an opening, never
    -- while you read: the list does not move under the pointer)
    if not panel.oneHook then
        panel.oneHook = true
        panel:HookScript("OnShow", function() S.leadWant = true end)
        S.leadWant = true
    end
    if S.leadWant then
        S.leadWant = nil
        if not S.page and W.Lead() then
            for _, r in ipairs(rows) do
                if r:IsShown() and r.line and r.line.under and r.y then
                    local top, tall = scroll:GetVerticalScroll() or 0, scroll:GetHeight() or 0
                    if r.y < top or r.y + (r.h or 18) > top + tall then
                        if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
                        scroll:SetVerticalScroll(math.max(0, r.y - 40))
                    end
                    break
                end
            end
        end
    end
    panel.laid = scroll:GetHeight()
    local onActs = S.sel and lines[S.sel] and lines[S.sel].acts
    padHint:SetText(not panel.pad and "" or onActs and "Left Right choose   A press   B back"
        or ("A open   B back   X track   Y tabs" .. (winUp and ", hold: fold" or "") .. "   LB RB zones"))   -- (one line in the window)
end

-- the quest log beside the world map switched off (worldLog.sidebar false): the map alone. A dev switch since the
-- user's rule of 2026-11-22, "With classic ticked, worldmap is off": Classic brings the big map and its classic window
-- back, New the world map with this log; nothing in the settings sets it
function ns.WorldSidebarOff()
    local c = ns.db and ns.db.worldLog
    return c and c.sidebar == false or false
end

-- every place of the zone page open again (a controller's A on a place's head folds it: for the dry run)
function W.PlacesOpenAll() S.placeShut = nil end

-- Once, the first time the log shows for a player who had the classic quest window on the quest log key: what changed,
-- and the way back. Settings set newNote at the update (BattlefieldInfo.lua / Setups.lua). The user, 2026-11-22: "New
-- log if they had the old. Are we able to make a note appear on the first open, if they were using the old one?"
function W.NewLogNote()
    local c = Cfg()
    if not c.newNote or not ns.Ask then return end
    -- (never in a fight: it waits for the next look after one. The player critic, 2026-11-23)
    if InCombatLockdown and InCombatLockdown() then return end
    c.newNote = nil
    local key = W.QuestKeyName and W.QuestKeyName() or "L"
    ns.Ask({ text = "Waymark has a new quest log. " .. key .. " opens it now, beside the world map or on its own.",
             sub = "The old quest window is still there (the big map comes back with it): Settings, Quest log, Your quest log, Classic.",
             ok = "Keep the new one", cancel = "Use the old one",
             -- (the old one only from its own button: Escape, a pad's B or a hide keep the new log. The release critic,
             -- 2026-11-22: a habit's Escape turned the world map off with no word)
             onNo = function() if ns.SetQuestLogKind then ns.SetQuestLogKind("classic") end end })
end

function ns.WorldPanelChanged()
    dirty = true
    if panel and (panel:IsShown() or win and win:IsShown()) then ns.Safe("World log", Refresh) end   -- (folded too: the bar)
end

-- a quest's page in our log, when the world map is up (a pin's "quest details", ns.OpenQuest in Tracker.lua): true if
-- it opened, the log unfolded if it was folded. The user, 2026-11-22, of "quest details" opening the other window
-- with the world map up: "do ikt"
function ns.WorldPanelOpenQuest(id)
    if not (id and panel and (panel:IsShown() or win and win:IsShown())) then return false end
    -- (or the log alone, the map shut: ns.OpenQuest opens it first with the new log picked)
    if ns.WorldMapUp and not ns.WorldMapUp() and not (W.Alone and W.Alone()) then return false end
    S.page, S.sel, S.anchor, S.chain = id, nil, nil, nil
    if Folded() then Fold(false) end
    scroll:SetVerticalScroll(0)
    dirty = true
    ns.Safe("World log", Refresh)
    return true
end

-- the chain of a quest as one scroll, from outside (the Lab's one log: As told's panel, "before this" and its turned
-- in page; Lab/OneLog.lua's ns.OneLogOpen): true when it showed it. Opens the log as ns.OpenQuest does: in the world
-- map when that is up, else the log alone where the new log is picked. false: no chain, the switch off, or no log
-- to show it in (the caller then opens the quest its own way).
function ns.WorldPanelOpenChain(id)
    if not (id and W.One("chain") and W.Beads(id)) then return false end
    if not ns.WorldPanelOpenQuest(id) then
        if not (ns.QuestLogKind and ns.QuestLogKind() == "new" and W.AloneOpen) then return false end
        if not (W.Alone and W.Alone()) then W.AloneOpen() end
        if not ns.WorldPanelOpenQuest(id) then return false end
    end
    if not W.ChainOpen(id) then return false end
    dirty = true
    ns.Safe("World log", Refresh)
    return true
end

-- A controller ----------------------------------------------------------------------------------

local function Step(dir)
    local lines = S.lines or {}
    local i = S.sel or (dir > 0 and 0 or #lines + 1)
    for _ = 1, #lines do
        i = i + dir
        if i < 1 or i > #lines then return end
        if lines[i].click and not lines[i].quiet then break end
    end
    if not (lines[i] and lines[i].click and not lines[i].quiet) then return end
    S.sel, S.act = i, 1
    local r = rows[i]
    if r and r.y then
        local top, view = scroll:GetVerticalScroll(), scroll:GetHeight()
        if r.y < top then scroll:SetVerticalScroll(r.y) elseif r.y + r.h > top + view then scroll:SetVerticalScroll(math.min(scroll.range or 0, r.y + r.h - view)) end
    end
    local l = lines[i]
    if l.enter then l.enter() end
end

function ns.WorldPanelPad(button)
    -- (Y waits for its release: a tap flips Held and Done, held 0.4 s it folds the log; ns.WorldPanelPadUp)
    if button == "PAD4" then
        S.yDown = GetTime and GetTime() or 0
        return
    end
    if Folded() then
        local list = S.rail or {}
        if button == "PADDUP" or button == "PADDDOWN" then
            if #list == 0 then return end
            S.railSel = math.max(1, math.min(#list, (S.railSel or 0) + (button == "PADDDOWN" and 1 or -1)))
            if ns.HoverQuestGlow then pcall(ns.HoverQuestGlow, list[S.railSel].id) end
        elseif button == "PAD1" then
            local h = S.railSel and list[S.railSel]
            if not h then return end
            if h.zone then
                S.railSel = nil
                GoTo(h.zone)
                return
            end
            S.page, S.sel = h.id, nil
            Fold(false)
        elseif button == "PAD2" then
            if ns.ToggleBigMap then ns.ToggleBigMap() end
        else
            return
        end
        dirty = true
        Refresh()
        return
    end
    local lines = S.lines or {}
    local l = S.sel and lines[S.sel]
    if button == "PADDUP" then Step(-1)
    elseif button == "PADDDOWN" then Step(1)
    elseif (button == "PADDLEFT" or button == "PADDRIGHT") and l and l.fold and not l.acts then
        if (l.open and true or false) ~= (button == "PADDRIGHT") then l.fold() end
    elseif (button == "PADDLEFT" or button == "PADDRIGHT") and l and l.acts then
        S.act = math.max(1, math.min(#l.acts, (S.act or 1) + (button == "PADDRIGHT" and 1 or -1)))
    elseif button == "PAD1" then
        local a = l and l.acts and l.acts[math.min(S.act or 1, #l.acts)]
        if a then a[2]()
        elseif l and l.click then l.click("LeftButton") end
    elseif button == "PAD2" then
        if S.page then S.page, S.sel = nil, nil
        elseif S.filter or S.search ~= "" then S.filter = nil tools.edit:SetText("")
        elseif W.Alone and W.Alone() and W.AloneClose then W.AloneClose()   -- (the log alone: B closes it)
        elseif ns.ToggleBigMap then ns.ToggleBigMap() end
    elseif button == "PAD3" then
        local id = S.page or (l and l.id)
        if id then ToggleTrack(id) end
    elseif button == "PADLSHOULDER" or button == "PADRSHOULDER" then
        local list = {}
        for map, n in pairs(W.Counts()) do
            if n.held > 0 or n.loose > 0 then list[#list + 1] = map end
        end
        table.sort(list, function(a, b) return MapName(a) < MapName(b) end)
        -- (the log alone steps its own place, logAt: MapID stays where you stand. Lab/WorldAlone.lua)
        local here, at = W.ZoneMap((W.Alone and W.Alone() and Cfg().logAt) or MapID()), 0
        for i, m in ipairs(list) do if m == here then at = i end end
        local nxt = list[(at - 1 + (button == "PADRSHOULDER" and 1 or -1)) % math.max(1, #list) + 1]
        if nxt then S.page, S.sel = nil, nil GoTo(nxt) end
    else
        return
    end
    dirty = true
    Refresh()
end

function ns.WorldPanelPadUp(button)
    if button ~= "PAD4" or not S.yDown then return end
    local long = (GetTime and GetTime() or 0) - S.yDown >= 0.4
    S.yDown = nil
    if long and Windowed() then
        Fold()
    elseif not Folded() then
        local c = Cfg()
        c.mode = c.mode == "done" and "held" or "done"
        S.page, S.sel = nil, nil
    end
    dirty = true
    Refresh()
end

-- When it shows ---------------------------------------------------------------------------------

local closingNow   -- (MapControls' WorldClose: the window goes before the map changes, not a tick after)
local function Wanted()
    local map = Map()
    if closingNow then return false end
    if not (ns.db and ns.db.worldLog and map and W.Ready()) then return false end
    if not Cfg().on then return false end
    -- (the quest log beside it off: the map alone, as the big map was, the classic quest window on L. The user,
    -- 2026-11-22: "Worldmap settings need a setting to disable this sidebar. That way we in effect keep the bigmap +
    -- classic log". worldLog.sidebar, on unless false; the settings page's row is Settings small fixes')
    if ns.WorldSidebarOff() then return false end
    if W.Alone and W.Alone() then return true end   -- (the log alone, no map: Lab/WorldAlone.lua)
    if not (map:IsShown() and ns.MapIsBig and ns.MapIsBig()) then return false end
    -- (never round the docked square: docked, the key lends the dock out and opens this at its own place,
    -- MapControls' WorldFromDock. Fix 7 of the switch's report)
    if ns.Docked and ns.Docked() then return false end
    return true
end

local function Tick()
    local want = Wanted()
    if want and not panel then Make() end
    if not panel then return end
    -- the window is up whenever this is; the column only while the log is not folded
    local wantWin = want and Windowed() and not (W.Alone and W.Alone())   -- (the log alone: no window round it)
    local wantPanel = want and not Folded()
    if wantWin and not win then MakeWin() end
    local winUp = win and win:IsShown() or false
    if wantPanel ~= panel:IsShown() or wantWin ~= winUp then
        panel:SetShown(wantPanel)
        if win then win:SetShown(wantWin) end
        if want then
            Place()
            dirty = true
        elseif ns.HoverQuestGlow then
            pcall(ns.HoverQuestGlow, nil)
        end
        if not wantWin then GripHold(false) end
        CloseRest(wantWin)
        BorderHold()
    end
    -- (the grip put back in the map's corner by something else, a setting changed: in the window's again)
    if wantWin and gripMoved then
        local grip = ns.debugFrames and ns.debugFrames.grip
        if grip and select(2, grip:GetPoint(1)) ~= win then GripHold(true) end
    end
    if not want then return end
    -- The map moved or changed size (its glide to big, a drag, a new shape): placed again, so the side it
    -- stands on and how far it comes in are right at the end of the glide and not only at its start. And the
    -- list's own height changed (the first drawing reads it before the frame is laid out; the glide; the little
    -- world folding): drawn again, so the scroll's reach is the true one.
    local map = Map()
    local at = math.floor((map:GetLeft() or 0) + 0.5) .. ":" .. math.floor(map:GetWidth() + 0.5) .. ":" .. math.floor(map:GetHeight() + 0.5)
        .. ":" .. tostring(Folded()) .. tostring(FrameKey()) .. tostring(Cfg().side)
    if at ~= panel.mapAt then
        panel.mapAt = at
        Place()
        dirty = true
    end
    if wantWin then SeamRule() end   -- (the neatline's ruler down the seam: follows the zoom; cheap when unchanged)
    if panel:IsShown() and panel.laid and math.abs(scroll:GetHeight() - panel.laid) > 0.5 then dirty = true end
    if wantWin and Folded() and math.abs((rail:GetHeight() or 0) - (rail.laid or 0)) > 0.5 then
        rail.laid = rail:GetHeight() or 0
        dirty = true
    end
    local id = MapID()
    if id ~= shownFor then
        shownFor = id
        S.sel = nil
        dirty = true
    end
    -- (a controller's buttons come to the panel only in controller mode; never in a fight: the frame is ours,
    -- but taking the pad's buttons while you fight would take your jump)
    local pad = PadMode() and not InCombatLockdown()   -- (on whenever you play with a controller: no setting)
    local host = wantWin and win or panel   -- (the window is up folded or not: it takes them where there is one)
    if pad ~= panel.pad or host ~= panel.padHost then
        if panel.padHost and panel.padHost ~= host and panel.padHost.EnableGamePadButton then
            pcall(panel.padHost.EnableGamePadButton, panel.padHost, false)
        end
        panel.pad, panel.padHost = pad, host
        if host.EnableGamePadButton then pcall(host.EnableGamePadButton, host, pad and true or false) end
        dirty = true
    end
    if dirty then ns.Safe("World log", Refresh) end
end

-- The world map is a thing of its own (MapControls' WorldOpen / WorldClose, 2026-11-22): on, there is no big map;
-- the window comes and goes in the same frame as the map's change, never a tick apart
function ns.WorldMapOn()   -- (the old test, kept for callers: the switch is ns.MapKind, MapControls)
    return ns.MapKind and ns.MapKind() == "world" and W.Ready() and true or false
end
function ns.WorldMapHideNow()
    closingNow = true
    local ok, err = pcall(Tick)
    closingNow = nil
    if not ok then error(err) end
end
function ns.WorldMapShowNow() Tick() end

local ticker = CreateFrame("Frame")
local since = 0
ticker:SetScript("OnUpdate", function(_, e)
    since = since + e
    if since < 0.1 then return end
    since = 0
    -- (asleep while there is no world map and none of it is up: fix 10 of the switch's report)
    if not (panel and (panel:IsShown() or win and win:IsShown())) and not (W.Alone and W.Alone()) then
        local m = Map()
        if not (m and m:IsShown() and ns.MapIsBig and ns.MapIsBig() and ns.MapKind and ns.MapKind() == "world") then return end
    end
    if ns.Safe then ns.Safe("World log tick", Tick) else Tick() end
end)

-- the big map leaves room for the panel, as it does for the quest window that opens with it (MapControls'
-- ScreenRoom asks ns.QuestLogSideRoom); and while this is on, that window does not open with the big map too
local sideRoom, followBig = ns.QuestLogSideRoom, ns.QuestLogFollowBig
function ns.QuestLogSideRoom()
    local on = ns.db and ns.db.worldLog and Cfg().on
    if on then
        local c = Cfg()
        local w = (c.fold and S.railW or (c.width or 300)) + 2 * EDGE
        return w * (c.scale or 100) / 100 * (ns.AddonScale and ns.AddonScale() or 1) + 12
    end
    return sideRoom and sideRoom() or 0
end
function ns.QuestLogFollowBig(big)
    if ns.db and ns.db.worldLog and Cfg().on then
        if C_Timer then C_Timer.After(0.55, function() if panel and (panel:IsShown() or win and win:IsShown()) then Place() end end) end
        return
    end
    if followBig then return followBig(big) end
end

function ns.WorldPanelInfo()
    local c = Cfg()
    if not c.on then return "the world map of our own is off." end
    if not W.Ready() then return "on, but the quest data is not there yet." end
    local held, loose = #W.Held(), #W.Loose()
    return ("on. %d quests held, %d loose ends. %s"):format(held, loose,
        panel and panel:IsShown() and "The panel is up." or "Make the map big to see it (the Big map key, or the map's arrow button).")
end

-- The stick check (the test bench's button; a controller plugged in). The question it settles in the game: can
-- a frame of ours read a controller's sticks. The client's own documentation says yes, two ways (read 2026-11-19
-- from the Forever client: C_GamePad.GetDeviceMappedState gives every stick's x, y and length to anyone who asks;
-- Frame:EnableGamePadStick with OnGamePadStick hands the sticks to one frame, "protected" only as Show and
-- SetScale are: on a protected frame in a fight, which ours is not). Eight seconds, never in a fight:
--   the first four  Waymark only LOOKS at the sticks (takes nothing: you still walk and turn)
--   the last four   a frame of ours TAKES the sticks (you should stand still)
-- It says what it saw in the chat and keeps it in the Lab's settings (stickCheck) for a session to read. The
-- control that tells "no controller" from "sticks not moved" from "the game gave us nothing": the controller's
-- name and its count of sticks are read first, and each half reports its own number.
local stick
function ns.WorldPanelStickCheck()
    local function Say(s) print("|cffc79a52Waymark|r: " .. s) end
    if InCombatLockdown() then return "Not in a fight. Try again after it." end
    if stick and stick.run then return "The stick check is running." end
    if not (C_GamePad and C_GamePad.GetDeviceMappedState) then return "This client has no way to read a controller." end
    local ok, st = pcall(C_GamePad.GetDeviceMappedState)
    if not (ok and type(st) == "table") then return "No controller is seen. Plug one in, press a button on it, and press this again." end
    if not stick then
        stick = CreateFrame("Frame", nil, UIParent)
        stick:SetSize(1, 1)
        stick:SetPoint("CENTER")
        stick:SetScript("OnGamePadStick", function(self, _, _, _, len)
            local run = self.run
            if run then
                run.taken = run.taken + 1
                if type(len) == "number" and len > run.takenMost then run.takenMost = len end
            end
        end)
    end
    local blocked = WaymarkDB and type(WaymarkDB.blockedLog) == "table" and #WaymarkDB.blockedLog or 0
    local run = { t = 0, read = {}, taken = 0, takenMost = 0, took = false, name = tostring(st.name or "?"), sticks = st.stickCount or 0 }
    stick.run = run
    local function Done(why)
        if stick.EnableGamePadStick then pcall(stick.EnableGamePadStick, stick, false) end
        stick:SetScript("OnUpdate", nil)
        stick:Hide()
        stick.run = nil
        local most = 0
        local parts = {}
        for i, v in pairs(run.read) do
            parts[#parts + 1] = ("stick %d %.2f"):format(i, v)
            if v > most then most = v end
        end
        table.sort(parts)
        local now = WaymarkDB and type(WaymarkDB.blockedLog) == "table" and #WaymarkDB.blockedLog or 0
        Cfg().stickCheck = { when = date and date("%Y-%m-%d %H:%M") or "", name = run.name, sticks = run.sticks, read = most, taken = run.taken,
                             takenMost = run.takenMost, canTake = stick.EnableGamePadStick and true or false, blocked = now - blocked, ended = why }
        Say(("Stick check done (%s). Controller: %s, %d sticks."):format(why, run.name, run.sticks))
        Say(most > 0.2 and ("Looking: yes, Waymark saw the sticks move (" .. table.concat(parts, ", ") .. ").")
            or "Looking: Waymark saw no stick move in the first four seconds.")
        if not stick.EnableGamePadStick then Say("Taking: this client has no way for a frame to take the sticks.")
        elseif run.taken > 0 then Say(("Taking: yes, %d moves came to Waymark's own frame. Did you stand still for those four seconds?"):format(run.taken))
        else Say("Taking: no stick move came to Waymark's frame in the last four seconds.") end
        if now > blocked then Say("The game blocked an action while this ran: /waymark report has it.") end
    end
    stick:Show()
    stick:SetScript("OnUpdate", function(_, e)
        run.t = run.t + e
        if InCombatLockdown() then return Done("a fight began") end
        if run.t < 4 then
            local okS, s = pcall(C_GamePad.GetDeviceMappedState)
            for i, k in ipairs(okS and type(s) == "table" and s.sticks or {}) do
                local len = type(k) == "table" and k.len
                if type(len) == "number" and not (issecretvalue and issecretvalue(len)) and len > (run.read[i] or 0) then run.read[i] = len end
            end
        elseif not run.took then
            run.took = true
            if stick.EnableGamePadStick then pcall(stick.EnableGamePadStick, stick, true) end
            Say("Now Waymark TAKES the sticks, four seconds. Keep moving them: you should stand still.")
        elseif run.t >= 8 then
            Done("eight seconds")
        end
    end)
    return "Eight seconds. Now: move both sticks about and keep them moving. (Waymark only looks: you still walk.)"
end

-- /worldlog: on and off; /worldlog info; /worldlog loose | before | fold | aims: its parts; /worldlog why <id>
SLASH_WAYMARKWORLDLOG1 = "/worldlog"
SlashCmdList.WAYMARKWORLDLOG = function(msg)
    -- (a dev's switches and dumps, not a player's: where DevBar.lua is missing (a release) it says nothing. The code
    -- critic, 2026-11-22)
    if not ns.DevCommands then return end
    local function Say(s) print("|cffc79a52Waymark|r: " .. s) end
    local word = (msg or ""):lower():match("^%s*(%S*)")
    local c = Cfg()
    if word == "info" then
        Say(ns.WorldPanelInfo())
        return
    elseif word == "why" then
        -- (/worldlog why <questID>: each step that finds a quest's ground, for a page that shows none. The user,
        -- 2026-11-22, of Nature's Call: "No area data for Nature's Call? forever Q")
        local id = tonumber((msg or ""):match("why%s+(%d+)"))
        if not id then Say("/worldlog why <quest ID>") return end
        local function Dump(v, depth)
            depth = depth or 0
            if type(v) ~= "table" then return tostring(v) end
            if depth > 2 then return "{..}" end
            local out = {}
            for k, x in pairs(v) do
                out[#out + 1] = (type(k) == "number" and "" or (tostring(k) .. "=")) .. Dump(x, depth + 1)
                if #out > 6 then out[#out + 1] = ".." break end
            end
            return "{" .. table.concat(out, ",") .. "}"
        end
        local function Try(f, ...) local ok, a, b = pcall(f, ...) if ok then return a, b end return "error: " .. tostring(a) end
        local src, qdb = ns.QuestSource and ns.QuestSource(), ns.QDB and ns.QDB()
        Say(("%d %s: source %s, QuestieDB %s, swept row %s, in log %s"):format(id, W.Title(id), tostring(ns.QuestSourceName and ns.QuestSourceName()),
            qdb and "loaded" or "missing", tostring(ns.ForeverSwept and ns.ForeverSwept[id] and true or false), tostring(W.IsHeld(id))))
        if src then
            Say("startedBy " .. Dump(Try(src.Quest.startedBy, id)) .. "  finishedBy " .. Dump(Try(src.Quest.finishedBy, id))
                .. "  objectives " .. Dump(Try(src.Quest.objectives, id)))
        end
        if qdb then
            Say("QuestieDB alone: startedBy " .. Dump(Try(qdb.Quest.startedBy, id)) .. "  objectives " .. Dump(Try(qdb.Quest.objectives, id)))
        end
        local ends = ns.QuestEnds and Try(ns.QuestEnds, id)
        Say("ends " .. Dump(ends) .. "  find map " .. tostring(ns.QuestFindMap and Try(ns.QuestFindMap, id)) .. "  zone " .. tostring(W.ZoneOf(id)))
        local map = W.ZoneOf(id)
        local n, here = 0, false
        if map and ns.QuestGround then
            local g = Try(ns.QuestGround, map)
            for _, q in ipairs(type(g) == "table" and g or {}) do
                n = n + 1
                if q.id == id then here = q.parts and #q.parts or 0 end
            end
        end
        Say(("ground on %s: %d quests, this one %s"):format(tostring(map), n, here and ("with " .. here .. " parts") or "absent"))
        return
    elseif word == "fold" then
        c.fold = not c.fold
        Say("fold is " .. (c.fold and "on." or "off."))
        Refit()
    elseif word == "aims" then
        c.aimsOpen = not c.aimsOpen
        Say("objectives are " .. (c.aimsOpen and "always open." or "open on a tracked quest, or as you rest the pointer on one."))
    elseif word == "sidebar" then
        c.sidebar = c.sidebar == false
        Say("the quest log beside the world map is " .. (c.sidebar and "on." or "off: the map alone."))
        if ns.ApplyQuestWindow then ns.ApplyQuestWindow("shown") end   -- (L: ours or the classic window)
    elseif word == "loose" or word == "before" then
        c[word] = not c[word]
        Say(word .. " is " .. (c[word] and "on." or "off."))
    else
        -- (through the switch, as the settings window does: a map that is up is put away first, MapControls)
        if ns.SetMapKind then ns.SetMapKind(c.on and "big" or "world") else c.on = not c.on end
        Say(c.on and "the world map is yours now: the Big map key opens it." or "the big map is yours now.")
        -- (a map that is big already makes room at once, and takes it back when this goes off)
        Refit()
    end
    dirty = true
    W.Bump()
end
