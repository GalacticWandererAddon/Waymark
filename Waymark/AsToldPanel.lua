local _, ns = ...

-- As told, the panel (the Lab; first mock-up mockups\as-told-panel.html, the user 2026-11-11: "Feels right!").
-- A small dark panel with a gold rule that tells the story of the quest that leads (ns.ToldLead in AsTold.lua),
-- in the giver's own words, without the quest log open. The user's rules: it must belong in a modern UI, be
-- calm, never jump about, carry no detail clutter. Always on its dark glass: "text only, no backdrop" was an
-- option until 2026-11-15 (the user: "unusable. Remove it. Always backdrop"); a saved "off" is ignored.
--
-- How it reads (the user's own design, 2026-11-13, after the first look in game; mock-up
-- mockups\as-told-reading.html, "Mockup is good", and their rules the same hour):
--     always   the quest's name, its count ("3 of 12"), and the story: the sentences that carry it, three lines
--              at most (AsToldLabels.lua: every quest read once, a letter a sentence; a quest not yet read
--              shows how the giver began)
--     details  the whole telling but for the chaff, in the giver's order, flavour and all, the ask and the way
--              in the way's colour; what the game asks in its one line; who gave it; the chain's earlier steps
--              with what the giver said at the end (words the game's own log throws away). They show while the
--              pointer is on the panel; a left click keeps them there until the next click; a quest held from
--              the menu shows them too; and for 25 s after a quest is taken. Standing at the quest's place does
--              NOT unfold them (it only makes that quest lead, when none is held).
--     list     the wheel on the panel unfolds your other quests under it (those that speak of where you stand
--              first; beside a name the place its giver named). The pointer marks a name, a left click selects
--              it, a right click holds it until handed in. The list folds when the pointer leaves.
--   A bare "Done." is never shown ("its useless... just a checkmark"); a finished quest says who to go back to.
--   When it changes by itself: a quest taken, handed in or dropped, a new place entered. Never while walking.
--   Never under the pointer either (the user, 2026-11-15, reading it while walking out of a town: "the quest in
--   focus while hovering tries to fade out of focus, or even switches"): a place entered while the pointer is
--   on the panel counts when the pointer leaves. The count is the quest's place among your quests, the newest
--   first, wherever you stand (it was its place in the list, which puts the quests of where you stand first:
--   "11 of 12 in town but 1 of 12 1 step later").
--   What the pointer brings fades in softly (0.3 s) with the rest standing still; so does a small change with
--   the same quest leading (the "more quests here" line at a town's edge); another quest leading fades out and
--   in. The glass is full under every letter and fades out beyond them. In a fight the panel stays
--   as it is ("I dont really want as told to fold when in combat. Need a choice"): stepping aside is in its menu.
--
--   Controls (the one scheme, Controls.lua): click = keep the details open, or let them fold; wheel = your
--   other quests; right-click = its menu; Ctrl-drag = move it; Shift-click = the quest's link into the chat.
--   /told next and /told prev lead with the next quest (for a macro, a key or a gamepad button); /told list.
--   Nothing here is protected: in a fight the drag and the menu are simply ignored.
--
--   The words are the quest's own, picked, never rewritten: how it began = the quest text's first sentences;
--   the way = the sentences that say where (AsToldRead.lua). A quest that reads badly this way wants a line
--   written for it; none are yet.

local W, PAD = 300, 14
local OPEN_FOR = 25          -- seconds a newly taken quest keeps its details open
local NEXT_FOR = 8           -- and one brought up by /told next
local EDGE = 18              -- the glass fades out over this much at the right, beyond the words (36 until 2026-11-15: "longer than it has to be")
local FADE, GROW = 0.3, 0.45
local SOFT_IN = 0.3          -- what the pointer brings fades in over this ("soft but not too slow": the user)
local TEXT = { 0.91, 0.89, 0.85 }
local SOFT = { 0.66, 0.64, 0.58 }
local FAINT = { 0.46, 0.44, 0.40 }
local WAY = { 0.85, 0.81, 0.71 }
local GOLD = { 0.73, 0.55, 0.32 }
-- (what the game asks, under the telling: a warm parchment gold, and its small heading in the rule's gold. A
-- player, 2026-11-17: "can you change the text a bit for the Asked section so that it stands out a little more?
-- Maybe change the font color?" It was the way's pale colour under a grey heading, a shade off the telling.)
local ASK = { 0.96, 0.84, 0.58 }
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local function Cfg() return ns.ToldCfg() end

local panel, body, back, rule, mark, watch
local lines = {}
local openUntil = 0     -- the details stay open until then
local hover, pinned, listOpen
local hidden            -- "hide for now": until the next quest is taken
local fighting
local shownSig
local spans = {}        -- rows that can be clicked, as laid: { top, bottom, id }
local markId            -- the name under the pointer in the list
local function Aside() return fighting and Cfg().fight == "aside" end

-- Words -------------------------------------------------------------------------------------------------------

local function Clean(s)
    return (tostring(s or ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- the sentences of a text, in order (the one splitter: AsToldLabels.lua, the labels count by it)
local Sentences = ns.ToldSentences

-- the story of a quest at rest: the sentences read as its story; for a quest nobody has read, how it began
local function StoryOf(id, q)
    local labelled, read = ns.ToldLabelled(id, q.text)
    if read then
        local s = ns.ToldPart(labelled, "S")
        -- (a stage direction whose closing ">" sits in a sentence not shown: the lone "<" goes)
        if s:find("<", 1, true) and not s:find(">", 1, true) then s = s:gsub("<", "") end
        if s ~= "" then return s end
    end
    return nil
end

-- the whole telling but for the chaff, in the giver's order; the ask and the way in the way's colour, and a new
-- line where the giver turns from telling to asking for good: before the last run of ask and way sentences. (A
-- way sentence in the middle of the telling gets no break: Cave Mushrooms names its cave in the second sentence,
-- and the line broke there, after one sentence, 2026-11-14.)
local function Telling(id, q)
    local kept = {}
    for _, e in ipairs((ns.ToldLabelled(id, q.text))) do
        if e[2] ~= "X" then kept[#kept + 1] = e end
    end
    local turn = #kept + 1
    while turn > 1 and (kept[turn - 1][2] == "A" or kept[turn - 1][2] == "W") do turn = turn - 1 end
    local out = {}
    for i, e in ipairs(kept) do
        local lead = (i == 1 and "") or (i == turn and "\n") or " "
        local ask = e[2] == "A" or e[2] == "W"
        out[#out + 1] = lead .. (ask and ("|cffd9cfb5" .. e[1] .. "|r") or e[1])
    end
    return table.concat(out)
end

-- how it began: the first sentences of the giver's words, up to about max letters
local function Began(q, max)
    local out, n = "", 0
    for _, s in ipairs(Sentences(q.text)) do
        if n > 0 and #out + #s > max then break end
        out = (n > 0 and (out .. " ") or "") .. s
        n = n + 1
        if n >= 2 then break end
    end
    return out
end

local function First(text)
    return Sentences(text)[1] or ""
end

-- What to say -------------------------------------------------------------------------------------------------
-- A list of rows: { text, size, colour, indent, gap, id, side, sideColour, maxLines }
-- (id: a row that can be clicked, a quest's id; side: a few words at the row's right, in sideColour)

local function Row(rows, text, size, colour, indent, gap, id, side, sideColour, maxLines)
    if text and text ~= "" then rows[#rows + 1] = { text, size, colour, indent or 0, gap or 0, id, side, sideColour, maxLines } end
end

local function From(q)
    local who, where = q.who, q.where
    if who and where then return who .. "  \194\183  " .. where end
    return who or where
end

-- every quest in the list's order: those that speak of where you stand, then the rest, the newest first
local function Order()
    local out, seen = {}, {}
    for _, it in ipairs(ns.ToldHere()) do out[#out + 1] = it seen[it.id] = true end
    local nHere = #out
    for _, it in ipairs(ns.ToldNow()) do
        if not seen[it.id] then out[#out + 1] = it end
    end
    return out, nHere
end
local function IndexOf(order, id)
    for i, it in ipairs(order) do
        if it.id == id then return i end
    end
end

-- the place a quest's giver named, in a few words (not the one you stand in)
local function Named(it, here)
    -- (only what the map would mark: a town to go back to, or a place only spoken of, is not where it sends you.
    -- The user, 2026-11-15, The Absent Minded Prospector: "It says ironforge... giver and objective is in
    -- darkshore": "At the academy in Ironforge everyone knew".)
    local what = ns.AsToldMarks(it.tellings, it.q.text, it.q.obj, it.id)
    for i, t in ipairs(it.tellings) do
        local name = t.place and t.place.name
        local says
        if not what[i] then
            -- (nothing on the map for it)
        elseif t.kind == "place" then says = name
        elseif t.kind == "dir" and t.dir then says = name and (t.dir .. " of " .. name) or ("to the " .. t.dir)
        elseif t.kind == "part" and t.dir and name then says = "the " .. t.dir .. " of " .. name end
        if says and says ~= here then return says end
    end
end

-- (the user, 2026-11-13: "Pointer on the panel shows details, clicking holds the details there... details
-- showing too when held. Being at the quest spot does not unfold details")
local function Detailed(it)
    return (hover or pinned or Cfg().hold == it.id or GetTime() < openUntil) and true or false
end

-- always: the name, the count, how it began
local function Main(rows, it, detailed)
    local q, id = it.q, it.id
    -- (its place among your quests, the newest first: not the list's order, which changes with where you stand)
    local order = ns.ToldNow()
    local nth = #order > 1 and IndexOf(order, id)
    Row(rows, (q.title or ""):upper(), 10, SOFT, 0, 0, nil, nth and (nth .. " of " .. #order), GOLD)
    -- (A story that was picked by reading is never cut: its length was set when it was picked, 200 letters,
    -- which is four or five lines here. The user, of a story cut at three lines: "its not mathching picked
    -- length either". Only the unread fallback is held, to five lines.)
    local text, cap
    if detailed then
        text = Telling(id, q)
    else
        text = StoryOf(id, q)
        if not text then text, cap = Began(q, 210), 5 end
    end
    if text == "" then text = First(q.obj) end
    Row(rows, text, 12, TEXT, 0, 3, nil, nil, nil, cap)
end

-- on demand, under the whole telling: what the game asks in its one line, who gave it, the chain
local function Details(rows, it)
    local q, id = it.q, it.id
    local asked
    if ns.ToldComplete(id) and q.who then
        asked = "Back to " .. q.who .. (q.where and (", at " .. q.where) or "") .. "."
    else
        asked = Clean(q.obj)
    end
    if asked ~= "" then
        Row(rows, "ASKED", 10, GOLD, 0, 8)
        Row(rows, asked, 12, ASK, 0, 3)
    end
    local before = ns.ToldBefore(id)
    if #before > 0 then
        Row(rows, "BEFORE THIS", 10, FAINT, 0, 8)
        for i = #before, 1, -1 do
            local b = ns.ToldQuest(before[i])
            if b then
                Row(rows, (b.title or ""):upper(), 10, SOFT, 0, 4)
                Row(rows, StoryOf(before[i], b) or First(b.text), 11, SOFT, 8, 2)
                if b.last then Row(rows, First(b.last), 11, SOFT, 8, 2) end
            end
        end
    end
    local from = From(q)
    local ahead, step = ns.ToldAhead(id)
    local chain = (step and step > 1 and ("STEP " .. step .. " OF A CHAIN")) or (ahead and ahead > 0 and "THE FIRST STEP OF A CHAIN") or nil
    if ahead and ahead > 0 then chain = chain .. "  \194\183  MORE TO COME" end
    local foot = from and from:upper() or nil
    if chain then foot = foot and (foot .. "\n" .. chain) or chain end
    Row(rows, foot, 10, FAINT, 0, 8)
end

-- the other quests, under the one that leads
local function List(rows, lead)
    local order, nHere = Order()
    local here = ns.ToldHereName()
    local first = true
    for i, it in ipairs(order) do
        if it.id ~= lead.id then
            if first then Row(rows, "YOUR OTHER QUESTS", 10, FAINT, 0, 9) end
            -- (done: that word in place of the place; the way is back to the one who asked)
            local done = ns.ToldComplete(it.id)
            local gap = first and 3 or ((nHere > 0 and i == nHere + 1) and 9 or 4)
            Row(rows, it.q.title or "", 12, TEXT, 0, gap, it.id, done and "done" or Named(it, here), FAINT)
            first = false
        end
    end
end

local function Rows()
    local rows = {}
    local it = ns.ToldLead and ns.ToldLead()
    if not it then return rows, "rest" end
    local detailed = Detailed(it)
    Main(rows, it, detailed)
    if detailed then Details(rows, it) end
    if listOpen then
        List(rows, it)
    else
        -- the other quests that share this ground: how many, in one quiet line (the user, 2026-11-13: "also here
        -- takes up so much space. 5 more quests here, or something in that muted grey is ok at the bottom")
        local also = 0
        for _, o in ipairs(ns.ToldHere()) do
            if o.id ~= it.id then also = also + 1 end
        end
        if also > 0 then Row(rows, also .. (also == 1 and " more quest here" or " more quests here"), 10, FAINT, 0, 6) end
    end
    return rows, (listOpen and "list") or (detailed and "open") or "rest"
end

-- The frame ---------------------------------------------------------------------------------------------------

local anim = {}   -- { fadeFrom, fadeTo, fadeT, hFrom, hTo, hT, after }
local function Animate(_, e)
    local busy = false
    if anim.fadeT then
        anim.fadeT = anim.fadeT + e
        local k = math.min(1, anim.fadeT / FADE)
        body:SetAlpha(anim.fadeFrom + (anim.fadeTo - anim.fadeFrom) * k)
        if k >= 1 then
            anim.fadeT = nil
            local nxt = anim.after
            anim.after = nil
            if nxt then nxt() end
        end
        busy = true
    end
    if anim.inT then
        anim.inT = anim.inT + e
        local k = math.min(1, anim.inT / SOFT_IN)
        for _, l in ipairs(lines) do
            if l.fresh and l:IsShown() then
                l:SetAlpha(k)
                if l.side then l.side:SetAlpha(k) end
            end
        end
        if k >= 1 then anim.inT = nil end
        busy = true
    end
    if anim.hT then
        anim.hT = anim.hT + e
        local k = math.min(1, anim.hT / (anim.hDur or GROW))
        k = k * k * (3 - 2 * k)
        panel:SetHeight(anim.hFrom + (anim.hTo - anim.hFrom) * k)
        if k >= 1 then anim.hT = nil end
        busy = true
    end
    if anim.aT then
        anim.aT = anim.aT + e
        local k = math.min(1, anim.aT / 0.5)
        panel:SetAlpha(anim.aFrom + (anim.aTo - anim.aFrom) * k)
        if k >= 1 then
            anim.aT = nil
            if anim.aTo <= 0 then panel:Hide() end
        end
        busy = true
    end
    if not busy then panel:SetScript("OnUpdate", nil) end
end
local function Run() panel:SetScript("OnUpdate", Animate) end

local function PanelAlpha(to)
    if to > 0 and not panel:IsShown() then
        panel:SetAlpha(0)
        panel:Show()
    end
    if math.abs(panel:GetAlpha() - to) < 0.01 then
        if to <= 0 then panel:Hide() end
        return
    end
    anim.aFrom, anim.aTo, anim.aT = panel:GetAlpha(), to, 0
    Run()
end

-- the mark behind the name under the pointer (no laying again: the pointer only moves this)
local function PlaceMark()
    if not mark then return end
    for _, sp in ipairs(spans) do
        if listOpen and markId and sp[3] == markId then
            mark:ClearAllPoints()
            mark:SetPoint("TOPLEFT", body, "TOPLEFT", PAD - 6, -(sp[1] - 2))
            mark:SetPoint("BOTTOMRIGHT", body, "TOPRIGHT", -(EDGE + PAD - 6), -(sp[2] + 2))
            mark:Show()
            return
        end
    end
    mark:Hide()
end

local function Lay(rows)
    local y = PAD
    spans = {}
    for i, r in ipairs(rows) do
        local l = lines[i]
        if not l then
            l = body:CreateFontString(nil, "ARTWORK")
            l:SetJustifyH("LEFT")
            l:SetWordWrap(true)
            lines[i] = l
        end
        y = y + r[5]
        local sideW = 0
        if r[7] then
            if not l.side then
                l.side = body:CreateFontString(nil, "ARTWORK")
                l.side:SetJustifyH("RIGHT")
            end
            local sc = r[8] or FAINT
            l.side:SetFont(FONT, 10, "")
            l.side:SetTextColor(sc[1], sc[2], sc[3])
            l.side:SetShadowColor(0, 0, 0, 0)
            l.side:SetShadowOffset(1, -1)
            l.side:SetText(r[7])
            l.side:ClearAllPoints()
            l.side:SetPoint("TOPRIGHT", body, "TOPRIGHT", -(EDGE + PAD), -(y + (r[2] > 10 and 2 or 0)))
            l.side:Show()
            sideW = (l.side:GetStringWidth() or 60) + 10
        elseif l.side then
            l.side:Hide()
        end
        l:SetFont(FONT, r[2], "")
        l:SetTextColor(r[3][1], r[3][2], r[3][3])
        l:SetShadowColor(0, 0, 0, 0)
        l:SetSpacing(r[2] >= 11 and 2 or 0)
        if l.SetMaxLines then l:SetMaxLines(r[9] or 0) end
        l:SetWidth(W - 2 * PAD - r[4] - sideW)
        -- (fresh: these words were not on this line a moment ago)
        l.fresh = not (l:IsShown() and l.txt == r[1])
        l.txt = r[1]
        l:SetAlpha(1)
        if l.side then l.side:SetAlpha(1) end
        l:SetText(r[1])
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", body, "TOPLEFT", PAD + r[4], -y)
        l:Show()
        local top = y
        y = y + (l:GetStringHeight() or r[2])
        if r[6] then spans[#spans + 1] = { top, y, r[6] } end
    end
    for i = #rows + 1, #lines do
        lines[i]:Hide()
        if lines[i].side then lines[i].side:Hide() end
    end
    PlaceMark()
    return y + PAD
end

local function Sig(rows)
    local t = {}
    for _, r in ipairs(rows) do t[#t + 1] = r[1] .. "\2" .. (r[7] or "") .. "\2" .. (r[9] or "") end
    return table.concat(t, "\1")
end

-- quick: the pointer did it, so the words that stay stand still and the new ones fade in softly; otherwise
-- all the words fade out, change, and fade in
local Build
local function Show(now, quick)
    if not panel then Build() end
    local c = Cfg()
    local rows = Rows()
    if not (c.on and c.panel ~= false) or hidden or #rows == 0 then
        shownSig = nil
        PanelAlpha(0)
        return
    end
    local sig = Sig(rows)
    if sig == shownSig and panel:IsShown() then
        if not Aside() then PanelAlpha(1) end
        return
    end
    local first = not shownSig or not panel:IsShown() or now
    shownSig = sig
    local function Swap()
        local h = Lay(rows)
        anim.inT = nil
        if first then
            panel:SetHeight(h)
        else
            anim.hFrom, anim.hTo, anim.hT, anim.hDur = panel:GetHeight(), h, 0, nil
        end
        anim.fadeFrom, anim.fadeTo, anim.fadeT = body:GetAlpha(), 1, 0
        Run()
    end
    if quick and not first then
        anim.fadeT, anim.after = nil, nil
        body:SetAlpha(1)
        local h = Lay(rows)
        for i = 1, #rows do
            local l = lines[i]
            if l.fresh then
                l:SetAlpha(0)
                if l.side then l.side:SetAlpha(0) end
            end
        end
        anim.inT = 0
        anim.hFrom, anim.hTo, anim.hT, anim.hDur = panel:GetHeight(), h, 0, SOFT_IN
        Run()
    elseif first then
        body:SetAlpha(0)
        Swap()
    else
        anim.fadeFrom, anim.fadeTo, anim.fadeT, anim.after = body:GetAlpha(), 0, 0, Swap
        Run()
    end
    PanelAlpha(Aside() and 0.06 or 1)
end

-- Choosing ----------------------------------------------------------------------------------------------------

-- the row under the pointer: its id
local function Under()
    if not (GetCursorPosition and panel and panel.GetEffectiveScale) then return end
    local x, y = GetCursorPosition()
    local s = panel:GetEffectiveScale()
    local top = panel:GetTop()
    if not (x and s and s > 0 and top) then return end
    local dy = top - y / s
    for _, sp in ipairs(spans) do
        if dy >= sp[1] - 2 and dy <= sp[2] + 2 then return sp[3] end
    end
end

local OpenFor
local function Pick(id, hold)
    if hold then ns.ToldSetLead(id, true, false) else ns.ToldSetLead(id) end
    listOpen, markId, pinned = nil, nil, nil
    -- (the list folds and the panel shrinks away from under the pointer: a name far down, a short quest. The
    -- quest you just picked keeps its details a few seconds all the same. The user, 2026-11-15: "panel escapes
    -- the mouse hover and goes to at rest on that quest".)
    OpenFor(NEXT_FOR)
    Show(nil, true)
end

local function OpenList()
    if listOpen or #Order() < 2 then return end
    listOpen = true
    hidden = nil
    Show(nil, true)
end

local function Enter()
    hover = true
    if watch then watch:Show() end
    Show(nil, true)
end
local function Leave()
    if not hover and not listOpen then return end
    hover, listOpen, markId = nil, nil, nil
    if watch then watch:Hide() end
    -- (a place entered while the pointer was here counts from now; the panel hears of it from there)
    if ns.ToldSettle and ns.ToldSettle() then return end
    Show(nil, true)
end
-- the pointer is on the panel: someone is reading it
function ns.ToldPanelBusy()
    return (hover and panel and panel:IsShown()) and true or false
end

OpenFor = function(seconds)
    openUntil = GetTime() + seconds
    if C_Timer and C_Timer.After then
        local mine = openUntil
        C_Timer.After(seconds + 0.1, function()
            if openUntil == mine then Show() end
        end)
    end
end

-- lead with the next quest (d = -1) or the one before (1), in the count's order: for a macro, a key, a gamepad
function ns.ToldPanelNext(d)
    local order = ns.ToldNow()
    local lead = ns.ToldLead()
    if #order < 2 or not lead then return end
    local at = IndexOf(order, lead.id) or 1
    ns.ToldSetLead(order[((at - 1 - (d or -1)) % #order) + 1].id)
    pinned, hidden = nil, nil
    OpenFor(NEXT_FOR)
    Show(nil, true)
end
function ns.ToldPanelList()
    if listOpen then
        listOpen, markId = nil, nil
        Show(nil, true)
    else
        OpenList()
    end
end
function ns.ToldPanelPick(id, hold) Pick(id, hold) end
-- (the pointer and the click, for the test outside the game)
function ns.ToldPanelHover(on) if on then Enter() else Leave() end end
function ns.ToldPanelPin()
    pinned = (not pinned) or nil
    Show(nil, true)
end

local function Menu()
    if not ns.QuillMenu or (InCombatLockdown and InCombatLockdown()) then return end
    local c = Cfg()
    local it = ns.ToldLead()
    local items = {}
    if it then
        if c.hold == it.id then
            items[#items + 1] = { "back to automatic", function() ns.ToldSetLead(nil, false) Show() end }
        else
            items[#items + 1] = { "hold this quest", function() ns.ToldSetLead(it.id, true, false) Show() end }
        end
        local ahead = ns.ToldAhead(it.id)
        if ahead and ahead > 0 and not (c.hold == it.id and c.holdChain) then
            items[#items + 1] = { "hold this chain", function() ns.ToldSetLead(it.id, true, true) Show() end }
        end
    end
    items[#items + 1] = { "hide for now", function() hidden = true Show() end }
    -- (moved by a drag: the way back to where it started)
    if c.panelAt then
        items[#items + 1] = { "reset position", function()
            c.panelAt = nil
            if ns.ToldPanelPlace then ns.ToldPanelPlace() end   -- (Place, below)
        end }
    end
    items[#items + 1] = { c.fight == "aside" and "stay visible in combat" or "fade out in combat", function()
        c.fight = c.fight ~= "aside" and "aside" or nil
    end }
    ns.QuillMenu(items)
end

-- Its size and its place. One size for all of it, letters, width and glass together (told.scale, 80 to 160, the
-- settings' "Panel size"; the user, 2026-11-15: "Some might want it bigger, some might need bigger letters to
-- read", and of one slider for both: "Yes, one slider"). Its top right corner stays where it was put (told.panelAt,
-- in the screen's measure), so it grows down and to the left.
local function Place()
    local s = math.max(0.8, math.min(1.6, (tonumber(Cfg().scale) or 100) / 100))
    panel:SetScale(s)
    panel:ClearAllPoints()
    local at = Cfg().panelAt
    if at then
        panel:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", at[1] / s, at[2] / s)
    else
        panel:SetPoint("TOPRIGHT", UIParent, "RIGHT", -40 / s, -40 / s)
    end
end
function ns.ToldPanelPlace() if panel then Place() end end

Build = function()
    panel = CreateFrame("Frame", "WaymarkToldPanel", UIParent)
    panel.bfiTag = "As told panel"
    -- (the user, 2026-11-13: "Extend shadow, letter sitting outside it to the right". The words are W wide; the
    -- glass is full under all of them and fades out over EDGE beyond.)
    panel:SetSize(W + EDGE, 60)
    panel:SetFrameStrata("LOW")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    -- (the game keeps a named, movable frame's place of its own once it has been dragged, and puts it back
    -- from its middle: the panel then grew up as well as down. The user, 2026-11-15. Its place is ours alone.)
    if panel.SetDontSavePosition then panel:SetDontSavePosition(true) end
    if panel.SetUserPlaced then pcall(panel.SetUserPlaced, panel, false) end
    Place()
    -- Dark glass, soft on every side but the top, where the gold rule is its edge (the user, 2026-11-15, of the
    -- hard left and bottom beside the faded right: "it looks abit unsymmetrical ... all sides fade, left and bot
    -- just a tiny bit? You consider and decide"). The right fades over EDGE as before; the left over 10 px and
    -- the bottom over 8, both OUTSIDE the panel's own box, so the words keep their margin; the rule fades out
    -- with the glass at both ends. The two lower corners are four thin rows each, so the two fades multiply
    -- instead of meeting in a seam. Where the client has no gradient call the glass keeps its hard edges.
    local GR, GG, GB, GA = 0.055, 0.06, 0.07, 0.78
    local SOFT_L, SOFT_B, ROWS = 10, 8, 4
    local parts = {}
    local function Piece(layer)
        local t = panel:CreateTexture(nil, layer or "BACKGROUND")
        t:SetColorTexture(1, 1, 1, 1)
        parts[#parts + 1] = t
        return t
    end
    -- (from a to b: left to right, or bottom to top)
    local function Grad(t, way, r, g, b, a, z)
        local ok
        if t.SetGradient and CreateColor then ok = pcall(t.SetGradient, t, way, CreateColor(r, g, b, a), CreateColor(r, g, b, z)) end
        if not ok and t.SetGradientAlpha then ok = pcall(t.SetGradientAlpha, t, way, r, g, b, a, r, g, b, z) end
        return ok
    end
    back = Piece()
    back:SetPoint("TOPLEFT")
    back:SetPoint("BOTTOMRIGHT", -EDGE, 0)
    back:SetColorTexture(GR, GG, GB, GA)
    back.parts = parts
    local edge = Piece()
    edge:SetPoint("TOPLEFT", back, "TOPRIGHT")
    edge:SetPoint("BOTTOMRIGHT")
    local soft = Grad(edge, "HORIZONTAL", GR, GG, GB, GA, 0)
    if not soft then edge:SetColorTexture(GR, GG, GB, GA) end
    rule = Piece("BORDER")
    rule:SetPoint("TOPLEFT")
    rule:SetPoint("TOPRIGHT", -EDGE, 0)
    rule:SetHeight(1)
    rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.95)
    if soft then
        local left = Piece()
        left:SetPoint("TOPRIGHT", panel, "TOPLEFT")
        left:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", -SOFT_L, 0)
        Grad(left, "HORIZONTAL", GR, GG, GB, 0, GA)
        local under = Piece()
        under:SetPoint("TOPLEFT", panel, "BOTTOMLEFT")
        under:SetPoint("TOPRIGHT", back, "BOTTOMRIGHT")
        under:SetHeight(SOFT_B)
        Grad(under, "VERTICAL", GR, GG, GB, 0, GA)
        local step = SOFT_B / ROWS
        for i = 0, ROWS - 1 do
            local a = GA * (1 - (i + 0.5) / ROWS)
            local l = Piece()
            l:SetSize(SOFT_L, step)
            l:SetPoint("TOPRIGHT", panel, "BOTTOMLEFT", 0, -i * step)
            Grad(l, "HORIZONTAL", GR, GG, GB, 0, a)
            local r = Piece()
            r:SetSize(EDGE, step)
            r:SetPoint("TOPLEFT", back, "BOTTOMRIGHT", 0, -i * step)
            Grad(r, "HORIZONTAL", GR, GG, GB, a, 0)
        end
        local ruleL = Piece("BORDER")
        ruleL:SetSize(SOFT_L, 1)
        ruleL:SetPoint("TOPRIGHT", panel, "TOPLEFT")
        Grad(ruleL, "HORIZONTAL", GOLD[1], GOLD[2], GOLD[3], 0, 0.95)
        local ruleR = Piece("BORDER")
        ruleR:SetSize(EDGE, 1)
        ruleR:SetPoint("TOPLEFT", rule, "TOPRIGHT")
        Grad(ruleR, "HORIZONTAL", GOLD[1], GOLD[2], GOLD[3], 0.95, 0)
    end
    body = CreateFrame("Frame", nil, panel)
    body:SetAllPoints()
    mark = body:CreateTexture(nil, "BACKGROUND")
    mark:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.16)
    mark:Hide()

    -- while the pointer is on the panel: which name it is over, and a second look that it has not left
    -- (the panel changes size under the pointer, and a leave can go unsaid). Twenty times a second, only then.
    watch = CreateFrame("Frame", nil, panel)
    watch:Hide()
    local since = 0
    watch:SetScript("OnUpdate", function(_, e)
        since = since + e
        if since < 0.05 then return end
        since = 0
        if panel.IsMouseOver and not panel:IsMouseOver() then Leave() return end
        if listOpen then
            local id = Under()
            if type(id) ~= "number" then id = nil end
            if id ~= markId then
                markId = id
                PlaceMark()
            end
        end
    end)

    -- A plain drag moves it (2026-11-15): it was Ctrl and drag, which nothing on the panel says, and the panel
    -- is on from the first login ("How do players know how to move the astold", the user on a clean install).
    -- The button held and the pointer moved a few pixels: a drag, and the click that would have opened or
    -- folded it does nothing. Ctrl and drag still moves it at once.
    local moving
    local grab = CreateFrame("Frame", nil, panel)
    grab:Hide()
    grab:SetScript("OnUpdate", function(self)
        if moving or not (IsMouseButtonDown and IsMouseButtonDown("LeftButton")) then self:Hide() return end
        local x, y = GetCursorPosition()
        if math.abs(x - self.x) + math.abs(y - self.y) > 8 then
            self:Hide()
            if InCombatLockdown and InCombatLockdown() then return end
            moving = true
            panel:StartMoving()
        end
    end)
    panel:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or (InCombatLockdown and InCombatLockdown()) then return end
        if IsControlKeyDown and IsControlKeyDown() then
            moving = true
            self:StartMoving()
            return
        end
        grab.x, grab.y = GetCursorPosition()
        grab:Show()
    end)
    panel:SetScript("OnMouseUp", function(self, button)
        grab:Hide()
        if moving then
            moving = nil
            self:StopMovingOrSizing()
            -- (kept by its top right corner, so it grows downward from where it was put)
            local r, t = self:GetRight(), self:GetTop()
            if r and t then
                -- (its own measure is the screen's divided by its size: kept in the screen's)
                local s = self:GetScale() or 1
                Cfg().panelAt = { r * s, t * s }
                if self.SetUserPlaced then pcall(self.SetUserPlaced, self, false) end
                Place()
            end
            return
        end
        local under = Under()
        if button == "RightButton" then
            -- (on a name in the list: hold that quest until it is handed in)
            if listOpen and type(under) == "number" then Pick(under, true) else Menu() end
            return
        end
        if button ~= "LeftButton" then return end
        local it = ns.ToldLead()
        if not it then return end
        if IsShiftKeyDown and IsShiftKeyDown() then
            local link = GetQuestLink and GetQuestLink(it.id)
            if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
            return
        end
        if listOpen then
            -- (a name: that quest; anywhere else: the list folds, nothing changed)
            if type(under) == "number" then
                Pick(under)
            else
                listOpen, markId = nil, nil
                Show(nil, true)
            end
            return
        end
        -- (on the quest itself: its details stay open after the pointer leaves, or fold again)
        pinned = (not pinned) or nil
        Show(nil, true)
    end)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function() OpenList() end)
    panel:SetScript("OnEnter", function()
        Enter()
        -- (the panel has no tooltip of its own: its hints were written into whichever tooltip stood open, "(Hold
        -- Shift)" on a player's. The user, 2026-11-15. Its controls are on the settings page.)
    end)
    panel:SetScript("OnLeave", function()
        Leave()
    end)
    panel:Hide()
end

-- What happened (from AsTold.lua) -----------------------------------------------------------------------------

function ns.ToldPanelEvent(kind, id, leadChanged)
    if not WaymarkDB then return end
    if kind == "fight" then
        fighting = true
        if listOpen then
            listOpen, markId = nil, nil
            Show(nil, true)
        end
        if panel and panel:IsShown() and Aside() then PanelAlpha(0.06) end
        return
    elseif kind == "calm" then
        fighting = nil
        Show()
        return
    end
    -- (a click keeps one quest's details open: another quest leading lets go of it)
    if leadChanged then pinned = nil end
    if kind == "taken" then
        hidden = nil
        pinned = nil
        OpenFor(OPEN_FOR)
    end
    -- (the same quest leads: what changed is small, a count or the "more quests here" line. The words that stay
    -- stand still.)
    Show(nil, not leadChanged)
end

function ns.ToldPanelToggle()
    local c = Cfg()
    if hidden then
        hidden = nil
    else
        c.panel = not (c.panel ~= false)
    end
    Show()
    -- (with no quest to show the panel stays unseen: say so, and no more than we know)
    local empty = (c.panel ~= false) and not (ns.ToldLead and ns.ToldLead())
    print("|cffc8a86eWaymark|r: " .. (empty and "The As told panel is on. It shows when you have a quest with directions."
          or (c.panel ~= false) and "The As told panel is shown." or "The As told panel is hidden."))
end

-- /told story: the details, kept open (the chain's earlier steps are in them)
function ns.ToldPanelStory()
    pinned = true
    hidden = nil
    Show()
end

-- (for the test outside the game: what the panel reads now, and "rest", "open" or "list")
function ns.ToldPanelLines()
    local out, sides = {}, {}
    local rows, mode = Rows()
    for _, r in ipairs(rows) do out[#out + 1] = r[1] sides[#sides + 1] = r[7] or "" end
    return out, mode, sides
end
